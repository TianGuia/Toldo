


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."contexto_conversacion" AS ENUM (
    'producto',
    'anuncio_espacio'
);


ALTER TYPE "public"."contexto_conversacion" OWNER TO "postgres";


CREATE TYPE "public"."estado_anuncio" AS ENUM (
    'abierto',
    'cerrado'
);


ALTER TYPE "public"."estado_anuncio" OWNER TO "postgres";


CREATE TYPE "public"."estado_apartado" AS ENUM (
    'pendiente',
    'aceptado',
    'rechazado',
    'cancelado',
    'expirado',
    'completado'
);


ALTER TYPE "public"."estado_apartado" OWNER TO "postgres";


CREATE TYPE "public"."estado_apelacion" AS ENUM (
    'pendiente',
    'resuelta'
);


ALTER TYPE "public"."estado_apelacion" OWNER TO "postgres";


CREATE TYPE "public"."estado_articulo" AS ENUM (
    'nuevo',
    'usado',
    'reacondicionado'
);


ALTER TYPE "public"."estado_articulo" OWNER TO "postgres";


CREATE TYPE "public"."estado_cuenta" AS ENUM (
    'activa',
    'suspendida',
    'eliminada'
);


ALTER TYPE "public"."estado_cuenta" OWNER TO "postgres";


CREATE TYPE "public"."estado_oferta" AS ENUM (
    'activa',
    'finalizada',
    'cancelada'
);


ALTER TYPE "public"."estado_oferta" OWNER TO "postgres";


CREATE TYPE "public"."estado_propuesta" AS ENUM (
    'pendiente',
    'aceptada',
    'rechazada',
    'contraofertada',
    'cancelada',
    'expirada'
);


ALTER TYPE "public"."estado_propuesta" OWNER TO "postgres";


CREATE TYPE "public"."estado_puesto" AS ENUM (
    'abierto',
    'cerrado'
);


ALTER TYPE "public"."estado_puesto" OWNER TO "postgres";


CREATE TYPE "public"."estado_reporte" AS ENUM (
    'pendiente',
    'en_revision',
    'resuelto'
);


ALTER TYPE "public"."estado_reporte" OWNER TO "postgres";


CREATE TYPE "public"."estado_vendedor" AS ENUM (
    'activo',
    'suspendido'
);


ALTER TYPE "public"."estado_vendedor" OWNER TO "postgres";


CREATE TYPE "public"."resolucion_apelacion" AS ENUM (
    'mantenida',
    'modificada',
    'revertida'
);


ALTER TYPE "public"."resolucion_apelacion" OWNER TO "postgres";


CREATE TYPE "public"."rol_anuncio" AS ENUM (
    'ofrece',
    'solicita'
);


ALTER TYPE "public"."rol_anuncio" OWNER TO "postgres";


CREATE TYPE "public"."tipo_acuerdo" AS ENUM (
    'renta',
    'prestamo',
    'traspaso'
);


ALTER TYPE "public"."tipo_acuerdo" OWNER TO "postgres";


CREATE TYPE "public"."tipo_documento" AS ENUM (
    'terminos',
    'privacidad'
);


ALTER TYPE "public"."tipo_documento" OWNER TO "postgres";


CREATE TYPE "public"."tipo_medida" AS ENUM (
    'advertencia',
    'ocultar_contenido',
    'retirar_contenido',
    'suspender_cuenta'
);


ALTER TYPE "public"."tipo_medida" OWNER TO "postgres";


CREATE TYPE "public"."tipo_notificacion" AS ENUM (
    'oferta',
    'ausencia',
    'recordatorio_tianguis',
    'mensaje',
    'propuesta_precio',
    'apartado',
    'moderacion',
    'sistema'
);


ALTER TYPE "public"."tipo_notificacion" OWNER TO "postgres";


CREATE TYPE "public"."tipo_objetivo" AS ENUM (
    'perfil',
    'producto',
    'mensaje',
    'calificacion',
    'anuncio_espacio'
);


ALTER TYPE "public"."tipo_objetivo" OWNER TO "postgres";


CREATE TYPE "public"."tipo_zona" AS ENUM (
    'zona',
    'pasillo',
    'espacio'
);


ALTER TYPE "public"."tipo_zona" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."abrir_puesto"("p_id_puesto" "uuid", "p_latitud" double precision, "p_longitud" double precision, "p_precision" real DEFAULT NULL::real) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_jornada uuid;
begin
  if not exists (select 1 from puestos p join perfiles_vendedor v on v.id = p.id_vendedor
                 where p.id = p_id_puesto and v.id_usuario = auth.uid() and v.estado = 'activo') then
    raise exception 'No autorizado para operar este puesto';
  end if;

  update jornadas_puesto set fecha_cierre = now()
   where id_puesto = p_id_puesto and fecha_cierre is null;

  insert into jornadas_puesto (id_puesto, latitud, longitud, precision_m)
  values (p_id_puesto, p_latitud, p_longitud, p_precision)
  returning id into v_jornada;

  update puestos
     set estado = 'abierto', latitud = p_latitud, longitud = p_longitud,
         fecha_apertura = now(), fecha_cierre = null
   where id = p_id_puesto;

  return v_jornada;
end $$;


ALTER FUNCTION "public"."abrir_puesto"("p_id_puesto" "uuid", "p_latitud" double precision, "p_longitud" double precision, "p_precision" real) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_cambiar_estado_cuenta"("p_id" "uuid", "p_estado" "public"."estado_cuenta") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not es_admin() then raise exception 'Solo administradores'; end if;
  update usuarios set estado_cuenta = p_estado where id = p_id;
end $$;


ALTER FUNCTION "public"."admin_cambiar_estado_cuenta"("p_id" "uuid", "p_estado" "public"."estado_cuenta") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calificacion_desde_visita"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v record;
begin
  select vi.id_usuario, vi.id_puesto, p.id_vendedor into v
    from visitas vi join puestos p on p.id = vi.id_puesto
   where vi.id = new.id_visita;
  if v.id_usuario is distinct from new.id_usuario then
    raise exception 'La visita no pertenece al usuario';
  end if;
  new.id_puesto := v.id_puesto;
  new.id_vendedor := v.id_vendedor;
  return new;
end $$;


ALTER FUNCTION "public"."calificacion_desde_visita"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cerrar_puesto"("p_id_puesto" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not exists (select 1 from puestos p join perfiles_vendedor v on v.id = p.id_vendedor
                 where p.id = p_id_puesto and v.id_usuario = auth.uid()) then
    raise exception 'No autorizado para operar este puesto';
  end if;

  update jornadas_puesto set fecha_cierre = now()
   where id_puesto = p_id_puesto and fecha_cierre is null;
  update puestos set estado = 'cerrado', fecha_cierre = now() where id = p_id_puesto;
end $$;


ALTER FUNCTION "public"."cerrar_puesto"("p_id_puesto" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirmar_visita"("p_codigo" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_jornada uuid; v_puesto uuid; v_visita uuid;
begin
  select c.id_jornada, j.id_puesto into v_jornada, v_puesto
    from codigos_visita c
    join jornadas_puesto j on j.id = c.id_jornada
   where c.codigo = p_codigo and c.expira_en > now() and j.fecha_cierre is null
   order by c.creado_en desc limit 1;

  if v_jornada is null then
    raise exception 'Código inválido o vencido';
  end if;

  insert into visitas (id_usuario, id_puesto, id_jornada)
  values (auth.uid(), v_puesto, v_jornada)
  on conflict (id_usuario, id_jornada) do update set fecha_hora = visitas.fecha_hora
  returning id into v_visita;
  return v_visita;
end $$;


ALTER FUNCTION "public"."confirmar_visita"("p_codigo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cuenta_activa"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from usuarios where id = auth.uid() and estado_cuenta = 'activa');
$$;


ALTER FUNCTION "public"."cuenta_activa"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."efecto_medida"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v boolean := new.activa;
begin
  if new.tipo_medida in ('ocultar_contenido','retirar_contenido') then
    case new.tipo_objetivo
      when 'producto'        then update productos        set moderado = v where id = new.id_objetivo;
      when 'mensaje'         then update mensajes         set moderado = v where id = new.id_objetivo;
      when 'calificacion'    then update calificaciones   set moderado = v where id = new.id_objetivo;
      when 'anuncio_espacio' then update anuncios_espacio set moderado = v where id = new.id_objetivo;
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
  select exists (select 1 from administradores where id_usuario = auth.uid());
$$;


ALTER FUNCTION "public"."es_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."es_anonimo"("p_uid" "uuid" DEFAULT "auth"."uid"()) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
  select coalesce((select u.is_anonymous from auth.users u where u.id = p_uid), false);
$$;


ALTER FUNCTION "public"."es_anonimo"("p_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expirar_apartados"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  update apartados set estado = 'expirado'
   where estado = 'aceptado' and fecha_expiracion is not null and fecha_expiracion <= now();
$$;


ALTER FUNCTION "public"."expirar_apartados"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expirar_ofertas"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  update ofertas set estado = 'finalizada' where estado = 'activa' and fecha_fin <= now();
$$;


ALTER FUNCTION "public"."expirar_ofertas"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fijar_vendedor_desde_producto"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  select id_vendedor into new.id_vendedor from productos where id = new.id_producto;
  if new.id_vendedor is null then raise exception 'Producto inexistente'; end if;
  return new;
end $$;


ALTER FUNCTION "public"."fijar_vendedor_desde_producto"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generar_codigo_visita"("p_id_puesto" "uuid", "p_minutos" integer DEFAULT 10) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_jornada uuid; v_codigo text;
begin
  select j.id into v_jornada
    from jornadas_puesto j
    join puestos p on p.id = j.id_puesto
    join perfiles_vendedor v on v.id = p.id_vendedor
   where j.id_puesto = p_id_puesto and j.fecha_cierre is null and v.id_usuario = auth.uid();
  if v_jornada is null then
    raise exception 'El puesto debe estar abierto y pertenecer al vendedor';
  end if;

  v_codigo := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into codigos_visita (id_jornada, codigo, expira_en)
  values (v_jornada, v_codigo, now() + make_interval(mins => p_minutos));
  return v_codigo;
end $$;


ALTER FUNCTION "public"."generar_codigo_visita"("p_id_puesto" "uuid", "p_minutos" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into usuarios (id, nombre_publico, correo, telefono)
  values (
    new.id,
    left(coalesce(nullif(trim(new.raw_user_meta_data->>'nombre_publico'), ''),
                  nullif(trim(new.raw_user_meta_data->>'nombre'), ''),
                  nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
                  'Invitado'), 80),
    new.email,
    new.phone
  ) on conflict (id) do nothing;

  insert into preferencias_notificacion (id_usuario) values (new.id)
  on conflict do nothing;
  return new;
end $$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."hay_bloqueo"("a" "uuid", "b" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from bloqueos
                 where activo and ((id_bloqueador = a and id_bloqueado = b)
                                or (id_bloqueador = b and id_bloqueado = a)));
$$;


ALTER FUNCTION "public"."hay_bloqueo"("a" "uuid", "b" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from administradores a where a.id_usuario = auth.uid())
         and not public.es_anonimo();
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."limpiar_codigos_visita"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  delete from codigos_visita where expira_en < now() - interval '1 day';
$$;


ALTER FUNCTION "public"."limpiar_codigos_visita"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mi_vendedor_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select case
    when public.es_anonimo() then null
    else (select id from perfiles_vendedor where id_usuario = auth.uid())
  end;
$$;


ALTER FUNCTION "public"."mi_vendedor_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notificar_ausencia"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into notificaciones (id_usuario, tipo, titulo, cuerpo, datos)
  select distinct f.id_usuario, 'ausencia'::tipo_notificacion, 'Ausencia programada',
         'El puesto ' || p.nombre || ' no abrirá el ' || to_char(new.fecha, 'DD/MM/YYYY'),
         jsonb_build_object('id_puesto', p.id, 'fecha', new.fecha)
    from puestos p
    join favoritos f on f.id_puesto = p.id
    join preferencias_notificacion pn on pn.id_usuario = f.id_usuario and pn.ausencias
   where p.id_vendedor = new.id_vendedor and p.id_tianguis = new.id_tianguis;
  return new;
end $$;


ALTER FUNCTION "public"."notificar_ausencia"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notificar_medida"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into notificaciones (id_usuario, tipo, titulo, cuerpo, datos)
  values (new.id_usuario_afectado, 'moderacion', 'Medida de moderación', new.motivo_general,
          jsonb_build_object('id_medida', new.id, 'tipo_medida', new.tipo_medida));
  return new;
end $$;


ALTER FUNCTION "public"."notificar_medida"() OWNER TO "postgres";


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
         jsonb_build_object('id_producto', v_prod.id, 'id_oferta', new.id_oferta)
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


ALTER FUNCTION "public"."notificar_oferta"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."calificaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_visita" "uuid" NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "id_puesto" "uuid" NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "puntuacion" smallint NOT NULL,
    "comentario" "text",
    "moderado" boolean DEFAULT false NOT NULL,
    "creada_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "calificaciones_puntuacion_check" CHECK ((("puntuacion" >= 1) AND ("puntuacion" <= 5)))
);


ALTER TABLE "public"."calificaciones" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."categorias" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "activa" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."categorias" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."favoritos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "id_producto" "uuid",
    "id_puesto" "uuid",
    "id_tianguis" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "favoritos_check" CHECK (("num_nonnulls"("id_producto", "id_puesto", "id_tianguis") = 1))
);


ALTER TABLE "public"."favoritos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."perfiles_vendedor" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "nombre_negocio" "text",
    "descripcion" "text",
    "estado" "public"."estado_vendedor" DEFAULT 'activo'::"public"."estado_vendedor" NOT NULL,
    "fecha_habilitacion" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."perfiles_vendedor" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."producto_imagenes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_producto" "uuid" NOT NULL,
    "ruta_storage" "text" NOT NULL,
    "orden" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."producto_imagenes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."productos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "id_puesto" "uuid",
    "id_categoria" "uuid",
    "nombre" "text" NOT NULL,
    "descripcion" "text",
    "estado_articulo" "public"."estado_articulo" DEFAULT 'nuevo'::"public"."estado_articulo" NOT NULL,
    "precio_referencia" numeric(10,2),
    "cantidad_disponible" integer,
    "disponible" boolean DEFAULT true NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "moderado" boolean DEFAULT false NOT NULL,
    "busqueda" "tsvector" GENERATED ALWAYS AS ("to_tsvector"('"spanish"'::"regconfig", ((COALESCE("nombre", ''::"text") || ' '::"text") || COALESCE("descripcion", ''::"text")))) STORED,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "productos_cantidad_disponible_check" CHECK (("cantidad_disponible" >= 0)),
    CONSTRAINT "productos_precio_referencia_check" CHECK (("precio_referencia" >= (0)::numeric))
);


