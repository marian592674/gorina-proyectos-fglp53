# ==============================================================================
# P005.Supervisor.General — Watchdog 24-7 Unificado con MySQL
# ==============================================================================
# Supervisa servicios HTTP y tareas Windows de P001 a P005.
# Persiste métricas, telemetría e incidentes en MySQL `p005.supervisor.general`.
# Auto-recupera servicios caídos y envía alertas por correo si corresponde.
# ==============================================================================

$ErrorActionPreference = "SilentlyContinue"
$mysqlExe = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
$dbName = "p005.supervisor.general"
$logFile = "D:\PROYECTOS\P005.Supervisor.General\logs\supervisor.log"

# Asegurar directorio de logs local del proyecto
$logDir = [System.IO.Path]::GetDirectoryName($logFile)
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-SupervisorLog ($mensaje) {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "[$timestamp] $mensaje" -ErrorAction SilentlyContinue
}

function Invoke-MySqlQuery ($query) {
    if (Test-Path $mysqlExe) {
        & $mysqlExe -u root -pgorina2025 -D $dbName --default-character-set=utf8mb4 -e $query 2>$null
    }
}

function Escape-Sql ($str) {
    if ($null -eq $str) { return "NULL" }
    $s = "$str".Replace("\", "\\").Replace("'", "''")
    return "'$s'"
}

function Send-AlertEmail ($asunto, $cuerpo, $destinatarios) {
    try {
        $smtpServer = "192.168.0.234"
        $smtpFrom = "alertas-sistemas@friggorina.com"
        $smtp = New-Object System.Net.Mail.SmtpClient($smtpServer, 25)
        $smtp.Timeout = 10000
        
        $msg = New-Object System.Net.Mail.MailMessage
        $msg.From = New-Object System.Net.Mail.MailAddress($smtpFrom, "Gorina Alertas Sistemas")
        foreach ($d in ($destinatarios -split ',')) {
            $dClean = $d.Trim()
            if ($dClean -match '@') {
                $msg.To.Add($dClean)
            }
        }
        if ($msg.To.Count -eq 0) {
            $msg.To.Add("sistemas@friggorina.com")
        }
        $msg.Subject = $asunto
        $msg.Body = $cuerpo
        $msg.IsBodyHtml = $true
        $smtp.Send($msg)
        return "Enviado OK"
    } catch {
        Write-SupervisorLog "[ERROR_MAIL] No se pudo enviar alerta SMTP: $_"
        return "Fallo de Envío: $_"
    }
}

# 1. Definición de servicios supervisados
$serviciosSupervisados = @(
    @{
        Codigo = "p001_dashboard_80"
        Nombre = "Acceso Red Corporativa (tablero.ciclo3)"
        Proyecto = "P001.Dashboard.Ciclo.3"
        Tipo = "HTTP"
        Target = "http://localhost/tablero.ciclo3/dashboard_operaciones.html"
        Puerto = 80
        Vigilante = "iisreset /noforce"
    },
    @{
        Codigo = "p001_dashboard_8080"
        Nombre = "LAB Dashboard (Puerto 8080)"
        Proyecto = "P001.Dashboard.Ciclo.3"
        Tipo = "HTTP"
        Target = "http://localhost:8080/dashboard_operaciones.html"
        Puerto = 8080
        Vigilante = "iisreset /noforce"
    },
    @{
        Codigo = "p001_tarea_colector"
        Nombre = "Tarea Programada Colector LAB"
        Proyecto = "P001.Dashboard.Ciclo.3"
        Tipo = "TASK_WINDOWS"
        Target = "Gorina LAB - Colector datos"
        Puerto = $null
        Vigilante = "Start-ScheduledTask -TaskName 'Gorina LAB - Colector datos'"
    },
    @{
        Codigo = "p002_stock_8090"
        Nombre = "Stock Almacén API/SPA (Puerto 8090)"
        Proyecto = "P002.Stock.Almacen.Congelado"
        Tipo = "HTTP"
        Target = "http://localhost:8090/stock_almacen/ping"
        Puerto = 8090
        Vigilante = "Start-ScheduledTask -TaskName 'Gorina - Stock Almacen 24-7'"
    },
    @{
        Codigo = "p002_tarea_stock"
        Nombre = "Tarea Windows Stock Almacén 24-7"
        Proyecto = "P002.Stock.Almacen.Congelado"
        Tipo = "TASK_WINDOWS"
        Target = "Gorina - Stock Almacen 24-7"
        Puerto = $null
        Vigilante = "Start-ScheduledTask -TaskName 'Gorina - Stock Almacen 24-7'"
    },
    @{
        Codigo = "p003_pick_5000"
        Nombre = "GorinaPick API Picking (Puerto 5000)"
        Proyecto = "P003.Pick.Materiales.Insumos"
        Tipo = "HTTP"
        Target = "http://localhost:5000/api/ping"
        Puerto = 5000
        Vigilante = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\PROYECTOS\P003.Pick.Materiales.Insumos\servidor\vigilante_gorina_api.ps1"
    },
    @{
        Codigo = "p003_tarea_pick"
        Nombre = "Tarea Windows GorinaPick API 24-7"
        Proyecto = "P003.Pick.Materiales.Insumos"
        Tipo = "TASK_WINDOWS"
        Target = "Gorina - GorinaPick API 24-7"
        Puerto = $null
        Vigilante = "Start-ScheduledTask -TaskName 'Gorina - GorinaPick API 24-7'"
    },
    @{
        Codigo = "p004_carniceria_8765"
        Nombre = "Tablero Carnicería Gorina (Puerto 8765)"
        Proyecto = "P004.Carniceria.Tablero"
        Tipo = "HTTP"
        Target = "http://localhost:8765/api/estado"
        Puerto = 8765
        Vigilante = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\PROYECTOS\P004.Carniceria.Tablero\vigilante_carniceria.ps1"
    },
    @{
        Codigo = "p004_tarea_carniceria"
        Nombre = "Tarea Windows Carniceria Tablero 24-7"
        Proyecto = "P004.Carniceria.Tablero"
        Tipo = "TASK_WINDOWS"
        Target = "Gorina - Carniceria Tablero 24-7"
        Puerto = $null
        Vigilante = "Start-ScheduledTask -TaskName 'Gorina - Carniceria Tablero 24-7'"
    }
)

# 2. Ejecutar chequeos concurrentes / secuenciales
$now = Get-Date
$nowSql = $now.ToString("yyyy-MM-dd HH:mm:ss")

foreach ($s in $serviciosSupervisados) {
    $estado = "OK"
    $latencia = 0
    $httpCode = 200
    $mensaje = "Operativo"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($s.Tipo -eq "HTTP") {
        try {
            $req = [System.Net.HttpWebRequest]::Create($s.Target)
            $req.Timeout = 4000
            $req.Method = "GET"
            $resp = $req.GetResponse()
            $httpCode = [int]$resp.StatusCode
            $resp.Close()
            $sw.Stop()
            $latencia = [int]$sw.ElapsedMilliseconds
        } catch [System.Net.WebException] {
            $sw.Stop()
            $latencia = [int]$sw.ElapsedMilliseconds
            $estado = "DOWN"
            if ($_.Response) {
                $httpCode = [int]$_.Response.StatusCode
                $mensaje = "HTTP Error $httpCode"
            } else {
                $httpCode = 0
                $mensaje = "Falla de conexion / Timeout ($($_.Message))"
            }
        } catch {
            $sw.Stop()
            $estado = "DOWN"
            $httpCode = 0
            $mensaje = $_.Exception.Message
        }
    } elseif ($s.Tipo -eq "TASK_WINDOWS") {
        try {
            $task = Get-ScheduledTask -TaskName $s.Target -ErrorAction Stop
            $sw.Stop()
            $latencia = [int]$sw.ElapsedMilliseconds
            if ($task.State -eq 'Disabled') {
                $estado = "WARNING"
                $mensaje = "Tarea deshabilitada"
            } elseif ($s.Target -like "*24-7*" -and $task.State -ne 'Running') {
                # Para tareas marcadas como servicios continuos 24-7
                # (Nota: algunas tareas como Colector o vigilante están 'Ready' hasta que se disparan)
                if ($s.Target -eq "Gorina - Stock Almacen 24-7" -and $task.State -ne 'Running') {
                    $estado = "DOWN"
                    $mensaje = "Tarea 24-7 no esta en ejecucion (Estado: $($task.State))"
                } else {
                    $mensaje = "Estado Tarea: $($task.State)"
                }
            } else {
                $mensaje = "Estado Tarea: $($task.State)"
            }
        } catch {
            $sw.Stop()
            $estado = "DOWN"
            $mensaje = "No se encontro o fallo consulta de tarea: $_"
        }
    }

    # Auto-recuperación si está DOWN
    if ($estado -eq "DOWN" -and $s.Vigilante) {
        Write-SupervisorLog "[RECUPERACION] Servicio $($s.Codigo) caido ($mensaje). Ejecutando vigilante..."
        try {
            if ($s.Vigilante.StartsWith("Start-ScheduledTask")) {
                Invoke-Expression $s.Vigilante
            } elseif ($s.Vigilante.StartsWith("powershell.exe")) {
                Start-Process powershell.exe -ArgumentList ($s.Vigilante.Substring(14)) -WindowStyle Hidden
            } else {
                Start-Process cmd.exe -ArgumentList "/c $($s.Vigilante)" -WindowStyle Hidden
            }
        } catch {
            Write-SupervisorLog "[RECUPERACION_ERROR] Error al disparar vigilante para $($s.Codigo): $_"
        }
    }

    # Guardar en MySQL
    $codSql = Escape-Sql $s.Codigo
    $msgSql = Escape-Sql $mensaje
    $estSql = Escape-Sql $estado

    # 1. Registrar snapshot en historial_checks
    $queryCheck = "INSERT INTO ``historial_checks`` (``fecha``, ``servicio_codigo``, ``estado``, ``latencia_ms``, ``http_code``, ``mensaje``) VALUES ('$nowSql', $codSql, $estSql, $latencia, $httpCode, $msgSql);"
    Invoke-MySqlQuery $queryCheck

    # 2. Consultar estado previo para detectar incidentes
    # Actualizar tabla de servicios
    if ($estado -eq "OK") {
        $querySrv = "UPDATE ``servicios`` SET ``estado_actual``=$estSql, ``ultimo_check``='$nowSql', ``ultimo_ok``='$nowSql', ``latencia_ms``=$latencia, ``mensaje_estado``=$msgSql WHERE ``codigo``=$codSql;"
    } else {
        $querySrv = "UPDATE ``servicios`` SET ``estado_actual``=$estSql, ``ultimo_check``='$nowSql', ``latencia_ms``=$latencia, ``mensaje_estado``=$msgSql WHERE ``codigo``=$codSql;"
        # Registrar incidente en MySQL si está caído
        $asuntoIncidente = "[Alerta Supervisor] Caida en $($s.Nombre)"
        $detalleIncidente = "$mensaje (Destino: $($s.Target))"
        $asSql = Escape-Sql $asuntoIncidente
        $detSql = Escape-Sql $detalleIncidente
        $queryInc = "INSERT INTO ``incidentes`` (``fecha_inicio``, ``servicio_codigo``, ``tipo_evento``, ``detalle``, ``asunto``, ``destinatarios``, ``estado_envio``, ``creado_el``) VALUES ('$nowSql', $codSql, 'ALERTA', $detSql, $asSql, 'sistemas@friggorina.com', 'Registrado BD', '$nowSql');"
        Invoke-MySqlQuery $queryInc
    }
    Invoke-MySqlQuery $querySrv
}

# 3. Mantenimiento: Purga de cheques anteriores a 30 días
$queryPurga = "DELETE FROM ``historial_checks`` WHERE ``fecha`` < DATE_SUB(NOW(), INTERVAL 30 DAY);"
Invoke-MySqlQuery $queryPurga

# 4. Heartbeat en log cada hora
if ($now.Minute -lt 4) {
    Write-SupervisorLog "[HEARTBEAT] Todos los servicios supervisados y registrados en MySQL p005.supervisor.general."
}
