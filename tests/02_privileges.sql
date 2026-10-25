BEGIN;
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (
      SELECT 1 FROM pg_tables t WHERE schemaname = 'public'
      AND (has_table_privilege(r, format('%I.%I', schemaname, tablename), 'TRUNCATE')
        OR has_table_privilege(r, format('%I.%I', schemaname, tablename), 'TRIGGER'))
    ) THEN
      RAISE EXCEPTION 'El rol % conserva privilegios administrativos sobre tablas', r;
    END IF;
  END LOOP;
END $$;
ROLLBACK;
