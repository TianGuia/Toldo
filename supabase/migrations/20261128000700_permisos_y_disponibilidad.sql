-- RNF-3. El permiso de operación exige la cuenta activa además del perfil activo.
create function public.puede_operar_vendedor(p_id uuid)
returns boolean
language sql stable set search_path = public
as $$
  select public.cuenta_activa() and public.soy_vendedor(p_id);
$$;
revoke all on function public.puede_operar_vendedor(uuid) from public, anon;
grant execute on function public.puede_operar_vendedor(uuid) to authenticated;

alter policy productos_update on public.productos
  using (public.puede_operar_vendedor(id_vendedor))
  with check (public.puede_operar_vendedor(id_vendedor));
alter policy productos_delete on public.productos
  using (public.puede_operar_vendedor(id_vendedor) or public.es_admin());
alter policy ofertas_write on public.ofertas
  using (public.puede_operar_vendedor(id_vendedor))
  with check (public.puede_operar_vendedor(id_vendedor));
alter policy anuncios_update on public.anuncios_espacio
  using (public.puede_operar_vendedor(id_vendedor))
  with check (public.puede_operar_vendedor(id_vendedor));
alter policy anuncios_delete on public.anuncios_espacio
  using (public.puede_operar_vendedor(id_vendedor) or public.es_admin());
alter policy puestos_insert on public.puestos
  with check (public.puede_operar_vendedor(id_vendedor));
alter policy puestos_update on public.puestos
  using (public.puede_operar_vendedor(id_vendedor) or public.es_admin())
  with check (public.puede_operar_vendedor(id_vendedor) or public.es_admin());
alter policy puestos_delete on public.puestos
  using (public.puede_operar_vendedor(id_vendedor) or public.es_admin());
alter policy pv_update on public.perfiles_vendedor
  using ((id_usuario = auth.uid() and public.cuenta_activa()) or public.es_admin())
  with check ((id_usuario = auth.uid() and public.cuenta_activa()) or public.es_admin());

alter policy imagenes_write on public.producto_imagenes
  using (exists (select 1 from public.productos p where p.id = id_producto
                 and public.puede_operar_vendedor(p.id_vendedor)))
  with check (exists (select 1 from public.productos p where p.id = id_producto
                      and public.puede_operar_vendedor(p.id_vendedor)));

-- RF-21. Conserva la última intención conocida de cada publicación existente.
alter table public.productos add column disponibilidad_manual boolean;
alter table public.productos disable trigger trg_productos_upd;
update public.productos set disponibilidad_manual = disponible;
alter table public.productos enable trigger trg_productos_upd;
alter table public.productos alter column disponibilidad_manual set not null;

create function public.sincronizar_disponibilidad_producto()
returns trigger
language plpgsql set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.disponibilidad_manual := coalesce(new.disponibilidad_manual, new.disponible);
  elsif new.disponibilidad_manual is not distinct from old.disponibilidad_manual
      and new.disponible is distinct from old.disponible then
    -- Las versiones anteriores escriben ambos campos al ajustar el inventario.
    if new.cantidad_disponible is not distinct from old.cantidad_disponible
        or new.cantidad_disponible is distinct from 0 then
      new.disponibilidad_manual := new.disponible;
    end if;
  end if;
  new.disponible := new.disponibilidad_manual
    and (new.cantidad_disponible is null or new.cantidad_disponible > 0);
  return new;
end;
$$;
revoke all on function public.sincronizar_disponibilidad_producto() from public, anon, authenticated;
create trigger productos_sincronizar_disponibilidad
  before insert or update of disponible, disponibilidad_manual, cantidad_disponible on public.productos
  for each row execute function public.sincronizar_disponibilidad_producto();

-- La aplicación escribe los campos de publicación y los RPC administran la moderación.
revoke insert, update on public.productos, public.anuncios_espacio, public.perfiles_vendedor from authenticated;
grant insert (id, id_vendedor, id_puesto, id_categoria, nombre, descripcion, estado_articulo,
              precio_referencia, cantidad_disponible, disponible, disponibilidad_manual, activo)
  on public.productos to authenticated;
grant update (id_puesto, id_categoria, nombre, descripcion, estado_articulo,
              precio_referencia, cantidad_disponible, disponible, disponibilidad_manual, activo, actualizado_en)
  on public.productos to authenticated;
grant insert (id, id_vendedor, id_tianguis, rol, acuerdo, titulo, descripcion, estado)
  on public.anuncios_espacio to authenticated;
grant update (id_tianguis, rol, acuerdo, titulo, descripcion, estado)
  on public.anuncios_espacio to authenticated;
grant insert (id, id_usuario, nombre_negocio, descripcion) on public.perfiles_vendedor to authenticated;
grant update (nombre_negocio, descripcion) on public.perfiles_vendedor to authenticated;

-- RF-27. Las transiciones y los vencimientos de una reserva se administran en servidor.
revoke update on public.apartados from authenticated;
alter table public.apartados alter column fecha_expiracion set default (now() + interval '24 hours');
alter policy apart_insert on public.apartados with check (
  id_comprador = auth.uid() and estado = 'pendiente' and public.cuenta_activa()
  and fecha_expiracion > now()
);
revoke execute on function public.expirar_apartados() from public, anon, authenticated;

