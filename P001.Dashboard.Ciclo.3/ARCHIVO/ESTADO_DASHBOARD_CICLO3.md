# Estado Dashboard Gorina Ciclo 3

> Archivo de seguimiento y registro de versiones del Dashboard Operaciones Ciclo 3 en VM (192.168.0.126).

---

## Actualización 09/09/2026 — Versión V1.1.4: Auto-refresco Automático 5 Minutos, Botón Normal y Alineación Superior

**Ubicaciones desplegadas:**
- PROD: `C:\Ciclo3\Servicios\DASHBOARD\PROD\dashboard` (IIS puerto 80)
- LAB: `C:\Ciclo3\Servicios\DASHBOARD\LAB\dashboard_test` (IIS puerto 8080)
- Backup: `C:\Ciclo3\Servicios\DASHBOARD\ARCHIVO\BACKUP_2026-09-09_DASHBOARD_AUTOREFRESH_5MIN`

### Ajustes incorporados en V1.1.4 (PROD & LAB):
1. **Separación de UX por proyecto:**
   - La funcionalidad de "Pill Al día / Aviso rojo pendiente" queda **exclusiva de Stock Almacén** (puerto 8090).
   - En **Dashboard Operaciones (PROD & LAB)** se retiró la pill interactiva y el botón bloqueante.
2. **Auto-refresco automático cada 5 minutos:**
   - La página se actualiza automáticamente cada 5 minutos en segundo plano (`setInterval(refreshData, 300000)`), sin requerir intervención del usuario.
   - También realiza control al recuperar el foco o cambiar de pestaña si ya transcurrieron 5 minutos.
3. **Leyenda de última actualización:**
   - A la izquierda de los botones se muestra el horario de actualización: `Actualizado HH:MMhs`, renovándose con cada ciclo de datos.
4. **Botón de actualización manual:**
   - Se restableció el botón estándar Gorina `↻ Actualizar datos`, siempre disponible y clickable bajo demanda.
5. **Alineación de cabecera:**
   - Los botones de la derecha (`⇩ Descargar informe` y `↻ Actualizar datos`) quedan a la misma altura exacta que los controles centrales (`Semana | Mes | Trimestre | Año`), desplazados ligeramente a la derecha.

---

## Actualización 09/09/2026 — Versión V1.1.3: Heartbeat, Polling HEAD, Anti-Caché IIS y Redondeo de Métricas

**Ubicaciones desplegadas:**
- PROD: `C:\Ciclo3\Servicios\DASHBOARD\PROD\dashboard` (IIS puerto 80)
- LAB: `C:\Ciclo3\Servicios\DASHBOARD\LAB\dashboard_test` (IIS puerto 8080)
- Backup: `C:\Ciclo3\Servicios\DASHBOARD\ARCHIVO\BACKUP_2026-09-09_AUTO_REFRESH_Y_CACHE`

### Mejoras incorporadas en V1.1.3:
1. **Detección Automática de Actualizaciones y Pill Inteligente (comportamiento unificado):**
   - Sondeo liviano HEAD sobre `datos.json` cada 15s (`Last-Modified` / `ETag`) y detección instantánea al enfocar o volver a la pestaña (`focus` y `visibilitychange`).
   - **Cuando está al día:** la pill muestra `● Al día · HH:MMhs` (verde) y el botón `✓ Al día`. Ninguno refresca al hacer clic para no interrumpir el trabajo ni congelar la pantalla.
   - **Cuando hay nuevos datos en el servidor:** la pill cambia dinámicamente a rojo vibrante parpadeante `🔔 Actualización disponible (HH:MMhs) — Refrescar` y el botón superior también se destaca en rojo `↻ Actualizar datos`.
   - **Un solo clic:** al hacer un clic sobre la pill roja o sobre el botón rojo, se actualizan los datos al instante, preservando la fecha y filtros seleccionados, y ambos elementos vuelven automáticamente al estado verde `● Al día`.
2. **Eliminación de decimales en métricas de cajas por día:**
   - Se corrigieron los formateadores de KPI para asegurar números enteros estrictos (`Math.round()` / `parseInt`) en todas las métricas de cajas (ingresos, salidas, stock), evitando valores con fracciones de caja.
3. **Control estricto de caché en IIS (`web.config`):**
   - Configuración de cabeceras HTTP en IIS para `no-cache, no-store, must-revalidate` y `Expires: -1` en `datos.json` y `dashboard_operaciones.html`.
4. **Visibilidad de versión:**
   - Badge identificador visible `V1.1.3` en la esquina inferior derecha del encabezado (junto al pie de navegación).

---

## 1. Qué hay hecho hasta ahora

### Proyecto original (cerrado)
- **Dashboard final:** `dashboard_operaciones.html` (113KB) + copia `final_version/dashboard_operaciones.html` — single HTML con Chart.js + jsPDF, estilo Gorina. Documentado en `PLAN_PROYECTO.md` (17 rondas).
- **Fuente actual:** Google Sheets `1Tme-57YZ3Zbj2-AgwrA1Ykp...` (GIDs `0`=TRV, `6245416`=Crane/Alm. Congelado). Datos embebidos hasta 03/08/2026.

