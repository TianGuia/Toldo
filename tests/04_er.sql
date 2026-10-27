BEGIN;
CREATE FUNCTION pg_temp.assert_er(ok boolean, mensaje text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION '%', mensaje; END IF;
END $$;

INSERT INTO auth.users (id, email, is_anonymous) VALUES
 ('13000000-0000-0000-0000-000000000001', 'er-a@example.test', false),
 ('13000000-0000-0000-0000-000000000002', 'er-b@example.test', false),
 ('13000000-0000-0000-0000-000000000003', 'er-c@example.test', false),
 ('13000000-0000-0000-0000-000000000004', 'er-d@example.test', false);
INSERT INTO public.usuarios (id, nombre_publico) VALUES
 ('13000000-0000-0000-0000-000000000001', 'Persona A'),
 ('13000000-0000-0000-0000-000000000002', 'Persona B'),
 ('13000000-0000-0000-0000-000000000003', 'Persona C'),
 ('13000000-0000-0000-0000-000000000004', 'Persona ajena')
ON CONFLICT (id) DO UPDATE SET nombre_publico=EXCLUDED.nombre_publico;
INSERT INTO public.perfiles_vendedor (id, id_usuario)
VALUES ('23000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000001');
SELECT pg_temp.assert_er(
  EXISTS (SELECT 1 FROM public.compradores WHERE id_usuario = '13000000-0000-0000-0000-000000000001'),
  'La especialización no permite comprador y vendedor simultáneos');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '13000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"13000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
INSERT INTO public.conversaciones (id, id_receptor)
VALUES ('33000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000002');
INSERT INTO public.participantes (id_conversacion, id_usuario)
VALUES ('33000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000003');
SELECT set_config('request.jwt.claim.sub', '13000000-0000-0000-0000-000000000003', true);
SELECT set_config('request.jwt.claims', '{"sub":"13000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
SELECT pg_temp.assert_er((SELECT count(*) = 3 FROM public.participantes), 'El tercer participante no puede leer la membresía');
INSERT INTO public.mensajes (id_conversacion, id_remitente, contenido)
VALUES ('33000000-0000-0000-0000-000000000001', auth.uid(), 'Mensaje del tercer participante');
SELECT public.ocultar_conversacion('33000000-0000-0000-0000-000000000001');
SELECT set_config('request.jwt.claim.sub', '13000000-0000-0000-0000-000000000004', true);
SELECT set_config('request.jwt.claims', '{"sub":"13000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
SELECT pg_temp.assert_er((SELECT count(*) = 0 FROM public.conversaciones), 'Un tercero lee conversaciones ajenas');
SELECT pg_temp.assert_er((SELECT count(*) = 0 FROM public.mensajes), 'Un tercero lee mensajes ajenos');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.mensajes (id_conversacion, id_remitente, contenido)
    VALUES ('33000000-0000-0000-0000-000000000001', auth.uid(), 'Intrusión');
    RAISE EXCEPTION 'Un ajeno pudo enviar mensajes';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'El remitente no participa en la conversación' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;

INSERT INTO public.tianguis (id, nombre) VALUES ('43000000-0000-0000-0000-000000000001', 'Tianguis ER');
INSERT INTO public.vendedor_tianguis (id_vendedor, id_tianguis)
VALUES ('23000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001');
INSERT INTO public.puestos (id, id_vendedor, id_tianguis, nombre)
VALUES ('53000000-0000-0000-0000-000000000001', '23000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001', 'Puesto ER');
INSERT INTO public.productos (id, id_vendedor, id_puesto, nombre)
VALUES ('63000000-0000-0000-0000-000000000001', '23000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001', 'Producto ER');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.productos (id_vendedor, nombre)
    VALUES ('23000000-0000-0000-0000-000000000001', 'Sin puesto');
    RAISE EXCEPTION 'Se permitió producto sin puesto';
  EXCEPTION WHEN not_null_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.ofertas (id_vendedor, descuento, fecha_fin)
    VALUES ('23000000-0000-0000-0000-000000000001', 10, now() + interval '1 day');
    RAISE EXCEPTION 'Se permitió oferta sin producto';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Producto inexistente' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM public.puestos WHERE id = '53000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'Eliminar un puesto dejó productos huérfanos';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
END $$;
INSERT INTO public.ofertas (id_producto, descuento, fecha_fin)
VALUES ('63000000-0000-0000-0000-000000000001', 20, now() + interval '1 day');
SELECT pg_temp.assert_er(
  EXISTS (SELECT 1 FROM public.ofertas WHERE id_producto = '63000000-0000-0000-0000-000000000001' AND descuento = 20),
  'No se puede publicar oferta individual');
SELECT pg_temp.assert_er(
  EXISTS (SELECT 1 FROM public.productos_catalogo WHERE id = '63000000-0000-0000-0000-000000000001' AND descuento_porcentaje = 20),
  'El catálogo no refleja la oferta individual');

INSERT INTO public.apelaciones (id_usuario, motivo)
VALUES ('13000000-0000-0000-0000-000000000002', 'Solicitud sin reporte, permitida por el ER');

INSERT INTO public.jornadas_puesto (id, id_puesto, latitud, longitud)
VALUES ('73000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001', 19.4, -99.1);
INSERT INTO public.visitas (id, id_usuario, id_puesto, id_jornada, estado)
VALUES ('83000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', 'pendiente');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.calificaciones (id_visita, id_usuario, puntuacion)
    VALUES ('83000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000002', 5);
    RAISE EXCEPTION 'Se calificó una visita no verificada';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'La visita no está verificada' THEN RAISE; END IF;
  END;
END $$;
UPDATE public.visitas SET estado = 'verificada' WHERE id = '83000000-0000-0000-0000-000000000001';
INSERT INTO public.calificaciones (id_visita, id_usuario, puntuacion)
VALUES ('83000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000002', 5);
DO $$
BEGIN
  BEGIN
    INSERT INTO public.calificaciones (id_visita, id_usuario, puntuacion)
    VALUES ('83000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000002', 4);
    RAISE EXCEPTION 'Se permitió más de una calificación por visita';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;
ROLLBACK;
