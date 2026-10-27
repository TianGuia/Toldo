-- Creación segura de conversaciones desde PostgREST, sin ampliar membresía.
BEGIN;
INSERT INTO auth.users (id, email, is_anonymous) VALUES
 ('15000000-0000-0000-0000-000000000001', 'cliente-a@example.test', false),
 ('15000000-0000-0000-0000-000000000002', 'cliente-b@example.test', false);
INSERT INTO public.usuarios (id, nombre_publico) VALUES
 ('15000000-0000-0000-0000-000000000001', 'Cliente A'),
 ('15000000-0000-0000-0000-000000000002', 'Cliente B')
ON CONFLICT (id) DO UPDATE SET nombre_publico=EXCLUDED.nombre_publico;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '15000000-0000-0000-0000-000000000001', true);
DO $$
DECLARE nueva uuid; propia uuid;
BEGIN
  -- Regresión: conv_select no debe dar acceso solo por ser el iniciador.
  BEGIN
    INSERT INTO public.conversaciones (id_receptor)
      VALUES ('15000000-0000-0000-0000-000000000002') RETURNING id INTO nueva;
    RAISE EXCEPTION 'INSERT RETURNING pasó sin la membresía del trigger';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  nueva := public.iniciar_conversacion(NULL, '15000000-0000-0000-0000-000000000002');
  IF (SELECT count(*) FROM public.participantes WHERE id_conversacion = nueva) <> 2 THEN
    RAISE EXCEPTION 'La RPC no creó ambos participantes';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.conversaciones WHERE id = nueva) THEN
    RAISE EXCEPTION 'La RPC no permite recuperar la conversación';
  END IF;
  INSERT INTO public.mensajes (id_conversacion, id_remitente, contenido)
    VALUES (nueva, auth.uid(), 'Creación desde cliente') RETURNING id INTO propia;
  DELETE FROM public.participantes WHERE id_conversacion = nueva AND id_usuario = auth.uid();
  IF EXISTS (SELECT 1 FROM public.conversaciones WHERE id = nueva) THEN
    RAISE EXCEPTION 'El iniciador conserva acceso después de salir';
  END IF;
  propia := public.iniciar_conversacion();
  IF (SELECT count(*) FROM public.participantes WHERE id_conversacion = propia) <> 1 THEN
    RAISE EXCEPTION 'No permite conversación sin receptor';
  END IF;
  BEGIN
    PERFORM public.iniciar_conversacion(NULL, auth.uid());
    RAISE EXCEPTION 'Permite conversación consigo mismo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'No puedes iniciar un chat contigo mismo' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon', 'public.iniciar_conversacion(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon puede iniciar conversaciones';
  END IF;
END $$;
ROLLBACK;
