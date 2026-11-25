-- Correcciones de privacidad posteriores a la captura de producción.

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

-- El comentario es privado: antes cualquier usuario con sesión podía leer toda la
--    tabla (calif_select dejaba pasar las no moderadas). Ahora solo la lee quien la
--    escribió, el vendedor calificado y el administrador. El promedio y el total que
--    ve el público salen de v_puestos_resumen, que no expone comentarios.
DROP POLICY calif_select ON public.calificaciones;
CREATE POLICY calif_select ON public.calificaciones FOR SELECT TO authenticated
  USING (id_usuario = auth.uid() OR public.soy_vendedor(id_vendedor) OR public.es_admin());

-- resumen_calificaciones trae el promedio y el total por vendedor. Con la política nueva
-- necesita correr con los permisos del dueño para que todos vean el agregado.
ALTER VIEW public.resumen_calificaciones SET (security_invoker = false);

CREATE INDEX reportes_falla_creada_idx ON public.reportes_falla (creada_en DESC);

-- Sustituye las políticas originales y conserva la referencia a auth.users.
DROP POLICY falla_insertar ON public.reportes_falla;
DROP POLICY falla_ver_propias ON public.reportes_falla;

CREATE POLICY falla_insert ON public.reportes_falla FOR INSERT TO authenticated
  WITH CHECK (id_usuario = auth.uid() AND public.cuenta_activa());
CREATE POLICY falla_select ON public.reportes_falla FOR SELECT TO authenticated
  USING (id_usuario = auth.uid() OR public.es_admin());
