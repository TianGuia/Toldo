begin;

insert into auth.users (id, email, is_anonymous) values
 ('26000000-0000-0000-0000-000000000001', 'cierre-vendedor@example.test', false),
 ('26000000-0000-0000-0000-000000000002', 'cierre-comprador@example.test', false),
 ('26000000-0000-0000-0000-000000000003', 'cierre-admin@example.test', false);
select public.admin_configurar_credenciales('admin cierre', 'clave-sintetica', 'respuesta prueba');
insert into public.perfiles_vendedor (id, id_usuario) values
 ('26000000-0000-0000-0000-000000000011', '26000000-0000-0000-0000-000000000001'),
 ('26000000-0000-0000-0000-000000000012', '26000000-0000-0000-0000-000000000002');
insert into public.tianguis (id, nombre)
values ('26000000-0000-0000-0000-000000000021', 'Mercado Auditoría');
insert into public.vendedor_tianguis (id_vendedor, id_tianguis)
values ('26000000-0000-0000-0000-000000000011', '26000000-0000-0000-0000-000000000021');
insert into public.puestos (id, id_vendedor, id_tianguis, nombre)
values ('26000000-0000-0000-0000-000000000031', '26000000-0000-0000-0000-000000000011', 'Puesto Auditoría');
insert into public.productos (id, id_vendedor, id_puesto, nombre, cantidad_disponible)
values ('26000000-0000-0000-0000-000000000041', '26000000-0000-0000-0000-000000000011',
        '26000000-0000-0000-0000-000000000031', 'Producto Auditoría', 2);
insert into public.anuncios_espacio (id, id_vendedor, id_tianguis, rol, acuerdo, titulo)
values ('26000000-0000-0000-0000-000000000051', '26000000-0000-0000-0000-000000000011',
        '26000000-0000-0000-0000-000000000021', 'ofrece', 'renta', 'Anuncio Auditoría');

do $$ begin
  if has_column_privilege('authenticated', 'public.productos', 'moderado', 'UPDATE')
     or has_column_privilege('authenticated', 'public.anuncios_espacio', 'moderado', 'UPDATE')
     or has_column_privilege('authenticated', 'public.perfiles_vendedor', 'estado', 'UPDATE')
     or has_column_privilege('authenticated', 'public.apartados', 'fecha_expiracion', 'UPDATE') then
    raise exception 'Siguen editables campos que administra el servidor';
  end if;
  if not has_column_privilege('authenticated', 'public.productos', 'actualizado_en', 'UPDATE') then
    raise exception 'La beta publicada debe poder seguir editando sus productos';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '26000000-0000-0000-0000-000000000002', true);
insert into public.apartados (id, id_comprador, id_producto, cantidad)
values
 ('26000000-0000-0000-0000-000000000061', auth.uid(), '26000000-0000-0000-0000-000000000041', 1),
 ('26000000-0000-0000-0000-000000000062', auth.uid(), '26000000-0000-0000-0000-000000000041', 1);
insert into public.reportes (id, id_reportante, tipo_objetivo, id_objetivo, id_usuario_reportado, motivo)
values ('26000000-0000-0000-0000-000000000071', auth.uid(), 'producto',
        '26000000-0000-0000-0000-000000000041', '26000000-0000-0000-0000-000000000003', 'Auditoría');

select set_config('request.jwt.claim.sub', '26000000-0000-0000-0000-000000000001', true);
select public.responder_apartado('26000000-0000-0000-0000-000000000061', 'aceptar');
select public.responder_apartado('26000000-0000-0000-0000-000000000062', 'aceptar');
do $$ begin
  if not exists (select 1 from public.productos where cantidad_disponible = 0
      and disponibilidad_manual and not disponible) then
    raise exception 'Agotar el inventario debe mantener la intención del vendedor';
  end if;
end $$;
update public.productos set disponibilidad_manual = false
where id = '26000000-0000-0000-0000-000000000041';
select public.responder_apartado('26000000-0000-0000-0000-000000000061', 'cancelar');
reset role;

update public.apartados set fecha_expiracion = now() - interval '1 minute'
where id = '26000000-0000-0000-0000-000000000062';
select public.vencer_pendientes();
do $$ begin
  if not exists (select 1 from public.productos where cantidad_disponible = 2
      and not disponibilidad_manual and not disponible) then
    raise exception 'Restituir inventario debe respetar la pausa manual';
  end if;
end $$;
update public.tianguis set activo = false where id = '26000000-0000-0000-0000-000000000021';

set local role authenticated;
select set_config('request.jwt.claim.sub', '26000000-0000-0000-0000-000000000002', true);
do $$ begin
  if exists (select 1 from public.anuncios_espacio) then
    raise exception 'Un anuncio de un tianguis desactivado salió en el catálogo de espacios';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '26000000-0000-0000-0000-000000000001', true);
do $$ begin
  if not exists (select 1 from public.anuncios_espacio) then
    raise exception 'El dueño perdió la opción de cerrar o mover su anuncio';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '26000000-0000-0000-0000-000000000003', true);
select public.admin_entrar('admin cierre', 'clave-sintetica', 'respuesta prueba');
reset role;
create function pg_temp.fallar_cierre_reporte() returns trigger
language plpgsql as $$
begin
  raise exception 'Fallo simulado al cerrar el reporte' using errcode = 'check_violation';
end $$;
create trigger prueba_fallar_cierre before update on public.reportes
  for each row execute function pg_temp.fallar_cierre_reporte();
set local role authenticated;
do $$ begin
  begin
    perform public.admin_resolver_reporte('26000000-0000-0000-0000-000000000071',
      'ocultar_contenido', 'Medida de prueba');
    raise exception 'El fallo simulado no ocurrió';
  exception when check_violation then null;
  end;
  if exists (select 1 from public.medidas_moderacion where id_reporte = '26000000-0000-0000-0000-000000000071') then
    raise exception 'Quedó una medida a pesar de fallar el cierre';
  end if;
end $$;
reset role;
drop trigger prueba_fallar_cierre on public.reportes;
set local role authenticated;
select public.admin_resolver_reporte('26000000-0000-0000-0000-000000000071', 'ocultar_contenido', 'Medida de prueba');
do $$ begin
  if not exists (
    select 1 from public.reportes r join public.medidas_moderacion m on m.id_reporte = r.id
    where r.estado = 'resuelto' and r.id_usuario_reportado = '26000000-0000-0000-0000-000000000001'
      and m.id_usuario_afectado = r.id_usuario_reportado
  ) then raise exception 'El cierre y la medida deben usar al dueño real'; end if;
  begin
    perform public.admin_resolver_reporte('26000000-0000-0000-0000-000000000071', 'ocultar_contenido', 'Reintento');
    raise exception 'Se permitió resolver dos veces';
  exception when raise_exception then
    if sqlerrm <> 'El reporte ya fue resuelto' then raise; end if;
  end;
end $$;

select public.admin_cambiar_estado_cuenta('26000000-0000-0000-0000-000000000001', 'suspendida', 'Auditoría');
select set_config('request.jwt.claim.sub', '26000000-0000-0000-0000-000000000001', true);
do $$ begin
  update public.productos set nombre = 'Cambio de prueba' where id = '26000000-0000-0000-0000-000000000041';
  if found or public.puede_operar_vendedor('26000000-0000-0000-0000-000000000011') then
    raise exception 'Una cuenta suspendida conserva acceso de escritura de vendedor';
  end if;
end $$;
rollback;
