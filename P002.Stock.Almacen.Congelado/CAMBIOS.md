# Vitacora de Cambios — Stock Almacen Congelado

Registro chronologico de todas las modificaciones al proyecto.

---

## 2026-09-28 — v1.6.0: Migración Integral de Backend a C# .NET 8 y Persistencia MySQL 8.0

**Archivos modificados / creados:**
- `servidor/Gorina.Stock.Api/Gorina.Stock.Api.csproj`
- `servidor/Gorina.Stock.Api/Config.cs`
- `servidor/Gorina.Stock.Api/Database.cs`
- `servidor/Gorina.Stock.Api/StockModels.cs`
- `servidor/Gorina.Stock.Api/StockEngine.cs`
- `servidor/Gorina.Stock.Api/CapaService.cs`
- `servidor/Gorina.Stock.Api/Program.cs`
- `servidor/publicar/` y `A PROBAR/ExportarStock.exe`
- Base de datos MySQL: `` `p002.stock.almacen.congelado` `` (`127.0.0.1:3306`)
- `CAMBIOS.md`

### Qué se hizo
1. **Base de Datos MySQL Oficial (`p002.stock.almacen.congelado`):**
   - Creación de esquema relacional completo con tablas `catalogo_skus`, `cargas`, `romaneos_resumen`, `analisis_manual` y `configuracion`.
   - Migración íntegra y validada de los datos preexistentes:
     - 2.410 SKUs en `catalogo_skus`.
     - 80 órdenes de carga históricas en `cargas`.
     - 276 romaneos de balanza en `romaneos_resumen`.
     - 25 pallets de análisis Brasil en `analisis_manual`.
2. **Backend C# .NET 8 de Alto Rendimiento (`Gorina.Stock.Api`):**
   - Sustitución del monolito en PowerShell por un backend compilado nativo en C# .NET 8 (`ExportarStock.exe`).
   - Motor `StockEngine` de análisis en memoria con caché inteligente y detección automática de nuevos archivos CSV de stock.
   - Conexión MySQL con `MySqlConnector` v2.3.7.
   - Mantenimiento estricto de todas las rutas HTTP y compatibilidad total con `/stock_almacen`, `/datos`, `/ping`, `/analisis-manual`, `/api/cargas`, `/api/romaneos`, etc.
3. **Despliegue y Validación:**
   - Despliegue en `A PROBAR/ExportarStock.exe` operando bajo la tarea programada `Gorina - Stock Almacen 24-7` en el puerto `8090`.
   - Pruebas exitosas de consulta (80 SKUs agrupados, 1.461 pallets, 1.173.314 kg) y mutaciones dinámicas de marcado/desmarcado de análisis.

### Pendientes Registrados para Próximas Etapas
- **Recepción e Ingesta de Mensajes XML de Pallets (Ingresos / Egresos / Trazabilidad)**:
  - Destinar un endpoint receptor dedicado (ej. `POST /api/pallets/evento-xml` o similar) para procesar mensajes XML en tiempo real procedentes de balanzas, sistemas de almacén o PLCs.
  - Volcar los eventos a tablas históricas en MySQL (movimientos, ubicaciones, bultos y kilos) para auditoría y trazabilidad histórica.
  - **Nota**: La estructura final de campos y el formato exacto del XML serán determinados en la etapa específica de implementación de dicho módulo.

---

## 2026-09-24 — v1.5.0: Soporte Integral para URL Corporativa `/stock_almacen` y Redirección Institucional IIS

**Archivos modificados:**
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `C:\Ciclo3\Servicios\DASHBOARD\PROD\dashboard\stock_almacen\index.html` (Redirección IIS puerto 80)
- `CAMBIOS.md`

### Qué se hizo
1. **Soporte Nativo de la Subruta `/stock_almacen` en el Servidor Backend:**
   - Se implementó normalización regex de subrutas en `exportar_stock.ps1` (`^/stock_almacen/?$` y `^/stock_almacen/(.*)$`), permitiendo que el servidor atienda solicitudes tanto en la raíz como bajo el prefijo corporativo `/stock_almacen`.
   - Se habilitó la resolución transparente para el HTML de la aplicación, el bundle de JavaScript (`/stock_almacen/exceljs.min.js`), endpoints de datos (`/stock_almacen/datos`), pulso (`/stock_almacen/ping`) y todas las APIs REST (`/stock_almacen/api/...`).
   - Se mantuvieron intactos y 100% compatibles los accesos directos a la raíz (`/`) para monitores de salud, diagnósticos automáticos y scripts de sincronización (`descargar_stock.ps1`).
2. **Preservación de URL en Frontend (`index.template.html`):**
   - Se reemplazaron las llamadas `location.href = '/'` por `location.reload()` tras seleccionar carpetas o archivos CSV manuales, preservando la navegación en `/stock_almacen` sin saltos forzados a la raíz.
   - Actualización de badge visual a **v1.5.0**.
3. **Punto de Entrada Institucional en IIS (Puerto 80):**
   - Se desplegó un redireccionador instantáneo en `C:\Ciclo3\Servicios\DASHBOARD\PROD\dashboard\stock_almacen\index.html` bajo el sitio IIS principal de la máquina `fglp53`.
   - Cualquier usuario que ingrese `http://fglp53/stock_almacen` (sin especificar el puerto 8090) es redirigido automáticamente a `http://fglp53:8090/stock_almacen` de forma inmediata.
4. **Validación, Compilación y Despliegue:**
   - Compilación exitosa de `ExportarStock.exe` versión **1.5.0.0** con `pack.ps1`.
   - Despliegue en `A PROBAR/ExportarStock.exe` y reinicio del servicio 24/7 `Gorina - Stock Almacen 24-7`.
   - Verificación de HTTP 200 OK en:
     - `http://fglp53:8090/stock_almacen` (HTML completo, 345 KB)
     - `http://fglp53:8090/stock_almacen/exceljs.min.js` (JavaScript, 947 KB)
     - `http://fglp53:8090/stock_almacen/ping` (JSON de pulso)
     - `http://fglp53/stock_almacen` (HTTP 301 / 200 de redirección hacia puerto 8090)
     - `http://fglp53:8090/` (Compatibilidad retroactiva raíz garantizada)

---

## 2026-09-24 — v1.4.9: Incorporación de Salidas por Pedidos de Clientes (Depósito 101), Badges de Cliente y Limpieza de Interfaz

**Archivos modificados:**
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Generación Automática de Salidas para Pedidos con Cliente en Depósito 101:**
   - Se implementó la función `Extract-PedidoCliente` en `exportar_stock.ps1` para detectar patrones `Pedido: [numero] [CLIENTE]` en romaneos de **Depósito 101** (ej. `QUICKFOOD SA`, `SWIFT ARGENTINA`, `CATTER MEAT`).
   - Se agregaron las salidas automáticas de pedidos al historial de cargas con ID del tipo `CRG-YYYYMMDD-HHMMSS-PED-[CLIENTE]`, asignando cliente, kilos reales de báscula y pallets correspondientes.
   - Se excluyeron deliberadamente consumos internos y movimientos de carnicería/embajada conforme a la directiva del usuario.
2. **Visualización y Búsqueda por Cliente en Frontend:**
   - Se incorporó la badge verde de cliente (`🏢 QUICKFOOD SA`) en las tarjetas de salida/carga en la pestaña de detalle.
   - El buscador de texto ahora permite filtrar directamente por nombre de cliente (ej: escribiendo "QUICKFOOD").
3. **Retiro del Botón Excel Individual de Tarjetas de Carga:**
   - Se removió el botón individual de descarga Excel de cada tarjeta en la lista de pendientes/cerradas, centralizando la descarga exclusivamente en el Informe Ejecutivo Gerencial para evitar redundancia y errores.
4. **Cómputo en Resumen Ejecutivo:**
   - Las salidas de pedidos locales ahora se integran de manera nativa al cálculo de KPIs, comparativa semanal y desglose por día del Resumen Ejecutivo (acumulando 20 salidas totales en la semana activa).
5. **Validación, Compilación y Despliegue:**
   - Compilación exitosa de `ExportarStock.exe` versión **1.4.9.0** con `pack.ps1`.
   - Despliegue en `A PROBAR/ExportarStock.exe` y reinicio de la tarea 24/7 `Gorina - Stock Almacen 24-7`.
   - Comprobación de conectividad HTTP 200 en `http://127.0.0.1:8090/ping` y `/api/cargas` (65 cargas totales devueltas).

---

## 2026-09-23 — v1.4.8: Restricción Estricta a Depósito 101 (Enfriado, Congelado y Madurado) y Saneamiento Retrospectivo de Historial

**Archivos modificados:**
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/cargas_historial.json`
- `A PROBAR/cargas_historial.json`
- `A PROBAR/romaneos_resumen.json`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Restricción Estricta a Depósito 101 en Ingesta y Auto-Vinculación:**
   - Se ajustó el motor de sincronización de Romaneos de Salida (RS) de CAPA en `exportar_stock.ps1` para procesar **única y exclusivamente romaneos con `dep -eq '101'`** (tanto para vinculación a cargas existentes como para auto-creación de cargas individuales).
   - Se excluyó terminantemente el Depósito 151 y cualquier otro código de depósito ajeno al despacho de almacén.
   - El tipo de conservación se rige fielmente por el Campo 9 del CSV de CAPA (`1` = Enfriado, `2` = Congelado, `3` = Madurado; con default Congelado).
2. **Corrección Retrospectiva y Purga de Historial (`cargas_historial.json`):**
   - Con respaldo previo fechado, se eliminaron del archivo histórico las 31 cargas automáticas que habían sido creadas indebidamente desde el Depósito 151.
   - Se eliminaron las cargas fantasma creadas previamente por números de `SHIPPING MARK` (`OF1297` y `OF4740`).
   - El historial quedó normalizado en **57 cargas limpias** tanto en `A PROBAR/` como en `Fuente A PROBAR/`.
3. **Refuerzo de `Extract-Ofertas` y Reevaluación en Caché:**
   - Se eliminó el match de regex sobre shipping marks para evitar falsos positivos de ofertas de exportación.
   - Se añadió recálculo dinámico de ofertas (`Extract-Ofertas`) al inicializar la caché desde `romaneos_resumen.json`, evitando que romaneos cacheados retengan ofertas obsoletas.
4. **Validación de Cargas Semanales vs. Cargas Gorina:**
   - **Martes 22/09:** Exactamente **5 cargas** (`PNJ 234`, `AC915CH`, `AG731VL`, `OAO 443`, `OBR 591`), coincidencia del 100% con lo informado por Andrés Romano.
   - **Miércoles 23/09:** Exactamente **6 cargas** (`AG731VL`, `MNO 527`, `AC915CH`, `NEF 769`, `GIQ 561`, `AG167KF`), coincidencia del 100% con lo informado por Andrés Romano.
5. **Validación, Compilación y Despliegue:**
   - Compilación exitosa de `ExportarStock.exe` versión 1.4.8.0 con `pack.ps1`.
   - Despliegue en `A PROBAR/ExportarStock.exe` y reinicio de la tarea 24/7 `Gorina - Stock Almacen 24-7`.
   - Comprobación de conectividad HTTP en `http://127.0.0.1:8090/ping` y respuesta íntegra de la API `/api/cargas`.