ALTER TABLE "public"."productos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."puestos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "id_tianguis" "uuid" NOT NULL,
    "nombre" "text" NOT NULL,
    "codigo" "text",
    "estado" "public"."estado_puesto" DEFAULT 'cerrado'::"public"."estado_puesto" NOT NULL,
    "latitud" double precision,
    "longitud" double precision,
    "fecha_apertura" timestamp with time zone,
    "fecha_cierre" timestamp with time zone,
    "activo" boolean DEFAULT true NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "descripcion" "text",
    "foto_ruta" "text",
    "cierre_tipo" "text",
    "reabre_en" "date",
    "cierre_motivo" "text",
    CONSTRAINT "puestos_cierre_tipo_chk" CHECK ((("cierre_tipo" IS NULL) OR ("cierre_tipo" = ANY (ARRAY['temporal'::"text", 'hasta_nuevo_aviso'::"text"])))),
    CONSTRAINT "puestos_latitud_check" CHECK ((("latitud" >= ('-90'::integer)::double precision) AND ("latitud" <= (90)::double precision))),
    CONSTRAINT "puestos_longitud_check" CHECK ((("longitud" >= ('-180'::integer)::double precision) AND ("longitud" <= (180)::double precision)))
);


ALTER TABLE "public"."puestos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tianguis" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "descripcion" "text",
    "direccion" "text",
    "latitud" double precision,
    "longitud" double precision,
    "activo" boolean DEFAULT true NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tianguis_latitud_check" CHECK ((("latitud" >= ('-90'::integer)::double precision) AND ("latitud" <= (90)::double precision))),
    CONSTRAINT "tianguis_longitud_check" CHECK ((("longitud" >= ('-180'::integer)::double precision) AND ("longitud" <= (180)::double precision)))
);


ALTER TABLE "public"."tianguis" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tianguis_horarios" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_tianguis" "uuid" NOT NULL,
    "dia_semana" smallint NOT NULL,
    "hora_inicio" time without time zone NOT NULL,
    "hora_fin" time without time zone NOT NULL,
    CONSTRAINT "tianguis_horarios_check" CHECK (("hora_fin" > "hora_inicio")),
    CONSTRAINT "tianguis_horarios_dia_semana_check" CHECK ((("dia_semana" >= 0) AND ("dia_semana" <= 6)))
);


ALTER TABLE "public"."tianguis_horarios" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_puestos_resumen" AS
 SELECT "p"."id",
    "p"."nombre",
    "p"."id_tianguis",
    "t"."nombre" AS "tianguis_nombre",
    ( SELECT "min"("h"."dia_semana") AS "min"
           FROM "public"."tianguis_horarios" "h"
          WHERE ("h"."id_tianguis" = "p"."id_tianguis")) AS "dia_semana",
    "cat"."id" AS "id_categoria",
    "cat"."nombre" AS "categoria_nombre",
    COALESCE(NULLIF("p"."descripcion", ''::"text"), NULLIF("pv"."descripcion", ''::"text"), "pv"."nombre_negocio") AS "descripcion",
    ( SELECT "round"("avg"("k"."puntuacion"), 1) AS "round"
           FROM "public"."calificaciones" "k"
          WHERE (("k"."id_puesto" = "p"."id") AND (NOT "k"."moderado"))) AS "promedio",
    ( SELECT "count"(*) AS "count"
           FROM "public"."calificaciones" "k"
          WHERE (("k"."id_puesto" = "p"."id") AND (NOT "k"."moderado"))) AS "calificaciones",
    ( SELECT "count"(*) AS "count"
           FROM "public"."favoritos" "f"
          WHERE ("f"."id_puesto" = "p"."id")) AS "guardados",
    ("p"."estado" = 'abierto'::"public"."estado_puesto") AS "abierto",
    COALESCE("p"."foto_ruta", ( SELECT "i"."ruta_storage"
           FROM ("public"."productos" "pr"
             JOIN "public"."producto_imagenes" "i" ON (("i"."id_producto" = "pr"."id")))
          WHERE (("pr"."id_puesto" = "p"."id") AND "pr"."activo" AND (NOT "pr"."moderado"))
          ORDER BY "i"."orden", "pr"."creado_en"
         LIMIT 1)) AS "ruta_imagen",
    "p"."fecha_apertura",
    "p"."creado_en"
   FROM ((("public"."puestos" "p"
     JOIN "public"."tianguis" "t" ON (("t"."id" = "p"."id_tianguis")))
     JOIN "public"."perfiles_vendedor" "pv" ON (("pv"."id" = "p"."id_vendedor")))
     LEFT JOIN LATERAL ( SELECT "c"."id",
            "c"."nombre"
           FROM ("public"."productos" "pr"
             JOIN "public"."categorias" "c" ON (("c"."id" = "pr"."id_categoria")))
          WHERE (("pr"."id_puesto" = "p"."id") AND "pr"."activo")
          GROUP BY "c"."id", "c"."nombre"
          ORDER BY ("count"(*)) DESC
         LIMIT 1) "cat" ON (true))
  WHERE ("p"."activo" AND ("pv"."estado" = 'activo'::"public"."estado_vendedor") AND "t"."activo");


ALTER VIEW "public"."v_puestos_resumen" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."puesto_destacado"("p_categoria" "uuid" DEFAULT NULL::"uuid") RETURNS SETOF "public"."v_puestos_resumen"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select * from public.v_puestos_resumen
   where p_categoria is null or id_categoria = p_categoria
   order by coalesce(promedio, 0) desc, calificaciones desc, guardados desc, creado_en desc
   limit 1;
$$;


ALTER FUNCTION "public"."puesto_destacado"("p_categoria" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."puestos_limpiar_cierre"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.estado::text = 'abierto' then
    new.cierre_tipo   := null;
    new.reabre_en     := null;
    new.cierre_motivo := null;
  end if;
  return new;
end $$;


ALTER FUNCTION "public"."puestos_limpiar_cierre"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."puestos_tendencia"("p_categoria" "uuid" DEFAULT NULL::"uuid", "p_limite" integer DEFAULT 12) RETURNS SETOF "public"."v_puestos_resumen"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select * from public.v_puestos_resumen
   where p_categoria is null or id_categoria = p_categoria
   order by guardados desc, calificaciones desc, fecha_apertura desc nulls last, creado_en desc
   limit greatest(p_limite, 1);
$$;


ALTER FUNCTION "public"."puestos_tendencia"("p_categoria" "uuid", "p_limite" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resumen_inicio"() RETURNS json
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select json_build_object(
    'abiertos',  (select count(*) from public.puestos where activo and estado = 'abierto'),
    'en_espera', (select count(*) from public.puestos where activo and estado <> 'abierto')
  );
$$;


ALTER FUNCTION "public"."resumen_inicio"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_actualizado_en"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin new.actualizado_en = now(); return new; end $$;


ALTER FUNCTION "public"."set_actualizado_en"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."soy_vendedor"("p_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from perfiles_vendedor
                 where id = p_id and id_usuario = auth.uid() and estado = 'activo');
$$;


ALTER FUNCTION "public"."soy_vendedor"("p_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."versiones_documento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tipo" "public"."tipo_documento" NOT NULL,
    "version" "text" NOT NULL,
    "contenido" "text" NOT NULL,
    "requiere_reaceptacion" boolean DEFAULT true NOT NULL,
    "vigente" boolean DEFAULT true NOT NULL,
    "publicado_por" "uuid",
    "publicado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."versiones_documento" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."terminos_pendientes"() RETURNS SETOF "public"."versiones_documento"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select v.* from versiones_documento v
  where v.vigente and v.requiere_reaceptacion
    and not exists (select 1 from aceptaciones_terminos a
                    where a.id_usuario = auth.uid() and a.id_version = v.id);
$$;


ALTER FUNCTION "public"."terminos_pendientes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_solo_cuentas_reales"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
begin
  if public.es_anonimo(new.id_usuario) then
    raise exception 'Los usuarios sin cuenta no pueden ser vendedores ni administradores. Inicia sesión con tu correo.';
  end if;
  return new;
end $$;


ALTER FUNCTION "public"."tg_solo_cuentas_reales"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validar_mensaje"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare c record;
begin
  select id_iniciador, id_receptor into c from conversaciones where id = new.id_conversacion;
  if c is null or new.id_remitente not in (c.id_iniciador, c.id_receptor) then
    raise exception 'El remitente no participa en la conversación';
  end if;
  if hay_bloqueo(c.id_iniciador, c.id_receptor) then
    raise exception 'No se pueden enviar mensajes: existe un bloqueo activo';
  end if;
  update conversaciones set ultimo_mensaje_en = now() where id = new.id_conversacion;
  return new;
end $$;


ALTER FUNCTION "public"."validar_mensaje"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."aceptaciones_terminos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "id_version" "uuid" NOT NULL,
    "aceptado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."aceptaciones_terminos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."administradores" (
    "id_usuario" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."administradores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."anuncios_espacio" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "id_tianguis" "uuid" NOT NULL,
    "rol" "public"."rol_anuncio" NOT NULL,
    "acuerdo" "public"."tipo_acuerdo" NOT NULL,
    "titulo" "text" NOT NULL,
    "descripcion" "text",
    "estado" "public"."estado_anuncio" DEFAULT 'abierto'::"public"."estado_anuncio" NOT NULL,
    "moderado" boolean DEFAULT false NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."anuncios_espacio" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."apartados" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_producto" "uuid" NOT NULL,
    "id_comprador" "uuid" NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "cantidad" integer DEFAULT 1 NOT NULL,
    "estado" "public"."estado_apartado" DEFAULT 'pendiente'::"public"."estado_apartado" NOT NULL,
    "fecha_inicio" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fecha_expiracion" timestamp with time zone,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "apartados_cantidad_check" CHECK (("cantidad" > 0))
);


ALTER TABLE "public"."apartados" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."apelaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "id_medida" "uuid",
    "id_reporte" "uuid",
    "id_calificacion" "uuid",
    "motivo" "text" NOT NULL,
    "estado" "public"."estado_apelacion" DEFAULT 'pendiente'::"public"."estado_apelacion" NOT NULL,
    "resolucion" "public"."resolucion_apelacion",
    "comentario_resolucion" "text",
    "id_admin" "uuid",
    "creada_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resuelta_en" timestamp with time zone,
    CONSTRAINT "apelaciones_check" CHECK (("num_nonnulls"("id_medida", "id_reporte", "id_calificacion") >= 1))
);


ALTER TABLE "public"."apelaciones" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ausencias_programadas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "id_tianguis" "uuid" NOT NULL,
    "fecha" "date" NOT NULL,
    "motivo" "text",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ausencias_programadas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bloqueos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_bloqueador" "uuid" NOT NULL,
    "id_bloqueado" "uuid" NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "bloqueos_check" CHECK (("id_bloqueador" <> "id_bloqueado"))
);


ALTER TABLE "public"."bloqueos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."calificacion_etiquetas" (
    "id_calificacion" "uuid" NOT NULL,
    "id_etiqueta" "uuid" NOT NULL
);


