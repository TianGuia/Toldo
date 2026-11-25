-- Valoraciones: las etiquetas son públicas (solo conteos) y el comentario es privado.
-- Reporte de fallas de la app.
-- Es idempotente: se puede volver a aplicar sin duplicar nada.

-- 1) Etiquetas de un puesto, para cualquier usuario con sesión.
--    Devuelve solo el nombre de la etiqueta y cuántas veces se usó; nunca comentarios
--    ni quién calificó. No cuenta calificaciones moderadas.
CREATE OR REPLACE FUNCTION public.etiquetas_puesto(p_puesto uuid)
RETURNS TABLE (nombre text, total bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  select ev.nombre::text, count(*)::bigint as total
    from calificaciones c
    join calificacion_etiquetas ce on ce.id_calificacion = c.id
    join etiquetas_valoracion ev on ev.id = ce.id_etiqueta
   where c.id_puesto = p_puesto
     and not c.moderado
   group by ev.nombre
   order by total desc, ev.nombre
   limit 8;
$$;
REVOKE ALL ON FUNCTION public.etiquetas_puesto(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.etiquetas_puesto(uuid) TO authenticated, service_role;

-- 2) El comentario es privado: antes cualquier usuario con sesión podía leer toda la
--    tabla (calif_select dejaba pasar las no moderadas). Ahora solo la lee quien la
--    escribió, el vendedor calificado y el administrador. El promedio y el total que
--    ve el público salen de v_puestos_resumen, que no expone comentarios.
DROP POLICY IF EXISTS calif_select ON public.calificaciones;
CREATE POLICY calif_select ON public.calificaciones FOR SELECT TO authenticated
  USING (id_usuario = auth.uid() OR public.soy_vendedor(id_vendedor) OR public.es_admin());

-- resumen_calificaciones solo trae promedio y total por vendedor; con la política nueva
-- necesita correr con los permisos del dueño para que todos vean el agregado.
ALTER VIEW public.resumen_calificaciones SET (security_invoker = false);

-- 3) Reporte de fallas de la app: cualquier persona con sesión manda el suyo y el
--    administrador los lee todos.
CREATE TABLE IF NOT EXISTS public.reportes_falla (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  id_usuario uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id) ON DELETE CASCADE,
  tipo text NOT NULL,
  descripcion text NOT NULL,
  plataforma text,
  creada_en timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reportes_falla_tipo_check
    CHECK (tipo IN ('no_funciona', 'se_traba', 'se_ve_mal', 'sugerencia', 'otra')),
  CONSTRAINT reportes_falla_descripcion_check
    CHECK (char_length(descripcion) BETWEEN 10 AND 500)
);
CREATE INDEX IF NOT EXISTS reportes_falla_creada_idx ON public.reportes_falla (creada_en DESC);
ALTER TABLE public.reportes_falla ENABLE ROW LEVEL SECURITY;

-- las tablas nuevas declaran sus GRANTs (ver restrict_client_privileges)
GRANT SELECT, INSERT ON public.reportes_falla TO authenticated;
GRANT ALL ON public.reportes_falla TO service_role;

DROP POLICY IF EXISTS falla_insert ON public.reportes_falla;
CREATE POLICY falla_insert ON public.reportes_falla FOR INSERT TO authenticated
  WITH CHECK (id_usuario = auth.uid() AND public.cuenta_activa());
DROP POLICY IF EXISTS falla_select ON public.reportes_falla;
CREATE POLICY falla_select ON public.reportes_falla FOR SELECT TO authenticated
  USING (id_usuario = auth.uid() OR public.es_admin());
