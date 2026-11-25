-- RF-02. La jornada del vendedor corresponde al tianguis del puesto.
create function public.productos_catalogo(p_tianguis uuid, p_dia integer)
returns setof public.productos
language sql stable security invoker set search_path = public
as $$
  select pr.*
  from public.productos pr
  join public.puestos pu on pu.id = pr.id_puesto and pu.activo
  join public.tianguis t on t.id = pu.id_tianguis and t.activo
  where pr.activo and not pr.moderado and pr.disponible
    and (pr.cantidad_disponible is null or pr.cantidad_disponible > 0)
    and (p_tianguis is null or t.id = p_tianguis)
    and (p_dia is null or exists (
      select 1 from public.vendedor_horarios h
      where h.id_vendedor = pr.id_vendedor and h.id_tianguis = t.id and h.dia_semana = p_dia
    ) or (
      not exists (
        select 1 from public.vendedor_horarios h
        where h.id_vendedor = pr.id_vendedor and h.id_tianguis = t.id
      ) and exists (
        select 1 from public.tianguis_horarios h
        where h.id_tianguis = t.id and h.dia_semana = p_dia
      )
    ));
$$;

revoke all on function public.productos_catalogo(uuid, integer) from public, anon;
grant execute on function public.productos_catalogo(uuid, integer) to authenticated;

-- RF-03. Para los vendedores sin nombre de negocio se muestra su nombre público.
create function public.nombre_vendedor_producto(p_producto uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select coalesce(nullif(btrim(v.nombre_negocio), ''), u.nombre_publico)
    from public.productos p
    join public.perfiles_vendedor v on v.id = p.id_vendedor
    join public.usuarios u on u.id = v.id_usuario
   where p.id = p_producto and p.activo and not p.moderado;
$$;

revoke all on function public.nombre_vendedor_producto(uuid) from public, anon;
grant execute on function public.nombre_vendedor_producto(uuid) to authenticated;

-- RF-13. Valida y bloquea el mismo producto al solicitar y al aceptar.
-- La cantidad NULL significa que el vendedor no lleva un inventario numérico.
create function public.producto_para_apartado(p_id uuid, p_cantidad integer)
returns public.productos
language plpgsql set search_path = public
as $$
declare producto public.productos%rowtype;
begin
  select * into producto from public.productos where id = p_id for no key update;
  if not found or not producto.activo or producto.moderado or not producto.disponible then
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

create function public.validar_solicitud_apartado()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform public.producto_para_apartado(new.id_producto, new.cantidad);
  return new;
end;
$$;

revoke all on function public.validar_solicitud_apartado() from public, anon, authenticated;
create trigger trg_validar_solicitud_apartado before insert on public.apartados
for each row execute function public.validar_solicitud_apartado();

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
    if not es_v then raise exception 'Solo el vendedor puede aceptar'; end if;
    if e <> 'pendiente' then raise exception 'Este apartado ya fue respondido'; end if;
    if r.fecha_expiracion is not null and r.fecha_expiracion < now() then
      raise exception 'La solicitud ya venció';
    end if;
    select p.cantidad_disponible into v_cant
      from public.producto_para_apartado(r.id_producto, r.cantidad) p;
    if v_cant is not null then
      update public.productos
         set cantidad_disponible = v_cant - r.cantidad,
             disponible = (v_cant - r.cantidad) > 0,
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
         set cantidad_disponible = cantidad_disponible + r.cantidad, disponible = true,
             actualizado_en = now()
       where id = r.id_producto and cantidad_disponible is not null;
    end if;
    update public.apartados set estado = 'cancelado' where id = p_id;

  else
    raise exception 'Acción no válida: %', p_accion;
  end if;
end $$;
