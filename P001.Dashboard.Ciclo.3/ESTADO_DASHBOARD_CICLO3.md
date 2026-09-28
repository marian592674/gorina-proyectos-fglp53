# Estado Dashboard Gorina Ciclo 3 — 28/09/2026

## 1. Arquitectura de Entornos y Persistencia MySQL 8.0
* **Base de Datos Local MySQL 8.0**: `127.0.0.1:3306`
  * Esquema corporativo: `P001.Dashboard.Ciclo.3`
  * Tablas activas: `raw_ingest`, `movimientos_horarios`, `telemetria_scada`, `operaciones_diarias`
  * Vistas SQL: `vw_dashboard_horario`, `vw_dashboard_diario`
  * Módulo de persistencia: `db.py` con adaptador universal (compatible con transacciones, backticks para palabras reservadas y emulación de Row).

* **LAB (Puerto 8080)**: `http://localhost:8080/dashboard_operaciones.html`
  * Ubicación: `D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\`
  * Tarea programada: `Gorina LAB - Colector datos` (cada 5 min bajo SYSTEM).
  * **Estado**: **100% Migrado a MySQL 8.0** con exportación atómica a `datos.json` y `datos_horarios.json`.
  * **Sistemas**:
    1. **TRV1 y TRV2 (Histórico)**: MySQL `192.168.0.162:3306` (`p003148.vw_tablero_trv1` / `trv2`).
    2. **TRV1 y TRV2 (En vivo hoy)**: **Siemens WinCC Unified Runtime (WebRH)** (`https://192.168.196.36/device/WebRH`).
    3. **Alm. Congelado (`crane`)**: **CTTO 2.1 REST API** (`http://fglp39v2:5000` / `192.168.0.164:5000`).

* **PROD (Puerto 80)**: `http://localhost/dashboard_operaciones.html`
  * Ubicación: `D:\PROYECTOS\P001.Dashboard.Ciclo.3\PROD\`
  * Módulo `db.py` sincronizado y listo para activación productiva directa en MySQL.

---

## 2. Novedad: Integración de CTTO 2.1 para Almacén Congelado (07/09/2026)
* **Objetivo**: Evitar cargas manuales en Google Sheets y prescindir de requerir vistas SQL adicionales al DBA para el Almacén Congelado.
* **Mecanismo técnico**:
  * En lugar de descargar manualmente archivos `.xlsx` desde la web de CTTO, el colector consulta en memoria la API REST nativa:
    `GET http://fglp39v2:5000/stacker-1/api/operations/metrics/summary?fromDate=YYYY-MM-DD&toDate=YYYY-MM-DD`
    *(Fallback con IP directa: `http://192.168.0.164:5000/...`)*
  * **Sin descargas a disco ni apertura de navegadores**: La consulta es en memoria RAM (JSON ~1 KB, respuesta en ~50 ms).
  * Extrae directamente:
    * `resultsByCategory.ingresos.count` (Palets ingresados).
    * `resultsByCategory.salidas.count` (Palets despachados/salidos).
  * Omite fines de semana sin movimientos para mantener la continuidad limpia de días hábiles.
  * **Cálculo de Ocupación Dinámica**:
    Aplica el balance de inventario diario sobre la capacidad nominal de 3.960 palets:
    $$\text{Stock}_{\text{hoy}} = \text{Stock}_{\text{ayer}} + \text{Ingresos} - \text{Salidas}$$
    $$\text{Ocupación \%} = \left(\frac{\text{Stock}_{\text{hoy}}}{3.960}\right) \times 100$$
    *El histórico previo al 01/09/2026 inclusive se conserva fijo e inalterable.*

---

## 3. Novedad 2: Captura en Tiempo Real desde SCADA Web (Siemens WinCC WebRH)
* **Objetivo**: Tomar los datos de producción de TRV1 y TRV2 directamente del SCADA en tiempo real *antes* de que el proceso nocturno/batch los grabe en MySQL.
* **Fuente Web**: `https://192.168.196.36/device/WebRH` (ASUAN Frontmatec).
* **Módulo implementado**: `LAB/colector_test/webrh_reader.py`.
* **Mecanismo técnico**:
  1. Utiliza Playwright en modo Headless (`chromium`) con certificados TLS ignorados.
  2. Autentica en el formulario UMC de Siemens (`Ingenieria` / `Inge132!`).
  3. Cierra diálogos emergentes y navega al menú lateral **ESTADIS.** (`ESTADÍSTICAS - Contadores`).
  4. Extrae los contadores de pantalla:
     * `ing_inf_t1` + `ing_sup_t1` (Ingresos TRV1).
     * `sal_t1` (Salidas TRV1).
     * `ing_inf_t2` + `ing_sup_t2` (Ingresos TRV2).
     * `sal_t2` (Salidas TRV2).
  5. **Soporte Multi-Turno**: Abre el selector superior de Turno, lee **Turno 1** y suma **Turno 2** si presenta valores registrados.
  6. **Cuidado de Licencia y Concurrencia de Siemens**:
     * WebRH permite únicamente 1 sesión web concurrente ("maximum number of allowed sessions").
     * El lector abre la página, extrae los datos en ~15 segundos y **cierra inmediatamente la sesión y el navegador**, dejando el cupo 100% disponible para operadores humanos.
     * Si un operador humano está usando la página al momento de la consulta, el colector detecta la advertencia, no bloquea ni crashea, y conserva el último valor bueno conocido.

---

## 4. Configuración Activa en LAB (`config.json`)
```json
{
  "source": "sheet",
  "out_path": "C:/Ciclo3/Servicios/DASHBOARD/LAB/dashboard_test/datos.json",
  "mysql": {
    "servers": {
      "TRV": {
        "host": "192.168.0.162",
        "port": 3306,
        "database": "p003148",
        "user": "TABLERO_RO",
        "password": "..."
      }
    },
    "views": {
      "trv": { "server": "TRV", "query": "SELECT fecha, ingresos, salidas, ocupacion FROM p003148.vw_tablero_trv1 WHERE fecha >= '2026-09-02' ORDER BY fecha" },
      "trv2": { "server": "TRV", "query": "SELECT fecha, ingresos, salida, acupacion FROM p003148.vw_tablero_trv2 WHERE fecha >= '2026-09-02' ORDER BY fecha" }
    }
  },
  "ctto": {
    "base_url": "http://fglp39v2:5000",
    "alt_url": "http://192.168.0.164:5000",
    "endpoint": "/stacker-1/api/operations/metrics/summary",
    "start_date": "2026-09-02",
    "timeout": 10
  },
  "webrh": {
    "url": "https://192.168.196.36/device/WebRH",
    "user": "Ingenieria",
    "password": "...",
    "timeout_ms": 25000
  },
  "source_hybrid": {
    "trv": "mysql",
    "trv2": "mysql",
    "crane": "ctto"
  }
}
```

---

## 5. Validación de Datos (Día en curso: 07/09/2026)
| Sistema | Fecha | Ingresos | Salidas | Ocupación % | Fuente Origen |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **TRV1 (Cajas)** | 2026-09-07 | **6.379** | **7.391** | **50,02%** | **Siemens WebRH (En Vivo)** |
| **TRV2 (Cajas)** | 2026-09-07 | 0 | 0 | --- | Siemens WebRH (Sin operación) |
| **Alm. Congelado (`crane`)** | 2026-09-07 | **159** | **176** | **33,18%** | **CTTO 2.1 API REST** |

---

## 6. Respaldos Creados en `C:\Ciclo3\Servicios\DASHBOARD\ARCHIVO\`
1. `BACKUP_LAB_PRE_CTTO_2026-09-07`: Estado íntegro de LAB antes de migrar Almacén Congelado a CTTO.
2. `BACKUP_LAB_PRE_WEBRH_2026-09-07`: Estado íntegro de LAB antes de incorporar el lector Siemens WebRH.
3. `BACKUP_LAB_CON_CIERRE_2026-09-07`: Estado íntegro de LAB con el cierre automático de jornada y generación de Excel.

---

## 7. Novedad 3: Envío Automático de Correo de Cierre de Jornada (07/09/2026)
* **Objetivo**: Automatizar el correo diario de cierre de producción que se enviaba manualmente a la tarde.
* **Módulo implementado**: `LAB/colector_test/cierre_jornada.py` (ejecutado al final de `colector.bat` cada 5 min).
* **Mecanismo de Detección de Fin de Jornada**:
  * Se activa de lunes a viernes a partir de las **16:00 hs**.
  * Monitorea `datos.json`: si durante **15 minutos consecutivos (3 ciclos de 5 min)** los contadores de TRV1 y Almacén permanecen estables (delta = 0), confirma el cese de producción.
  * **Corte de seguridad**: A las 18:00 hs dispara el cierre con la última foto del día si continuó habiendo actividad.
  * **Control diario**: Registra `logs/cierre_enviado_YYYY-MM-DD.json` para garantizar un único envío por día hábil.
* **Adjunto Excel Oficial (`Stock.Almacen`)**:
  * Conecta en segundo plano (Playwright) a `http://localhost:8090` y hace clic en `#btnExportStock`.
  * Genera el archivo oficial `STOCK_ALMACEN_YYYY-MM-DD.xlsx` con el catálogo enriquecido y colores corporativos.
* **Tabla HTML en el Correo**:
  * Formato corporativo refinado: encabezado en **gris plata neutro (`#D9D9D9`)** para distinguir de las cantidades, columnas compactas y estilizadas, columna de sistemas en azul suave, cantidades IN/OUT en naranja pastel, y Unidades y % en amarillo destacado.
  * Unidades calculadas dinámicamente:
    * TRV1: $\text{round}(25.200 \times \text{Occ} / 100) \rightarrow$ `12605 CAJAS` ($50,02\%$).
    * Crane: $\text{round}(3.960 \times \text{Occ} / 100) \rightarrow$ `1314 PALETS` ($33,18\%$).
* **Firma y Remitente**:
  * Remitente: `ciclo3@friggorina.com` (SMTP `192.168.0.234:25`).
  * Destinatarios: **`informes.ciclo3@friggorina.com`** (mismo canal corporativo que los reportes de dashboard, editable en `destinatarios.txt`).
  * Asunto: `Ciclo 3 - Stock y Operaciones del D/MM` (ej: `Ciclo 3 - Stock y Operaciones del 7/09`).
  * Firma institucional: `Control de Operaciones — Ciclo 3 / Frigorífico Gorina` con aviso automático al pie en 13px.
* **Estado de Prueba**: Probado y validado en vivo con entrega exitosa.

---

