# Toldo

El backend de TianGuía: estructura PostgreSQL, permisos e integraciones de
Supabase. La app vive en [Tianguiapp](https://github.com/Tianguia/Tianguiapp).

## Línea base y mejoras

| Versión | Contenido |
| --- | --- |
| `20261027000000_baseline_supabase` | Captura del 27 de octubre: 39 tablas, funciones, relaciones, ACL, RLS, nombres únicos e integraciones propias de Auth, Storage, Realtime y cron. |
| `20261027000100_restrict_client_privileges` | Reducción de permisos administrativos de clientes. |
| `20261027000200_align_domain_contract` | Compradores, participantes, puesto obligatorio, ofertas por producto y demás relaciones del contrato. |
| `20261027000300_client_operations` | Retiro transaccional, validaciones de publicación y creación de chats por RPC. |
| `20261124000000_sync_admin_and_documents` | Captura del panel de administración, moderación y lectura de documentos vigentes en producción. |
| `20261128000000_valoraciones_privadas_y_fallas` | Etiquetas de un puesto visibles para todos (solo conteos), comentarios de calificaciones solo para quien calificó, el vendedor y el administrador, y la tabla de reportes de fallas. |

La primera migración es lo que se llamó “seeder inicial”: crea estructura y
configuración, sin copiar registros reales. `supabase/seed.sql` contiene solo
categorías sintéticas para desarrollo. `schema-reference.sql` conserva la captura
de public **anterior a las mejoras**.

Procedencia, comparación y regeneración: [Línea base](docs/baseline-20261027.md).
Relaciones y compatibilidad: [Modelo ER](docs/modelo-er.md).

## Pruebas locales

Requisitos: Node.js 22+, Python 3, npm y Docker. En Windows usa WSL con Node dentro de WSL.

```sh
bash scripts/test-db.sh
```

La suite usa CLI 2.122.0 y PostgreSQL de Supabase en Docker. Primero restaura solo
la línea base y verifica sus integraciones y permisos. Después aplica la reducción
de privilegios, prueba la transformación ER sobre datos históricos sintéticos y
aplica las mejoras restantes. Ejecuta siete pruebas SQL finales y verifica el historial
y las RPC. También prueba la regeneración exacta del SQL y los scripts de despliegue.

Usa `toldo_tests`, puerto 55432, sin credenciales ni vínculo remoto. Rechaza
concurrencia con ese nombre y elimina su contenedor/volumen al terminar. Los fixtures
se revierten. GitHub Actions ejecuta la misma suite en push y PR; no despliega con push.

## Adopción del proyecto existente

La consulta del 24 de noviembre de 2026 confirmó que el proyecto Tianguia tiene las
primeras cuatro migraciones en su historial y que ya contiene el esquema de la
quinta. Antes de registrar la quinta en ese proyecto, verifica que la estructura
siga coincidiendo. Una base vacía aplica las cinco migraciones en orden.

La quinta migración reproduce la estructura. Las credenciales administrativas,
sesiones, bitácora y contenidos legales de producción son datos del entorno.

Comandos y coordinación con la app: [Despliegue](docs/despliegue-supabase.md).

## Archivos principales

- `supabase/migrations/`: línea base y mejoras escalonadas.
- `scripts/inspect-baseline.sql`: inventario remoto de solo lectura.
- `scripts/build-baseline.py`: genera la línea base desde la captura y metadatos.
- `docs/snapshots/baseline-20261027.json`: inventario sin datos personales.
- `scripts/preflight-er.sql`: condiciones de datos que bloquean el ER.
- `scripts/verify-er.sql`: comprobación posterior al despliegue.
- `.github/workflows/deploy-supabase.yml`: despliegue manual con preview.

## Límites

Los esquemas internos son responsabilidad de la plataforma Supabase. Proveedores
Auth/SMTP, secretos, archivos Storage y registros de usuarios no se exportan aquí.
Configurar esos servicios y revisar OTP, GPS, imágenes y Realtime desde la app son
verificaciones separadas. La línea base de estructura no es un respaldo de los datos.

## Licencia

[BSD de 3 cláusulas](LICENSE) (`BSD-3-Clause`).