ALTER TABLE "public"."calificacion_etiquetas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."codigos_visita" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_jornada" "uuid" NOT NULL,
    "codigo" "text" NOT NULL,
    "expira_en" timestamp with time zone NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."codigos_visita" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."conversaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contexto" "public"."contexto_conversacion" NOT NULL,
    "id_producto" "uuid",
    "id_anuncio_espacio" "uuid",
    "id_iniciador" "uuid" NOT NULL,
    "id_receptor" "uuid" NOT NULL,
    "creada_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ultimo_mensaje_en" timestamp with time zone,
    CONSTRAINT "conversaciones_check" CHECK (("id_iniciador" <> "id_receptor")),
    CONSTRAINT "conversaciones_check1" CHECK (((("contexto" = 'producto'::"public"."contexto_conversacion") AND ("id_producto" IS NOT NULL) AND ("id_anuncio_espacio" IS NULL)) OR (("contexto" = 'anuncio_espacio'::"public"."contexto_conversacion") AND ("id_anuncio_espacio" IS NOT NULL) AND ("id_producto" IS NULL))))
);


ALTER TABLE "public"."conversaciones" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dispositivos_push" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "token" "text" NOT NULL,
    "plataforma" "text" DEFAULT 'android'::"text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."dispositivos_push" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."etiquetas_valoracion" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "activa" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."etiquetas_valoracion" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."intereses_categoria" (
    "id_usuario" "uuid" NOT NULL,
    "id_categoria" "uuid" NOT NULL
);


ALTER TABLE "public"."intereses_categoria" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."jornadas_puesto" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_puesto" "uuid" NOT NULL,
    "fecha_apertura" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fecha_cierre" timestamp with time zone,
    "latitud" double precision,
    "longitud" double precision,
    "precision_m" real
);


ALTER TABLE "public"."jornadas_puesto" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medidas_moderacion" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_reporte" "uuid",
    "id_usuario_afectado" "uuid" NOT NULL,
    "tipo_medida" "public"."tipo_medida" NOT NULL,
    "tipo_objetivo" "public"."tipo_objetivo",
    "id_objetivo" "uuid",
    "motivo_general" "text" NOT NULL,
    "activa" boolean DEFAULT true NOT NULL,
    "id_admin" "uuid",
    "creada_en" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."medidas_moderacion" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mensajes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_conversacion" "uuid" NOT NULL,
    "id_remitente" "uuid" NOT NULL,
    "contenido" "text" NOT NULL,
    "enviado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "leido_en" timestamp with time zone,
    "moderado" boolean DEFAULT false NOT NULL,
    CONSTRAINT "mensajes_contenido_check" CHECK ((("char_length"("contenido") >= 1) AND ("char_length"("contenido") <= 2000)))
);


ALTER TABLE "public"."mensajes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notificaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "tipo" "public"."tipo_notificacion" NOT NULL,
    "titulo" "text" NOT NULL,
    "cuerpo" "text",
    "datos" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "leida" boolean DEFAULT false NOT NULL,
    "creada_en" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."notificaciones" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."oferta_productos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_oferta" "uuid" NOT NULL,
    "id_producto" "uuid" NOT NULL,
    "precio_promocional" numeric(10,2),
    "descuento_porcentaje" numeric(5,2),
    CONSTRAINT "oferta_productos_check" CHECK ((("precio_promocional" IS NOT NULL) OR ("descuento_porcentaje" IS NOT NULL))),
    CONSTRAINT "oferta_productos_descuento_porcentaje_check" CHECK ((("descuento_porcentaje" > (0)::numeric) AND ("descuento_porcentaje" <= (100)::numeric))),
    CONSTRAINT "oferta_productos_precio_promocional_check" CHECK (("precio_promocional" >= (0)::numeric))
);


ALTER TABLE "public"."oferta_productos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ofertas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "titulo" "text",
    "fecha_inicio" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fecha_fin" timestamp with time zone NOT NULL,
    "estado" "public"."estado_oferta" DEFAULT 'activa'::"public"."estado_oferta" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ofertas_check" CHECK (("fecha_fin" > "fecha_inicio"))
);


ALTER TABLE "public"."ofertas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."usuarios" (
    "id" "uuid" NOT NULL,
    "nombre_publico" "text" NOT NULL,
    "correo" "text",
    "telefono" "text",
    "foto_url" "text",
    "estado_cuenta" "public"."estado_cuenta" DEFAULT 'activa'::"public"."estado_cuenta" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "usuarios_nombre_publico_check" CHECK ((("char_length"("nombre_publico") >= 1) AND ("char_length"("nombre_publico") <= 80)))
);


ALTER TABLE "public"."usuarios" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."perfiles_publicos" AS
 SELECT "id",
    "nombre_publico",
    "foto_url"
   FROM "public"."usuarios"
  WHERE ("estado_cuenta" = 'activa'::"public"."estado_cuenta");


ALTER VIEW "public"."perfiles_publicos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."preferencias_notificacion" (
    "id_usuario" "uuid" NOT NULL,
    "ofertas" boolean DEFAULT true NOT NULL,
    "ausencias" boolean DEFAULT true NOT NULL,
    "recordatorios_tianguis" boolean DEFAULT true NOT NULL,
    "mensajes" boolean DEFAULT true NOT NULL,
    "apartados_propuestas" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."preferencias_notificacion" OWNER TO "postgres";


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


ALTER VIEW "public"."productos_catalogo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."propuestas_precio" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_producto" "uuid" NOT NULL,
    "id_comprador" "uuid" NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "id_emisor" "uuid" NOT NULL,
    "id_propuesta_anterior" "uuid",
    "monto" numeric(10,2) NOT NULL,
    "estado" "public"."estado_propuesta" DEFAULT 'pendiente'::"public"."estado_propuesta" NOT NULL,
    "creada_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "respondida_en" timestamp with time zone,
    CONSTRAINT "propuestas_precio_monto_check" CHECK (("monto" >= (0)::numeric))
);


ALTER TABLE "public"."propuestas_precio" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."puestos_abiertos" WITH ("security_invoker"='true') AS
 SELECT "pu"."id",
    "pu"."id_tianguis",
    "pu"."id_vendedor",
    "pu"."nombre",
    "pu"."codigo",
    "pu"."latitud",
    "pu"."longitud",
    "pu"."fecha_apertura",
    "v"."nombre_negocio",
    "t"."nombre" AS "tianguis"
   FROM (("public"."puestos" "pu"
     JOIN "public"."perfiles_vendedor" "v" ON (("v"."id" = "pu"."id_vendedor")))
     JOIN "public"."tianguis" "t" ON (("t"."id" = "pu"."id_tianguis")))
  WHERE (("pu"."estado" = 'abierto'::"public"."estado_puesto") AND "pu"."activo" AND "t"."activo" AND ("v"."estado" = 'activo'::"public"."estado_vendedor"));


ALTER VIEW "public"."puestos_abiertos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reportes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_reportante" "uuid" NOT NULL,
    "tipo_objetivo" "public"."tipo_objetivo" NOT NULL,
    "id_objetivo" "uuid" NOT NULL,
    "id_usuario_reportado" "uuid",
    "motivo" "text" NOT NULL,
    "estado" "public"."estado_reporte" DEFAULT 'pendiente'::"public"."estado_reporte" NOT NULL,
    "decision" "text",
    "id_admin" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resuelto_en" timestamp with time zone
);


ALTER TABLE "public"."reportes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."resumen_calificaciones" WITH ("security_invoker"='true') AS
 SELECT "id_vendedor",
    "round"("avg"("puntuacion"), 2) AS "promedio",
    "count"(*) AS "total"
   FROM "public"."calificaciones"
  WHERE (NOT "moderado")
  GROUP BY "id_vendedor";


ALTER VIEW "public"."resumen_calificaciones" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."silencios_notificacion" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "id_vendedor" "uuid",
    "id_tianguis" "uuid",
    CONSTRAINT "silencios_notificacion_check" CHECK (("num_nonnulls"("id_vendedor", "id_tianguis") = 1))
);


ALTER TABLE "public"."silencios_notificacion" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tianguis_zonas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_tianguis" "uuid" NOT NULL,
    "nombre" "text" NOT NULL,
    "tipo" "public"."tipo_zona" DEFAULT 'zona'::"public"."tipo_zona" NOT NULL,
    "geometria" "jsonb",
    "orden" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."tianguis_zonas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vendedor_horarios" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "id_tianguis" "uuid" NOT NULL,
    "dia_semana" smallint NOT NULL,
    "hora_inicio" time without time zone NOT NULL,
    "hora_fin" time without time zone NOT NULL,
    CONSTRAINT "vendedor_horarios_check" CHECK (("hora_fin" > "hora_inicio")),
    CONSTRAINT "vendedor_horarios_dia_semana_check" CHECK ((("dia_semana" >= 0) AND ("dia_semana" <= 6)))
);


ALTER TABLE "public"."vendedor_horarios" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vendedor_tianguis" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_vendedor" "uuid" NOT NULL,
    "id_tianguis" "uuid" NOT NULL
);