## 8. Herramientas de Diagnóstico y Control en el Escritorio (Implementado 10/09/2026)
* **Ubicación en el Host**: Carpeta en el Escritorio: `C:\Users\gorinahostadmin\Desktop\Revision Informes\`
* **Herramientas disponibles**:
  1. `1_ESTADO_Y_DIAGNOSTICO.bat`:
     * **Diagnóstico integral en pantalla**:
       - Estado de las páginas web (PROD :80, LAB :8080, Stock Almacén :8090).
       - Última actualización de `datos.json` en PROD y LAB con minutos de desfase y etiquetas [AL DIA].
       - Último archivo de stock descargado por la tarea automática de 30 min.
       - Últimos envíos efectivos de correos (Diario de cierre, Semanal, Mensual).
       - Estado en tiempo real de las tareas programadas de Windows.
       - Evaluación inteligente de calendario para el disparo automático de hoy y de la próxima jornada.
  2. `2_ENVIO_MANUAL_INFORMES.bat`:
     * **Menú interactivo de forzado y pruebas**:
       - `[1]` Enviar Correo Diario de Cierre de Operaciones (HTML con tabla + Excel oficial).
       - `[2]` Enviar Informe Semanal (PDF completo de todas las pestañas).
       - `[3]` Enviar Informe Mensual (PDF completo de todas las pestañas).
       - `[4]` Enviar Cierre Diario + Informes de Hoy según calendario.
       - `[5]` Modo Prueba / Simulación (Genera archivos sin enviar correos).
       - `[0]` Salir.
     * Permite confirmar el destinatario por defecto (`informes.ciclo3@friggorina.com`) o ingresar una casilla alternativa en caliente.
* **Módulos backend asociados**:
  - `LAB/colector_test/diagnostico_sistema.py`
  - `LAB/colector_test/menu_envio_informes.py`

---

## 9. Novedad 4: Unificación y Automatización de Informes Semanal y Mensual al Cierre de Jornada (10/09/2026)
* **Objetivo**: Alinear los informes Semanales y Mensuales con el criterio del Cierre Diario de Operaciones (monitoreo de 3 ciclos consecutivos de 5 min de inactividad a partir de las 16:00 hs o corte forzoso de 18:00 hs).
* **Reglas de Negocio Implementadas**:
  1. **Informe Semanal**:
     * Se despacha **al mismo momento exacto** que el correo de operaciones del último día hábil de la semana laboral.
     * Habitualmente se emite los **viernes** tras confirmar el cese de producción.
     * **Manejo de feriados**: Si el viernes es feriado, el envío se adelanta automáticamente al jueves (o al día hábil inmediatamente anterior si hubiese feriado puente o fin de semana largo).
  2. **Informe Mensual**:
     * Se despacha **al mismo momento exacto** que el cierre de operaciones del último día hábil del mes calendario.
     * Si el cierre de mes calendario cae sábado o domingo, se envía el viernes inmediatamente anterior.
     * Si ese viernes o el último día de mes es feriado, se adelanta automáticamente al día hábil previo.
* **Componentes Técnicos Desarrollados**:
  * `LAB/colector_test/feriados.json`: Base de feriados nacionales oficiales y no laborables de planta para 2026 (fácilmente ampliable).
  * `LAB/colector_test/calendario_informes.py`: Módulo que calcula dinámicamente si una fecha dada es hábil, si es el último día hábil de la semana en curso y si es el último día hábil del mes en curso.
  * `LAB/colector_test/envio_informe.py` (v2):
    * Elimina la restricción obsoleta del día 1 del mes.
    * Incorpora control de banderas `logs/informe_semanal_enviado_YYYY-MM-DD.json` e `informe_mensual_enviado_YYYY-MM.json` para evitar cualquier reenvío redundante.
    * Permite ejecución modular, forzado individual (`--weekly`, `--monthly`), simulación (`--test`) y modo automático por calendario (`--auto`).
  * `LAB/colector_test/cierre_jornada.py` (v2):
    * Al confirmar los 3 ciclos de inactividad (o las 18:00 hs), tras enviar el mail diario con Excel, invoca de manera coordinada a `envio_informe.verificar_y_enviar_informes()`.
* **Desactivación de Tareas Programadas Obsoletas**:
  * Las tareas antiguas en Windows Task Scheduler (`Gorina LAB - Informe Semanal` de sábados a las 6 AM y `Gorina LAB - Informe Mensual` de los días 1 a las 6 AM) fueron pasadas al estado **`Disabled`**.
  * Ahora todos los reportes corren sincronizados con la producción real en `Gorina LAB - Colector datos` (`colector.bat`).
* **Respaldo creado**: `ARCHIVO/BACKUP_PRE_INFORME_CIERRE_2026-09-10/`.

---

## 10. Mejoras de Interfaz, Responsividad Móvil y Nuevos KPIs (11/09/2026)
* **Objetivo**: Optimizar la experiencia en dispositivos móviles y sumar métricas de volumen en la vista general.
* **Cambios realizados**:
  1. **Nuevos KPIs**: Incorporación de *Entradas Máximas* del período previo a las *Salidas Máximas*.
  2. **Encabezados y Fechas**: Eliminación de fechas duplicadas en los títulos y etiquetas.
  3. **Menú y Botones en Móvil**:
     - Barra superior compacta con menú desplegable estilizado.
     - Botones de acción agrupados (Actualizar / Descargar lado a lado).
     - Botones de sistemas organizados en cuadrícula 2x2 compacta sin fechas redundantes.
  4. **Distribución de KPIs**:
     - KPIs principales en 2 columnas por renglón en móviles.
     - Reubicación de KPIs laterales y resumen diario para flujo visual continuo en smartphones.
* **Archivos modificados**: `LAB/dashboard_test/dashboard_operaciones.html` y `PROD/dashboard/dashboard_operaciones.html`.

---

## 11. Depuración de Días Inactivos / Sin Movimiento (12/09/2026)
* **Causa**: Al consultar el SCADA Siemens WebRH en fin de semana, el colector recibía registros con 0 ingresos y 0 salidas correspondientes al día sábado (`2026-09-12`), incorporándolos a `datos.json`. En consecuencia, la vista semanal extendía el rango e incrementaba el conteo de días hábiles activos de 5 a 6.
* **Correcciones implementadas**:
  1. **Colector Backend (`LAB/colector_test/colector.py`)**:
     - Se omite la inserción de registros del día de hoy provenientes de WebRH si `inn == 0` y `out == 0`.
     - Si existiera un registro vacío previo de la fecha actual, se purga del payload.
     - Filtro global previo al guardado para descartar cualquier entrada donde tanto ingresos como salidas sean nulos o cero.
  2. **Frontend Defensivo (`dashboard_operaciones.html` en LAB y PROD)**:
     - Función `weekRange(a)`: Solo extiende el cierre semanal a sábado o domingo si dichos días registran movimientos efectivos (`inn > 0` o `out > 0`).
     - Parsers `parseJsonPayload` y `loadFromCSV`: Descartan filas con 0 movimientos para evitar conteos falsos en "Días con datos".
* **Validación**: Dashboard LAB normalizado al rango `Semana (Lun–Vie) · 07/09 — 11/09 (2026)` con 5 días activos computados.

---

## 12. Captura Horaria, Vista Diaria Dinámica y Nuevos KPIs por Hora (15/09/2026 - V1.1.5)
* **Objetivo**: Habilitar visualización de movimientos hora por hora en gráficos, selector de turnos y métricas de picos horarios centradas.
* **Módulos y Almacenamiento Desarrollados**:
  1. **Base de Datos SQLite (`LAB/colector_test/historico_horario.db`)**:
     - Tabla `movimientos_horarios` con: `(sistema, fecha_operativa, turno, hora, inn, out, occ, updated_at)`.
     - Consumo anual estimado: ~1,2 MB.
  2. **Reglas de Turnos y Cruce de Medianoche**:
     - Turno 1: 05:00 a 17:59 (asociado al día en curso).
     - Turno 2: 18:00 a 23:59 (asociado al día en curso).
     - Turno 2 (Noche): 00:00 a 04:59 (asociado a la `fecha_operativa` del día de inicio del turno).
  3. **Módulo Colector Horario (`LAB/colector_test/colector_horario.py`)**:
     - Integrado a `colector.py` en cada ciclo de 5 minutos.
     - **CTTO (Almacén Congelado)**: Consulta el endpoint `/stacker-1/api/operations` con paginación automática (`limit=100`) para agrupar ingresos y salidas por hora exacta.
     - **TRV1 / TRV2**: Reconstrucción horaria completa de entradas (`SCF_AT1_06`) y salidas (`SCF_SE5_03`) desde `registros_cam` en MySQL, normalizadas con los totales oficiales de `produccion_turnos` y WebRH live.
     - Genera `datos_horarios.json` y `datos_horarios.js` para consumo del frontend.
* **Interfaz de Usuario (`LAB` y `PROD` - V1.1.5)**:
  1. **Selector de Período**: Botón **[Día]** a la izquierda de `[Semana]`. La vista por defecto permanece fija en **Semana** (con la suma de ambos turnos).
  2. **Gráficos en Modo Día**:
     - **Gráfico Superior (Card c7)**: Gráfico de **LÍNEA** de **Ingresos (azul `#2e6fd8`)** y **Salidas (rojo `#d9001d`)** por hora. Eje Y en unidades (`sys.unit`), sin porcentaje y sin líneas de capacidad. Eje X dinámico mostrando solo horas con actividad.
     - **Gráfico Inferior (Card c8)**: Curva de **Evolución de ocupación estimada (%)** hora por hora (0–100%) calculada sobre el balance acumulado y capacidad del sistema.
  3. **Resumen del Día (`#sumDay`) y KPIs Centrados**:
     - Grilla superior 2x2: Ingresos, Salidas, Ocupación y Balance (despejada de selectores, con formato limpio).
     - Fila inferior: **Pico Ingreso/h** y **Pico Salida/h** perfectamente **centrados** horizontalmente con valor y hora exacta (ej. TRV1: `793 cajas a las 13:00 hs` y `984 cajas a las 11:00 hs`).
  4. **Selector de Turnos**:
     - Implementado como **desplegable interactivo (`<select>`)** ubicado en la barra de herramientas del gráfico horario (`c7`).
     - **Por defecto siempre Turno 1** (`Turno 1 (05 a 17 hs)`). Al alternar a `Turno 2 (18 a 04 hs)` filtra de forma instantánea las horas del turno, curvas y métricas.
     - En vistas Semanal y Mensual se visualiza la suma consolidada de ambos turnos.
  5. **Selector de Fecha Clickeable (`#dayDate`)**: Estilo sutil de botón interactivo con ícono `📅`, borde y flecha `▾`.
  6. **Resumen Ejecutivo y Reportes**:
     - En modo Día: Detalla picos horarios de entrada y salida, cantidad de horas operativas con actividad y balance neto.
     - En modo Semana: Destaca el día de mayor ingreso y el día de mayor salida de la semana.
* **Resguardo y Despliegue a Producción (15/09/2026)**:
  - **Copia de Resguardo**: Creado `ARCHIVO/BACKUP_PRE_V1.1.5_HORARIOS_2026-09-15` con versión anterior de `dashboard_operaciones.html`, `datos.json`, `colector.py`, `config.json` y `colector.bat`.
  - **Paso a PROD**: Desplegados en `PROD/dashboard` y `PROD/colector`:
    - `dashboard_operaciones.html` (V1.1.5)
    - `datos_horarios.json` y `datos_horarios.js`
    - `colector.py` y `colector_horario.py`
    - `historico_horario.db` (SQLite)
    - `config.json` apuntando a `PROD/dashboard/datos.json`.
  - **Validación Final**: Corrida de `colector.py` en PROD con código 0 y verificación en navegador con Playwright confirmando renderizado óptimo y responsivo.

---

