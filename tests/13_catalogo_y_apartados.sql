begin;

insert into auth.users (id, email, raw_user_meta_data, is_anonymous) values
  ('24000000-0000-0000-0000-000000000001', 'catalogo-vendedor@example.test', '{"nombre_publico":"Nombre público de prueba"}', false),
  ('24000000-0000-0000-0000-000000000002', 'catalogo-comprador@example.test', '{"nombre_publico":"Comprador de prueba"}', false);
insert into public.perfiles_vendedor (id, id_usuario)
values ('24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000001');
insert into public.tianguis (id, nombre) values
  ('24000000-0000-0000-0000-000000000021', 'Tianguis A'),
  ('24000000-0000-0000-0000-000000000022', 'Tianguis B'),
  ('24000000-0000-0000-0000-000000000023', 'Tianguis C');
insert into public.vendedor_tianguis (id_vendedor, id_tianguis)
select '24000000-0000-0000-0000-000000000010', id from public.tianguis where nombre in ('Tianguis A', 'Tianguis B', 'Tianguis C');
insert into public.vendedor_horarios (id_vendedor, id_tianguis, dia_semana, hora_inicio, hora_fin) values
  ('24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000021', 1, '09:00', '13:00'),
  ('24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000022', 2, '09:00', '13:00');
insert into public.tianguis_horarios (id_tianguis, dia_semana, hora_inicio, hora_fin) values
  ('24000000-0000-0000-0000-000000000022', 1, '09:00', '13:00'),
  ('24000000-0000-0000-0000-000000000023', 1, '09:00', '13:00');
insert into public.puestos (id, id_vendedor, id_tianguis, nombre) values
  ('24000000-0000-0000-0000-000000000031', '24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000021', 'Puesto A'),
  ('24000000-0000-0000-0000-000000000032', '24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000022', 'Puesto B'),
  ('24000000-0000-0000-0000-000000000033', '24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000023', 'Puesto C');
insert into public.productos (id, id_vendedor, id_puesto, nombre, cantidad_disponible, disponible, moderado) values
  ('24000000-0000-0000-0000-000000000041', '24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000031', 'Producto A', 2, true, false),
  ('24000000-0000-0000-0000-000000000042', '24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000032', 'Producto B', 2, true, false),
  ('24000000-0000-0000-0000-000000000043', '24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000033', 'Producto C', null, true, false),
  ('24000000-0000-0000-0000-000000000044', '24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000031', 'Sin stock', 0, true, false),
  ('24000000-0000-0000-0000-000000000045', '24000000-0000-0000-0000-000000000010', '24000000-0000-0000-0000-000000000031', 'Oculto', 2, true, true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '24000000-0000-0000-0000-000000000002', true);
do $$ begin
  if (select array_agg(nombre order by nombre) from public.productos_catalogo(null, 1))
      is distinct from array['Producto A', 'Producto C']
     or exists (select 1 from public.productos_catalogo('24000000-0000-0000-0000-000000000022', 1))
     or (select nombre from public.productos_catalogo('24000000-0000-0000-0000-000000000022', 2)) <> 'Producto B' then
    raise exception 'El filtro debe combinar el tianguis y la jornada, con horario general de respaldo';
  end if;
  if public.nombre_vendedor_producto('24000000-0000-0000-0000-000000000041')
      is distinct from 'Nombre público de prueba'
     or public.nombre_vendedor_producto('24000000-0000-0000-0000-000000000045') is not null then
    raise exception 'El nombre debe corresponder a un vendedor de un producto publicado';
  end if;
  begin
    insert into public.apartados (id_comprador, id_producto, cantidad)
    select id_comprador, '24000000-0000-0000-0000-000000000044', 1 from public.compradores where id_usuario = auth.uid();
    raise exception 'Se permitió solicitar un producto sin stock';
  exception when check_violation then
    if sqlerrm <> 'No hay suficientes piezas disponibles' then raise; end if;
  end;
  begin
    insert into public.apartados (id_comprador, id_producto, cantidad)
    select id_comprador, '24000000-0000-0000-0000-000000000045', 1 from public.compradores where id_usuario = auth.uid();
    raise exception 'Se permitió solicitar un producto moderado';
  exception when check_violation then
    if sqlerrm <> 'Este producto no está disponible para apartar' then raise; end if;
  end;
end $$;

insert into public.apartados (id, id_comprador, id_producto, cantidad)
select '24000000-0000-0000-0000-000000000051', id_comprador, '24000000-0000-0000-0000-000000000043', 1
from public.compradores where id_usuario = auth.uid();
reset role;

update public.productos set disponible = false where id = '24000000-0000-0000-0000-000000000043';
set local role authenticated;
select set_config('request.jwt.claim.sub', '24000000-0000-0000-0000-000000000001', true);
do $$ begin
  begin
    perform public.responder_apartado('24000000-0000-0000-0000-000000000051', 'aceptar');
    raise exception 'Se aceptó un producto que dejó de estar disponible';
  exception when check_violation then
    if sqlerrm <> 'Este producto no está disponible para apartar' then raise; end if;
  end;
  if (select estado from public.apartados where id = '24000000-0000-0000-0000-000000000051')
      is distinct from 'pendiente'::public.estado_apartado then
    raise exception 'La solicitud debe seguir pendiente';
  end if;
end $$;
rollback;
