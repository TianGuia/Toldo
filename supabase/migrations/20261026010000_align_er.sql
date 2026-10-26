-- Modelo ER TianGuía. Equivalencias de nombres y tipos en docs/modelo-er.md.
-- Incremental: conserva cuentas, IDs y datos. Los casos ambiguos abortan.
SET check_function_bodies = false;

-- Un producto pertenece a exactamente un puesto. Solo inferimos una asignación
-- cuando el vendedor tiene un único puesto; nunca elegimos entre varios.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.productos p WHERE p.id_puesto IS NULL
      AND (SELECT count(*) FROM public.puestos pu WHERE pu.id_vendedor = p.id_vendedor) <> 1
  ) THEN
    RAISE EXCEPTION 'ER: hay productos sin puesto y sin asignación unívoca. Ejecuta scripts/preflight-er.sql y asigna sus puestos antes de migrar.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.productos p JOIN public.puestos pu ON pu.id = p.id_puesto
    WHERE p.id_vendedor <> pu.id_vendedor
  ) THEN
    RAISE EXCEPTION 'ER: hay productos asignados al puesto de otro vendedor.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.ofertas o WHERE NOT EXISTS (
      SELECT 1 FROM public.oferta_productos op WHERE op.id_oferta = o.id)
  ) THEN
    RAISE EXCEPTION 'ER: hay ofertas sin productos. Completa sus productos antes de migrar.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.oferta_productos op
      JOIN public.ofertas o ON o.id = op.id_oferta
      JOIN public.productos p ON p.id = op.id_producto
    WHERE o.id_vendedor <> p.id_vendedor
  ) THEN
    RAISE EXCEPTION 'ER: hay ofertas con productos de otro vendedor.';
  END IF;
END $$;

UPDATE public.productos p SET id_puesto = (
  SELECT pu.id FROM public.puestos pu WHERE pu.id_vendedor = p.id_vendedor
) WHERE p.id_puesto IS NULL;
ALTER TABLE public.puestos ADD CONSTRAINT puestos_id_vendedor_key UNIQUE (id, id_vendedor);
ALTER TABLE public.productos DROP CONSTRAINT productos_id_puesto_fkey;
ALTER TABLE public.productos ALTER COLUMN id_puesto SET NOT NULL;
ALTER TABLE public.productos ADD CONSTRAINT productos_id_puesto_fkey
  FOREIGN KEY (id_puesto) REFERENCES public.puestos(id) ON DELETE RESTRICT;
ALTER TABLE public.productos ADD CONSTRAINT productos_puesto_vendedor_fkey
  FOREIGN KEY (id_puesto, id_vendedor) REFERENCES public.puestos(id, id_vendedor) ON DELETE RESTRICT;

-- Especialización solapada: toda cuenta puede comprar y además habilitar vendedor.
-- Se comparte el valor UUID para conservar los IDs y las políticas existentes.
CREATE TABLE public.compradores (
  id_comprador uuid PRIMARY KEY,
  id_usuario uuid NOT NULL UNIQUE REFERENCES public.usuarios(id) ON DELETE CASCADE,
  CONSTRAINT compradores_identidad_check CHECK (id_comprador = id_usuario)
);
INSERT INTO public.compradores (id_comprador, id_usuario) SELECT id, id FROM public.usuarios;
CREATE FUNCTION public.crear_comprador() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.compradores (id_comprador, id_usuario) VALUES (NEW.id, NEW.id);
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.crear_comprador() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER usuarios_crear_comprador AFTER INSERT ON public.usuarios
  FOR EACH ROW EXECUTE FUNCTION public.crear_comprador();
ALTER TABLE public.compradores ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.compradores TO authenticated;
GRANT ALL ON public.compradores TO service_role;
CREATE POLICY compradores_select ON public.compradores FOR SELECT TO authenticated
  USING (id_usuario = auth.uid() OR public.es_admin() OR EXISTS (
    SELECT 1 FROM public.apartados a WHERE a.id_comprador = compradores.id_comprador
      AND public.es_mi_vendedor(a.id_vendedor)
  ) OR EXISTS (
    SELECT 1 FROM public.propuestas_precio p WHERE p.id_comprador = compradores.id_comprador
      AND public.es_mi_vendedor(p.id_vendedor)
  ));