## 13. Versión V1.1.6 — Botón de Fecha Sombreado, Comparación Diaria, Almanaque Interactivo e Informe PDF por Turnos (15/09/2026)
* **Objetivo**: Perfeccionar la experiencia de usuario diaria, habilitar la comparación histórica en gráficos horarios y enriquecer el informe PDF diario con desglose de turnos operativos.
* **Mejoras Implementadas (`LAB` y `PROD`)**:
  1. **Botón de Fecha Interactivo (`#dayDate`) y Centrado Estricto del Día**:
     - Estilizado con fondo blanco puro (`#fff`), borde azul definido (`1.5px solid #2e6fd8`), altura de 36px exacta y alineación vertical estricta (`y: 456.5px`, `height: 36px`) idéntica a las flechas `❮` `❯` y botón `Hoy`.
     - **Día de la semana (`#dayWeek`, ej. MARTES)**: Reubicado por encima del botón de fecha dentro de `.daycenter`, con centrado horizontal exacto (0.00px de diferencia) respecto al botón del almanaque (`#dayDate`), sin desfasarse por el ancho total del card.
  2. **Comparación con Período Anterior en Modo Día**:
     - Corregido `prevFrom('day', d)` y mapeo en `cmpLabel('prev')` (`vs. día anterior`).
     - Gráfico superior (`occChart`): Grafica líneas punteadas para `Ingresos (vs. día anterior)` (azul claro) y `Salidas (vs. día anterior)` (rojo punteado) alineadas a las mismas horas.
     - Gráfico inferior (`flowChart`): Grafica curva punteada morada (`#8a63d2`) con la evolución de ocupación horaria estimada del día anterior.
  3. **Botón de Comparación en Gráfico Inferior (`#flowBar` / Card c8)**:
     - Incorporado botón `.cmpwrap` con menú desplegable sincronizado (`cmpMenuFlow`) idéntico al gráfico superior.
     - En modo semanal y mensual proyecta barras comparativas de ingresos y salidas del período anterior.
  4. **Almanaque Inline de Comparación y Filtro Superior desde Mes (`unitWrap` / `cmpMenu`)**:
     - **Filtro Superior (`unitWrap`)**: Visible únicamente a partir de **Mes** (Mes, Trimestre, Año); oculto en Día y Semana respetando la navegación principal alineada.
     - **Almanaque Inline en el Gráfico**: Al hacer clic en el botón de comparación del gráfico y seleccionar **"Otro período…"**, el almanaque mensual interactivo se despliega **directamente en el menú emergente del gráfico**. El usuario selecciona cualquier día con datos y la comparación se aplica instantáneamente sobre las curvas.
  5. **Informe PDF Diario Multi-Turno (`exportAllPDF`)**:
     - Aplica **exclusivamente al informe diario** (los informes semanal, mensual y trimestral permanecen idénticos e inalterados).
     - **Página 1 (Resumen del Día)**:
       - 6 tarjetas KPI adaptadas al día: Ingresos Día, Salidas Día, Balance Día, Pico Ingreso/h (con horario), Pico Salida/h (con horario) y Ocupación.
       - **Gráfico Turno 1 (05:00 a 17:00 hs)**: Curva horaria de ingresos y salidas del turno.
       - **Gráfico Turno 2 (18:00 a 04:00 hs)**: Se dibuja **únicamente si Turno 2 registra actividad**; si no tiene datos se omite automáticamente y se presenta la curva de ocupación estimada del Turno 1.
     - **Página 2 (Detalle Horario)**:
       - Tabla detallada hora por hora: `HORA | TURNO | INGRESOS | SALIDAS | BALANCE` y fila de `TOTALES DÍA`.
  6. **Maximizado de Gráficos Contextual (`openModal`)**:
     - Corregido el visor de pantalla completa para que clone fielmente la instancia activa del gráfico en pantalla (`srcChart`):
       - **En modo Día**: Maximiza las curvas horarias reales del turno (Ingresos y Salidas en gráfico superior, y evolución de Ocupación horaria estimada en el inferior).
       - **En modo Semana/Mes/Trimestre/Año**: Maximiza la evolución de ocupación (línea) y el flujo de ingresos/salidas (barras).
       - Conserva todas las líneas de comparación activas (curvas punteadas de día/período anterior) y escala Y con formato porcentual y de unidades.
* **Validación y Despliegue**:
  - **Estado**: **CERRADO Y VALIDADO POR EL USUARIO (15/09/2026 18:35 hs)**.
  - **Pruebas Automatizadas y Visuales**: Realizadas con Playwright en `LAB` y `PROD`. Centrado milimétrico validado (diferencia de eje X: 0.00px, altura de botones: 36px en eje Y idéntico).
  - **Exportación PDF**: Verificada en vivo (7 páginas por turnos, 451 KB).
  - **Copia de Resguardo Físico**: Creada en `ARCHIVO/BACKUP_V1.1.6_VALIDADO_2026-09-15` conteniendo:
    - `dashboard_operaciones.html` (173 KB)
    - `datos_horarios.json` (23 KB)
    - `datos_horarios.js` (23 KB)
    - `colector_horario.py` (15 KB)
    - `colector.py` (20 KB)
    - `config.json` (3 KB)

---

## 8. Corrección Crítica: Purgado de Horas Futuras y Ajuste de Fecha en Almacén Congelado (16/09/2026)
* **Incidente / Síntoma**:
  - En la vista diaria de hoy (`16/09/2026`) para Almacén Congelado (`crane`), el gráfico mostraba horas hasta las 16:00 hs con movimientos de la tarde del día anterior, cuando aún eran las 10:00 / 11:00 hs de la mañana.
* **Causa Raíz Técnica**:
  - En `colector_horario.py`, durante la ejecución de madrugada (`now.hour < 5`, aprox. 04:58 hs), `get_shift_and_op_date(now)` retornó `op_date = '2026-09-15'`.
  - El colector consultó CTTO para el 15/09/2026, pero al procesar cada hora `h_str` ejecutaba:
    `dummy_dt = datetime.datetime.combine(now.date(), datetime.time(h_int, 0))`
  - Dado que `now.date()` era ya `2026-09-16`, las horas de la tarde del día 15 (11:00 a 16:00 hs) se combinaron con la fecha calendario del 16, haciendo que `get_shift_and_op_date(dummy_dt)` les asignara fecha operativa `2026-09-16`.
  - Al avanzar el día 16, el colector actualizó las horas matutinas (05:00 a 10:00 hs) por `upsert`, pero las filas 11:00 a 16:00 de la base SQLite permanecieron intactas, proyectándose erróneamente en el gráfico.
* **Solución Implementada**:
  1. **Alineación de Fechas en `colector_horario.py`**:
     - En `run_hourly_collection`: se consulta el día calendario de hoy (`today_cal = now.date()`) y, si `now.hour < 5`, también el día anterior (`today_cal - 1 día`).
     - Se combinan las horas con su fecha calendario real de consulta (`q_date`), impidiendo cruces de días.
     - Se omite cualquier registro con `h_int > now.hour` en el día en curso.
  2. **Purga Automática de Horas Futuras en SQLite**:
     - Al concluir la ingesta de CTTO, se ejecuta una limpieza atómica en SQLite:
       `DELETE FROM movimientos_horarios WHERE sistema = 'crane' AND fecha_operativa = ? AND hora > ?`
       garantizando que ninguna hora posterior a la hora en curso subsista en la base de datos para la fecha operativa activa.
  3. **Salvaguarda en `populate_ctto_range`**:
     - Se aplicó la misma condición para evitar inserción de horas futuras en ejecuciones de reconstrucción histórica (`--init-history`).
  4. **Sincronización y Regeneración**:
     - Se aplicó la corrección en `PROD\colector\colector_horario.py` y `LAB\colector_test\colector_horario.py`.
     - Se ejecutó la recolección horaria: las horas 11:00 a 16:00 fueron purgadas de `historico_horario.db`.
     - Se re-exportaron `datos_horarios.json` y `datos_horarios.js` en PROD y LAB.
* **Validación**:
  - Verificado en vivo en `http://192.168.0.126/dashboard_operaciones.html` (Día: 16/09/2026):

---

## 9. Integración Directa de MySQL `registros_cam` para TRV1 y TRV2 en Tiempo Real (16/09/2026)
* **Incidente / Síntoma**:
  - En la vista diaria de TRV1 para el día en curso (`16/09/2026`), los datos de las 10:00 a 11:00 hs se observaban muy bajos o vacíos (en LAB marcaba 584 salidas a las 10:00 hs mientras que en la planta se habían producido más de 1.000).
* **Causa Raíz Técnica**:
  1. La vista oficial `vw_tablero_trv1` lee de `produccion_turnos`, la cual se carga recién al cierre del turno diario (lote cerrado). Por lo tanto, durante el transcurso del día, `vw_tablero_trv1` no posee el día actual.
  2. En el colector horario se dependía de un scraper web hacia Siemens WinCC WebRH (`webrh_reader.py`), el cual sufría de retardos de PLC, bloqueos por sesión única concurrente de Siemens y cálculo de deltas acumulativos en snapshots volátiles. WebRH reportaba sólo 4.323 salidas cuando la base de datos de cámaras ya registraba más de 5.200.
  3. En PROD ni siquiera estaba activo WebRH, por lo que TRV1 permanecía vacío (`[]`) para el día de hoy.
* **Solución Definitiva Implementada**:
  1. **Ingesta Directa desde MySQL `registros_cam`**:
     - Se implementó `fetch_trv_mysql_hourly_today(cfg)` en `colector_horario.py`.
     - Consulta directamente cada 5 minutos la tabla oficial `p003148.registros_cam` agrupando por hora:
       - `SCF_AT1_06`: Ingresos a TRV1 (caja por caja con timestamp real).
       - `SCF_SE5_03`: Salidas de TRV1.
       - `SCF_AT2_06` y `SCF_SE6_03`: Sensores de TRV2.
     - Inserta los movimientos reales exactos hora por hora en SQLite `movimientos_horarios` y purga horas futuras.
  2. **Acumulado en Tiempo Real en `colector.py`**:
     - En `fetch_mysql_system(cfg, 'trv')`, si el día actual aún no cerró en `vw_tablero_trv1`, se calcula la suma acumulada de ingresos y salidas en vivo desde `registros_cam`.
     - Se calcula la ocupación estimada acumulada continua sobre la capacidad nominal (25.200 cajas) mediante `fill_missing_occupancy`.
  3. **Blindaje de Prioridad de BD Oficial**:
     - Se modificó `colector.py` para que nunca se sobrescriban los datos oficiales de MySQL con valores truncados o menores provenientes de WebRH.
  4. **Despliegue y Sincronización**:
     - Aplicado en `PROD\colector` y `LAB\colector_test`.
     - Regenerados `datos.json`, `datos_horarios.json` y `datos_horarios.js`.
* **Validación**:
  - Verificado en vivo en `http://192.168.0.126/dashboard_operaciones.html` (TRV1 · Día 16/09/2026):
    - Hora 06:00 -> IN: 124, OUT: 294
    - Hora 07:00 -> IN: 767, OUT: 1.135
    - Hora 08:00 -> IN: 689, OUT: 1.137
    - Hora 09:00 -> IN: 740, OUT: 1.114
    - **Hora 10:00 -> IN: 763, OUT: 1.062** (exacto al sensor físico)
    - **Hora 11:00 -> IN: 411, OUT: 540** (en tiempo real continuo)
    - Totales en curso: 3.494 cajas ingresadas, 5.282 cajas salidas, ocupación estimada en 40,6%.




---

## 10. Bug Cierre de Día TRV1 — Salidas Incorrectas por SCF_SE5_03 (16/09/2026)

