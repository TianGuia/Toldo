-- TianGuía · datos de demostración (ficticios) para presentar la app.
-- Se ejecuta A MANO en el SQL Editor de Supabase (rol postgres). No es una migración.
-- Es repetible: cada fila tiene un id fijo y se ignora si ya existe.
-- Los vendedores y compradores son cuentas ficticias sin contraseña: no se puede entrar con ellas.
-- Las coordenadas del Tianguis Cultural son aproximadas: ajústalas (ver el final del archivo).
BEGIN;

-- Tianguis
INSERT INTO public.tianguis (id, nombre, descripcion, direccion, latitud, longitud) VALUES
 ('9418e626-2b24-5a83-a6ca-6329c953fd5b', 'Tianguis Cultural de Guadalajara', 'Mercado de los sábados con ropa vintage, música, zines y comida.', 'Plaza Juárez, frente al Parque Agua Azul, Guadalajara', 20.6600, -103.3515),
 ('45c14a27-8a56-56a6-8d00-3f7f75b24e1b', 'Tianguis Demo CUCEI (ficticio)', 'Tianguis de ejemplo para la presentación en el campus.', 'Blvd. Marcelino García Barragán 1421, Guadalajara', 20.6556, -103.3256)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.tianguis_horarios (id, id_tianguis, dia_semana, hora_inicio, hora_fin) VALUES
 ('36636283-8dfc-569e-b88d-242d37bc753d', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 6, '10:00', '19:00'),
 ('dc73226a-8880-54bc-9178-6107167c3cd1', '45c14a27-8a56-56a6-8d00-3f7f75b24e1b', 3, '09:00', '15:00'),
 ('e50add0c-a9f7-5d95-af1e-f5e4848e84f8', '45c14a27-8a56-56a6-8d00-3f7f75b24e1b', 5, '09:00', '15:00')
ON CONFLICT (id) DO NOTHING;

-- Zonas, pasillos y espacios del Tianguis Cultural (GeoJSON [longitud, latitud])
INSERT INTO public.tianguis_zonas (id, id_tianguis, nombre, tipo, geometria, orden) VALUES
 ('49c0a179-b469-58ba-b5dc-1a1bb9b59ec2', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 'Callejón principal', 'zona', '{"type":"Polygon","coordinates":[[[-103.3522,20.6606],[-103.3508,20.6606],[-103.3508,20.6594],[-103.3522,20.6594],[-103.3522,20.6606]]]}'::jsonb, 0),
 ('250bcab3-1efb-54c1-bc30-a64c4013e27c', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 'Pasillo central', 'pasillo', '{"type":"LineString","coordinates":[[-103.3522,20.6600],[-103.3508,20.6600]]}'::jsonb, 1),
 ('c738bbbb-3f80-54a4-99b6-5cca69f5c992', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 'Foro de música', 'espacio', '{"type":"Polygon","coordinates":[[[-103.3513,20.6597],[-103.3509,20.6597],[-103.3509,20.6594],[-103.3513,20.6594],[-103.3513,20.6597]]]}'::jsonb, 2)
ON CONFLICT (id) DO NOTHING;

-- Categorías (solo si no existen ya con ese nombre)
INSERT INTO public.categorias (nombre) SELECT 'Música y vinilos' WHERE NOT EXISTS (SELECT 1 FROM public.categorias WHERE nombre = 'Música y vinilos');
INSERT INTO public.categorias (nombre) SELECT 'Ropa y accesorios' WHERE NOT EXISTS (SELECT 1 FROM public.categorias WHERE nombre = 'Ropa y accesorios');
INSERT INTO public.categorias (nombre) SELECT 'Libros y zines' WHERE NOT EXISTS (SELECT 1 FROM public.categorias WHERE nombre = 'Libros y zines');
INSERT INTO public.categorias (nombre) SELECT 'Coleccionables' WHERE NOT EXISTS (SELECT 1 FROM public.categorias WHERE nombre = 'Coleccionables');
INSERT INTO public.categorias (nombre) SELECT 'Alimentos' WHERE NOT EXISTS (SELECT 1 FROM public.categorias WHERE nombre = 'Alimentos');
INSERT INTO public.categorias (nombre) SELECT 'Electrónica' WHERE NOT EXISTS (SELECT 1 FROM public.categorias WHERE nombre = 'Electrónica');

