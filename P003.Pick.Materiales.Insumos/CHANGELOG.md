# Historial de cambios

Este archivo registra los cambios relevantes de Gorina Pick.

## Cómo actualizarlo

- Agregar primero cada cambio nuevo en `Próxima versión`.
- Clasificarlo como `Agregado`, `Modificado`, `Corregido`, `Seguridad` o `Eliminado`.
- Al publicar una versión, reemplazar `Próxima versión` por el número y la fecha.
- Describir el comportamiento visible, evitando detalles internos innecesarios.
- No incluir contraseñas, tokens, rutas privadas ni información operativa.

## 1.6.0 - 2026-09-28

### Modificado

- **Migración a MySQL 8.0**: Migración completa de persistencia de datos del servidor `Gorina.Api` desde SQLite hacia MySQL 8.0 local (`127.0.0.1:3306`), utilizando la base de datos oficial `P003.Pick.Materiales.Insumos`.
- Integración de `MySqlConnector` v2.3.7 en el proyecto .NET 8 `Gorina.Api.csproj`.
- Actualización de `Config.cs`, `Database.cs`, `RecepcionService.cs`, `Importador.cs`, `SapMonitorService.cs` y `Program.cs` para operaciones transaccionales y sintaxis nativa de MySQL.
- Actualización de configuración `config.json` y variables de entorno.

## 1.5.1 - 2026-09-24 (Piloto / Pruebas)

### Agregado

- Visualización del número de versión en la app móvil: expuesto al pie de la pantalla de inicio de sesión (`Login`) y al pie de la pantalla principal (`Home`).
- Edición de cantidad en picks pendientes: los operarios y supervisores pueden modificar la cantidad escaneada de cualquier posición mientras la orden esté en estado `PENDIENTE`.
- Eliminación de posiciones y órdenes pendientes: posibilidad de suprimir materiales erróneos o descartar la orden completa mientras se encuentre en estado `PENDIENTE`.
- Selección múltiple en Mis Picks: permite seleccionar en lote múltiples órdenes (con restricción estricta de que solo se pueden seleccionar órdenes en estado `PENDIENTE`) para eliminarlas en una sola acción.
- Filtro de calendario (Desde - Hasta): selector de rango de fechas personalizado tanto en `Mis Picks` como en `Control de Picks`, conservando el filtro rápido de 7 días.
- Captura y visualización de Documento SAP (`Doc SAP`): extracción del comprobante de material generado por SAP (`OK`, columna L) y visualización destacada en `Mis Picks`, `Detalle Pick` y `Control de Picks`.
- Captura y visualización de Detalle y Motivo SAP (`NP`): lectura de la categoría de error (columna N) y mensaje detallado (columna M) expuesto directamente en la app.
- Timeout y captura de logs de rechazo en servidor: purga automática tras 4 horas y lectura de logs en `No Procesados`.
- Prefijo `39-TEXTO` y soporte de movimientos de auditoría `PICKQUIM_AUD` en servidor.
- Configuración de conexión fija: IP del servidor establecida de forma inmutable a `http://192.168.0.126:5000`, eliminando el botón y campo editable en la pantalla de Login para prevenir desconfiguraciones.
- Repositorio OTA en servidor: endpoints `/api/app/version` y `/api/app/latest.apk`.

### Modificado

- Esquema de base de datos local SQLite elevado a versión 7 con migración automática de columnas `doc_sap` y `estado_sap_detalle`.
- `pubspec.yaml` actualizado a versión `1.5.1+8` (visualización visible limpia como `v1.5.1`).
- Servidor `version.json` conservado temporalmente en versión 7 (v1.4.0) para que no solicite actualización obligatoria al resto de los operarios durante el piloto.

## 1.4.0+7 - 2026-08-27

### Agregado

- Reserva centralizada y transaccional del número de pick en el servidor.
- Compatibilidad con varios teléfonos creando picks simultáneamente sin repetir números.
- Registro de respuestas SAP `NP` que no pueden asociarse a una operación.
- Visualización de respuestas SAP sin asociación como `ERROR/NP` en Control de Picks.

### Modificado

- La nueva serie de picks comienza en `1` y continúa de manera incremental.
- Un pick nuevo requiere conexión con `Gorina.Api` para obtener su número oficial.
- La acción de compartir abre directamente el selector del teléfono, compatible con WhatsApp.

### Corregido

- Eliminado el cálculo del próximo número a partir del máximo del historial local.
- Validación del Material SAP manual: exactamente siete dígitos numéricos.
- Formulario de usuarios desplazable para evitar que `GUARDAR` cubra los campos.
- Nombre y extensión del archivo XLSX compartido.
- Detección alternativa de archivos SAP `NP` cuando el nombre original no coincide.

## 1.3.0+6 - 2026-08-27

### Agregado

- Caché offline de Control de Picks en SQLite.
- Conservación del historial configurado, con un período predeterminado de 30 días.
- Caché de detalles de picks abiertos previamente con conexión.
- Indicador `MODO OFFLINE` y fecha de última actualización.
- Actualización automática al recuperar conexión real con `Gorina.Api`.

### Modificado

- Control de Picks funciona en modo de solo lectura cuando el servidor no está disponible.
- Las acciones que requieren servidor quedan deshabilitadas durante el modo offline.

## 1.2.0+5 - 2026-08-26

### Agregado

- Estados de respuesta SAP `OK` y `NP`.
- Historial configurable de operaciones.
- Importación administrativa de catálogos Excel.
- Control y reintento de operaciones con errores de generación.

## Versiones iniciales

### Agregado

- Inicio de sesión y administración de usuarios.
- Lectura de códigos QR y carga manual.
- Equivalencias entre códigos QR y materiales SAP.
- Creación, cierre y sincronización de picks.
- Generación de archivos XLSX para SAP.
- Administración de centros de costo, almacenes, clases de movimiento y centros SAP.
