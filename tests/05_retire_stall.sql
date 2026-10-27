BEGIN;
CREATE FUNCTION pg_temp.assert_retiro(ok boolean, mensaje text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION '%', mensaje; END IF;
END $$;

INSERT INTO auth.users (id, email, is_anonymous) VALUES
 ('14000000-0000-0000-0000-000000000001', 'retiro-a@example.test', false),
 ('14000000-0000-0000-0000-000000000002', 'retiro-b@example.test', false);
INSERT INTO public.usuarios (id, nombre_publico) VALUES
 ('14000000-0000-0000-0000-000000000001', 'Vendedor retiro'),
 ('14000000-0000-0000-0000-000000000002', 'Persona ajena')
ON CONFLICT (id) DO UPDATE SET nombre_publico=EXCLUDED.nombre_publico;
INSERT INTO public.perfiles_vendedor (id, id_usuario)
VALUES ('24000000-0000-0000-0000-000000000001', '14000000-0000-0000-0000-000000000001');
INSERT INTO public.tianguis (id, nombre) VALUES ('44000000-0000-0000-0000-000000000001', 'Tianguis retiro');
INSERT INTO public.vendedor_tianguis (id_vendedor, id_tianguis)
VALUES ('24000000-0000-0000-0000-000000000001', '44000000-0000-0000-0000-000000000001');
INSERT INTO public.puestos (id, id_vendedor, id_tianguis, nombre, estado)
VALUES ('54000000-0000-0000-0000-000000000001', '24000000-0000-0000-0000-000000000001',
 '44000000-0000-0000-0000-000000000001', 'Puesto retiro', 'abierto');
INSERT INTO public.jornadas_puesto (id, id_puesto, latitud, longitud)
VALUES ('74000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000001', 19.4, -99.1);
INSERT INTO public.productos (id, id_vendedor, id_puesto, nombre, cantidad_disponible)
VALUES ('64000000-0000-0000-0000-000000000001', '24000000-0000-0000-0000-000000000001',
 '54000000-0000-0000-0000-000000000001', 'Producto retiro', 5);
INSERT INTO public.ofertas (id_producto, descuento, fecha_fin)
VALUES ('64000000-0000-0000-0000-000000000001', 10, now() + interval '1 day');
INSERT INTO public.apartados (id_producto, id_comprador, id_vendedor, cantidad)
VALUES ('64000000-0000-0000-0000-000000000001', '14000000-0000-0000-0000-000000000002',
 '24000000-0000-0000-0000-000000000001', 1);
INSERT INTO public.visitas (id, id_usuario, id_puesto, id_jornada)
VALUES ('84000000-0000-0000-0000-000000000001', '14000000-0000-0000-0000-000000000002',
 '54000000-0000-0000-0000-000000000001', '74000000-0000-0000-0000-000000000001');
INSERT INTO public.calificaciones (id_visita, id_usuario, puntuacion)
VALUES ('84000000-0000-0000-0000-000000000001', '14000000-0000-0000-0000-000000000002', 5);

SELECT pg_temp.assert_retiro(NOT has_function_privilege('anon', 'public.retirar_puesto(uuid)', 'EXECUTE'),
 'anon puede retirar puestos');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '14000000-0000-0000-0000-000000000002', true);
DO $$ BEGIN
  BEGIN
    PERFORM public.retirar_puesto('54000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'Se permitió retirar un puesto ajeno';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'No autorizado para retirar este puesto' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;

-- Un fallo después de cerrar la jornada y retirar productos revierte todo.
CREATE FUNCTION pg_temp.fallar_retiro() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Fallo sintético al finalizar oferta'; END $$;
CREATE TRIGGER fallo_retiro BEFORE UPDATE ON public.ofertas
 FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_retiro();
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '14000000-0000-0000-0000-000000000001', true);
DO $$ BEGIN
  BEGIN
    PERFORM public.retirar_puesto('54000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'No se ejercitó el fallo sintético';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Fallo sintético al finalizar oferta' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;
SELECT pg_temp.assert_retiro((SELECT activo AND estado = 'abierto' FROM public.puestos), 'El fallo dejó cerrado el puesto');
SELECT pg_temp.assert_retiro((SELECT activo AND disponible FROM public.productos), 'El fallo retiró productos');
SELECT pg_temp.assert_retiro((SELECT fecha_cierre IS NULL FROM public.jornadas_puesto), 'El fallo cerró la jornada');
DROP TRIGGER fallo_retiro ON public.ofertas;

SET LOCAL ROLE authenticated;
SELECT public.retirar_puesto('54000000-0000-0000-0000-000000000001');
SELECT public.retirar_puesto('54000000-0000-0000-0000-000000000001');
RESET ROLE;
SELECT pg_temp.assert_retiro((SELECT NOT activo AND estado = 'cerrado' FROM public.puestos), 'No retiró el puesto');
SELECT pg_temp.assert_retiro((SELECT NOT activo AND NOT disponible AND cantidad_disponible = 5
 AND id_puesto = '54000000-0000-0000-0000-000000000001' FROM public.productos), 'Perdió stock o relación');
SELECT pg_temp.assert_retiro((SELECT estado = 'finalizada' FROM public.ofertas), 'No finalizó la oferta');
SELECT pg_temp.assert_retiro((SELECT fecha_cierre IS NOT NULL FROM public.jornadas_puesto), 'No cerró la jornada');
SELECT pg_temp.assert_retiro((SELECT count(*) = 1 FROM public.visitas)
 AND (SELECT count(*) = 1 FROM public.calificaciones)
 AND (SELECT count(*) = 1 FROM public.apartados WHERE estado = 'pendiente'), 'Perdió historial');
DO $$ BEGIN
  BEGIN
    UPDATE public.productos SET activo = true;
    RAISE EXCEPTION 'Permitió reactivar un producto en puesto retirado';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'El producto requiere un puesto activo del mismo vendedor' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO public.productos (id_vendedor, id_puesto, nombre)
    VALUES ('24000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000001', 'Nuevo');
    RAISE EXCEPTION 'Permitió publicar un producto en puesto retirado';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'El producto requiere un puesto activo del mismo vendedor' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.ofertas SET estado = 'activa';
    RAISE EXCEPTION 'Permitió reactivar una oferta en puesto retirado';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'No se puede publicar una oferta en un puesto retirado' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK;
