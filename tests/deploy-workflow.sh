#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
test_dir="$(mktemp -d -t toldo-deploy-test.XXXXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
export NPX_CALLS_FILE="$test_dir/calls"
export STUB_PREFLIGHT_FILE="$test_dir/preflight.json"
export PATH="$test_dir:$PATH"
cat > "$test_dir/npx" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$NPX_CALLS_FILE"
if [[ " $* " == *' scripts/preflight-er.sql '* ]]; then
  cat "$STUB_PREFLIGHT_FILE"
elif [[ " $* " == *' --dry-run '* && "${STUB_DRY_RUN_FAIL:-0}" == 1 ]]; then
  exit 1
fi
SH
chmod +x "$test_dir/npx"
cat > "$STUB_PREFLIGHT_FILE" <<'JSON'
{"rows":[
 {"condicion":"productos_sin_puesto_ambiguos","pendientes":0},
 {"condicion":"productos_en_puesto_ajeno","pendientes":0},
 {"condicion":"ofertas_sin_productos","pendientes":0},
 {"condicion":"ofertas_con_productos_ajenos","pendientes":0}
]}
JSON
cp "$STUB_PREFLIGHT_FILE" "$test_dir/good.json"

expect_no_npx() {
  : > "$NPX_CALLS_FILE"
  if "$@" > "$test_dir/output" 2>&1; then
    echo 'La validación aceptó secretos ausentes o vacíos.' >&2
    exit 1
  fi
  if [[ -s "$NPX_CALLS_FILE" ]]; then
    echo 'Se llamó npx con secretos inválidos.' >&2
    exit 1
  fi
}
expect_no_npx env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_PASSWORD bash scripts/deploy-supabase.sh
expect_no_npx env SUPABASE_ACCESS_TOKEN='' SUPABASE_DB_PASSWORD=test bash scripts/deploy-supabase.sh
expect_no_npx env SUPABASE_ACCESS_TOKEN=test SUPABASE_DB_PASSWORD='' bash scripts/deploy-supabase.sh
expect_no_npx env SUPABASE_ACCESS_TOKEN=$' \t\n' SUPABASE_DB_PASSWORD=test bash scripts/deploy-supabase.sh
expect_no_npx env SUPABASE_ACCESS_TOKEN=test SUPABASE_DB_PASSWORD=$' \t\n' bash scripts/deploy-supabase.sh

export SUPABASE_ACCESS_TOKEN=test-token SUPABASE_DB_PASSWORD=test-password
export SUPABASE_PROJECT_REF=ijnvztoyhizdwtzagrvy
: > "$NPX_CALLS_FILE"
bash scripts/deploy-supabase.sh preview > "$test_dir/output" 2>&1
grep -Fq -- 'db push --linked --include-all --dry-run' "$NPX_CALLS_FILE"
if grep -Fq -- 'db push --linked --include-all --yes' "$NPX_CALLS_FILE"; then
  echo 'El modo preview aplicó migraciones.' >&2
  exit 1
fi
: > "$NPX_CALLS_FILE"
bash scripts/deploy-supabase.sh apply > "$test_dir/output" 2>&1
grep -Fq -- 'db push --linked --include-all --yes' "$NPX_CALLS_FILE"
grep -Fq -- 'db query --linked --file scripts/verify-er.sql' "$NPX_CALLS_FILE"

# Los datos incompatibles o una respuesta vacía deben detener incluso el plan.
for response in '{"rows":[]}' '{"rows":[{"condicion":"desconocida","pendientes":0}]}'; do
  printf '%s\n' "$response" > "$STUB_PREFLIGHT_FILE"
  : > "$NPX_CALLS_FILE"
  if bash scripts/deploy-supabase.sh apply > "$test_dir/output" 2>&1; then
    echo 'Se aceptó un preflight inválido.' >&2
    exit 1
  fi
  if grep -Fq -- 'db push' "$NPX_CALLS_FILE"; then exit 1; fi
done
sed 's/"pendientes":0/"pendientes":1/g' "$test_dir/good.json" > "$STUB_PREFLIGHT_FILE"
: > "$NPX_CALLS_FILE"
if bash scripts/deploy-supabase.sh apply > "$test_dir/output" 2>&1; then exit 1; fi
if grep -Fq -- 'db push' "$NPX_CALLS_FILE"; then exit 1; fi

cp "$test_dir/good.json" "$STUB_PREFLIGHT_FILE"
: > "$NPX_CALLS_FILE"
if STUB_DRY_RUN_FAIL=1 bash scripts/deploy-supabase.sh apply > "$test_dir/output" 2>&1; then exit 1; fi
if grep -Fq -- 'db push --linked --include-all --yes' "$NPX_CALLS_FILE"; then exit 1; fi
echo 'Dispatch: secretos, preview, aplicación y fallos previos comprobados sin acceso remoto.'
