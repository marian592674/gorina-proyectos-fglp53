@echo off
chcp 65001 >nul
title Supervisor General 24-7 - Estado de Servicios e Incidentes
echo ==============================================================================
echo        FRIGORIFICO GORINA - SUPERVISOR GENERAL DE SERVICIOS (P005)
echo ==============================================================================
echo.
echo Consultando estado en tiempo real en base de datos `p005.supervisor.general`...
echo.

"C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe" -u root -pgorina2025 -D "p005.supervisor.general" -t -e "SELECT codigo, nombre, tipo, puerto, estado_actual, latencia_ms, ultimo_check, mensaje_estado FROM servicios ORDER BY codigo ASC;"

echo.
echo ------------------------------------------------------------------------------
echo HISTORIAL DE INCIDENTES RECIENTES:
echo ------------------------------------------------------------------------------

"C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe" -u root -pgorina2025 -D "p005.supervisor.general" -t -e "SELECT id, fecha_inicio, servicio_codigo, tipo_evento, detalle, estado_envio FROM incidentes ORDER BY id DESC LIMIT 10;"

echo.
echo ==============================================================================
echo Fin del reporte de estado.
echo ==============================================================================
