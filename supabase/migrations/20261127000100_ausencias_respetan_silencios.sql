-- Los avisos de ausencia dejan de llegar a quien silenció al vendedor o al tianguis.
-- Mismo criterio que notificar_oferta(). Es idempotente (CREATE OR REPLACE) y conserva
-- propietario y permisos de la función existente.

CREATE OR REPLACE FUNCTION public.notificar_ausencia() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into notificaciones (id_usuario, tipo, titulo, cuerpo, datos)
  select distinct f.id_usuario, 'ausencia'::tipo_notificacion, 'Ausencia programada',
         'El puesto ' || p.nombre || ' no abrirá el ' || to_char(new.fecha, 'DD/MM/YYYY'),
         jsonb_build_object('id_puesto', p.id, 'fecha', new.fecha)
    from puestos p
    join favoritos f on f.id_puesto = p.id
    join preferencias_notificacion pn on pn.id_usuario = f.id_usuario and pn.ausencias
   where p.id_vendedor = new.id_vendedor
     and p.id_tianguis = new.id_tianguis
     and not exists (
           select 1 from silencios_notificacion s
            where s.id_usuario = f.id_usuario
              and (s.id_vendedor = new.id_vendedor or s.id_tianguis = new.id_tianguis));
  return new;
end $$;
