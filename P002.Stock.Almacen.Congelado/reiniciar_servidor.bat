@echo off
echo ===================================================
echo   REINICIANDO SERVICIO STOCK ALMACEN 24/7
echo ===================================================
powershell -Command "Stop-Process -Name ExportarStock -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; if (Test-Path 'Fuente A PROBAR\ExportarStock.exe') { Copy-Item 'Fuente A PROBAR\ExportarStock.exe' 'A PROBAR\ExportarStock.exe' -Force -ErrorAction SilentlyContinue }; Start-ScheduledTask -TaskName 'Gorina - Stock Almacen 24-7'; Start-Sleep -Seconds 2; Write-Host 'Estado:' (Get-ScheduledTask -TaskName 'Gorina - Stock Almacen 24-7').State"
echo Verificando respuesta HTTP en puerto 8090...
powershell -Command "try { $r = Invoke-RestMethod -Uri 'http://localhost:8090/ping' -TimeoutSec 3; Write-Host 'Servidor OK (ping: ' $r.ok ')' } catch { Write-Host 'Error de conexion' }"
echo ===================================================