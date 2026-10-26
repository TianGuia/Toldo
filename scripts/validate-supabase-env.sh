#!/usr/bin/env bash
set -euo pipefail

# No imprimir valores: los errores identifican únicamente los nombres ausentes.
missing=0
for secret_name in SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD; do
  secret_value="${!secret_name-}"
  if [[ -z "$secret_value" || "$secret_value" =~ ^[[:space:]]*$ ]]; then
    printf '::error::Falta el secreto %s o su valor está vacío.\n' "$secret_name" >&2
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  exit 1
fi