-- Cuentas ficticias (no tienen contraseña)
INSERT INTO auth.users (id, email, is_anonymous) VALUES
 ('4bc237de-3edc-5a79-9e8f-ab9cbc7a5e30', 'demo-vendedor1@tianguia.demo', false),
 ('3304493c-87a9-57d5-bd72-6c0ce51f75bb', 'demo-vendedor2@tianguia.demo', false),
 ('ecff9d3f-1da2-5652-a171-0dd619ed284a', 'demo-vendedor3@tianguia.demo', false),
 ('44c64191-e05f-5e8b-922a-234ef85d2508', 'demo-vendedor4@tianguia.demo', false),
 ('5fd7960c-91be-582c-a728-51886e090462', 'demo-vendedor5@tianguia.demo', false),
 ('0e6776f8-699f-562b-a850-f763cd1db97f', 'demo-comprador1@tianguia.demo', false),
 ('eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', 'demo-comprador2@tianguia.demo', false),
 ('922ec138-e996-51af-8328-3dcdf10f9382', 'demo-comprador3@tianguia.demo', false),
 ('eca83eed-5636-5d46-bc55-aa638cc56a63', 'demo-comprador4@tianguia.demo', false),
 ('fe6e905e-e9f3-5cd3-921e-6719746a177d', 'demo-comprador5@tianguia.demo', false)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.usuarios (id, nombre_publico) VALUES
 ('4bc237de-3edc-5a79-9e8f-ab9cbc7a5e30', 'Vendedor demo Disco Rayado'),
 ('3304493c-87a9-57d5-bd72-6c0ce51f75bb', 'Vendedora demo Karma'),
 ('ecff9d3f-1da2-5652-a171-0dd619ed284a', 'Vendedor demo Zines'),
 ('44c64191-e05f-5e8b-922a-234ef85d2508', 'Vendedora demo Lupe'),
 ('5fd7960c-91be-582c-a728-51886e090462', 'Vendedor demo Chip'),
 ('0e6776f8-699f-562b-a850-f763cd1db97f', 'Comprador demo Ana'),
 ('eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', 'Comprador demo Beto'),
 ('922ec138-e996-51af-8328-3dcdf10f9382', 'Comprador demo Carla'),
 ('eca83eed-5636-5d46-bc55-aa638cc56a63', 'Comprador demo Diego'),
 ('fe6e905e-e9f3-5cd3-921e-6719746a177d', 'Comprador demo Elena')
ON CONFLICT (id) DO UPDATE SET nombre_publico = EXCLUDED.nombre_publico;

