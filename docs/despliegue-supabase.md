# Adoptar la línea base y desplegar mejoras

Un commit de Toldo no modifica Supabase. `db push` aplica archivos pendientes y
registra sus versiones en `supabase_migrations.schema_migrations`.
La [captura actual](baseline-20261027.md) confirmó que esa tabla no existe en el
destino revisado. Reorganizar el repositorio no cambia ese historial.

## 1. Probar e identificar el destino

Desde Toldo, con Node, Python 3 y Docker disponibles (WSL en Windows):

```sh
bash scripts/test-db.sh
npx --yes supabase@2.122.0 link --project-ref ijnvztoyhizdwtzagrvy
npx --yes supabase@2.122.0 migration list --linked
```

`link` selecciona el proyecto, no lo despliega. La CLI puede obtener un rol temporal
con el token de una cuenta autorizada sin conocer la contraseña PostgreSQL.
Si se proporciona `SUPABASE_DB_PASSWORD`, usa esa credencial.

## 2. Verificar y registrar solo la línea base

Confirma con el equipo que otros entornos no dependan de las cinco versiones antiguas.
Si aparecen versiones antiguas o nuevas en el remoto, reconcilia ese caso antes de
seguir; no borres entradas para forzar la secuencia.

Compara una exportación nueva de public con `schema-reference.sql` y el inventario
obtenido mediante `scripts/inspect-baseline.sql` con `docs/snapshots/baseline-20261027.json`.
También deben coincidir las integraciones propias de Auth, Storage, Realtime y cron.
No ejecutes la línea base sobre tablas existentes.

Solo después de verificar esa correspondencia y ausencia de historial que preservar:

```sh
npx --yes supabase@2.122.0 migration repair 20261027000000 --status applied --linked
npx --yes supabase@2.122.0 migration list --linked
```

`repair` escribe el registro; no ejecuta, compara ni verifica el SQL. No marques
las tres mejoras como aplicadas si no se ejecutaron. Estos comandos corresponden
al despliegue futuro: no se ejecutaron durante la reorganización.

En un proyecto vacío se omite `repair`: deben ejecutarse las cuatro migraciones.

## 3. Revisar datos y vista previa

```sh
npx --yes supabase@2.122.0 db query --linked --file scripts/preflight-er.sql
npx --yes supabase@2.122.0 db push --linked --dry-run
```

Los cuatro contadores deben quedar en cero. Con la línea base registrada, el dry-run
solo debe listar `20261027000100_restrict_client_privileges.sql`,
`20261027000200_align_domain_contract.sql` y `20261027000300_client_operations.sql`.
En un destino vacío también debe listar `20261027000000_baseline_supabase.sql`.
La vista previa enumera archivos, no prueba sus transformaciones con datos remotos.

## 4. Aplicar y verificar

Prepara un respaldo restaurable de los registros y coordina la distribución de
la app compatible. La exportación de estructura no sustituye ese respaldo.
Tras revisar destino, historial, datos y vista previa:

```sh
npx --yes supabase@2.122.0 db push --linked
npx --yes supabase@2.122.0 migration list --linked
npx --yes supabase@2.122.0 db query --linked --file scripts/verify-er.sql
```

No uses `db reset --linked` ni pegues la línea base sobre la base existente.
Para deshacer mejoras aplicadas prepara otra migración o restaura el respaldo;
`repair --status reverted` solo modifica el historial, no revierte el SQL.

Después verifica acceso anónimo/OTP, catálogo, GPS, imágenes, chat Realtime,
visitas/calificaciones, propuestas/apartados, ofertas y retiro con la app adaptada.
Registra fecha, proyecto y commit al completar la revisión funcional.

## GitHub Actions

El workflow **Actualizar Supabase** se inicia manualmente (`workflow_dispatch`) y
requiere estar publicado en la rama predeterminada. Su configuración actual exige
los Secrets `SUPABASE_ACCESS_TOKEN` y `SUPABASE_DB_PASSWORD`. Ese requisito es del
workflow actual; no significa que la CLI interactiva siempre necesite contraseña.

Después de adoptar la línea base, ejecuta primero sin `apply_changes`. El workflow
prueba localmente, vincula el destino, muestra el historial y exige preflight y dry-run
correctos. Con `apply_changes` aplica y verifica. No repara el historial automáticamente.
No se publican secretos en SQL ni logs. Los fallos previos impiden el push.

## Referencias

- [Adopción de proyectos existentes](https://supabase.com/docs/guides/local-development/cli-workflows)
- [Migraciones e historial](https://supabase.com/docs/guides/deployment/database-migrations)
- [Referencia de la CLI](https://supabase.com/docs/reference/cli)
