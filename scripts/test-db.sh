#!/usr/bin/env bash
set -euo pipefail
# No recibe URLs, credenciales ni banderas de destino remoto.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$repo_root/tests/deploy-workflow.sh"
command -v docker >/dev/null
command -v npx >/dev/null
docker info >/dev/null
work_dir="$(mktemp -d -t toldo-tests.XXXXXXXX)"
cli() { npx --yes supabase@2.122.0 --workdir "$work_dir" "$@"; }
cleanup() {
  result=$?
  if [ "$result" -ne 0 ]; then
    docker logs --tail 80 supabase_db_toldo_tests 2>/dev/null || true
  fi
  cli stop --no-backup >/dev/null 2>&1 || true
  # El temporal solo contiene los archivos creados por esta ejecución.
  case "$(realpath -- "$work_dir")" in
    /tmp/toldo-tests.*) rm -rf -- "$work_dir" ;;
    *) echo "No se eliminó un temporal fuera de /tmp/toldo-tests.*" >&2 ;;
  esac
  exit "$result"
}
# Una segunda ejecución no debe borrar una base que ya está en uso.
if docker container inspect supabase_db_toldo_tests >/dev/null 2>&1; then
  echo 'Ya existe supabase_db_toldo_tests. Detén esa ejecución antes de continuar.' >&2
  exit 1
fi
trap cleanup EXIT
mkdir -p "$work_dir/supabase/.temp"
printf '%s' '17.11.0.003' > "$work_dir/supabase/.temp/postgres-version"
printf '%s' 'v1.80.2' > "$work_dir/supabase/.temp/storage-version"
printf '%s' 'v2.197.0' > "$work_dir/supabase/.temp/gotrue-version"
cp "$repo_root/supabase/config.toml" "$work_dir/supabase/config.toml"
sed -i 's/^project_id = .*/project_id = "toldo_tests"/; s/54322/55432/g; s/54320/55430/g' "$work_dir/supabase/config.toml"
cp -R "$repo_root/supabase/migrations" "$work_dir/supabase/migrations"
# Primero restaurar el estado previo para probar la actualización con datos.
er_migration=20261026010000_align_er.sql
mv "$work_dir/supabase/migrations/$er_migration" "$work_dir/$er_migration"
cp "$repo_root/supabase/seed.sql" "$work_dir/supabase/seed.sql"
echo 'Creando base de pruebas local desde cero...'
cli db start
echo 'Probando migración ER con datos previos (ROLLBACK al terminar)...'
{
  cat "$repo_root/tests/upgrade/er_before.sql"
  cat "$work_dir/$er_migration"
  cat "$repo_root/tests/upgrade/er_after.sql"
} | docker exec -i supabase_db_toldo_tests psql -X -U postgres -d postgres -v ON_ERROR_STOP=1
mv "$work_dir/$er_migration" "$work_dir/supabase/migrations/$er_migration"
cli migration up --local
# Cada ejecución crea un contenedor y volumen nuevos, sin vínculo remoto.
for test_file in "$repo_root"/tests/*.sql; do
  echo "Ejecutando $(basename "$test_file")..."
  docker exec -i supabase_db_toldo_tests psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_file"
done
echo 'Verificando la estructura que comprobará el despliegue...'
docker exec -i supabase_db_toldo_tests psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$repo_root/scripts/verify-er.sql"
echo 'Restauración, datos de ejemplo y pruebas SQL: correctos.'
