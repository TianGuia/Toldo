create or replace function public.notificar_mensaje()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conv record;
  v_destinatario uuid;
  v_remitente_nombre text;
  v_permite_mensajes boolean;
  v_cuerpo text;
begin
  if coalesce(new.moderado, false) then
    return new;
  end if;

  select id, contexto, id_producto, id_anuncio_espacio, id_iniciador, id_receptor
  into v_conv
  from public.conversaciones
  where id = new.id_conversacion;

  if not found then
    return new;
  end if;

  if v_conv.id_iniciador = new.id_remitente then
    v_destinatario := v_conv.id_receptor;
  elsif v_conv.id_receptor = new.id_remitente then
    v_destinatario := v_conv.id_iniciador;
  else
    return new;
  end if;

  if v_destinatario is null or v_destinatario = new.id_remitente then
    return new;
  end if;

  if exists (
    select 1
    from public.bloqueos b
    where b.activo = true
      and (
        (b.id_bloqueador = v_destinatario and b.id_bloqueado = new.id_remitente)
        or (b.id_bloqueador = new.id_remitente and b.id_bloqueado = v_destinatario)
      )
  ) then
    return new;
  end if;

  if exists (
    select 1
    from public.silencios_notificacion s
    where s.id_usuario = v_destinatario
      and s.id_vendedor = new.id_remitente
  ) then
    return new;
  end if;

  select coalesce(p.mensajes, true)
  into v_permite_mensajes
  from public.preferencias_notificacion p
  where p.id_usuario = v_destinatario;

  if coalesce(v_permite_mensajes, true) = false then
    return new;
  end if;

  select coalesce(nullif(trim(u.nombre_publico), ''), 'Nuevo mensaje')
  into v_remitente_nombre
  from public.usuarios u
  where u.id = new.id_remitente;

  v_remitente_nombre := coalesce(v_remitente_nombre, 'Nuevo mensaje');

  v_cuerpo := left(trim(coalesce(new.contenido, '')), 120);
  if length(trim(coalesce(new.contenido, ''))) > 120 then
    v_cuerpo := v_cuerpo || '...';
  end if;

  insert into public.notificaciones (
    id_usuario,
    tipo,
    titulo,
    cuerpo,
    datos
  )
  values (
    v_destinatario,
    'mensaje',
    v_remitente_nombre,
    v_cuerpo,
    jsonb_build_object(
      'id_conversacion', new.id_conversacion,
      'id_mensaje', new.id,
      'id_remitente', new.id_remitente,
      'contexto', v_conv.contexto,
      'id_producto', v_conv.id_producto,
      'id_anuncio_espacio', v_conv.id_anuncio_espacio
    )
  );

  return new;
end;
$$;

drop trigger if exists trg_notificar_mensaje on public.mensajes;

create trigger trg_notificar_mensaje
after insert on public.mensajes
for each row
execute function public.notificar_mensaje();

create or replace function public.notificar_propuesta_precio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_destinatario uuid;
  v_actor uuid;
  v_actor_nombre text;
  v_prod_nombre text;
  v_permite boolean;
  v_titulo text;
  v_cuerpo text;