ALTER TABLE "public"."vendedor_tianguis" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."visitas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "id_puesto" "uuid" NOT NULL,
    "id_jornada" "uuid" NOT NULL,
    "metodo_verificacion" "text" DEFAULT 'codigo'::"text" NOT NULL,
    "fecha_hora" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."visitas" OWNER TO "postgres";


ALTER TABLE ONLY "public"."aceptaciones_terminos"
    ADD CONSTRAINT "aceptaciones_terminos_id_usuario_id_version_key" UNIQUE ("id_usuario", "id_version");



ALTER TABLE ONLY "public"."aceptaciones_terminos"
    ADD CONSTRAINT "aceptaciones_terminos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."administradores"
    ADD CONSTRAINT "administradores_pkey" PRIMARY KEY ("id_usuario");



ALTER TABLE ONLY "public"."anuncios_espacio"
    ADD CONSTRAINT "anuncios_espacio_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."apartados"
    ADD CONSTRAINT "apartados_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."apelaciones"
    ADD CONSTRAINT "apelaciones_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ausencias_programadas"
    ADD CONSTRAINT "ausencias_programadas_id_vendedor_id_tianguis_fecha_key" UNIQUE ("id_vendedor", "id_tianguis", "fecha");



ALTER TABLE ONLY "public"."ausencias_programadas"
    ADD CONSTRAINT "ausencias_programadas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bloqueos"
    ADD CONSTRAINT "bloqueos_id_bloqueador_id_bloqueado_key" UNIQUE ("id_bloqueador", "id_bloqueado");



ALTER TABLE ONLY "public"."bloqueos"
    ADD CONSTRAINT "bloqueos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."calificacion_etiquetas"
    ADD CONSTRAINT "calificacion_etiquetas_pkey" PRIMARY KEY ("id_calificacion", "id_etiqueta");



ALTER TABLE ONLY "public"."calificaciones"
    ADD CONSTRAINT "calificaciones_id_visita_key" UNIQUE ("id_visita");



ALTER TABLE ONLY "public"."calificaciones"
    ADD CONSTRAINT "calificaciones_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categorias"
    ADD CONSTRAINT "categorias_nombre_key" UNIQUE ("nombre");



ALTER TABLE ONLY "public"."categorias"
    ADD CONSTRAINT "categorias_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."codigos_visita"
    ADD CONSTRAINT "codigos_visita_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversaciones"
    ADD CONSTRAINT "conversaciones_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dispositivos_push"
    ADD CONSTRAINT "dispositivos_push_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dispositivos_push"
    ADD CONSTRAINT "dispositivos_push_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."etiquetas_valoracion"
    ADD CONSTRAINT "etiquetas_valoracion_nombre_key" UNIQUE ("nombre");



ALTER TABLE ONLY "public"."etiquetas_valoracion"
    ADD CONSTRAINT "etiquetas_valoracion_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favoritos"
    ADD CONSTRAINT "favoritos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."intereses_categoria"
    ADD CONSTRAINT "intereses_categoria_pkey" PRIMARY KEY ("id_usuario", "id_categoria");



ALTER TABLE ONLY "public"."jornadas_puesto"
    ADD CONSTRAINT "jornadas_puesto_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medidas_moderacion"
    ADD CONSTRAINT "medidas_moderacion_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mensajes"
    ADD CONSTRAINT "mensajes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notificaciones"
    ADD CONSTRAINT "notificaciones_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."oferta_productos"
    ADD CONSTRAINT "oferta_productos_id_oferta_id_producto_key" UNIQUE ("id_oferta", "id_producto");



ALTER TABLE ONLY "public"."oferta_productos"
    ADD CONSTRAINT "oferta_productos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ofertas"
    ADD CONSTRAINT "ofertas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."perfiles_vendedor"
    ADD CONSTRAINT "perfiles_vendedor_id_usuario_key" UNIQUE ("id_usuario");



ALTER TABLE ONLY "public"."perfiles_vendedor"
    ADD CONSTRAINT "perfiles_vendedor_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."preferencias_notificacion"
    ADD CONSTRAINT "preferencias_notificacion_pkey" PRIMARY KEY ("id_usuario");



ALTER TABLE ONLY "public"."producto_imagenes"
    ADD CONSTRAINT "producto_imagenes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."productos"
    ADD CONSTRAINT "productos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."propuestas_precio"
    ADD CONSTRAINT "propuestas_precio_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."puestos"
    ADD CONSTRAINT "puestos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reportes"
    ADD CONSTRAINT "reportes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."silencios_notificacion"
    ADD CONSTRAINT "silencios_notificacion_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tianguis_horarios"
    ADD CONSTRAINT "tianguis_horarios_id_tianguis_dia_semana_hora_inicio_key" UNIQUE ("id_tianguis", "dia_semana", "hora_inicio");



ALTER TABLE ONLY "public"."tianguis_horarios"
    ADD CONSTRAINT "tianguis_horarios_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tianguis"
    ADD CONSTRAINT "tianguis_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tianguis_zonas"
    ADD CONSTRAINT "tianguis_zonas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."usuarios"
    ADD CONSTRAINT "usuarios_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vendedor_horarios"
    ADD CONSTRAINT "vendedor_horarios_id_vendedor_id_tianguis_dia_semana_hora_i_key" UNIQUE ("id_vendedor", "id_tianguis", "dia_semana", "hora_inicio");



ALTER TABLE ONLY "public"."vendedor_horarios"
    ADD CONSTRAINT "vendedor_horarios_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vendedor_tianguis"
    ADD CONSTRAINT "vendedor_tianguis_id_vendedor_id_tianguis_key" UNIQUE ("id_vendedor", "id_tianguis");



ALTER TABLE ONLY "public"."vendedor_tianguis"
    ADD CONSTRAINT "vendedor_tianguis_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."versiones_documento"
    ADD CONSTRAINT "versiones_documento_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."versiones_documento"
    ADD CONSTRAINT "versiones_documento_tipo_version_key" UNIQUE ("tipo", "version");



ALTER TABLE ONLY "public"."visitas"
    ADD CONSTRAINT "visitas_id_usuario_id_jornada_key" UNIQUE ("id_usuario", "id_jornada");



ALTER TABLE ONLY "public"."visitas"
    ADD CONSTRAINT "visitas_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_anuncios_tianguis" ON "public"."anuncios_espacio" USING "btree" ("id_tianguis", "acuerdo", "estado");



CREATE INDEX "idx_apartados_comprador" ON "public"."apartados" USING "btree" ("id_comprador");



CREATE INDEX "idx_apartados_producto" ON "public"."apartados" USING "btree" ("id_producto", "estado");



CREATE INDEX "idx_apartados_vendedor" ON "public"."apartados" USING "btree" ("id_vendedor");



CREATE INDEX "idx_calif_vendedor" ON "public"."calificaciones" USING "btree" ("id_vendedor");



CREATE INDEX "idx_codigos_visita_codigo" ON "public"."codigos_visita" USING "btree" ("codigo", "expira_en");



CREATE INDEX "idx_conv_iniciador" ON "public"."conversaciones" USING "btree" ("id_iniciador");



CREATE INDEX "idx_conv_receptor" ON "public"."conversaciones" USING "btree" ("id_receptor");



CREATE INDEX "idx_medidas_usuario" ON "public"."medidas_moderacion" USING "btree" ("id_usuario_afectado");



CREATE INDEX "idx_mensajes_conv" ON "public"."mensajes" USING "btree" ("id_conversacion", "enviado_en");



CREATE INDEX "idx_notif_usuario" ON "public"."notificaciones" USING "btree" ("id_usuario", "leida", "creada_en" DESC);



CREATE INDEX "idx_oferta_prod_producto" ON "public"."oferta_productos" USING "btree" ("id_producto");



CREATE INDEX "idx_ofertas_vigencia" ON "public"."ofertas" USING "btree" ("estado", "fecha_fin");



CREATE INDEX "idx_productos_busqueda" ON "public"."productos" USING "gin" ("busqueda");



CREATE INDEX "idx_productos_categoria" ON "public"."productos" USING "btree" ("id_categoria");



CREATE INDEX "idx_productos_nombre_trgm" ON "public"."productos" USING "gin" ("nombre" "public"."gin_trgm_ops");



CREATE INDEX "idx_productos_precio" ON "public"."productos" USING "btree" ("precio_referencia");



CREATE INDEX "idx_productos_puesto" ON "public"."productos" USING "btree" ("id_puesto");



CREATE INDEX "idx_productos_vendedor" ON "public"."productos" USING "btree" ("id_vendedor");



CREATE INDEX "idx_propuestas_comprador" ON "public"."propuestas_precio" USING "btree" ("id_comprador");



CREATE INDEX "idx_propuestas_producto" ON "public"."propuestas_precio" USING "btree" ("id_producto", "estado");



CREATE INDEX "idx_propuestas_vendedor" ON "public"."propuestas_precio" USING "btree" ("id_vendedor");



CREATE INDEX "idx_puestos_tianguis" ON "public"."puestos" USING "btree" ("id_tianguis", "estado");



CREATE INDEX "idx_puestos_vendedor" ON "public"."puestos" USING "btree" ("id_vendedor");



CREATE INDEX "idx_reportes_estado" ON "public"."reportes" USING "btree" ("estado", "creado_en");



CREATE INDEX "idx_tianguis_horarios" ON "public"."tianguis_horarios" USING "btree" ("id_tianguis", "dia_semana");



CREATE UNIQUE INDEX "uq_conv_anuncio" ON "public"."conversaciones" USING "btree" ("id_iniciador", "id_receptor", "id_anuncio_espacio") WHERE ("id_anuncio_espacio" IS NOT NULL);



CREATE UNIQUE INDEX "uq_conv_producto" ON "public"."conversaciones" USING "btree" ("id_iniciador", "id_receptor", "id_producto") WHERE ("id_producto" IS NOT NULL);



CREATE UNIQUE INDEX "uq_fav_producto" ON "public"."favoritos" USING "btree" ("id_usuario", "id_producto") WHERE ("id_producto" IS NOT NULL);



CREATE UNIQUE INDEX "uq_fav_puesto" ON "public"."favoritos" USING "btree" ("id_usuario", "id_puesto") WHERE ("id_puesto" IS NOT NULL);



CREATE UNIQUE INDEX "uq_fav_tianguis" ON "public"."favoritos" USING "btree" ("id_usuario", "id_tianguis") WHERE ("id_tianguis" IS NOT NULL);



CREATE UNIQUE INDEX "uq_jornada_abierta" ON "public"."jornadas_puesto" USING "btree" ("id_puesto") WHERE ("fecha_cierre" IS NULL);



CREATE UNIQUE INDEX "uq_silencio_tianguis" ON "public"."silencios_notificacion" USING "btree" ("id_usuario", "id_tianguis") WHERE ("id_tianguis" IS NOT NULL);



CREATE UNIQUE INDEX "uq_silencio_vendedor" ON "public"."silencios_notificacion" USING "btree" ("id_usuario", "id_vendedor") WHERE ("id_vendedor" IS NOT NULL);



CREATE OR REPLACE TRIGGER "administradores_solo_reales" BEFORE INSERT ON "public"."administradores" FOR EACH ROW EXECUTE FUNCTION "public"."tg_solo_cuentas_reales"();



CREATE OR REPLACE TRIGGER "perfiles_vendedor_solo_reales" BEFORE INSERT ON "public"."perfiles_vendedor" FOR EACH ROW EXECUTE FUNCTION "public"."tg_solo_cuentas_reales"();



CREATE OR REPLACE TRIGGER "puestos_limpiar_cierre" BEFORE INSERT OR UPDATE ON "public"."puestos" FOR EACH ROW EXECUTE FUNCTION "public"."puestos_limpiar_cierre"();



