-- Se ejecuta sobre la linea base, antes de cualquier mejora.
BEGIN;
DO $$ BEGIN
  IF (SELECT count(*) FROM pg_tables WHERE schemaname='public') <> 39 THEN
    RAISE EXCEPTION 'La linea base no reproduce las 39 tablas remotas';
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname='public') <> 86 THEN
    RAISE EXCEPTION 'La linea base no reproduce las 86 politicas remotas';
  END IF;
  IF NOT has_table_privilege('authenticated','public.productos','TRUNCATE') THEN
    RAISE EXCEPTION 'Se incorporo la reduccion de permisos antes de su migracion';
  END IF;
  IF has_column_privilege('authenticated','public.usuarios','estado_cuenta','UPDATE') THEN
    RAISE EXCEPTION 'La restauracion amplio los permisos reservados de usuarios';
  END IF;
  IF has_function_privilege('anon','public.vencer_pendientes()','EXECUTE') THEN
    RAISE EXCEPTION 'La restauracion amplio el permiso de vencer_pendientes';
  END IF;
  IF (SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public' AND t.typtype='e') <> 19 THEN
    RAISE EXCEPTION 'La linea base no reproduce los 19 enums';
  END IF;
  IF to_regclass('public.compradores') IS NOT NULL OR to_regclass('public.participantes') IS NOT NULL THEN
    RAISE EXCEPTION 'La linea base incorpora anticipadamente la mejora ER';
  END IF;
  IF to_regclass('public.usuarios_nombre_publico_unico') IS NULL
    OR to_regprocedure('public.nombre_disponible(text)') IS NULL THEN
    RAISE EXCEPTION 'Se perdieron las mejoras remotas de nombres unicos';
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname='storage') <> 4 THEN
    RAISE EXCEPTION 'Faltan las politicas Storage capturadas';
  END IF;
  IF (SELECT count(*) FROM storage.buckets WHERE id IN ('productos','perfiles') AND public) <> 2 THEN
    RAISE EXCEPTION 'Falta la configuracion de los buckets';
  END IF;
  IF (SELECT count(*) FROM pg_publication_tables
      WHERE pubname='supabase_realtime' AND schemaname='public') <> 5 THEN
    RAISE EXCEPTION 'Faltan tablas de Realtime';
  END IF;
END $$;
INSERT INTO auth.users (id, email, raw_user_meta_data, is_anonymous) VALUES
 ('16000000-0000-0000-0000-000000000001','baseline-a@example.test','{"nombre_publico":"Nombre repetido"}',false),
 ('16000000-0000-0000-0000-000000000002','baseline-b@example.test','{"nombre_publico":"Nombre repetido"}',false);
DO $$ BEGIN
  IF (SELECT count(*) FROM public.usuarios) <> 2 OR
     (SELECT count(*) FROM public.preferencias_notificacion) <> 2 THEN
    RAISE EXCEPTION 'No se restauraron las integraciones de alta de Auth';
  END IF;
  IF (SELECT nombre_publico FROM public.usuarios WHERE id='16000000-0000-0000-0000-000000000002') <> 'Nombre repetido-16000000' THEN
    RAISE EXCEPTION 'handle_new_user no conserva la resolucion remota de nombres repetidos';
  END IF;
  IF public.nombre_disponible('NOMBRE REPETIDO') THEN
    RAISE EXCEPTION 'nombre_disponible ignora el nombre registrado';
  END IF;
END $$;
UPDATE auth.users SET email='baseline-nuevo@example.test'
 WHERE id='16000000-0000-0000-0000-000000000001';
DO $$ BEGIN
  IF (SELECT correo FROM public.usuarios WHERE id='16000000-0000-0000-0000-000000000001') <> 'baseline-nuevo@example.test' THEN
    RAISE EXCEPTION 'No se restauro el trigger de sincronizacion de contacto';
  END IF;
END $$;
ROLLBACK;
