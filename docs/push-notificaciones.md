# Avisos push (Supabase + Firebase Cloud Messaging)

Flujo: se inserta una fila en `notificaciones` → trigger `trg_enviar_push` →
Edge Function `enviar-push` → FCM → teléfono. Los tokens viven en `dispositivos_push`.

## Configuración única
1. Firebase: crear proyecto, agregar la app Android `mx.udg.alumnos.tianguia`,
   descargar `google-services.json` y ponerlo en `android/app/` de Tianguiapp.
2. Firebase → Configuración → Cuentas de servicio → generar clave privada (JSON).
3. Secretos de la función (reemplaza el contenido de los archivos):
   `supabase secrets set FCM_SERVICE_ACCOUNT="$(cat cuenta-servicio.json)" PUSH_WEBHOOK_SECRET="<texto-largo-aleatorio>"`
4. Desplegar: `supabase functions deploy enviar-push --no-verify-jwt`
5. Aplicar la migración `20261125000000_push_notifications.sql`.
6. En el SQL editor de Supabase, con el mismo secreto del paso 3:
   ```sql
   select vault.create_secret('https://<ref>.supabase.co/functions/v1/enviar-push', 'push_function_url');
   select vault.create_secret('<texto-largo-aleatorio>', 'push_webhook_secret');
   ```

## Probar
Con la app abierta una vez en un teléfono (para registrar el token), inserta una
fila en `notificaciones` para ese usuario con la app cerrada y debe llegar el aviso.
