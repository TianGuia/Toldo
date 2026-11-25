
begin;

insert into auth.users (id, is_anonymous) values
  ('21000000-0000-0000-0000-000000000001', true),
  ('21000002-0000-0000-0000-000000000002', true),
  ('21000003-0000-0000-0000-000000000003', true);

insert into public.conversaciones (id, id_iniciador, id_receptor) values
  ('21000000-0000-0000-0000-000000000010',
   '21000000-0000-0000-0000-000000000001',
   '21000002-0000-0000-0000-000000000002');

insert into public.mensajes (id_conversacion, id_remitente, contenido) values
  ('21000000-0000-0000-0000-000000000010',
   '21000000-0000-0000-0000-000000000001', 'Mensaje antes del cambio');

set local role authenticated;
select set_config('request.jwt.claim.sub', '21000002-0000-0000-0000-000000000002', true);
do $$ begin
  if not exists (select 1 from public.mis_conversaciones()
                  where ultimo_texto = 'Mensaje antes del cambio' and no_leidos = 1)
     or not exists (select 1 from public.notificaciones where cuerpo = 'Mensaje antes del cambio') then
    raise exception 'El participante actual debe ver su conversación y su aviso';
  end if;
end $$;
reset role;

delete from public.participantes
 where id_conversacion = '21000000-0000-0000-0000-000000000010'
   and id_usuario = '21000002-0000-0000-0000-000000000002';
insert into public.participantes values
  ('21000000-0000-0000-0000-000000000010', '21000003-0000-0000-0000-000000000003');
insert into public.mensajes (id_conversacion, id_remitente, contenido, enviado_en) values
  ('21000000-0000-0000-0000-000000000010',
   '21000000-0000-0000-0000-000000000001', 'Mensaje posterior al cambio', now() + interval '1 second');

do $$ begin
  if (select array_agg(id_usuario) from public.notificaciones where cuerpo = 'Mensaje posterior al cambio')
      is distinct from array['21000003-0000-0000-0000-000000000003'::uuid] then
    raise exception 'El aviso debe llegar únicamente al destinatario actual';
  end if;
end $$;

set local role authenticated;
do $$ begin
  if exists (select 1 from public.mis_conversaciones())
     or exists (select 1 from public.notificaciones where tipo = 'mensaje') then
    raise exception 'Una membresía revocada conserva acceso a datos del chat';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '21000000-0000-0000-0000-000000000001', true);
do $$ begin
  if (select id_otro from public.mis_conversaciones()) is distinct from
     '21000003-0000-0000-0000-000000000003'::uuid then
    raise exception 'La conversación debe mostrar al otro participante actual';
  end if;
end $$;
rollback;