INSERT INTO public.perfiles_vendedor (id, id_usuario, nombre_negocio, descripcion) VALUES
 ('a6654095-01b1-5811-b5bf-10de8a93387b', '4bc237de-3edc-5a79-9e8f-ab9cbc7a5e30', 'Disco Rayado', 'Vinilos y música usada'),
 ('b847aa53-8459-50b3-910d-dda29fd3956d', '3304493c-87a9-57d5-bd72-6c0ce51f75bb', 'Karma Paca', 'Ropa vintage y de paca'),
 ('6a167b0e-b48e-57f9-b71e-d3d5dd1fb17a', 'ecff9d3f-1da2-5652-a171-0dd619ed284a', 'Zines y Más', 'Zines y libros independientes'),
 ('1fb8e222-b97b-5934-9005-b92fb1cc59e1', '44c64191-e05f-5e8b-922a-234ef85d2508', 'Doña Lupe', 'Antojitos de la casa'),
 ('5325ee17-f63a-5c25-90bf-8526536f0d28', '5fd7960c-91be-582c-a728-51886e090462', 'Chip & Cable', 'Electrónica y piezas')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.vendedor_tianguis (id, id_vendedor, id_tianguis) VALUES
 ('28910676-b413-5bb6-b80a-b11f2bef732f', 'a6654095-01b1-5811-b5bf-10de8a93387b', '9418e626-2b24-5a83-a6ca-6329c953fd5b'),
 ('d91c89c1-2f0a-5b96-ac9e-50e511df7b8b', 'b847aa53-8459-50b3-910d-dda29fd3956d', '9418e626-2b24-5a83-a6ca-6329c953fd5b'),
 ('2d750a83-8869-51cc-9549-310b7b6d19f9', '6a167b0e-b48e-57f9-b71e-d3d5dd1fb17a', '9418e626-2b24-5a83-a6ca-6329c953fd5b'),
 ('c04a944c-31c5-59e6-8de6-b6f533f84105', '1fb8e222-b97b-5934-9005-b92fb1cc59e1', '9418e626-2b24-5a83-a6ca-6329c953fd5b'),
 ('2ec6b51e-782b-5992-9b3f-594a6ede9e60', '5325ee17-f63a-5c25-90bf-8526536f0d28', '45c14a27-8a56-56a6-8d00-3f7f75b24e1b')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.vendedor_horarios (id, id_vendedor, id_tianguis, dia_semana, hora_inicio, hora_fin) VALUES
 ('bb9d7a3b-965e-5181-a358-96565d5991a9', 'a6654095-01b1-5811-b5bf-10de8a93387b', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 6, '10:00', '19:00'),
 ('b76ec815-ac23-5f99-8470-03cbb0448c37', 'b847aa53-8459-50b3-910d-dda29fd3956d', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 6, '10:00', '19:00'),
 ('4c09fd3b-9ffd-5806-8fd1-fa82a6fb12dd', '6a167b0e-b48e-57f9-b71e-d3d5dd1fb17a', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 6, '10:00', '19:00'),
 ('17bcb2e0-24f1-5d6d-8362-3786182e3162', '1fb8e222-b97b-5934-9005-b92fb1cc59e1', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 6, '10:00', '19:00'),
 ('02c14dae-9949-54a6-b31b-5aff74694e60', '5325ee17-f63a-5c25-90bf-8526536f0d28', '45c14a27-8a56-56a6-8d00-3f7f75b24e1b', 3, '09:00', '15:00')
ON CONFLICT (id) DO NOTHING;

-- Puestos (los abiertos traen su ubicación del día)
INSERT INTO public.puestos (id, id_vendedor, id_tianguis, nombre, codigo, descripcion, estado, latitud, longitud, fecha_apertura) VALUES
 ('a75ae15e-6486-5245-b50e-8d4fdd5cb2de', 'a6654095-01b1-5811-b5bf-10de8a93387b', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 'Vinilos El Disco Rayado', 'A-01', 'Vinilos, casetes y tornamesas. Cambios y compra de colecciones.', 'abierto', 20.6602, -103.3518, now() - interval '1 hour'),
 ('7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', 'b847aa53-8459-50b3-910d-dda29fd3956d', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 'Karma Paca Vintage', 'A-07', 'Chamarras, playeras y mezclilla seleccionada.', 'abierto', 20.6599, -103.3512, now() - interval '1 hour'),
 ('82649ce1-3d25-5bfc-b712-a966d794b246', '6a167b0e-b48e-57f9-b71e-d3d5dd1fb17a', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 'Zines y Más', 'B-03', 'Zines, novela gráfica y pósters de autores locales.', 'abierto', 20.6597, -103.352, now() - interval '1 hour'),
 ('3a287ea6-8f47-5dbd-b98e-32212573c983', '1fb8e222-b97b-5934-9005-b92fb1cc59e1', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 'Antojitos Doña Lupe', 'C-12', 'Tamales, aguas frescas y antojitos para recorrer el tianguis.', 'abierto', 20.6604, -103.351, now() - interval '1 hour'),
 ('b3410e7a-a430-5752-ba77-11630376a747', '6a167b0e-b48e-57f9-b71e-d3d5dd1fb17a', '9418e626-2b24-5a83-a6ca-6329c953fd5b', 'Cacharros Retro', 'B-09', 'Coleccionables y juguetes de los 90. Hoy cerrado.', 'cerrado', NULL, NULL, NULL),
 ('923414e7-417c-5945-a267-52a250a0eadd', '5325ee17-f63a-5c25-90bf-8526536f0d28', '45c14a27-8a56-56a6-8d00-3f7f75b24e1b', 'Chip & Cable', 'D-02', 'Cables, kits de componentes y placas compatibles con Arduino.', 'abierto', 20.6557, -103.3257, now() - interval '1 hour'),
 ('f8de5a4b-3a2f-5ba1-970a-5ba02d4993e0', '5325ee17-f63a-5c25-90bf-8526536f0d28', '45c14a27-8a56-56a6-8d00-3f7f75b24e1b', 'Pan Casero de Mari', 'D-05', 'Pan de elote, conchas y galletas hechas en casa.', 'cerrado', NULL, NULL, NULL)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.jornadas_puesto (id, id_puesto, fecha_apertura, latitud, longitud, precision_m) VALUES
 ('b6a10187-78bd-5194-b152-7dab23b3f571', 'a75ae15e-6486-5245-b50e-8d4fdd5cb2de', now() - interval '1 hour', 20.6602, -103.3518, 5),
 ('a683c07c-20db-52e9-a7a0-c3f26c707551', '7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', now() - interval '1 hour', 20.6599, -103.3512, 5),
 ('27ddbf80-3e1e-5f90-aac9-fee374ad2964', '82649ce1-3d25-5bfc-b712-a966d794b246', now() - interval '1 hour', 20.6597, -103.352, 5),
 ('7719615f-9296-5cf8-8394-77087ab0dabf', '3a287ea6-8f47-5dbd-b98e-32212573c983', now() - interval '1 hour', 20.6604, -103.351, 5),
 ('c20e1cb6-d9a6-598b-8fab-242e5d4b721c', '923414e7-417c-5945-a267-52a250a0eadd', now() - interval '1 hour', 20.6557, -103.3257, 5)