### Sub-proyecto integrador_bds (preparado para VM)
- **Ubicación:** `integrador_bds/` — no toca el dashboard original.
- **Componentes:**
  - `colector/colector.py` — Etapa 1 `source=sheet` (Sheets CSV), Etapa 2 `source=sql` (pyodbc + vistas). Upsert por `k=YYYY-MM-DD`, escritura atómica `.tmp` + `.prev`, normaliza `occ` a 0-100.
  - `colector/config.json` — ya corregido a `out_path: C:/Ciclo3/Servicios/dashboard/datos.json`
  - `tablero_v4/dashboard_operaciones.html` — copia con `loadFromJSON()` (lee `datos.json` mismo origen) + fallback a Sheets + auto-refresh 5 min, + `web.config` para MIME `.json`
  - `tablero_v4/datos.json` — 18824 bytes de muestra (trv+crane)
  - `dba_entregables/` — `01_login_y_permisos.sql` (login `tablero_ro` RO), `02_vistas_trv.sql`, `03_vista_almacen.sql`, `LECTURA_DBA.md` (contrato `fecha, ingresos, salidas, ocupacion 0-100`)
  - `despliegue/` — `GUIA_DESPLIEGUE.md`, `CHECKLIST_VALIDACION.md`, BATs: `instala_iis_dashboard.bat`, `instala_tarea_colector.bat`, `valida_dashboard.bat`, `diagnostico_iis.bat`, `mostrar_ip.bat`
  - `PLAN_INTEGRACION.md` — hoja de ruta Fases A-D

### Despliegue en VM (Windows 10 Pro)
- **VM:** `192.168.0.126`, acceso por VPN + Radmin (desde tu casa)
- **Carpetas creadas (vos, punto 3 OK):**
  ```
  C:\Ciclo3\Servicios\dashboard\  -> dashboard_operaciones.html + datos.json + web.config (SITIO IIS)
  C:\Ciclo3\Servicios\colector\   -> colector.py + config.json + colector.bat + logs\ (FUERA del sitio, no expuesto)
  ```
  > `colector/` va **al lado** de `dashboard/`, no dentro — si va dentro queda expuesto por HTTP (`/colector/config.json` con password BD).
- **ZIP de despliegue:** `Gorina_Dashboard_Despliegue.zip` (61KB) en la raíz del proyecto — contiene todo lo anterior listo para copiar por Radmin File Transfer.

### Validación actual (30/08/2026 13:51)
`J:\valida_log.txt` (copia de `C:\Ciclo3\Servicios\dashboard\valida_log.txt`):
- [OK] Carpetas y archivos existen, `datos.json` válido (18824 B, claves trv/crane), `config.json` OK
- [OK] IIS W3SVC corriendo, sitio `Gorina Ciclo3` existe `http/*:80:` -> `C:\Ciclo3\Servicios\dashboard`
- [OK] Firewall `Dashboard Gorina` puerto 80, tarea `Gorina - Colector datos` existe y habilitada
- [FAIL] `Python: no se encontró Python` (alias Store, no instalado real)
- [FAIL] `colector --test` falla (sin Python)
- [FAIL] `http://localhost NO responde` — sitio creado pero no sirve
- IP VM: `192.168.0.126` -> URL objetivo `http://192.168.0.126/dashboard_operaciones.html`

---

## 2. Qué hay que arreglar AHORA (para que ande)

### A) IIS — HTTP localhost no responde (PRIORIDAD 1, no necesita Python)
Aunque el sitio existe, `http://localhost/dashboard_operaciones.html` no responde. Causas típicas en Win10 Pro: sitio detenido, AppPool parado, puerto 80 ocupado por Default Web Site/Skype, falta `iisreset`.

**Fix:**
1. `cmd Admin > %windir%\System32\inetsrv\appcmd.exe list site` y `list site "Gorina Ciclo3" /text:state` — debe decir `Started`
2. `appcmd start site /site.name:"Gorina Ciclo3"` + `appcmd start apppool /apppool.name:"Gorina Ciclo3"` + `iisreset`
3. Probar en VM: `http://localhost/dashboard_operaciones.html` y `http://localhost/datos.json` (si `datos.json` da 404.3, re-copiar `web.config`)
4. BAT diagnóstico: ejecutar `despliegue\diagnostico_iis.bat` como Admin — genera `diagnostico_iis_log.txt` con estado, bindings, netstat :80, tests a `localhost/127.0.0.1/192.168.0.126` y repara automático.

Sin esto nadie en LAN/VPN puede entrar, aunque el resto esté OK.

### B) Python — colector no corre (PRIORIDAD 2, no bloquea visualización)
`datos.json` ya existe (muestra estática), el dashboard se ve sin Python. Python solo hace falta para que se **actualice solo** cada 5 min.