CREATE OR REPLACE TRIGGER "trg_anuncios_upd" BEFORE UPDATE ON "public"."anuncios_espacio" FOR EACH ROW EXECUTE FUNCTION "public"."set_actualizado_en"();



CREATE OR REPLACE TRIGGER "trg_apartado_vendedor" BEFORE INSERT ON "public"."apartados" FOR EACH ROW EXECUTE FUNCTION "public"."fijar_vendedor_desde_producto"();



CREATE OR REPLACE TRIGGER "trg_calificacion_visita" BEFORE INSERT ON "public"."calificaciones" FOR EACH ROW EXECUTE FUNCTION "public"."calificacion_desde_visita"();



CREATE OR REPLACE TRIGGER "trg_efecto_medida_ins" AFTER INSERT ON "public"."medidas_moderacion" FOR EACH ROW EXECUTE FUNCTION "public"."efecto_medida"();



CREATE OR REPLACE TRIGGER "trg_efecto_medida_upd" AFTER UPDATE OF "activa" ON "public"."medidas_moderacion" FOR EACH ROW WHEN (("old"."activa" IS DISTINCT FROM "new"."activa")) EXECUTE FUNCTION "public"."efecto_medida"();



CREATE OR REPLACE TRIGGER "trg_notificar_ausencia" AFTER INSERT ON "public"."ausencias_programadas" FOR EACH ROW EXECUTE FUNCTION "public"."notificar_ausencia"();



CREATE OR REPLACE TRIGGER "trg_notificar_medida" AFTER INSERT ON "public"."medidas_moderacion" FOR EACH ROW EXECUTE FUNCTION "public"."notificar_medida"();



CREATE OR REPLACE TRIGGER "trg_notificar_oferta" AFTER INSERT ON "public"."oferta_productos" FOR EACH ROW EXECUTE FUNCTION "public"."notificar_oferta"();



CREATE OR REPLACE TRIGGER "trg_productos_upd" BEFORE UPDATE ON "public"."productos" FOR EACH ROW EXECUTE FUNCTION "public"."set_actualizado_en"();



CREATE OR REPLACE TRIGGER "trg_propuesta_vendedor" BEFORE INSERT ON "public"."propuestas_precio" FOR EACH ROW EXECUTE FUNCTION "public"."fijar_vendedor_desde_producto"();



CREATE OR REPLACE TRIGGER "trg_tianguis_upd" BEFORE UPDATE ON "public"."tianguis" FOR EACH ROW EXECUTE FUNCTION "public"."set_actualizado_en"();



CREATE OR REPLACE TRIGGER "trg_usuarios_upd" BEFORE UPDATE ON "public"."usuarios" FOR EACH ROW EXECUTE FUNCTION "public"."set_actualizado_en"();



CREATE OR REPLACE TRIGGER "trg_validar_mensaje" BEFORE INSERT ON "public"."mensajes" FOR EACH ROW EXECUTE FUNCTION "public"."validar_mensaje"();



ALTER TABLE ONLY "public"."aceptaciones_terminos"
    ADD CONSTRAINT "aceptaciones_terminos_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."aceptaciones_terminos"
    ADD CONSTRAINT "aceptaciones_terminos_id_version_fkey" FOREIGN KEY ("id_version") REFERENCES "public"."versiones_documento"("id");



ALTER TABLE ONLY "public"."administradores"
    ADD CONSTRAINT "administradores_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."anuncios_espacio"
    ADD CONSTRAINT "anuncios_espacio_id_tianguis_fkey" FOREIGN KEY ("id_tianguis") REFERENCES "public"."tianguis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."anuncios_espacio"
    ADD CONSTRAINT "anuncios_espacio_id_vendedor_fkey" FOREIGN KEY ("id_vendedor") REFERENCES "public"."perfiles_vendedor"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."apartados"
    ADD CONSTRAINT "apartados_id_comprador_fkey" FOREIGN KEY ("id_comprador") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."apartados"
    ADD CONSTRAINT "apartados_id_producto_fkey" FOREIGN KEY ("id_producto") REFERENCES "public"."productos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."apartados"
    ADD CONSTRAINT "apartados_id_vendedor_fkey" FOREIGN KEY ("id_vendedor") REFERENCES "public"."perfiles_vendedor"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."apelaciones"
    ADD CONSTRAINT "apelaciones_id_admin_fkey" FOREIGN KEY ("id_admin") REFERENCES "public"."usuarios"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."apelaciones"
    ADD CONSTRAINT "apelaciones_id_calificacion_fkey" FOREIGN KEY ("id_calificacion") REFERENCES "public"."calificaciones"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."apelaciones"
    ADD CONSTRAINT "apelaciones_id_medida_fkey" FOREIGN KEY ("id_medida") REFERENCES "public"."medidas_moderacion"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."apelaciones"
    ADD CONSTRAINT "apelaciones_id_reporte_fkey" FOREIGN KEY ("id_reporte") REFERENCES "public"."reportes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."apelaciones"
    ADD CONSTRAINT "apelaciones_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ausencias_programadas"
    ADD CONSTRAINT "ausencias_programadas_id_vendedor_id_tianguis_fkey" FOREIGN KEY ("id_vendedor", "id_tianguis") REFERENCES "public"."vendedor_tianguis"("id_vendedor", "id_tianguis") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bloqueos"
    ADD CONSTRAINT "bloqueos_id_bloqueado_fkey" FOREIGN KEY ("id_bloqueado") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bloqueos"
    ADD CONSTRAINT "bloqueos_id_bloqueador_fkey" FOREIGN KEY ("id_bloqueador") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."calificacion_etiquetas"
    ADD CONSTRAINT "calificacion_etiquetas_id_calificacion_fkey" FOREIGN KEY ("id_calificacion") REFERENCES "public"."calificaciones"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."calificacion_etiquetas"
    ADD CONSTRAINT "calificacion_etiquetas_id_etiqueta_fkey" FOREIGN KEY ("id_etiqueta") REFERENCES "public"."etiquetas_valoracion"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."calificaciones"
    ADD CONSTRAINT "calificaciones_id_puesto_fkey" FOREIGN KEY ("id_puesto") REFERENCES "public"."puestos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."calificaciones"
    ADD CONSTRAINT "calificaciones_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."calificaciones"
    ADD CONSTRAINT "calificaciones_id_vendedor_fkey" FOREIGN KEY ("id_vendedor") REFERENCES "public"."perfiles_vendedor"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."calificaciones"
    ADD CONSTRAINT "calificaciones_id_visita_fkey" FOREIGN KEY ("id_visita") REFERENCES "public"."visitas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."codigos_visita"
    ADD CONSTRAINT "codigos_visita_id_jornada_fkey" FOREIGN KEY ("id_jornada") REFERENCES "public"."jornadas_puesto"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversaciones"
    ADD CONSTRAINT "conversaciones_id_anuncio_espacio_fkey" FOREIGN KEY ("id_anuncio_espacio") REFERENCES "public"."anuncios_espacio"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversaciones"
    ADD CONSTRAINT "conversaciones_id_iniciador_fkey" FOREIGN KEY ("id_iniciador") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversaciones"
    ADD CONSTRAINT "conversaciones_id_producto_fkey" FOREIGN KEY ("id_producto") REFERENCES "public"."productos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversaciones"
    ADD CONSTRAINT "conversaciones_id_receptor_fkey" FOREIGN KEY ("id_receptor") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dispositivos_push"
    ADD CONSTRAINT "dispositivos_push_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favoritos"
    ADD CONSTRAINT "favoritos_id_producto_fkey" FOREIGN KEY ("id_producto") REFERENCES "public"."productos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favoritos"
    ADD CONSTRAINT "favoritos_id_puesto_fkey" FOREIGN KEY ("id_puesto") REFERENCES "public"."puestos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favoritos"
    ADD CONSTRAINT "favoritos_id_tianguis_fkey" FOREIGN KEY ("id_tianguis") REFERENCES "public"."tianguis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favoritos"
    ADD CONSTRAINT "favoritos_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."intereses_categoria"
    ADD CONSTRAINT "intereses_categoria_id_categoria_fkey" FOREIGN KEY ("id_categoria") REFERENCES "public"."categorias"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."intereses_categoria"
    ADD CONSTRAINT "intereses_categoria_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."jornadas_puesto"
    ADD CONSTRAINT "jornadas_puesto_id_puesto_fkey" FOREIGN KEY ("id_puesto") REFERENCES "public"."puestos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medidas_moderacion"
    ADD CONSTRAINT "medidas_moderacion_id_admin_fkey" FOREIGN KEY ("id_admin") REFERENCES "public"."usuarios"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."medidas_moderacion"
    ADD CONSTRAINT "medidas_moderacion_id_reporte_fkey" FOREIGN KEY ("id_reporte") REFERENCES "public"."reportes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."medidas_moderacion"
    ADD CONSTRAINT "medidas_moderacion_id_usuario_afectado_fkey" FOREIGN KEY ("id_usuario_afectado") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mensajes"
    ADD CONSTRAINT "mensajes_id_conversacion_fkey" FOREIGN KEY ("id_conversacion") REFERENCES "public"."conversaciones"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mensajes"
    ADD CONSTRAINT "mensajes_id_remitente_fkey" FOREIGN KEY ("id_remitente") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notificaciones"
    ADD CONSTRAINT "notificaciones_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."oferta_productos"
    ADD CONSTRAINT "oferta_productos_id_oferta_fkey" FOREIGN KEY ("id_oferta") REFERENCES "public"."ofertas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."oferta_productos"
    ADD CONSTRAINT "oferta_productos_id_producto_fkey" FOREIGN KEY ("id_producto") REFERENCES "public"."productos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ofertas"
    ADD CONSTRAINT "ofertas_id_vendedor_fkey" FOREIGN KEY ("id_vendedor") REFERENCES "public"."perfiles_vendedor"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."perfiles_vendedor"
    ADD CONSTRAINT "perfiles_vendedor_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."preferencias_notificacion"
    ADD CONSTRAINT "preferencias_notificacion_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."producto_imagenes"
    ADD CONSTRAINT "producto_imagenes_id_producto_fkey" FOREIGN KEY ("id_producto") REFERENCES "public"."productos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."productos"
    ADD CONSTRAINT "productos_id_categoria_fkey" FOREIGN KEY ("id_categoria") REFERENCES "public"."categorias"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."productos"
    ADD CONSTRAINT "productos_id_puesto_fkey" FOREIGN KEY ("id_puesto") REFERENCES "public"."puestos"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."productos"
    ADD CONSTRAINT "productos_id_vendedor_fkey" FOREIGN KEY ("id_vendedor") REFERENCES "public"."perfiles_vendedor"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."propuestas_precio"
    ADD CONSTRAINT "propuestas_precio_id_comprador_fkey" FOREIGN KEY ("id_comprador") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."propuestas_precio"
    ADD CONSTRAINT "propuestas_precio_id_emisor_fkey" FOREIGN KEY ("id_emisor") REFERENCES "public"."usuarios"("id");