ON CONFLICT (id) DO NOTHING;

-- Productos
INSERT INTO public.productos (id, id_vendedor, id_puesto, id_categoria, nombre, descripcion, estado_articulo, precio_referencia, cantidad_disponible) VALUES
 ('23dcb788-4897-5573-a07c-f37bc849d3d3', 'a6654095-01b1-5811-b5bf-10de8a93387b', 'a75ae15e-6486-5245-b50e-8d4fdd5cb2de', (SELECT id FROM public.categorias WHERE nombre = 'Música y vinilos' ORDER BY id LIMIT 1), 'Disco de vinilo de rock mexicano', 'Edición de los 70, buen estado.', 'usado', 250, 3),
 ('9e03dc2b-eada-5161-b075-434799e1c904', 'a6654095-01b1-5811-b5bf-10de8a93387b', 'a75ae15e-6486-5245-b50e-8d4fdd5cb2de', (SELECT id FROM public.categorias WHERE nombre = 'Música y vinilos' ORDER BY id LIMIT 1), 'Tornamesa portátil', 'Revisada y funcionando, con bocinas integradas.', 'reacondicionado', 1200, 1),
 ('aa9f6a01-910c-5af6-b90c-35aa957fd84f', 'a6654095-01b1-5811-b5bf-10de8a93387b', 'a75ae15e-6486-5245-b50e-8d4fdd5cb2de', (SELECT id FROM public.categorias WHERE nombre = 'Ropa y accesorios' ORDER BY id LIMIT 1), 'Playera de banda local', 'Serigrafía hecha a mano.', 'nuevo', 180, 10),
 ('1c14f113-b4b6-51c6-82fc-598bace17f9d', 'b847aa53-8459-50b3-910d-dda29fd3956d', '7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', (SELECT id FROM public.categorias WHERE nombre = 'Ropa y accesorios' ORDER BY id LIMIT 1), 'Chamarra de mezclilla vintage', 'Tallas M y L.', 'usado', 350, 2),
 ('201b0ad6-f3fd-5c4a-9cee-fcbe3bbb1b50', 'b847aa53-8459-50b3-910d-dda29fd3956d', '7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', (SELECT id FROM public.categorias WHERE nombre = 'Ropa y accesorios' ORDER BY id LIMIT 1), 'Playera oversize de paca', 'Varios colores.', 'usado', 90, 15),
 ('96d0cba5-0876-500b-a842-a90a449e87e7', 'b847aa53-8459-50b3-910d-dda29fd3956d', '7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', (SELECT id FROM public.categorias WHERE nombre = 'Ropa y accesorios' ORDER BY id LIMIT 1), 'Gorra bordada', 'Bordado artesanal.', 'nuevo', 120, 6),
 ('ab049a1a-25df-58c5-b663-14f20c9d9f20', '6a167b0e-b48e-57f9-b71e-d3d5dd1fb17a', '82649ce1-3d25-5bfc-b712-a966d794b246', (SELECT id FROM public.categorias WHERE nombre = 'Libros y zines' ORDER BY id LIMIT 1), 'Zine ilustrado, edición limitada', 'Autoría local, 24 páginas.', 'nuevo', 60, 20),
 ('9459f7a2-7104-521f-8057-dc4401aae98a', '6a167b0e-b48e-57f9-b71e-d3d5dd1fb17a', '82649ce1-3d25-5bfc-b712-a966d794b246', (SELECT id FROM public.categorias WHERE nombre = 'Libros y zines' ORDER BY id LIMIT 1), 'Novela gráfica independiente', 'Primera edición.', 'nuevo', 220, 5),
 ('fafc8aa3-32df-5891-95a2-45e5af967b9a', '6a167b0e-b48e-57f9-b71e-d3d5dd1fb17a', 'b3410e7a-a430-5752-ba77-11630376a747', (SELECT id FROM public.categorias WHERE nombre = 'Coleccionables' ORDER BY id LIMIT 1), 'Figura coleccionable de los 90', 'Sin caja, en buen estado.', 'usado', 400, 1),
 ('07bddc60-4371-53fc-9951-ae686bd3c785', '6a167b0e-b48e-57f9-b71e-d3d5dd1fb17a', 'b3410e7a-a430-5752-ba77-11630376a747', (SELECT id FROM public.categorias WHERE nombre = 'Coleccionables' ORDER BY id LIMIT 1), 'Sobre de cartas coleccionables', 'Sellado.', 'nuevo', 50, 12),
 ('f1faf72c-00d2-52ee-97e6-759c12869b68', '1fb8e222-b97b-5934-9005-b92fb1cc59e1', '3a287ea6-8f47-5dbd-b98e-32212573c983', (SELECT id FROM public.categorias WHERE nombre = 'Alimentos' ORDER BY id LIMIT 1), 'Tamales de rajas (docena)', 'Hechos esta mañana.', 'nuevo', 180, 8),
 ('4985df02-27df-560e-8aa7-17b3cb09d76c', '1fb8e222-b97b-5934-9005-b92fb1cc59e1', '3a287ea6-8f47-5dbd-b98e-32212573c983', (SELECT id FROM public.categorias WHERE nombre = 'Alimentos' ORDER BY id LIMIT 1), 'Agua de jamaica (1 litro)', 'Sin conservadores.', 'nuevo', 35, 15),
 ('fd59a2cc-8fef-5996-a616-1579d8f78be5', '5325ee17-f63a-5c25-90bf-8526536f0d28', '923414e7-417c-5945-a267-52a250a0eadd', (SELECT id FROM public.categorias WHERE nombre = 'Electrónica' ORDER BY id LIMIT 1), 'Cable HDMI de 2 metros', 'Nuevo.', 'nuevo', 90, 10),
 ('2d24f4a8-0d74-5567-a3dd-c32d196169a8', '5325ee17-f63a-5c25-90bf-8526536f0d28', '923414e7-417c-5945-a267-52a250a0eadd', (SELECT id FROM public.categorias WHERE nombre = 'Electrónica' ORDER BY id LIMIT 1), 'Kit de 600 resistencias', 'Valores surtidos.', 'nuevo', 150, 7),
 ('2fa37694-5b57-5899-be8b-0efe017683b0', '5325ee17-f63a-5c25-90bf-8526536f0d28', '923414e7-417c-5945-a267-52a250a0eadd', (SELECT id FROM public.categorias WHERE nombre = 'Electrónica' ORDER BY id LIMIT 1), 'Placa compatible con Arduino Uno', 'Con cable USB.', 'nuevo', 260, 4),
 ('a52fa3fa-f260-5f71-aff8-2c00ff6c4733', '5325ee17-f63a-5c25-90bf-8526536f0d28', 'f8de5a4b-3a2f-5ba1-970a-5ba02d4993e0', (SELECT id FROM public.categorias WHERE nombre = 'Alimentos' ORDER BY id LIMIT 1), 'Pan de elote', 'Por rebanada o entero.', 'nuevo', 45, 10),
 ('b67f312a-622e-5a6e-adc0-3f66992b5e41', '5325ee17-f63a-5c25-90bf-8526536f0d28', 'f8de5a4b-3a2f-5ba1-970a-5ba02d4993e0', (SELECT id FROM public.categorias WHERE nombre = 'Alimentos' ORDER BY id LIMIT 1), 'Conchas artesanales (6 piezas)', 'Vainilla y chocolate.', 'nuevo', 70, 9)
