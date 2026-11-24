-- Lista de conversaciones del usuario con el nombre de la otra persona, el último
-- mensaje y los mensajes sin leer. La app no puede leer 'usuarios' de otras personas
-- (RLS), por eso esta función security definer devuelve solo el nombre que se muestra.
-- Es idempotente (CREATE OR REPLACE).

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
    left join usuarios o
           on o.id = case when c.id_iniciador = auth.uid() then c.id_receptor else c.id_iniciador end
    left join perfiles_vendedor pv on pv.id_usuario = o.id
    left join productos p on p.id = c.id_producto
    left join anuncios_espacio a on a.id = c.id_anuncio_espacio
   where auth.uid() in (c.id_iniciador, c.id_receptor)
   order by c.ultimo_mensaje_en desc nulls last, c.creada_en desc;
$$;

REVOKE ALL ON FUNCTION public.mis_conversaciones() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mis_conversaciones() TO authenticated;
