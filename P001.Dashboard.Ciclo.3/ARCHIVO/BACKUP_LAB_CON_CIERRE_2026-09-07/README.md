# Entorno LAB (Gorina Dashboard Ciclo 3)

## 1. Acceso y URLs
* **Dashboard LAB**: `http://192.168.0.126:8080/dashboard_operaciones.html`
* **Directorio Web**: `C:\Ciclo3\Servicios\DASHBOARD\LAB\dashboard_test\`
* **Colector y Scripts**: `C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\`
* **Archivos generados**: `datos.json` y `datos.js` (soporte `file://` local).

---

## 2. Fuentes de Datos (Modo Híbrido Automático en Tiempo Real)
* **TRV1 y TRV2 (Histórico)**: MySQL `192.168.0.162:3306` (Base `p003148`, usuario `TABLERO_RO`).
* **TRV1 y TRV2 (En vivo hoy)**: **Siemens WinCC Unified Runtime (WebRH)** (`https://192.168.196.36/device/WebRH`), suma automática de Turno 1 y Turno 2 sin retención de sesión.
* **Almacén Congelado (`crane`)**: **CTTO 2.1 API REST** (`http://fglp39v2:5000/stacker-1/api/operations/metrics/summary`).
* **Google Sheets**: Totalmente desactivado en LAB.

---

## 3. Automatización
* **Tarea en Programador de Tareas**: `Gorina LAB - Colector datos`
* **Frecuencia**: Cada 5 minutos (`PT5M`), 24/7 en segundo plano.
* **Comando**: `C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\colector.bat`
* **Flujo**:
  1. `colector.py`: actualiza `datos.json` desde MySQL, CTTO 2.1 y Siemens WebRH.
  2. `cierre_jornada.py`: a partir de las 16:00 hs, vigila 15 min de inactividad, genera el Excel de stock desde `http://localhost:8090` y envía el correo diario de cierre con la tabla calculada.

---

## 4. Pruebas Manuales
Para probar una corrida del colector sin escribir:
```cmd
cd /d C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test
python colector.py --test
```
Para probar el correo de cierre diario (simulación sin envío):
```cmd
python cierre_jornada.py --test
```
Para forzar el envío del correo de cierre a una casilla puntual:
```cmd
python cierre_jornada.py --force --to mariano.diaz@friggorina.com
```
O para ejecutar la corrida completa en caliente:
```cmd
colector.bat
```


