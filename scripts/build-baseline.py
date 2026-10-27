"""Assemble a schema baseline from CLI pg_dump output and catalog metadata.

Only Python's standard library is used. No production user rows are accepted.
Usage: python3 scripts/build-baseline.py PUBLIC_SQL METADATA_JSON OUTPUT_SQL
"""
import hashlib
import json
from pathlib import Path
import re
import sys


def identifier(value):
    return '"' + value.replace('"', '""') + '"'


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def assemble(public_sql, metadata):
    if not re.search(r'CREATE (?:OR REPLACE )?FUNCTION', public_sql):
        raise ValueError('Empty or incomplete public schema export')
    if re.search(r'^\s*(?:INSERT INTO|COPY) ', public_sql, re.MULTILINE):
        raise ValueError('The public export must be schema-only')
    public_sql = public_sql.replace('\r\n', '\n').strip() + '\n'
    lines = [
        '-- Baseline of the existing Tianguia project, captured with Supabase CLI 2.122.0.',
        '-- public is schema-only; managed schemas are provided by the Supabase platform.',
        '-- Custom Auth triggers, Storage configuration/policies and Realtime follow the dump.',
        '-- No user rows, credentials, bucket objects or internal migration records.',
        '-- See docs/baseline-20261027.md for provenance and adoption procedure.',
        '-- public SHA256: ' + hashlib.sha256(public_sql.encode()).hexdigest(),
        '',
    ]
    for ext in metadata['extensions']:
        if ext['schema'] != 'pg_catalog':
            lines.append(f'CREATE SCHEMA IF NOT EXISTS {identifier(ext["schema"])};')
        lines.append(f'CREATE EXTENSION IF NOT EXISTS {identifier(ext["name"])} '
                     f'WITH SCHEMA {identifier(ext["schema"])};')
    # pg_dump grants are additive. Clear grants inherited from the target's
    # default privileges before restoring the captured ACL, as the previous
    # initial migration already did. This reproduces remote permissions.
    acl_marker = 'GRANT USAGE ON SCHEMA "public" TO "postgres";'
    if acl_marker not in public_sql:
        raise ValueError('Expected public ACL section not found')
    restored = public_sql.replace(acl_marker,
        '-- Remove target default grants before replaying the source ACL.\n'
        'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated, PUBLIC;\n'
        'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon, authenticated;\n' + acl_marker, 1)
    lines.extend(['', restored, 'SET search_path = public, extensions;',
                  '', '-- Existing application triggers on platform-managed tables.'])
    for trigger in metadata['managed_triggers']:
        sql = trigger['sql'].replace('CREATE TRIGGER ', 'CREATE OR REPLACE TRIGGER ', 1)
        sql = re.sub(r'EXECUTE FUNCTION (?!public\.)(\w+)\(', r'EXECUTE FUNCTION public.\1(', sql)
        lines.append(sql.rstrip(';') + ';')
        if trigger['enabled'] != 'O':
            raise ValueError('Unsupported trigger enabled mode; review before generating')
    lines.extend(['', '-- Bucket configuration only, never storage.objects rows.'])
    for bucket in metadata['storage_buckets']:
        limit = 'NULL' if bucket['file_size_limit'] is None else str(int(bucket['file_size_limit']))
        mime = 'NULL' if bucket['allowed_mime_types'] is None else (
            'ARRAY[' + ','.join(literal(v) for v in bucket['allowed_mime_types']) + ']::text[]')
        lines.append('INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) '
                     f'VALUES ({literal(bucket["id"])}, {literal(bucket["name"])}, '
                     f'{str(bucket["public"]).lower()}, {limit}, {mime}) '
                     'ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, public=EXCLUDED.public, '
                     'file_size_limit=EXCLUDED.file_size_limit, allowed_mime_types=EXCLUDED.allowed_mime_types;')
    for policy in metadata['storage_policies']:
        roles = ', '.join('PUBLIC' if r == 'public' else identifier(r) for r in policy['roles'])
        sql = (f'CREATE POLICY {identifier(policy["name"])} ON '
               f'{identifier(policy["schema"])}.{identifier(policy["table"])} '
               f'AS {policy["permissive"]} FOR {policy["command"]} TO {roles}')
        if policy['using'] is not None:
            sql += ' USING (' + policy['using'] + ')'
        if policy['check'] is not None:
            sql += ' WITH CHECK (' + policy['check'] + ')'
        lines.append(sql + ';')
    lines.extend(['', '-- Only application tables; platform Realtime partitions are not copied.',
                  'DO $baseline_publication$ BEGIN',
                  "  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN",
                  '    CREATE PUBLICATION supabase_realtime;', '  END IF;',
                  'END $baseline_publication$;'])
    for pub in metadata['application_publications']:
        lines.append(f'ALTER PUBLICATION {identifier(pub["publication"])} ADD TABLE ONLY '
                     f'{identifier(pub["schema"])}.{identifier(pub["table"])};')
    lines.extend(['', '-- Existing application schedule; never export cron execution logs.'])
    for job in metadata.get('cron_jobs', []):
        if not re.fullmatch(r'\s*select\s+(?:public\.)?\w+\(\)\s*;?\s*', job['command'], re.I):
            raise ValueError('Review nontrivial cron commands for secrets before versioning')
        lines.append(f'SELECT cron.schedule({literal(job["jobname"])}, '
                     f'{literal(job["schedule"])}, {literal(job["command"])});')
        if not job['active']:
            lines.append(f"UPDATE cron.job SET active=false WHERE jobname={literal(job['jobname'])};")
    lines.append('')
    return '\n'.join(lines)


if __name__ == '__main__':
    source, meta, output = map(Path, sys.argv[1:])
    data = json.loads(meta.read_text(encoding='utf-8-sig'))
    if isinstance(data, dict) and 'rows' in data:
        data = data['rows'][0]['baseline_metadata']
    output.write_bytes(assemble(source.read_text(encoding='utf-8-sig'), data).encode())