ALTER TABLE ONLY "public"."propuestas_precio"
    ADD CONSTRAINT "propuestas_precio_id_producto_fkey" FOREIGN KEY ("id_producto") REFERENCES "public"."productos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."propuestas_precio"
    ADD CONSTRAINT "propuestas_precio_id_propuesta_anterior_fkey" FOREIGN KEY ("id_propuesta_anterior") REFERENCES "public"."propuestas_precio"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."propuestas_precio"
    ADD CONSTRAINT "propuestas_precio_id_vendedor_fkey" FOREIGN KEY ("id_vendedor") REFERENCES "public"."perfiles_vendedor"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."puestos"
    ADD CONSTRAINT "puestos_id_vendedor_id_tianguis_fkey" FOREIGN KEY ("id_vendedor", "id_tianguis") REFERENCES "public"."vendedor_tianguis"("id_vendedor", "id_tianguis") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reportes"
    ADD CONSTRAINT "reportes_id_admin_fkey" FOREIGN KEY ("id_admin") REFERENCES "public"."usuarios"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reportes"
    ADD CONSTRAINT "reportes_id_reportante_fkey" FOREIGN KEY ("id_reportante") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reportes"
    ADD CONSTRAINT "reportes_id_usuario_reportado_fkey" FOREIGN KEY ("id_usuario_reportado") REFERENCES "public"."usuarios"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."silencios_notificacion"
    ADD CONSTRAINT "silencios_notificacion_id_tianguis_fkey" FOREIGN KEY ("id_tianguis") REFERENCES "public"."tianguis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."silencios_notificacion"
    ADD CONSTRAINT "silencios_notificacion_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."silencios_notificacion"
    ADD CONSTRAINT "silencios_notificacion_id_vendedor_fkey" FOREIGN KEY ("id_vendedor") REFERENCES "public"."perfiles_vendedor"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tianguis_horarios"
    ADD CONSTRAINT "tianguis_horarios_id_tianguis_fkey" FOREIGN KEY ("id_tianguis") REFERENCES "public"."tianguis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tianguis_zonas"
    ADD CONSTRAINT "tianguis_zonas_id_tianguis_fkey" FOREIGN KEY ("id_tianguis") REFERENCES "public"."tianguis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."usuarios"
    ADD CONSTRAINT "usuarios_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vendedor_horarios"
    ADD CONSTRAINT "vendedor_horarios_id_vendedor_id_tianguis_fkey" FOREIGN KEY ("id_vendedor", "id_tianguis") REFERENCES "public"."vendedor_tianguis"("id_vendedor", "id_tianguis") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vendedor_tianguis"
    ADD CONSTRAINT "vendedor_tianguis_id_tianguis_fkey" FOREIGN KEY ("id_tianguis") REFERENCES "public"."tianguis"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vendedor_tianguis"
    ADD CONSTRAINT "vendedor_tianguis_id_vendedor_fkey" FOREIGN KEY ("id_vendedor") REFERENCES "public"."perfiles_vendedor"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."versiones_documento"
    ADD CONSTRAINT "versiones_documento_publicado_por_fkey" FOREIGN KEY ("publicado_por") REFERENCES "public"."usuarios"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."visitas"
    ADD CONSTRAINT "visitas_id_jornada_fkey" FOREIGN KEY ("id_jornada") REFERENCES "public"."jornadas_puesto"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."visitas"
    ADD CONSTRAINT "visitas_id_puesto_fkey" FOREIGN KEY ("id_puesto") REFERENCES "public"."puestos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."visitas"
    ADD CONSTRAINT "visitas_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



CREATE POLICY "acep_ins" ON "public"."aceptaciones_terminos" FOR INSERT TO "authenticated" WITH CHECK (("id_usuario" = "auth"."uid"()));



CREATE POLICY "aceptaciones_insert" ON "public"."aceptaciones_terminos" FOR INSERT TO "authenticated" WITH CHECK (("id_usuario" = "auth"."uid"()));



CREATE POLICY "aceptaciones_select" ON "public"."aceptaciones_terminos" FOR SELECT TO "authenticated" USING ((("id_usuario" = "auth"."uid"()) OR "public"."es_admin"()));



ALTER TABLE "public"."aceptaciones_terminos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_read_productos" ON "public"."productos" FOR SELECT TO "authenticated" USING ("public"."es_admin"());



ALTER TABLE "public"."administradores" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admins_select" ON "public"."administradores" FOR SELECT TO "authenticated" USING ((("id_usuario" = "auth"."uid"()) OR "public"."es_admin"()));



CREATE POLICY "anuncios_delete" ON "public"."anuncios_espacio" FOR DELETE TO "authenticated" USING (("public"."soy_vendedor"("id_vendedor") OR "public"."es_admin"()));



ALTER TABLE "public"."anuncios_espacio" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "anuncios_insert" ON "public"."anuncios_espacio" FOR INSERT TO "authenticated" WITH CHECK (("public"."soy_vendedor"("id_vendedor") AND "public"."cuenta_activa"()));



CREATE POLICY "anuncios_select" ON "public"."anuncios_espacio" FOR SELECT TO "authenticated" USING ((((NOT "moderado") AND (EXISTS ( SELECT 1
   FROM "public"."perfiles_vendedor"
  WHERE ("perfiles_vendedor"."id_usuario" = "auth"."uid"())))) OR "public"."soy_vendedor"("id_vendedor") OR "public"."es_admin"()));



CREATE POLICY "anuncios_update" ON "public"."anuncios_espacio" FOR UPDATE TO "authenticated" USING ("public"."soy_vendedor"("id_vendedor")) WITH CHECK ("public"."soy_vendedor"("id_vendedor"));



CREATE POLICY "apart_insert" ON "public"."apartados" FOR INSERT TO "authenticated" WITH CHECK ((("id_comprador" = "auth"."uid"()) AND ("estado" = 'pendiente'::"public"."estado_apartado") AND "public"."cuenta_activa"()));



CREATE POLICY "apart_select" ON "public"."apartados" FOR SELECT TO "authenticated" USING ((("id_comprador" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."perfiles_vendedor" "v"
  WHERE (("v"."id" = "apartados"."id_vendedor") AND ("v"."id_usuario" = "auth"."uid"()))))));



CREATE POLICY "apart_update" ON "public"."apartados" FOR UPDATE TO "authenticated" USING ((("id_comprador" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."perfiles_vendedor" "v"
  WHERE (("v"."id" = "apartados"."id_vendedor") AND ("v"."id_usuario" = "auth"."uid"()))))));



ALTER TABLE "public"."apartados" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "apel_insert" ON "public"."apelaciones" FOR INSERT TO "authenticated" WITH CHECK ((("id_usuario" = "auth"."uid"()) AND ("estado" = 'pendiente'::"public"."estado_apelacion")));



CREATE POLICY "apel_select" ON "public"."apelaciones" FOR SELECT TO "authenticated" USING ((("id_usuario" = "auth"."uid"()) OR "public"."es_admin"()));



CREATE POLICY "apel_update" ON "public"."apelaciones" FOR UPDATE TO "authenticated" USING ("public"."es_admin"()) WITH CHECK ("public"."es_admin"());



ALTER TABLE "public"."apelaciones" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "aus_select" ON "public"."ausencias_programadas" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "aus_write" ON "public"."ausencias_programadas" TO "authenticated" USING ("public"."soy_vendedor"("id_vendedor")) WITH CHECK ("public"."soy_vendedor"("id_vendedor"));



ALTER TABLE "public"."ausencias_programadas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bloqueos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bloqueos_insert" ON "public"."bloqueos" FOR INSERT TO "authenticated" WITH CHECK (("id_bloqueador" = "auth"."uid"()));



CREATE POLICY "bloqueos_select" ON "public"."bloqueos" FOR SELECT TO "authenticated" USING ((("id_bloqueador" = "auth"."uid"()) OR "public"."es_admin"()));



CREATE POLICY "bloqueos_update" ON "public"."bloqueos" FOR UPDATE TO "authenticated" USING (("id_bloqueador" = "auth"."uid"())) WITH CHECK (("id_bloqueador" = "auth"."uid"()));



CREATE POLICY "calif_et_select" ON "public"."calificacion_etiquetas" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "calif_et_write" ON "public"."calificacion_etiquetas" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."calificaciones" "c"
  WHERE (("c"."id" = "calificacion_etiquetas"."id_calificacion") AND ("c"."id_usuario" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."calificaciones" "c"
  WHERE (("c"."id" = "calificacion_etiquetas"."id_calificacion") AND ("c"."id_usuario" = "auth"."uid"())))));



CREATE POLICY "calif_insert" ON "public"."calificaciones" FOR INSERT TO "authenticated" WITH CHECK ((("id_usuario" = "auth"."uid"()) AND "public"."cuenta_activa"() AND (EXISTS ( SELECT 1
   FROM "public"."visitas" "v"
  WHERE (("v"."id" = "calificaciones"."id_visita") AND ("v"."id_usuario" = "auth"."uid"()))))));



CREATE POLICY "calif_select" ON "public"."calificaciones" FOR SELECT TO "authenticated" USING (((NOT "moderado") OR ("id_usuario" = "auth"."uid"()) OR "public"."soy_vendedor"("id_vendedor") OR "public"."es_admin"()));



CREATE POLICY "calif_update" ON "public"."calificaciones" FOR UPDATE TO "authenticated" USING (("id_usuario" = "auth"."uid"())) WITH CHECK (("id_usuario" = "auth"."uid"()));



ALTER TABLE "public"."calificacion_etiquetas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."calificaciones" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."categorias" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "categorias_admin" ON "public"."categorias" TO "authenticated" USING ("public"."es_admin"()) WITH CHECK ("public"."es_admin"());



CREATE POLICY "categorias_select" ON "public"."categorias" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "codigos_select" ON "public"."codigos_visita" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."jornadas_puesto" "j"
     JOIN "public"."puestos" "p" ON (("p"."id" = "j"."id_puesto")))
  WHERE (("j"."id" = "codigos_visita"."id_jornada") AND "public"."soy_vendedor"("p"."id_vendedor")))));



ALTER TABLE "public"."codigos_visita" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conv_insert" ON "public"."conversaciones" FOR INSERT TO "authenticated" WITH CHECK ((("id_iniciador" = "auth"."uid"()) AND "public"."cuenta_activa"() AND (NOT "public"."hay_bloqueo"("id_iniciador", "id_receptor"))));



CREATE POLICY "conv_select" ON "public"."conversaciones" FOR SELECT TO "authenticated" USING (((("auth"."uid"() = "id_iniciador") OR ("auth"."uid"() = "id_receptor")) OR "public"."es_admin"()));



ALTER TABLE "public"."conversaciones" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "disp_all" ON "public"."dispositivos_push" TO "authenticated" USING (("id_usuario" = "auth"."uid"())) WITH CHECK (("id_usuario" = "auth"."uid"()));



ALTER TABLE "public"."dispositivos_push" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "etiquetas_admin" ON "public"."etiquetas_valoracion" TO "authenticated" USING ("public"."es_admin"()) WITH CHECK ("public"."es_admin"());



CREATE POLICY "etiquetas_select" ON "public"."etiquetas_valoracion" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."etiquetas_valoracion" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fav_all" ON "public"."favoritos" TO "authenticated" USING (("id_usuario" = "auth"."uid"())) WITH CHECK (("id_usuario" = "auth"."uid"()));



ALTER TABLE "public"."favoritos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "imagenes_select" ON "public"."producto_imagenes" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."productos" "p"
  WHERE ("p"."id" = "producto_imagenes"."id_producto"))));



CREATE POLICY "imagenes_write" ON "public"."producto_imagenes" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."productos" "p"
  WHERE (("p"."id" = "producto_imagenes"."id_producto") AND "public"."soy_vendedor"("p"."id_vendedor"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."productos" "p"
  WHERE (("p"."id" = "producto_imagenes"."id_producto") AND "public"."soy_vendedor"("p"."id_vendedor")))));



CREATE POLICY "int_all" ON "public"."intereses_categoria" TO "authenticated" USING (("id_usuario" = "auth"."uid"())) WITH CHECK (("id_usuario" = "auth"."uid"()));



