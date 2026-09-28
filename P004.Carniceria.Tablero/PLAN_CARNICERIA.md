# Tablero Carnicería Gorina - Plan y Documentación Central

Documento principal de arquitectura, configuración y registro de cambios para el Tablero de Ventas de Carnicería Gorina.

---

## 1. Visión y Objetivo
Proveer un tablero analítico comercial accesible en la red interna de Frigorífico Gorina para monitorear ventas netas, kilos netos, precios promedio, evolución diaria/mensual, desglose por clientes, comprobantes y productos.

- **Ubicación local en VM:** `D:\PROYECTOS\P004.Carniceria.Tablero`
- **Hostname de la VM:** `FGLP53`
- **Puerto de servicio:** `8765`
- **URL oficial en red Gorina:** `http://FGLP53:8765/tablero_carniceria` (también disponible en la raíz `http://FGLP53:8765/`)
- **Base de Datos MySQL 8.0:** `P004.Carniceria.Tablero` en `127.0.0.1:3306` (tablas `ventas`, `cargas`, `estado`, `raw_ingest`, vista `vw_carniceria_resumen`).

---

## 2. Arquitectura de Componentes
1. **Frontend (`Tablero_Carniceria.html`):**
   - Interfaz en HTML5, CSS y JavaScript Vanilla.
   - Consume `/api/ventas` y `/api/estado` con compresión dinámica Gzip.
   - Filtros multidimensionales (fechas, clientes, familias, comprobantes).
2. **Servidor HTTP (`servidor.py`):**
   - `ThreadingHTTPServer` de Python (puerto 8765, modo solo lectura).
   - Servido en background sin ventanas interactivas vía `vigilante_carniceria.ps1`.
