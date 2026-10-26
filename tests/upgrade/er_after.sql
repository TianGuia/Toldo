DO $$
BEGIN
  IF (SELECT count(*) FROM public.compradores) <> 2 THEN RAISE EXCEPTION 'Se perdieron compradores previos'; END IF;
  IF (SELECT count(*) FROM public.participantes) <> 2 THEN RAISE EXCEPTION 'No se migraron ambos participantes'; END IF;
  IF EXISTS (SELECT 1 FROM public.productos WHERE id_puesto IS DISTINCT FROM '42000000-0000-0000-0000-000000000001'::uuid) THEN
    RAISE EXCEPTION 'Falló la asignación del puesto único';
  END IF;
  IF (SELECT count(*) FROM public.ofertas WHERE id_oferta_origen = '62000000-0000-0000-0000-000000000001') <> 2 THEN
    RAISE EXCEPTION 'No se dividió la campaña en dos ofertas trazables';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ofertas WHERE id = '62000000-0000-0000-0000-000000000001'
      AND precio_promocional = 25 AND id_producto = '52000000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'No se preservaron ID y precio de la primera oferta';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ofertas WHERE descuento = 15
      AND id_relacion_origen = '72000000-0000-0000-0000-000000000002'
      AND id_producto = '52000000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'Se perdió el descuento del segundo producto';
  END IF;
  IF (SELECT count(*) FROM public.oferta_productos) <> 2 THEN RAISE EXCEPTION 'Falló la vista de compatibilidad'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.mensajes WHERE contenido = 'Mensaje previo' AND estado = 'enviado') THEN
    RAISE EXCEPTION 'Se perdió el mensaje previo';
  END IF;
END $$;
ROLLBACK;
