-- Esta transacción engloba fixtures, migración incremental y comprobaciones.
BEGIN;
INSERT INTO auth.users (id, email, is_anonymous) VALUES
 ('12000000-0000-0000-0000-000000000001', 'upgrade-v@example.test', false),
 ('12000000-0000-0000-0000-000000000002', 'upgrade-c@example.test', false);
INSERT INTO public.usuarios (id, nombre_publico) VALUES
 ('12000000-0000-0000-0000-000000000001', 'Vendedor previo'),
 ('12000000-0000-0000-0000-000000000002', 'Comprador previo');
INSERT INTO public.perfiles_vendedor (id, id_usuario)
VALUES ('22000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000001');
INSERT INTO public.tianguis (id, nombre) VALUES ('32000000-0000-0000-0000-000000000001', 'Mercado previo');
INSERT INTO public.vendedor_tianguis (id_vendedor, id_tianguis)
VALUES ('22000000-0000-0000-0000-000000000001', '32000000-0000-0000-0000-000000000001');
INSERT INTO public.puestos (id, id_vendedor, id_tianguis, nombre)
VALUES ('42000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', '32000000-0000-0000-0000-000000000001', 'Puesto previo');
-- Sin puesto, pero con una sola asignación posible: backfill sin ambigüedad.
INSERT INTO public.productos (id, id_vendedor, nombre, cantidad_disponible) VALUES
 ('52000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', 'Producto previo A', 4),
 ('52000000-0000-0000-0000-000000000002', '22000000-0000-0000-0000-000000000001', 'Producto previo B', 6);
INSERT INTO public.ofertas (id, id_vendedor, titulo, fecha_fin)
VALUES ('62000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', 'Campaña previa', now() + interval '1 day');
INSERT INTO public.oferta_productos (id, id_oferta, id_producto, precio_promocional, descuento_porcentaje) VALUES
 ('72000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', 25, NULL),
 ('72000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', NULL, 15);
INSERT INTO public.conversaciones (id, contexto, id_producto, id_iniciador, id_receptor)
VALUES ('82000000-0000-0000-0000-000000000001', 'producto', '52000000-0000-0000-0000-000000000001',
 '12000000-0000-0000-0000-000000000002', '12000000-0000-0000-0000-000000000001');
INSERT INTO public.mensajes (id_conversacion, id_remitente, contenido)
VALUES ('82000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000002', 'Mensaje previo');
