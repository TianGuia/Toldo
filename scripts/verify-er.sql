-- Solo lectura: falla si no se observa la estructura que despliega Toldo.
DO $$
DECLARE relation_name text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
                 WHERE version = '20261026010000') THEN
    RAISE EXCEPTION 'No está registrada la migración del ER';
  END IF;
  IF to_regclass('public.compradores') IS NULL OR to_regclass('public.participantes') IS NULL THEN
    RAISE EXCEPTION 'Faltan compradores o participantes';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.participantes'::regclass AND contype = 'p' AND cardinality(conkey) = 2) THEN
    RAISE EXCEPTION 'Participante no tiene PK compuesta';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.vendedor_tianguis'::regclass AND contype = 'p' AND cardinality(conkey) = 2) THEN
    RAISE EXCEPTION 'Vendedor_Tianguis no tiene PK compuesta';
  END IF;
  FOREACH relation_name IN ARRAY ARRAY['apartados', 'propuestas_precio', 'visitas', 'calificaciones'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid = format('public.%I', relation_name)::regclass
        AND contype = 'f' AND confrelid = 'public.compradores'::regclass) THEN
      RAISE EXCEPTION 'Falta la FK a Comprador en %', relation_name;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.productos'::regclass
    AND attname = 'id_puesto' AND attnotnull AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Producto no exige un puesto';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.ofertas'::regclass
    AND attname = 'id_producto' AND attnotnull AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Oferta no exige un producto';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = to_regclass('public.oferta_productos') AND relkind = 'v') THEN
    RAISE EXCEPTION 'oferta_productos sigue siendo una tabla N:M o no existe';
  END IF;
  FOREACH relation_name IN ARRAY ARRAY['conversaciones', 'visitas', 'mensajes'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_attribute
      WHERE attrelid = format('public.%I', relation_name)::regclass
        AND attname = 'estado' AND NOT attisdropped) THEN
      RAISE EXCEPTION 'Falta estado en %', relation_name;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND NOT rowsecurity) THEN
    RAISE EXCEPTION 'Hay tablas públicas sin RLS';
  END IF;
END $$;
SELECT 'Estructura ER de Toldo aplicada; falta verificar los flujos de TianGuía.' AS resultado;