ALTER TABLE "public"."intereses_categoria" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."jornadas_puesto" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "jornadas_select" ON "public"."jornadas_puesto" FOR SELECT TO "authenticated" USING (("public"."es_admin"() OR (EXISTS ( SELECT 1
   FROM "public"."puestos" "p"
  WHERE (("p"."id" = "jornadas_puesto"."id_puesto") AND "public"."soy_vendedor"("p"."id_vendedor"))))));



CREATE POLICY "med_admin" ON "public"."medidas_moderacion" TO "authenticated" USING ("public"."es_admin"()) WITH CHECK ("public"."es_admin"());



CREATE POLICY "med_select" ON "public"."medidas_moderacion" FOR SELECT TO "authenticated" USING ((("id_usuario_afectado" = "auth"."uid"()) OR "public"."es_admin"()));



ALTER TABLE "public"."medidas_moderacion" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mensajes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "msg_insert" ON "public"."mensajes" FOR INSERT TO "authenticated" WITH CHECK ((("id_remitente" = "auth"."uid"()) AND "public"."cuenta_activa"()));



CREATE POLICY "msg_select" ON "public"."mensajes" FOR SELECT TO "authenticated" USING ((((NOT "moderado") AND (EXISTS ( SELECT 1
   FROM "public"."conversaciones" "c"
  WHERE (("c"."id" = "mensajes"."id_conversacion") AND (("auth"."uid"() = "c"."id_iniciador") OR ("auth"."uid"() = "c"."id_receptor")))))) OR ("public"."es_admin"() AND (EXISTS ( SELECT 1
   FROM "public"."reportes" "r"
  WHERE (("r"."tipo_objetivo" = 'mensaje'::"public"."tipo_objetivo") AND ("r"."id_objetivo" = "mensajes"."id")))))));



CREATE POLICY "msg_update" ON "public"."mensajes" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."conversaciones" "c"
  WHERE (("c"."id" = "mensajes"."id_conversacion") AND (("auth"."uid"() = "c"."id_iniciador") OR ("auth"."uid"() = "c"."id_receptor")) AND ("mensajes"."id_remitente" <> "auth"."uid"())))));



CREATE POLICY "notif_delete" ON "public"."notificaciones" FOR DELETE TO "authenticated" USING (("id_usuario" = "auth"."uid"()));



CREATE POLICY "notif_select" ON "public"."notificaciones" FOR SELECT TO "authenticated" USING (("id_usuario" = "auth"."uid"()));



CREATE POLICY "notif_update" ON "public"."notificaciones" FOR UPDATE TO "authenticated" USING (("id_usuario" = "auth"."uid"()));



ALTER TABLE "public"."notificaciones" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "oferta_prod_select" ON "public"."oferta_productos" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "oferta_prod_write" ON "public"."oferta_productos" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."ofertas" "o"
  WHERE (("o"."id" = "oferta_productos"."id_oferta") AND "public"."soy_vendedor"("o"."id_vendedor"))))) WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."ofertas" "o"
  WHERE (("o"."id" = "oferta_productos"."id_oferta") AND "public"."soy_vendedor"("o"."id_vendedor")))) AND (EXISTS ( SELECT 1
   FROM ("public"."productos" "p"
     JOIN "public"."ofertas" "o2" ON ((("o2"."id" = "oferta_productos"."id_oferta") AND ("o2"."id_vendedor" = "p"."id_vendedor"))))
  WHERE ("p"."id" = "oferta_productos"."id_producto")))));



ALTER TABLE "public"."oferta_productos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ofertas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ofertas_select" ON "public"."ofertas" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "ofertas_write" ON "public"."ofertas" TO "authenticated" USING ("public"."soy_vendedor"("id_vendedor")) WITH CHECK ("public"."soy_vendedor"("id_vendedor"));



ALTER TABLE "public"."perfiles_vendedor" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pref_all" ON "public"."preferencias_notificacion" TO "authenticated" USING (("id_usuario" = "auth"."uid"())) WITH CHECK (("id_usuario" = "auth"."uid"()));



ALTER TABLE "public"."preferencias_notificacion" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."producto_imagenes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."productos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "productos_delete" ON "public"."productos" FOR DELETE TO "authenticated" USING (("public"."soy_vendedor"("id_vendedor") OR "public"."es_admin"()));



CREATE POLICY "productos_insert" ON "public"."productos" FOR INSERT TO "authenticated" WITH CHECK (("public"."soy_vendedor"("id_vendedor") AND "public"."cuenta_activa"()));



CREATE POLICY "productos_select" ON "public"."productos" FOR SELECT TO "authenticated" USING ((("activo" AND (NOT "moderado")) OR "public"."soy_vendedor"("id_vendedor") OR "public"."es_admin"()));



CREATE POLICY "productos_update" ON "public"."productos" FOR UPDATE TO "authenticated" USING ("public"."soy_vendedor"("id_vendedor")) WITH CHECK ("public"."soy_vendedor"("id_vendedor"));



CREATE POLICY "prop_insert" ON "public"."propuestas_precio" FOR INSERT TO "authenticated" WITH CHECK ((("id_emisor" = "auth"."uid"()) AND "public"."cuenta_activa"() AND (("id_comprador" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."perfiles_vendedor" "v"
  WHERE (("v"."id" = "propuestas_precio"."id_vendedor") AND ("v"."id_usuario" = "auth"."uid"())))))));



CREATE POLICY "prop_select" ON "public"."propuestas_precio" FOR SELECT TO "authenticated" USING ((("id_comprador" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."perfiles_vendedor" "v"
  WHERE (("v"."id" = "propuestas_precio"."id_vendedor") AND ("v"."id_usuario" = "auth"."uid"()))))));



CREATE POLICY "prop_update" ON "public"."propuestas_precio" FOR UPDATE TO "authenticated" USING ((("id_comprador" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."perfiles_vendedor" "v"
  WHERE (("v"."id" = "propuestas_precio"."id_vendedor") AND ("v"."id_usuario" = "auth"."uid"()))))));



ALTER TABLE "public"."propuestas_precio" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."puestos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "puestos_delete" ON "public"."puestos" FOR DELETE TO "authenticated" USING (("public"."soy_vendedor"("id_vendedor") OR "public"."es_admin"()));



CREATE POLICY "puestos_insert" ON "public"."puestos" FOR INSERT TO "authenticated" WITH CHECK ("public"."soy_vendedor"("id_vendedor"));



CREATE POLICY "puestos_select" ON "public"."puestos" FOR SELECT TO "authenticated" USING (("activo" OR "public"."soy_vendedor"("id_vendedor") OR "public"."es_admin"()));



CREATE POLICY "puestos_update" ON "public"."puestos" FOR UPDATE TO "authenticated" USING (("public"."soy_vendedor"("id_vendedor") OR "public"."es_admin"())) WITH CHECK (("public"."soy_vendedor"("id_vendedor") OR "public"."es_admin"()));



CREATE POLICY "pv_insert" ON "public"."perfiles_vendedor" FOR INSERT TO "authenticated" WITH CHECK ((("id_usuario" = "auth"."uid"()) AND "public"."cuenta_activa"()));



CREATE POLICY "pv_select" ON "public"."perfiles_vendedor" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "pv_update" ON "public"."perfiles_vendedor" FOR UPDATE TO "authenticated" USING ((("id_usuario" = "auth"."uid"()) OR "public"."es_admin"())) WITH CHECK ((("id_usuario" = "auth"."uid"()) OR "public"."es_admin"()));



CREATE POLICY "rep_insert" ON "public"."reportes" FOR INSERT TO "authenticated" WITH CHECK ((("id_reportante" = "auth"."uid"()) AND ("estado" = 'pendiente'::"public"."estado_reporte")));



CREATE POLICY "rep_select" ON "public"."reportes" FOR SELECT TO "authenticated" USING ((("id_reportante" = "auth"."uid"()) OR "public"."es_admin"()));



CREATE POLICY "rep_update" ON "public"."reportes" FOR UPDATE TO "authenticated" USING ("public"."es_admin"()) WITH CHECK ("public"."es_admin"());



ALTER TABLE "public"."reportes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sil_all" ON "public"."silencios_notificacion" TO "authenticated" USING (("id_usuario" = "auth"."uid"())) WITH CHECK (("id_usuario" = "auth"."uid"()));



ALTER TABLE "public"."silencios_notificacion" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tianguis" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tianguis_admin" ON "public"."tianguis" TO "authenticated" USING ("public"."es_admin"()) WITH CHECK ("public"."es_admin"());



ALTER TABLE "public"."tianguis_horarios" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tianguis_horarios_admin" ON "public"."tianguis_horarios" TO "authenticated" USING ("public"."es_admin"()) WITH CHECK ("public"."es_admin"());



CREATE POLICY "tianguis_horarios_select" ON "public"."tianguis_horarios" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "tianguis_select" ON "public"."tianguis" FOR SELECT TO "authenticated" USING (("activo" OR "public"."es_admin"()));



ALTER TABLE "public"."tianguis_zonas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tianguis_zonas_admin" ON "public"."tianguis_zonas" TO "authenticated" USING ("public"."es_admin"()) WITH CHECK ("public"."es_admin"());



CREATE POLICY "tianguis_zonas_select" ON "public"."tianguis_zonas" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."usuarios" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "usuarios_select" ON "public"."usuarios" FOR SELECT TO "authenticated" USING ((("id" = "auth"."uid"()) OR "public"."es_admin"()));



CREATE POLICY "usuarios_update" ON "public"."usuarios" FOR UPDATE TO "authenticated" USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



ALTER TABLE "public"."vendedor_horarios" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vendedor_tianguis" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "versiones_admin" ON "public"."versiones_documento" TO "authenticated" USING ("public"."es_admin"()) WITH CHECK ("public"."es_admin"());



ALTER TABLE "public"."versiones_documento" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "versiones_select" ON "public"."versiones_documento" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "vh_select" ON "public"."vendedor_horarios" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "vh_write" ON "public"."vendedor_horarios" TO "authenticated" USING ("public"."soy_vendedor"("id_vendedor")) WITH CHECK ("public"."soy_vendedor"("id_vendedor"));



ALTER TABLE "public"."visitas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "visitas_select" ON "public"."visitas" FOR SELECT TO "authenticated" USING ((("id_usuario" = "auth"."uid"()) OR "public"."es_admin"() OR (EXISTS ( SELECT 1
   FROM "public"."puestos" "p"
  WHERE (("p"."id" = "visitas"."id_puesto") AND "public"."soy_vendedor"("p"."id_vendedor"))))));



CREATE POLICY "vt_select" ON "public"."vendedor_tianguis" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "vt_write" ON "public"."vendedor_tianguis" TO "authenticated" USING ("public"."soy_vendedor"("id_vendedor")) WITH CHECK ("public"."soy_vendedor"("id_vendedor"));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."apartados";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."mensajes";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notificaciones";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."propuestas_precio";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."puestos";