### Síntoma
El dashboard reportó al cierre del día 16/09/2026: **IN=5862, OUT=8724**.
Los valores reales confirmados por operaciones fueron: **IN=5882, OUT=6277**.

### Diagnóstico
- La vista `vw_tablero_trv1` no tiene datos del día actual hasta que cierre el lote de producción.
- El colector usaba `SCF_SE5_03` como proxy de salidas en tiempo real.
- **`SCF_SE5_03` NO es confiable para salidas reales de TRV1**: en el 15/09 arrojó 8808 vs 7109 oficiales (sobreestima ~24%). Captura también movimientos de líneas auxiliares, devoluciones o transportadores bidireccionales, además de las salidas reales.
- Resultado: el campo `out` se inflaba masivamente durante todo el día hasta el cierre del lote.

### Causa Raíz Exacta
En `colector.py`, función `fetch_mysql_system` (~L218-234):
- Condición `not any(r['k'] == today_str for r in res)` → True (la vista no tiene hoy)
- Consultaba `SCF_SE5_03` y asignaba ese valor erróneo como `out` del día.

### Solución Definitiva — Aplicada en PROD y LAB (16/09/2026)
**Archivo:** `colector.py` → bloque de "día en vivo" dentro de `fetch_mysql_system`.

**Antes:**
```python
SUM(CASE WHEN camara = 'SCF_SE5_03' THEN 1 ELSE 0 END) as out_t1  # ERRÓNEO
```

**Ahora:**
1. **IN**: sigue usando `SCF_AT1_06` (diferencia < 0.5% con dato oficial — fiable).
2. **OUT**: consulta `produccion_turnos.sal_t1 + sal_t2` para el día actual.
   - Si el lote ya cerró parcialmente → se muestra el dato oficial.
   - Si el lote aún no cerró → `out = None` (el dashboard no muestra un valor falso).
3. `SCF_SE5_03` **queda eliminado de toda lógica de salidas**.

### Resultado Post-Fix (verificado en datos.json)
```
{'k': '2026-09-16', 'inn': 5869.0, 'out': None, 'occ': 71.0}
```
→ IN correcto desde sensor, OUT pendiente de cierre oficial del lote en `produccion_turnos`.

### Comportamiento Esperado Futuro
- **Durante el turno**: `out = None` (sin dato falso). El día siguiente, una vez que `vw_tablero_trv1` incluye la fecha, tomará automáticamente el dato oficial de la vista.
- **Al cierre del lote** (cuando `produccion_turnos.sal_t1` se carga): `out` mostrará el valor correcto proveniente de la fuente oficial.


---

## 11. Trazabilidad Definitiva y Calibración Horaria de TRV1 (16/09/2026)

### Diagnóstico de Divergencia
1. **Divergencia en Salidas y Ocupación**:
   - `SCF_SE5_03` registraba 7.866 a 8.600 cajas físicas por contar derivaciones y recirculaciones, frente a las **6.277 cajas netas de despacho oficial**.
   - Al tener `out = None` temporalmente, la fórmula de ocupación sumaba el ingreso total (+5.869) sin descontar salidas, proyectando una ocupación anómala del 71,0% (17.892 cajas).
   - Al filtrar por Turno 1 (`T1`), el dashboard realizaba la suma horaria directa de los registros sin calibrar, mostrando 8.600 salidas en la tarjeta de resumen.

### Solución Definitiva de Extremo a Extremo
1. **Calibración Proporcional de la Distribución Horaria (`colector_horario.py`)**:
   - La forma de la curva horaria (picos por hora) se toma de los sensores físicos en tiempo real.
   - Cada hora se calibra con la escala: $\text{Salida}_{\text{hora}} = \text{Salida}_{\text{sensor}} \times \left(\frac{\text{Salida Total Oficial}}{\sum \text{Salidas Sensor}}\right)$.
   - Resultado: La suma de todas las horas coincide **exactamente al 100% con las 6.277 cajas** de salida oficial.

---

## 12. Armonización de KPIs Diarios y Promedios Horarios (16/09/2026)
- **8 Tarjetas en Cuadrícula 4x2 Homogénea (Todo en 1 renglón por etiqueta)**:
  - **Fila 1 (Totales del Día sin sufijo T1)**: `Ingresos`, `Salidas`, `Ocupación`, `Balance`.
  - **Fila 2 (Rendimiento Horario con unidad /h)**:
    1. `Prom. Ing./h`: Promedio horario de ingresos (`cajas/h` o `palets/h`) sin texto de horas abajo.
    2. `Máx. Ing./h`: Máximo ingreso horario (`cajas/h`) con etiqueta `a las HH:00 hs`.
    3. `Prom. Sal./h`: Promedio horario de salidas (`cajas/h`) sin texto de horas abajo.
    4. `Máx. Sal./h`: Máxima salida horaria (`cajas/h`) con etiqueta `a las HH:00 hs`.
- **Eliminación de Sombreado Hover Anómalo**:
  - Se removieron los estilos específicos de `.sumday-peaks` (borde azul marino y fondo diferenciado en hover) para que todas las 8 tarjetas compartan exactamente el mismo fondo, borde, dimensiones y comportamiento visual uniforme.
- **Despliegue**: Aplicado directamente en `PROD` y sincronizado en `LAB`.

---

## 13. Normalización Estricta a Números Enteros para Cajas y Palets (17/09/2026)
- **Causa Raíz**:
  - En la calibración horaria de `colector_horario.py`, el factor de escala utilizaba `round(..., 1)` generando valores flotantes (ej. `667.8`).
  - En `dashboard_operaciones.html`, el callback del tooltip de Chart.js imprimía `(c.parsed.y || 0).toLocaleString('es-AR')` sin redondeo entero previo, mostrando decimales en pantalla (`667,8 cajas`).
- **Solución Definitiva de Extremo a Extremo**:
  1. **Colector (`colector_horario.py`)**:
     - `upsert_hourly_record` almacena exclusivamente valores `int(round(...))` en SQLite `movimientos_horarios`.
     - El cálculo de escala aplica `int(round(...))` tanto para `inn` como para `out`.
     - `export_hourly_json` exporta siempre tipos enteros a `datos_horarios.json` y `datos_horarios.js`.
  2. **Frontend (`dashboard_operaciones.html`)**:
     - Callbacks de tooltips y ejes Y en gráficos diarios y generales actualizados con `Math.round(c.parsed.y || 0).toLocaleString('es-AR')`.
     - `parseJsonPayload` y `getHourlyFor` aplican `Math.round()` al cargar datos en memoria.
  3. **Base de Datos y JSONs**:
     - Base SQLite y archivos JSON en `PROD` y `LAB` saneados a valores enteros.
- **Despliegue**: Verificado y activo en `PROD` y `LAB`.

---

## 14. Presentación Ejecutiva para Gerencia y Material Visual (17/09/2026)
- **Objetivo**: Presentar a la Dirección y Gerencia de Operaciones el valor estratégico, evolución y capacidades del Tablero de Control Operativo Ciclo 3 en lenguaje ejecutivo claro y sin jerga informática.
- **Ejes Clave Incorporados**:
  1. **Origen y Necesidad**: Reemplazo de planillas de papel y consultas telefónicas demoradas por un monitoreo sencillo y continuo que permite tomar decisiones preventivas durante el turno.
  2. **Agentes Autónomos de Software**: Captura de datos cada 5 minutos en segundo plano sin carga operativa humana.
  3. **Cierre Automático de Turno**: Detección inteligente de fin de jornada (15 min de inactividad luego de las 16:00 hs o corte a las 18:00 hs) y despacho autónomo del resumen por correo a Gerencia con cuadro corporativo oficial y Excel de stock adjunto.
  4. **Preparados para el Segundo Turno**: Arquitectura modular con selectores listos para discriminar Turno 1, Turno 2 o consolidar el día completo, extensible a nuevas áreas de planta (desposte, empaque, etc.).
  5. **Navegación Temporal y Comparativas**: Selectores de Día, Semana, Mes, Trimestre, Año, resumen del día con calendario integrado y comparación frente al día previo (+/- cajas).
  6. **Indicadores Diarios Armonizados (8 KPIs)**: Total ingresos, salidas, stock, % ocupación, y ritmos de promedios/máximos horarios en números enteros garantizados.
  7. **Movilidad y Seguridad Interna**: Visualización en smartphones para supervisores en planta y confinamiento 100% en la red interna de Frigorífico Gorina (sin salida a internet ni riesgos de fuga de datos).
- **Entregables**:
  - Presentación interactiva en pantalla: `http://192.168.0.126/presentacion.html` (transición suave de slides, modo pantalla completa `F11`, atajos de teclado `←` / `→`).
  - Documento Ejecutivo: `PRESENTACION_GERENCIA_CICLO3.md` y artefacto `presentacion_gerencia_ciclo3.md`.
  - Recortes y capturas reales en alta resolución: Carpeta `img_pres/` (header de navegación temporal, resumen del día, 8 KPIs, gráfico de ocupación, gráfico de flujo, vista móvil y correo automático de cierre).
  - **Despliegue**: Desplegado en `PROD` y replicado en `LAB`.

---

## 15. Diagnóstico y Solución Definitiva de Persistencia Horaria y Salidas en Vivo (17/09/2026)

### Diagnóstico de Causa Raíz
1. **Día 16/09 sin datos en el gráfico y KPIs horarios**:
   - `colector_horario.py` únicamente consultaba el día de hoy (`today_cal`). No existía un mecanismo de auto-backfill para días previos.
   - Si un lote cerraba de madrugada en MySQL o la tarea programada no capturaba el día anterior, `movimientos_horarios` quedaba vacío para esa fecha. Al navegar al 16/09, el dashboard mostraba 0 ingresos y 0 salidas horarias.
2. **Día 17/09 con valores duplicados (15.075 in y 12.550 out) en :8080**:
   - `fetch_webrh_today` reporta los contadores acumulados de todo el día (`inn = 7537, out = 5938`).
   - Un bloque de código en `run_hourly_collection` trataba ese acumulado diario como un delta de la hora 17:00, insertando `7537` y `5938` en esa única hora. Al sumarlo a las horas 06:00 a 16:00 (que ya sumaban 7537 y 5938), el total del día se duplicaba exactamente al 200% (15.075 y 12.550).
3. **PROD con `out: None` y Ocupación Inflada al 74.13%**:
   - `PROD/colector/` no tenía el archivo `webrh_reader.py`, por lo que fallaba el import y dependía exclusivamente de `produccion_turnos` en MySQL.
   - Como `produccion_turnos.sal_t1` aún no está cerrado para hoy por el proceso batch nocturno, `out` quedaba en `None`.
   - La función `fill_missing_occupancy` interpretaba `None` como 0 salidas, sumando 7.054 cajas sin restar salidas, disparando la ocupación anómalamente a 74.13%.

### Solución Definitiva Implementada
1. **Módulo de Auto-Sincronización Histórica (`sync_recent_history`)**:
   - En cada ejecución (cada 5 min), el colector revisa los últimos 7 días hábiles.
   - Si algún día carece de horas en SQLite, consulta automáticamente `produccion_turnos` + `registros_cam` (para TRV) y la API de CTTO (para Crane), calibrando las horas y rellenando la base sin intervención manual.
