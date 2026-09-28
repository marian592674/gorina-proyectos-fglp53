# Vigilante y autorecuperaciÃ³n 24-7 para Gorina.Api
$exePath = "D:\PROYECTOS\P003.Pick.Materiales.Insumos\servidor\publicar\Gorina.Api.exe"
$workDir = "D:\PROYECTOS\P003.Pick.Materiales.Insumos\servidor\publicar"
$pingUrl = "http://localhost:5000/api/ping"

function Test-ApiHealth {
    try {
        $resp = Invoke-RestMethod -Uri $pingUrl -Method Get -TimeoutSec 4 -ErrorAction Stop
        return ($resp.estado -eq "OK")
    } catch {
        return $false
    }
}

$responde = Test-ApiHealth
if (-not $responde) {
    # Reintento de confirmaciÃ³n para evitar falsos positivos por carga transitoria
    Start-Sleep -Seconds 2
    $responde = Test-ApiHealth
}

if (-not $responde) {
    # Detener instancias de Gorina.Api
    Get-Process -Name "Gorina.Api" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    
    # Esperar hasta que el puerto 5000 estÃ© liberado por el sistema operativo
    $intentosLiberacion = 0
    while ($intentosLiberacion -lt 5) {
        $puertoOcupado = Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue
        if (-not $puertoOcupado) { break }
        Start-Sleep -Seconds 1
        $intentosLiberacion++
    }

    # Iniciar proceso nuevo desacoplado
    $processClass = [wmiclass]"root\cimv2:Win32_Process"
    $startupParams = [wmiclass]"root\cimv2:Win32_ProcessStartup"
    $startupProps = $startupParams.CreateInstance()
    $startupProps.ShowWindow = 0
    $processClass.Create($exePath, $workDir, $startupProps) | Out-Null

    # Registrar evento en log de recuperaciÃ³n
    $logLine = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Gorina.Api no respondia, reiniciado por watchdog tras liberar puerto.`r`n"
    Add-Content -Path "D:\PROYECTOS\P003.Pick.Materiales.Insumos\servidor\watchdog.log" -Value $logLine -ErrorAction SilentlyContinue
}
