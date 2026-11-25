-- Entrega push: cada fila nueva en notificaciones dispara la Edge Function enviar-push.
-- Requiere (una sola vez, ver docs/push-notificaciones.md) los secretos de Vault
-- push_function_url y push_webhook_secret. Sin ellos el trigger no hace nada.

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Registra el token del teléfono para la persona con sesión. Si el token ya
-- estaba ligado a otra cuenta (mismo teléfono, otra sesión), lo reasigna.
CREATE OR REPLACE FUNCTION public.registrar_token_push(p_token text, p_plataforma text DEFAULT 'android')
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if auth.uid() is null then
    raise exception 'Sin sesión' using errcode = '28000';
  end if;
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception 'Token vacío' using errcode = '22023';
  end if;
  insert into dispositivos_push (id_usuario, token, plataforma)
  values (auth.uid(), trim(p_token), coalesce(nullif(trim(p_plataforma), ''), 'android'))
  on conflict (token) do update
    set id_usuario = excluded.id_usuario,
        plataforma = excluded.plataforma;
end $$;

CREATE OR REPLACE FUNCTION public.quitar_token_push(p_token text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if auth.uid() is null then
    return;
  end if;
  delete from dispositivos_push
   where token = trim(p_token) and id_usuario = auth.uid();
end $$;

REVOKE ALL ON FUNCTION public.registrar_token_push(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.quitar_token_push(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_token_push(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quitar_token_push(text) TO authenticated;

-- Trigger por sentencia: una oferta que avisa a 200 personas hace una sola llamada.
CREATE OR REPLACE FUNCTION public.enviar_push_notificaciones()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
declare
  v_url text;
  v_secreto text;
  v_ids uuid[];
begin
  select array_agg(id) into v_ids from nuevas;
  if v_ids is null then
    return null;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secreto
    from vault.decrypted_secrets where name = 'push_webhook_secret';
  if v_url is null or v_secreto is null then
    return null; -- push sin configurar: la notificación igual queda en la tabla
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secreto),
    body := jsonb_build_object('ids', to_jsonb(v_ids)),
    timeout_milliseconds := 5000);
  return null;
exception when others then
  -- un fallo del push nunca debe impedir que se cree la notificación
  raise warning 'enviar_push_notificaciones: %', sqlerrm;
  return null;
end $$;

REVOKE ALL ON FUNCTION public.enviar_push_notificaciones() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_enviar_push ON public.notificaciones;
CREATE TRIGGER trg_enviar_push
  AFTER INSERT ON public.notificaciones
  REFERENCING NEW TABLE AS nuevas
  FOR EACH STATEMENT EXECUTE FUNCTION public.enviar_push_notificaciones();
