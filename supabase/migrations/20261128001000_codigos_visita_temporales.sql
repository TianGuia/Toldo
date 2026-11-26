-- RF-41: los códigos nuevos son numéricos, únicos y reutilizables durante diez minutos.
-- Los códigos anteriores de seis dígitos pueden terminar su vigencia.
create unique index codigos_visita_codigo_temporal_uidx
  on public.codigos_visita (codigo) where length(codigo) = 8;

create function public.codigo_visita_vigente(p_id_puesto uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_vendedor uuid;
  v_jornada uuid;
  v_codigo text;
  v_expira timestamptz;
  v_ahora timestamptz;
  v_hash text;
begin
  select j.id, p.id_vendedor into v_jornada, v_vendedor
    from jornadas_puesto j
    join puestos p on p.id = j.id_puesto
   where j.id_puesto = p_id_puesto and j.fecha_cierre is null
     and p.estado = 'abierto' and p.activo and puede_operar_vendedor(p.id_vendedor)
   order by j.fecha_apertura desc, j.id desc limit 1 for update of j;
  if not found then
    raise exception 'El puesto debe estar abierto y pertenecer al vendedor';
  end if;

  v_ahora := clock_timestamp();
  select c.codigo, c.expira_en into v_codigo, v_expira
    from codigos_visita c
   where c.id_jornada = v_jornada and length(c.codigo) = 8 and c.expira_en > v_ahora
   order by c.creado_en desc limit 1;
  if found then
    return jsonb_build_object('codigo', v_codigo, 'expira_en', v_expira);
  end if;

  -- La identidad del vendedor interviene en el hash. Los bytes aleatorios
  -- impiden que conocer esa identidad permita predecir el código.
  for intento in 1..20 loop
    v_hash := encode(extensions.digest(uuid_send(v_vendedor) || extensions.gen_random_bytes(16), 'sha256'), 'hex');
    v_codigo := lpad(((('x' || left(v_hash, 8))::bit(32)::bigint) % 100000000)::text, 8, '0');
    v_expira := clock_timestamp() + interval '10 minutes';
    insert into codigos_visita (id_jornada, codigo, expira_en)
    values (v_jornada, v_codigo, v_expira)
    on conflict (codigo) where length(codigo) = 8 do nothing;
    if found then
      return jsonb_build_object('codigo', v_codigo, 'expira_en', v_expira);
    end if;
  end loop;
  raise exception 'No se pudo reservar un código. Intenta de nuevo';
end
$$;

-- Mantiene operativo el APK anterior, que espera recibir únicamente el código.
create or replace function public.generar_codigo_visita(p_id_puesto uuid, p_minutos integer default 10)
returns text language sql security definer set search_path = public
as $$
  select public.codigo_visita_vigente(p_id_puesto)->>'codigo';
$$;

revoke execute on function public.codigo_visita_vigente(uuid) from public, anon;
grant execute on function public.codigo_visita_vigente(uuid) to authenticated;
revoke execute on function public.generar_codigo_visita(uuid, integer) from public, anon;

create or replace function public.confirmar_visita(p_codigo text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare
  v_jornada uuid;
  v_puesto uuid;
  v_visita uuid;
begin
  begin
    select distinct c.id_jornada, j.id_puesto into strict v_jornada, v_puesto
      from codigos_visita c
      join jornadas_puesto j on j.id = c.id_jornada
      join puestos p on p.id = j.id_puesto
     where c.codigo = btrim(p_codigo) and c.expira_en > clock_timestamp()
       and j.fecha_cierre is null and p.estado = 'abierto' and p.activo;
  exception when no_data_found or too_many_rows then
    raise exception 'Código inválido o vencido';
  end;

  insert into visitas (id_usuario, id_puesto, id_jornada)
  values (auth.uid(), v_puesto, v_jornada)
  on conflict (id_usuario, id_jornada) do update set fecha_hora = visitas.fecha_hora
  returning id into v_visita;
  return v_visita;
end
$$;

revoke execute on function public.confirmar_visita(text) from public, anon;

revoke insert, update, delete on public.codigos_visita from authenticated;
