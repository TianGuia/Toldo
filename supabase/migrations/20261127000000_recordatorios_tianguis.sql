-- Recordatorios de días de operación de los tianguis favoritos.
-- La función ya existe en producción; esta migración la deja versionada en Toldo
-- para poder reconstruir la base desde cero. Es idempotente (CREATE OR REPLACE).
-- El cron 'recordatorios-tianguis-favoritos' (cada 15 min) se programa en
-- 20261126000000_push_triggers_faltantes.sql.

-- Evita repetir el recordatorio de un tianguis a un usuario el mismo día
-- (el cron corre cada 15 min). Ya existe en producción: aquí no hace nada.
CREATE UNIQUE INDEX IF NOT EXISTS uq_notif_recordatorio_tianguis
  ON public.notificaciones (id_usuario, ((datos ->> 'id_tianguis')), ((datos ->> 'fecha')))
  WHERE (tipo = 'recordatorio_tianguis'::tipo_notificacion);

CREATE OR REPLACE FUNCTION public.generar_recordatorios_tianguis(p_ahora timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_local timestamp := p_ahora at time zone 'America/Mexico_City';
  v_fecha date := v_local::date;
  v_dia   smallint := extract(dow from v_local)::smallint;  -- 0 = domingo … 6 = sábado
  v_hora  time := v_local::time;
  v_total integer;
begin
  with horario_hoy as (
    select h.id_tianguis,
           min(h.hora_inicio) as inicio,
           max(h.hora_fin)    as fin
      from tianguis_horarios h
     where h.dia_semana = v_dia
     group by h.id_tianguis
  ), ventana as (
    -- Desde 2 horas antes de abrir hasta el cierre.
    select t.id as id_tianguis, t.nombre, hh.inicio, hh.fin
      from horario_hoy hh
      join tianguis t on t.id = hh.id_tianguis and t.activo
     where v_hora >= case when hh.inicio > time '02:00'
                          then hh.inicio - interval '2 hours'
                          else time '00:00' end
       and (hh.fin <= hh.inicio or v_hora < hh.fin)
  ), ins as (
    insert into notificaciones (id_usuario, tipo, titulo, cuerpo, datos)
    select f.id_usuario,
           'recordatorio_tianguis'::tipo_notificacion,
           'Hoy hay tianguis',
           v.nombre || ' abre hoy de ' || to_char(v.inicio, 'HH24:MI') ||
             ' a ' || to_char(v.fin, 'HH24:MI'),
           jsonb_build_object('id_tianguis', v.id_tianguis, 'fecha', v_fecha)
      from favoritos f
      join ventana v on v.id_tianguis = f.id_tianguis
      left join preferencias_notificacion pn on pn.id_usuario = f.id_usuario
      join usuarios u on u.id = f.id_usuario and u.estado_cuenta = 'activa'
     where coalesce(pn.recordatorios_tianguis, true)
       and not exists (
             select 1 from silencios_notificacion s
              where s.id_usuario = f.id_usuario
                and s.id_tianguis = v.id_tianguis)
    on conflict do nothing
    returning 1
  )
  select count(*) into v_total from ins;
  return v_total;
end $function$;

-- Solo el cron (que corre como propietario) debe poder llamarla: con SECURITY DEFINER
-- y p_ahora libre, cualquier cliente podría generar avisos a todos los favoritos.
REVOKE ALL ON FUNCTION public.generar_recordatorios_tianguis(timestamp with time zone)
  FROM PUBLIC, anon, authenticated;
