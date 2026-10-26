# Toldo

El backend de TianGuía: la base de datos, los permisos y los servicios que
sostienen nuestra comunidad.

La app móvil vive en [Tianguiapp](https://github.com/Tianguia/Tianguiapp).
Aquí mantenemos la estructura de datos y la configuración de Supabase.

## Pruebas locales

Necesitas Node.js 22 o posterior, npm y Docker funcionando. En Windows ejecuta
los comandos desde WSL, con Node instalado dentro de WSL:

```sh
bash scripts/test-db.sh
```

El script usa Supabase CLI 2.122.0 para crear un contenedor PostgreSQL con las
dependencias de Supabase, aplicar las migraciones y cargar datos sintéticos.
Ejecuta las pruebas SQL y elimina su contenedor y volumen al terminar. Usa el
proyecto temporal `toldo_tests` y el puerto local 55432, separado del entorno
habitual `Toldo`. Una ejecución concurrente con ese nombre se rechaza.
No necesita cuenta de Supabase, credenciales ni vínculo a un proyecto remoto.
La primera ejecución descarga las imágenes necesarias.

Se comprueban la restauración de las 39 tablas, la activación de RLS, los datos
de ejemplo, la lectura del perfil propio, la edición de productos propios, el
rechazo de cambios y publicaciones ajenas, los campos reservados del perfil y
la ausencia de privilegios TRUNCATE/TRIGGER para clientes.
También se prueban ocultación de chats, respuestas de propuestas y apartados,
restitución de stock al cancelar o vencer y sincronización del correo del perfil.

GitHub Actions ejecuta el mismo script en cada push y pull request, sin secretos
de despliegue. Una prueba que falla devuelve un código de salida distinto de cero.

## Estructura

- `supabase/config.toml`: configuración del entorno local.
- `supabase/migrations/`: estructura inicial y correcciones posteriores.
- `supabase/seed.sql`: categorías de ejemplo, sin cuentas reales.
- `scripts/test-db.sh`: creación y limpieza del entorno Docker de pruebas.
- `tests/`: comprobaciones SQL; sus datos se revierten al terminar.
- `.github/workflows/database.yml`: ejecución automática de la misma suite.
- `schema-reference.sql`: exportación de `public` del 2026-10-26, sin registros.
- `docs/revision-inicial.md`: comparación con el modelo y trabajo pendiente.
- `docs/sincronizacion-20261026.md`: cambios remotos incorporados y alcance.

## Migraciones y permisos

La primera migración procede de la exportación del proyecto compartido. Antes
de reproducir sus GRANTs, limpia los permisos heredados de las tablas para evitar
que las concesiones predeterminadas del entorno local amplíen el acceso.

La segunda migración propone retirar TRUNCATE, TRIGGER, REFERENCES y MAINTAIN de
los roles de cliente, impedir que creen objetos en public y exigir permisos
explícitos para tablas nuevas. Estos cambios solo se han preparado para revisión
y pruebas locales; no se aplican automáticamente al proyecto compartido.

Los cambios se prueban localmente y se revisan antes de que un responsable los
aplique al entorno correspondiente. La aplicación móvil utiliza la API con
permisos limitados; no crea tablas ni ejecuta migraciones.

La tercera migración incorpora los cambios de `public` exportados el 2026-10-26:
conversaciones ocultas, respuestas y vencimiento de tratos, verificación de
cuentas y nuevas políticas. Conserva la reducción local de privilegios de la
segunda migración. El SQL de referencia reproduce los permisos exportados;
las migraciones son la fuente para restaurar con los permisos restringidos.
Esta sincronización no modifica el modelo para alinearlo con el ER.

## Alcance de la verificación

Estas pruebas cubren la base y una selección de permisos. No sustituyen una
revisión completa de funciones, vistas, mensajería, moderación y almacenamiento.
La exportación no contiene toda la configuración del servicio de autenticación,
los buckets ni los triggers personalizados de esquemas administrados como auth.
Antes de conectar la app a un entorno nuevo, hay que completar y probar esas
integraciones. No es todavía una copia funcional completa del proyecto alojado.

Las credenciales y los archivos temporales se excluyen de Git. Los datos de
usuarios y sus archivos no se exportan ni se incluyen en este repositorio.

## Licencia

Este proyecto se distribuye bajo la licencia [BSD de 3 cláusulas](LICENSE) (`BSD-3-Clause`).
