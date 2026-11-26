begin;

insert into auth.users (id, email, is_anonymous) values
  ('16000000-0000-4000-8000-000000000001', 'visita-vendedor@example.test', false),
  ('16000000-0000-4000-8000-000000000002', 'visita-comprador@example.test', false);
insert into public.perfiles_vendedor (id, id_usuario)
values ('16000000-0000-4000-8000-000000000010', '16000000-0000-4000-8000-000000000001');
insert into public.tianguis (id, nombre)
values ('16000000-0000-4000-8000-000000000020', 'Tianguis de prueba de visitas');

set local role authenticated;
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);
do $$
declare
  vendedor constant uuid := '16000000-0000-4000-8000-000000000010';
  tianguis constant uuid := '16000000-0000-4000-8000-000000000020';
  puesto_a constant uuid := '16000000-0000-4000-8000-000000000031';
  puesto_b constant uuid := '16000000-0000-4000-8000-000000000032';
  a jsonb;
  b jsonb;
  inicio timestamptz;
begin
  perform public.crear_puesto_transaccional(puesto_a, vendedor, tianguis, 'A');
  perform public.crear_puesto_transaccional(puesto_a, vendedor, tianguis, 'A', null, 'Editado');
  perform public.crear_puesto_transaccional(puesto_b, vendedor, tianguis, 'B');
  update public.puestos set foto_ruta = 'visita-prueba.jpg' where id = puesto_a;
  if not exists (select 1 from public.puestos where id = puesto_a
                 and descripcion = 'Editado' and foto_ruta = 'visita-prueba.jpg') then
    raise exception 'Falló la creación idempotente o la edición del puesto';
  end if;
  if has_column_privilege('public.puestos', 'estado', 'UPDATE')
     or has_table_privilege('public.codigos_visita', 'INSERT') then
    raise exception 'Las transiciones de estado y la emisión deben pasar por RPC';
  end if;

  perform public.abrir_puesto(puesto_a, null, null);
  perform public.abrir_puesto(puesto_b, null, null);
  inicio := clock_timestamp();
  a := public.codigo_visita_vigente(puesto_a);
  b := public.codigo_visita_vigente(puesto_b);
  if (a->>'codigo') !~ '^[0-9]{8}$'
     or (b->>'codigo') !~ '^[0-9]{8}$'
     or a->>'codigo' = b->>'codigo'
     or (a->>'expira_en')::timestamptz < inicio + interval '10 minutes'
     or (a->>'expira_en')::timestamptz > clock_timestamp() + interval '10 minutes'
     or a is distinct from public.codigo_visita_vigente(puesto_a)
     or a->>'codigo' is distinct from public.generar_codigo_visita(puesto_a, 200) then
    raise exception 'El código debe ser único por puesto y conservar su caducidad';
  end if;
  perform set_config('toldo.prueba_codigo_a', a->>'codigo', true);
  perform set_config('toldo.prueba_codigo_b', b->>'codigo', true);
end $$;

select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000002', true);
do $$
declare
  codigo text := current_setting('toldo.prueba_codigo_a');
  visita uuid;
begin
  begin
    perform public.codigo_visita_vigente('16000000-0000-4000-8000-000000000031');
    raise exception 'Se permitió emitir para un vendedor ajeno';
  exception when raise_exception then
    if sqlerrm <> 'El puesto debe estar abierto y pertenecer al vendedor' then raise; end if;
  end;
  visita := public.confirmar_visita(codigo);
  if visita is distinct from public.confirmar_visita(codigo)
     or not exists (select 1 from public.visitas where id = visita
                    and id_puesto = '16000000-0000-4000-8000-000000000031') then
    raise exception 'El canje debe corresponder al mismo puesto y ser idempotente';
  end if;
end $$;

reset role;
update public.codigos_visita set expira_en = clock_timestamp() - interval '1 second'
where codigo = current_setting('toldo.prueba_codigo_a');

set local role authenticated;
do $$ begin
  begin
    perform public.confirmar_visita(current_setting('toldo.prueba_codigo_a'));
    raise exception 'Se aceptó un código expirado';
  exception when raise_exception then
    if sqlerrm <> 'Código inválido o vencido' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '16000000-0000-4000-8000-000000000001', true);
do $$ begin
  if public.codigo_visita_vigente('16000000-0000-4000-8000-000000000031')->>'codigo'
       is not distinct from current_setting('toldo.prueba_codigo_a') then
    raise exception 'El código vencido debe rotar';
  end if;
  perform public.cerrar_puesto('16000000-0000-4000-8000-000000000032');
  begin
    perform public.confirmar_visita(current_setting('toldo.prueba_codigo_b'));
    raise exception 'Se aceptó un código de un puesto cerrado';
  exception when raise_exception then
    if sqlerrm <> 'Código inválido o vencido' then raise; end if;
  end;
end $$;

rollback;