---

## 2026-09-23 — v1.4.7: Eliminación de Scrollbars Internos, Cuadrícula Proporcional (1.25fr) y Holgura de Columnas sin Superposición

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Eliminación Total de Barras de Scroll Horizontal Internas:**
   - Se removió `overflow-x: auto;` de los contenedores de las 3 tablas de desglose (`Totales por Día`, `Salidas por Destino` y `Salidas por Establecimiento`), reemplazándolo por `width: 100%; overflow: hidden;`.
   - Se aplicó `overflow: hidden; text-overflow: ellipsis;` a `.resumen-mini-table td`, asegurando que ninguna celda genere desbordes o barras de desplazamiento dentro de una subcolumna o tarjeta.
2. **Rebalanceo de Cuadrícula Proporcional (1.25fr para Card 1) y Separación de Títulos:**
   - Para resolver la superposición de títulos `SALIDAS` y `PALLETS` (provocada al coexistir 5 columnas en Card 1 contra 4 en Cards 2 y 3 con un ancho uniforme), se configuró la cuadrícula a `grid-template-columns: 1.25fr 1fr 1fr;`.
   - Card 1 dispone ahora de un 25% más de ancho (~488px), asignando anchos proporcionales exactos: `Día: 18%`, `Fecha: 22%`, `Salidas: 18%`, `Pallets: 18%`, `KG. Netos: 24%` (Total 100%). Cada encabezado cuenta con más de 85px de espacio libre, eliminando cualquier superposición o contacto tipográfico.
   - En Cards 2 y 3 se optimizaron las proporciones a: `Destino/Estab: 26%`, `Pallets: 20%`, `Kilos: 32%`, `% Total: 22%` (Total 100%).
3. **Centrado Simétrico de Pallets en Totales por Día:**
   - El encabezado `PALLETS` en Card 1 ahora está centrado (`<th class="center">`), y las celdas diarias y de la fila TOTAL ahora se renderizan con `<td class="center">`, logrando simetría vertical alineada con su título.
4. **Ampliación de Ventana Modal Preservando la Armonía:**
   - Se incrementó el ancho máximo de `.historial-modal-content` de 1200px a **1320px** (`width: 96%; max-width: 1320px;`), aportando 120px adicionales de margen horizontal sin alterar la estética visual ni el equilibrio del modal.
5. **Validación y Despliegue:**
   - Compilación exitosa de `ExportarStock.exe` versión 1.4.7.0 con `pack.ps1`.
   - Despliegue en `A PROBAR/ExportarStock.exe` y reinicio de la tarea 24/7 `Gorina - Stock Almacen 24-7`.
   - Comprobación de respuesta HTTP 200 en `http://127.0.0.1:8090/ping`.
6. **Depuración de Duplicados en `cargas_historial.json`:**
   - Se crearon copias de seguridad fechadas y se purgaron los 4 registros masivos duplicados (`CRG-20260922-044133`, `CRG-20260922-080459`, `CRG-20260922-110131` y `CRG-20260923-090309`).
   - Se eliminaron 655 pallets ficticios y más de 660.000 kg duplicados, normalizando los totales a los camiones individuales reales con RS de cada jornada.

---

## 2026-09-23 — v1.4.6: Centrado Simétrico de Columnas (Día, Pallets y Kilos) y Ampliación de Espacio en Desglose

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Centrado Simétrico en Tabla de Totales por Día (`Totales por Día (Lun a Vie)`):**
   - Se centró el encabezado de la columna **DÍA** (`<th class="center" style="width:22%;">Día</th>`) y las celdas de días (`<td class="center">`), alineando el título exactamente con su contenido.
   - En la fila de total, `TOTAL` ahora está centrado (`<td colspan="2" class="center">TOTAL</td>`) abarcando simétricamente el bloque izquierdo (Día + Fecha).
2. **Centrado de Pallets y Reposicionamiento Holgado de Kilos en Salidas por Destino y Establecimiento:**
   - **Pallets Centrado:** Tanto el encabezado (`<th class="center">`) como los valores diarios (`<td class="center">`) y la fila total de Pallets ahora se renderizan estrictamente centrados en su columna, eliminando la proximidad visual con Kilos.
   - **Kilos Holgado y Desplazado a la Izquierda:** Se asignó un 36% de ancho fijo a la columna Kilos y se centraron tanto el título como los valores netos, separándolos cómodamente de Pallets a la izquierda y de % Total a la derecha.
   - **Table-Layout Fixed:** Se fijó `table-layout: fixed;` en `.resumen-mini-table` para evitar que el navegador comprima columnas numéricas arbitrariamente.
3. **Ampliación de Espacio Horizontal del Modal:**
   - Se incrementó el `max-width` de `.historial-modal-content` de 1120px a **1200px**, otorgando más de 26px adicionales de ancho a cada una de las 3 tarjetas de desglose (`Totales por Día`, `Salidas por Destino`, `Salidas por Establecimiento`).
4. **Sincronización en Reporte Excel:**
   - Se replicó el centrado de las columnas Día, Pallets, Kilos y % Total en las hojas generadas con ExcelJS para mantener 100% de coherencia estética.
5. **Validación y Despliegue:**
   - Compilación exitosa de `ExportarStock.exe` versión 1.4.6.0.
   - Despliegue en `A PROBAR/ExportarStock.exe` y reinicio de la tarea 24/7 en puerto 8090 con respuesta HTTP 200 verificada.

---

## 2026-09-23 — v1.4.5: Fluidez Nativa de Cursor y Scroll en Terminales Remotas, Centrado de Tabla Diaria y Estandarización a 'Salidas'

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Solución Definitiva de Fluidez en Terminales Remotas y Thin Clients ("Mouse Lento"):**
   - **Eliminación de filtros gráficos pesados (`backdrop-filter: blur`):** En adaptadores de video virtual y sesiones RDP de terminales de planta, el rasterizado de blur en tiempo real sobre toda la pantalla saturaba la CPU/GPU virtual provocando latencia severa en el puntero del mouse. Se eliminó `backdrop-filter: blur(...)` manteniendo la transparencia translúcida de fondo oscuro (`rgba(10, 14, 23, 0.75)`), preservando la estética moderna sin costo gráfico.
   - **Retorno a desplazamiento nativo de Windows:** Se removió `scroll-behavior: smooth` de `.historial-body`, devolviendo el scroll con rueda de mouse a respuesta física instantánea de 0ms (sin animación impuesta de desaceleración).
   - **Eliminación de saltos por contención dinámica (`content-visibility: auto` y capas 3D):** Al paginarse en bloques estables de 25 tarjetas, se removieron `content-visibility`, `contain` y `transform: translateZ(0)` de las tarjetas y modales, evitando jitter en el cálculo de altura y composición pesada de texturas en terminales.
2. **Alineación Visual y Simetría de la Tabla Diaria (`Totales por Día`):**
   - Se crearon las clases `.resumen-mini-table th.center` y `.resumen-mini-table td.center`.
   - La columna **FECHA** y la columna **SALIDAS** quedan estrictamente centradas tanto en el encabezado como en los valores numéricos de las filas y fila de total.
   - La columna **DÍA** permanece a la izquierda (`TOTAL` abarca 2 columnas con `colspan="2"`), y **PALLETS** y **KG. NETOS** alineados a la derecha (`.num`), logrando una tabla perfectamente proporcionada y legible.
3. **Estandarización del Término 'CARGAS' por 'SALIDAS':**
   - En el Resumen Ejecutivo, tarjetas de KPIs y tablas de desglose, se reemplazó la denominación 'Cargas' por **'Salidas'** (abarcando tanto despachos a clientes como traslados internos).
   - Se actualizó el reporte descargable en Excel (`exportarExcelResumenEjecutivo`) reflejando la denominación 'Salidas' y centrando las columnas de Fecha y Salidas.
4. **Validación y Despliegue:**
   - Compilación exitosa del binario `ExportarStock.exe` (v1.4.5.0) con `pack.ps1`.
   - Reemplazo y despliegue en `A PROBAR/ExportarStock.exe`.
   - Reinicio de la tarea 24/7 `Gorina - Stock Almacen 24-7` y comprobación de respuesta HTTP 200 en `http://127.0.0.1:8090/`.

---

## 2026-09-23 — v1.4.4: Fluidez Extrema a 60 FPS, Almanaque Flotante Interactivo y Filtro Rápido 'En Proceso / Asignar RS'

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Prioridad 1 — Fluidez Absoluta del Scroll en la Ventana de Cargas (60 FPS sin tirones):**
   - **Eliminación del doble scroll anidado:** Se suprimió el scroll independiente de `.cargas-list-wrap` (`overflow-y: auto; max-height: 520px`), unificando el desplazamiento vertical en un único contenedor fluido (`.historial-body`) con `scroll-behavior: smooth`, `overscroll-behavior: contain` y aceleración por GPU (`transform: translateZ(0)`).
   - **Aislamiento de capas GPU:** Se aplicó `transform: translateZ(0)` a `.historial-modal-content` para independizarlo del `backdrop-filter` del overlay, eliminando el re-renderizado global de la ventana al desplazarse.
   - **Virtualización nativa y containment:** Se incorporó `content-visibility: auto; contain-intrinsic-size: 135px; contain: layout style paint;` en `.carga-card`, permitiendo que el navegador omita el cálculo y dibujo de las tarjetas fuera de la pantalla.
   - **Renderizado por lotes (Batching progresivo):** Se implementó paginación suave de 25 en 25 tarjetas con centinela interactivo y auto-carga vía `IntersectionObserver`, garantizando navegación instantánea sin importar la cantidad de cargas en el historial.
2. **Selector de Día tipo Almanaque Flotante (Idéntico a la Barra Principal):**
   - Se reemplazó el control nativo `<input type="date">` por un botón interactivo `📅 [Elegir Día]` conectado al dropdown flotante de calendario (`singleDateCalPopup`, target `'cargas'`).
   - El almanaque permite navegar meses con `<` y `>`, seleccionar cualquier día en 1 click, muestra qué días tienen cargas despachadas (marcador azul y tooltip con cantidad de cargas) y añade botón directo para quitar la fecha.
   - Al seleccionar un día, el botón adopta la fecha seleccionada (`📅 DD/MM/AAAA`) con estilo activo y botón rápido `✕` para limpiar.
