-- Cambios de esquema ya presentes en Supabase, capturados el 2026-11-24.

ALTER TYPE public.tipo_objetivo ADD VALUE IF NOT EXISTS 'puesto';
ALTER TYPE public.tipo_objetivo ADD VALUE IF NOT EXISTS 'vendedor';
ALTER TYPE public.tipo_objetivo ADD VALUE IF NOT EXISTS 'oferta';

CREATE TABLE "public"."admin_bitacora" (
    "id" bigint NOT NULL,
    "quien" "text",
    "accion" "text" NOT NULL,
    "objetivo" "text",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."admin_bitacora" OWNER TO "postgres";

ALTER TABLE "public"."admin_bitacora" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."admin_bitacora" FROM PUBLIC, anon, authenticated;

GRANT ALL ON TABLE "public"."admin_bitacora" TO "service_role";

CREATE TABLE "public"."admin_credencial" (
    "clave_hash" "text" NOT NULL,
    "respuesta_hash" "text" NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "nombre" "text" NOT NULL
);

ALTER TABLE "public"."admin_credencial" OWNER TO "postgres";

ALTER TABLE "public"."admin_credencial" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."admin_credencial" FROM PUBLIC, anon, authenticated;

GRANT ALL ON TABLE "public"."admin_credencial" TO "service_role";

CREATE TABLE "public"."admin_intentos" (
    "id" bigint NOT NULL,
    "id_usuario" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."admin_intentos" OWNER TO "postgres";

ALTER TABLE "public"."admin_intentos" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."admin_intentos" FROM PUBLIC, anon, authenticated;

GRANT ALL ON TABLE "public"."admin_intentos" TO "service_role";

CREATE TABLE "public"."admin_sesiones" (
    "id_usuario" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expira_en" timestamp with time zone NOT NULL,
    "nombre" "text"
);

ALTER TABLE "public"."admin_sesiones" OWNER TO "postgres";

ALTER TABLE "public"."admin_sesiones" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."admin_sesiones" FROM PUBLIC, anon, authenticated;

GRANT ALL ON TABLE "public"."admin_sesiones" TO "service_role";

CREATE SEQUENCE "public"."admin_bitacora_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE "public"."admin_bitacora_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."admin_bitacora_id_seq" OWNED BY "public"."admin_bitacora"."id";

GRANT ALL ON SEQUENCE "public"."admin_bitacora_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."admin_bitacora_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."admin_bitacora_id_seq" TO "service_role";

CREATE SEQUENCE "public"."admin_intentos_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE "public"."admin_intentos_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."admin_intentos_id_seq" OWNED BY "public"."admin_intentos"."id";

GRANT ALL ON SEQUENCE "public"."admin_intentos_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."admin_intentos_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."admin_intentos_id_seq" TO "service_role";

ALTER TABLE ONLY "public"."admin_bitacora" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."admin_bitacora_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."admin_bitacora"
    ADD CONSTRAINT "admin_bitacora_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."admin_credencial"
    ADD CONSTRAINT "admin_credencial_pkey" PRIMARY KEY ("nombre");

ALTER TABLE ONLY "public"."admin_intentos" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."admin_intentos_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."admin_intentos"
    ADD CONSTRAINT "admin_intentos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."admin_sesiones"
    ADD CONSTRAINT "admin_sesiones_pkey" PRIMARY KEY ("id_usuario");

ALTER TABLE ONLY "public"."admin_sesiones"
    ADD CONSTRAINT "admin_sesiones_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION "public"."_admin_actual"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select nombre from public.admin_sesiones
   where id_usuario = auth.uid() and expira_en > now();
$$;

ALTER FUNCTION "public"."_admin_actual"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."_admin_actual"() FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."_admin_actual"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_admin_actual"() TO "service_role";

CREATE OR REPLACE FUNCTION "public"."_admin_validar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
declare
  c public.admin_credencial%rowtype;
  ok boolean;
begin
  if (select count(*) from public.admin_intentos
       where creado_en > now() - interval '15 minutes') >= 10 then
    raise exception 'Demasiados intentos. Espera unos minutos.';
  end if;
  select * into c from public.admin_credencial
   where nombre = lower(trim(coalesce(p_nombre, '')));
  ok := coalesce(
          found
          and crypt(coalesce(p_clave, ''), c.clave_hash) = c.clave_hash
          and crypt(lower(trim(coalesce(p_respuesta, ''))), c.respuesta_hash) = c.respuesta_hash,
          false);
  if not ok then
    insert into public.admin_intentos (id_usuario) values (auth.uid());
  end if;
  return ok;
end $$;

ALTER FUNCTION "public"."_admin_validar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."_admin_validar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."_admin_validar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_admin_validar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_aplicar_medida"("p_tipo_objetivo" "text", "p_id" "uuid", "p_tipo_medida" "text", "p_motivo" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_usuario uuid; v_medida uuid;
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  if coalesce(btrim(p_motivo), '') = '' then raise exception 'El motivo es obligatorio'; end if;
  if p_tipo_medida not in ('ocultar_contenido', 'retirar_contenido') then
    raise exception 'Medida no permitida en acciones directas';
  end if;

  case p_tipo_objetivo
    when 'puesto' then
      select pv.id_usuario into v_usuario from puestos p
        join perfiles_vendedor pv on pv.id = p.id_vendedor where p.id = p_id;
    when 'producto' then
      select pv.id_usuario into v_usuario from productos p
        join perfiles_vendedor pv on pv.id = p.id_vendedor where p.id = p_id;
    when 'vendedor' then
      select id_usuario into v_usuario from perfiles_vendedor where id = p_id;
    when 'anuncio_espacio' then
      select pv.id_usuario into v_usuario from anuncios_espacio a
        join perfiles_vendedor pv on pv.id = a.id_vendedor where a.id = p_id;
    when 'oferta' then
      select pv.id_usuario into v_usuario from ofertas o
        join perfiles_vendedor pv on pv.id = o.id_vendedor where o.id = p_id;
    when 'calificacion' then
      select coalesce(co.id_usuario, c.id_usuario) into v_usuario from calificaciones c
        left join compradores co on co.id_comprador = c.id_usuario where c.id = p_id;
    when 'mensaje' then
      select id_remitente into v_usuario from mensajes where id = p_id;
    else raise exception 'Tipo de objetivo no soportado: %', p_tipo_objetivo;
  end case;
  if v_usuario is null then raise exception 'No existe el elemento indicado'; end if;

  if exists (select 1 from medidas_moderacion
              where activa and tipo_objetivo::text = p_tipo_objetivo and id_objetivo = p_id
                and tipo_medida in ('ocultar_contenido','retirar_contenido')) then
    raise exception 'Ya hay una medida activa sobre este elemento';
  end if;

  insert into medidas_moderacion
    (id_reporte, id_usuario_afectado, tipo_medida, tipo_objetivo, id_objetivo, motivo_general, id_admin)
  values
    (null, v_usuario, p_tipo_medida::tipo_medida, p_tipo_objetivo::tipo_objetivo, p_id, btrim(p_motivo), auth.uid())
  returning id into v_medida;
  return v_medida;
end $$;

ALTER FUNCTION "public"."admin_aplicar_medida"("p_tipo_objetivo" "text", "p_id" "uuid", "p_tipo_medida" "text", "p_motivo" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_aplicar_medida"("p_tipo_objetivo" "text", "p_id" "uuid", "p_tipo_medida" "text", "p_motivo" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_aplicar_medida"("p_tipo_objetivo" "text", "p_id" "uuid", "p_tipo_medida" "text", "p_motivo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_aplicar_medida"("p_tipo_objetivo" "text", "p_id" "uuid", "p_tipo_medida" "text", "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_aplicar_medida"("p_tipo_objetivo" "text", "p_id" "uuid", "p_tipo_medida" "text", "p_motivo" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_bitacora_listar"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(b) order by b.creado_en desc)
    from (select quien, accion, objetivo, creado_en from public.admin_bitacora
           order by creado_en desc limit 50) b), '[]'::jsonb);
end $$;

ALTER FUNCTION "public"."admin_bitacora_listar"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_bitacora_listar"() FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_bitacora_listar"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_bitacora_listar"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_bitacora_listar"() TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_buscar_moderable"("p_tipo" "text", "p_texto" "text" DEFAULT ''::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare
  vacio boolean := coalesce(btrim(p_texto), '') = '';
  t text := '%' || coalesce(btrim(p_texto), '') || '%';
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;

  if p_tipo = 'calificacion' then
    return (select coalesce(jsonb_agg(to_jsonb(r) order by r.fecha desc), '[]'::jsonb) from (
      select c.id, c.puntuacion::text || '/5 · ' || p.nombre as titulo, c.comentario as detalle,
             u.nombre_publico as usuario_nombre, c.moderado, c.creada_en as fecha, m.id as medida_id
        from calificaciones c
        join puestos p on p.id = c.id_puesto
        left join compradores co on co.id_comprador = c.id_usuario
        left join usuarios u on u.id = coalesce(co.id_usuario, c.id_usuario)
        left join lateral (select mm.id from medidas_moderacion mm
                            where mm.activa and mm.tipo_objetivo::text = 'calificacion' and mm.id_objetivo = c.id
                              and mm.tipo_medida in ('ocultar_contenido','retirar_contenido')
                            order by mm.creada_en desc limit 1) m on true
       where vacio or c.comentario ilike t or p.nombre ilike t or u.nombre_publico ilike t
       order by c.creada_en desc limit 60) r);

  elsif p_tipo = 'anuncio_espacio' then
    return (select coalesce(jsonb_agg(to_jsonb(r) order by r.fecha desc), '[]'::jsonb) from (
      select a.id, a.titulo,
             a.rol::text || ' · ' || a.acuerdo::text || ' · ' || a.estado::text
               || coalesce(' · ' || a.descripcion, '') as detalle,
             u.nombre_publico as usuario_nombre, a.moderado, a.creado_en as fecha, m.id as medida_id
        from anuncios_espacio a
        join perfiles_vendedor pv on pv.id = a.id_vendedor
        left join usuarios u on u.id = pv.id_usuario
        left join lateral (select mm.id from medidas_moderacion mm
                            where mm.activa and mm.tipo_objetivo::text = 'anuncio_espacio' and mm.id_objetivo = a.id
                              and mm.tipo_medida in ('ocultar_contenido','retirar_contenido')
                            order by mm.creada_en desc limit 1) m on true
       where vacio or a.titulo ilike t or a.descripcion ilike t or u.nombre_publico ilike t
       order by a.creado_en desc limit 60) r);

  elsif p_tipo = 'oferta' then
    return (select coalesce(jsonb_agg(to_jsonb(r) order by r.fecha desc), '[]'::jsonb) from (
      select o.id, coalesce(nullif(o.titulo, ''), pr.nombre) as titulo,
             pr.nombre || ' · '
               || coalesce('$' || o.precio_promocional::text, coalesce(o.descuento::text || ' de descuento', 'sin precio'))
               || ' · ' || o.estado::text as detalle,
             u.nombre_publico as usuario_nombre, (m.id is not null) as moderado,
             o.creado_en as fecha, m.id as medida_id
        from ofertas o
        join productos pr on pr.id = o.id_producto
        join perfiles_vendedor pv on pv.id = o.id_vendedor
        left join usuarios u on u.id = pv.id_usuario
        left join lateral (select mm.id from medidas_moderacion mm
                            where mm.activa and mm.tipo_objetivo::text = 'oferta' and mm.id_objetivo = o.id
                              and mm.tipo_medida in ('ocultar_contenido','retirar_contenido')
                            order by mm.creada_en desc limit 1) m on true
       where vacio or o.titulo ilike t or pr.nombre ilike t or u.nombre_publico ilike t
       order by o.creado_en desc limit 60) r);
  end if;
  raise exception 'Tipo no soportado: %', p_tipo;
end $_$;


ALTER FUNCTION "public"."admin_buscar_moderable"("p_tipo" "text", "p_texto" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_cambiar_estado_cuenta"("p_id" "uuid", "p_estado" "public"."estado_cuenta") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not es_admin() then raise exception 'Solo administradores'; end if;
  update usuarios set estado_cuenta = p_estado where id = p_id;
end $$;

ALTER FUNCTION "public"."admin_buscar_moderable"("p_tipo" "text", "p_texto" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_buscar_moderable"("p_tipo" "text", "p_texto" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_buscar_moderable"("p_tipo" "text", "p_texto" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_buscar_moderable"("p_tipo" "text", "p_texto" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_buscar_moderable"("p_tipo" "text", "p_texto" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_catalogo_guardar"("p_tabla" "text", "p_id" "uuid" DEFAULT NULL::"uuid", "p_nombre" "text" DEFAULT NULL::"text", "p_activa" boolean DEFAULT true) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_id uuid; v_nombre text := btrim(coalesce(p_nombre, ''));
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  if v_nombre = '' then raise exception 'El nombre es obligatorio'; end if;
  if p_tabla = 'categorias' then
    if p_id is null then
      insert into categorias (nombre, activa) values (v_nombre, p_activa) returning id into v_id;
    else
      update categorias set nombre = v_nombre, activa = p_activa where id = p_id returning id into v_id;
    end if;
  elsif p_tabla = 'etiquetas' then
    if p_id is null then
      insert into etiquetas_valoracion (nombre, activa) values (v_nombre, p_activa) returning id into v_id;
    else
      update etiquetas_valoracion set nombre = v_nombre, activa = p_activa where id = p_id returning id into v_id;
    end if;
  else
    raise exception 'Catálogo no soportado: %', p_tabla;
  end if;
  if v_id is null then raise exception 'No existe el elemento indicado'; end if;
  return v_id;
exception when unique_violation then
  raise exception 'Ya existe una entrada con ese nombre';
end $$;

ALTER FUNCTION "public"."admin_catalogo_guardar"("p_tabla" "text", "p_id" "uuid", "p_nombre" "text", "p_activa" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_catalogo_guardar"("p_tabla" "text", "p_id" "uuid", "p_nombre" "text", "p_activa" boolean) FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_catalogo_guardar"("p_tabla" "text", "p_id" "uuid", "p_nombre" "text", "p_activa" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_catalogo_guardar"("p_tabla" "text", "p_id" "uuid", "p_nombre" "text", "p_activa" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_catalogo_guardar"("p_tabla" "text", "p_id" "uuid", "p_nombre" "text", "p_activa" boolean) TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_catalogo_listar"("p_tabla" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  if p_tabla = 'categorias' then
    return (select coalesce(jsonb_agg(jsonb_build_object(
              'id', c.id, 'nombre', c.nombre, 'activa', c.activa,
              'usos', (select count(*) from productos p where p.id_categoria = c.id)
            ) order by c.nombre), '[]'::jsonb) from categorias c);
  elsif p_tabla = 'etiquetas' then
    return (select coalesce(jsonb_agg(jsonb_build_object(
              'id', e.id, 'nombre', e.nombre, 'activa', e.activa,
              'usos', (select count(*) from calificacion_etiquetas ce where ce.id_etiqueta = e.id)
            ) order by e.nombre), '[]'::jsonb) from etiquetas_valoracion e);
  end if;
  raise exception 'Catálogo no soportado: %', p_tabla;
end $$;

ALTER FUNCTION "public"."admin_catalogo_listar"("p_tabla" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_catalogo_listar"("p_tabla" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_catalogo_listar"("p_tabla" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_catalogo_listar"("p_tabla" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_catalogo_listar"("p_tabla" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_configurar_credenciales"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
declare n text := lower(trim(coalesce(p_nombre, '')));
begin
  if n = '' then raise exception 'Escribe el nombre del administrador'; end if;
  if length(coalesce(p_clave, '')) < 6 then
    raise exception 'La clave debe tener al menos 6 caracteres';
  end if;
  if length(trim(coalesce(p_respuesta, ''))) < 1 then
    raise exception 'Escribe la respuesta a la pregunta secreta';
  end if;
  if not exists (select 1 from public.admin_credencial where nombre = n)
     and (select count(*) from public.admin_credencial) >= 4 then
    raise exception 'Ya hay 4 administradores. Quita uno con admin_quitar() antes de agregar otro.';
  end if;
  insert into public.admin_credencial (nombre, clave_hash, respuesta_hash)
  values (n, crypt(p_clave, gen_salt('bf')), crypt(lower(trim(p_respuesta)), gen_salt('bf')))
  on conflict (nombre) do update
    set clave_hash = excluded.clave_hash,
        respuesta_hash = excluded.respuesta_hash,
        actualizado_en = now();
end $$;

ALTER FUNCTION "public"."admin_configurar_credenciales"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_configurar_credenciales"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_configurar_credenciales"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_configurar_credenciales"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_entrar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
declare n text := lower(trim(coalesce(p_nombre, '')));
begin
  if auth.uid() is null then
    raise exception 'Sin sesión';
  end if;
  if not public._admin_validar(p_nombre, p_clave, p_respuesta) then
    return false;
  end if;

  -- Una sola sesión por administrador: se retira la anterior y las vencidas.
  delete from auth.users u
   where u.is_anonymous
     and u.id <> auth.uid()
     and u.id in (select id_usuario from public.admin_sesiones
                   where nombre = n or expira_en < now());

  insert into public.admin_sesiones (id_usuario, nombre, expira_en)
  values (auth.uid(), n, now() + interval '12 hours')
  on conflict (id_usuario) do update
    set nombre = excluded.nombre, expira_en = excluded.expira_en;
  delete from public.admin_intentos where creado_en < now() - interval '1 day';
  return true;
end $$;

ALTER FUNCTION "public"."admin_entrar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_entrar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_entrar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_entrar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_entrar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_guardar_admin"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
declare yo text := public._admin_actual(); n text := lower(trim(coalesce(p_nombre, ''))); existia boolean;
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  if yo is null then
    raise exception 'Solo un administrador que entró con clave puede gestionar administradores';
  end if;
  if not public._admin_validar(yo, p_mi_clave, p_mi_respuesta) then
    raise exception 'Tu clave o tu respuesta secreta no coinciden';
  end if;
  select exists (select 1 from public.admin_credencial where nombre = n) into existia;
  perform public.admin_configurar_credenciales(n, p_clave, p_respuesta);  -- valida largo y tope de 4
  insert into public.admin_bitacora (quien, accion, objetivo)
  values (yo, case when existia then 'cambio_clave' else 'alta' end, n);
end $$;

ALTER FUNCTION "public"."admin_guardar_admin"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_guardar_admin"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_guardar_admin"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_guardar_admin"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_guardar_admin"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_levantar_medida"("p_id" "uuid", "p_motivo" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_usuario uuid;
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  if coalesce(btrim(p_motivo), '') = '' then raise exception 'El motivo es obligatorio'; end if;
  update medidas_moderacion set activa = false
   where id = p_id and activa
   returning id_usuario_afectado into v_usuario;   -- el trigger revierte el efecto
  if v_usuario is null then raise exception 'La medida no existe o ya no está activa'; end if;
  insert into notificaciones (id_usuario, tipo, titulo, cuerpo, datos)
  values (v_usuario, 'moderacion', 'Medida levantada', btrim(p_motivo),
          jsonb_build_object('id_medida', p_id, 'levantada', true));
end $$;

ALTER FUNCTION "public"."admin_levantar_medida"("p_id" "uuid", "p_motivo" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_levantar_medida"("p_id" "uuid", "p_motivo" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_levantar_medida"("p_id" "uuid", "p_motivo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_levantar_medida"("p_id" "uuid", "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_levantar_medida"("p_id" "uuid", "p_motivo" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_lista_admins"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'nombre', c.nombre,
      'actualizado_en', c.actualizado_en,
      'sesion_hasta', (select max(s.expira_en) from public.admin_sesiones s
                        where s.nombre = c.nombre and s.expira_en > now()),
      'es_yo', c.nombre = public._admin_actual()
    ) order by c.nombre)
    from public.admin_credencial c), '[]'::jsonb);
end $$;

ALTER FUNCTION "public"."admin_lista_admins"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_lista_admins"() FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_lista_admins"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_lista_admins"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_lista_admins"() TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_medidas_activas"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.creada_en desc), '[]'::jsonb)
    from (
      select m.id, m.id_reporte, m.id_usuario_afectado,
             u.nombre_publico as usuario_nombre,
             m.tipo_medida::text as tipo_medida,
             m.tipo_objetivo::text as tipo_objetivo,
             m.id_objetivo, m.motivo_general, m.creada_en
        from medidas_moderacion m
        left join usuarios u on u.id = m.id_usuario_afectado
       where m.activa
       order by m.creada_en desc
       limit 200
    ) x
  );
end $$;

ALTER FUNCTION "public"."admin_medidas_activas"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_medidas_activas"() FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_medidas_activas"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_medidas_activas"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_medidas_activas"() TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_quitar"("p_nombre" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare n text := lower(trim(coalesce(p_nombre, '')));
begin
  delete from auth.users u
   where u.is_anonymous
     and u.id in (select id_usuario from public.admin_sesiones where nombre = n);
  delete from public.admin_sesiones where nombre = n;
  delete from public.admin_credencial where nombre = n;
end $$;

ALTER FUNCTION "public"."admin_quitar"("p_nombre" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_quitar"("p_nombre" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_quitar"("p_nombre" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_quitar"("p_nombre" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_quitar_admin"("p_nombre" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
declare yo text := public._admin_actual(); n text := lower(trim(coalesce(p_nombre, '')));
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  if yo is null then
    raise exception 'Solo un administrador que entró con clave puede gestionar administradores';
  end if;
  if not public._admin_validar(yo, p_mi_clave, p_mi_respuesta) then
    raise exception 'Tu clave o tu respuesta secreta no coinciden';
  end if;
  if n = yo then raise exception 'No puedes quitarte a ti mismo'; end if;
  if not exists (select 1 from public.admin_credencial where nombre = n) then
    raise exception 'No existe ese administrador';
  end if;
  if (select count(*) from public.admin_credencial) <= 1 then
    raise exception 'Debe quedar al menos un administrador';
  end if;
  perform public.admin_quitar(n);
  insert into public.admin_bitacora (quien, accion, objetivo) values (yo, 'quitar', n);
end $$;

ALTER FUNCTION "public"."admin_quitar_admin"("p_nombre" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_quitar_admin"("p_nombre" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_quitar_admin"("p_nombre" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_quitar_admin"("p_nombre" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_quitar_admin"("p_nombre" "text", "p_mi_clave" "text", "p_mi_respuesta" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_resumen"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  return jsonb_build_object(
    'usuarios',              (select count(*) from usuarios),
    'usuarios_suspendidos',  (select count(*) from usuarios where estado_cuenta = 'suspendida'),
    'vendedores',            (select count(*) from perfiles_vendedor),
    'vendedores_suspendidos',(select count(*) from perfiles_vendedor where estado = 'suspendido'),
    'puestos_abiertos',      (select count(*) from puestos where activo and estado = 'abierto'),
    'puestos_activos',       (select count(*) from puestos where activo),
    'productos_activos',     (select count(*) from productos where activo and not moderado),
    'productos_ocultos',     (select count(*) from productos where moderado),
    'tianguis_activos',      (select count(*) from tianguis where activo),
    'reportes_pendientes',   (select count(*) from reportes where estado in ('pendiente', 'en_revision')),
    'apelaciones_pendientes',(select count(*) from apelaciones where estado = 'pendiente'),
    'medidas_activas',       (select count(*) from medidas_moderacion where activa)
  );
end $$;

ALTER FUNCTION "public"."admin_resumen"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_resumen"() FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_resumen"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_resumen"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_resumen"() TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_salir"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  delete from public.admin_sesiones where id_usuario = auth.uid();
$$;

ALTER FUNCTION "public"."admin_salir"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_salir"() FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_salir"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_salir"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_salir"() TO "service_role";

CREATE OR REPLACE FUNCTION "public"."admin_verificar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ select public._admin_validar(p_nombre, p_clave, p_respuesta); $$;

ALTER FUNCTION "public"."admin_verificar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."admin_verificar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") FROM anon, authenticated;
REVOKE ALL ON FUNCTION "public"."admin_verificar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_verificar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_verificar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_verificar"("p_nombre" "text", "p_clave" "text", "p_respuesta" "text") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."documento_vigente"("p_tipo" "public"."tipo_documento") RETURNS TABLE("version" "text", "contenido" "text", "publicado_en" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select v.version, v.contenido, v.publicado_en
  from public.versiones_documento v
  where v.tipo = p_tipo and v.vigente
  order by v.publicado_en desc
  limit 1
$$;

ALTER FUNCTION "public"."documento_vigente"("p_tipo" "public"."tipo_documento") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."documento_vigente"("p_tipo" "public"."tipo_documento") FROM anon, authenticated;
GRANT ALL ON FUNCTION "public"."documento_vigente"("p_tipo" "public"."tipo_documento") TO "anon";
GRANT ALL ON FUNCTION "public"."documento_vigente"("p_tipo" "public"."tipo_documento") TO "authenticated";
GRANT ALL ON FUNCTION "public"."documento_vigente"("p_tipo" "public"."tipo_documento") TO "service_role";

CREATE OR REPLACE FUNCTION "public"."efecto_medida"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v boolean := new.activa;
begin
  if new.tipo_medida in ('ocultar_contenido','retirar_contenido') then
    case new.tipo_objetivo::text
      when 'producto'        then update productos        set moderado = v where id = new.id_objetivo;
      when 'mensaje'         then update mensajes         set moderado = v where id = new.id_objetivo;
      when 'calificacion'    then update calificaciones   set moderado = v where id = new.id_objetivo;
      when 'anuncio_espacio' then update anuncios_espacio set moderado = v where id = new.id_objetivo;
      when 'oferta' then
        -- al levantar: vuelve a 'activa' si aún está vigente, si no a 'finalizada'
        update ofertas
           set estado = (case when v then 'cancelada'
                              when fecha_fin > now() then 'activa'
                              else 'finalizada' end)::estado_oferta
         where id = new.id_objetivo;
      when 'puesto' then
        update puestos
           set activo = not v,
               estado = case when v then 'cerrado'::estado_puesto else estado end,
               fecha_cierre = case when v and estado = 'abierto' then now() else fecha_cierre end
         where id = new.id_objetivo;
      when 'vendedor' then
        update perfiles_vendedor
           set estado = (case when v then 'suspendido' else 'activo' end)::estado_vendedor
         where id = new.id_objetivo;
        if v then
          update puestos
             set activo = false, estado = 'cerrado',
                 fecha_cierre = case when estado = 'abierto' then now() else fecha_cierre end
           where id_vendedor = new.id_objetivo;
        else
          update puestos set activo = true where id_vendedor = new.id_objetivo;
        end if;
      else null;
    end case;
  elsif new.tipo_medida = 'suspender_cuenta' then
    update usuarios
       set estado_cuenta = (case when v then 'suspendida' else 'activa' end)::estado_cuenta
     where id = new.id_usuario_afectado;
  end if;
  return new;
end $$;

ALTER FUNCTION "public"."efecto_medida"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."es_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from administradores where id_usuario = auth.uid())
      or exists (select 1 from admin_sesiones
                  where id_usuario = auth.uid() and expira_en > now());
$$;

ALTER FUNCTION "public"."es_admin"() OWNER TO "postgres";

CREATE POLICY "versiones_select_publico" ON "public"."versiones_documento" FOR SELECT TO "anon" USING ("vigente");
