-- Solo metadatos/configuracion de la aplicacion; nunca filas de usuarios.
-- Una sentencia para supabase db query --linked --file scripts/inspect-baseline.sql.
SELECT json_build_object(
  'database', current_database(),
  'cli_history_table', to_regclass('supabase_migrations.schema_migrations')::text,
  'migration_tables', COALESCE((
    SELECT json_agg(json_build_object('schema', table_schema, 'table', table_name)
      ORDER BY table_schema, table_name)
    FROM information_schema.tables WHERE table_name ILIKE '%migration%'
      AND table_schema NOT IN ('pg_catalog', 'information_schema')
  ), '[]'::json),
  'extensions', (
    SELECT json_agg(json_build_object('name', extname, 'schema', nspname, 'version', extversion)
      ORDER BY extname)
    FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
  ),
  'counts', json_build_object(
    'tables', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relkind IN ('r','p')),
    'functions', (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND NOT EXISTS (
        SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')),
    'triggers', (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal),
    'policies', (SELECT count(*) FROM pg_policies WHERE schemaname='public'),
    'enums', (SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public' AND t.typtype='e'),
    'views', (SELECT count(*) FROM pg_views WHERE schemaname='public')
  ),
  'managed_triggers', COALESCE((
    SELECT json_agg(json_build_object('schema', n.nspname, 'table', c.relname,
      'name', t.tgname, 'enabled', t.tgenabled, 'sql', pg_get_triggerdef(t.oid, false))
      ORDER BY n.nspname, c.relname, t.tgname)
    FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid
    JOIN pg_namespace pn ON pn.oid=p.pronamespace
    WHERE NOT t.tgisinternal AND n.nspname <> 'public' AND pn.nspname='public'
  ), '[]'::json),
  'storage_policies', COALESCE((
    SELECT json_agg(json_build_object('schema', schemaname, 'table', tablename,
      'name', policyname, 'permissive', permissive, 'roles', roles,
      'command', cmd, 'using', qual, 'check', with_check)
      ORDER BY schemaname, tablename, policyname)
    FROM pg_policies WHERE schemaname='storage'
  ), '[]'::json),
  'storage_buckets', COALESCE((
    SELECT json_agg(json_build_object('id', id, 'name', name, 'public', public,
      'file_size_limit', file_size_limit, 'allowed_mime_types', allowed_mime_types) ORDER BY id)
    FROM storage.buckets
  ), '[]'::json),
  'cron_jobs', COALESCE((
    SELECT json_agg(json_build_object('jobname', jobname, 'schedule', schedule,
      'active', active, 'command', command) ORDER BY jobname)
    FROM cron.job WHERE database=current_database()
  ), '[]'::json),
  'application_publications', COALESCE((
    SELECT json_agg(json_build_object('publication', pubname, 'schema', schemaname, 'table', tablename)
      ORDER BY pubname, schemaname, tablename)
    FROM pg_publication_tables WHERE schemaname='public'
  ), '[]'::json)
) AS baseline_metadata;