create or replace function public.producto_para_apartado(p_id uuid, p_cantidad integer)
returns public.productos
language plpgsql set search_path = public
as $$
declare producto public.productos%rowtype;
begin
  select * into producto from public.productos where id = p_id for no key update;
  if not found or not producto.activo or producto.moderado or not producto.disponibilidad_manual then
    raise exception 'Este producto no está disponible para apartar' using errcode = '23514';
  end if;
  if p_cantidad is null or p_cantidad < 1 then
    raise exception 'La cantidad debe ser mayor que cero' using errcode = '23514';
  end if;
  if producto.cantidad_disponible < p_cantidad then
    raise exception 'No hay suficientes piezas disponibles' using errcode = '23514';
  end if;
  return producto;
end;
$$;

revoke all on function public.producto_para_apartado(uuid, integer) from public, anon, authenticated;

create or replace function public.validar_solicitud_apartado()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform public.producto_para_apartado(new.id_producto, new.cantidad);
  if new.estado = 'pendiente' then
    new.fecha_expiracion := least(new.fecha_expiracion, now() + interval '24 hours');
  end if;
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."abrir_puesto"("p_id_puesto" "uuid", "p_latitud" double precision, "p_longitud" double precision, "p_precision" real DEFAULT NULL::real) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_jornada uuid;
begin
  if not exists (select 1 from puestos p join perfiles_vendedor v on v.id = p.id_vendedor
                 where p.id = p_id_puesto and p.activo and public.puede_operar_vendedor(v.id)) then
    raise exception 'No autorizado para operar este puesto';
  end if;

  update jornadas_puesto set fecha_cierre = now()
   where id_puesto = p_id_puesto and fecha_cierre is null;

  insert into jornadas_puesto (id_puesto, latitud, longitud, precision_m)
  values (p_id_puesto, p_latitud, p_longitud, p_precision)
  returning id into v_jornada;

  update puestos
     set estado = 'abierto', latitud = p_latitud, longitud = p_longitud,
         fecha_apertura = now(), fecha_cierre = null
   where id = p_id_puesto;

  return v_jornada;
end $$;

CREATE OR REPLACE FUNCTION "public"."responder_apartado"("p_id" "uuid", "p_accion" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare r record; v_user_vendedor uuid; es_v boolean; es_c boolean; e text; v_cant integer;
begin
  select * into r from public.apartados where id = p_id for update;
  if not found then raise exception 'Apartado no encontrado'; end if;

  select id_usuario into v_user_vendedor from public.perfiles_vendedor where id = r.id_vendedor;
  es_v := (auth.uid() = v_user_vendedor);
  es_c := (auth.uid() = r.id_comprador);
  if not (coalesce(es_v, false) or coalesce(es_c, false)) then raise exception 'No participas en este apartado'; end if;
  e := r.estado::text;

  perform set_config('tianguia.rpc', '1', true);

  if p_accion = 'aceptar' then
    if not es_v or not public.puede_operar_vendedor(r.id_vendedor) then
      raise exception 'Solo un vendedor activo puede aceptar';
    end if;
    if e <> 'pendiente' then raise exception 'Este apartado ya fue respondido'; end if;
    if r.fecha_expiracion is not null and r.fecha_expiracion < now() then
      raise exception 'La solicitud ya venció';
    end if;
    select p.cantidad_disponible into v_cant
      from public.producto_para_apartado(r.id_producto, r.cantidad) p;
    if v_cant is not null then
      update public.productos
         set cantidad_disponible = v_cant - r.cantidad,
             actualizado_en = now()
       where id = r.id_producto;
    end if;
    -- el apartado aceptado dura 24 h a partir de que el vendedor acepta
    update public.apartados set estado = 'aceptado', fecha_expiracion = now() + interval '24 hours'
     where id = p_id;

  elsif p_accion = 'rechazar' then
    if not es_v then raise exception 'Solo el vendedor puede rechazar'; end if;
    if e <> 'pendiente' then raise exception 'Este apartado ya fue respondido'; end if;
    update public.apartados set estado = 'rechazado' where id = p_id;

  elsif p_accion = 'cancelar' then
    if not ((es_c and e in ('pendiente', 'aceptado')) or (es_v and e = 'aceptado')) then
      raise exception 'No se puede cancelar en este estado';
    end if;
    if e = 'aceptado' then
      update public.productos
         set cantidad_disponible = cantidad_disponible + r.cantidad,
             actualizado_en = now()
       where id = r.id_producto and cantidad_disponible is not null;
    end if;
    update public.apartados set estado = 'cancelado' where id = p_id;

  else
    raise exception 'Acción no válida: %', p_accion;
  end if;
end $$;

CREATE OR REPLACE FUNCTION "public"."vencer_pendientes"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare a record;
begin
  perform set_config('tianguia.rpc', '1', true);

  for a in
    select id, id_producto, cantidad, estado::text as e from public.apartados
     where estado::text in ('pendiente', 'aceptado')
       and fecha_expiracion is not null and fecha_expiracion < now()
     for update
  loop
    if a.e = 'aceptado' then
      update public.productos
         set cantidad_disponible = cantidad_disponible + a.cantidad,
             actualizado_en = now()
       where id = a.id_producto and cantidad_disponible is not null;
    end if;
    update public.apartados set estado = 'expirado' where id = a.id;
  end loop;

  update public.ofertas set estado = 'finalizada'
   where estado::text = 'activa' and fecha_fin < now();
end $$;
