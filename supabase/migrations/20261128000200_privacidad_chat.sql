-- RF-37 y RNF-3. El acceso depende de la membresía actual.

CREATE OR REPLACE FUNCTION public.mis_conversaciones()
RETURNS TABLE (
  id uuid,
  id_producto uuid,
  id_anuncio_espacio uuid,
  creada_en timestamptz,
  ultimo_mensaje_en timestamptz,
  id_otro uuid,
  otro_nombre text,
  producto_nombre text,
  anuncio_titulo text,
  ultimo_texto text,
  no_leidos integer
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  select c.id, c.id_producto, c.id_anuncio_espacio, c.creada_en, c.ultimo_mensaje_en,
         o.id,
         case
           -- chat de un producto y la otra persona es quien compra: su nombre público
           when p.id is not null and pv.id is distinct from p.id_vendedor then o.nombre_publico
           -- si no, el nombre del negocio y, si no lo llenó, su nombre público
           else coalesce(nullif(trim(pv.nombre_negocio), ''), o.nombre_publico)
         end,
         p.nombre,
         a.titulo,
         (select m.contenido from mensajes m
           where m.id_conversacion = c.id and not m.moderado
           order by m.enviado_en desc limit 1),
         (select count(*)::int from mensajes m
           where m.id_conversacion = c.id and not m.moderado
             and m.id_remitente <> auth.uid() and m.leido_en is null)
    from conversaciones c
    left join lateral (
      select u.id, u.nombre_publico
        from participantes miembro
        join usuarios u on u.id = miembro.id_usuario
       where miembro.id_conversacion = c.id and miembro.id_usuario <> auth.uid()
       order by (miembro.id_usuario in (c.id_iniciador, c.id_receptor)) desc nulls last,
                miembro.id_usuario
       limit 1
    ) o on true
    left join perfiles_vendedor pv on pv.id_usuario = o.id
    left join productos p on p.id = c.id_producto
    left join anuncios_espacio a on a.id = c.id_anuncio_espacio
   where public.participa_en(c.id)
   order by c.ultimo_mensaje_en desc nulls last, c.creada_en desc;
$$;

REVOKE ALL ON FUNCTION public.mis_conversaciones() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mis_conversaciones() TO authenticated;
create or replace function public.notificar_mensaje()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.moderado or not public.participa_en(new.id_conversacion, new.id_remitente) then
    return new;
  end if;

  insert into notificaciones (id_usuario, tipo, titulo, cuerpo, datos)
  select destinatario.id_usuario, 'mensaje',
         coalesce(nullif(trim(remitente.nombre_publico), ''), 'Nuevo mensaje'),
         left(trim(new.contenido), 120) ||
           case when length(trim(new.contenido)) > 120 then '...' else '' end,
         jsonb_build_object(
           'id_conversacion', c.id, 'id_mensaje', new.id,
           'id_remitente', new.id_remitente, 'contexto', c.contexto,
           'id_producto', c.id_producto, 'id_anuncio_espacio', c.id_anuncio_espacio
         )
    from conversaciones c
    join participantes destinatario on destinatario.id_conversacion = c.id
    join usuarios remitente on remitente.id = new.id_remitente
    left join preferencias_notificacion pref on pref.id_usuario = destinatario.id_usuario
   where c.id = new.id_conversacion and destinatario.id_usuario <> new.id_remitente
     and coalesce(pref.mensajes, true)
     and not public.hay_bloqueo(new.id_remitente, destinatario.id_usuario)
     and not exists (
       select 1 from silencios_notificacion s
       join perfiles_vendedor pv on pv.id = s.id_vendedor
       where s.id_usuario = destinatario.id_usuario and pv.id_usuario = new.id_remitente
     );

  return new;
end;
$$;

revoke all on function public.notificar_mensaje() from public, anon, authenticated;

alter policy notif_select on public.notificaciones using (
  id_usuario = auth.uid() and (
    tipo <> 'mensaje' or
    case when pg_input_is_valid(datos->>'id_conversacion', 'uuid')
         then public.participa_en((datos->>'id_conversacion')::uuid)
         else false end
  )
);