begin
  if tg_op = 'INSERT' then
    v_actor := new.id_emisor;
    if new.id_emisor = new.id_comprador then
      v_destinatario := new.id_vendedor;
    else
      v_destinatario := new.id_comprador;
    end if;
  elsif tg_op = 'UPDATE' then
    if new.estado is not distinct from old.estado then
      return new;
    end if;

    if new.estado in ('aceptada', 'rechazada') then
      if new.id_emisor = new.id_comprador then
        v_actor := new.id_vendedor;
        v_destinatario := new.id_comprador;
      else
        v_actor := new.id_comprador;
        v_destinatario := new.id_vendedor;
      end if;
    elsif new.estado = 'cancelada' then
      v_actor := new.id_emisor;
      if new.id_emisor = new.id_comprador then
        v_destinatario := new.id_vendedor;
      else
        v_destinatario := new.id_comprador;
      end if;
    else
      return new;
    end if;
  end if;

  if v_destinatario is null or v_destinatario = v_actor then
    return new;
  end if;

  if exists (
    select 1
    from public.bloqueos b
    where b.activo = true
      and (
        (b.id_bloqueador = v_destinatario and b.id_bloqueado = v_actor)
        or (b.id_bloqueador = v_actor and b.id_bloqueado = v_destinatario)
      )
  ) then
    return new;
  end if;

  if exists (
    select 1
    from public.silencios_notificacion s
    where s.id_usuario = v_destinatario
      and s.id_vendedor = new.id_vendedor
  ) then
    return new;
  end if;

  select coalesce(p.apartados_propuestas, true)
  into v_permite
  from public.preferencias_notificacion p
  where p.id_usuario = v_destinatario;

  if coalesce(v_permite, true) = false then
    return new;
  end if;

  select coalesce(nullif(trim(nombre), ''), 'un producto')
  into v_prod_nombre
  from public.productos
  where id = new.id_producto;

  select coalesce(nullif(trim(nombre_publico), ''), 'Un usuario')
  into v_actor_nombre
  from public.usuarios
  where id = v_actor;

  v_prod_nombre := coalesce(v_prod_nombre, 'un producto');
  v_actor_nombre := coalesce(v_actor_nombre, 'Un usuario');

  if tg_op = 'INSERT' then
    if new.id_propuesta_anterior is not null then
      v_titulo := 'Nueva contraoferta';
      v_cuerpo := v_actor_nombre || ' contraofertó $' || trim(to_char(new.monto, 'FM999,999,990.##')) || ' por ' || v_prod_nombre;
    else
      v_titulo := 'Nueva propuesta de precio';
      v_cuerpo := v_actor_nombre || ' ofreció $' || trim(to_char(new.monto, 'FM999,999,990.##')) || ' por ' || v_prod_nombre;
    end if;
  else
    case new.estado
      when 'aceptada' then
        v_titulo := 'Propuesta aceptada';
        v_cuerpo := v_actor_nombre || ' aceptó la oferta de $' || trim(to_char(new.monto, 'FM999,999,990.##')) || ' por ' || v_prod_nombre;
      when 'rechazada' then
        v_titulo := 'Propuesta rechazada';
        v_cuerpo := v_actor_nombre || ' rechazó la oferta por ' || v_prod_nombre;
      when 'cancelada' then
        v_titulo := 'Propuesta cancelada';
        v_cuerpo := v_actor_nombre || ' canceló su oferta por ' || v_prod_nombre;
    end case;
  end if;

  insert into public.notificaciones (
    id_usuario,
    tipo,
    titulo,
    cuerpo,
    datos
  )
  values (
    v_destinatario,
    'propuesta_precio'::tipo_notificacion,
    v_titulo,
    v_cuerpo,
    jsonb_build_object(
      'id_propuesta', new.id,
      'id_producto', new.id_producto,
      'id_comprador', new.id_comprador,
      'id_vendedor', new.id_vendedor,
      'monto', new.monto,
      'estado', new.estado
    )
  );

  return new;
end;
$$;

drop trigger if exists trg_notificar_propuesta_precio on public.propuestas_precio;

create trigger trg_notificar_propuesta_precio
after insert or update of estado on public.propuestas_precio
for each row
execute function public.notificar_propuesta_precio();

create or replace function public.notificar_apartado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_destinatario uuid;
  v_actor uuid;
  v_comprador_nombre text;
  v_prod_nombre text;
  v_permite boolean;
  v_titulo text;
  v_cuerpo text;