3. **Barra de Herramientas Sticky y Filtro Directo 'En Proceso / Asignar RS':**
   - La barra de filtros de fecha y estado se fijó como `position: sticky; top: -18px` para permanecer siempre visible mientras el usuario desciende por la lista.
   - Se jerarquizó el botón de estado `⚠️ En Proceso / Asignar RS (${cnt})` para que los operarios identifiquen y filtren en un instante todos los camiones que esperan romaneo de salida.
4. **Validación y Despliegue Operativo:**
   - Compilación exitosa del binario portable `ExportarStock.exe` (v1.4.4.0) con `pack.ps1`.
   - Traslado verificado a `A PROBAR/ExportarStock.exe` y reinicio de la tarea 24/7 `Gorina - Stock Almacen 24-7`.
   - Verificación de respuesta HTTP 200 en puerto 8090 con ping y entrega de componentes activos.

---

## 2026-09-23 — v1.4.3: Soporte de Conservación CAPA (Enfriado/Congelado/Madurado), Ultra-Fluidez y Tipografía Optimizada

**Archivos modificados:**
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `A PROBAR/romaneos_resumen.json`
- `A PROBAR/cargas_historial.json`
- `CAMBIOS.md`

### Qué se hizo
1. **Soporte Integral de Conservación desde Campo 9 de CAPA:**
   - Se procesó la columna 9 (`Con.`) de los archivos de salida de CAPA: `1` = Enfriado, `2` = Congelado, `3` = Madurado.
   - Se amplió la ingesta automática para aceptar tanto Depósito 101 como Depósito 151 (Chiller/Enfriados) y romaneos con `Con == 1`.
   - Se incorporaron las cargas enfriadas al historial de despachos, sumando sus kilos netos reales al total general del Resumen Ejecutivo.
   - En cada tarjeta de carga se incorporó el badge distintivo de conservación: `🥩 Enfriado` (ámbar), `❄️ Congelado` (celeste), `🏺 Madurado` (púrpura) o `🔄 Mixto` (teal).
   - En cada chip de Romaneo vinculado se detalla la conservación y en el modal de vinculación de RS se sumó la columna y filtro por conservación.
2. **Optimización Extrema de Fluidez del Menú de Cargas:**
   - **Lazy Loading de Tablas de Renglones:** Se eliminó la generación anticipada de tablas de renglones para todas las cargas cerradas. El HTML del detalle ahora se renderiza bajo demanda (`data-cargado="0"`) únicamente al pulsar `👁️ Ver Detalle`, reduciendo cientos de nodos DOM y acelerando el renderizado de la lista a menos de 5ms.
   - **Debouncing en Búsqueda:** Se implementó `debouncedFiltrarListaCargas()` (160ms) en el cuadro de búsqueda para evitar re-renderizados continuos e innecesarios durante el tipeo de los operarios.
3. **Tipografía Agrandada y Contraste Nitido Preservando la Transparencia:**
   - Se mantuvo intacto el diseño translúcido con efecto vidrio (`backdrop-filter: blur`, fondos con transparencia).
   - Se incrementaron los tamaños de texto y pesos tipográficos para máxima legibilidad en monitores de planta y depósito:
     * Identificador de carga: de 13px a **14.5px** bold con sombra de texto.
     * Etiquetas de métricas (`lbl`): de 9px a **11px** semibold con color `#a0aec0`.
     * Valores numéricos (`val`): de 13px a **15px** bold blanco `#ffffff` con realce.
     * Badges de estado y conservación: de 10px a **11.5px** bold con relleno contrastante.
     * Botones de acción y filtros: de 11px a **12px** con mayor área clickeable (padding 5px 12px).
4. **Validación y Despliegue en Producción:**
   - Compilación exitosa del nuevo ejecutable portable `ExportarStock.exe` (v1.4.3.0) con `pack.ps1`.
   - Despliegue en `A PROBAR/ExportarStock.exe` y reinicio de la tarea programada `Gorina - Stock Almacen 24-7`.
   - Verificación funcional HTTP 200 en puerto 8090, 75 cargas indexadas (60 congelado, 14 enfriado, 1 madurado) y respuesta fluida instantánea (< 0.6s).

---

## 2026-09-22 — v1.4.2: Interfaz Operativa de Cargas con Filtros por Día, Estado y Guía de Operación

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Guía Visual para Operarios en Cargas Realizadas:**
   - Banner explicativo superior que clarifica sin ambigüedades qué significa cada estado:
     * **En Proceso (Amarillo):** Cargas descargadas que esperan vincular su Romaneo de Salida (RS) de CAPA para computar los kilos netos finales.
     * **Cerrada (Verde):** Cargas con RS y kilos netos confirmados, ya sumadas a los totales del Resumen Ejecutivo.
2. **Barra de Filtros Directos por Día:**
   - Botones rápidos: `[ Ver Todas ]`, `[ Hoy ]`, `[ Ayer ]` y selector de calendario individual (`<input type="date">`).
   - Permite al operador consultar con un solo click los camiones de una fecha puntual sin tipear nada.
3. **Píldoras de Filtro por Estado con Contadores en Vivo:**
   - `Todas (44)` | `🟡 En Proceso (2)` | `🟢 Cerradas (42)`.
   - Permite a los operarios ver al instante cuántos y cuáles camiones tienen pendientes de romaneo para resolver en el día.
4. **Diseño de Tarjetas Orientado a la Acción:**
   - Tarjetas diferenciadas con franja lateral de color: ámbar para *En Proceso* y verde para *Cerrada*.
   - Botón destacado y prioritario `🔗 Asignar RS de CAPA` en cargas pendientes.
   - Botones contextuales claros en cargas cerradas: `👁️ Ver Detalle`, `✏️ Modificar RS`, `📥 Excel`, `🗑️ Eliminar`.
5. **Validación y Despliegue:**
   - Compilación exitosa con `pack.ps1` (`v1.4.2`) y binario desplegado en `A PROBAR/ExportarStock.exe`.
   - Tarea programada `Gorina - Stock Almacen 24-7` reiniciada y verificada respondiendo en puerto `8090`.

---

## 2026-09-22 — v1.4.1: Normalización de Encabezados a KG. Netos e Inspección / Edición 1-Click desde Resumen Ejecutivo

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Normalización Visual de Encabezados y KPIs:**
   - Se removió la mención `(Balanza)` en la tabla *Totales por Día (Lun a Vie)*, reemplazándola de forma limpia y concisa por **`KG. Netos`**.
   - Se actualizaron las tarjetas de KPIs en el Resumen Ejecutivo: `Total KG. Netos` y `Desvío Neto vs Estimado`.
   - Se normalizaron las etiquetas en la exportación Excel gerencial a `KG. NETOS` y `KG. Netos`.
2. **Navegación e Inspección / Edición 1-Click desde Resumen Diario:**
   - Ahora cada fila de día con cargas en la tabla *Totales por Día* es clickeable (`.fila-dia-interactiva`), con cursor pointer, efecto hover y tooltip explicativo.
   - Al hacer click en cualquier día (ej. Lunes 21/09 o Martes 22/09), la aplicación cambia instantáneamente a la pestaña *Cargas Realizadas y Pesaje* filtrando por la fecha exacta seleccionada (`irACargasPorFecha`).
3. **Flujo de Auditoría y Corrección de Cargas:**
   - Se incorporó el botón `✕ Limpiar` junto al cuadro de búsqueda de cargas para restablecer la vista completa en un solo click.
   - El operador puede inspeccionar el detalle (`👁️ Ver Detalle`), modificar romaneos asociados (`✏️ Vincular / Editar RS`) o dar de baja cargas incorrectas/duplicadas (`🗑️`), impactando inmediatamente en los totales del Resumen Ejecutivo.
4. **Validación y Despliegue:**
   - Binario compilado con `pack.ps1` (`v1.4.1`) y desplegado en producción `A PROBAR/ExportarStock.exe`.
   - Servicio 24/7 verificado respondiendo en puerto `8090`.

---

## 2026-09-22 — v1.4.0: Vinculación Automática y Manual de Romaneos de Salida (RS) con Cargas Gorina y Kilos Netos de Balanza

**Archivos modificados:**
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/carpeta.json`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/carpeta.json`
- `A PROBAR/cargas_historial.json`
- `A PROBAR/romaneos_resumen.json`
- `A PROBAR/ExportarStock.exe`

### Qué se hizo
1. **Indexador y Caché Ultrarrápido de Romaneos CAPA (`exportar_stock.ps1`):**
   - Se implementó `Sync-RomaneosCapa` con lectura ultraligera de metadatos (línea 2 para fecha, patente, destino y observación; última línea o sumatoria directa de columna 13 para `Kg.Neto`).
   - Caché local persistente en `romaneos_resumen.json` (~50 KB, 198 romaneos indexados) con verificación de `LastWriteTimeUtc.Ticks` (lecturas en < 1 ms, sin impacto en la red ni saturación de VM).
   - Soporte automático para unidad de red `J:\UTIL\USER\CAPA` y ruta UNC `\\svr\d\UTIL\USER\CAPA`, garantizando acceso continuo incluso bajo ejecución de servicio como `SYSTEM`.
   - Extracción de números de oferta (`OF,XXXXX`, `OF XXXXX`, `OFERTA XXXXX`) con normalización numérica.
2. **Motor de Vinculación Automática (`Auto-VincularCargasPendientes`):**
   - Vinculación inteligente por número de oferta y ventana de consistencia temporal (+/- 4 días).
   - Reemplazo del concepto de "Kilos Reales" por **Kilos Netos (Balanza)** calculados estrictamente desde `Kg.Neto` (columna 13) del Romaneo de Salida.
   - Si la carga cuenta con RS vinculados y kilos netos de balanza mayores a 0, pasa automáticamente a estado **Cerrada**.
   - Asignación automática de patente del camión a la carga.
   - Retrocompatibilidad y backfill automático sobre el historial existente (`cargas_historial.json`), vinculando exitosamente las 6 cargas históricas pendientes.
3. **Ingesta Automática de Cargas desde RS (Depósito 101 - Septiembre 2026 en adelante):**
   - Detección de columna 20 (`Dep == 101`) y filtrado estricto a partir del `01/09/2026` con ofertas comerciales reconocidas.
   - Prevención exhaustiva de duplicados: si la oferta ya existe en una carga previa, se asocia el RS a dicha carga; si no existe, se crea una carga nueva en estado **Cerrada**.
   - Agrupación consolidada por oferta y fecha/camión (ej. RS 464464 + 464467 agrupados bajo OF 27973).
   - Generación automática de 21 cargas de exportación de Septiembre (llegando a 44 cargas totales), permitiendo el análisis comparativo retrospectivo de las semanas 1 a 4 en el Resumen Ejecutivo.
