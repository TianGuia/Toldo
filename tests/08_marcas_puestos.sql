-- Marcas de puesto: Nuevo, Veterano y Destacado (datos sintéticos, ROLLBACK).
BEGIN;
CREATE FUNCTION pg_temp.assert_marca(ok boolean, mensaje text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION '%', mensaje; END IF;
END $$;

-- Dueño del negocio (17...01) y 10 compradores (18...0001 a 18...0010).
INSERT INTO auth.users (id, email, is_anonymous) VALUES
 ('17000000-0000-0000-0000-000000000001', 'marcas-vendedor@example.test', false);
INSERT INTO auth.users (id, email, is_anonymous)
SELECT ('18000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       'marcas-comprador-' || i || '@example.test', false
  FROM generate_series(1, 10) i;
INSERT INTO public.usuarios (id, nombre_publico) VALUES
 ('17000000-0000-0000-0000-000000000001', 'Dueño marcas')
ON CONFLICT (id) DO UPDATE SET nombre_publico = EXCLUDED.nombre_publico;
INSERT INTO public.usuarios (id, nombre_publico)
SELECT ('18000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 'Comprador ' || i
  FROM generate_series(1, 10) i
ON CONFLICT (id) DO UPDATE SET nombre_publico = EXCLUDED.nombre_publico;

INSERT INTO public.perfiles_vendedor (id, id_usuario)
VALUES ('27000000-0000-0000-0000-000000000001', '17000000-0000-0000-0000-000000000001');
INSERT INTO public.tianguis (id, nombre) VALUES ('47000000-0000-0000-0000-000000000001', 'Tianguis marcas');
INSERT INTO public.vendedor_tianguis (id_vendedor, id_tianguis)
VALUES ('27000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000001');
INSERT INTO public.categorias (id, nombre) VALUES
 ('37000000-0000-0000-0000-000000000001', 'Marcas uno'),
 ('37000000-0000-0000-0000-000000000002', 'Marcas dos'),
 ('37000000-0000-0000-0000-000000000003', 'Marcas tres');

-- A: 5 personas distintas (4.6) | B: una sola persona con 5.0 | C: veterano | D: sin calificaciones
INSERT INTO public.puestos (id, id_vendedor, id_tianguis, nombre) VALUES
 ('57000000-0000-0000-0000-00000000000a', '27000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000001', 'Puesto A'),
 ('57000000-0000-0000-0000-00000000000b', '27000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000001', 'Puesto B'),
 ('57000000-0000-0000-0000-00000000000c', '27000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000001', 'Puesto C'),
 ('57000000-0000-0000-0000-00000000000d', '27000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000001', 'Puesto D');
INSERT INTO public.productos (id_vendedor, id_puesto, id_categoria, nombre) VALUES
 ('27000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-00000000000a', '37000000-0000-0000-0000-000000000001', 'Producto A'),
 ('27000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-00000000000b', '37000000-0000-0000-0000-000000000001', 'Producto B'),
 ('27000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-00000000000c', '37000000-0000-0000-0000-000000000002', 'Producto C'),
 ('27000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-00000000000d', '37000000-0000-0000-0000-000000000003', 'Producto D');

-- Jornadas: A y B abrieron hoy; C abrió por primera vez hace 400 días y 12 veces en total.
INSERT INTO public.jornadas_puesto (id, id_puesto, fecha_apertura, fecha_cierre) VALUES
 ('77000000-0000-0000-0000-00000000000a', '57000000-0000-0000-0000-00000000000a', now() - interval '2 hours', now() - interval '1 hour'),
 ('77000000-0000-0000-0000-00000000000b', '57000000-0000-0000-0000-00000000000b', now() - interval '2 hours', now() - interval '1 hour');
INSERT INTO public.jornadas_puesto (id, id_puesto, fecha_apertura, fecha_cierre)
SELECT ('78000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       '57000000-0000-0000-0000-00000000000c',
       CASE WHEN i = 1 THEN now() - interval '400 days' ELSE now() - ((13 - i) * interval '3 days') END,
       CASE WHEN i = 1 THEN now() - interval '400 days' + interval '4 hours'
            ELSE now() - ((13 - i) * interval '3 days') + interval '4 hours' END
  FROM generate_series(1, 12) i;

-- A: cinco personas distintas (5,5,4,4,5) y una calificación del dueño que no debe contar.
INSERT INTO public.visitas (id, id_usuario, id_puesto, id_jornada)
SELECT ('87000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       ('18000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       '57000000-0000-0000-0000-00000000000a', '77000000-0000-0000-0000-00000000000a'
  FROM generate_series(1, 5) i;
INSERT INTO public.calificaciones (id_visita, id_usuario, puntuacion)
SELECT ('87000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       ('18000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       (ARRAY[5, 5, 4, 4, 5])[i]
  FROM generate_series(1, 5) i;
INSERT INTO public.visitas (id, id_usuario, id_puesto, id_jornada) VALUES
 ('87000000-0000-0000-0000-0000000000ff', '17000000-0000-0000-0000-000000000001',
  '57000000-0000-0000-0000-00000000000a', '77000000-0000-0000-0000-00000000000a');
INSERT INTO public.calificaciones (id_visita, id_usuario, puntuacion)
VALUES ('87000000-0000-0000-0000-0000000000ff', '17000000-0000-0000-0000-000000000001', 1);

-- B: una sola persona con 5 estrellas.
INSERT INTO public.visitas (id, id_usuario, id_puesto, id_jornada) VALUES
 ('87000000-0000-0000-0000-0000000000b1', '18000000-0000-0000-0000-000000000001',
  '57000000-0000-0000-0000-00000000000b', '77000000-0000-0000-0000-00000000000b');
INSERT INTO public.calificaciones (id_visita, id_usuario, puntuacion)
VALUES ('87000000-0000-0000-0000-0000000000b1', '18000000-0000-0000-0000-000000000001', 5);

-- C: diez personas distintas, cada una en una jornada distinta, todas con 5.
INSERT INTO public.visitas (id, id_usuario, id_puesto, id_jornada)
SELECT ('88000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       ('18000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       '57000000-0000-0000-0000-00000000000c',
       ('78000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid
  FROM generate_series(1, 10) i;
INSERT INTO public.calificaciones (id_visita, id_usuario, puntuacion)
SELECT ('88000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       ('18000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 5
  FROM generate_series(1, 10) i;

-- La calificación del dueño no cuenta: A sigue con 5 calificaciones y promedio 4.6.
SELECT pg_temp.assert_marca(
  (SELECT calificaciones = 5 AND calificadores = 5 AND promedio = 4.6
     FROM public.v_puestos_resumen WHERE id = '57000000-0000-0000-0000-00000000000a'),
  'La calificación del dueño entró al promedio');

-- Nuevo: A y B abrieron hoy; C abrió hace más de 30 días; D nunca abrió.
SELECT pg_temp.assert_marca(
  (SELECT es_nuevo FROM public.v_puestos_resumen WHERE id = '57000000-0000-0000-0000-00000000000a')
  AND (SELECT es_nuevo FROM public.v_puestos_resumen WHERE id = '57000000-0000-0000-0000-00000000000b'),
  'Un puesto recién abierto no salió como nuevo');
SELECT pg_temp.assert_marca(
  (SELECT NOT es_nuevo FROM public.v_puestos_resumen WHERE id = '57000000-0000-0000-0000-00000000000c')
  AND (SELECT NOT es_nuevo FROM public.v_puestos_resumen WHERE id = '57000000-0000-0000-0000-00000000000d'),
  'La marca nuevo no se quitó con el tiempo o salió sin haber abierto');

-- Veterano: solo C cumple todo; A y B son muy recientes.
SELECT pg_temp.assert_marca(
  (SELECT es_veterano AND calificadores = 10 AND jornadas = 12
     FROM public.v_puestos_resumen WHERE id = '57000000-0000-0000-0000-00000000000c'),
  'El puesto veterano no salió como veterano');
SELECT pg_temp.assert_marca(
  NOT EXISTS (SELECT 1 FROM public.v_puestos_resumen
               WHERE es_veterano AND id IN ('57000000-0000-0000-0000-00000000000a',
                                            '57000000-0000-0000-0000-00000000000b',
                                            '57000000-0000-0000-0000-00000000000d')),
  'Se marcó veterano a un puesto que no cumple');

-- Veterano no se queda si baja el promedio: con 10 calificaciones de 1 deja de serlo.
UPDATE public.calificaciones SET puntuacion = 1
 WHERE id_puesto = '57000000-0000-0000-0000-00000000000c';
SELECT pg_temp.assert_marca(
  (SELECT NOT es_veterano FROM public.v_puestos_resumen WHERE id = '57000000-0000-0000-0000-00000000000c'),
  'El veterano conservó la marca con promedio bajo');
UPDATE public.calificaciones SET puntuacion = 5
 WHERE id_puesto = '57000000-0000-0000-0000-00000000000c';

-- Destacado: 4.6 con 5 personas le gana a 5.0 con una sola persona.
SELECT pg_temp.assert_marca(
  (SELECT id FROM public.puesto_destacado('37000000-0000-0000-0000-000000000001'))
    = '57000000-0000-0000-0000-00000000000a',
  'Una sola calificación le ganó al puesto con 5 personas');
-- Sin nadie que cumpla el mínimo siempre hay destacado (categoría con un puesto sin calificar).
SELECT pg_temp.assert_marca(
  (SELECT id FROM public.puesto_destacado('37000000-0000-0000-0000-000000000003'))
    = '57000000-0000-0000-0000-00000000000d',
  'No hay destacado de respaldo cuando nadie cumple el mínimo');
ROLLBACK;
