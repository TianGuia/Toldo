#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# También se valida al invocar el script fuera de Actions, antes de cualquier npx.
bash scripts/validate-supabase-env.sh
deploy_mode="${1:-preview}"
project_ref="${2:-${SUPABASE_PROJECT_REF:-}}"
if [[ "$deploy_mode" != preview && "$deploy_mode" != apply ]]; then
  echo 'Modo inválido: usa preview o apply.' >&2
  exit 1
fi
if [[ ! "$project_ref" =~ ^[a-z]{20}$ ]]; then
  echo 'El identificador del proyecto debe contener exactamente 20 letras minúsculas.' >&2
  exit 1
fi
cli() {
  bash scripts/validate-supabase-env.sh
  npx --yes supabase@2.122.0 "$@"
}

cli link --project-ref "$project_ref" --yes
cli migration list --linked

# La consulta solo lee contadores. Un resultado vacío o inesperado también falla.
preflight_result="$(cli db query --linked --file scripts/preflight-er.sql --output json)"
PREFLIGHT_RESULT="$preflight_result" node <<'JS'
const data = JSON.parse(process.env.PREFLIGHT_RESULT);
const expected = new Set([
  'productos_sin_puesto_ambiguos', 'productos_en_puesto_ajeno',
  'ofertas_sin_productos', 'ofertas_con_productos_ajenos',
]);
if (!Array.isArray(data.rows) || data.rows.length !== expected.size) {
  throw new Error('Respuesta inesperada del preflight; no se ejecutará db push.');
}
for (const row of data.rows) {
  const count = Number(row.pendientes);
  if (!expected.delete(row.condicion) || row.pendientes == null ||
      !Number.isSafeInteger(count) || count < 0) {
    throw new Error('Contador inválido del preflight; no se ejecutará db push.');
  }
  if (count !== 0) throw new Error(`Preflight bloqueado: ${row.condicion} (${count}).`);
}
console.log('Preflight ER correcto: los cuatro contadores están en cero.');
JS

# No reparar automáticamente el historial: preparar la línea base según la guía.
cli db push --linked --include-all --dry-run
if [[ "$deploy_mode" == apply ]]; then
  cli db push --linked --include-all --yes
  cli migration list --linked
  cli db query --linked --file scripts/verify-er.sql
else
  echo 'Vista previa completada; no se aplicaron migraciones.'
fi
