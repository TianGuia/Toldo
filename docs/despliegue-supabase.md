# De Toldo a Supabase

Toldo versiona SQL, no una segunda base que se copie automáticamente. Cada archivo
de `supabase/migrations` transforma el estado anterior. `supabase db push` ejecuta
en el proyecto vinculado las migraciones pendientes, en orden, y registra sus
versiones. Un commit de Git por sí solo no modifica Supabase.

Los comandos siguientes se ejecutan en WSL, dentro de Toldo, con Node, Docker y
la sesión de Supabase disponibles. No se ejecutaron contra el remoto en esta tarea.

## Estado pendiente de entrega

Al 2026-10-26, la estructura del ER está implementada y probada en Toldo, pero
falta desplegarla en Supabase y comprobar que TianGuía tenga esa estructura
realmente aplicada. Los commits y las pruebas locales no acreditan el despliegue.
También falta revisar TianGuía con el cliente adaptado: acceso, catálogo,
publicación de ofertas, puestos, chats, visitas, calificaciones y apartados.
Registrar fecha, proyecto e historial de migraciones al completar esa revisión.

## Probar y seleccionar el destino

```bash
cd /mnt/d/Almacenamiento/Edson/Tareas/11/ISW/Tianguiapp/Toldo
bash scripts/test-db.sh
npx --yes supabase link --project-ref ijnvztoyhizdwtzagrvy
npx --yes supabase migration list --linked
```

`link` guarda el destino en esta copia del repositorio; no aplica SQL del proyecto.
La suite usa un contenedor temporal independiente. El proyecto del ejemplo es
Tianguia; para un entorno de ensayo usa su propio identificador.

## Proyecto existente: reconocer lo que ya está instalado

El proyecto compartido ya tenía las estructuras de la migración inicial y la
sincronización del 2026-10-26 antes de crear estos archivos. No se deben volver a
ejecutar encima de esas mismas tablas. La segunda migración de permisos no se
reflejó en la exportación revisada.

Primero revisa `migration list`, una exportación reciente y los cambios desde la
exportación de referencia. Solo si el estado sigue siendo el revisado y faltan
estas versiones en el historial, reconoce las dos versiones ya presentes:

```bash
npx --yes supabase migration repair 20261025000000 --status applied --linked
npx --yes supabase migration repair 20261026000000 --status applied --linked
```

`repair` escribe el historial: no ejecuta el SQL ni comprueba que los objetos
existan. No marques como aplicada la migración de permisos ni la del ER si no se
han ejecutado. Si aparecen otras migraciones remotas sin archivo local, hay que
recuperarlas y reconciliar ese historial antes de seguir; no borrar sus entradas
para forzar el despliegue.

En un proyecto nuevo y vacío no se hacen estos `repair`: las cuatro migraciones
deben ejecutarse completas mediante `db push`.

## Revisar datos y cambios pendientes

```bash
npx --yes supabase db query --linked --file scripts/preflight-er.sql
npx --yes supabase db push --linked --include-all --dry-run
```

Los cuatro contadores del preflight deben quedar en cero. La migración también
comprueba estas condiciones y aborta si encuentra asignaciones ambiguas,
productos en puestos ajenos u ofertas sin producto. No elige un puesto al azar
ni elimina ofertas para sortearlas.

En el proyecto compartido, después del reconocimiento anterior, el dry-run debe
listar únicamente `20261025000100_client_privileges.sql` y
`20261026010000_align_er.sql`. Si la primera ya se aplicó y está registrada,
solo debe listar la del ER. `--include-all` permite incluir la migración de
permisos, cuya versión es anterior a la sincronización ya reconocida.

El dry-run lista archivos pendientes; no prueba sus transformaciones con los
datos remotos. Las pruebas locales verifican fixtures representativos, no todos
los datos de producción.

## Aplicar

Antes de aplicar: respaldo restaurable del proyecto y despliegue coordinado del
cliente compatible. La exportación de estructura sola no respalda los registros.
En particular, Tianguiapp debe cambiar publicación de ofertas, creación/retiro de
productos y las relaciones de compradores descritas en [Modelo ER](modelo-er.md).

Una vez revisado el destino, el historial, los datos y el dry-run:

```bash
npx --yes supabase db push --linked --include-all
npx --yes supabase migration list --linked
```

La CLI pedirá confirmar las migraciones. No usar `db reset --linked`: eso no es
un despliegue incremental. Tampoco pegar `schema-reference.sql` sobre la base
existente. Para deshacer un cambio aplicado se prepara otra migración y se
verifican sus datos, o se restaura el respaldo; `migration repair --status reverted`
solo cambia el historial, no revierte los cambios SQL.

Después del despliegue verifica OTP/alta, catálogo, puestos, chat, visitas,
calificaciones, apartados y ofertas con el cliente compatible. La configuración
de Auth, storage y sus triggers no queda totalmente descrita por la exportación
de `public`; un proyecto nuevo también necesita esas integraciones.

## Referencias

- [Flujo local y despliegue de Supabase](https://supabase.com/docs/guides/local-development/cli-workflows)
- [Migraciones e historial](https://supabase.com/docs/guides/deployment/database-migrations)
- [Referencia de la CLI](https://supabase.com/docs/reference/cli)
