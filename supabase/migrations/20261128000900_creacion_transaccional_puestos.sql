-- Incorpora la creación idempotente de puestos que ya usa la app.
CREATE OR REPLACE FUNCTION "public"."crear_puesto_transaccional"("p_id" "uuid", "p_id_vendedor" "uuid", "p_id_tianguis" "uuid", "p_nombre" "text", "p_codigo" "text" DEFAULT NULL::"text", "p_descripcion" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    v_id uuid;
BEGIN
    INSERT INTO public.vendedor_tianguis (
        id_vendedor,
        id_tianguis
    )
    VALUES (
        p_id_vendedor,
        p_id_tianguis
    )
    ON CONFLICT (id_vendedor, id_tianguis)
    DO NOTHING;

    INSERT INTO public.puestos AS puesto (
        id,
        id_vendedor,
        id_tianguis,
        nombre,
        codigo,
        descripcion
    )
    VALUES (
        p_id,
        p_id_vendedor,
        p_id_tianguis,
        p_nombre,
        p_codigo,
        p_descripcion
    )
    ON CONFLICT (id)
    DO UPDATE SET
        nombre = EXCLUDED.nombre,
        codigo = EXCLUDED.codigo,
        descripcion = EXCLUDED.descripcion
    WHERE puesto.id_vendedor = EXCLUDED.id_vendedor
      AND puesto.id_tianguis = EXCLUDED.id_tianguis
    RETURNING puesto.id INTO v_id;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'Identificador de puesto incompatible';
    END IF;

    RETURN v_id;
END;
$$;

revoke execute on function public.crear_puesto_transaccional(uuid, uuid, uuid, text, text, text) from public, anon;
grant execute on function public.crear_puesto_transaccional(uuid, uuid, uuid, text, text, text) to authenticated, service_role;

-- La app edita estos campos. Las transiciones de estado siguen mediante RPC.
revoke update on public.puestos from authenticated;
grant update (nombre, codigo, descripcion, activo, foto_ruta, cierre_tipo, reabre_en, cierre_motivo)
  on public.puestos to authenticated;
