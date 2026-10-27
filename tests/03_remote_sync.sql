-- Integración de los cambios exportados; solo fixtures locales y ROLLBACK.
BEGIN;

CREATE FUNCTION pg_temp.assert_true(ok boolean, mensaje text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION '%', mensaje; END IF;
END $$;

-- Se ejercitan los triggers reales de Auth capturados en la linea base.

INSERT INTO auth.users (id, email, raw_user_meta_data, is_anonymous)
VALUES
  ('11000000-0000-0000-0000-000000000001', 'vendedor@example.test', '{"nombre_publico":"Vendedor"}', false),
  ('11000000-0000-0000-0000-000000000002', 'comprador@example.test', '{"nombre_publico":"Comprador"}', false),
  ('11000000-0000-0000-0000-000000000003', 'ajeno@example.test', '{}', false),
  ('11000000-0000-0000-0000-000000000004', NULL, '{}', true);

SELECT pg_temp.assert_true(
  (SELECT count(*) = 4 FROM public.preferencias_notificacion),
  'El alta no creó las preferencias de las cuatro cuentas');
SELECT pg_temp.assert_true(
  (SELECT nombre_publico = 'Invitado' FROM public.usuarios
   WHERE id = '11000000-0000-0000-0000-000000000004'),
  'El alta anónima no usó el nombre de respaldo');
UPDATE auth.users SET email = 'nuevo@example.test'
  WHERE id = '11000000-0000-0000-0000-000000000002';
SELECT pg_temp.assert_true(
  (SELECT correo = 'nuevo@example.test' FROM public.usuarios
   WHERE id = '11000000-0000-0000-0000-000000000002'),
  'No se sincronizó el correo');

DO $$
BEGIN
  BEGIN
    INSERT INTO public.perfiles_vendedor (id_usuario)
      VALUES ('11000000-0000-0000-0000-000000000004');
    RAISE EXCEPTION 'Se permitió vender con cuenta anónima';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT IN ('Verifica tu correo para poder ser vendedor.',
                      'Los usuarios sin cuenta no pueden ser vendedores ni administradores. Inicia sesión con tu correo.') THEN
      RAISE;
    END IF;
  END;
END $$;

INSERT INTO public.perfiles_vendedor (id, id_usuario)
VALUES ('21000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001');
INSERT INTO public.tianguis (id, nombre) VALUES ('71000000-0000-0000-0000-000000000001', 'Tianguis sintético');
INSERT INTO public.vendedor_tianguis (id_vendedor, id_tianguis)
VALUES ('21000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001');
INSERT INTO public.puestos (id, id_vendedor, id_tianguis, nombre)
VALUES ('81000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', 'Puesto sintético');
INSERT INTO public.productos (id, id_vendedor, id_puesto, nombre, cantidad_disponible)
VALUES ('31000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'Producto sintético', 5);
INSERT INTO public.conversaciones (id, contexto, id_producto, id_iniciador, id_receptor)
VALUES ('41000000-0000-0000-0000-000000000001', 'producto',
        '31000000-0000-0000-0000-000000000001',
        '11000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000001');
INSERT INTO public.apartados (id, id_producto, id_comprador, id_vendedor, cantidad, fecha_expiracion)
VALUES ('51000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001',
        '11000000-0000-0000-0000-000000000002', '21000000-0000-0000-0000-000000000001', 2, now() + interval '1 day');
INSERT INTO public.propuestas_precio (id, id_producto, id_comprador, id_vendedor, id_emisor, monto)
VALUES ('61000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001',
        '11000000-0000-0000-0000-000000000002', '21000000-0000-0000-0000-000000000001',
        '11000000-0000-0000-0000-000000000002', 50);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000003', true);
SELECT set_config('request.jwt.claims', '{"sub":"11000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
DO $$
BEGIN
  BEGIN
    PERFORM public.ocultar_conversacion('41000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'Se permitió ocultar un chat ajeno';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'No participas en esa conversación' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.responder_apartado('51000000-0000-0000-0000-000000000001', 'aceptar');
    RAISE EXCEPTION 'Se permitió aceptar un apartado ajeno';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'No participas en este apartado' THEN RAISE; END IF;
  END;
END $$;

SELECT set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000002', true);
SELECT set_config('request.jwt.claims', '{"sub":"11000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
SELECT public.ocultar_conversacion('41000000-0000-0000-0000-000000000001');
SELECT public.ocultar_conversacion('41000000-0000-0000-0000-000000000001');
SELECT pg_temp.assert_true((SELECT count(*) = 1 FROM public.conversaciones_ocultas),
  'Ocultar dos veces no fue idempotente');

SELECT set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000003', true);
SELECT set_config('request.jwt.claims', '{"sub":"11000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
SELECT pg_temp.assert_true((SELECT count(*) = 0 FROM public.conversaciones_ocultas),
  'Un tercero puede leer los chats ocultos ajenos');

SELECT set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"11000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SELECT pg_temp.assert_true(
  EXISTS (SELECT 1 FROM public.usuarios WHERE id = '11000000-0000-0000-0000-000000000002'),
  'El vendedor no puede leer al comprador con un trato');
DO $$
BEGIN
  BEGIN
    UPDATE public.apartados SET estado = 'aceptado'
      WHERE id = '51000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'Se permitió responder sin RPC';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Usa las opciones de la app para responder (el estado no se cambia directo)' THEN RAISE; END IF;
  END;
END $$;
SELECT public.responder_apartado('51000000-0000-0000-0000-000000000001', 'aceptar');
SELECT pg_temp.assert_true(
  (SELECT cantidad_disponible = 3 FROM public.productos WHERE id = '31000000-0000-0000-0000-000000000001'),
  'Aceptar un apartado no descontó el stock');
SELECT public.responder_propuesta('61000000-0000-0000-0000-000000000001', 'contraofertar', 60);
SELECT pg_temp.assert_true(
  EXISTS (SELECT 1 FROM public.propuestas_precio
          WHERE id_propuesta_anterior = '61000000-0000-0000-0000-000000000001' AND monto = 60),
  'No se creó la contraoferta');

-- Las RPC habilitan su actualización interna hasta el final de la transacción.
SELECT set_config('tianguia.rpc', '', true);
SELECT set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000002', true);
SELECT set_config('request.jwt.claims', '{"sub":"11000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
SELECT public.responder_apartado('51000000-0000-0000-0000-000000000001', 'cancelar');
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT cantidad_disponible = 5 FROM public.productos WHERE id = '31000000-0000-0000-0000-000000000001'),
  'Cancelar no devolvió el stock');

-- Apartado aceptado vencido y oferta caducada para comprobar restitución y cierre.
INSERT INTO public.apartados (id_producto, id_comprador, id_vendedor, cantidad, estado, fecha_expiracion)
VALUES ('31000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000002',
        '21000000-0000-0000-0000-000000000001', 2, 'aceptado', now() - interval '1 hour');
UPDATE public.productos SET cantidad_disponible = 3 WHERE id = '31000000-0000-0000-0000-000000000001';
INSERT INTO public.ofertas (id_vendedor, id_producto, descuento, fecha_inicio, fecha_fin)
VALUES ('21000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001', 10, now() - interval '2 hours', now() - interval '1 hour');
SET LOCAL ROLE authenticated;
SELECT public.vencer_pendientes();
SELECT public.vencer_pendientes();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT cantidad_disponible = 5 FROM public.productos WHERE id = '31000000-0000-0000-0000-000000000001'),
  'El vencimiento no devolvió exactamente una vez el stock');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM public.apartados WHERE estado = 'expirado'),
  'No venció el apartado aceptado');
SELECT pg_temp.assert_true(
  (SELECT bool_and(estado = 'finalizada') FROM public.ofertas),
  'No finalizó la oferta vencida');
SELECT pg_temp.assert_true(
  NOT has_function_privilege('anon', 'public.vencer_pendientes()', 'EXECUTE'),
  'Se heredó acceso anónimo a vencer_pendientes');

ROLLBACK;