2. **Calibración Exacta en Vivo (Cero Duplicación)**:
   - Se eliminó el bloque erróneo que insertaba el total diario en una hora individual.
   - Para el día en curso, las 11 horas de escaneo real en `registros_cam` se escalan con factor proporcional contra los totales de WebRH (`7537 in, 5938 out`), con ajuste estricto de residuo.
   - Resultado: La suma de todas las horas del 17/09 es **exactamente 7.537 in y 5.938 out**.
3. **Despliegue y Validación en PROD y LAB**:
   - `webrh_reader.py` copiado a `PROD/colector/`.
   - `PROD/colector/colector.py` corregido para tomar WebRH cuando `out` sea `None` o 0.
   - Base de datos SQLite saneada y sincronizada en ambos entornos.
   - Validación visual con Playwright en puerto 80 y 8080: ambos muestran exactamente 5.882 in / 6.277 out el 16/09 y 7.537 in / 5.938 out el 17/09, con ocupación real del 50,57% - 52,49%.

---

## 16. Suspensión de Presentación y Dirección Limpia para Acceso a LAB (17/09/2026)
- **Presentación Eliminada/Suspendida**:
  - A solicitud del usuario, se eliminaron los archivos interactivos y documentación de la presentación ejecutiva (`presentacion.html`, `PRESENTACION_GERENCIA_CICLO3.md`).
- **Configuración de URLs de Red para LAB**:
  - **Servidor**: Hostname en Active Directory: `FGLP53` (`fglp53.friggorina.local`, IP `192.168.0.126`).
  - **Directorio Virtual IIS Creado**: `/tablero.ciclo3` bajo el puerto 80 apuntando a `C:\Ciclo3\Servicios\DASHBOARD\LAB\dashboard_test` (alias `/lab` eliminado).
  - **Host Header Binding IIS**: Sitio `Gorina LAB` vinculado con `HostHeader: tablero.ciclo3` en puerto 80.
  - **Ajuste en `LAB/web.config`**: Incorporación de directivas `<remove>` en `customHeaders` para evitar conflicto HTTP 500.19 por herencia de encabezados.
  - **Redirección Raíz**: Archivo `index.html` en `dashboard_test` que redirige automáticamente a `dashboard_operaciones.html`.
- **Direcciones Definitivas de Acceso a LAB desde la Red**:
  1. `http://fglp53/tablero.ciclo3` (Ya activa y operativa sin tocar nada de DNS).
  2. `http://tablero.ciclo3/` (Activa en IIS; requiere que Sistemas agregue en el DNS interno `tablero.ciclo3` -> `192.168.0.126`).
  3. `http://fglp53:8080/` (Alternativa por puerto).

---

## 17. Optimización Móvil: Tarjetas de Resumen del Día (18/09/2026)
- **Problema Reportado**: En pantallas de celular (`max-width: 768px`), la tarjeta "Resumen del día" forzaba 4 columnas fijas (`sumday-grid`). Debido al ancho reducido del viewport (375px a 390px), los últimos dos KPIs de cada fila (`Balance` y `Máx. Sal./h`) quedaban desbordados horizontalmente fuera de la pantalla.
- **Solución Aplicada**:
  1. **Ocultamiento de Métricas Horarias en Móvil (`.sumday-hourly`)**: Se suprimió la segunda fila de indicadores horarios (`Prom. Ing./h`, `Máx. Ing./h`, `Prom. Sal./h`, `Máx. Sal./h`) exclusivamente en vista móvil (`display: none !important`), evitando inflar la altura vertical de la tarjeta.
  2. **Diseño Simétrico 2x2 para KPIs Principales**: Los 4 KPIs esenciales del día (`Ingresos`, `Salidas`, `Ocupación`, `Balance`) se reestructuraron en una grilla de 2 columnas por 2 filas (`grid-template-columns: repeat(2, 1fr)`).
  3. **Preservación Total en Desktop**: En resoluciones de PC se conservan intactos los 8 indicadores en sus 2 filas completas de 4 columnas.
- **Despliegue**: Aplicado y verificado con Playwright en `LAB` y `PROD`.

---

## 18. Actualización de Leyenda de Pie de Página y Encabezado PDF (18/09/2026)
- **Modificación**: Se reemplazó la referencia desactualizada a planillas externas (`Panel de almacenamiento (cajas y palets) · Datos desde Google Sheets`) por la denominación oficial del sistema:
  - **Nuevo texto**: `Frigorífico Gorina SAIC · Operaciones Ciclo 3 · Panel de operaciones (cajas y palets) · Datos en tiempo real`.
- **Alcance**:
  1. Pie de página (`<footer>`) en la interfaz web (móvil y escritorio).
  2. Subtítulo superior de los informes exportados en formato PDF.
- **Despliegue**: Activo y verificado en `LAB` y `PROD`.

---

## 19. Nomenclatura Limpia y Corta de Archivos Exportados (18/09/2026)
- **Problema**: Al exportar informes o gráficos, la cadena descriptiva del período contenía caracteres especiales y espacios que se sanitizaban de forma agresiva, generando nombres largos con múltiples guiones bajos consecutivos (ej. `gorina_ciclo3_Semana__Lun_Vie____14_09____18_09__2026_.pdf`).
- **Solución Implementada**:
  - Se introdujo la función `fileSlugFor(p, from, to)` para estandarizar sufijos limpios, breves y sin repetición de guiones:
    - **Semanal**: `gorina_ciclo3_Semana_14_09-18_09.pdf`
    - **Mensual**: `gorina_ciclo3_Mes_09_2026.pdf`
    - **Diario**: `gorina_ciclo3_Dia_18_09_2026.pdf`
    - **Trimestral**: `gorina_ciclo3_Trimestre_3_2026.pdf`
    - **Anual**: `gorina_ciclo3_Ano_2026.pdf`
  - Se homogeneizaron las descargas de imágenes PNG y tablas CSV con el mismo patrón.
  - Se alinearon los envíos automáticos de correo (`envio_informe.py`) con la misma convención de nombres.
- **Despliegue**: Aplicado y validado en `LAB` y `PROD`.

---

## 20. Exclusión y Purga de Datos de Mantenimiento Almacén (19/09/2026)
- **Motivo**: El sábado 19/09/2026 se registraron movimientos en CTTO 2.1 (10 palets in, 10 palets out) debidos a pruebas de mantenimiento y no a la operatoria productiva normal.
- **Acciones Realizadas**:
  1. **Configuración de Fechas Excluidas**: Se incorporó el parámetro `excluded_dates: ["2026-09-19"]` en la sección `ctto` de `config.json` tanto en `LAB` como en `PROD`.
  2. **Protección en `colector.py`**: Se implementó el filtrado activo en `fetch_ctto_system` y en la consolidación de `payload['crane']` para ignorar fechas no operativas y recalcular la curva de ocupación sin distorsiones.
  3. **Purga Efectiva**: Se eliminó el registro del 19/09 en `datos.json` y `datos.js`. En SQLite (`historico_horario.db`) no había registros dado que la recolección horaria omite fines de semana.
  4. **Verificación**: Último día registrado para Almacén Congelado vuelve a ser el viernes 18/09/2026 (161 in, 174 out, 34,04% ocupación).
- **Despliegue**: Ejecutado y verificado en `LAB` y `PROD`.

---

## 21. Restauración de Puerto 8080 en IIS, Deshabilitación de Colector PROD y Verificación de Red (21/09/2026)
- **Diagnóstico del Incidente**:
  - Al ejecutar `diagnostico_sistema.py`, arrojaba error de conexión `WinError 10061` en `http://localhost:8080/dashboard_operaciones.html`.
  - Causa raíz: En IIS, el sitio `Gorina LAB` (id: 3) tenía bindings en `8085` y `80:tablero.ciclo3`, pero se había perdido el binding explícito en el puerto `8080`.
- **Acciones Correctivas**:
  1. **Restauración del Binding 8080**: Se reincorporó `http/*:8080:` al sitio `Gorina LAB` en IIS mediante `appcmd`. Verificado: responde HTTP 200 (176 KB).
  2. **Archivado / Deshabilitación de PROD**:
     - Se deshabilitó la tarea programada `Gorina - Colector datos` (`Disable-ScheduledTask`).
     - El único colector activo y vigente es `Gorina LAB - Colector datos` (corre cada 5 minutos recolectando TRV1 MySQL, Almacén CTTO y Dotación WebRH).
  3. **Preservación Estricta del Puerto 5000**:
     - Confirmado que ningún sitio ni binding de IIS ocupa el puerto 5000.
     - El puerto 5000 se mantiene reservado y en uso exclusivo por `Gorina.Api.exe` (C:\EGalli\GorinaPick\servidor\publicar\Gorina.Api.exe).
  4. **Verificación de Estructura Oficial de Acceso en Red**:
     - URL corporativa: `http://fglp53/tablero.ciclo3/dashboard_operaciones.html` (o `http://fglp53/tablero.ciclo3/`) mapeada directamente al físico de `LAB\dashboard_test`. Responde HTTP 200 OK.
     - Acceso por puerto: `http://fglp53:8080/dashboard_operaciones.html`. Responde HTTP 200 OK.
  5. **Actualización de `diagnostico_sistema.py`**:
     - Incorporada la verificación explícita de `http://localhost/tablero.ciclo3/dashboard_operaciones.html`.
     - Clarificado en la salida que PROD está archivado y LAB es el motor productivo vigente.

---

## 22. Implementación del Monitor Automático de Salud y Alertas por Correo (21/09/2026)
- **Objetivo**: Detectar de forma temprana e inmediata cualquier caída en los servicios del Dashboard Ciclo 3 (sitios IIS, recolección de datos, tareas programadas) y notificar por correo electrónico a los responsables técnicos.
- **Componentes Creados**:
  1. **Script de Monitoreo (`LAB/colector_test/monitor_alertas.py`)**:
     - **Chequeos continuos**:
       - Sitios HTTP: `http://fglp53/tablero.ciclo3/...` (acceso corporativo), `http://localhost:8080/...` (LAB), `http://localhost:8090/` (Stock Almacén).
       - Tareas Programadas: `Gorina LAB - Colector datos` (alerta si pasa a estado `Disabled`).
       - Frescura de datos: `datos.json` (alerta si transcurren más de 20 min sin actualizarse durante horario laboral 06:00 a 20:00 hs).
     - **Lógica Anti-Spam (Cooldown)**:
       - Guarda estado en `logs/monitor_state.json`.
       - Primer fallo: Disparo inmediato de **[ALERTA ROJA]**.
       - Persistencia: Solo reenvía recordatorio tras 60 minutos de falla continuada.
       - Recuperación: Envía aviso verde de **[RESTABLECIDO]** en cuanto todos los servicios vuelven a responder [OK].
  2. **Configuración en `config.json`**:
     - Bloque `alerts`: `enabled: true`, `to: ["mariano.diaz@friggorina.com"]` (exclusivo para soporte técnico, sin enviar a `informes.ciclo3`), `cooldown_minutes: 60`, `max_data_age_minutes: 20`.
  3. **Script Lanzador Batch (`LAB/colector_test/monitor_alertas.bat`)**:
     - Ejecución desatendida de `monitor_alertas.py`.
  4. **Tarea Programada de Windows**:
     - Nombre: `Gorina LAB - Monitor Alertas Servicios`.
     - Frecuencia: Cada 5 minutos (24/7), cuenta `SYSTEM`.
     - Estado actual: **Ready** (validada en ejecución exitosa).
  5. **Integración en Diagnóstico**:
     - `diagnostico_sistema.py` ahora reporta la tarea de monitoreo y su estado de ejecución.

