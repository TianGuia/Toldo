
begin;

insert into auth.users (id, is_anonymous) values
  ('22000000-0000-0000-0000-000000000001', true),
  ('22000002-0000-0000-0000-000000000002', true);
select public.admin_configurar_credenciales('operador srs', 'clave-prueba-1', 'respuesta local');

set local role authenticated;
select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select public.admin_entrar('operador srs', 'clave-prueba-1', 'respuesta local');
select public.admin_cambiar_estado_cuenta(
  '22000002-0000-0000-0000-000000000002', 'suspendida', 'Razón general de prueba');
select public.admin_cambiar_estado_cuenta(
  '22000002-0000-0000-0000-000000000002', 'suspendida', 'Reintento');

select set_config('request.jwt.claim.sub', '22000002-0000-0000-0000-000000000002', true);
do $$ begin
  if (select estado_cuenta from public.usuarios where id = auth.uid()) <> 'suspendida'
     or (select count(*) from public.medidas_moderacion where tipo_medida = 'suspender_cuenta') <> 1
     or not exists (select 1 from public.notificaciones where cuerpo = 'Razón general de prueba') then
    raise exception 'La suspensión debe generar una única medida y avisar su motivo';
  end if;
end $$;
insert into public.apelaciones (id, id_usuario, id_medida, motivo)
select '22000000-0000-0000-0000-000000000010', auth.uid(), id, 'Solicito una revisión'
from public.medidas_moderacion where tipo_medida = 'suspender_cuenta';

select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select public.admin_resolver_apelacion(
  '22000000-0000-0000-0000-000000000010', 'modificada', 'Se reduce a una advertencia');

select set_config('request.jwt.claim.sub', '22000002-0000-0000-0000-000000000002', true);
do $$ begin
  if (select estado_cuenta from public.usuarios where id = auth.uid()) <> 'activa'
     or not exists (select 1 from public.medidas_moderacion where activa and tipo_medida = 'advertencia')
     or not exists (select 1 from public.apelaciones where estado = 'resuelta' and resolucion = 'modificada')
     or not exists (select 1 from public.notificaciones where cuerpo = 'Se reduce a una advertencia') then
    raise exception 'Modificar debe aliviar la sanción y notificar la decisión';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select public.admin_cambiar_estado_cuenta(
  '22000002-0000-0000-0000-000000000002', 'suspendida', 'Segunda suspensión');

select set_config('request.jwt.claim.sub', '22000002-0000-0000-0000-000000000002', true);
insert into public.apelaciones (id, id_usuario, id_medida, motivo)
select '22000000-0000-0000-0000-000000000011', auth.uid(), id, 'Pido revertir'
from public.medidas_moderacion where tipo_medida = 'suspender_cuenta';

select set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000001', true);
select public.admin_resolver_apelacion(
  '22000000-0000-0000-0000-000000000011', 'revertida', 'Se retira la medida');

select set_config('request.jwt.claim.sub', '22000002-0000-0000-0000-000000000002', true);
do $$ begin
  if (select estado_cuenta from public.usuarios where id = auth.uid()) <> 'activa'
     or exists (select 1 from public.medidas_moderacion where activa and tipo_medida = 'suspender_cuenta')
     or not exists (select 1 from public.apelaciones where estado = 'resuelta' and resolucion = 'revertida') then
    raise exception 'Revertir debe desactivar la suspensión de la cuenta';
  end if;
end $$;
rollback;
