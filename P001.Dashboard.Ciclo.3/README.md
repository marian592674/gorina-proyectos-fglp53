# P001.Dashboard.Ciclo.3 — Tablero de Operaciones Ciclo 3

Tablero web y sistema de monitoreo en tiempo real de desposte, rendimiento y producción del sector Ciclo 3 en Frigorífico Gorina.

## Accesos
* **Producción:** `http://fglp53/tablero.ciclo3/dashboard_operaciones.html` (Puerto 80 / IIS)
* **Laboratorio:** `http://fglp53:8080/dashboard_operaciones.html` (Puerto 8080 / IIS)

## Base de Datos
* **MySQL 8.0 Local:** `127.0.0.1:3306`
* **Esquema:** `` `p001.dashboard.ciclo.3` ``

## Componentes
* **Servidor Web:** IIS 10 (Servicio Windows `W3SVC`).
* **Colector de Datos:** Tarea programada `Gorina LAB - Colector datos` (Python 3.12).
