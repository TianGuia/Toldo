# Marcas de puesto: Nuevo, Veterano y Destacado

Migración: `supabase/migrations/20261127000000_marcas_puestos.sql`. Prueba: `tests/08_marcas_puestos.sql`.

## Qué cuenta como calificación

Una calificación solo existe si la persona confirmó una visita: el vendedor, con el puesto
abierto, genera un código de 6 dígitos (vigencia de 10 minutos) y la persona lo escribe.
Hay una calificación por visita y una visita por persona y jornada. Para las marcas no
cuentan las calificaciones moderadas ni las del propio dueño del puesto.

## Reglas

| Marca | Regla | Se quita |
|---|---|---|
| Nuevo | Menos de 30 días desde la primera apertura real (`jornadas_puesto`) | Sola, al cumplirse el plazo |
| Veterano | Más de 1 año desde la primera apertura, 12 jornadas o más, alguna jornada en los últimos 60 días, 10 personas distintas calificando y promedio de 4.0 o más | Si baja el promedio o deja de abrir |
| Destacado | Compite quien tenga 5 personas distintas calificando y al menos 1 calificación en los últimos 30 días. Se ordena por promedio ponderado (con 5 calificaciones «de peso» hacia el promedio de toda la plataforma), luego personas distintas, guardados y fecha de alta | Cambia solo cuando otro puesto lo supera |

Si nadie cumple el mínimo del destacado se elige entre todos con el mismo orden, así que el
Home siempre muestra uno. Un puesto no puede ser Nuevo y Veterano a la vez.

Los plazos (30 días, 1 año, 12 jornadas, 60 días, 10 y 5 personas, 4.0) están escritos en la
vista `v_puestos_resumen` y en `puesto_destacado`; se cambian ahí.

## Columnas nuevas en `v_puestos_resumen`

`calificadores`, `calificaciones_recientes`, `primera_apertura`, `jornadas`, `es_nuevo`, `es_veterano`.
