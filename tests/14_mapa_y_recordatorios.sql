begin;

do $$ begin
  if (select count(*) from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename in ('puestos', 'ofertas', 'productos', 'tianguis', 'tianguis_zonas')) <> 5 then
    raise exception 'Faltan las tablas de actualización de la app';
  end if;
end $$;

-- Simula dos ejecuciones del recordatorio de un tianguis favorito dentro de su ventana.
insert into auth.users (id, is_anonymous)
values ('25000000-0000-0000-0000-000000000001', true);
insert into public.tianguis (id, nombre) values ('25000000-0000-0000-0000-000000000002', 'Tianguis de prueba RF-14');
insert into public.tianguis_horarios (id_tianguis, dia_semana, hora_inicio, hora_fin)
values ('25000000-0000-0000-0000-000000000002', 3, '09:00', '13:00');
insert into public.favoritos (id_usuario, id_tianguis)
values ('25000000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-000000000002');

do $$ begin
  if public.generar_recordatorios_tianguis('2026-11-25 06:45:00-06') <> 0
     or public.generar_recordatorios_tianguis('2026-11-25 07:00:00-06') <> 1
     or public.generar_recordatorios_tianguis('2026-11-25 07:15:00-06') <> 0 then
    raise exception 'El recordatorio debe crearse una sola vez y dentro de la ventana';
  end if;
  if (select count(*) from public.notificaciones
      where id_usuario = '25000000-0000-0000-0000-000000000001'
        and tipo = 'recordatorio_tianguis'
        and datos->>'fecha' = '2026-11-25') <> 1 then
    raise exception 'Falta el aviso que puede leer el comprador';
  end if;
end $$;
rollback;
