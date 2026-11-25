
-- RF-45, RF-46 y RF-51. Las acciones administrativas y sus avisos son atómicos.
create function public.admin_cambiar_estado_cuenta(
  p_id uuid, p_estado public.estado_cuenta, p_motivo text
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_estado estado_cuenta;
  v_motivo text := nullif(btrim(p_motivo), '');
begin
  if not public.es_admin() then raise exception 'Solo administradores'; end if;
  if v_motivo is null then raise exception 'El motivo es obligatorio'; end if;
  if p_estado is null or p_estado not in ('suspendida', 'activa') then
    raise exception 'Estado no admitido';
  end if;

  select estado_cuenta into v_estado from usuarios where id = p_id for update;
  if not found or v_estado = 'eliminada' then raise exception 'Cuenta no disponible'; end if;
  if v_estado = p_estado then return; end if;

  if p_estado = 'suspendida' then
    insert into medidas_moderacion (id_usuario_afectado, tipo_medida, motivo_general, id_admin)
    values (p_id, 'suspender_cuenta', v_motivo, auth.uid());
  else
    update medidas_moderacion set activa = false
      where id_usuario_afectado = p_id and tipo_medida = 'suspender_cuenta' and activa;
    update usuarios set estado_cuenta = 'activa' where id = p_id;
    insert into notificaciones (id_usuario, tipo, titulo, cuerpo)
    values (p_id, 'moderacion', 'Cuenta reactivada', v_motivo);
  end if;
end;
$$;

-- La firma antigua no puede seguir suspendiendo cuentas sin motivo.
drop function public.admin_cambiar_estado_cuenta(uuid, public.estado_cuenta);
revoke all on function public.admin_cambiar_estado_cuenta(uuid, public.estado_cuenta, text)
  from public, anon, authenticated;
grant execute on function public.admin_cambiar_estado_cuenta(uuid, public.estado_cuenta, text)
  to authenticated;

create function public.admin_resolver_apelacion(
  p_id uuid, p_resolucion public.resolucion_apelacion, p_comentario text
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_apelacion apelaciones%rowtype;
  v_medida medidas_moderacion%rowtype;
  v_comentario text := nullif(btrim(p_comentario), '');
begin
  if not public.es_admin() then raise exception 'Solo administradores'; end if;
  if p_resolucion is null or v_comentario is null then
    raise exception 'La resolución y el comentario son obligatorios';
  end if;

  select * into v_apelacion from apelaciones where id = p_id for update;
  if not found or v_apelacion.estado <> 'pendiente' then
    raise exception 'La apelación ya se resolvió o no existe';
  end if;

  if v_apelacion.id_medida is not null then
    -- El cambio de estado de cuenta y la resolución toman los bloqueos en este orden.
    perform 1 from usuarios where id = v_apelacion.id_usuario for update;
    select * into v_medida from medidas_moderacion
      where id = v_apelacion.id_medida and id_usuario_afectado = v_apelacion.id_usuario
      for update;
    if not found then raise exception 'La medida no pertenece al solicitante'; end if;
  end if;

  if p_resolucion = 'modificada' then
    if v_medida.activa is distinct from true or v_medida.tipo_medida = 'advertencia' then
      raise exception 'Solo se puede reducir una medida restrictiva activa a advertencia';
    end if;
    update medidas_moderacion set activa = false where id = v_medida.id;
    update medidas_moderacion set tipo_medida = 'advertencia', activa = true
      where id = v_medida.id;
  elsif p_resolucion = 'revertida' and v_medida.activa then
    update medidas_moderacion set activa = false where id = v_medida.id;
  end if;

  update apelaciones set estado = 'resuelta', resolucion = p_resolucion,
         comentario_resolucion = v_comentario, id_admin = auth.uid(), resuelta_en = now()
    where id = p_id;

  insert into notificaciones (id_usuario, tipo, titulo, cuerpo, datos)
  values (v_apelacion.id_usuario, 'moderacion', 'Resolución de tu apelación',
          v_comentario, jsonb_build_object('id_apelacion', p_id,
            'id_medida', v_apelacion.id_medida, 'resolucion', p_resolucion));
end;
$$;

revoke all on function public.admin_resolver_apelacion(uuid, public.resolucion_apelacion, text)
  from public, anon, authenticated;
grant execute on function public.admin_resolver_apelacion(uuid, public.resolucion_apelacion, text)
  to authenticated;

drop policy apel_update on public.apelaciones;
alter policy apel_insert on public.apelaciones with check (
  id_usuario = auth.uid() and estado = 'pendiente' and resolucion is null
  and comentario_resolucion is null and id_admin is null and resuelta_en is null
  and nullif(btrim(motivo), '') is not null
  and (id_medida is null or exists (
    select 1 from public.medidas_moderacion m
    where m.id = id_medida and m.id_usuario_afectado = auth.uid() and m.activa
  ))
);

CREATE OR REPLACE FUNCTION "public"."efecto_medida"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v boolean := new.activa;
begin
  if new.tipo_medida in ('ocultar_contenido','retirar_contenido') then
    if not v and exists (
      select 1 from medidas_moderacion
      where activa and tipo_objetivo = new.tipo_objetivo and id_objetivo = new.id_objetivo
        and tipo_medida in ('ocultar_contenido', 'retirar_contenido')
    ) then return new; end if;
    case new.tipo_objetivo::text
      when 'producto'        then update productos        set moderado = v where id = new.id_objetivo;
      when 'mensaje'         then update mensajes         set moderado = v where id = new.id_objetivo;
      when 'calificacion'    then update calificaciones   set moderado = v where id = new.id_objetivo;
      when 'anuncio_espacio' then update anuncios_espacio set moderado = v where id = new.id_objetivo;
      when 'oferta' then
        -- al levantar: vuelve a 'activa' si aún está vigente, si no a 'finalizada'
        update ofertas
           set estado = (case when v then 'cancelada'
                              when fecha_fin > now() then 'activa'
                              else 'finalizada' end)::estado_oferta
         where id = new.id_objetivo;
      when 'puesto' then
        update puestos
           set activo = not v,
               estado = case when v then 'cerrado'::estado_puesto else estado end,
               fecha_cierre = case when v and estado = 'abierto' then now() else fecha_cierre end
         where id = new.id_objetivo;
      when 'vendedor' then
        update perfiles_vendedor
           set estado = (case when v then 'suspendido' else 'activo' end)::estado_vendedor
         where id = new.id_objetivo;
        if v then
          update puestos
             set activo = false, estado = 'cerrado',
                 fecha_cierre = case when estado = 'abierto' then now() else fecha_cierre end
           where id_vendedor = new.id_objetivo;
        else
          update puestos set activo = true where id_vendedor = new.id_objetivo;
        end if;
      else null;
    end case;
  elsif new.tipo_medida = 'suspender_cuenta' then
    update usuarios
       set estado_cuenta = (case when v then 'suspendida' else 'activa' end)::estado_cuenta
     where id = new.id_usuario_afectado and estado_cuenta <> 'eliminada'
       and (v or not exists (
         select 1 from medidas_moderacion
         where activa and id_usuario_afectado = new.id_usuario_afectado
           and tipo_medida = 'suspender_cuenta'
       ));
  end if;
  return new;
end $$;

-- Da acceso a revisión a las cuentas suspendidas por el flujo directo anterior.
insert into public.medidas_moderacion (id_usuario_afectado, tipo_medida, motivo_general)
select u.id, 'suspender_cuenta', 'Suspensión previa. El motivo original no quedó registrado.'
  from public.usuarios u
 where u.estado_cuenta = 'suspendida' and not exists (
   select 1 from public.medidas_moderacion m
   where m.id_usuario_afectado = u.id and m.tipo_medida = 'suspender_cuenta' and m.activa
 );
