-- RF-44, RF-45 y RF-50. El servidor identifica al responsable del contenido.
create function public.usuario_de_objetivo_reportado(
  p_tipo public.tipo_objetivo, p_objetivo uuid
) returns uuid
language sql stable set search_path = public
as $$
  select case p_tipo
    when 'perfil' then (select id from usuarios where id = p_objetivo)
    when 'producto' then (
      select v.id_usuario from productos p join perfiles_vendedor v on v.id = p.id_vendedor
      where p.id = p_objetivo)
    when 'mensaje' then (select id_remitente from mensajes where id = p_objetivo)
    when 'calificacion' then (select id_usuario from calificaciones where id = p_objetivo)
    when 'anuncio_espacio' then (
      select v.id_usuario from anuncios_espacio a join perfiles_vendedor v on v.id = a.id_vendedor
      where a.id = p_objetivo)
  end;
$$;
revoke all on function public.usuario_de_objetivo_reportado(public.tipo_objetivo, uuid)
  from public, anon, authenticated;

create function public.verificar_objetivo_reporte() returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.tipo_objetivo = 'mensaje' and not public.es_admin() and not exists (
    select 1 from mensajes
    where id = new.id_objetivo and public.participa_en(id_conversacion, new.id_reportante)
  ) then
    raise exception 'El contenido reportado no está disponible';
  end if;

  new.id_usuario_reportado := public.usuario_de_objetivo_reportado(new.tipo_objetivo, new.id_objetivo);
  if new.id_usuario_reportado is null then
    raise exception 'El contenido reportado no está disponible';
  end if;
  return new;
end;
$$;
revoke all on function public.verificar_objetivo_reporte() from public, anon, authenticated;
create trigger reportes_verificar_objetivo before insert on public.reportes
  for each row execute function public.verificar_objetivo_reporte();

create function public.admin_resolver_reporte(
  p_id uuid, p_medida public.tipo_medida, p_decision text
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_reporte reportes%rowtype;
  v_afectado uuid;
  v_previa medidas_moderacion%rowtype;
  v_decision text := nullif(btrim(p_decision), '');
begin
  if not public.es_admin() then raise exception 'Solo administradores'; end if;
  if v_decision is null then raise exception 'El motivo es obligatorio'; end if;

  select * into v_reporte from reportes where id = p_id for update;
  if not found then raise exception 'Reporte no encontrado'; end if;
  if v_reporte.estado = 'resuelto' then
    raise exception 'El reporte ya fue resuelto';
  end if;

  v_afectado := public.usuario_de_objetivo_reportado(v_reporte.tipo_objetivo, v_reporte.id_objetivo);
  if p_medida is not null then
    if v_afectado is null then raise exception 'El contenido reportado ya no está disponible'; end if;
    if v_reporte.tipo_objetivo = 'perfil' and p_medida in ('ocultar_contenido', 'retirar_contenido') then
      raise exception 'Esta medida no está disponible para perfiles';
    end if;
    select * into v_previa from medidas_moderacion
      where id_reporte = p_id order by creada_en, id limit 1;
    if not found then
      insert into medidas_moderacion
        (id_reporte, id_usuario_afectado, tipo_medida, tipo_objetivo, id_objetivo, motivo_general, id_admin)
      values (p_id, v_afectado, p_medida, v_reporte.tipo_objetivo, v_reporte.id_objetivo, v_decision, auth.uid());
    elsif v_previa.id_usuario_afectado <> v_afectado
        or v_previa.tipo_medida <> p_medida or v_previa.motivo_general <> v_decision then
      raise exception 'El reporte tiene una medida previa. Revisa la medida antes de cerrar el reporte';
    end if;
  end if;

  update reportes set estado = 'resuelto', decision = v_decision, id_admin = auth.uid(),
         resuelto_en = now(), id_usuario_reportado = coalesce(v_afectado, id_usuario_reportado)
    where id = p_id;
end;
$$;
revoke all on function public.admin_resolver_reporte(uuid, public.tipo_medida, text)
  from public, anon, authenticated;
grant execute on function public.admin_resolver_reporte(uuid, public.tipo_medida, text)
  to authenticated;

-- Evita que el cliente antiguo vuelva a separar el cierre y la medida.
revoke update on public.reportes from authenticated;
revoke insert on public.medidas_moderacion from authenticated;

-- RF-31 y RF-47. El dueño puede cerrar o mover sus anuncios de tianguis desactivados.
alter policy anuncios_select on public.anuncios_espacio using (
  (not moderado and exists (select 1 from perfiles_vendedor where id_usuario = auth.uid())
    and exists (select 1 from tianguis where id = id_tianguis and activo))
  or public.soy_vendedor(id_vendedor) or public.es_admin()
);

create function public.verificar_tianguis_anuncio() returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if new.id_tianguis is not distinct from old.id_tianguis then return new; end if;
  end if;
  if not exists (select 1 from tianguis where id = new.id_tianguis and activo) then
    raise exception 'Elige un tianguis activo';
  end if;
  return new;
end;
$$;
revoke all on function public.verificar_tianguis_anuncio() from public, anon, authenticated;
create trigger anuncios_verificar_tianguis before insert or update of id_tianguis on public.anuncios_espacio
  for each row execute function public.verificar_tianguis_anuncio();

alter publication supabase_realtime add table public.anuncios_espacio;
