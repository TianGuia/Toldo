
-- RF-40 y RF-53. Se registran únicamente las versiones presentadas al usuario.
create or replace function public.terminos_pendientes()
returns setof public.versiones_documento
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Se requiere una sesión activa'; end if;

  if (select count(distinct tipo) from versiones_documento where vigente) <> 2 then
    raise exception 'Los documentos vigentes todavía no están disponibles';
  end if;

  return query
  select v.*
    from (
      select distinct on (tipo) *
      from versiones_documento
      where vigente
      order by tipo, publicado_en desc, id desc
    ) v
   where not exists (
     select 1 from aceptaciones_terminos a
     where a.id_usuario = auth.uid() and a.id_version = v.id
   ) and (v.requiere_reaceptacion or not exists (
     select 1 from aceptaciones_terminos a
     join versiones_documento anterior on anterior.id = a.id_version
     where a.id_usuario = auth.uid() and anterior.tipo = v.tipo
   ))
   order by v.tipo;
end;
$$;

create function public.aceptar_terminos_vigentes(p_versiones uuid[])
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_usuario uuid := auth.uid();
begin
  if v_usuario is null then raise exception 'Se requiere una sesión activa'; end if;

  -- Serializa la aceptación con una publicación y permite reintentar tras un fallo de red.
  lock table versiones_documento in share mode;
  if p_versiones is null or cardinality(p_versiones) = 0
      or exists (
        select 1 from unnest(p_versiones) solicitada(id)
        where not exists (
          select 1 from (
            select distinct on (tipo) id
            from versiones_documento
            where vigente
            order by tipo, publicado_en desc, id desc
          ) vigente where vigente.id = solicitada.id
        )
      ) then
    raise exception 'Las versiones cambiaron. Vuelve a consultar los documentos.';
  end if;

  insert into aceptaciones_terminos (id_usuario, id_version)
  select v_usuario, id from unnest(p_versiones) aceptada(id)
  on conflict (id_usuario, id_version) do nothing;
end;
$$;

create function public.admin_publicar_documento(
  p_tipo public.tipo_documento, p_version text, p_contenido text, p_requiere_reaceptacion boolean
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.es_admin() then raise exception 'Solo administradores'; end if;
  if p_tipo is null or nullif(btrim(p_version), '') is null
      or nullif(btrim(p_contenido), '') is null or p_requiere_reaceptacion is null then
    raise exception 'Completa los datos del documento';
  end if;

  lock table versiones_documento in share row exclusive mode;
  update versiones_documento set vigente = false where tipo = p_tipo and vigente;
  insert into versiones_documento (tipo, version, contenido, requiere_reaceptacion, publicado_por)
  values (p_tipo, btrim(p_version), p_contenido, p_requiere_reaceptacion, auth.uid());
end;
$$;

-- Los RPC son el camino de la app actual.
revoke all on function public.terminos_pendientes() from public, anon, authenticated;
revoke all on function public.aceptar_terminos_vigentes(uuid[]) from public, anon, authenticated;
revoke all on function public.admin_publicar_documento(public.tipo_documento, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.terminos_pendientes() to authenticated;
grant execute on function public.aceptar_terminos_vigentes(uuid[]) to authenticated;
grant execute on function public.admin_publicar_documento(public.tipo_documento, text, text, boolean)
  to authenticated;

revoke insert, update, delete on table public.aceptaciones_terminos from authenticated;
-- La beta publicada aún inserta las aceptaciones directamente. Se conserva esa
-- entrada solo para el usuario autenticado y las versiones que tiene pendientes.
grant insert (id_usuario, id_version) on public.aceptaciones_terminos to authenticated;
drop policy acep_ins on public.aceptaciones_terminos;
alter policy aceptaciones_insert on public.aceptaciones_terminos with check (
  id_usuario = auth.uid() and exists (
    select 1 from public.terminos_pendientes() documento where documento.id = id_version
  )
);
revoke insert, update, delete on table public.versiones_documento from authenticated;

alter publication supabase_realtime add table public.versiones_documento;