begin
  if tg_op = 'INSERT' then
    v_actor := new.id_comprador;
    v_destinatario := new.id_vendedor;
  elsif tg_op = 'UPDATE' then
    if new.estado is not distinct from old.estado then
      return new;
    end if;

    if new.estado in ('aceptado', 'rechazado', 'expirado') then
      v_actor := new.id_vendedor;
      v_destinatario := new.id_comprador;
    elsif new.estado = 'cancelado' then
      v_actor := new.id_comprador;
      v_destinatario := new.id_vendedor;
    else
      return new;
    end if;
  end if;

  if v_destinatario is null or v_destinatario = v_actor then
    return new;
  end if;

  if exists (
    select 1
    from public.bloqueos b
    where b.activo = true
      and (
        (b.id_bloqueador = v_destinatario and b.id_bloqueado = v_actor)
        or (b.id_bloqueador = v_actor and b.id_bloqueado = v_destinatario)
      )
  ) then
    return new;
  end if;

  if exists (
    select 1
    from public.silencios_notificacion s
    where s.id_usuario = v_destinatario
      and s.id_vendedor = new.id_vendedor
  ) then
    return new;
  end if;

  select coalesce(p.apartados_propuestas, true)
  into v_permite
  from public.preferencias_notificacion p
  where p.id_usuario = v_destinatario;

  if coalesce(v_permite, true) = false then
    return new;
  end if;

  select coalesce(nullif(trim(nombre), ''), 'un producto')
  into v_prod_nombre
  from public.productos
  where id = new.id_producto;

  select coalesce(nullif(trim(nombre_publico), ''), 'Un comprador')
  into v_comprador_nombre
  from public.usuarios
  where id = new.id_comprador;

  v_prod_nombre := coalesce(v_prod_nombre, 'un producto');
  v_comprador_nombre := coalesce(v_comprador_nombre, 'Un comprador');

  if tg_op = 'INSERT' then
    v_titulo := 'Nuevo apartado';
    v_cuerpo := v_comprador_nombre || ' apartó ' || new.cantidad || ' x ' || v_prod_nombre;
  else
    case new.estado
      when 'aceptado' then
        v_titulo := 'Apartado aceptado';
        v_cuerpo := 'Tu apartado de ' || new.cantidad || ' x ' || v_prod_nombre || ' fue aceptado';
      when 'rechazado' then
        v_titulo := 'Apartado rechazado';
        v_cuerpo := 'Tu apartado de ' || v_prod_nombre || ' fue rechazado por el vendedor';
      when 'expirado' then
        v_titulo := 'Apartado expirado';
        v_cuerpo := 'Tu apartado de ' || v_prod_nombre || ' ha expirado';
      when 'cancelado' then
        v_titulo := 'Apartado cancelado';
        v_cuerpo := v_comprador_nombre || ' canceló su apartado de ' || v_prod_nombre;
    end case;
  end if;

  insert into public.notificaciones (
    id_usuario,
    tipo,
    titulo,
    cuerpo,
    datos
  )
  values (
    v_destinatario,
    'apartado'::tipo_notificacion,
    v_titulo,
    v_cuerpo,
    jsonb_build_object(
      'id_apartado', new.id,
      'id_producto', new.id_producto,
      'id_comprador', new.id_comprador,
      'id_vendedor', new.id_vendedor,
      'cantidad', new.cantidad,
      'estado', new.estado
    )
  );

  return new;
end;
$$;

drop trigger if exists trg_notificar_apartado on public.apartados;

create trigger trg_notificar_apartado
after insert or update of estado on public.apartados
for each row
execute function public.notificar_apartado();

do $$
begin
  create extension if not exists pg_cron with schema extensions;

  perform cron.unschedule('recordatorios-tianguis-favoritos')
  where exists (
    select 1 from cron.job where jobname = 'recordatorios-tianguis-favoritos'
  );

  perform cron.schedule(
    'recordatorios-tianguis-favoritos',
    '*/15 * * * *',
    $cron$select public.generar_recordatorios_tianguis();$cron$
  );
exception
  when others then
    raise notice 'pg_cron no disponible en este entorno: %', sqlerrm;
end;
$$;