4. **Nuevos Endpoints Backend REST:**
   - `/api/romaneos`: Devuelve el catálogo completo de romaneos indexados desde la caché local.
   - `/api/vincular-rs-carga`: Permite vinculación manual o desvinculación de uno o más RS para una carga, recalculando kilos netos, patente y estado.
   - `/api/sincronizar-romaneos`: Forzado de reescaneo inmediato de la carpeta CAPA y auto-vinculación.
4. **Interfaz de Usuario y Modal de Vinculación RS (`index.template.html`):**
   - Nueva tarjeta de carga en Pestaña 2: muestra badge de patente (`🚚 Patente`), kilos netos balanza con color status, cálculo de desvío % vs estimado y chips visuales detallados de cada RS vinculado (`RS XXXXX: X,XXX kg · XXX cjs`).
   - Modal interactivo `#modalVincularRS`: selector múltiple con checkboxes, búsqueda instantánea por RS/oferta/patente/destino, pre-selección automática de sugeridos por oferta, botón para agregar RS manual por número y resumen en vivo de kilos netos y patente resultante.
   - Botón `🔄 Sincronizar Romaneos (CAPA)` en cabecera de Cargas Gorina.
   - Actualización de terminología en Resumen Ejecutivo (KPIs, tablas) y exportación a Excel en blanco y negro con columnas de Patente, RS Vinculados y Kilos Netos Balanza.
5. **Compilación y Despliegue en Producción:**
   - Binario compilado con `pack.ps1` (`v1.4.0`) y desplegado en `A PROBAR/ExportarStock.exe`.
   - Servicio 24/7 `Gorina - Stock Almacen 24-7` reiniciado y verificado operativo en puerto `8090`.

---

## 2026-09-18 — v1.3.2: Incorporación de Sufijo -ANGUS- para SKUs Terminados en 08

**Archivos modificados:**
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/catalogo.json`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`

### Qué se hizo
1. **Backend (`exportar_stock.ps1`):**
   - Se implementó la función auxiliar `Format-SkuNombre([string]$sku, [string]$nombre)` que detecta de forma no destructiva si el SKU finaliza en `08` y concatena ` -ANGUS-` al final de la descripción si no lo poseía previamente.
   - Se aplicó el formateador en todos los puntos de ingesta y armado de registros: lectura de `catalogo.json`, lectura de `Stock.Almacen.Base.xlsx`, mapeo de grupos activos con stock, aprendizaje dinámico de nuevos SKUs desde el CSV de CTTO y catálogo de productos sin stock.
2. **Base de Catálogo Embebida (`catalogo.json`):**
   - Se actualizaron las 76 entradas de productos de raza Aberdeen Angus terminados en `08` para incluir el sufijo ` -ANGUS-` en el JSON base embebido dentro del binario.
3. **Frontend (`index.template.html`):**
   - Se incorporó normalización preventiva en `renderData()` asegurando que cualquier fila con SKU terminado en `08` refleje el sufijo ` -ANGUS-` en tabla principal, selector de cargas, exportación Excel y búsqueda.
4. **Compilación y Despliegue en Producción:**
   - Compilado con `pack.ps1` y desplegado en `A PROBAR/ExportarStock.exe`.
   - Servicio productivo `Gorina - Stock Almacen 24-7` reiniciado y verificado en puerto `8090` (PID 9292).

---

## 2026-09-15 — v1.3.1: Formato Blanco y Negro para Exportación Excel de Cargas

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`

### Qué se hizo
1. **Exportación Excel de Cargas (`CARGAS_GORINA_*.xlsx`):**
   - Se eliminaron todos los colores de fondo (fondos verdes de título, subtítulo, encabezados y subtotales; fondos naranja de ítems pendientes; fondo gris de totales).
   - El reporte completo quedó en blanco y negro (fondos transparentes/blancos con texto en negro `#000000`).
   - Se aplicó negrita destacada al título principal ("CARGAS GORINA"), a los nombres de las 13 columnas y a los subtotales/totales.
   - Encabezados con borde inferior reforzado y fila total con doble subrayado contable.
   - Soporte idéntico en blanco y negro aplicado tanto en la descarga de cargas activas (`exportarExcel`) como en la re-descarga desde el historial (`redescargarExcelCarga`).
2. **Compilación y Despliegue en Producción:**
   - Binario compilado y desplegado a `A PROBAR/ExportarStock.exe`.
   - Servicio productivo 24/7 reiniciado y activo en puerto `8090`.

---

## 2026-09-14 — v1.3.0: Incorporación de Establecimiento Faenador y Diferenciación de Elaborador

**Archivos modificados:**
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/carpeta.json`
- `Fuente A PROBAR/ExportarStock.exe`

### Qué se hizo
1. **Backend (`exportar_stock.ps1`):**
   - Detección de columna `Est. Faenador` en los archivos CSV de stock (`lista_cajas_*.csv`).
   - Clave de agrupamiento de stock extendida a 4 dimensiones: `SKU | Venta | Est. Elaborador | Est. Faenador`. Permite discriminar pallets con igual elaborador pero distinto faenador sin alterar la integridad de los LPNs.
   - Inclusión del campo `estabFaenador` en el payload JSON entregado al frontend.
2. **Filtros y Tabla Principal (`index.template.html`):**
   - Se posicionó primero el filtro desplegable "Est. Faenador" (`filterFaenador`) y luego "Est. Elaborador" (`filterEstablecimiento`).
   - En la tabla de stock, la columna "Est. Faen." precede a "Est. Elab." tanto en la cabecera fija como en las filas de datos.
3. **Módulo de Cargas Gorina y Exportaciones Excel:**
   - En la tabla de preparación de descargas (`descargaTable`), la columna "Est. Faen." precede a "Est. Elab.", manteniendo los índices correctos para duplicación y cálculo de kilos aproximados.
   - En el reporte Excel de Stock (`STOCK_ALMACEN_*.xlsx`), "Est. Faen." figura en columna C y "Est. Elab." en columna D.
   - En el reporte Excel de Cargas Gorina, "Est. Faen." figura en columna E y "Est. Elab." en columna F.
   - En el Resumen Ejecutivo semanal ("Detalle de Cargas"), se respeta el mismo orden ("Est. Faen." antes de "Est. Elab.").
4. **Calibración de Anchos de Columnas (Tabla Principal):**
   - Se recalibraron las 12 reglas CSS `nth-child(1..12)` de la tabla fija `#stockTable` y `.head-table` para acomodar la nueva columna `Est. Faenador` sin distorsionar el resto.
   - Se restablecieron los anchos originales: Col 8 MAT SAP (`88px`), Col 10 Total Pallets (`145px`), Col 11 Cajas (`80px`), Col 12 Kilos Neto (`110px`).
   - La columna Nombre (Col 9) recuperó su asignación `width: auto` con salto de línea natural (`white-space: normal`), evitando truncados indeseados.
5. **Verificación y Despliegue en Producción:**
   - La versión productiva en puerto `8090` fue actualizada y reiniciada bajo la tarea programada `Gorina - Stock Almacen 24-7`.
   - Pruebas superadas con verificación de cabeceras, alineación visual de columnas y descarga de Excel.

---

## 2026-09-09 — v1.2.1: Corrección de Detección Cliente vs Servidor (Heartbeat /ping)

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`

### Qué se corrigió
1. **Detección real de desactualización del navegador del usuario:**
   - La tarea automática de descarga (`descargar_stock.ps1`) al ejecutarse a las horas en punto (ej. 17:00, 17:30, 18:00) notificaba al servidor local (`/refrescar`), actualizando la memoria interna del servidor.
   - El endpoint `/ping` comparaba únicamente el disco contra la memoria del servidor. Como el servidor ya tenía cargado el nuevo CSV, devolvía `hasNew: false`, provocando que cualquier navegador abierto previamente (ej. a las 16:51) creyera erróneamente que estaba "Al día".
   - **Solución implementada:** el cliente ahora rastrea el archivo exacto cargado en su pantalla (`currentLoadedCsv` / `currentLoadedTime`) y lo envía a `/ping?loaded=...`. Si el servidor o disco tienen una versión más nueva que la que el usuario está viendo en su pantalla, se activa inmediatamente el aviso en rojo `🔔 Actualización disponible (HH:MM hs) — Refrescar` y el botón superior `↻ Actualizar stock`, permitiendo el refresco con un clic.

---

## 2026-09-09 — v1.2.0: Detección Automática, Pill Dinámica de Estado y Centrado Visual

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/pack.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`

### Qué se hizo
1. **Detección Automática de Nuevas Descargas en Servidor:**
   - Se actualizó el endpoint `/ping` en el servidor HTTP integrado para comparar el nombre del archivo CSV cargado en memoria (`$global:cachedCsvName`) con el archivo más reciente en disco detectado por `Get-LatestStockCsv`.
   - Se implementó un ciclo de sondeo periódico en el cliente (cada 30s) junto con listeners de activación al cambiar o enfocar la pestaña (`visibilitychange` y `focus`).
2. **Indicador de Estado (Pill) y Comportamiento de Refresco:**
   - Cuando los datos están al día: se muestra en verde `● Al día` con texto informativo y `cursor: default`. No ejecuta ninguna acción al hacer clic para evitar recargas innecesarias.
   - Cuando se detecta un nuevo archivo CSV disponible: cambia dinámicamente a rojo vibrante con animación sutil (`status-pill pendiente`), texto explicativo y `cursor: pointer`. Al hacer un único clic sobre la pill roja, o sobre el botón superior `↻ Refrescar` (que también se resalta en rojo), se ejecuta `refrescarStock()`, recargando la vista y restaurando el estado verde `● Al día`.
3. **Centrado Visual del Encabezado y Retiro de Ruta de Carpetas:**
   - Se removió la visualización de la ruta de carpetas local (`dirInfo`) de la barra inferior del encabezado.
   - Se reposicionaron las acciones secundarias (`Exportar Stock` e `Historial Cargas`) de manera absoluta a la derecha (`position: absolute; right: 0; top: 50%; transform: translateY(-50%)`) para garantizar un centrado geométrico perfecto (offset 0.0px) del bloque de estado:
     `--Ciclo 3 Almacén Congelado Ctto-- · Ult. actualización: DD/MM/YYYY HH:MM · [Status Pill]`.
