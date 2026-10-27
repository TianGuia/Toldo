-- Retiro coordinado con Tianguiapp: nunca deja productos sin puesto.
CREATE FUNCTION public.retirar_puesto(p_id_puesto uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE p public.puestos;
BEGIN
  SELECT * INTO p FROM public.puestos WHERE id = p_id_puesto FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM public.perfiles_vendedor v
    WHERE v.id = p.id_vendedor AND v.id_usuario = auth.uid()
  ) THEN
    RAISE EXCEPTION 'No autorizado para retirar este puesto';
  END IF;
  IF p.activo THEN
    PERFORM public.cerrar_puesto(p_id_puesto);
  END IF;
  UPDATE public.productos SET activo = false, disponible = false
    WHERE id_puesto = p_id_puesto AND (activo OR disponible);
  UPDATE public.ofertas SET estado = 'finalizada'
    WHERE estado = 'activa' AND id_producto IN (
      SELECT id FROM public.productos WHERE id_puesto = p_id_puesto
    );
  UPDATE public.puestos SET activo = false WHERE id = p_id_puesto AND activo;
END $$;
REVOKE ALL ON FUNCTION public.retirar_puesto(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.retirar_puesto(uuid) TO authenticated;

-- El bloqueo del padre serializa publicación/reasignación con su retiro.
CREATE FUNCTION public.validar_producto_puesto_activo() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE p public.puestos;
BEGIN
  -- NOT NULL/FK conservan los errores de integridad del esquema ER.
  IF NEW.id_puesto IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NOT NEW.activo AND NEW.id_puesto = OLD.id_puesto AND NEW.id_vendedor = OLD.id_vendedor THEN
      RETURN NEW;
    END IF;
  END IF;
  SELECT * INTO p FROM public.puestos WHERE id = NEW.id_puesto FOR UPDATE;
  IF NOT FOUND OR NOT p.activo OR p.id_vendedor <> NEW.id_vendedor THEN
    RAISE EXCEPTION 'El producto requiere un puesto activo del mismo vendedor';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.validar_producto_puesto_activo() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER productos_puesto_activo BEFORE INSERT OR UPDATE OF id_puesto, id_vendedor, activo
  ON public.productos FOR EACH ROW EXECUTE FUNCTION public.validar_producto_puesto_activo();

CREATE FUNCTION public.validar_oferta_producto_activo() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE id_puesto_producto uuid; producto_activo boolean;
BEGIN
  IF NEW.estado <> 'activa' THEN RETURN NEW; END IF;
  SELECT pr.id_puesto INTO id_puesto_producto FROM public.productos pr WHERE pr.id = NEW.id_producto;
  IF id_puesto_producto IS NULL THEN RETURN NEW; END IF;
  PERFORM 1 FROM public.puestos WHERE id = id_puesto_producto AND activo FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No se puede publicar una oferta en un puesto retirado'; END IF;
  SELECT pr.activo INTO producto_activo FROM public.productos pr WHERE pr.id = NEW.id_producto FOR UPDATE;
  IF NOT producto_activo THEN RAISE EXCEPTION 'No se puede publicar una oferta de un producto retirado'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.validar_oferta_producto_activo() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER ofertas_producto_activo BEFORE INSERT OR UPDATE OF id_producto, estado
  ON public.ofertas FOR EACH ROW EXECUTE FUNCTION public.validar_oferta_producto_activo();

-- INSERT ... RETURNING desde PostgREST comprueba conv_select antes del trigger
-- AFTER INSERT de participantes. La RPC termina ese trigger antes de recuperar
-- la conversación, sin ampliar conv_select ni mantener acceso al exmiembro.
CREATE FUNCTION public.iniciar_conversacion(p_id_producto uuid DEFAULT NULL,
  p_id_receptor uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE nueva uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.cuenta_activa() THEN
    RAISE EXCEPTION 'Se necesita una cuenta activa para iniciar una conversación';
  END IF;
  IF p_id_receptor = auth.uid() THEN
    RAISE EXCEPTION 'No puedes iniciar un chat contigo mismo';
  END IF;
  IF p_id_producto IS NULL THEN
    INSERT INTO public.conversaciones (id_iniciador, id_receptor)
      VALUES (auth.uid(), p_id_receptor) RETURNING id INTO nueva;
  ELSE
    INSERT INTO public.conversaciones (id_iniciador, id_receptor, contexto, id_producto)
      VALUES (auth.uid(), p_id_receptor, 'producto', p_id_producto) RETURNING id INTO nueva;
  END IF;
  RETURN nueva;
END $$;
REVOKE ALL ON FUNCTION public.iniciar_conversacion(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.iniciar_conversacion(uuid, uuid) TO authenticated;
