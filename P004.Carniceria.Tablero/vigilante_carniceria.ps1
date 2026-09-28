# Vigilante y autorecuperaciÃ³n 24-7 para Tablero Carniceria Gorina
$scriptPath = "D:\PROYECTOS\P004.Carniceria.Tablero\servidor.py"
$workDir = "D:\PROYECTOS\P004.Carniceria.Tablero"
$pythonw = "C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\pythonw.exe"
$pingUrl = "http://localhost:8765/api/estado"
$logFolder = "D:\PROYECTOS\P004.Carniceria.Tablero\logs"

if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
}

function Test-ServerHealth {
    try {
        $resp = Invoke-RestMethod -Uri $pingUrl -Method Get -TimeoutSec 4 -ErrorAction Stop
        return ($resp.registros -gt 0)
    } catch {
        return $false
    }
}

$responde = Test-ServerHealth
if (-not $responde) {
    Start-Sleep -Seconds 2
    $responde = Test-ServerHealth
}

if (-not $responde) {
    # Liberar puerto 8765 si quedo un proceso colgado
    $puerto = Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue
    if ($puerto) {
        $puerto | ForEach-Object {
            Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    $intentos = 0
    while ($intentos -lt 5) {
        $ocupado = Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue
        if (-not $ocupado) { break }
        Start-Sleep -Seconds 1
        $intentos++
    }

    # Iniciar servidor silencioso en segundo plano con log
    $python = "C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe"
    $processClass = [wmiclass]"root\cimv2:Win32_Process"
    $startupParams = [wmiclass]"root\cimv2:Win32_ProcessStartup"
    $startupProps = $startupParams.CreateInstance()
    $startupProps.ShowWindow = 0
    $cmd = "cmd.exe /c `"`"$python`" `"$scriptPath`" >> `"$logFolder\servidor.log`" 2>&1`""
    $processClass.Create($cmd, $workDir, $startupProps) | Out-Null

    # Log de evento
    $logLine = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Tablero Carniceria reiniciado por vigilante.`r`n"
    Add-Content -Path "$logFolder\vigilante.log" -Value $logLine -ErrorAction SilentlyContinue
}
