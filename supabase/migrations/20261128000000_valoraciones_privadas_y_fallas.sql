-- Captura del esquema vigente de Supabase antes de aplicar correcciones.
-- En producción estos objetos ya existen y se registra esta versión en el historial.

CREATE FUNCTION public.etiquetas_puesto(p_puesto uuid)
RETURNS TABLE (nombre text, total bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  select ev.nombre, count(*) as total
  from calificaciones c
  join calificacion_etiquetas ce on ce.id_calificacion = c.id
  join etiquetas_valoracion ev on ev.id = ce.id_etiqueta
  where c.id_puesto = p_puesto
  group by ev.nombre
  order by total desc, ev.nombre
  limit 8;
$$;
GRANT EXECUTE ON FUNCTION public.etiquetas_puesto(uuid) TO anon, authenticated, service_role;

CREATE TABLE public.reportes_falla (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  id_usuario uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  tipo text NOT NULL,
  descripcion text NOT NULL,
  plataforma text,
  creada_en timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reportes_falla_descripcion_check
    CHECK (char_length(descripcion) BETWEEN 10 AND 500),
  CONSTRAINT reportes_falla_tipo_check
    CHECK (tipo IN ('no_funciona', 'se_traba', 'se_ve_mal', 'sugerencia', 'otra'))
);
ALTER TABLE public.reportes_falla ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.reportes_falla TO authenticated;
GRANT ALL ON public.reportes_falla TO service_role;

CREATE POLICY falla_insertar ON public.reportes_falla FOR INSERT
  WITH CHECK (id_usuario = auth.uid());
CREATE POLICY falla_ver_propias ON public.reportes_falla FOR SELECT
  USING (id_usuario = auth.uid());