**Fix:**
1. Descargar `python-3.12.x-amd64.exe` de python.org, instalar tildando **Add python.exe to PATH**
2. Desactivar alias Store: `Configuración > Aplicaciones > Alias de ejecución` -> off `python.exe`/`python3.exe`
3. `cmd > python --version` debe dar `3.12.x`, luego `cd C:\Ciclo3\Servicios\colector && python colector.py --test` -> `trv: N leídos`
4. Re-ejecutar `valida_dashboard.bat` — debe pasar a `TODO OK`

---

## 3. Cómo acceden todos (cuando IIS responda)

- **En la VM:** `http://localhost/dashboard_operaciones.html`
- **PC en LAN / tu PC con VPN:** `http://192.168.0.126/dashboard_operaciones.html`
- **Celular (misma WiFi):** misma URL
- **Casa (VPN + Radmin):** misma URL interna — nada expuesto a internet

Firewall ya está abierto para puerto 80. Si usás nombre DNS interno, cambiar `http://192.168.0.126` por `http://nombre-vm/`.

---

## 4. Planes futuros

### Fase B (ya en curso) — Validar con Sheets
- Correr `valida_dashboard.bat` hasta `TODO OK` y `CHECKLIST_VALIDACION.md` punto D (probar desde tu PC sin Radmin, solo VPN, + celular WiFi)

### Fase C — Conectar BDs productivas (cuando el DBA entregue)
- Entregar `dba_entregables/` al DBA: crea login `tablero_ro` + vistas `vw_tablero_trv1/vw_tablero_trv2` (TRV) y `vw_tablero_almacen` (Almacén). Contrato: una fila por día `fecha, ingresos, salidas, ocupacion 0-100`.
- En `C:\Ciclo3\Servicios\colector\config.json` completar `sql.servers` (IPs, BD, PWD `TrustServerCertificate=yes`) y `source: "sql"`, `pip install pyodbc` + ODBC Driver 18, `python colector.py --test` — histórico acumulado se mantiene, Sheets queda fuera.

### Fase C-alternativa — API en lugar de SQL directo
Si prefieren no abrir 1433, cada VM productiva expone `GET /api/tablero` y el colector pasa de `pyodbc` a `fetch HTTP`. Mismo `datos.json` final. Requiere desarrollar la API (Flask/FastAPI) — hoy no hace falta para 2 vistas.

### Fase D — Corte y mejoras
- Decidir corte: `C:\Ciclo3\Servicios\dashboard` pasa a ser el oficial, `final_version/` queda legado en `old/`
- (Opcional) Mail automático del PDF vía `colector.py` + SMTP
- Si hay más BDs (distintos motores), agregar entradas en `config.json` `sql.servers/views` o sumar APIs — arquitectura ya es multi-BD

---

## 5. Para seguir desde la VM con Opencode

1. **Instalar Opencode en la VM:** ver https://opencode.ai/docs — en Windows `npm i -g opencode` o bajar binario, luego `opencode --help`. Abrir la carpeta `C:\Ciclo3\Servicios\` o clonar el repo `Dhasboards` en la VM para tener el mismo proyecto.
2. **Qué copiar:** este archivo `ESTADO_DASHBOARD_CICLO3.md`, el ZIP `Gorina_Dashboard_Despliegue.zip` y la carpeta `integrador_bds/` si querés seguir iterando colector/tablero_v4 desde la VM (no hace falta copiar `old/` ni `PLAN_PROYECTO_INVERSIONES.md`).
3. **Desde la VM ya podés:** correr `valida_dashboard.bat`, `diagnostico_iis.bat`, `python colector.py`, `appcmd` y pedirle a Opencode que te genere FIX sin ir y venir por Radmin.

---

## 6. Archivos clave (rutas)

- Este estado: `C:\Users\mediaz\Desktop\Docs\Proyectos\Dhasboards\ESTADO_DASHBOARD_CICLO3.md` **<-- COPIAR ESTE A LA VM (ej: C:\Ciclo3\Servicios\dashboard\ESTADO.md)**
- ZIP despliegue: `C:\Users\mediaz\Desktop\Docs\Proyectos\Dhasboards\Gorina_Dashboard_Despliegue.zip`
- Config: `integrador_bds/colector/config.json:3` (`C:/Ciclo3/Servicios/dashboard/datos.json`)
- Guía: `integrador_bds/despliegue/GUIA_DESPLIEGUE.md`
- Checklist: `integrador_bds/despliegue/CHECKLIST_VALIDACION.md`
- Logs VM: `C:\Ciclo3\Servicios\colector\logs\colector.log` y `C:\Ciclo3\Servicios\dashboard\valida_log.txt` / `diagnostico_iis_log.txt`

> Última validación: `J:\valida_log.txt` 30/08/2026 13:51 — 2 FAIL (Python + HTTP). Próximo paso: `diagnostico_iis.bat` + instalar Python 3.12.