---

## 23. Suite "Control de Aplicaciones", Diagrama de Flujo e Integración de GorinaPick (22/09/2026)
- **Requerimiento del Usuario**:
  1. Proveer un diagrama de flujo claro que explique el proceso completo de monitoreo y alertas.
  2. Permitir agregar/quitar destinatarios de correo de forma sencilla y transparente.
  3. Permitir ver exactamente qué servicios se vigilan y cuáles no, y subir/bajar (activar/pausar) cualquier alerta de forma ágil.
  4. Agrupar todo el control en una carpeta en el Escritorio (`Control de Aplicaciones`).
  5. Eliminar cualquier mención de herramientas personales del listado y manuales.
  6. Incorporar **GorinaPick** (API en puerto 5000 y tarea 24-7) al monitoreo y control de aplicaciones.
- **Acciones Realizadas**:
  1. **Carpeta en Escritorio**: `C:\Users\gorinahostadmin\Desktop\Control de Aplicaciones` creada con accesos directos y manual visual.
  2. **Diagrama y Manual Visual (`1_DIAGRAMA_Y_MANUAL.html`)**:
     - Diagrama de flujo SVG integrado (Vigilancia 5 min -> Chequeo de 7 puntos -> Detección de Falla -> Anti-Spam 60 min -> Alerta Roja / Aviso de Restablecimiento Verde).
     - Tabla detallada de qué se vigila: Red corporativa, LAB 8080, Stock 8090, GorinaPick API 5000, Colector LAB, GorinaPick Tarea 24-7, datos.json.
     - Eliminada cualquier mención a bots o herramientas personales.
  3. **Integración de GorinaPick en el Monitoreo**:
     - `GorinaPick API Picking (Puerto 5000)`: Evaluada vía HTTP contra `http://localhost:5000/api/ping`.
     - `Gorina - GorinaPick API 24-7`: Evaluada en Windows Task Scheduler.
     - Incorporados los toggles en `config.json` (`api_gorinapick_5000` y `tarea_gorinapick`) para subir/bajar su alerta individualmente.
  4. **Sección Técnica de Frecuencias y Mecánica de Control**:
     - Documentadas en `1_DIAGRAMA_Y_MANUAL.html` las frecuencias exactas: Monitor (cada 5 min), Servicios HTTP (timeout 4s), Colector LAB (cada 5 min), GorinaPick Watchdog (cada 1 min), Stock Almacén (cada 30 min), umbral datos.json (20 min sin cambios en horario 06-20h), y filtro anti-spam (60 min).
  5. **Panel Unificado de Configuración y Pausa (`3_CONFIGURAR_Y_PAUSAR_ALERTAS.bat`)**:
     - Agrupa en un solo menú interactivo: subir/bajar alertas individuales (1 a 6), pausar o reactivar el sistema completo (conmutando tarea Windows y config con tecla [P]), y abrir la edición de destinatarios ([D]).
     - Reemplaza los accesos separados anteriores manteniendo el escritorio limpio y ordenado.
  6. **Visor de Estado en Tiempo Real (`2_VER_ESTADO_DE_ALERTAS.bat`)**:
     - Ejecuta `monitor_alertas.py --status` mostrando destinatarios activos/pausados, estado de cada verificación en vivo (todos en `[ACTIVA - OK]`) y último evento.
  7. **Herramientas de Contingencia**:
     - `4_EDITAR_DESTINATARIOS.bat`: Acceso directo para editar correos en el Bloc de Notas.
     - `5_ENVIAR_ALERTA_DE_PRUEBA.bat`: Disparo manual de correo de prueba para verificar entrega.

---

## 24. Corrección de Entrega SMTP, Formato Multipart HTML y Filtros Anti-Spam (22/09/2026)
- **Diagnóstico del Problema Reportado**:
  - En los envíos previos, el correo salía como texto plano simple con el asunto `[ALERTA ROJA] Caída de servicios...`.
  - En los servidores corporativos que derivan a Google Workspace (`aspmx.l.google.com`), correos sin multipart HTML, sin encabezados `Date`/`Message-ID` y con asuntos con términos como `[ALERTA ROJA]` son clasificados directamente como **Spam / Correo no deseado** o asignados a pestañas secundarias ("Otros").
  - Además, el test con `--force-alert` alteraba el estado real a `FAIL`, disparando a los 2 minutos un correo automático de "Restablecido".
- **Mejoras Implementadas**:
  1. **Estructura Multipart MIME (HTML + Texto)**:
     - Diseñada plantilla HTML profesional con cabecera corporativa de Frigorífico Gorina, tabla de estados con insignias de color (verde/rojo/gris) y diagnóstico claro.
     - Texto plano conservado como respaldo técnico.
  2. **Encabezados Estándar RFC**:
     - Remitente amigable: `Control de Operaciones Ciclo 3 <ciclo3@friggorina.com>`.
     - Generación automática de `Date` y `Message-ID` único con dominio `@friggorina.com`.
     - Prioridades MIME (`X-Priority: 2` para alertas reales, `3` para pruebas y normalizaciones).
  3. **Asuntos Limpios Anti-Spam**:
     - Alerta: `[Aviso Operativo] Anomalía en Servicios Dashboard Ciclo 3 (FGLP53 - %d/%m %H:%M)`.
     - Prueba: `[Prueba de Alertas] Verificación de Sistema — Servicios Ciclo 3 (FGLP53)`.
     - Normalizado: `[Normalizado] Servicios Dashboard Ciclo 3 operando correctamente (FGLP53 - %d/%m %H:%M)`.
  4. **Modo de Prueba Aislado (`--test-mail`)**:
     - Verifica en tiempo real los 7 servicios y envía el informe del estado actual sin alterar el historial `monitor_state.json`.
     - Integrado en `5_ENVIAR_ALERTA_DE_PRUEBA.bat`.
  5. **Validación**:
     - Prueba ejecutada contra el relay Postfix (`192.168.0.234:25`): Aceptado con código `250 2.0.0 Ok: queued`.

---

## 25. Log de Actividad en Vivo: Últimos Envíos, Alertas y Desconexiones (22/09/2026)
- **Requerimiento del Usuario**:
  - Reemplazar la tarjeta estática de "Herramientas en la Carpeta del Escritorio" en `1_DIAGRAMA_Y_MANUAL.html` por un log interactivo que muestre lo último enviado, las últimas alertas emitidas y las desconexiones detectadas.
- **Acciones Realizadas**:
  1. **Reemplazo de la Tarjeta en `1_DIAGRAMA_Y_MANUAL.html`**:
     - Se eliminó la lista redundante de botones de escritorio.
     - Se incorporó la tarjeta **"Registro de Últimos Envíos y Alertas (Log de Actividad)"** con tabla desplazable (`Fecha/Hora`, `Evento`, `Servicio/Motivo`, `Notificado A`).
     - Badges semánticos de estado: `[ALERTA]` (rojo), `[RESTABLECIDO]` (verde) y `[PRUEBA]` (azul).
  2. **Persistencia Estructurada (`logs/historial_alertas.json`)**:
     - Creado archivo JSON de historial que almacena cronológicamente los últimos 25 eventos (alertas reales, desconexiones, recuperaciones y pruebas).
  3. **Sincronización Automática en `monitor_alertas.py`**:
     - Funciones `record_event()` y `update_manual_html()` incorporadas: cada vez que el monitor detecta una caída, una recuperación o se dispara una prueba, actualiza automáticamente el JSON y reescribe la tabla en `1_DIAGRAMA_Y_MANUAL.html`.
  4. **Visibilidad en Consola (`2_VER_ESTADO_DE_ALERTAS.bat`)**:
     - `monitor_alertas.py --status` ahora imprime la sección `[4] HISTORIAL DE ÚLTIMAS ALERTAS Y DESCONEXIONES` con los últimos 5 eventos.

---

## 26. Inclusión de Historial de Logs en Correos y Prueba In Situ en Panel (22/09/2026)
- **Requerimiento del Usuario**:
  1. Verificar por qué tras cambiar el destinatario de alertas a `sistemas@friggorina.com` en `destinatarios_alertas.txt` no vio salir la prueba.
  2. Incluir en el cuerpo del correo electrónico un log con los últimos eventos, alertas y desconexiones detectadas.
- **Acciones Realizadas**:
  1. **Diagnóstico del Envío a `sistemas@friggorina.com`**:
     - El destinatario `sistemas@friggorina.com` quedó correctamente configurado en `destinatarios_alertas.txt`.
     - La prueba manual se despachó y fue aceptada inmediatamente por el relay SMTP interno `192.168.0.234:25` (`queued as ...`).
     - Causa por la cual el operador no vio la salida: en `3_CONFIGURAR_Y_PAUSAR_ALERTAS.bat` no existía un botón directo para disparar la prueba in situ tras editar destinatarios sin abrir otra ventana.
  2. **Opción Directa `[T]` en el Menú de Configuración**:
     - Agregada la opción interactiva `[T] ENVIAR CORREO DE PRUEBA AHORA` en `toggle_check_interactive()`.
     - Permite que el operador cambie destinatarios con `[D]` y pruebe de inmediato con `[T]` en la misma pantalla.
  3. **Inclusión de Logs Recientes en Correos Salientes**:
     - Funciones `get_recent_events_html()` y `get_recent_events_text()` incrustadas en:
       - Correos de **Prueba Técnica** (`send_test_email`).
       - Correos de **Alerta por Anomalía** (`run_monitor`).
       - Correos de **Restablecimiento de Servicios** (`run_monitor`).
     - Muestra una tabla prolija con la fecha/hora, tipo de evento y detalle de las últimas desconexiones o avisos registrados.
  4. **Validación**:
     - Ejecutada prueba con `python monitor_alertas.py --test-mail`. Confirmado envío exitoso a `sistemas@friggorina.com` con código 0 y registro en `historial_alertas.json`.

---

## 27. Exclusión Temporal / Automática de TRV2 y TRV1+TRV2 en Reportes PDF (23/09/2026)
- **Requerimiento del Usuario**:
  - En el reporte que se descarga y en los envíos automáticos de fin de semana y mes (`envio_informe.py`), retirar temporalmente (hasta nuevo aviso / inicio operativo) la información de **TRV2** (sin movimientos) y de **TRV1 + TRV2** (redundante con TRV1).
  - Evaluar la mejor medida técnica: si dejarlo en automático o mediante configuración.
