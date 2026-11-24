-- Prueba local con credenciales y documentos sintéticos.
BEGIN;

DO $$
DECLARE relation_name text; client_role text;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY['admin_bitacora','admin_credencial','admin_intentos','admin_sesiones'] LOOP
    FOREACH client_role IN ARRAY ARRAY['anon','authenticated'] LOOP
      IF has_table_privilege(client_role, format('public.%I', relation_name), 'SELECT,INSERT,UPDATE,DELETE') THEN
        RAISE EXCEPTION 'El rol % tiene acceso directo a %', client_role, relation_name;
      END IF;
    END LOOP;
  END LOOP;
  IF has_function_privilege('anon', 'public.admin_entrar(text,text,text)', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.admin_configurar_credenciales(text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'El cliente puede usar funciones administrativas reservadas';
  END IF;
END $$;

INSERT INTO auth.users (id, is_anonymous) VALUES ('16000000-0000-0000-0000-000000000001', true);
SELECT public.admin_configurar_credenciales('operador de prueba', 'clave-local-1', 'respuesta local');
INSERT INTO public.versiones_documento (tipo, version, contenido, vigente)
VALUES ('terminos', 'anterior-prueba', 'Texto anterior', false),
       ('terminos', 'vigente-prueba', 'Texto vigente', true);

SET LOCAL ROLE anon;
DO $$ BEGIN
  IF (SELECT version FROM public.documento_vigente('terminos')) IS DISTINCT FROM 'vigente-prueba' THEN
    RAISE EXCEPTION 'El cliente sin sesión no recibe la versión vigente';
  END IF;
END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '16000000-0000-0000-0000-000000000001', true);
DO $$ BEGIN
  IF public.es_admin() THEN
    RAISE EXCEPTION 'La cuenta tiene permisos administrativos antes de entrar al panel';
  END IF;
  IF NOT public.admin_entrar('operador de prueba', 'clave-local-1', 'respuesta local') THEN
    RAISE EXCEPTION 'No se pudo iniciar la sesión administrativa';
  END IF;
  IF NOT public.es_admin() OR jsonb_typeof(public.admin_resumen()) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'La sesión administrativa no habilitó el panel';
  END IF;
  PERFORM public.admin_salir();
  IF public.es_admin() THEN
    RAISE EXCEPTION 'La cuenta conserva permisos administrativos después de salir';
  END IF;
END $$;
RESET ROLE;

ROLLBACK;
