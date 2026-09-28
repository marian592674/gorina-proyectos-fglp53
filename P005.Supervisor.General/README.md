# P005.Supervisor.General — Watchdog y Monitoreo 24/7

Sistema centralizado de vigilancia técnica, auto-recuperación de servicios e historial de incidentes del servidor FGLP53.

## Accesos
* **Reporte y Diagrama Web:** `http://fglp53/tablero.ciclo3/1_DIAGRAMA_Y_MANUAL.html`
* **Consola Rápida:** `2_VER_ESTADO_DE_ALERTAS.bat`

## Base de Datos
* **MySQL 8.0 Local:** `127.0.0.1:3306`
* **Esquema:** `` `p005.supervisor.general` ``
* **Tablas Principales:** `servicios`, `incidentes`, `historial_checks`, `configuracion`.

## Vigilancia
* **Script Principal:** `supervisor_servicios_24-7.ps1`
* **Tarea Programada:** `Gorina - Supervisor General 24-7` (`AtStartup` + repetición cada 3 minutos).
