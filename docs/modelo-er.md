# Correspondencia con el ER de TianGuía

Fuente: `Diagrama_ER_TianGuia.pdf`, proporcionado en Tianguiapp. El responsable
aceptó equivalencias documentadas de nombres y tipos el 2026-10-26. La migración
incremental es `20261027000200_align_domain_contract.sql`; no modifica el PDF ni el cliente.

## Equivalencias físicas

UUID implementa los identificadores String/VARCHAR; `text`, `varchar` y enums
representan atributos de texto y estados; `timestamptz` implementa DATETIME;
`numeric` implementa DECIMAL. Se conservan nombres existentes cuando el significado
coincide. En las tablas con `id`, este es el `id_<entidad>` del PDF.

| Entidad ER | Tabla / atributos equivalentes |
| --- | --- |
| Usuario | `usuarios`: `id`, `nombre_publico` = nombre, `correo`, `telefono`, `foto_url` = foto_perfil, `creado_en` = fecha_registro, `estado_cuenta` |
| Comprador | `compradores`: `id_comprador` PK e `id_usuario` FK/UQ a usuarios. Se comparte el UUID, sin excluir la habilitación simultánea de vendedor. |
| Vendedor | `perfiles_vendedor`: `id`, `id_usuario` FK/UQ, `descripcion`, `fecha_habilitacion`, `estado` |
| Participante | `participantes`: PK compuesta `(id_conversacion, id_usuario)` y ambas FK |
| Conversacion | `conversaciones`: `id`, `creada_en` = fecha_creacion, `estado` |
| Mensaje | `mensajes`: `id`, ambas FK, `contenido`, `enviado_en` = fecha_envio, `estado` calculado desde lectura y moderación |
| Reporte | `reportes`: `id`, `id_reportante` = id_usuario, `tipo_objetivo` = tipo, `id_objetivo` = id_referencia, `motivo`, `creado_en` = fecha_creacion, `estado` |
| Apelacion | `apelaciones`: `id`, `id_reporte` FK opcional, `id_usuario` FK, `motivo`, `creada_en` = fecha_creacion, `estado`, `resolucion` |
| Visita | `visitas`: `id`, `id_usuario` = id_comprador (FK a compradores), `id_puesto`, `fecha_hora`, `metodo_verificacion`, `estado` |
| Calificacion | `calificaciones`: `id`, `id_visita` FK/UQ, `id_usuario` = id_comprador (FK a compradores), `id_vendedor`, `id_puesto`, `puntuacion`, `comentario`, `creada_en` = fecha_creacion. Etiquetas mediante `calificacion_etiquetas` y `etiquetas_valoracion`. |
| Apartado | `apartados`: `id`, `id_producto`, `id_comprador` FK a compradores, `id_vendedor`, `fecha_inicio`, `fecha_expiracion`, `estado` |
| Puesto | `puestos`: `id`, `id_tianguis`, `id_vendedor`, `codigo`, ubicación mediante `latitud`/`longitud`, `estado`, `fecha_apertura`, `fecha_cierre` |
| Producto | `productos`: `id`, ambas FK, `nombre`, `descripcion`, categoría por `id_categoria` y `categorias.nombre`, `estado_articulo`, `precio_referencia`, `cantidad_disponible` = disponibilidad INT. Imágenes mediante `producto_imagenes`. `disponible` es un indicador adicional, no el stock. |
| Oferta | `ofertas`: `id`, `id_producto` obligatorio, `precio_promocional`, `descuento`, `fecha_inicio`, `fecha_fin`, `estado` |
| Vendedor_Tianguis | `vendedor_tianguis`: PK compuesta `(id_vendedor, id_tianguis)` y ambas FK; el UUID auxiliar anterior se conserva UNIQUE |
| Tianguis | `tianguis`: `id`, `nombre`, ubicación mediante `direccion`/coordenadas, `descripcion`, `activo` = estado activo/inactivo. Días y horario general normalizados en `tianguis_horarios` (día, hora_inicio, hora_fin). |

