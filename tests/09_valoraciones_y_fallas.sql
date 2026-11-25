-- Datos sintéticos para verificar privacidad, agregados y permisos de reportes.
BEGIN;

CREATE FUNCTION pg_temp.assert_true(ok boolean, mensaje text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION '%', mensaje; END IF;
END $$;

INSERT INTO auth.users (id, email, is_anonymous) VALUES
 ('19000000-0000-0000-0000-000000000001', 'privacidad-vendedor@example.test', false),
 ('19000000-0000-0000-0000-000000000002', 'privacidad-autor@example.test', false),
 ('19000000-0000-0000-0000-000000000003', 'privacidad-visitante@example.test', false),
 ('19000000-0000-0000-0000-000000000004', 'privacidad-admin@example.test', false);

INSERT INTO public.admin_sesiones (id_usuario, nombre, expira_en)
VALUES ('19000000-0000-0000-0000-000000000004', 'Admin de prueba', now() + interval '1 hour');
INSERT INTO public.perfiles_vendedor (id, id_usuario)
VALUES ('29000000-0000-0000-0000-000000000001', '19000000-0000-0000-0000-000000000001');
INSERT INTO public.tianguis (id, nombre)
VALUES ('49000000-0000-0000-0000-000000000001', 'Tianguis de privacidad');
INSERT INTO public.vendedor_tianguis (id_vendedor, id_tianguis)
VALUES ('29000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000001');
INSERT INTO public.puestos (id, id_vendedor, id_tianguis, nombre)
VALUES ('59000000-0000-0000-0000-000000000001', '29000000-0000-0000-0000-000000000001',
        '49000000-0000-0000-0000-000000000001', 'Puesto de privacidad');
INSERT INTO public.jornadas_puesto (id, id_puesto, fecha_apertura, fecha_cierre)
VALUES ('79000000-0000-0000-0000-000000000001', '59000000-0000-0000-0000-000000000001',
        now() - interval '2 hours', now() - interval '1 hour');
INSERT INTO public.visitas (id, id_usuario, id_puesto, id_jornada) VALUES
 ('89000000-0000-0000-0000-000000000001', '19000000-0000-0000-0000-000000000002',
  '59000000-0000-0000-0000-000000000001', '79000000-0000-0000-0000-000000000001'),
 ('89000000-0000-0000-0000-000000000002', '19000000-0000-0000-0000-000000000003',
  '59000000-0000-0000-0000-000000000001', '79000000-0000-0000-0000-000000000001');
INSERT INTO public.calificaciones (id, id_visita, id_usuario, puntuacion, comentario, moderado) VALUES
 ('99000000-0000-0000-0000-000000000001', '89000000-0000-0000-0000-000000000001',
  '19000000-0000-0000-0000-000000000002', 5, 'Comentario de prueba', false),
 ('99000000-0000-0000-0000-000000000002', '89000000-0000-0000-0000-000000000002',
  '19000000-0000-0000-0000-000000000003', 1, 'Comentario moderado', true);
INSERT INTO public.etiquetas_valoracion (id, nombre)
VALUES ('39000000-0000-0000-0000-000000000001', 'Etiqueta de privacidad');
INSERT INTO public.calificacion_etiquetas (id_calificacion, id_etiqueta)
SELECT id, '39000000-0000-0000-0000-000000000001'
FROM public.calificaciones WHERE id_puesto = '59000000-0000-0000-0000-000000000001';

SELECT pg_temp.assert_true(
  NOT has_function_privilege('anon', 'public.etiquetas_puesto(uuid)', 'EXECUTE'),
  'El rol anon conserva acceso al conteo de etiquetas');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '19000000-0000-0000-0000-000000000002', true);
SELECT pg_temp.assert_true(
  (SELECT comentario FROM public.calificaciones WHERE id = '99000000-0000-0000-0000-000000000001')
    = 'Comentario de prueba', 'El autor perdió acceso a su comentario');
INSERT INTO public.reportes_falla (tipo, descripcion) VALUES ('otra', 'Reporte sintético del autor');

SELECT set_config('request.jwt.claim.sub', '19000000-0000-0000-0000-000000000003', true);
SELECT pg_temp.assert_true(
  NOT EXISTS (SELECT 1 FROM public.calificaciones WHERE id = '99000000-0000-0000-0000-000000000001'),
  'Una cuenta ajena puede leer el comentario');
SELECT pg_temp.assert_true(
  (SELECT total FROM public.etiquetas_puesto('59000000-0000-0000-0000-000000000001')
   WHERE nombre = 'Etiqueta de privacidad') = 1, 'El conteo incluye la valoración moderada');
SELECT pg_temp.assert_true(
  (SELECT promedio = 5 AND total = 1 FROM public.resumen_calificaciones
   WHERE id_vendedor = '29000000-0000-0000-0000-000000000001'),
  'La política privada impide ver el resumen público');
SELECT pg_temp.assert_true(
  NOT EXISTS (SELECT 1 FROM public.reportes_falla), 'Una cuenta ajena puede ver el reporte');

SELECT set_config('request.jwt.claim.sub', '19000000-0000-0000-0000-000000000001', true);
SELECT pg_temp.assert_true(
  EXISTS (SELECT 1 FROM public.calificaciones WHERE id = '99000000-0000-0000-0000-000000000001'),
  'El vendedor perdió acceso a la valoración de su puesto');

SELECT set_config('request.jwt.claim.sub', '19000000-0000-0000-0000-000000000004', true);
SELECT pg_temp.assert_true(
  (SELECT count(*) FROM public.reportes_falla) = 1, 'El administrador no puede ver el reporte');
RESET ROLE;

UPDATE public.usuarios SET estado_cuenta = 'suspendida' WHERE id = '19000000-0000-0000-0000-000000000003';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '19000000-0000-0000-0000-000000000003', true);
DO $$ BEGIN
  BEGIN
    INSERT INTO public.reportes_falla (tipo, descripcion) VALUES ('otra', 'Reporte de cuenta suspendida');
    RAISE EXCEPTION 'Una cuenta suspendida puede enviar reportes';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
ROLLBACK;