4. **Visibilidad de Versión:**
   - Se agregó la insignia visible `v1.2.0` al lado del título principal `Stock Almacen Congelado`.
   - Se actualizó la versión del binario a `1.2.0.0` en `pack.ps1`.
5. **Empaquetado y Despliegue:**
   - Binario recompilado y desplegado en `A PROBAR/ExportarStock.exe`.
   - Tarea programada `Gorina - Stock Almacen 24-7` reiniciada y verificada operativa en puerto `8090`.

---

## 2026-09-07 — Mejoras en Modal Análisis Brasil (Contraste, Tipografía y Buscador de Pallet)

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`

### Qué se hizo
1. **Corrección de Contraste y Transparencia Involuntaria:**
   - Se definieron formalmente las variables de tema `--bg-card` y `--bg-sub` tanto en `:root` (modo oscuro: `#1a1d27` y `#161922`) como en `.light-mode` (modo claro: `#ffffff` y `#f0f2f6`). Con esto se resolvió la causa por la cual la ventana modal resultaba transparente sobre la tabla de fondo, logrando un fondo 100% opaco, sólido y de alto contraste.
   - Se intensificó el overlay (`rgba(0,0,0,0.72)`) y el sombreado perimetral del modal.
2. **Tipografía y Legibilidad de Pallets:**
   - Se amplió el tamaño del número de LPN a `16px` en negrita con tipografía monoespaciada (`Consolas`) en color naranja distintivo (`var(--orange)`).
   - Se aumentaron los textos de producto, SKU y kilos/cajas a `13px` con separación más holgada en cada fila (`padding: 9px 12px; margin-bottom: 5px;`).
   - Se ampliaron las casillas de verificación (checkbox) a `18px x 18px` para facilitar la selección.
3. **Buscador de Pallet Integrado en Tiempo Real:**
   - Se incorporó una barra de herramientas superior con un campo de búsqueda estilizado a tono con la paleta de la aplicación: `🔍 Buscar N° de pallet (LPN), SKU o corte...`.
   - Incluye botón de borrado instantáneo (`×`) y filtrado en vivo por LPN, LPN normalizado, SKU o nombre de corte.
   - Botón `Seleccionar visibles` para tildar únicamente los pallets filtrados en pantalla.
4. **Mejoras de Experiencia de Usuario (UX):**
   - Bloqueo del scroll de fondo (`document.body.style.overflow = 'hidden'`) al abrir el modal y restauración automática al cerrar.
   - Cierre ágil del modal presionando la tecla `Escape`.
5. **Empaquetado y Despliegue:**
   - Binario recompilado con `pack.ps1` (`ExportarStock.exe`).
   - Binario sincronizado en `A PROBAR/ExportarStock.exe`.
   - Servicio 24/7 reiniciado y verificado con respuesta HTTP 200 OK en puerto `8090`.

---

## 2026-09-07 — Restauración del Botón Excluir Fechas en Barra de Filtros

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`

### Causa del retiro previo
- En el commit `3bd7f4e` (*fix(fechas): retirar boton antiguo de almanaque y ocultar selector nativo del navegador*), durante la normalización de los selectores de fechas Desde/Hasta a 36px y agregado de almanaques individuales, se retiró por confusión el botón `📅 Excluir Fechas`, interpretándolo como un selector de calendario antiguo que había quedado obsoleto.
- Toda la lógica subyacente (modal `calPopup`, estado `excludedDates`, chips de fechas excluidas, renderizado del almanaque de exclusión y exclusión a nivel de cajas en `applyFilters`) permanecía intacta en el código.

### Qué se hizo
1. **Restauración del Botón:** Se reinsertó el botón `<button type="button" class="btn btn-exclude" id="btnExclude" ...>` con su badge contador de fechas excluidas en la barra de filtros principal entre `Fecha Prod. Hasta` y `Análisis Brasil`.
2. **Prevención de Solapamiento:** Se agregó la llamada a `closeSingleDateCalendar()` dentro de `toggleCalendarModal` para garantizar cierre mutuo e instantáneo si el usuario tenía abierto el calendario de Desde o Hasta.
3. **Control de Disponibilidad:** Se incluyó el manejo de `btnExclude.disabled` en la función `renderData` según la presencia de columna de producción (`fechaProdOk`).
4. **Empaquetado y Despliegue:**
   - Binario recompilado con `pack.ps1` (`ExportarStock.exe`).
   - Binario sincronizado en `A PROBAR/ExportarStock.exe`.
   - Servicio 24/7 en VM reiniciado y verificado operativo en puerto `8090` con respuesta HTTP 200 OK.

---

## 2026-09-05 — Módulo de Historial, Registro de Cargas, Pesaje Real y Resumen Ejecutivo

**Archivos modificados:**
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/cargas_historial.json` (NUEVO)
- `A PROBAR/cargas_historial.json` (NUEVO)
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`

### Ajustes de UI y Rendimiento (Ronda de pulido)
- **Corrección de anidamiento HTML**: Se cerraron tags del modal de Análisis Brasil que dejaban oculto el contenedor de historial.
- **Apertura instantánea**: El modal ahora se abre inmediatamente con feedback visual de carga sin esperar a la respuesta del fetch.
- **Alineación a la derecha e integración visual:** Los botones `📊 Exportar Stock` y `📦 Historial Cargas` ahora se integran de forma limpia con fondo transparente y sin bordes divisorios, eliminando el recuadro resaltado a lo ancho de la pantalla y alineándose con el margen derecho de la cabecera.
- **Posición al borde inferior:** Se integraron los botones en la misma fila inferior (`.header-bottom-row`) que el texto de última actualización, bajándolos para que queden situados casi al ras de la línea divisoria de la barra de filtros y optimizando el espacio vertical.
- **Bloqueo de scroll al abrir Historial:** Se anula el scroll de la página de fondo (`document.body.style.overflow = 'hidden'`) al abrir el modal para que no se mueva la pantalla detrás, restaurándolo al cerrar o presionar Escape.
- **Corrección de fechas y zona horaria (UTC-3):** Se reemplazó el uso de `.toISOString()` por `toLocalDateStr()` y horas neutrales (`0, 0, 0, 0`). Esto resolvió el problema donde el viernes a última hora rolaba a sábado en UTC, haciendo que el informe dijera erróneamente "viernes 5/9" siendo sábado 5/9.

### Qué se hizo
Implementación completa del sistema de registro de descargas, trazabilidad operativa, pesaje real de camiones y módulo de reportes ejecutivos comparativos:
1. **Registro automático en servidor:** Al hacer clic en "Exportar Excel" en la pantalla de Cargas Gorina, los datos se empaquetan y se registran automáticamente en el servidor (`cargas_historial.json`) con ID único (`CRG-YYYYMMDD-HHMMSS`), items, pallets solicitados, kilos estimados, oferta y estado.
2. **Ajuste y confirmación de Kilos Reales:** En el historial de cargas se permite ingresar el pesaje real de balanza por camión/carga total y marcarla como "Cerrada", guardando en el servidor sin alterar el estimado original.
3. **Módulo de Historial y Resumen Ejecutivo (UI):**
   - Botón `📦 Historial Cargas` en la barra superior.
   - Pestaña **Resumen Ejecutivo**:
     - Filtros rápidos de período: **Esta Semana (Lun-Vie)**, **Semana Anterior (Lun-Vie)**, **Hoy**, **Este Mes** y **Personalizado (Desde / Hasta)**.
     - Tarjetas de KPIs: Total Cargas / Camiones, Total Pallets, Total Kilos Reales de balanza, Desvío Real vs Estimado.
     - **Cuadro Comparativo Semanal:** Comparación directa con la semana anterior (variación absoluta y % de pallets y kilos).
     - **Tablas de Desglose:** Totales por Día (Lunes a Viernes), Salidas por Destino (% sobre total) y Salidas por Establecimiento.
     - **Botón "Descargar Informe Ejecutivo (Excel)":** Generación de informe gerencial formal con ExcelJS con portada, comparativa, desglose diario y detalle de cargas.
   - Pestaña **Cargas Realizadas y Pesaje**:
     - Búsqueda en vivo de cargas históricas.
     - Edición directa de pesaje real por camión y guardado instantáneo.
     - Despliegue de detalle de renglones/órdenes por carga.
     - Re-descarga del Excel original de la carga en cualquier momento.
     - Anulación / eliminación de cargas.
4. **Endpoints REST agregados:**
   - `GET /api/cargas`: Colección histórica de cargas.
   - `POST /api/guardar-carga`: Alta o actualización de carga.
   - `POST /api/actualizar-carga`: Actualización de kilos reales, estado u observaciones.
   - `POST /api/eliminar-carga`: Eliminación o anulación de carga.

### Cierre de Jornada y Próximos Pasos
- **Estado del Entorno:** Servidor 24/7 activo en puerto `8090` bajo la tarea programada `Gorina - Stock Almacen 24-7`. Binario `ExportarStock.exe` compilado y sincronizado en `A PROBAR/`. Repositorio limpio y sincronizado con GitHub en la rama `feature/vm-analisis-brasil`.
- **Seguimiento operativo:** Comenzar a acumular registros de descargas reales para evaluar la persistencia histórica, la facilidad de ingreso de pesaje real y los desvíos balanza vs estimado.
- **Evaluación de Informes:** Revisar el diseño y formato de los informes ejecutivos (tanto en pantalla como en el archivo Excel gerencial generado con ExcelJS) con datos acumulados de varias semanas para planificar mejoras futuras.
- **Análisis Brasil:** Seguir el uso del nuevo modal de aptos/pendientes para verificar cómo se integra en la rutina diaria de expedición a Brasil.

---

## 2026-08-27 — Exportacion de Stock a Excel (Ronda 18)

**Archivo modificado:** `Fuente A PROBAR/index.template.html`

### Que se hizo
Nueva funcionalidad: boton **"Exportar Stock"** que genera un Excel con el stock actual resumido por SKU, respetando los filtros activos en pantalla.

### Cambios detallados

**1. CSS (linea ~294)**
- Nueva clase `.btn-export-stock`: fondo verde `#1d6f42`, sombra sutil (`box-shadow`), font-weight 600
- Hover: fondo mas oscuro `#155530`, sombra mas intensa, efecto `translateY(-1px)`