ON CONFLICT (id) DO NOTHING;

-- Ofertas activas
INSERT INTO public.ofertas (id, id_producto, titulo, descuento, precio_promocional, fecha_fin) VALUES
 ('76de1f0d-3b68-5c49-968e-74bbb0f245f4', '1c14f113-b4b6-51c6-82fc-598bace17f9d', 'Liquidación del sábado', 20, NULL, now() + interval '3 days'),
 ('7bfc422d-5e5c-559d-8469-86655e7aea32', '23dcb788-4897-5573-a07c-f37bc849d3d3', 'Disco a precio especial', NULL, 200, now() + interval '2 days')
ON CONFLICT (id) DO NOTHING;

-- Visitas confirmadas y calificaciones (para promedios y la marca Destacado)
INSERT INTO public.visitas (id, id_usuario, id_puesto, id_jornada) VALUES
 ('27ce2edd-f6ef-526d-ae1a-0f8c18a50e20', '0e6776f8-699f-562b-a850-f763cd1db97f', 'a75ae15e-6486-5245-b50e-8d4fdd5cb2de', 'b6a10187-78bd-5194-b152-7dab23b3f571'),
 ('d28f0c2c-406d-580b-b8b0-56e80a7e4f02', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', 'a75ae15e-6486-5245-b50e-8d4fdd5cb2de', 'b6a10187-78bd-5194-b152-7dab23b3f571'),
 ('f2987c33-177c-57cc-a0a3-06ad230717df', '922ec138-e996-51af-8328-3dcdf10f9382', 'a75ae15e-6486-5245-b50e-8d4fdd5cb2de', 'b6a10187-78bd-5194-b152-7dab23b3f571'),
 ('f0fd295e-eac3-55d5-ae1a-c564e870481c', 'eca83eed-5636-5d46-bc55-aa638cc56a63', 'a75ae15e-6486-5245-b50e-8d4fdd5cb2de', 'b6a10187-78bd-5194-b152-7dab23b3f571'),
 ('752d6c40-7ff8-5afb-981b-0ffcf5356a3b', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', 'a75ae15e-6486-5245-b50e-8d4fdd5cb2de', 'b6a10187-78bd-5194-b152-7dab23b3f571'),
 ('a687271a-62e1-5d96-bce7-e56fce74413a', '0e6776f8-699f-562b-a850-f763cd1db97f', '7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', 'a683c07c-20db-52e9-a7a0-c3f26c707551'),
 ('411b44d5-478c-586a-80d9-1a4fe47e5758', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', '7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', 'a683c07c-20db-52e9-a7a0-c3f26c707551'),
 ('41723427-c65b-58bd-bd92-cac505ee2f40', '922ec138-e996-51af-8328-3dcdf10f9382', '7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', 'a683c07c-20db-52e9-a7a0-c3f26c707551'),
 ('118dc173-e8c7-50cc-911c-38ca5594f0bf', 'eca83eed-5636-5d46-bc55-aa638cc56a63', '7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', 'a683c07c-20db-52e9-a7a0-c3f26c707551'),
 ('20598169-cea0-5523-a05c-e0a0075f280f', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', '7df21a5a-8d10-5e3c-9cc3-03eda1ae5e7a', 'a683c07c-20db-52e9-a7a0-c3f26c707551'),
 ('9d16c719-fe96-53c4-a7f9-4f5099057c70', '0e6776f8-699f-562b-a850-f763cd1db97f', '82649ce1-3d25-5bfc-b712-a966d794b246', '27ddbf80-3e1e-5f90-aac9-fee374ad2964'),
 ('796aeef2-62ef-53c4-adfb-60ff0cf52d37', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', '82649ce1-3d25-5bfc-b712-a966d794b246', '27ddbf80-3e1e-5f90-aac9-fee374ad2964'),
 ('b96015de-daad-52b5-9d39-70bb44400ddb', '922ec138-e996-51af-8328-3dcdf10f9382', '82649ce1-3d25-5bfc-b712-a966d794b246', '27ddbf80-3e1e-5f90-aac9-fee374ad2964'),
 ('703b0669-076e-5cd3-a8e4-8cd7578c578c', 'eca83eed-5636-5d46-bc55-aa638cc56a63', '82649ce1-3d25-5bfc-b712-a966d794b246', '27ddbf80-3e1e-5f90-aac9-fee374ad2964'),
 ('bfcc8d53-5d1e-5c46-acac-4ef0f0dfdc28', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', '82649ce1-3d25-5bfc-b712-a966d794b246', '27ddbf80-3e1e-5f90-aac9-fee374ad2964'),
 ('e4658173-74be-5acb-8c82-c9a83063b374', '0e6776f8-699f-562b-a850-f763cd1db97f', '3a287ea6-8f47-5dbd-b98e-32212573c983', '7719615f-9296-5cf8-8394-77087ab0dabf'),
 ('e303c847-9149-5499-9bd5-6e9a0241192b', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', '3a287ea6-8f47-5dbd-b98e-32212573c983', '7719615f-9296-5cf8-8394-77087ab0dabf'),
 ('5ceecedf-1255-5813-8edc-17fa6dc53a1a', '922ec138-e996-51af-8328-3dcdf10f9382', '3a287ea6-8f47-5dbd-b98e-32212573c983', '7719615f-9296-5cf8-8394-77087ab0dabf'),
 ('2e20419d-289c-516f-a061-12131cd13b2b', 'eca83eed-5636-5d46-bc55-aa638cc56a63', '3a287ea6-8f47-5dbd-b98e-32212573c983', '7719615f-9296-5cf8-8394-77087ab0dabf'),
 ('eab94da0-cb58-572f-aaf9-90e1fca59ba2', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', '3a287ea6-8f47-5dbd-b98e-32212573c983', '7719615f-9296-5cf8-8394-77087ab0dabf'),
 ('aa58f30b-e5dd-5371-8bac-00b629f93abc', '0e6776f8-699f-562b-a850-f763cd1db97f', '923414e7-417c-5945-a267-52a250a0eadd', 'c20e1cb6-d9a6-598b-8fab-242e5d4b721c'),
 ('9a8d1db1-64bf-54f9-a9ab-3bdf36baad5d', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', '923414e7-417c-5945-a267-52a250a0eadd', 'c20e1cb6-d9a6-598b-8fab-242e5d4b721c'),
 ('b734ccc9-f487-52f6-a3f1-a75176e7a0d9', '922ec138-e996-51af-8328-3dcdf10f9382', '923414e7-417c-5945-a267-52a250a0eadd', 'c20e1cb6-d9a6-598b-8fab-242e5d4b721c'),
 ('b9758c67-1a0a-570c-a0d5-b2de2daede7d', 'eca83eed-5636-5d46-bc55-aa638cc56a63', '923414e7-417c-5945-a267-52a250a0eadd', 'c20e1cb6-d9a6-598b-8fab-242e5d4b721c'),
 ('3df609da-8f68-5793-ba73-e249d9b3b8f2', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', '923414e7-417c-5945-a267-52a250a0eadd', 'c20e1cb6-d9a6-598b-8fab-242e5d4b721c')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.calificaciones (id_visita, id_usuario, puntuacion) VALUES
 ('27ce2edd-f6ef-526d-ae1a-0f8c18a50e20', '0e6776f8-699f-562b-a850-f763cd1db97f', 5),
 ('d28f0c2c-406d-580b-b8b0-56e80a7e4f02', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', 5),
 ('f2987c33-177c-57cc-a0a3-06ad230717df', '922ec138-e996-51af-8328-3dcdf10f9382', 5),
 ('f0fd295e-eac3-55d5-ae1a-c564e870481c', 'eca83eed-5636-5d46-bc55-aa638cc56a63', 5),
 ('752d6c40-7ff8-5afb-981b-0ffcf5356a3b', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', 5),
 ('a687271a-62e1-5d96-bce7-e56fce74413a', '0e6776f8-699f-562b-a850-f763cd1db97f', 4),
 ('411b44d5-478c-586a-80d9-1a4fe47e5758', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', 5),
 ('41723427-c65b-58bd-bd92-cac505ee2f40', '922ec138-e996-51af-8328-3dcdf10f9382', 4),
 ('118dc173-e8c7-50cc-911c-38ca5594f0bf', 'eca83eed-5636-5d46-bc55-aa638cc56a63', 4),
 ('20598169-cea0-5523-a05c-e0a0075f280f', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', 5),
 ('9d16c719-fe96-53c4-a7f9-4f5099057c70', '0e6776f8-699f-562b-a850-f763cd1db97f', 5),
 ('796aeef2-62ef-53c4-adfb-60ff0cf52d37', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', 4),
 ('b96015de-daad-52b5-9d39-70bb44400ddb', '922ec138-e996-51af-8328-3dcdf10f9382', 5),
 ('703b0669-076e-5cd3-a8e4-8cd7578c578c', 'eca83eed-5636-5d46-bc55-aa638cc56a63', 4),
 ('bfcc8d53-5d1e-5c46-acac-4ef0f0dfdc28', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', 4),
 ('e4658173-74be-5acb-8c82-c9a83063b374', '0e6776f8-699f-562b-a850-f763cd1db97f', 4),
 ('e303c847-9149-5499-9bd5-6e9a0241192b', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', 4),
 ('5ceecedf-1255-5813-8edc-17fa6dc53a1a', '922ec138-e996-51af-8328-3dcdf10f9382', 5),
 ('2e20419d-289c-516f-a061-12131cd13b2b', 'eca83eed-5636-5d46-bc55-aa638cc56a63', 5),
 ('eab94da0-cb58-572f-aaf9-90e1fca59ba2', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', 4),
 ('aa58f30b-e5dd-5371-8bac-00b629f93abc', '0e6776f8-699f-562b-a850-f763cd1db97f', 5),
 ('9a8d1db1-64bf-54f9-a9ab-3bdf36baad5d', 'eb4bd4d2-00ce-5e1d-800e-4ba7fe708ff6', 4),
 ('b734ccc9-f487-52f6-a3f1-a75176e7a0d9', '922ec138-e996-51af-8328-3dcdf10f9382', 5),
 ('b9758c67-1a0a-570c-a0d5-b2de2daede7d', 'eca83eed-5636-5d46-bc55-aa638cc56a63', 4),
 ('3df609da-8f68-5793-ba73-e249d9b3b8f2', 'fe6e905e-e9f3-5cd3-921e-6719746a177d', 5)
ON CONFLICT DO NOTHING;

COMMIT;

-- Después de ejecutarlo, en la app:
--  * Mapa de puestos: elige "Tianguis Cultural de Guadalajara"; salen 4 puestos abiertos y las 3 zonas dibujadas.
--  * Los puestos abiertos tienen ubicación, calificaciones y productos; el de Vinilos suele salir como Destacado.
--
-- Para corregir la ubicación del Tianguis Cultural con la real, ajusta latitud y longitud:
--   UPDATE public.tianguis SET latitud = 20.XXXX, longitud = -103.XXXX WHERE nombre = 'Tianguis Cultural de Guadalajara';
