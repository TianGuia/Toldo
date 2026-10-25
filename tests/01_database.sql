-- Cualquier error detiene psql. Los datos de cada prueba se revierten.
BEGIN;
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_tables WHERE schemaname = 'public') <> 38 THEN
    RAISE EXCEPTION 'No se restauraron las 38 tablas esperadas';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND NOT rowsecurity) THEN
    RAISE EXCEPTION 'Hay tablas públicas sin RLS';
  END IF;
  IF (SELECT count(*) FROM public.categorias WHERE nombre IN ('Ropa','Comida','Coleccionables')) <> 3 THEN
    RAISE EXCEPTION 'No se aplicaron los datos de ejemplo';
  END IF;
END $$;

-- Cuentas completamente sintéticas, sin invocar servicios remotos.
INSERT INTO auth.users (id, email, raw_user_meta_data, is_anonymous)
VALUES ('10000000-0000-0000-0000-000000000001','a@example.test','{"nombre_publico":"Vendedor A"}',false),
       ('10000000-0000-0000-0000-000000000002','b@example.test','{"nombre_publico":"Vendedor B"}',false);
INSERT INTO public.usuarios (id,nombre_publico,correo)
VALUES ('10000000-0000-0000-0000-000000000001','Vendedor A','a@example.test'),
       ('10000000-0000-0000-0000-000000000002','Vendedor B','b@example.test')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.perfiles_vendedor (id,id_usuario)
VALUES ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001'),
       ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002');
INSERT INTO public.productos (id,id_vendedor,nombre)
VALUES ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Producto A'),
       ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Producto B');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
DO $$
DECLARE affected integer;
BEGIN
  IF (SELECT count(*) FROM public.usuarios) <> 1 THEN
    RAISE EXCEPTION 'Un usuario puede leer perfiles privados ajenos';
  END IF;
  UPDATE public.usuarios SET nombre_publico = 'Nombre actualizado'
    WHERE id = '10000000-0000-0000-0000-000000000001';
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 1 THEN RAISE EXCEPTION 'No puede editar su nombre'; END IF;
  BEGIN
    UPDATE public.usuarios SET estado_cuenta = 'suspendida'
      WHERE id = '10000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'Puede modificar un campo reservado';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  UPDATE public.productos SET nombre = 'Editado por propietario'
    WHERE id = '30000000-0000-0000-0000-000000000001';
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 1 THEN RAISE EXCEPTION 'No puede editar su producto'; END IF;
  UPDATE public.productos SET nombre = 'Cambio ajeno'
    WHERE id = '30000000-0000-0000-0000-000000000002';
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'Puede editar productos ajenos'; END IF;
  BEGIN
    INSERT INTO public.productos (id_vendedor,nombre)
    VALUES ('20000000-0000-0000-0000-000000000002','Publicación ajena');
    RAISE EXCEPTION 'Puede publicar como otro vendedor';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
ROLLBACK;