ALTER TABLE public.apartados DROP CONSTRAINT apartados_id_comprador_fkey;
ALTER TABLE public.apartados ADD CONSTRAINT apartados_id_comprador_fkey
  FOREIGN KEY (id_comprador) REFERENCES public.compradores(id_comprador) ON DELETE CASCADE;
ALTER TABLE public.propuestas_precio DROP CONSTRAINT propuestas_precio_id_comprador_fkey;
ALTER TABLE public.propuestas_precio ADD CONSTRAINT propuestas_precio_id_comprador_fkey
  FOREIGN KEY (id_comprador) REFERENCES public.compradores(id_comprador) ON DELETE CASCADE;
ALTER TABLE public.visitas DROP CONSTRAINT visitas_id_usuario_fkey;
ALTER TABLE public.visitas ADD CONSTRAINT visitas_id_comprador_fkey
  FOREIGN KEY (id_usuario) REFERENCES public.compradores(id_comprador) ON DELETE CASCADE;
ALTER TABLE public.calificaciones DROP CONSTRAINT calificaciones_id_usuario_fkey;
ALTER TABLE public.calificaciones ADD CONSTRAINT calificaciones_id_comprador_fkey
  FOREIGN KEY (id_usuario) REFERENCES public.compradores(id_comprador) ON DELETE CASCADE;

-- Participación N:M. Iniciador/receptor se conservan como metadatos del cliente
-- anterior; la autorización y los mensajes se basan en participantes.
CREATE TABLE public.participantes (
  id_conversacion uuid NOT NULL REFERENCES public.conversaciones(id) ON DELETE CASCADE,
  id_usuario uuid NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  PRIMARY KEY (id_conversacion, id_usuario)
);
CREATE INDEX participantes_usuario_idx ON public.participantes(id_usuario);
INSERT INTO public.participantes
  SELECT id, id_iniciador FROM public.conversaciones
  UNION SELECT id, id_receptor FROM public.conversaciones;
ALTER TABLE public.conversaciones ALTER COLUMN id_iniciador SET DEFAULT auth.uid();
ALTER TABLE public.conversaciones ALTER COLUMN id_receptor DROP NOT NULL;
ALTER TABLE public.conversaciones ALTER COLUMN contexto DROP NOT NULL;
ALTER TABLE public.conversaciones DROP CONSTRAINT conversaciones_check1;
ALTER TABLE public.conversaciones ADD CONSTRAINT conversaciones_contexto_check CHECK (
  (contexto IS NULL AND id_producto IS NULL AND id_anuncio_espacio IS NULL)
  OR (contexto IS NOT NULL AND (
    (contexto = 'producto' AND id_producto IS NOT NULL AND id_anuncio_espacio IS NULL)
    OR (contexto = 'anuncio_espacio' AND id_anuncio_espacio IS NOT NULL AND id_producto IS NULL)))
);
ALTER TABLE public.conversaciones ADD COLUMN estado varchar NOT NULL DEFAULT 'activa'
  CHECK (estado IN ('activa', 'cerrada', 'archivada'));
CREATE FUNCTION public.participa_en(p_conversacion uuid, p_usuario uuid DEFAULT auth.uid()) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.participantes
    WHERE id_conversacion = p_conversacion AND id_usuario = p_usuario);
