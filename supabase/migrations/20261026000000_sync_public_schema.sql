-- Sincroniza public con la exportación del 2026-10-26, sin registros.

-- Conserva la migración inicial y la reducción de privilegios de clientes.

SET check_function_bodies = false;

CREATE TABLE IF NOT EXISTS "public"."conversaciones_ocultas" (
    "id_usuario" "uuid" NOT NULL,
    "id_conversacion" "uuid" NOT NULL,
    "ocultada_en" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."conversaciones_ocultas"
    ADD CONSTRAINT "conversaciones_ocultas_pkey" PRIMARY KEY ("id_usuario", "id_conversacion");

ALTER TABLE ONLY "public"."conversaciones_ocultas"
    ADD CONSTRAINT "conversaciones_ocultas_id_conversacion_fkey" FOREIGN KEY ("id_conversacion") REFERENCES "public"."conversaciones"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."conversaciones_ocultas"
    ADD CONSTRAINT "conversaciones_ocultas_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION "public"."es_mi_vendedor"("p_vendedor_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1
    from public.perfiles_vendedor
    where id = p_vendedor_id and id_usuario = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.usuarios (id, nombre_publico, correo)
  values (
    new.id,
    left(coalesce(nullif(trim(new.raw_user_meta_data->>'nombre_publico'), ''),
                  nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
                  'Invitado'), 80),
    new.email
  )
  on conflict (id) do nothing;

  insert into public.preferencias_notificacion (id_usuario)
  values (new.id)
  on conflict (id_usuario) do nothing;
  return new;
end $$;

CREATE OR REPLACE FUNCTION "public"."ocultar_conversacion"("p_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not exists (
    select 1 from public.conversaciones c
    where c.id = p_id and (c.id_iniciador = auth.uid() or c.id_receptor = auth.uid())
  ) then
    raise exception 'No participas en esa conversación';
  end if;
  insert into public.conversaciones_ocultas (id_usuario, id_conversacion, ocultada_en)
  values (auth.uid(), p_id, now())
  on conflict (id_usuario, id_conversacion) do update set ocultada_en = now();
end $$;

CREATE OR REPLACE FUNCTION "public"."responder_apartado"("p_id" "uuid", "p_accion" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare r record; v_user_vendedor uuid; es_v boolean; es_c boolean; e text; v_cant integer;
begin
  select * into r from public.apartados where id = p_id for update;
  if not found then raise exception 'Apartado no encontrado'; end if;

  select id_usuario into v_user_vendedor from public.perfiles_vendedor where id = r.id_vendedor;
  es_v := (auth.uid() = v_user_vendedor);
  es_c := (auth.uid() = r.id_comprador);
  if not (es_v or es_c) then raise exception 'No participas en este apartado'; end if;
  e := r.estado::text;

  perform set_config('tianguia.rpc', '1', true);

  if p_accion = 'aceptar' then
    if not es_v then raise exception 'Solo el vendedor puede aceptar'; end if;
    if e <> 'pendiente' then raise exception 'Este apartado ya fue respondido'; end if;
    if r.fecha_expiracion is not null and r.fecha_expiracion < now() then
      raise exception 'La solicitud ya venció';
    end if;
    select cantidad_disponible into v_cant from public.productos where id = r.id_producto for update;
    if v_cant is not null then
      if v_cant < r.cantidad then raise exception 'No hay suficientes piezas disponibles'; end if;
      update public.productos
         set cantidad_disponible = v_cant - r.cantidad,
             disponible = (v_cant - r.cantidad) > 0,
             actualizado_en = now()
       where id = r.id_producto;
    end if;
    -- el apartado aceptado dura 24 h a partir de que el vendedor acepta
    update public.apartados set estado = 'aceptado', fecha_expiracion = now() + interval '24 hours'
     where id = p_id;

  elsif p_accion = 'rechazar' then
    if not es_v then raise exception 'Solo el vendedor puede rechazar'; end if;
    if e <> 'pendiente' then raise exception 'Este apartado ya fue respondido'; end if;
    update public.apartados set estado = 'rechazado' where id = p_id;

  elsif p_accion = 'cancelar' then
    if not ((es_c and e in ('pendiente', 'aceptado')) or (es_v and e = 'aceptado')) then
      raise exception 'No se puede cancelar en este estado';
    end if;
    if e = 'aceptado' then
      update public.productos
         set cantidad_disponible = cantidad_disponible + r.cantidad, disponible = true,
             actualizado_en = now()
       where id = r.id_producto and cantidad_disponible is not null;
    end if;
    update public.apartados set estado = 'cancelado' where id = p_id;

  else
    raise exception 'Acción no válida: %', p_accion;
  end if;
end $$;

CREATE OR REPLACE FUNCTION "public"."responder_propuesta"("p_id" "uuid", "p_accion" "text", "p_monto" numeric DEFAULT NULL::numeric) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare r record; v_user_vendedor uuid; v_nuevo uuid;
begin
  select * into r from public.propuestas_precio where id = p_id for update;
  if not found then raise exception 'Propuesta no encontrada'; end if;

  select id_usuario into v_user_vendedor from public.perfiles_vendedor where id = r.id_vendedor;
  if auth.uid() is null or auth.uid() not in (r.id_comprador, v_user_vendedor) then
    raise exception 'No participas en esta propuesta';
  end if;
  if r.id_emisor = auth.uid() then
    raise exception 'Esta propuesta la envió otra persona: ella debe responderla';
  end if;
  if r.estado::text <> 'pendiente' then
    raise exception 'Esta propuesta ya fue respondida';
  end if;

  perform set_config('tianguia.rpc', '1', true);

  if p_accion = 'aceptar' then
    update public.propuestas_precio set estado = 'aceptada', respondida_en = now() where id = p_id;
    return p_id;
  elsif p_accion = 'rechazar' then
    update public.propuestas_precio set estado = 'rechazada', respondida_en = now() where id = p_id;
    return p_id;
  elsif p_accion = 'contraofertar' then
    if p_monto is null or p_monto < 0 then raise exception 'Escribe un monto válido'; end if;
    update public.propuestas_precio set estado = 'contraofertada', respondida_en = now() where id = p_id;
    insert into public.propuestas_precio
      (id_producto, id_comprador, id_vendedor, id_emisor, id_propuesta_anterior, monto)
    values (r.id_producto, r.id_comprador, r.id_vendedor, auth.uid(), p_id, p_monto)
    returning id into v_nuevo;
    return v_nuevo;
  end if;
  raise exception 'Acción no válida: %', p_accion;
end $$;

CREATE OR REPLACE FUNCTION "public"."tg_solo_cuentas_verificadas"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
begin
  if public.es_anonimo(new.id_usuario) then
    raise exception 'Verifica tu correo para poder ser vendedor.';
  end if;
  return new;
end $$;

CREATE OR REPLACE FUNCTION "public"."tg_sync_contacto"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update public.usuarios
     set correo = new.email,
         actualizado_en = now()
   where id = new.id;
  return new;
end $$;

CREATE OR REPLACE FUNCTION "public"."tratos_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if coalesce(current_setting('tianguia.rpc', true), '') = '1' or public.es_admin() then
    return new;
  end if;
  if new.estado is distinct from old.estado then
    raise exception 'Usa las opciones de la app para responder (el estado no se cambia directo)';
  end if;
  if tg_table_name = 'apartados' and (new.cantidad is distinct from old.cantidad
                                      or new.id_producto is distinct from old.id_producto) then
    raise exception 'No se puede modificar un apartado ya creado';
  end if;
  if tg_table_name = 'propuestas_precio' and (new.monto is distinct from old.monto
                                              or new.id_producto is distinct from old.id_producto) then
    raise exception 'No se puede modificar una propuesta ya enviada';
  end if;
  return new;
end $$;

CREATE OR REPLACE FUNCTION "public"."vencer_pendientes"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare a record;
begin
  perform set_config('tianguia.rpc', '1', true);

  for a in
    select id, id_producto, cantidad, estado::text as e from public.apartados
     where estado::text in ('pendiente', 'aceptado')
       and fecha_expiracion is not null and fecha_expiracion < now()
     for update
  loop
    if a.e = 'aceptado' then
      update public.productos
         set cantidad_disponible = cantidad_disponible + a.cantidad, disponible = true,
             actualizado_en = now()
       where id = a.id_producto and cantidad_disponible is not null;
    end if;
    update public.apartados set estado = 'expirado' where id = a.id;
  end loop;

  update public.ofertas set estado = 'finalizada'
   where estado::text = 'activa' and fecha_fin < now();
end $$;

CREATE OR REPLACE TRIGGER "administradores_verificado" BEFORE INSERT ON "public"."administradores" FOR EACH ROW EXECUTE FUNCTION "public"."tg_solo_cuentas_verificadas"();

CREATE OR REPLACE TRIGGER "apartados_guard" BEFORE UPDATE ON "public"."apartados" FOR EACH ROW EXECUTE FUNCTION "public"."tratos_guard"();

CREATE OR REPLACE TRIGGER "perfiles_vendedor_verificado" BEFORE INSERT ON "public"."perfiles_vendedor" FOR EACH ROW EXECUTE FUNCTION "public"."tg_solo_cuentas_verificadas"();

CREATE OR REPLACE TRIGGER "propuestas_guard" BEFORE UPDATE ON "public"."propuestas_precio" FOR EACH ROW EXECUTE FUNCTION "public"."tratos_guard"();

CREATE POLICY "tg_ocultas_propias" ON "public"."conversaciones_ocultas" TO "authenticated" USING (("id_usuario" = "auth"."uid"())) WITH CHECK (("id_usuario" = "auth"."uid"()));

CREATE POLICY "trato_usuarios_leer" ON "public"."usuarios" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."propuestas_precio" "pp"
  WHERE (("pp"."id_comprador" = "usuarios"."id") AND "public"."es_mi_vendedor"("pp"."id_vendedor")))) OR (EXISTS ( SELECT 1
   FROM "public"."apartados" "ap"
  WHERE (("ap"."id_comprador" = "usuarios"."id") AND "public"."es_mi_vendedor"("ap"."id_vendedor"))))));

ALTER TABLE public.conversaciones_ocultas ENABLE ROW LEVEL SECURITY;

-- CRUD como en el remoto, sin reintroducir privilegios administrativos.

REVOKE ALL ON TABLE public.conversaciones_ocultas FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.conversaciones_ocultas TO anon, authenticated;

GRANT ALL ON TABLE public.conversaciones_ocultas TO service_role;

-- Los permisos predeterminados de funciones también conceden acceso a anon.

-- El remoto restringe vencer_pendientes a authenticated y service_role.

REVOKE ALL ON FUNCTION public.vencer_pendientes() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.vencer_pendientes() TO authenticated, service_role;
