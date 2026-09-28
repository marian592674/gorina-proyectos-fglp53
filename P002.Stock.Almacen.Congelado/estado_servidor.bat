@echo off
echo ===================================================
echo   ESTADO SERVICIO STOCK ALMACEN (VM FGLP53 :8090)
echo ===================================================
powershell -Command "$t = Get-ScheduledTask -TaskName 'Gorina - Stock Almacen 24-7' -ErrorAction SilentlyContinue; Write-Host 'Tarea programada:' $t.State; $p = Get-Process ExportarStock -ErrorAction SilentlyContinue; if ($p) { Write-Host 'Proceso PID:' $p.Id 'Inicio:' $p.StartTime } else { Write-Host 'Proceso: NO ACTIVO' }; try { $r = Invoke-RestMethod -Uri 'http://localhost:8090/ping' -TimeoutSec 3; Write-Host 'Respuesta HTTP 8090: OK' } catch { Write-Host 'Respuesta HTTP 8090: ERROR' }"
echo ---------------------------------------------------
echo URL local:   http://localhost:8090/
echo URL red IP:  http://192.168.0.126:8090/
echo URL nombre:  http://fglp53:8090/
echo ===================================================