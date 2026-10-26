# Revisión inicial de la base de datos

Fecha: 2026-10-25. Fuente: exportación de estructura del proyecto compartido
Tianguia mediante Supabase CLI 2.122.0. No se exportaron registros de usuarios.

Esta revisión describe la exportación inicial. La sincronización posterior se
documenta en [Sincronización del 2026-10-26](sincronizacion-20261026.md);
`schema-reference.sql` ahora contiene esa exportación más reciente de `public`.

## Resultado

La exportación contiene 38 tablas de aplicación, todas con RLS habilitado,
19 tipos enumerados y 30 funciones en public. Esto documenta la estructura real;
se convirtió después en una migración inicial y se probó en Docker. No constituye una auditoría completa.

## Comparación con el ER

El ER se consultó como referencia externa y no se incorpora a este repositorio.
Las siguientes diferencias describen el diseño; no implican por sí mismas errores.

| Concepto | ER | Base exportada | Decisión pendiente |
| --- | --- | --- | --- |
| Identidad | Usuario, Comprador y Vendedor separados | usuarios y perfiles_vendedor; no existe una tabla Comprador | Documentar cómo se representa al comprador y cómo convive con el perfil de vendedor. |
| Identificadores | VARCHAR | UUID | Mantener una correspondencia de nombres y tipos con el modelo. |
| Conversaciones | Entidad asociativa Participante | id_iniciador e id_receptor en conversaciones | Confirmar que el alcance requiere conversaciones entre dos personas. |
| Productos | Categoría e imágenes como atributos | categorias y producto_imagenes separadas | Documentar la normalización. |
| Ubicación | Atributo ubicacion | latitud y longitud; jornadas_puesto y codigos_visita | Documentar la ubicación por jornada y la verificación de visita. |
| Horarios | Atributos del tianguis | tianguis_horarios y vendedor_horarios | Documentar los horarios generales y los de cada vendedor. |
| Ofertas | Oferta vinculada a un producto | ofertas y oferta_productos | Confirmar el comportamiento de ofertas con varios productos. |
| Valoraciones | Etiquetas multivaloradas y visita única | calificaciones, etiquetas_valoracion y calificacion_etiquetas | Verificar restricciones y comportamiento de visitas con pruebas. |
| Apelaciones | Reporte opcional | Referencias a medida, reporte o calificación; exige al menos una | Confirmar las combinaciones permitidas. |

## Diferencias con el SQL de Tianguiapp

No ejecutar automáticamente el antiguo 01_setup.sql sobre la base exportada.
Ese archivo no es una representación fiel de todas las funciones remotas.
Ejemplos confirmados:

- abrir_puesto recibe p_id_puesto, p_latitud y p_longitud en la base remota;
  el script antiguo utiliza p_puesto, p_lat y p_lng.
- La base tiene confirmar_visita(p_codigo); el script propone verificar_visita
  con otra firma.
- terminos_pendientes devuelve registros de versiones_documento en la base;
  el script antiguo la define con retorno booleano.

La revisión de compatibilidad debe cubrir todas las llamadas RPC y consultas de
la versión actual de Flutter antes de consolidar las migraciones.

## Permisos por revisar

Todas las tablas exportadas tienen RLS habilitado. Eso no demuestra por sí solo
que los permisos sean correctos.

- Existen GRANT ALL a authenticated en múltiples tablas, así como concesiones
  explícitas de TRUNCATE. Revisar y reducir privilegios a las operaciones
  necesarias: RLS no protege TRUNCATE. No se ha intentado ejecutar esa operación.
- Revisar funciones SECURITY DEFINER, sus validaciones y permisos de ejecución.
- Revisar las vistas públicas y los campos que exponen.
- Probar accesos permitidos y rechazados con dos usuarios independientes,
  compradores anónimos, vendedores y administradores.
- No equiparar el rol SQL authenticated con el rol de vendedor o administrador.

Las observaciones anteriores corresponden a la exportación original. Las pruebas
locales confirmaron que había que limpiar permisos heredados al restaurar. Una
migración separada retira privilegios administrativos de los clientes y elimina
las concesiones predeterminadas para tablas nuevas. No se modificaron
las tablas ni sus permisos en el proyecto compartido.

## Verificación realizada

El comando `bash scripts/test-db.sh` terminó correctamente sobre un contenedor
nuevo, con Supabase CLI 2.122.0 y PostgreSQL 17.11.0.003. El contenedor y su volumen
se eliminan al terminar. El mismo comando está configurado en GitHub Actions;
la ejecución en GitHub aún no se ha realizado.

Se verificaron:

- Restauración de 38 tablas y RLS habilitado en todas ellas.
- Aplicación de las dos migraciones y carga de categorías sintéticas.
- Lectura del perfil propio y modificación del nombre público.
- Rechazo de la modificación de campos reservados del perfil.
- Edición del producto propio y rechazo de edición y publicación como otro vendedor.
- Ausencia de TRUNCATE y TRIGGER para anon y authenticated.

Los datos de las pruebas se ejecutan dentro de transacciones que se revierten.
Las cuentas se insertan como fixtures SQL: estas pruebas no validan el flujo de
registro ni el envío de códigos OTP.

## Qué falta para reproducir todos los servicios de la app

1. Capturar las personalizaciones de auth y storage que no aparecen en la
   exportación, incluido el trigger de alta sobre auth.users.
2. Definir buckets, políticas de archivos y configuración de autenticación local.
3. Ampliar las pruebas a funciones privilegiadas, vistas, conversaciones,
   moderación, compradores anónimos y almacenamiento.
4. Revisar todas las llamadas RPC y consultas de Flutter contra el esquema.
5. Completar los catálogos necesarios para una demostración de la app.

No se ha ejecutado db push, db reset remoto ni reparaciones del historial de
migraciones. El vínculo local y la exportación utilizaron la sesión autorizada;
la CLI informó que inicializó un rol de acceso temporal para la conexión.
