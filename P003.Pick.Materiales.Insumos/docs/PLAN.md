# PLAN — App PICKING Frigorífico Gorina

> Estado: **IMPLEMENTADO v1** — este documento refleja lo acordado y construido.

## 1. Objetivo

App simple para escanear materiales con QR, imputar consumos a Centros de Costo
y generar el archivo para SAP. Herramienta operativa, no un sistema administrativo.
Preparada conceptualmente para agregar INGRESOS en el futuro (campo `tipo` en operaciones),
sin desarrollarlos.

## 2. Arquitectura (offline-first)

```
App Flutter (Android)
 ├─ BD local SQLite en el teléfono (réplica de maestros + cola de operaciones)
 ▼  Sincroniza automáticamente (login, cierre de pick) y manualmente (botón / pull-to-refresh)
API mínima .NET 8 en servidor Windows (Gorina.Api.exe autocontenido)
 ├─ SQLite central (gorina.db): fuente única de verdad
 └─ XLSX (ClosedXML) → carpeta configurable (\\SERVIDOR\INTERFAZ_SAP\CONSUMOS)
```

- El picking funciona sin red: escanea contra la réplica local; al cerrar queda `PENDIENTE`
  y se envía solo cuando hay señal.
- El GUID/ID interno de cada operación hace imposible duplicar consumos aunque se reintente.
- Los maestros se editan solo centralmente (ADMIN); los teléfonos se actualizan al sincronizar.

## 3. Perfiles

| Perfil | Puede |
|---|---|
| PICK | Nuevo Pick, Mis Picks |
| ADMIN | Todo lo anterior + Control de Picks, Equivalencias, Sin Equivalencia, CECOs, Usuarios |

Login con usuario + PIN (PBKDF2-SHA256). Funciona offline contra réplica local;
si hay red valida también contra el servidor y obtiene token persistente.

## 4. Flujo del operario

1. INICIO → NUEVO PICK → Orden + Almacén + CECO (buscador) + texto cabecera opcional.
   Cl.movimiento/Centro vienen de configuración del servidor.
2. Pantalla de ESCANEO continuo: cámara activa permanente + campo para lectora física/manual.
3. QR conocido → tarjeta material + cantidad (+ texto posición) → AGREGAR → sigue escaneando.
4. QR desconocido → "QR SIN EQUIVALENCIA" → pide Material SAP manual → continúa normal,
   posición marcada MANUAL (no crea equivalencia).
5. Lista editable en todo momento (modificar cantidad / eliminar posición).
6. CERRAR PICK → resumen → CONFIRMAR → cerrada e inmediatamente enviada si hay red.

## 5. Archivo de salida

Columnas exactas del modelo (`Ejemplos de Salida.xls`):

```
Orden | Cl.movimiento | Centro | Almacen | Material | Unidad de medida |
Centro de costo | Lote | Cantidad | Texto cabecera | texto posicion
```

- Una fila por posición; texto cabecera en primera fila de la Orden (configurable a todas las filas).
- Nombre único: `PICK_YYYYMMDD_HHMMSS_<orden>.xlsx`.
- Cantidad = lectura × factor; unidad = Unidad_SAP. Se conserva además la lectura original (trazabilidad).
- Generador tras interfaz interna lista para CSV/TXT futuros (no implementados).

## 6. Estados y control

Operación: `PENDIENTE` → `PROCESADO` / `ERROR` (+ mensaje).
- ERROR típico: carpeta de red no disponible. El ADMIN reintenta desde la app sin rehacer el pick.
- "SIN EQUIVALENCIA": agrupado por QR leído (usos, última fecha, último usuario, material usado)
  con botón CREAR EQUIVALENCIA precargada.

## 7. Estructura del proyecto

```
\Poyecto PICK\
  app\            App Flutter (lib/core, lib/data, lib/services, lib/screens)
  servidor\
    Gorina.Api\   API .NET 8 (Program.cs, Database.cs, XlsxGenerator.cs, Importador.cs)
    publicar.bat  Genera EXE autocontenido en servidor\publicar\
    README.md     Instalación del servidor
  docs\           PLAN.md (este archivo)
  Ejemplos\       Excel provistos (modelo de salida, maestros)
  Logo.png        Identidad corporativa (rojo #D2001C)
```

## 8. Decisiones tomadas (confirmadas por el usuario)

| Tema | Decisión |
|---|---|
| Conectividad | Hay zonas sin WiFi → app offline-first con cola de envío |
| Texto cabecera | Configurable: primera fila o todas (`CabeceraEnTodasLasFilas`) |
| Cantidades | Operario ingresa en unidad de lectura; archivo lleva cantidad×factor + Unidad_SAP |
| Almacén | Maestro importado (7 valores); el operario elige en Paso 1 (default A1) |
| Errores | ADMIN puede reintentar desde la app |
| Escaneo | Cámara ML Kit + compatible lectoras físicas (teclado) + entrada manual |
| Visual | Rojo corporativo #D2001C sobre blanco, logo en login/inicio/ícono |

## 9. Pendientes / próximos pasos sugeridos

- Reemplazar maestros parciales cuando el usuario entregue versiones completas
  (el Excel de Centros de Costo provisto contiene solo 38 CECOs activos).
- Definir reglas de limpieza del código QR cuando se reciban ejemplos reales
  (el campo `Codigo_Limpio` sugiere recortes del código crudo).
- Firma del APK (release usa firma debug por defecto) antes de distribución amplia.
- Etapa futura: módulo INGRESOS (la estructura ya lo contempla).

## 10. Registro de Cambios (Bitácora)

- **2026-09-15:** Migración del formato de salida de interfaz de `.xlsx` a `.csv`.
  - Delimitador: punto y coma (`;`).
  - Encabezados conservados en fila 1.
  - Formato decimal con punto (`.`) y codificación UTF-8 sin BOM.
  - Implementado en `CsvGenerator.cs`.
  - `archivo_nombre` pasa a registrarse con extensión `.csv` y el estado pasa a `PROCESADO`.
  - Textos de ayuda y exportación en la app Flutter sincronizados a `.csv`.
- **2026-09-16:** Implementación de servicio y autorecuperación 24-7 para `Gorina.Api`.
  - Watchdog `vigilante_gorina_api.ps1` que verifica `/api/ping` y reinicia el proceso automáticamente si no responde.
  - Tarea programada en Windows `Gorina - GorinaPick API 24-7` configurada para inicio con Windows y chequeo periódico cada 1 minuto.
- **2026-09-28:** Alta de usuarios operativos y blindaje de sesión (Fix 401 en Reserva de Picks).
  - Causa detectada: Al migrar a MySQL, los usuarios de los operarios (`wmaidana`, `limpieza`) no estaban presentes en la tabla `usuarios` y sus sesiones previas no existían en MySQL. Al intentar iniciar un pick (`/api/operaciones/reservar`), el servidor devolvía 401 "No autorizado".
  - Se crearon los usuarios `wmaidana` y `limpieza` en la base MySQL `p003.pick.materiales.insumos` con PIN 1234 y perfil `PICK`.
  - Se actualizó el mensaje de error 401 en el servidor y en la app móvil (`nuevo_pick_screen.dart`) para indicar explícitamente *"Sesión vencida. Vuelva a iniciar sesión con su PIN"*.
  - Compilado y publicado `Gorina.Api.exe` bajo servicio vigilante 24-7 con pruebas de login y reserva de orden exitosas.