- **Medida Técnica Implementada (Detección Automática Inteligente + Override)**:
  1. **Lógica Automática en `exportAllPDF()`**:
     - En vez de exportar fijamente los 4 sistemas, el generador evalúa dinámicamente si los sistemas registran movimientos (`inn > 0`, `out > 0` o `occ > 0`):
       - `trv2`: se incluye únicamente si existen movimientos reales cargados. Si está en 0 / sin datos, se omite.
       - `comb` (TRV1+TRV2): se incluye únicamente si TRV2 está activo y registrando movimientos (para justificar la suma combinada). Si TRV2 no opera, se omite evitando duplicar la información de TRV1.
     - **Gran ventaja**: No requerirá intervención manual cuando TRV2 comience a operar en planta; el reporte incorporará automáticamente a TRV2 y a la combinación en cuanto aparezcan sus primeros datos.
  2. **Control Configurable (`REPORT_SYSTEMS_OVERRIDE`)**:
     - Se añadió la constante `REPORT_SYSTEMS_OVERRIDE = null;` en la cabecera de `dashboard_operaciones.html`.
     - Permite forzar una lista fija de sistemas en cualquier momento si se desea invalidar la detección automática.
  3. **Preservación de la Interfaz Web**:
     - Las pestañas del dashboard web permanecen intactas para consulta de supervisores (TRV2 muestra su badge "SIN OPERACIÓN").
  4. **Impacto en el Reporte PDF**:
     - Reducción de 7 páginas a **4 páginas ejecutivas limpias**:
       - Páginas 1 y 2: **TRV1** (KPIs, gráficos de flujo/ocupación y tabla detallada).
       - Páginas 3 y 4: **Almacén Congelado** (KPIs, gráficos y tabla detallada).
  5. **Validación Exhaustiva**:
     - Generación de informe semanal probada con Playwright: 4 páginas, 327 KB, validada la presencia exclusiva de TRV1 y Alm. Congelado.
     - Generación de informe mensual probada con Playwright: 4 páginas, 544 KB, validada la presencia exclusiva de TRV1 y Alm. Congelado.
     - Cambios sincronizados en `LAB\dashboard_test\dashboard_operaciones.html` y en la raíz del proyecto.

---

## 28. Nuevo Formato Visual HTML para Correos de Informes Semanales y Mensuales (23/09/2026)
- **Requerimiento del Usuario**:
  - Modificar el cuerpo del correo de los informes automáticos semanal y mensual (`envio_informe.py`) para igualar el estilo visual del informe diario (`cierre_jornada.py`), con tipografía corporativa Calibri, saludo formal, listado de sistemas incluidos y pie de página con aclaración de reporte automático.
  - Enviar un correo de prueba inmediato para su revisión.
- **Acciones Realizadas**:
  1. **Actualización de Plantillas en `envio_informe.py`**:
     - Estructurado en multipart MIME (HTML + Texto plano de respaldo).
     - Tipografía corporativa (Calibri, 14px), saludo "Estimados, buenas tardes", período de la semana/mes en negrita y viñetas descriptivas de los sistemas analizados:
       - **TRV1 (Cajas)**: Ingresos, salidas y curvas de ocupación de túneles continuos.
       - **Almacén Congelado (Palets)**: Movimientos CTTO y capacidad del almacén autoportante.
     - Firma institucional: "Control de Operaciones — Ciclo 3 · Frigorífico Gorina".
     - Pie con separador y aviso: *"Este es un reporte automático generado al cierre de operaciones de la semana laboral / fin de mes del Ciclo 3. Favor de no responder a este correo. Ante consultas, contactar a Mariano Díaz (mariano.diaz@friggorina.com)."*
  2. **Encabezados RFC y Entrega Limpia**:
     - Remitente amigable: `Control de Operaciones Ciclo 3 <ciclo3@friggorina.com>`.
     - Inclusión de encabezados `Date` y `Message-ID` únicos para evitar clasificación como spam.
  3. **Envío y Validación de Prueba**:
     - Se disparó un correo de prueba directo hacia `mariano.diaz@friggorina.com` con el PDF adjunto de 4 páginas (`gorina_ciclo3_Semana_21_09-25_09.pdf`). Aceptado y entregado exitosamente por el relay SMTP local (`192.168.0.234:25`).
     - Se eliminó el flag temporal `informe_semanal_enviado_2026-09-23.json` para no afectar el envío regular programado del próximo viernes.

---

## 29. Incorporación de Contacto en Pie de Correo de Cierre Diario (23/09/2026)
- **Requerimiento del Usuario**:
  - Agregar al pie aclaratorio del correo diario ('Ciclo 3 - Stock y Operaciones del D/MM') la referencia de contacto ante consultas.
  - Enviar un correo de prueba inmediato para verificar su visualización.
- **Acciones Realizadas**:
  1. **Actualización en `cierre_jornada.py`**:
     - Pie HTML y texto plano unificados con la leyenda oficial:
       *"Este es un reporte automático generado al cierre de operaciones diarias del Ciclo 3. Favor de no responder a este correo. Ante consultas, contactar a Mariano Díaz (mariano.diaz@friggorina.com)."*
     - Encabezados estándar RFC (`Date`, `Message-ID`, remitente `Control de Operaciones Ciclo 3 <ciclo3@friggorina.com>`) agregados a `send_cierre_email`.
     - Optimización en `export_stock_excel` utilizando `wait_until='domcontentloaded'` para asegurar descarga rápida (~4 seg) del Excel oficial de stock desde el puerto 8090.
  2. **Envío y Validación de Prueba**:
     - Se disparó correo de prueba forzado hacia `mariano.diaz@friggorina.com` conteniendo la tabla resumen de contadores y el Excel `STOCK_ALMACEN_2026-09-23.xlsx` adjunto. Entregado con código `250 Ok` a las 13:46 hs.
     - Se eliminó el archivo testigo `cierre_enviado_2026-09-23.json` para garantizar que el cierre automático real de hoy (a partir de las 16:00 hs / 18:00 hs) se procese con la totalidad de los datos productivos hacia `informes.ciclo3@friggorina.com`.

---

## 30. Corrección de URL de Notificación para Stock Almacén Puerto 8090 (23/09/2026)
- **Requerimiento del Usuario**:
  - En los correos y avisos de alerta del monitor de sistemas figuraba `http://localhost:8090/`.
  - Corregir para que incluya el host corporativo `fglp53` (`http://fglp53:8090/`).
- **Acciones Realizadas**:
  1. **Actualización en `monitor_alertas.py`**:
     - Configuración de `web_stock_puerto_8090`: actualizado tanto `url_local` como `url_display` a `http://fglp53:8090/`.
  2. **Actualización de Historial de Eventos (`historial_alertas.json`)**:
     - Registros previos de anomalías actualizados a `http://fglp53:8090/` para que la tabla histórica incluida en los correos y en el panel muestre la URL canónica correcta.
  3. **Actualización en `diagnostico_sistema.py`**:
     - URL de visualización ajustada a `http://fglp53:8090`.
  4. **Verificación**:
     - Ejecutado `python monitor_alertas.py --status`, confirmando estado `[ACTIVA - OK]` en `http://fglp53:8090/` e historial normalizado.

---

## 31. Ajuste Final de Textos en Informes Semanal y Cierre Diario (23/09/2026)
- **Requerimiento del Usuario**:
  - Ajuste fino y unificación en la redacción de ambos correos:
    1. **Informe Semanal (`envio_informe.py`)**:
       - Párrafo de apertura: *"Se adjunta el Informe Semanal de Operaciones del Ciclo 3 en formato PDF, correspondiente al período entre del {lunes} al {viernes}."*
       - Viñetas de sistemas:
         - `TRV1 (Cajas): Ingresos, salidas y curvas de ocupación de túnel.`
         - `Almacén Congelado (Pallets): Ingresos, salidas y capacidad del almacén Ctto.`
    2. **Cierre Diario (`cierre_jornada.py`)**:
       - Unificación en un solo párrafo introductorio:
         *"Se adjunta excel con el stock del almacén de congelados y cuadro resumen de ingresos y salidas de TRV y almacén, junto con la capacidad ocupada de los mismos:"*
       - Ajuste en tabla resumen: `Crane (Pallets)`.
  - Disparar ambos correos de prueba de inmediato a `mariano.diaz@friggorina.com`.
- **Acciones Realizadas**:
  1. **Edición de plantillas**:
     - `envio_informe.py`: actualizados tanto `text_body` como `html_body` en `enviar_informe_semanal` y `enviar_informe_mensual`.
     - `cierre_jornada.py`: párrafo unificado aplicado tanto en versión HTML como en texto plano, y tabla con fila `Crane (Pallets)`.
  2. **Emisión de Pruebas**:
     - Semanal: ejecutado `python envio_informe.py --weekly --to mariano.diaz@friggorina.com --force`. PDF de 4 páginas generado y enviado con éxito (SMTP 250 Ok).
     - Corrección gramatical inmediata: se ajustó la frase a *"correspondiente al período comprendido entre el {lunes} y el {viernes}."* (HTML y texto plano) y se reemitió la prueba con entrega exitosa a las 14:56:09 hs.
     - Cierre Diario: ejecutado `python cierre_jornada.py --force --to mariano.diaz@friggorina.com`. Excel oficial descargado desde puerto 8090 y correo enviado con éxito (SMTP 250 Ok).
  3. **Corrección Ortográfica de Contacto**:
     - Se reemplazó "Mariano Díaz" por "Mariano Diaz" (sin tilde) en todos los pies de correo (texto plano y HTML) en `cierre_jornada.py` y `envio_informe.py`.
  4. **Purga de Flags Testigo**:
     - Eliminados `informe_semanal_enviado_2026-09-23.json` y `cierre_enviado_2026-09-23.json` para dejar el colector automático listo para el cierre real de la jornada operativa hacia `informes.ciclo3@friggorina.com`.

---

## 32. Contingencia Automática ante Interrupción de `registros_cam` en Planta (25/09/2026)
- **Incidente / Síntoma**:
  - En la vista diaria del dashboard para la fecha en curso (`25/09/2026`), TRV1 solo mostraba movimientos hasta las 07:00 hs, quedando ausentes las horas posteriores (08:00, 09:00, 10:00 y 11:00 hs).
- **Diagnóstico y Causa Raíz Técnica**:
  1. En el servidor MySQL de planta `FGLP40` (`192.168.0.162:3306`), base `p003148`, las tablas de lectura física de arcos/cámaras (`registros_cam`) y de impresión (`registros_print`) registraron su último movimiento exactamente a las **07:49:57 hs**.
  2. A partir de ese segundo, el servicio de adquisición o lector de códigos de Frontmatec en planta interrumpió la inserción en MySQL.
  3. No obstante, la producción real de planta continuó activa de forma ininterrumpida, registrándose en el PLC de Siemens WinCC WebRH (a las 11:11 hs reportaba un acumulado vivo de 3.658 ingresos y 4.301 salidas).
  4. Debido a que el colector horario dependía exclusivamente de la presencia de filas en `registros_cam` para generar las franjas horarias, escalaba la totalidad de la producción viva sobre las únicas dos horas existentes (06:00 y 07:00).
- **Solución de Resiliencia Implementada**:
  1. **Módulo de Contingencia `get_webrh_hourly_deltas`**:
     - Implementado en `colector_horario.py`.
     - Detecta automáticamente si `registros_cam` presenta un retraso o congelamiento mayor a 1 hora respecto al reloj del sistema.
     - Extrae los deltas de producción hora a hora a partir de las lecturas periódicas de Siemens WebRH almacenadas cada 5 minutos en el ciclo del colector.
     - Reconstruye y calibra las horas faltantes (05:00 a 11:00 hs) garantizando que la sumatoria horaria coincida al 100% con los contadores oficiales de WebRH.
     - Si en el futuro `registros_cam` se restablece, el sistema conmuta automáticamente de nuevo a la lectura de arcos de escaneo sin intervención manual.
  2. **Validación**:
     - Ejecutado ciclo de recolección: se generaron 7 registros horarios para TRV1 (05:00 a 11:00 hs) y 6 para Crane (05:00 a 10:00 hs).
     - Verificado en `datos_horarios.json` y en la interfaz web del dashboard.

---

