
begin;

insert into auth.users (id, is_anonymous) values
  ('23000000-0000-0000-0000-000000000001', true),
  ('23000002-0000-0000-0000-000000000002', true);
select public.admin_configurar_credenciales('operador documentos', 'clave-prueba-1', 'respuesta local');

set local role authenticated;
select set_config('request.jwt.claim.sub', '23000000-0000-0000-0000-000000000001', true);
select public.admin_entrar('operador documentos', 'clave-prueba-1', 'respuesta local');
select public.admin_publicar_documento('terminos', 'srs-1', 'Condiciones de prueba', false);
select public.admin_publicar_documento('privacidad', 'srs-1', 'Aviso de prueba', false);

select set_config('request.jwt.claim.sub', '23000002-0000-0000-0000-000000000002', true);
do $$ declare versiones uuid[];
begin
  select array_agg(id) into versiones from public.terminos_pendientes();
  if cardinality(versiones) is distinct from 2 then
    raise exception 'El primer acceso debe exigir ambos documentos vigentes';
  end if;
  perform public.aceptar_terminos_vigentes(versiones);
  perform public.aceptar_terminos_vigentes(versiones);
  if exists (select 1 from public.terminos_pendientes())
     or (select count(*) from public.aceptaciones_terminos) <> 2 then
    raise exception 'La aceptación debe ser idempotente';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '23000000-0000-0000-0000-000000000001', true);
select public.admin_publicar_documento('privacidad', 'srs-2', 'Aviso opcional', false);
select public.admin_publicar_documento('terminos', 'srs-2', 'Condiciones nuevas', true);
do $$ begin
  begin
    perform public.admin_publicar_documento('terminos', 'srs-2', 'Duplicado', true);
    raise exception 'La versión duplicada no se rechazó' using errcode = 'assert_failure';
  exception when unique_violation then null;
  end;
  if (select version from public.documento_vigente('terminos')) is distinct from 'srs-2' then
    raise exception 'Una publicación fallida dejó el documento sin versión vigente';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '23000002-0000-0000-0000-000000000002', true);
do $$ declare anterior uuid;
begin
  if (select array_agg(tipo::text) from public.terminos_pendientes()) is distinct from array['terminos']
     or (select version from public.terminos_pendientes()) is distinct from 'srs-2' then
    raise exception 'Solo la nueva versión obligatoria debe requerir aceptación';
  end if;
  select id into strict anterior from public.versiones_documento where tipo = 'terminos' and version = 'srs-1';
  begin
    perform public.aceptar_terminos_vigentes(array[anterior]);
    raise exception 'Se aceptó un documento ya reemplazado' using errcode = 'assert_failure';
  exception when raise_exception then
    if sqlerrm <> 'Las versiones cambiaron. Vuelve a consultar los documentos.' then raise; end if;
  end;
end $$;
rollback;