3. **Carga y ETL (`importador.py`):**
   - Carga inicial histórica (`CARNICERIA 2026.CSV`) procesada a SQLite (99.441 filas).
   - Ingesta diaria incremental nocturna (21:30) desde carpeta compartida (`J:\UTIL\USER\CARNI_VENTA` con fallback a `\\svr\d\UTIL\USER\CARNI_VENTA`).
   - Validación contra catálogo [Catalogo_Carniceria_Gorina.xlsx](file:///J:/UTIL/USER/CARNI_VENTA/Catalogo_Carniceria_Gorina.xlsx).
   - Respaldo automático comprimido en `respaldos/carniceria_YYYY-MM-DD.sqlite.gz` (retención de 14 días).
4. **Base de Datos (`datos/carniceria.sqlite`):**
   - Tablas `ventas`, `cargas`, `estado` con índice por fecha.

---

## 3. Automatización y Tareas del Sistema
- **Regla de Firewall:** `Tablero Carniceria Gorina (8765)` (TCP 8765 Inbound Permitido).
- **Tarea 24-7 (Servicio):** `Gorina - Carniceria Tablero 24-7`
  - Ejecuta: `C:\EGalli\Carniceria_Gorina\vigilante_carniceria.ps1`
  - Frecuencia: Al inicio de la VM y cada 5 minutos como watchdog de autorecuperación.
- **Tarea ETL Diario:** `Gorina - Carniceria Actualizacion Diaria`
  - Ejecuta: `C:\EGalli\Carniceria_Gorina\actualizar_diario.cmd`
  - Frecuencia: Diariamente a las 21:30 hs.

---

## 4. Registro de Cambios (Changelog)
- **2026-09-23 (v1.1.0 - Despliegue productivo y alta en red):**
  - Instalación de dependencia `openpyxl` 3.1.5.
  - Corrección de ruta HTML en `servidor.py` (`Tablero_Carniceria.html`).
  - Incorporación de visualización del hostname de la VM (`FGLP53`) en la consola/log del servidor.
  - Incorporación de resolución y fallback automático de unidad `J:` a ruta UNC `\\svr\d` en `importador.py`.
  - Ejecución exitosa de la carga inicial histórica (99.441 registros).
  - Apertura de puerto 8765 en Firewall de Windows.
  - Creación del script de watchdog `vigilante_carniceria.ps1`.
  - Configuración y alta de tareas programadas `Gorina - Carniceria Tablero 24-7` y `Gorina - Carniceria Actualizacion Diaria`.
  - Validación de entrega HTTP de interfaz y endpoints `/api/estado` y `/api/ventas`.
- **2026-09-23 (v1.2.0 - Enrutamiento amigable):**
  - Soporte para la ruta `/tablero_carniceria` y `/tablero_carniceria/`.
  - Soporte retrocompatible para `/` y endpoints de API bajo subruta.
- **2026-09-23 (v2.1.0 - Almanaque Corporativo Gorina y Rediseño de Botones):**
  - Reemplazo completo de los selectores HTML nativos `<input type="date">` por el **Almanaque Corporativo Gorina** (`.calpop`, `.calgrid`, cabecera de mes con navegación rápida `❮ ❯`, celdas de días con datos `.has`, rango visual `.in-range` y fechas de corte `.sel`).
  - Lógica interactiva en `filtros.js` (`toggleAlmanaque`, `renderAlmanaque`, `pickAlmanaqueDate`, `setAlmanaqueRange`, cierre por clic exterior).
  - Rediseño integral de botones diferenciado de Ciclo 3:
    - Selector de períodos en formato de **Chips Táctiles** (`.range-chip` con indicador puntual activo `::before`, bordes neutros y sombreado flotante).
    - Barra de navegación en **Contenedor Segmentado Flotante** (`.tabs-container` con pestañas tipo píldora `.tab`).
    - Botones de acción en cabecera (`.btn-header.primary` y `.btn-header.ghost`) y de paginación (`.btn-page`).
    - Botón de limpieza de filtros con microinteracción (`.btn-clear`).
- **2026-09-23 (v2.2.0 - KPI Cards Exclusivas, Almanaque en Barra Superior y Multi-Segmento Toggle):**
  - **Rediseño Exclusivo de Cuadros KPI:** Eliminación total de la barra superior sólida roja/verde de Ciclo 3. Creación de tarjetas ejecutivas con esquinas de 14px, sombras multicapa, etiquetas badge en cápsula (`.kpi-tag.rojo`, `.azul`, `.verde`, etc.), tipografía tabular y microinteracción hover.
  - **Reubicación del Almanaque:** Trasladado a la barra superior (`.quick-ranges-bar`), a la derecha de los chips rápidos, resolviendo el apiñamiento previo y dejando la grilla de filtros 100% simétrica y ordenada.
  - **Selección Dinámica Multi-Segmento con Toggle:**
    - Clic sobre barras de evolución mensual o sobre ítems de rankings (Grupos, Productos Expone, Clientes) selecciona el segmento y lo resalta (`.selected`, fondo rosado suave, borde rojo y tilde `✓`).
    - Un segundo clic sobre el mismo elemento lo deselecciona (toggle off).
    - Soporte de selección múltiple concurrente (ej. múltiples grupos o meses combinados).
    - Soporte en backend SQLite mediante cláusulas dinámicas `IN (...)` en `servidor.py`.
    - Las barras del gráfico mensual no seleccionadas se atenúan sutilmente (`.dimmed`, opacidad 0.35) para un fuerte contraste dinámico.
    - Píldoras individuales para cada valor activo con descarte individual por `×`.
- **2026-09-23 (v2.2.1 - Corrección SQL de Rankings y Nivelación de KPIs):**
  - **Corrección Crítica en `/api/ranking`:** Subsanado error de sintaxis SQL `near "WHERE"` producido por concatenación de doble `WHERE` cuando había filtros de fecha activos. Los paneles Top Grupos, Top Productos y Top Clientes ahora cargan de inmediato.
  - **Centrado y Nivelación de Cuadros KPI:**
    - Título (`.kpi-tag`), valor numérico (`.kpi-value`) y subtítulo (`.kpi-sub`) centrados horizontalmente en todas las tarjetas.
    - Altura uniforme garantizada (`min-height: 120px` en tarjeta, `min-height: 36px` en valores) manteniendo todos los números exactamente en la misma línea visual horizontal.
    - Variación Mensual rediseñada con el mismo tamaño y peso tipográfico (`24px`, peso 800) en color verde/rojo según el signo, eliminando el badge pequeño desalineado.
    - Subtítulos condensados a una sola línea con `white-space: nowrap; overflow: hidden; text-overflow: ellipsis;` impidiendo rupturas en dos renglones.
  - Verificación de servicio en `http://FGLP53:8765/tablero_carniceria` con respuesta 200 OK en todos los endpoints.
- **2026-09-23 (v2.3.1 - Preservación de Rankings en Toggle y Centrado Estricto con Cache-Busting):**
  - **Preservación de Opciones en Rankings (Foto 1 resuelta):** En `tablero.js`, cada panel de ranking (`grupo`, `cliente`, `expone`) y el gráfico de evolución mensual (`mes`) ahora realiza su consulta excluyendo su propia dimensión (`const fSinDim = { ...f, dim: [] }`). Esto permite que al hacer clic en un grupo (ej. "Medias Reses") **todos los demás grupos permanezcan activos y visibles en pantalla**, posibilitando la selección múltiple y deselección interactiva sin ocultar opciones.
  - **Centrado Estricto de KPIs y Cache-Busting (Foto 2 resuelta):**
    - Refuerzo de alineación en `estilos.css` con directivas `!important` en `.kpi`, `.kpi-tag`, `.kpi-value` y `.kpi-sub`.
    - Atributos inline de layout flex y centrado horizontal/vertical directo en el marcado HTML (`Tablero_Carniceria.html`).
    - Incorporación de control de versiones `?v=2.3.1` en hoja de estilos CSS y scripts JS (`api.js`, `graficos.js`, `filtros.js`, `tablero.js`) para invalidar inmediatamente la caché de navegadores en clientes de la red corporativa.
  - Verificación exitosa en `http://FGLP53:8765/tablero_carniceria` con 99.441 registros activos.
- **2026-09-23 (v2.4.0 - Optimización de Rendimiento, Fix de Gráfico y KPIs Sobrios):**
  - **Corrección de Gráfico y Rankings (Causa raíz identificada):** Se corrigió la firma de `renderEvolution` en `graficos.js` agregando el parámetro por defecto `selectedPeriods = []`, eliminando el `ReferenceError` que detenía la ejecución de JavaScript en tiempo de ejecución.
  - **Aceleración Extrema de Navegación (62ms vs 1.150ms):**
    - Creación de índices de cobertura en SQLite (`idx_ventas_cov_grupo`, `idx_ventas_cov_expone`, `idx_ventas_cov_cliente`, `idx_ventas_cov_kpis`).
    - Paralelización de todas las consultas asíncronas con `Promise.all` en `tablero.js`.
  - **Rediseño Sobrio de Tarjetas KPI y Nueva Tipografía:**
    - Eliminación de fondos y bordes de colores en las etiquetas de los KPIs (`.kpi-tag`), adoptando un estilo ejecutivo monocromático neutro en slate.
    - Valores numéricos en color carbón oscuro sobrio (`#0f172a`), eliminando saturación visual.
    - Adopción de tipografía moderna **Plus Jakarta Sans** con soporte de números tabulares (`tabular-nums`).
    - Cache-busting actualizado a `?v=2.4.0` en HTML, CSS y JS.
- **2026-09-23 (v2.4.1 - Fix de Ingesta Diaria, Auto-Invalidación de Caché y Carga de 2026-09-23):**
  - **Corrección de Ejecutable en `actualizar_diario.cmd`:** Se reemplazó la llamada a `py -3` (incompatible con tareas programadas sin sesión de usuario interactiva) por la ruta absoluta `C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe` con fallback a `python`, más logging con timestamp.
  - **Corrección de Conexión en `backup(db)` en `importador.py`:** Se aseguró el cierre explícito `dest.close()` antes de la compresión y eliminación del archivo temporal, evitando el error `WinError 32` (archivo en uso) en Windows.
  - **Auto-Invalidación de Caché en `servidor.py`:** El servidor ahora detecta automáticamente cambios en el `st_mtime` del archivo SQLite (`carniceria.sqlite`) y purga su memoria caché en caliente, reflejando inmediatamente las nuevas cargas sin necesidad de reinicios manuales.
  - **Ingesta Exitosa:** Procesado el archivo `20260923_210001.csv` con 244 renglones del día de hoy. Base de datos actualizada a 99.685 registros y fecha máxima 2026-09-23.
- **2026-09-23 (v2.5.0 - Vista Diaria/Mensual en Evolución y Auditoría Integral de Días Hábiles):**
  - **Conmutador de Granularidad [Mensual | Diario]:**
    - Agregado selector segmentado interactivo en la cabecera del gráfico de Evolución (`App.setGranularity`).
    - En vista **Diario**, muestra la curva día por día del mes/período seleccionado (barras rojas de $ neto y línea azul de kg) con tooltip detallado (Día de la semana y fecha).
    - En vista **Mensual**, agrupa a nivel mes histórico.
  - **Auditoría Automática de Ingesta (Lunes a Sábado vs Domingos/Feriados):**
    - Módulo en `servidor.py` (`/api/calidad`) que evalúa la cronología completa contra calendario oficial 2026 (feriados inamovibles y trasladables de Argentina).
    - Regla validada: Lunes a Sábado obligatorios con datos (salvo feriados), Domingos sin actividad comercial (0 registros requeridos).
    - Resultados auditados: **99.1% de cobertura de días hábiles** (215 días laborables con venta de 217 posibles, solo 2 días faltantes históricos `2026-06-08` y `2026-06-15`), 0 anomalías en domingos (100% cerrados), 10 feriados reconocidos.
    - Nuevo panel visual y tabla de control en la pestaña **Calidad de Datos**.
  - Cache-busting actualizado a `?v=2.5.0` en HTML, CSS y JS.
- **2026-09-24 (v2.6.0 - Exportación Excel/CSV, Ticket Promedio, Colores por Día de la Semana y Fix de Barra de Filtros):**
  - **Eliminación del Marquito/Hueco Superior en Filtros:** Se corrigió `.filters` de `position: sticky; top: 10px;` a `position: relative;`, eliminando el espacio transparente donde se transparentaba el contenido inferior al scrollear.
  - **Colores Identificatorios por Día de la Semana en Vista Diaria:**
    - Cada día cuenta con su color distintivo: Lunes (Índigo `#4f46e5`), Martes (Azul `#0284c7`), Miércoles (Esmeralda `#059669`), Jueves (Ámbar `#d97706`), Viernes (Frambuesa `#e11d48`), Sábado (Violeta `#7c3aed`) y Domingo (Gris `#64748b`).
    - Leyenda visual con píldoras de colores activa únicamente en modo diario.
    - Soporte interactivo de multi-selección y deselección (toggle) de días con resaltado y atenuación dinámica (`.dimmed`).
  - **Reemplazo de KPI "Clientes Únicos" por "Ticket Promedio":**
    - Cálculo matemático exacto: $\text{Ticket Promedio} = \frac{\text{Venta Neta}}{\text{Comprobantes}}$.
    - Etiqueta centrada y número formateado con moneda argentina `$ #.###`.
  - **Botón de Descarga Filtrada (Excel y CSV):**
    - Ubicado estratégicamente entre *Actualizar* e *Imprimir*.
    - Menú desplegable con 2 opciones: **[ Descargar en Excel (.xlsx) ]** con cabecera corporativa y formato de celdas, y **[ Descargar en CSV (.csv) ]** delimitado por punto y coma con UTF-8 BOM.
    - Exporta exactamente los registros que coinciden con los filtros aplicados en ese instante en pantalla.
  - **Identificador de Versión Visible:** Badge `v2.6.0` en la cabecera y pie de página del tablero.
  - Cache-busting actualizado a `?v=2.6.0` en HTML, CSS y JS.
- **2026-09-24 (v2.6.3 - Restauración de Filtros Sticky al Tope y Pestañas Centradas con Líneas):**
  - **Filtros Sticky al Tope (`top: 0`):** La barra de filtros avanzada recuperó su anclaje flotante permanente (`position: sticky; top: 0; z-index: 120;`), acompañando fluidamente el scroll vertical sin dejar huecos transparentes ni marcos desfasados por donde se vea el contenido inferior.
  - **Pestañas Centradas con Líneas Laterales:** La barra de navegación de pestañas (`Resumen General`, `Productos`, `Clientes`, etc.) ahora se encuentra centrada geométricamente en la hoja, enmarcada por líneas divisoras horizontales continuas (`.tabs-nav-wrapper` y `.tabs-line`), aportando simetría y jerarquía ejecutiva.
  - Actualización de cache-busting a `?v=2.6.3` en HTML, CSS y JS.
- **2026-09-27 (v2.7.0 - Corrección Integral de Filtros Agrupa y Apertura, Eliminación de Grupo Residual y Estandarización de Rutas):**
  - **Corrección de Mapeo de Origen (Catálogo Excel `Hoja2`):**
    - Se identificó y resolvió el desfasaje: la columna `Agrupa` del catálogo (familias amplias como *Costillar, Rueda, Menudencias*) estaba desplazada por la macro-categoría residual *Grupo*, y `Apertura` (*Asado Completo, Vacio, Asado Plancha*) se mostraba como "Expone".
    - Se reestructuró la barra de filtros con 6 selectores limpios: **Material / Producto**, **Agrupa** (8 familias), **Apertura** (47 cortes comerciales), **Tipo Venta**, **Comprobante** y **Cliente**.
  - **Rankings Top en Resumen General:**
    - Tarjeta 1: **Top Agrupa ($)** (multiselección y toggle sobre familias como Costillar, Rueda, etc.).
    - Tarjeta 2: **Top Apertura ($)** (multiselección y toggle sobre cortes como Asado Completo, Vacio, Asado Plancha).
    - Tarjeta 3: **Top Clientes ($)**.
  - **Sincronización en Backend (`servidor.py`):**
    - `/api/filtros` entrega `agrupas` y `aperturas` (con retrocompatibilidad).
    - `build_filter_clause` admite parámetro `apertura` mapeado a la columna `expone`.
    - `/api/ranking` soporta `dim=agrupa` y `dim=apertura`.
    - `/api/exportar` exporta con encabezado formal *Apertura*.
  - **Estandarización de Directorios de Datos:**
    - Erradicación y bloqueo de carpetas `dataGorina` en la raíz de los discos `C:\` y `D:\`.
    - Rutas de almacenamiento y logs centralizadas exclusivamente en `D:\GorinaData\P004.Carniceria.Tablero\`.
  - **Tablas y Vistas Actualizadas:**
    - Pestaña **Productos**: *Rendimiento por Desglose Comercial (Apertura)* con columna *Apertura Comercial*.
    - Pestaña **Drilldown Jerarquía**: *Grupo → Agrupa → Apertura*.
    - Pestañas **Detalle Paginado** y **Calidad de Datos**: columnas normalizadas a *Agrupa* y *Apertura*.
- **2026-09-27 (v2.7.6 - Ajuste Exacto de Grilla de Filtros a 6 Columnas y Textos de KPIs Fijos):**
  - **Alineación Estricta de Filtros con Tamaño Original:**
    - Fila 1 (4 columnas a la izquierda con ancho idéntico al original): `Material / Producto` (Col 1), `Agrupa` (Col 2), `Apertura` (Col 3), `Tipo Venta` (Col 4).
    - Fila 2 (únicamente 2 filtros movidos debajo): `Comprobante` (Col 3, debajo de Apertura), `Cliente` (Col 4, debajo de Tipo Venta).
    - Col 5 y Col 6: Botones KPI Fijos con altura equilibrada de 2 filas:
      - **Último Día** (importe neto y fecha).
      - **% Respecto al Mes** (porcentaje exacto sobre el mes en curso y nombre del mes).
  - Versionado y cache-busting elevado a `v2.7.6` (`?v=2.7.6`) en HTML, CSS y JS.
- **2026-09-27 (v2.7.8 - Soporte para 2 Renglones de Pastillas de Filtros, Alineación y Estado Clarito en Botón Limpiar):**
  - **Doble Renglón de Pastillas de Filtros:** El área de estado de filtros (`.pos-status`) ahora aprovecha los 55px de altura de la fila 2 para alojar hasta 2 renglones de pastillas de 22px (`flex-wrap: wrap; align-content: center;`), con scroll vertical sutil si se superan las 2 líneas.
  - **Alineación Elevada del Botón Limpiar:** Se aplicó `align-self: center;` al botón `Limpiar filtros`, elevándolo unos píxeles para centrarlo verticalmente con respecto a toda la segunda fila y alinearlo con el selector adyacente de *Comprobante*.
  - **Estado Atenuado/Clarito sin Filtros:** Cuando no existen filtros activos para limpiar, el botón adopta automáticamente una apariencia tenue y grisácea (`.is-empty` / `disabled`), activándose con su tono rojo corporativo en cuanto se selecciona cualquier filtro.
- **2026-09-28 (v2.7.10 - Ingesta y Recuperación de Registros Faltantes 21/09 a 26/09):**
  - **Procesamiento de Archivo de Faltantes (`D:\DOWNLOADS\Faltantes Carni.csv`):**
    - Se procesaron 391 filas totales; 94 coincidencias exactas existentes fueron omitidas para prevenir duplicados.
    - Se insertaron **297 nuevos registros comerciales** no ingresados previamente (2026-09-23: 66 filas, 2026-09-24: 56 filas, 2026-09-25: 101 filas, 2026-09-26: 74 filas).
    - Los registros fueron cruzados y clasificados contra el catálogo oficial (Agrupa, Apertura, IVA, Tipo Venta).
  - **Actualización de Base de Datos:**
    - Total acumulado de registros en `ventas` ascendió a **101.344**.
    - La tabla `cargas` fue sincronizada con los nuevos totales por fecha.
- **2026-09-28 (v2.8.1 - Disposición Vertical de Indicadores en Botones de KPIs):**
- **2026-09-28 (v2.8.2 - Corrección Integral de Variación Intermensual en Filtrados):**
  - **Causa Raíz Diagnosticada:** Cuando se aplicaban filtros temporales (rango de fechas `desde`/`hasta`, chip *Mes Actual*, o selección de un mes en el gráfico), la consulta SQL limitaba los registros a ese único mes. Al obtener un solo resultado (`len(meses) < 2`), el cálculo devolvía `None` y la tarjeta mostraba `— (Sin datos comparativos)`.
  - **Desacoplamiento de Filtros Temporales en `build_filter_clause`:** Se incorporó el parámetro `include_date=False` para extraer la cláusula de filtros dimensionales (Cliente, Agrupa, Apertura, Tipo de Venta, Material, Búsqueda libre).
  - **Cálculo Robusto de Variación:**
    - Identifica el mes objetivo seleccionado (o el último mes con datos).
    - Calcula la venta neta del mes objetivo y la del mes calendario inmediatamente anterior (`YYYY-MM - 1`) aplicando exactamente los mismos filtros dimensionales.
    - Devuelve el porcentaje de variación exacto y los meses comparados (`mes_anterior`, `ultimo_mes`).
  - **Visualización en Frontend:** Subtítulo dinámico `YYYY-MM vs YYYY-MM` en el pie de la tarjeta KPI.
  - Actualización de versión y cache-busting a `?v=2.8.2` en HTML y scripts JS.