$$;
REVOKE ALL ON FUNCTION public.participa_en(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.participa_en(uuid, uuid) TO authenticated, service_role;
CREATE FUNCTION public.registrar_participantes() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.participantes VALUES (NEW.id, NEW.id_iniciador);
  IF NEW.id_receptor IS NOT NULL THEN
    INSERT INTO public.participantes VALUES (NEW.id, NEW.id_receptor);
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.registrar_participantes() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER conversaciones_participantes AFTER INSERT ON public.conversaciones
  FOR EACH ROW EXECUTE FUNCTION public.registrar_participantes();
ALTER TABLE public.participantes ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, DELETE ON public.participantes TO authenticated;
GRANT ALL ON public.participantes TO service_role;
CREATE POLICY participantes_select ON public.participantes FOR SELECT TO authenticated
  USING (public.participa_en(id_conversacion) OR public.es_admin());
CREATE POLICY participantes_insert ON public.participantes FOR INSERT TO authenticated
  WITH CHECK (public.es_admin() OR EXISTS (
    SELECT 1 FROM public.conversaciones c WHERE c.id = id_conversacion AND c.id_iniciador = auth.uid()
  ));
CREATE POLICY participantes_delete ON public.participantes FOR DELETE TO authenticated
  USING (id_usuario = auth.uid() OR public.es_admin() OR EXISTS (
    SELECT 1 FROM public.conversaciones c WHERE c.id = id_conversacion AND c.id_iniciador = auth.uid()
  ));
DROP POLICY conv_select ON public.conversaciones;
CREATE POLICY conv_select ON public.conversaciones FOR SELECT TO authenticated
  USING (public.participa_en(id) OR public.es_admin());
DROP POLICY msg_select ON public.mensajes;
CREATE POLICY msg_select ON public.mensajes FOR SELECT TO authenticated
  USING ((NOT moderado AND public.participa_en(id_conversacion)) OR (public.es_admin() AND EXISTS (
    SELECT 1 FROM public.reportes r WHERE r.tipo_objetivo = 'mensaje' AND r.id_objetivo = mensajes.id
  )));
DROP POLICY msg_update ON public.mensajes;
CREATE POLICY msg_update ON public.mensajes FOR UPDATE TO authenticated
  USING (public.participa_en(id_conversacion) AND id_remitente <> auth.uid())
  WITH CHECK (public.participa_en(id_conversacion) AND id_remitente <> auth.uid());
CREATE OR REPLACE FUNCTION public.validar_mensaje() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.participa_en(NEW.id_conversacion, NEW.id_remitente) THEN
    RAISE EXCEPTION 'El remitente no participa en la conversación';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.conversaciones WHERE id = NEW.id_conversacion AND estado = 'activa') THEN
    RAISE EXCEPTION 'La conversación no está activa';
  END IF;
  IF EXISTS (SELECT 1 FROM public.participantes p
    WHERE p.id_conversacion = NEW.id_conversacion AND p.id_usuario <> NEW.id_remitente
      AND public.hay_bloqueo(NEW.id_remitente, p.id_usuario)) THEN
    RAISE EXCEPTION 'No se pueden enviar mensajes: existe un bloqueo activo';
  END IF;
  UPDATE public.conversaciones SET ultimo_mensaje_en = now() WHERE id = NEW.id_conversacion;
  RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.ocultar_conversacion(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.participa_en(p_id) THEN RAISE EXCEPTION 'No participas en esa conversación'; END IF;
  INSERT INTO public.conversaciones_ocultas (id_usuario, id_conversacion, ocultada_en)
    VALUES (auth.uid(), p_id, now())
    ON CONFLICT (id_usuario, id_conversacion) DO UPDATE SET ocultada_en = now();
END $$;

-- Atributos de estado que el ER exige explícitamente.
ALTER TABLE public.visitas ADD COLUMN estado varchar NOT NULL DEFAULT 'verificada'
  CHECK (estado IN ('pendiente', 'verificada', 'rechazada'));
ALTER TABLE public.mensajes ADD COLUMN estado varchar GENERATED ALWAYS AS (
  CASE WHEN moderado THEN 'moderado' WHEN leido_en IS NOT NULL THEN 'leido' ELSE 'enviado' END
) STORED;
CREATE OR REPLACE FUNCTION public.calificacion_desde_visita() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v record;
BEGIN
  SELECT vi.id_usuario, vi.id_puesto, p.id_vendedor, vi.estado INTO v
    FROM public.visitas vi JOIN public.puestos p ON p.id = vi.id_puesto WHERE vi.id = NEW.id_visita;
  IF NOT FOUND OR v.id_usuario IS DISTINCT FROM NEW.id_usuario THEN
    RAISE EXCEPTION 'La visita no pertenece al usuario';
  END IF;
  IF v.estado <> 'verificada' THEN RAISE EXCEPTION 'La visita no está verificada'; END IF;
  NEW.id_puesto := v.id_puesto;
  NEW.id_vendedor := v.id_vendedor;
  RETURN NEW;
END $$;
-- Reporte 0..1 por apelación: los vínculos de moderación adicionales son opcionales.
ALTER TABLE public.apelaciones DROP CONSTRAINT apelaciones_check;
-- La pareja del ER pasa a ser la PK; el ID auxiliar anterior permanece único.
ALTER TABLE public.vendedor_tianguis DROP CONSTRAINT vendedor_tianguis_pkey;
ALTER TABLE public.vendedor_tianguis ADD CONSTRAINT vendedor_tianguis_id_key UNIQUE (id);
ALTER TABLE public.vendedor_tianguis ADD PRIMARY KEY (id_vendedor, id_tianguis);

-- Oferta 1:N desde Producto. Una campaña anterior se divide por producto:
-- la primera conserva el ID original, las demás reciben IDs nuevos y trazables.
CREATE TEMP TABLE er_ofertas ON COMMIT DROP AS
  SELECT op.id AS id_relacion_origen, o.id AS id_oferta_origen,
    CASE WHEN row_number() OVER (PARTITION BY o.id ORDER BY op.id) = 1
      THEN o.id ELSE gen_random_uuid() END AS id_nuevo,
    op.id_producto, op.precio_promocional, op.descuento_porcentaje AS descuento,
    o.id_vendedor, o.titulo, o.fecha_inicio, o.fecha_fin, o.estado, o.creado_en
  FROM public.ofertas o JOIN public.oferta_productos op ON op.id_oferta = o.id;
ALTER TABLE public.ofertas
  ADD COLUMN id_producto uuid,
  ADD COLUMN precio_promocional numeric(10,2),
  ADD COLUMN descuento numeric(5,2),
  ADD COLUMN id_oferta_origen uuid,
  ADD COLUMN id_relacion_origen uuid UNIQUE;
UPDATE public.ofertas o SET
  id_producto = m.id_producto, precio_promocional = m.precio_promocional,
  descuento = m.descuento, id_oferta_origen = m.id_oferta_origen, id_relacion_origen = m.id_relacion_origen
  FROM er_ofertas m WHERE o.id = m.id_nuevo;
INSERT INTO public.ofertas (id, id_producto, precio_promocional, descuento,
  id_oferta_origen, id_relacion_origen, id_vendedor, titulo, fecha_inicio, fecha_fin, estado, creado_en)
  SELECT id_nuevo, id_producto, precio_promocional, descuento, id_oferta_origen,
    id_relacion_origen, id_vendedor, titulo, fecha_inicio, fecha_fin, estado, creado_en
  FROM er_ofertas WHERE id_nuevo <> id_oferta_origen;
ALTER TABLE public.ofertas ALTER COLUMN id_producto SET NOT NULL;
ALTER TABLE public.ofertas ADD CONSTRAINT ofertas_id_producto_fkey
  FOREIGN KEY (id_producto) REFERENCES public.productos(id) ON DELETE CASCADE;
ALTER TABLE public.productos ADD CONSTRAINT productos_id_vendedor_key UNIQUE (id, id_vendedor);
ALTER TABLE public.ofertas ADD CONSTRAINT ofertas_producto_vendedor_fkey
  FOREIGN KEY (id_producto, id_vendedor) REFERENCES public.productos(id, id_vendedor) ON DELETE CASCADE;
ALTER TABLE public.ofertas ADD CONSTRAINT ofertas_precio_check CHECK (
  (precio_promocional IS NOT NULL OR descuento IS NOT NULL)
  AND (precio_promocional IS NULL OR precio_promocional >= 0)
  AND (descuento IS NULL OR (descuento > 0 AND descuento <= 100))
);
CREATE INDEX ofertas_producto_idx ON public.ofertas(id_producto);
CREATE TRIGGER ofertas_vendedor BEFORE INSERT OR UPDATE OF id_producto ON public.ofertas
  FOR EACH ROW EXECUTE FUNCTION public.fijar_vendedor_desde_producto();

-- Se conserva la lectura SQL del catálogo anterior, sin otra tabla N:M editable.
DROP VIEW public.productos_catalogo;
DROP TABLE public.oferta_productos;
CREATE VIEW public.oferta_productos WITH (security_invoker = true) AS
  SELECT id, id AS id_oferta, id_producto, precio_promocional, descuento AS descuento_porcentaje
  FROM public.ofertas;
GRANT SELECT ON public.oferta_productos TO authenticated, service_role;
COMMENT ON VIEW public.oferta_productos IS 'Compatibilidad de lectura; publicar directamente en ofertas con id_producto.';

-- La definición del catálogo y la notificación se restablecen a continuación.

CREATE OR REPLACE VIEW "public"."productos_catalogo" WITH ("security_invoker"='true') AS
 SELECT "p"."id",
    "p"."id_vendedor",
    "p"."id_puesto",
    "p"."id_categoria",
    "p"."nombre",
    "p"."descripcion",
    "p"."estado_articulo",
    "p"."precio_referencia",
    "p"."disponible",
    "p"."busqueda",
        CASE
            WHEN ("p"."cantidad_disponible" IS NULL) THEN NULL::integer
            ELSE GREATEST(("p"."cantidad_disponible" - "ap"."n"), 0)
        END AS "cantidad_libre",
    "pu"."id_tianguis",
    "pu"."estado" AS "estado_puesto",
    "ov"."precio_promocional",
    "ov"."descuento_porcentaje",
    "ov"."fecha_fin" AS "oferta_fin",
    "im"."ruta_storage" AS "imagen_principal"
   FROM (((("public"."productos" "p"
     LEFT JOIN "public"."puestos" "pu" ON (("pu"."id" = "p"."id_puesto")))
     LEFT JOIN LATERAL ( SELECT (COALESCE("sum"("a"."cantidad"), (0)::bigint))::integer AS "n"
           FROM "public"."apartados" "a"
          WHERE (("a"."id_producto" = "p"."id") AND ("a"."estado" = 'aceptado'::"public"."estado_apartado") AND (("a"."fecha_expiracion" IS NULL) OR ("a"."fecha_expiracion" > "now"())))) "ap" ON (true))
     LEFT JOIN LATERAL ( SELECT "op"."precio_promocional",
            "op"."descuento_porcentaje",
            "o"."fecha_fin"
           FROM ("public"."oferta_productos" "op"
             JOIN "public"."ofertas" "o" ON (("o"."id" = "op"."id_oferta")))
          WHERE (("op"."id_producto" = "p"."id") AND ("o"."estado" = 'activa'::"public"."estado_oferta") AND (("now"() >= "o"."fecha_inicio") AND ("now"() <= "o"."fecha_fin")))
          ORDER BY "o"."fecha_fin"
         LIMIT 1) "ov" ON (true))
     LEFT JOIN LATERAL ( SELECT "producto_imagenes"."ruta_storage"
           FROM "public"."producto_imagenes"
          WHERE ("producto_imagenes"."id_producto" = "p"."id")
          ORDER BY "producto_imagenes"."orden"
         LIMIT 1) "im" ON (true))
  WHERE ("p"."activo" AND (NOT "p"."moderado"));

GRANT SELECT ON public.productos_catalogo TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."notificar_oferta"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_prod record;
begin
  select p.id, p.nombre, p.id_vendedor, p.id_puesto, p.id_categoria, pu.id_tianguis
    into v_prod
    from productos p left join puestos pu on pu.id = p.id_puesto
   where p.id = new.id_producto;

  insert into notificaciones (id_usuario, tipo, titulo, cuerpo, datos)
  select distinct u.id_usuario, 'oferta'::tipo_notificacion, 'Nueva oferta',
         'Oferta disponible en ' || v_prod.nombre,
         jsonb_build_object('id_producto', v_prod.id, 'id_oferta', new.id)
    from (
      select id_usuario from favoritos where id_producto = v_prod.id
      union select id_usuario from favoritos where v_prod.id_puesto is not null and id_puesto = v_prod.id_puesto
      union select id_usuario from favoritos where v_prod.id_tianguis is not null and id_tianguis = v_prod.id_tianguis
      union select id_usuario from intereses_categoria where v_prod.id_categoria is not null and id_categoria = v_prod.id_categoria
    ) u
    join preferencias_notificacion pn on pn.id_usuario = u.id_usuario and pn.ofertas
   where not exists (
           select 1 from silencios_notificacion s
            where s.id_usuario = u.id_usuario
              and (s.id_vendedor = v_prod.id_vendedor or s.id_tianguis = v_prod.id_tianguis))
     and u.id_usuario <> (select id_usuario from perfiles_vendedor where id = v_prod.id_vendedor);
  return new;
end $$;

CREATE TRIGGER trg_notificar_oferta AFTER INSERT ON public.ofertas
  FOR EACH ROW EXECUTE FUNCTION public.notificar_oferta();
