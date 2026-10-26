# Sincronización de public del 2026-10-26

Fuente: exportación de estructura de `public` del proyecto Tianguia mediante
Supabase CLI 2.122.0, proporcionada por el responsable del proyecto. Sin registros.
`schema-reference.sql` se actualiza con esa exportación; solo se normalizan los
finales de línea y espacios al final de las líneas.

## Cambios incorporados

La migración `20261026000000_sync_public_schema.sql` se aplica después de las dos
existentes, sin reescribir su historial. Agrega:

- `conversaciones_ocultas`, con PK compuesta, dos FK, RLS y política propia.
- `es_mi_vendedor` y la política `trato_usuarios_leer` para consultar compradores
  con propuestas o apartados dirigidos al vendedor de la sesión.
- `ocultar_conversacion`, con comprobación de participación y actualización de
  la fecha de ocultación cuando el usuario repite la operación.
- `responder_apartado`, `responder_propuesta`, `vencer_pendientes` y
  `tratos_guard`, con los dos triggers de control de modificaciones.
- `tg_solo_cuentas_verificadas` y sus triggers sobre vendedores y administradores.
- `tg_sync_contacto`, que actualiza el correo del perfil desde auth.

Actualiza `handle_new_user` como en el remoto: nombre público o parte local del
correo como respaldo y, por último, Invitado. Ya no copia el teléfono ni utiliza
el metadato `nombre` como alternativa. Conserva el alta de preferencias.

El conjunto queda en 39 tablas, 38 funciones, 20 triggers de tablas de `public`,
86 políticas RLS, 19 enumeraciones y 5 vistas. Las 38 tablas anteriores,
sus restricciones, índices, enumeraciones y vistas no cambiaron en la exportación.

## Diferencias deliberadas y límites

Se conserva la reducción de privilegios de `20261025000100_client_privileges.sql`.
La tabla nueva concede CRUD a los roles de cliente y todos los permisos a
`service_role`, sin reintroducir TRUNCATE, TRIGGER, REFERENCES ni MAINTAIN para
clientes. `vencer_pendientes` excluye PUBLIC y anon, como el permiso efectivo
exportado, también al restaurar con los permisos predeterminados de funciones.

El SQL de referencia documenta el remoto, incluidos sus permisos amplios;
no sustituye a las migraciones para restaurar el entorno con permisos restringidos.
No se ejecutaron migraciones ni cambios de configuración en el proyecto remoto.

La exportación está limitada a `public`. No demuestra que se hayan eliminado las
extensiones ni las publicaciones Realtime presentes en la migración inicial;
estas se conservan. Tampoco incluye los triggers instalados sobre `auth.users`,
buckets, políticas de storage ni configuración del servicio Auth. Se incorpora
el cuerpo de `tg_sync_contacto`, pero no se inventa un trigger de producción en
auth que la exportación no documenta.

Las diferencias con el ER siguen pendientes; esta migración reproduce los
cambios remotos y no realiza la adaptación al modelo acordado.

## Verificación

`tests/01_database.sql` exige 39 tablas y RLS. `tests/02_privileges.sql` sigue
comprobando la ausencia de privilegios administrativos para clientes.
`tests/03_remote_sync.sql` usa cuentas sintéticas y revierte todos sus datos;
comprueba alta y sincronización de correo mediante triggers instalados solo
durante la prueba, rechazo de vendedores anónimos, ocultación de chats propios,
aislamiento de terceros, acceso del vendedor al comprador de un trato, respuestas
por RPC, stock al aceptar/cancelar y vencimiento sin restitución duplicada.
Esto no valida el envío de OTP ni la configuración de auth alojada.

El 2026-10-26 se ejecutó `bash scripts/test-db.sh` en WSL con Docker:
restauración desde cero de las tres migraciones, carga de seed y las tres pruebas
SQL correctas. También se compararon las definiciones de tablas, funciones,
restricciones, índices, triggers, políticas, vistas y enumeraciones de las
migraciones con la exportación, sin diferencias de definición. Los permisos
restringidos y el alcance de los esquemas se exceptúan como se explicó arriba.