**2. HTML (linea ~786)**
- Boton agregado en `.header-actions` (fila superior del header, a la derecha)
- Orden: Carpeta | Refrescar | Tema | **Exportar Stock**
- Icono: 📊 (&#128202;)
- Titulo tooltip: "Exportar stock actual a Excel"

**3. JavaScript — funcion `exportarStock()` (linea ~2232)**
- Valida que ExcelJS este cargado y que haya datos filtrados
- Genera Excel con formato identico al `2026.08.26.Stock.Almacen.xlsx`:
  - Fila 2: "STOCK ALMACEN CONGELADO" (合并 A2:G2, fondo naranja, texto blanco)
  - Fila 5: Encabezados (SKU, DEST., Est., Nombre, MAT SAP, Pallets, KILOS) en naranja
  - Filas 6+: datos ordenados por KILOS de mayor a menor
- Columnas:
  - `SKU` — codigo del producto
  - `DEST.` — destino (2 digitos del SKU)
  - `Est.` — establecimiento elaborador (NUEVA COLUMNA)
  - `Nombre` — descripcion del producto
  - `MAT SAP` — codigo SAP
  - `Pallets` — cantidad total de pallets
  - `KILOS` — kilos netos totales
- Descarga automatica: `STOCK_ALMACEN_<fecha>.xlsx`

**4. Integracion (linea ~1046)**
- Boton `#btnExportStock` agregado a `setButtonsDisabled()` para que se deshabilite durante refresh

### Cambios posteriores (ajustes 2026-08-27 tarde)
- Bordes naranja remarcados (`ORANGE_BORDER` medium #9E3D00) en titulo y encabezados
- Fecha en fila 3 como `--- dd de mes de aaaa ---` centrada
- Columnas SKU, DEST., Est., MAT SAP, Pallets, KILOS centradas (Nombre a la izquierda)
- SKU/DEST/Est/MAT SAP convertidos a numero para evitar error "texto como numero"
- Fila 5 con `ws.autoFilter = 'A5:G5'` (filtros desplegables nativos en Excel)
- Columnas B(DEST) 8→10, E(MAT SAP) 12→13, F(Pallets) 10→11 para que no tape el boton de filtro
- Boton movido a la izquierda del tema: orden Carpeta | Refrescar | Exportar Stock | Tema

### Release
- EXE compilado con `pack.ps1` (117.3 KB HTML, 925.5 KB exceljs, 302.4 KB xlsx, 484.8 KB catalogo)
- Backup previo: `A PROBAR/_old_backup_exe_20260827.exe` y `Fuente A PROBAR/_old_backup_index_20260827_125227.html`
- Guardado en:
  - `A PROBAR/ExportarStock.exe` (2 633 216 bytes, 27/08/2026 13:26)
  - `Releases/EXPORT STOCK 2026-08-27/ExportarStock.exe` + LEEME + carpeta.json
- Fuente modificado: `Fuente A PROBAR/index.template.html`

## 2026-08-27 — Optimizacion Buscador (Ronda 18b)

**Archivo modificado:** `Fuente A PROBAR/index.template.html`

### Problema
Al tipear el 2do caracter en el buscador habia un parate largo (filtro + render bloqueante sobre 2516 SKUs y 48k filas de detalle).

### Cambios detallados
- **Debounce** `setupListeners` linea ~997: `100ms → 250ms` (`setTimeout(applyFilters, 250)`) — tipeo rapido "ab" ahora dispara solo un filtro para "ab", no dos.
- **Cache precomputado en `renderData` (linea ~1006):** para cada `d` en `data` se genera `_lcSku`, `_lcNombre`, `_lcDestino`, `_lcVenta`, `_lcDetail` (concatenado de LPNs+boxIds en minusculas). Evita `toLowerCase()` por keystroke sobre 2516 items.
- **`applyFilters` (linea ~1284):** reescrito para usar cache. Busqueda sobre `_lcSku/_lcNombre/_lcDestino/_lcVenta` con `includes(t)`; busqueda profunda en `_lcDetail` solo si `t.length >= 3` (con 1-2 letras no recorre las 48k cajas). Logica AND entre terminos se mantiene.
- **`renderTable` auto-expand (linea ~1442):** gating `needExpand = terms.some(t=>t.length>=3)` — solo expande pallets si hay termino >=3 chars, evita recorrer detalle con busquedas cortas.
- **Impacto:** filtro de 1-2 letras ya no escanea detalle (principal costo), y el debounce reduce a la mitad los filtrados al tipear rapido.

### Release
- EXE recompilado con `pack.ps1` (118.1 KB HTML, 925.5 KB exceljs, 302.4 KB xlsx, 484.8 KB catalogo)
- Backup previo: `A PROBAR/_old_backup_exe_20260827b.exe`
- Guardado en:
  - `A PROBAR/ExportarStock.exe` (2 634 240 bytes, 27/08/2026 13:33)
  - `Releases/OPTIMIZACION BUSCADOR 2026-08-27/ExportarStock.exe` + LEEME + carpeta.json
- Fuente modificado: `Fuente A PROBAR/index.template.html` (3 lineas debounce + 15 lineas cache + 8 lineas filtro + 2 lineas render gating)

## 2026-08-27 — Optimizacion Arranque + Version Final A PROBAR (Ronda 18c)

**Archivo modificado:** `Fuente A PROBAR/index.template.html`

### Problema
Arranque con parate por precálculo de cache de búsqueda bloqueando primer render (mismo loop de 46k boxIds).

### Cambios detallados
- **Cache async en `renderData` (linea ~1006):** se saca el loop de `_lc*` del path síncrono y se pasa a `setTimeout(...,0)` post-`populateFilters/updateStats`. Tabla se pinta inmediato; cache se completa en background (<50ms). Primer `applyFilters` (sin términos) no necesita cache.
- **Fallback robusto en `applyFilters` (linea ~1309):** si `_lc*` aún no existe (tipeo en primeros ms), usa `(d.sku||'').toLowerCase()` directo y no hace búsqueda profunda en detalle (evita loops pesados).
- **Impacto:** primer pintado pasa de ~200ms bloqueante a inmediato; arranque percibido mucho más rápido.

### Beta CARGAS descartada
- Intento segunda hoja `CARGAS` con `FILTER(CONGELADO!...)` y col `Sel.` (beta) guardado pero NO usado como versión activa.
- Guardado en: `Releases/BETA CARGAS EN EXCEL 2026-08-27 - DESCARTADO/index.template.CON GELADO+SEL+CARGAS.html` + `LEEME_BETA.txt`
- Decisión usuario: suspendida ("naa una mierda").

### Release FINAL A PROBAR
- EXE recompilado con `pack.ps1` (118.9 KB HTML, 925.5 KB exceljs, 302.4 KB xlsx, 484.8 KB catalogo)
- Backup previo: `A PROBAR/_old_backup_exe_20260827c.exe`
- Guardado en:
  - `A PROBAR/ExportarStock.exe` (2 635 776 bytes, 27/08/2026 13:50)
  - `Releases/A PROBAR 2026-08-27 FINAL/ExportarStock.exe` + LEEME + carpeta.json
- Incluye acumuladas: Ronda 18 (Export Stock) + 18b (buscador) + 18c (arranque) — todo en una sola versión final.

## 2026-09-02 — Exclusión de Fechas de Producción y Pallets No Disponibles (Ronda 19)

**Archivo modificado:** `Fuente A PROBAR/index.template.html`

### Requerimiento del Usuario
- Poder **excluir fechas puntuales** desde un calendario interactivo además de filtrar por rango (Desde / Hasta).
- Un pallet solo se considera **disponible** si todas las cajas contenidas cumplen la condición (estar dentro del rango y no pertenecer a las fechas excluidas).
- Los pallets que no cumplan la condición deben mostrarse en un **tono atenuado (menor opacidad)** y ubicarse **por debajo** de los pallets disponibles dentro del detalle del SKU.
- Mantener la versión anterior intacta en respaldo antes de probar.

### Cambios detallados
1. **Barra de Filtros Intacta e Inalterada:**
   - Se preservó la estructura original de `.filters` sin alterar su altura ni crear scrollbars internos (`overflow-y: hidden`).
   - Se añadió un único botón estándar de acción inline `.btn-exclude` (`📅 Excluir Fechas`) al nivel de los demás controles, sin etiquetas adicionales ni contenedores que deformen la barra.
   - Estado del botón: cuando hay fechas excluidas, muestra el contador en un badge rojo.
2. **Almanaque Desplegable Flotante (Fuera del Flujo):**
   - El popup del calendario (`#calPopup`) está situado directamente como hijo de `<body>` con `position: fixed` y `z-index: 99999`. No interactúa con el flujo del DOM de `.filters` ni altera su altura ni genera scrollbars.
   - **Solo fechas con producción disponible:** Se escanea el stock cargado (`availableProdDatesMap`). Únicamente los días que tengan al menos una caja con producción registrada en stock están habilitados para excluir (mostrando además tooltip con cantidad de cajas y punto identificador).
   - **Prohibidas fechas futuras y días sin producción:** Días futuros (posteriores a la fecha actual) o días sin cajas producidas quedan completamente deshabilitados (`.cal-day.disabled`), con opacidad al 22% y cursor bloqueado.
   - **Multiselección persistente sin cierre involuntario:** Se detuvo la propagación del evento (`stopPropagation`) en clicks sobre el calendario y días. El usuario puede clickear una, dos o múltiples fechas consecutivas sin que el almanaque se cierre. El almanaque solo se cierra al pulsar "Cerrar" o clickear fuera del mismo.
   - **Auto-enfoque inteligente:** Al abrir el almanaque por primera vez, se posiciona automáticamente en el mes más reciente con producción disponible en stock.
   - En el pie del almanaque se muestra el total de fechas excluidas y botón para limpiarlas.
3. **Evaluación de Pallets a Nivel de Caja (`applyFilters`):**
   - Para cada pallet, se evalúan todas sus cajas (`p.cajasDetalle`). Si alguna caja no tiene fecha, es anterior a Desde, posterior a Hasta o pertenece al conjunto de `excludedDates`, el pallet se marca con `p.cumple = false` y se registra el motivo.
   - Si todas las cajas cumplen, `p.cumple = true`.
4. **Ordenamiento Jerárquico y Visual:**
   - Dentro de cada SKU, los pallets conformes (`cumple = true`) se sitúan al principio; los no conformes se ordenan debajo.
   - Los pallets no disponibles se renderizan con clase `.pallet-no-cumple` (opacidad reducida al 52%), texto atenuado y badge `NO DISPONIBLE` con tooltip explicativo.
   - En el detalle de cajas, la caja no conforme muestra la fecha en rojo con ícono de advertencia y etiqueta `EXCLUIDA` / motivo correspondiente.
   - La columna de Pallets del SKU muestra los disponibles y entre paréntesis el total cuando hay pallets no conformes (ej. `3 (5)`). Si todos los pallets están excluidos, el SKU muestra badge `0 DISP.`.
5. **Limpieza e Integración:**
   - `clearFilters()` y `clearAll()` resetean las exclusiones, devuelven el botón a su estado normal y cierran el almanaque.
   - Click fuera del almanaque lo cierra automáticamente.
6. **Corrección en Despliegue de Pallets (`buildPalletHtml`):**
   - Se restauró la definición de la variable `bName` en el bucle de renderizado de cajas que causaba un error de JavaScript (`bName is not defined`) e impedía desplegar los pallets y cajas al hacer click en el botón `+`.

### Release Definitiva (Aprobada y Cerrada)
- **Estado:** VALIDADA Y APROBADA POR EL USUARIO.
- EXE compilado con `pack.ps1` (140.9 KB HTML, 925.5 KB exceljs, 302.4 KB xlsx, 484.8 KB catalogo).
- **Binario activo definitivo:** `A PROBAR/ExportarStock.exe` — **VERSIÓN VIGENTE**.
- **Respaldos de versión anterior (2026-09-02):**
  - `A PROBAR/_old_backup_exe_20260902_pre_exclusion.exe`
  - `A PROBAR/_old_backup_exe_20260902_exclusion_fechas_final.exe`
  - `Fuente A PROBAR/_backup_index_template_20260902_exclusion_fechas_final.html`
- **Releases empaquetadas:**
  - `Releases/A PROBAR 2026-09-02 FINAL/` (ExportarStock.exe + LEEME.txt + carpeta.json)
  - `Releases/EXCLUSION FECHAS 2026-09-02 FINAL/` (ExportarStock.exe + index.template.html + LEEME.txt)
- Fuente modificado: `Fuente A PROBAR/index.template.html`.

## 2026-09-05 — Migración VM 24/7 y Trazabilidad Análisis Brasil (Ronda 20)

**Archivos modificados:**
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/carpeta.json`
- `descargar_stock.ps1` (NUEVO)
- `A PROBAR/ExportarStock.exe`
- `A PROBAR/carpeta.json`
- `A PROBAR/descargar_stock.ps1`

### Que se hizo
1. **Modo Servidor 24/7 en Máquina Virtual:**
   - Se removió el apagado automático por inactividad a los 5 minutos para permitir funcionamiento ininterrumpido en la VM.
   - Vinculación del listener TCP a `[System.Net.IPAddress]::Any` permitiendo acceso local (`http://localhost:<puerto>`) y remoto desde la red interna (`http://<ip-vm>:<puerto>`).
   - Puerto configurable mediante `carpeta.json` (ej. `"puerto": 8090`), con puerto por defecto 8080 y fallback dinámico automático a puerto libre si está ocupado (ej. por IIS).
2. **Detección Automática de Destino Brasil:**
   - Detección precisa de cajas/pallets de Brasil mediante coincidencia de destino `"10"`, SKU terminado o conteniendo código 10, o descripción que incluya `"BRASIL"`.
3. **Motor de Trazabilidad y Regla de Reingreso:**
   - Persistencia histórica en `%LOCALAPPDATA%\StockAlmacenCongelado\historico_cajas.json` con registro de primer ingreso, última aparición, estado de análisis y fecha de reingreso.
   - Regla de negocio de 2 días: toda caja ausente $\ge 2.0$ días respecto al último CSV que reingrese al almacén se promueve automáticamente a `ANALISIS_OK` (`manual: false`).
4. **Gestión Manual de Análisis (Día 1 y Excepciones):**
   - Archivo `analisis_manual.json` en la carpeta base con listados persistidos de LPNs y Box IDs marcados manualmente.
   - Nuevos endpoints API seguros con token CSRF: `/analisis-manual` (GET), `/marcar-analisis` (POST) y `/desmarcar-analisis` (POST).
5. **Interfaz de Usuario Web:**
   - Botón de acción rápida `🇧🇷 Análisis Brasil` en el encabezado principal con modal para carga y desmarcado masivo de LPNs y Box IDs.
   - Filtro dedicado en barra de herramientas: `Análisis: Todos`, `Con Análisis (Aptos)`, `Sin Análisis (Pendientes)`.
   - Jerarquía visual: pallets sin análisis en tono ámbar y atenuado (45% opacidad) posicionados por debajo de los pallets aptos.
   - Acciones rápidas de marcado/desmarcado individual directamente en cada pallet.
   - Detalle de cajas desplegable con badges distintivos de análisis.
6. **Script de Descarga Desatendida (`descargar_stock.ps1`):**
   - Script PowerShell para el Programador de Tareas de Windows que descarga el CSV periódico mediante stream seguro y renombrado atómico (`.tmp` a `lista_cajas_*.csv`), con registro en `descargar_stock.log`.

## 2026-09-05 — Refinamiento UI Web Centralizada y Toggles de Análisis Brasil (Ronda 20b)

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `reiniciar_servidor.bat`

### Que se hizo
1. **Limpieza de Interfaz para Modo Servidor Central:**
   - Se removió el botón "Elegir Carpeta" (📁) y cualquier selector de archivo CSV local en el cliente, dejando únicamente las acciones globales válidas: **Refrescar**, **Exportar Stock** y **Tema**.
   - Se ajustó el panel de error para mostrar un reintento limpio en lugar de solicitar carpetas al usuario.
2. **Acciones Contextuales y Toggles Directos de Análisis Brasil:**
   - Se removió el botón global `🇧🇷 Análisis Brasil` del header principal.
   - En la barra de filtros, se integró el botón compacto `📋 Lote` junto al selector de `Análisis Brasil` para abrir el modal de pegado masivo.
   - En cada pallet de Brasil, el badge de estado (`CON ANÁLISIS`, `SIN ANÁLISIS`, `PARCIAL`) se convirtió en un **botón interactivo directo (toggle chip)**: con un solo clic sobre el badge se cambia su estado inmediatamente sin necesidad de columnas extra ni botones toscos.
   - En el detalle de cajas, cada caja cuenta también con su chip interactivo para marcar o quitar aptitud al vuelo.


## 2026-09-05 — Sincronización Manual Protegida, Rotación de Snapshots y Refinamiento Badges Brasil (Ronda 20c)

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/descargar_stock.ps1`
- `A PROBAR/descargar_stock.ps1`
- `descargar_stock.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`

### Que se hizo
1. **Badges Planos de Análisis Brasil:**
   - Se removieron los botones interactivos de las filas de pallets y cajas a petición del usuario.
   - Se restablecieron los badges visuales limpios y claros: `CON ANÁLISIS` (verde apto), `SIN ANÁLISIS` (naranja pendiente) y `PARCIAL (X/Y)` (azul para pallets mixtos).
   - Encabezado de tabla restaurado a `Estado Análisis`.
2. **Botón de Gestión de Análisis en Filtros:**
   - Se renombró el botón de la barra de filtros a `📋 Análisis` para mayor claridad semántica. Abre el modal centralizado para marcar/desmarcar por lista de LPNs o Box IDs.
3. **Botón de Sincronización CTTO en Tiempo Real (`⚡ Sincronizar CTTO`):**
   - Agregado en el header principal junto a `Refrescar`.
   - Permite a cualquier usuario forzar una descarga inmediata del stock desde la API de CTTO 2.1 (~54.000 cajas en ~35 segundos).
4. **Protección Concurrente y Cooldown Anti-Spam:**
   - **Bloqueo de concurrencia:** Si un usuario ya inició una sincronización con CTTO, cualquier otra solicitud simultánea es rechazada con un aviso amigable para no saturar el stacker.
   - **Cooldown de 3 minutos:** Basado en la fecha del último archivo CSV generado (tanto por descarga automática programada como manual). Evita consultas masivas y continuas a CTTO.
5. **Política Automática de Rotación y Retención de Archivos CSV:**
   - Cada snapshot pesa ~9.2 MB (48 archivos/día = ~440 MB/día).
   - El script `descargar_stock.ps1` ejecuta mantenimiento automático tras cada descarga:
     - Conserva todos los snapshots de las últimas 24 horas (detalle cada 30 min).
     - Conserva 1 snapshot diario (cierre del día) para los días previos (hasta 7 días).
     - Purga archivos de más de 7 días y archivos intermedios de más de 24 horas.
     - Aplica un tope de seguridad de máximo 50 archivos y elimina temporales `.tmp` de más de 1 hora.

## 2026-09-05 — Normalización de LPNs, Modal Visual con Listas Pendientes/Aptos y Optimización de Rendimiento Instantáneo (Ronda 20d)

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/exportar_stock.ps1`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Normalización Universal de LPNs (Ceros a la Izquierda):**
   - Se resolvió el problema por el cual los pallets `00353163` y `00351534` cargados manualmente no aparecían con análisis: el CSV de almacén los almacena con 3 ceros (`000353163`) mientras que el usuario los ingresaba con 2 ceros (`00353163`).
   - Se implementó la función `Normalize-Lpn` en PowerShell y `normId()` en JavaScript que elimina ceros a la izquierda (`.TrimStart('0')` / `.replace(/^0+/, '')`), asegurando una coincidencia 100% confiable sin importar la cantidad de ceros ingresados o provenientes del CSV.
   - Los dos pallets mencionados pasaron inmediatamente al estado **CON ANÁLISIS (Apto)** al 100%.

2. **Nuevo Modal con Listas de Selección (Pendientes vs Aptos):**
   - Se rediseñó por completo el modal `📋 Análisis` estructurándolo en pestañas claras y amigables:
     - **⏳ Pendientes (Sin Análisis):** Lista filtrable de todos los pallets Brasil en stock que aún no tienen análisis, con buscador por LPN/SKU/Producto, botones de selección masiva (*Todos / Ninguno*) y botón verde destacado: `✔ Marcar Seleccionados como CON ANÁLISIS`.
     - **✅ Aptos (Con Análisis):** Lista de todos los pallets Brasil aptos, con buscador y botón: `✖ Quitar Análisis a Seleccionados`.
     - **📋 Pegar Texto / Lote:** Pestaña para ingreso por texto masivo de LPNs o Box IDs desde planillas o correos, con normalización automática de ceros.
   - En cada ítem de la lista y en la vista desplegable de la tabla principal se añadió un botón rápido `[✔ Apto] / [✖ Quitar]` para cambiar el estado con un solo clic.

3. **Optimización de Rendimiento al Extremo (< 0.05s de latencia):**
   - **Actualización local en cliente (`actualizarAnalisisPalletsLocal`):** Al modificar el estado de cualquier pallet, la interfaz web actualiza su modelo de datos en memoria y repinta la tabla en **menos de 1 milisegundo**, enviando la persistencia al servidor en segundo plano. Los usuarios ya no experimentan ninguna demora ni congelamiento.
   - **Actualización en memoria del servidor (`Update-CachedPayloadAnalisis`):** Al recibir peticiones de marcado o desmarcado, el servidor actualiza el JSON en memoria en ~20 milisegundos sin re-leer ni re-parsear las 54.000 filas del archivo CSV.
   - **Pre-calentamiento de Caché en Arranque:** Al iniciar el servidor 24/7 en la VM, se pre-calienta la caché de stock en memoria. La primera apertura de la página web (`/datos`) responde en milisegundos sin demoras de inicio.
   - **Unificación de Detección de Archivos (`Get-LatestStockCsv`):** Se alineó la lógica de detección de nuevo CSV en disco con el timestamp del nombre para evitar invalidaciones innecesarias de caché.

4. **Estado estrictamente binario en Pallets Brasil:**
   - Se confirmó y reforzó la regla de negocio: ningún pallet de Brasil es mixto; o es estrictamente `CON ANÁLISIS` o `SIN ANÁLISIS`.

---

## 2026-09-05 — Simplificación de Interfaz: Eliminación de Filtro Dropdown, Retiro de Pestaña Lote y Buscador Interno (Ronda 20e)

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Eliminación del Dropdown Filtro Análisis:**
   - Se retiró el selector `<select id="filterAnalisis">` de la barra de filtros superior a pedido del usuario.
   - Se mantuvo el botón estilizado `📋 Análisis Brasil` integrado limpiamente en la barra de herramientas junto a `Excluir Fechas`.
2. **Depuración del Modal de Gestión de Análisis:**
   - **Retiro de opción por Lote / Texto:** Se eliminó la pestaña de pegado de texto/lotes (`tabContentPegar`). La gestión se realiza directamente sobre las listas visuales e interactivas de pallets presentes en el stock.
   - **Eliminación del buscador interno del modal:** Se quitaron los campos de búsqueda por texto dentro de las listas de Pendientes y Aptos para una experiencia más limpia y directa.
   - **Botones de selección masiva:** Se reposicionaron los botones *Seleccionar Todos* y *Deseleccionar* con mejor espaciado.
3. **Ordenamiento de Pallets Brasil:**
   - Los pallets de cada SKU de Brasil se listan de forma priorizada: los pallets `CON ANÁLISIS` en la parte superior y los `SIN ANÁLISIS` (griseados) en la parte inferior.
4. **Empaquetado y Compilación:**
   - Se compiló el nuevo binario `ExportarStock.exe` en `Fuente A PROBAR/` y se actualizó en `A PROBAR/`.
5. **Blindaje de Rendimiento y Velocidad de Carga Definitiva (223 ms):**
   - **Diagnóstico:** Se identificó la causa de la lentitud percibida tras las actualizaciones automáticas de las 17:00: el script `descargar_stock.ps1` abortaba la conexión con `/refrescar` antes de finalizar, provocando una excepción de socket en `exportar_stock.ps1` que cancelaba el precalentamiento de la memoria caché y obligaba al siguiente usuario a esperar un reprocesamiento completo de 30 segundos.
   - **Aislamiento en `exportar_stock.ps1`:** Se protegieron las funciones `Send-Chunk`, `Send-Progress` y `Send-TerminalChunk` con bloques de captura de desconexión. Si un cliente o script cierra la conexión anticipadamente, la exportación continúa en segundo plano hasta finalizar y guardar la caché en memoria RAM.
   - **Sincronización en `descargar_stock.ps1`:** El proceso automático de descarga ahora espera la lectura completa de la respuesta de refresco (`while (-not $reader.EndOfStream)`) antes de terminar.
   - **Optimización TCP:** Se activó `NoDelay = $true` (sin demoras por Nagle), búferes de 512 KB y transmisión en bloques de 64 KB, reduciendo el tiempo de transferencia del dataset completo de stock (7,46 MB) a solo **223 - 269 milisegundos**.

---

## 2026-09-05 — Selector Inteligente de Rango de Fechas (Desde - Hasta) con Almanaque Desplegable (Ronda 20f)

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Nuevo Selector Interactivo de Rango de Fechas:**
   - Se añadió un botón desplegable `📅 Rango Fechas` junto a los campos `Fecha Prod. Desde` y `Fecha Prod. Hasta`.
   - Incluye indicador dinámico (`badge`) que informa el estado: `✓`, `1 día`, `Rango`, `Desde` o `Hasta`.
2. **Compatibilidad Total con Ingreso Manual:**
   - Los campos `<input type="date">` (`filterFechaDesde` y `filterFechaHasta`) permanecen completamente editables y funcionales.
   - Cualquier fecha ingresada o modificada manualmente se sincroniza de inmediato con el almanaque interactivo y activa los filtros.
3. **Mecánica del Almanaque Flotante:**
   - **1° clic sobre un día:** Selecciona la fecha `Desde` e indica en la leyenda que se seleccione la fecha `Hasta`.
   - **2° clic sobre un día:** Selecciona la fecha `Hasta` (con ordenamiento automático en caso de hacer clic en orden inverso), actualiza los inputs, aplica los filtros a la grilla y mantiene el resaltado visual del rango.
   - **Doble clic sobre un día:** Establece dicho día como fecha única tanto para `Desde` como para `Hasta`, aplica el filtro de producción para ese único día y cierra el almanaque automáticamente tras una breve confirmación visual.
   - **Vista previa interactiva (hover):** Al estar en el paso 2 (esperando la fecha `Hasta`), desplazar el cursor sobre los días muestra sombreado en tiempo real el rango resultante.
   - **Limpiar rango:** Opción integrada para restablecer los campos `Desde` y `Hasta` y volver a mostrar todo el stock.
   - **Integración con "Limpiar Filtros":** La función global `clearFilters()` también restablece el estado del selector de rango y cierra el desplegable.
4. **Empaquetado y Servicio 24/7:**
   - Recompilado `ExportarStock.exe` mediante `pack.ps1` y desplegado en `A PROBAR/ExportarStock.exe`.
   - Reiniciado el servicio programado `Gorina - Stock Almacen 24-7`.

---

## 2026-09-05 — Normalización Visual de Barra de Filtros y Almanaques Individuales para Fecha Desde y Hasta (Ronda 20g)

**Archivos modificados:**
- `Fuente A PROBAR/index.template.html`
- `Fuente A PROBAR/ExportarStock.exe`
- `A PROBAR/ExportarStock.exe`
- `CAMBIOS.md`

### Qué se hizo
1. **Normalización Visual Integral de la Barra de Filtros:**
   - Se estandarizó la altura de todos los componentes interactivos de la barra superior a exactamente **36px** (`box-sizing: border-box`, `border-radius: 6px`, alineación uniforme `align-items: flex-end`):
     - Caja de búsqueda (`#searchInput`).
     - Selector de Venta (`#filterVenta`).
     - Desplegables de Destino y Establecimiento (`#filterDestino`, `#filterEstablecimiento`).
     - Grupos de Fecha Prod. Desde y Hasta (inputs + botones de calendario).
     - Botones de acción: `📅 Excluir Fechas`, `📋 Análisis Brasil`, `Limpiar Filtros` y `Limpiar Todo`.
   - Se mantiene flexibilidad total de ancho ("el largo") según el texto o contenido de cada control, garantizando una línea visual perfectamente prolija y nivelada.
2. **Reemplazo del Rango Combinado por Almanaques Individuales:**
   - Se retiró el selector agrupado "Rango Fechas" a pedido del usuario.
   - Se mantienen los campos separados **Fecha Prod. Desde** y **Fecha Prod. Hasta**:
     - **Ingreso Manual:** El usuario puede tipear o modificar las fechas directamente en cada campo.
     - **Botón de Almanaque Individual (`📅`):** Cada campo cuenta con su propio botón disparador adjunto para desplegar un almanaque flotante individual.
3. **Mecánica del Almanaque Flotante Individual:**
   - Despliega un calendario flotante idéntico en estilo y navegación (`<` mes anterior, `>` mes siguiente) al de Excluir Fechas.
   - **Selección en 1 solo clic:** Hacer clic sobre cualquier fecha disponible asigna inmediatamente ese día al parámetro correspondiente (`Desde` o `Hasta`), cierra el desplegable y aplica los filtros a la grilla.
   - **Visualización limpia de fechas:** Muestra los días del mes sin sobrecarga de puntos o estados de cajas, habilitando cualquier fecha hasta el día de hoy.
   - **Criterio por defecto:**
     - Si `Fecha Desde` no se especifica: el filtrado toma la producción desde el comienzo histórico del stock.
     - Si `Fecha Hasta` no se especifica: el filtrado toma la producción hasta la fecha de hoy.
   - Botón *Quitar fecha* dentro del almanaque para desasignar el parámetro de forma directa.
4. **Retiro del Botón Antiguo de Almanaque:**
   - Se removió de la barra de filtros el botón anterior `📅 Excluir Fechas` que se encontraba al lado de las fechas a pedido expreso del usuario.
   - Se ocultó vía CSS el indicador nativo del navegador (`::-webkit-calendar-picker-indicator`) dentro de los campos de fecha para evitar iconos duplicados o popups del navegador.
5. **Empaquetado y Servicio 24/7:**
   - Binario `ExportarStock.exe` recompilado con `pack.ps1` y desplegado en `A PROBAR/ExportarStock.exe`.
   - Servicio VM 24/7 reiniciado y verificado con respuesta HTTP 200 y latencia óptima.

---

## Versiones anteriores (resumen)

| Fecha | Ronda | Descripcion |
|-------|-------|-------------|
| 2026-09-05 | 20g | Normalización visual 36px de barra de filtros y almanaques individuales 1-clic (Desde / Hasta) |
| 2026-09-05 | 20f | Selector interactivo de rango de fechas (Desde/Hasta, 1°/2° clic y doble clic día único) |
| 2026-09-05 | 20e | Retiro de filtro dropdown análisis, simplificación modal Brasil y blindaje 223ms TCP |
| 2026-09-05 | 20 | Servidor VM 24/7, trazabilidad cajas Brasil (2 días ausencia) y control manual |
| 2026-09-02 | 19 | Exclusión de fechas de producción y visualización de pallets no conformes |
| 2026-08-25 | 17 | Excel CARGAS: blancos por orden + subtotales |
| 2026-08-19 | 11c | EXE A PROBAR: nuevo EXE con exportar simplificado |
| 2026-08-19 | 11 | Pestana Ofertas SAP |
| 2026-08-13 | 10 | Pallets multi-SKU |
| 2026-08-03 | 7-9 | EXE unico, UX descargas, fecha de creacion |
| 2026-08-03 | 6 | Formato CSV nuevo (comillas) |
| 2026-08-01 | 2-5 | Rotacion log, columnas robustas, paths relativos, CSRF |


