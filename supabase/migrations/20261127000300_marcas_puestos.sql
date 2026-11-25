-- Marcas de puesto: "Nuevo", "Veterano" y "Destacado" con reglas justas.
--
-- Una calificación solo existe si el comprador confirmó una visita con el
-- código de 6 dígitos que genera el vendedor con el puesto abierto (vigencia de
-- 10 minutos) y hay una calificación por visita. Las marcas se apoyan en eso:
--
--   Nuevo     Menos de 30 días desde la PRIMERA apertura real del puesto
--             (jornadas_puesto), no desde que se dio de alta. Se quita sola.
--   Veterano  Más de 1 año desde la primera apertura, mínimo 10 personas
--             distintas que lo calificaron, promedio >= 4.0, mínimo 12
--             jornadas abiertas y alguna jornada en los últimos 60 días.
--   Destacado Compite quien tenga >= 5 personas distintas calificando y al
--             menos 1 calificación en los últimos 30 días. El orden usa un
--             promedio ponderado (bayesiano) para que 1 sola calificación de
--             5 estrellas no le gane a 4.8 con 100 opiniones. Si nadie cumple
--             el mínimo, se elige entre todos con el mismo orden para que el
--             Home nunca quede sin destacado.
--
-- No cuentan: calificaciones moderadas ni las del propio dueño del puesto.
-- Una misma persona que califica en varias jornadas suma una sola vez en
-- "calificadores", pero todas sus calificaciones cuentan en el promedio.

CREATE OR REPLACE VIEW public.v_puestos_resumen AS
 SELECT p.id,
    p.nombre,
    p.id_tianguis,
    t.nombre AS tianguis_nombre,
    ( SELECT min(h.dia_semana) AS min
           FROM public.tianguis_horarios h
          WHERE h.id_tianguis = p.id_tianguis) AS dia_semana,
    cat.id AS id_categoria,
    cat.nombre AS categoria_nombre,
    COALESCE(NULLIF(p.descripcion, ''::text), NULLIF(pv.descripcion, ''::text), pv.nombre_negocio) AS descripcion,
    st.prom AS promedio,
    st.n AS calificaciones,
    ( SELECT count(*) AS count
           FROM public.favoritos f
          WHERE f.id_puesto = p.id) AS guardados,
    (p.estado = 'abierto'::public.estado_puesto) AS abierto,
    COALESCE(p.foto_ruta, ( SELECT i.ruta_storage
           FROM (public.productos pr
             JOIN public.producto_imagenes i ON ((i.id_producto = pr.id)))
          WHERE ((pr.id_puesto = p.id) AND pr.activo AND (NOT pr.moderado))
          ORDER BY i.orden, pr.creado_en
         LIMIT 1)) AS ruta_imagen,
    p.fecha_apertura,
    p.creado_en,
    -- marcas (columnas nuevas, siempre al final de la vista)
    st.quienes AS calificadores,
    st.recientes AS calificaciones_recientes,
    jo.primera AS primera_apertura,
    jo.n AS jornadas,
    (jo.primera IS NOT NULL
       AND jo.primera > now() - interval '30 days') AS es_nuevo,
    (jo.primera IS NOT NULL
       AND jo.primera <= now() - interval '1 year'
       AND jo.ultima > now() - interval '60 days'
       AND jo.n >= 12
       AND st.quienes >= 10
       AND st.prom_exacto >= 4.0) AS es_veterano
   FROM (((public.puestos p
     JOIN public.tianguis t ON ((t.id = p.id_tianguis)))
     JOIN public.perfiles_vendedor pv ON ((pv.id = p.id_vendedor)))
     LEFT JOIN LATERAL ( SELECT c.id,
            c.nombre
           FROM (public.productos pr
             JOIN public.categorias c ON ((c.id = pr.id_categoria)))
          WHERE ((pr.id_puesto = p.id) AND pr.activo)
          GROUP BY c.id, c.nombre
          ORDER BY (count(*)) DESC
         LIMIT 1) cat ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS n,
            count(DISTINCT k.id_usuario) AS quienes,
            count(*) FILTER (WHERE k.creada_en > now() - interval '30 days') AS recientes,
            round(avg(k.puntuacion), 1) AS prom,
            avg(k.puntuacion) AS prom_exacto
           FROM public.calificaciones k
          WHERE k.id_puesto = p.id
            AND NOT k.moderado
            AND k.id_usuario <> pv.id_usuario) st ON (true)
     LEFT JOIN LATERAL ( SELECT min(j.fecha_apertura) AS primera,
            max(j.fecha_apertura) AS ultima,
            count(*) AS n
           FROM public.jornadas_puesto j
          WHERE j.id_puesto = p.id) jo ON (true)
  WHERE (p.activo AND (pv.estado = 'activo'::public.estado_vendedor) AND t.activo);

CREATE OR REPLACE FUNCTION public.puesto_destacado(p_categoria uuid DEFAULT NULL::uuid)
RETURNS SETOF public.v_puestos_resumen
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  WITH base AS (
    -- promedio de toda la plataforma: es el "punto de partida" del ponderado
    SELECT COALESCE(avg(k.puntuacion), 4.0) AS media
      FROM public.calificaciones k
      JOIN public.puestos p ON p.id = k.id_puesto
      JOIN public.perfiles_vendedor pv ON pv.id = p.id_vendedor
     WHERE NOT k.moderado AND k.id_usuario <> pv.id_usuario
  )
  SELECT r.*
    FROM public.v_puestos_resumen r, base b
   WHERE p_categoria IS NULL OR r.id_categoria = p_categoria
   ORDER BY (r.calificadores >= 5 AND r.calificaciones_recientes >= 1) DESC,
            ((COALESCE(r.promedio, 0) * r.calificaciones + 5 * b.media)
              / (r.calificaciones + 5)) DESC,
            r.calificadores DESC, r.guardados DESC, r.creado_en DESC
   LIMIT 1;
$$;