-- Al restaurar, las tablas pueden heredar GRANTs del entorno Supabase local.
-- Limpiar esos permisos antes de reproducir las concesiones de la exportación.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated, PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."abrir_puesto"("p_id_puesto" "uuid", "p_latitud" double precision, "p_longitud" double precision, "p_precision" real) TO "anon";
GRANT ALL ON FUNCTION "public"."abrir_puesto"("p_id_puesto" "uuid", "p_latitud" double precision, "p_longitud" double precision, "p_precision" real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."abrir_puesto"("p_id_puesto" "uuid", "p_latitud" double precision, "p_longitud" double precision, "p_precision" real) TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_cambiar_estado_cuenta"("p_id" "uuid", "p_estado" "public"."estado_cuenta") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_cambiar_estado_cuenta"("p_id" "uuid", "p_estado" "public"."estado_cuenta") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_cambiar_estado_cuenta"("p_id" "uuid", "p_estado" "public"."estado_cuenta") TO "service_role";



GRANT ALL ON FUNCTION "public"."calificacion_desde_visita"() TO "anon";
GRANT ALL ON FUNCTION "public"."calificacion_desde_visita"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."calificacion_desde_visita"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cerrar_puesto"("p_id_puesto" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."cerrar_puesto"("p_id_puesto" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cerrar_puesto"("p_id_puesto" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."confirmar_visita"("p_codigo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."confirmar_visita"("p_codigo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirmar_visita"("p_codigo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."cuenta_activa"() TO "anon";
GRANT ALL ON FUNCTION "public"."cuenta_activa"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cuenta_activa"() TO "service_role";



GRANT ALL ON FUNCTION "public"."efecto_medida"() TO "anon";
GRANT ALL ON FUNCTION "public"."efecto_medida"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."efecto_medida"() TO "service_role";



GRANT ALL ON FUNCTION "public"."es_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."es_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."es_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."es_anonimo"("p_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."es_anonimo"("p_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."es_anonimo"("p_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."expirar_apartados"() TO "anon";
GRANT ALL ON FUNCTION "public"."expirar_apartados"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."expirar_apartados"() TO "service_role";



GRANT ALL ON FUNCTION "public"."expirar_ofertas"() TO "anon";
GRANT ALL ON FUNCTION "public"."expirar_ofertas"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."expirar_ofertas"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fijar_vendedor_desde_producto"() TO "anon";
GRANT ALL ON FUNCTION "public"."fijar_vendedor_desde_producto"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fijar_vendedor_desde_producto"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generar_codigo_visita"("p_id_puesto" "uuid", "p_minutos" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."generar_codigo_visita"("p_id_puesto" "uuid", "p_minutos" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."generar_codigo_visita"("p_id_puesto" "uuid", "p_minutos" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."hay_bloqueo"("a" "uuid", "b" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."hay_bloqueo"("a" "uuid", "b" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hay_bloqueo"("a" "uuid", "b" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."limpiar_codigos_visita"() TO "anon";
GRANT ALL ON FUNCTION "public"."limpiar_codigos_visita"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."limpiar_codigos_visita"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mi_vendedor_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."mi_vendedor_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mi_vendedor_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notificar_ausencia"() TO "anon";
GRANT ALL ON FUNCTION "public"."notificar_ausencia"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notificar_ausencia"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notificar_medida"() TO "anon";
GRANT ALL ON FUNCTION "public"."notificar_medida"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notificar_medida"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notificar_oferta"() TO "anon";
GRANT ALL ON FUNCTION "public"."notificar_oferta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notificar_oferta"() TO "service_role";



GRANT ALL ON TABLE "public"."calificaciones" TO "authenticated";
GRANT ALL ON TABLE "public"."calificaciones" TO "service_role";



GRANT ALL ON TABLE "public"."categorias" TO "authenticated";
GRANT ALL ON TABLE "public"."categorias" TO "service_role";



GRANT ALL ON TABLE "public"."favoritos" TO "authenticated";
GRANT ALL ON TABLE "public"."favoritos" TO "service_role";



GRANT ALL ON TABLE "public"."perfiles_vendedor" TO "authenticated";
GRANT ALL ON TABLE "public"."perfiles_vendedor" TO "service_role";



GRANT ALL ON TABLE "public"."producto_imagenes" TO "authenticated";
GRANT ALL ON TABLE "public"."producto_imagenes" TO "service_role";



GRANT ALL ON TABLE "public"."productos" TO "authenticated";
GRANT ALL ON TABLE "public"."productos" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."puestos" TO "authenticated";
GRANT ALL ON TABLE "public"."puestos" TO "service_role";



GRANT UPDATE("nombre") ON TABLE "public"."puestos" TO "authenticated";



GRANT UPDATE("codigo") ON TABLE "public"."puestos" TO "authenticated";



GRANT UPDATE("activo") ON TABLE "public"."puestos" TO "authenticated";



GRANT ALL ON TABLE "public"."tianguis" TO "authenticated";
GRANT ALL ON TABLE "public"."tianguis" TO "service_role";



GRANT ALL ON TABLE "public"."tianguis_horarios" TO "authenticated";
GRANT ALL ON TABLE "public"."tianguis_horarios" TO "service_role";



GRANT ALL ON TABLE "public"."v_puestos_resumen" TO "service_role";



GRANT ALL ON FUNCTION "public"."puesto_destacado"("p_categoria" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."puesto_destacado"("p_categoria" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."puesto_destacado"("p_categoria" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."puestos_limpiar_cierre"() TO "anon";
GRANT ALL ON FUNCTION "public"."puestos_limpiar_cierre"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."puestos_limpiar_cierre"() TO "service_role";



GRANT ALL ON FUNCTION "public"."puestos_tendencia"("p_categoria" "uuid", "p_limite" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."puestos_tendencia"("p_categoria" "uuid", "p_limite" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."puestos_tendencia"("p_categoria" "uuid", "p_limite" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."resumen_inicio"() TO "anon";
GRANT ALL ON FUNCTION "public"."resumen_inicio"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."resumen_inicio"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_actualizado_en"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_actualizado_en"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_actualizado_en"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "postgres";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "anon";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "service_role";



GRANT ALL ON FUNCTION "public"."show_limit"() TO "postgres";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "anon";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "service_role";



GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."soy_vendedor"("p_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."soy_vendedor"("p_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."soy_vendedor"("p_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "service_role";



GRANT ALL ON TABLE "public"."versiones_documento" TO "authenticated";
GRANT ALL ON TABLE "public"."versiones_documento" TO "service_role";



GRANT ALL ON FUNCTION "public"."terminos_pendientes"() TO "anon";
GRANT ALL ON FUNCTION "public"."terminos_pendientes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."terminos_pendientes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."tg_solo_cuentas_reales"() TO "anon";
GRANT ALL ON FUNCTION "public"."tg_solo_cuentas_reales"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."tg_solo_cuentas_reales"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validar_mensaje"() TO "anon";
GRANT ALL ON FUNCTION "public"."validar_mensaje"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validar_mensaje"() TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "service_role";


















GRANT ALL ON TABLE "public"."aceptaciones_terminos" TO "authenticated";
GRANT ALL ON TABLE "public"."aceptaciones_terminos" TO "service_role";



GRANT ALL ON TABLE "public"."administradores" TO "authenticated";
GRANT ALL ON TABLE "public"."administradores" TO "service_role";



GRANT ALL ON TABLE "public"."anuncios_espacio" TO "authenticated";
GRANT ALL ON TABLE "public"."anuncios_espacio" TO "service_role";



GRANT ALL ON TABLE "public"."apartados" TO "authenticated";
GRANT ALL ON TABLE "public"."apartados" TO "service_role";



GRANT ALL ON TABLE "public"."apelaciones" TO "authenticated";
GRANT ALL ON TABLE "public"."apelaciones" TO "service_role";



GRANT ALL ON TABLE "public"."ausencias_programadas" TO "authenticated";
GRANT ALL ON TABLE "public"."ausencias_programadas" TO "service_role";



GRANT ALL ON TABLE "public"."bloqueos" TO "authenticated";
GRANT ALL ON TABLE "public"."bloqueos" TO "service_role";



GRANT ALL ON TABLE "public"."calificacion_etiquetas" TO "authenticated";
GRANT ALL ON TABLE "public"."calificacion_etiquetas" TO "service_role";



GRANT ALL ON TABLE "public"."codigos_visita" TO "authenticated";
GRANT ALL ON TABLE "public"."codigos_visita" TO "service_role";



GRANT ALL ON TABLE "public"."conversaciones" TO "authenticated";
GRANT ALL ON TABLE "public"."conversaciones" TO "service_role";



GRANT ALL ON TABLE "public"."dispositivos_push" TO "authenticated";
GRANT ALL ON TABLE "public"."dispositivos_push" TO "service_role";



GRANT ALL ON TABLE "public"."etiquetas_valoracion" TO "authenticated";
GRANT ALL ON TABLE "public"."etiquetas_valoracion" TO "service_role";



GRANT ALL ON TABLE "public"."intereses_categoria" TO "authenticated";
GRANT ALL ON TABLE "public"."intereses_categoria" TO "service_role";



GRANT ALL ON TABLE "public"."jornadas_puesto" TO "authenticated";
GRANT ALL ON TABLE "public"."jornadas_puesto" TO "service_role";



GRANT ALL ON TABLE "public"."medidas_moderacion" TO "authenticated";
GRANT ALL ON TABLE "public"."medidas_moderacion" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."mensajes" TO "authenticated";
GRANT ALL ON TABLE "public"."mensajes" TO "service_role";



GRANT UPDATE("leido_en") ON TABLE "public"."mensajes" TO "authenticated";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."notificaciones" TO "authenticated";
GRANT ALL ON TABLE "public"."notificaciones" TO "service_role";



GRANT UPDATE("leida") ON TABLE "public"."notificaciones" TO "authenticated";



GRANT ALL ON TABLE "public"."oferta_productos" TO "authenticated";
GRANT ALL ON TABLE "public"."oferta_productos" TO "service_role";



GRANT ALL ON TABLE "public"."ofertas" TO "authenticated";
GRANT ALL ON TABLE "public"."ofertas" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."usuarios" TO "authenticated";
GRANT ALL ON TABLE "public"."usuarios" TO "service_role";



GRANT UPDATE("nombre_publico") ON TABLE "public"."usuarios" TO "authenticated";



GRANT UPDATE("telefono") ON TABLE "public"."usuarios" TO "authenticated";



GRANT UPDATE("foto_url") ON TABLE "public"."usuarios" TO "authenticated";



GRANT ALL ON TABLE "public"."perfiles_publicos" TO "authenticated";
GRANT ALL ON TABLE "public"."perfiles_publicos" TO "service_role";



GRANT ALL ON TABLE "public"."preferencias_notificacion" TO "authenticated";
GRANT ALL ON TABLE "public"."preferencias_notificacion" TO "service_role";



GRANT ALL ON TABLE "public"."productos_catalogo" TO "authenticated";
GRANT ALL ON TABLE "public"."productos_catalogo" TO "service_role";



GRANT ALL ON TABLE "public"."propuestas_precio" TO "authenticated";
GRANT ALL ON TABLE "public"."propuestas_precio" TO "service_role";



GRANT ALL ON TABLE "public"."puestos_abiertos" TO "authenticated";
GRANT ALL ON TABLE "public"."puestos_abiertos" TO "service_role";



GRANT ALL ON TABLE "public"."reportes" TO "authenticated";
GRANT ALL ON TABLE "public"."reportes" TO "service_role";



GRANT ALL ON TABLE "public"."resumen_calificaciones" TO "authenticated";
GRANT ALL ON TABLE "public"."resumen_calificaciones" TO "service_role";



GRANT ALL ON TABLE "public"."silencios_notificacion" TO "authenticated";
GRANT ALL ON TABLE "public"."silencios_notificacion" TO "service_role";



GRANT ALL ON TABLE "public"."tianguis_zonas" TO "authenticated";
GRANT ALL ON TABLE "public"."tianguis_zonas" TO "service_role";



GRANT ALL ON TABLE "public"."vendedor_horarios" TO "authenticated";
GRANT ALL ON TABLE "public"."vendedor_horarios" TO "service_role";



GRANT ALL ON TABLE "public"."vendedor_tianguis" TO "authenticated";
GRANT ALL ON TABLE "public"."vendedor_tianguis" TO "service_role";



GRANT ALL ON TABLE "public"."visitas" TO "authenticated";
GRANT ALL ON TABLE "public"."visitas" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