Imágenes y etiquetas son atributos multivalorados normalizados en relaciones
auxiliares, no cadenas concatenadas. Categorías, horarios, jornadas, códigos,
favoritos, propuestas, notificaciones y moderación son extensiones operativas.
No sustituyen las relaciones del ER. Los campos opcionales del PDF no reciben
obligatoriedad adicional sin una regla del dominio; las cardinalidades sí se
implementan con FK, NOT NULL, PK y UNIQUE.

## Relaciones y migración de datos

- Se crean compradores para las cuentas existentes y mediante trigger para las
  futuras. Las referencias de apartados, propuestas, visitas y calificaciones
  apuntan al subtipo; un vendedor también puede ser comprador.
- Los dos interlocutores históricos se trasladan a `participantes`. La tabla
  permite N usuarios y las políticas, validación de mensajes y ocultación de
  conversaciones comprueban membresía. `id_iniciador` conserva al creador y
  `id_receptor` queda como metadato opcional de compatibilidad, no como límite de
  participantes. Una conversación puede no tener contexto de producto/anuncio.
- Cada producto requiere un puesto del mismo vendedor. Se rellena únicamente
  cuando existe un solo puesto posible. Los casos sin puesto o con varios
  candidatos detienen la migración. El borrado físico del puesto queda restringido
  mientras tenga productos; la baja lógica sigue disponible.
- Cada oferta pertenece a un producto. Las campañas de varios productos se
  dividen sin perder precios, descuentos, fechas ni estado: una conserva el UUID
  original y las otras reciben uno nuevo. `id_oferta_origen` e
  `id_relacion_origen` conservan la trazabilidad. Una oferta vacía o con productos
  de otro vendedor bloquea el despliegue.
- `oferta_productos` pasa de tabla N:M a vista de lectura sobre ofertas. El
  catálogo existente se reconstruye y las notificaciones se disparan al insertar
  una oferta individual.
- Se agregan estado de conversación, visita y mensaje. Una visita no verificada
  no admite calificación; la restricción UNIQUE previa impide dos calificaciones
  por visita.
- Apelación permite reporte nulo sin exigir una medida o calificación alternativa.
  Esos vínculos adicionales se conservan como extensiones opcionales.

## Compatibilidad con Tianguiapp

Antes de desplegar este cambio junto con el cliente hay que adaptar:

1. Publicación de ofertas: insertar en `ofertas` con producto y precio/descuento;
   no insertar campañas y después filas en `oferta_productos`.
2. Productos: exigir puesto al crear; al retirar un puesto, reasignar sus productos
   o darlos de baja junto con él sin poner `id_puesto = NULL`.
3. Tratos: las relaciones PostgREST de compradores ahora llevan a `compradores`
   y desde ahí a `usuarios`; las selecciones explícitas antiguas deben cambiar.
4. Chat: consultar y administrar participantes para aprovechar conversaciones
   de más de dos personas; las RPC de mensajes y ocultación ya los validan.

La copia de Tianguiapp se adapta a estas relaciones y documenta las clases en
`docs/contrato-dominio.md` del repositorio de la app. La migración posterior
`20261027000300_client_operations.sql` agrega el retiro transaccional del puesto y sus
productos, sin anular su asociación. Los cambios permanecen locales hasta
coordinar backend y cliente; consulta [Despliegue](despliegue-supabase.md).
La misma migración agrega `iniciar_conversacion` para crear por RPC y recuperar
después por membresía. El INSERT con RETURNING del cliente anterior se evalúa
antes del trigger AFTER INSERT y no cumple la nueva política de lectura.

## Pruebas

La suite restaura la línea base y la mejora de permisos, inserta datos históricos,
ejecuta la migración ER, comprueba la transformación y revierte esa prueba.
Después aplica la migración mediante la CLI y ejecuta todas las pruebas sobre
el esquema final. Los fixtures no contienen datos reales ni acceden al remoto.

Verificado el 2026-10-26 con `bash scripts/test-db.sh` en WSL/Docker: la prueba
de transformación histórica y las cuatro pruebas SQL del esquema final pasaron.
El contenedor y el volumen temporales se limpiaron al finalizar.