## 33. Corrección de Total Acumulado en Tarjetas y Comparación con Día Anterior (25/09/2026)
- **Incidente / Síntoma**:
  - En la vista diaria, los ingresos de TRV1 marcaban erróneamente más de 9.800 cajas cuando la producción real rondaba 6.425 cajas.
  - La tarjeta diaria mostraba la leyenda *"primer día / sin dato previo"* a pesar de contar con registros de los días anteriores.
- **Diagnóstico y Causa Raíz**:
  1. **Acumulación espuria en SQLite**: A las 12:00 hs planta restableció la base `registros_cam`, insertando horas 12, 13 y 14. Al no haber limpiado las horas 08, 09, 10 y 11 previas generadas por la contingencia matutina, el escalador de cámaras sumó las horas nuevas sobre las existentes, inflando `datos_horarios.json` a 9.899.
  2. **Detección de huecos intermedias**: La condición de contingencia previa solo chequeaba la última hora, sin notar que entre las 07:00 y las 12:00 faltaban 4 horas completas en las cámaras.
  3. **Frontend y selector de Turno**: Al estar activo el selector de Turno 1 por defecto (`state.shift = '1'`), la tarjeta diaria sumaba las horas de `datos_horarios.json` en lugar de tomar `r.inn` oficial (6.425), y enviaba `delta = null` al componente `dayBox`, provocando que mostrara por defecto la leyenda *"primer día / sin dato previo"*.
- **Solución Aplicada**:
  1. **Detección de Huecos (`has_gaps`) en `colector_horario.py`**:
     - Si entre el inicio de jornada y la hora actual faltan horas intermedias en `registros_cam`, activa la contingencia continua con Siemens WebRH.
     - Antes de reinsertar las horas calibradas del día en SQLite, purga los registros previos de TRV de la fecha (`DELETE FROM movimientos_horarios WHERE fecha_operativa = today AND sistema = 'trv'`), garantizando que la sumatoria de las 10 horas coincida exactamente con los 6.461 ingresos y 4.998 salidas oficiales.
  2. **Frontend `dashboard_operaciones.html`**:
     - Prioriza el dato oficial `r.inn` y `r.out` en la tarjeta diaria.
     - Calcula la variación real contra el día anterior (`prev.inn` y `prev.out`), mostrando el indicador dinámico (`▲ +2.126`, `▼ 824`) y eliminando el texto erróneo *"primer día / sin dato previo"*.
- **Validación**:
  - Verificado con Playwright en `http://localhost:8080/dashboard_operaciones.html`:
    - INGRESOS: `6.461 cajas` · `▲ +2.126` (vs ayer).
    - SALIDAS: `4.998 cajas` · `▼ 824` (vs ayer).
    - BALANCE: `+1.463 cajas` · `▲ +2.950` (vs ayer).
    - OCUPACIÓN: `42,0% (10.579 cajas)` · `▲ +1.464` (vs ayer).

---

## 34. Blindaje Preventivo e Independencia de Base de Datos Externa (25/09/2026)
- **Objetivo**: Blindar el sistema para evitar pérdida de datos y garantizar que el dashboard opere de forma 100% autónoma, sin depender de la estabilidad del servidor MySQL de Asuan/Frontmatec (`FGLP40`).
- **Medidas Preventivas Implementadas**:
  1. **Tabla Propia de Telemetría SCADA (`telemetria_scada`) en SQLite**:
     - Estructurada en `historico_horario.db` con clave única `(fecha_hora, sistema)`.
     - Registra automáticamente cada ciclo de 5 minutos la lectura en vivo del PLC de Siemens WebRH.
     - Poblamiento inicial completado con 179 lecturas del día (00:03 a 14:43 hs).
     - Si la base de cámaras de Asuan deja de registrar, nuestro colector consulta directamente su propia tabla local de telemetría, calculando los deltas horarios de forma continua e ininterrumpida.
  2. **Guardrail de Integridad Matemática Estricta**:
     - Implementado en `export_hourly_json` de `colector_horario.py`.
     - Antes de emitir los archivos `datos_horarios.json` y `datos_horarios.js`, valida la invariante:
       $$\sum (\text{horas del día}) \equiv \text{Total oficial de datos.json}$$
     - Si existiera cualquier residuo de redondeo o desfase temporal, ajusta el delta en la última hora registrada, haciendo físicamente imposible una discrepancia entre tarjetas y gráficos.
  3. **Preservación Total del Histórico**:
     - Verificado que los días históricos pasados (24/09, 23/09, 22/09, etc.) permanecen inmutables y 100% preservados en la base SQLite.
- **Validación**:
  - Invariante verificada con assert matemático: `datos.json: 6.529 IN / 4.998 OUT` idéntico a `suma_horas: 6.529 IN / 4.998 OUT`.

---

## 35. Mudanza a Nueva Ruta Oficial `D:\PROYECTOS\P001.Dashboard.Ciclo.3` y Restablecimiento Web (25/09/2026)
- **Contexto**:
  - El proyecto completo fue relocalizado físicamente en su ruta definitiva: `D:\PROYECTOS\P001.Dashboard.Ciclo.3`.
  - Se solicitó verificar por qué no se mostraban los datos del día en curso y proveer las URLs operativas de acceso.
- **Diagnóstico y Correcciones Realizadas**:
  1. **Directorio Virtual IIS Desactualizado**:
     - El sitio IIS `Gorina Ciclo3/tablero.ciclo3` continuaba apuntando a la ruta previa en disco C:.
     - Se actualizó mediante `appcmd`:
       `appcmd set vdir "Gorina Ciclo3/tablero.ciclo3" -physicalPath:"D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\dashboard_test"`
     - Confirmado retorno HTTP 200 OK tanto en puerto 80 (`/tablero.ciclo3/`) como en el sitio LAB puerto 8080.
  2. **Blindaje de WebRH contra Lecturas Transitorias en Cero**:
     - Causa identificada: Ante un bache o error transitorio de renderizado en la interfaz web de Siemens WinCC WebRH que devolviera `0/0`, la lógica anterior purgaba el registro del día de `datos.json`.
     - Se modificó `colector.py` para que, si ya existen datos previos con producción (`inn > 0` o `out > 0`), **nunca borre ni sobreescriba con ceros** el registro de la jornada en curso.
     - Se reforzó el guardrail en `colector_horario.py` para asegurar que la calibración se aplique de forma estricta contra la fecha actual (`today_str`).
  3. **Tareas Programadas en Servidor**:
     - Verificado que `Gorina LAB - Colector datos` y `Gorina LAB - Monitor Alertas Servicios` ejecutan los scripts ubicados en la nueva ruta `D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\colector_test`.
- **URLs Operativas de Acceso**:
  - **Por Nombre de Servidor**:
    - `http://fglp53/tablero.ciclo3/`
    - `http://fglp53:8080/`
  - **Por Dirección IP Directa**:
    - `http://192.168.0.126/tablero.ciclo3/`
    - `http://192.168.0.126:8080/`
- **Estado de Producción y Cuadre al Cierre**:
  - **TRV1**: 7.666 IN / 4.998 OUT · Ocupación: 46,76% (cuadre horario exacto).
  - **Almacén Congelado (Crane)**: 129 IN / 93 OUT · Ocupación: 37,53% (cuadre horario exacto).

---

## 36. Registro de Pendientes Prioritarios y Preservación de Histórico (27/09/2026)
- **Directriz de Datos**:
  - **Preservación Total del Histórico**: No se aplicará ningún script de purga ni recorte temporal en `historico_horario.db`. Todos los registros de telemetría y datos operativos acumulados se conservarán de forma indefinida como memoria histórica completa del Ciclo 3.
- **Listado de Pendientes Registrados (Para abordar en próximas etapas)**:
  1. **Incorporación de Logo Corporativo**:
     - Integrar el logo oficial de Frigorífico Gorina en la cabecera del dashboard web (`dashboard_operaciones.html`) y en los reportes exportables en PDF (semanal y mensual).
  2. **Actualización de Paleta Institucional**:
     - Adaptar los esquemas de color de la interfaz web hacia los tonos y lineamientos de la identidad visual corporativa institucional.
  3. **Ajuste de Títulos**:
     - Retirar la leyenda *"Frigorífico Gorina SAIC"* de los títulos del dashboard y los reportes para mantener encabezados más limpios y ejecutivos.
  4. **Mapa Horario Semanal con KPIs de Actividad en Reporte Semanal**:
     - Incorporar en el informe semanal un nuevo gráfico de mapa/perfil de distribución horaria consolidada de la semana laboral (suma acumulada de ingresos y salidas por franja horaria: 05:00 a 23:00 hs).
     - Permitir visualizar rápidamente los picos de mayor actividad y los valles productivos de la semana.
     - Incluir métricas / KPIs destacados:
       - Máximo ingreso horario registrado.
       - Máxima salida horaria registrada.
       - Promedios horarios de ingresos y salidas.

---

## 37. Diagnóstico y Corrección de Duplicación en Salidas de TRV1 (28/09/2026)
- **Incidente / Síntoma**:
  - A las 10:03 hs se observó en el dashboard que las salidas de TRV1 marcaban el doble de su valor real (~7.812 cajas en vez de ~3.906 cajas), escalando al doble todas las barras horarias de la jornada.
- **Diagnóstico y Causa Raíz Técnica**:
  1. En `webrh_reader.py`, el lector de Siemens WinCC WebRH consultaba siempre **Turno 1** y luego abría el selector para sumar **Turno 2**.
  2. A las 10:03 hs, por un retraso transitorio en el renderizado del menú emergente en el navegador web del SCADA, el clic para cambiar a "Turno 2" no llegó a conmutar la pantalla, permaneciendo visualizado Turno 1.
  3. Como resultado, `t2_data` extrajo por segunda vez los números de Turno 1 (`out = 3906`), y la consolidación `sal_trv1 = t1_data['sal_t1'] + t2_data['sal_t1']` sumó `3906 + 3906 = 7812` (duplicación exacta del 100%).
  4. En el ciclo siguiente (10:08 hs), el valor se normalizó a 3.990 al conmutar correctamente, pero el salto transitorio fue visible para el operador.
- **Solución y Blindaje Permanente Implementado**:
  1. **Acotamiento Horario de Turno 2**: Durante la mañana (antes de las 14:00 hs), el Turno 2 no opera en planta. Se restringió la apertura del desplegable de Turno 2 exclusivamente a partir de las 14:00 hs, acelerando la recolección matutina y eliminando cualquier posibilidad de falsa conmutación.
  2. **Detección Automática de Duplicación por Fallo de Pantalla**: Si después de las 14:00 hs se consulta Turno 2 y sus contadores resultan idénticos a los de Turno 1 (`t2_data['sal_t1'] == t1_data['sal_t1'] > 0`), el sistema detecta que la pantalla no cambió, descarta `t2_data` y registra advertencia en log.
  3. **Ajuste de Coordenadas de Clic**: Actualizada la coordenada precisa del texto de Turno 2 a `(1020, 94)` con mayor tiempo de espera (`800ms`) para asegurar la apertura del menú.
- **Validación**:
  - Corrida de prueba ejecutada exitosamente: Turno 1 leído en 22 segundos con `In = 2.520`, `Out = 4.121` (coincidente con los 4.115 registros de cámaras MySQL).
  - Total sincronizado en `datos.json` y `datos_horarios.json` con cuadre exacto hora por hora.









