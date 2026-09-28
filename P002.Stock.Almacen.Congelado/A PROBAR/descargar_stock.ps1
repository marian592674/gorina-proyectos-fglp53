# ─────────────────────────────────────────────────────────────
#  Stock Almacen Congelado - Script de Descarga Automatica
#  Descarga desatendida del CSV o consulta directa a la API de CTTO
#  y almacena el archivo con nomenclatura: lista_cajas_AAAA-MM-DD_HH-mm-ss.csv
#  Incluye rotacion y retencion automatica de archivos de stock
# ─────────────────────────────────────────────────────────────

param(
    [string]$Url = "",
    [string]$DestinoDir = "",
    [int]$TimeoutSeconds = 90,
    [switch]$SkipNotify
)

$baseDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$carpetaFile = Join-Path $baseDir "carpeta.json"

if (-not $DestinoDir) {
    if (Test-Path $carpetaFile) {
        try {
            $cfg = Get-Content $carpetaFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.carpeta -and (Test-Path -LiteralPath $cfg.carpeta)) { $DestinoDir = $cfg.carpeta }
            if (-not $Url -and $cfg.url_descarga) { $Url = $cfg.url_descarga }
        } catch {}
    }
}
if (-not $DestinoDir) {
    if (Test-Path (Join-Path $baseDir "STOCK")) {
        $DestinoDir = Join-Path $baseDir "STOCK"
    } elseif (Test-Path (Join-Path $baseDir "A PROBAR\STOCK")) {
        $DestinoDir = Join-Path $baseDir "A PROBAR\STOCK"
    } else {
        $DestinoDir = Join-Path $baseDir "STOCK"
    }
}
if (-not $Url) {
    # Default: API directa de CTTO 2.1 (Stacker 1)
    $Url = "http://fglp39v2:5000/stacker-1/api/boxes?page=1&limit=100000&storageStatus=stored"
}

if (-not (Test-Path -LiteralPath $DestinoDir -PathType Container)) {
    New-Item -ItemType Directory -Path $DestinoDir -Force | Out-Null
}

$logFile = Join-Path $baseDir "descargar_stock.log"
function Log([string]$msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    try { [System.IO.File]::AppendAllText($logFile, "$line`r`n", [System.Text.Encoding]::UTF8) } catch {}
    Write-Host $line
}

# ── Politica de Rotacion y Retencion de Archivos de Stock ──
function Rotar-ArchivosStock([string]$carpeta) {
    try {
        Log "Ejecutando mantenimiento y rotacion de archivos en: $carpeta"
        # 1. Limpiar temporales antiguos (.tmp de mas de 1 hora)
        Get-ChildItem -LiteralPath $carpeta -Filter "*.tmp" -File -ErrorAction SilentlyContinue | Where-Object {
            $_.LastWriteTime -lt (Get-Date).AddHours(-1)
        } | ForEach-Object {
            Log "Eliminando temporal huerfano: $($_.Name)"
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }

        # 2. Obtener todos los CSV de stock ordenados de mas reciente a mas antiguo
        $archivos = Get-ChildItem -LiteralPath $carpeta -Filter "lista_cajas_*.csv" -File -ErrorAction SilentlyContinue | 
                    Sort-Object LastWriteTime -Descending

        if (-not $archivos -or $archivos.Count -le 1) { return }

        $ahora = Get-Date
        $conservar = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # Regla 1: Conservar siempre el archivo mas reciente absoluto
        [void]$conservar.Add($archivos[0].FullName)

        # Regla 2: Conservar todos los archivos de las ultimas 24 horas (capturas cada 30 min)
        foreach ($arch in $archivos) {
            if ($arch.LastWriteTime -ge $ahora.AddHours(-24)) {
                [void]$conservar.Add($arch.FullName)
            }
        }

        # Regla 3: Para archivos entre 24 horas y 7 dias, conservar solo 1 snapshot por dia (el ultimo generado ese dia)
        $diasProcesados = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($arch in $archivos) {
            $antiguedadHoras = ($ahora - $arch.LastWriteTime).TotalHours
            if ($antiguedadHoras -gt 24 -and $arch.LastWriteTime -ge $ahora.AddDays(-7)) {
                $diaKey = $arch.LastWriteTime.ToString("yyyy-MM-dd")
                if (-not $diasProcesados.Contains($diaKey)) {
                    [void]$conservar.Add($arch.FullName)
                    [void]$diasProcesados.Add($diaKey)
                }
            }
        }

        # Regla 4: Borrar los archivos que no estan en la lista de conservados (mas viejos de 7 dias o intermedios > 24h)
        $borrados = 0
        foreach ($arch in $archivos) {
            if (-not $conservar.Contains($arch.FullName)) {
                Log "Rotacion: Purgando snapshot antiguo: $($arch.Name) ($([Math]::Round($arch.Length/1MB, 2)) MB)"
                Remove-Item $arch.FullName -Force -ErrorAction SilentlyContinue
                $borrados++
            }
        }

        # Regla 5: Tope absoluto de seguridad (maximo 50 archivos en carpeta)
        $restantes = Get-ChildItem -LiteralPath $carpeta -Filter "lista_cajas_*.csv" -File -ErrorAction SilentlyContinue | 
                     Sort-Object LastWriteTime -Descending
        if ($restantes.Count -gt 50) {
            for ($i = 50; $i -lt $restantes.Count; $i++) {
                Log "Tope de seguridad (max 50): Purgando $($restantes[$i].Name)"
                Remove-Item $restantes[$i].FullName -Force -ErrorAction SilentlyContinue
                $borrados++
            }
        }

        $totalRestantes = (Get-ChildItem -LiteralPath $carpeta -Filter "lista_cajas_*.csv" -File -ErrorAction SilentlyContinue).Count
        Log "Mantenimiento finalizado. Snapshots conservados: $totalRestantes, purgados: $borrados."
    } catch {
        Log "Aviso: no se pudo completar la rotacion de archivos: $($_.Exception.Message)"
    }
}

Log "Iniciando proceso de sincronizacion / descarga automatica..."
Log "Carpeta destino: $DestinoDir"

$ts = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
$finalFileName = "lista_cajas_$ts.csv"
$finalPath = Join-Path $DestinoDir $finalFileName
$tempPath = Join-Path $DestinoDir "lista_cajas_$ts.tmp"

try {
    if ($Url -like "*api/boxes*") {
        Log "Consultando API de stock CTTO: $Url"
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout = $TimeoutSeconds * 1000
        $req.UserAgent = "StockAlmacen-Downloader/2.0"
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $rawJson = $reader.ReadToEnd()
        $reader.Close()
        $stream.Close()
        $resp.Close()

        $dataObj = $rawJson | ConvertFrom-Json
        $boxes = $dataObj.data
        if (-not $boxes -or $boxes.Count -lt 1) {
            throw "La API de CTTO devolvio 0 registros de cajas almacenadas."
        }
        Log "Cajas recibidas de CTTO: $($boxes.Count) (Total en almacen: $($dataObj.totalRecords))"

        $sw = [System.IO.StreamWriter]::new($tempPath, $false, [System.Text.Encoding]::UTF8)
        $sw.WriteLine('"Box ID","SKU","Producto","Est. Elaborador","Est. Faenador","LPN Pallet","Conservación","Peso bruto (kg)","Peso neto (kg)","Producción","Vencimiento","Orden de venta","Reserva","Actualizado"')

        foreach ($b in $boxes) {
            $boxId = $b.boxId
            $sku = $b.sku
            $prodName = if ($b.product -and $b.product.itemDescription) { $b.product.itemDescription.Replace('"', '""') } else { "" }
            $estOfi = $b.estOfi
            $estFae = $b.estFae
            $lpn = $b.palletLpn
            $cons = $b.conservation
            $wGross = $b.weight
            $wNet = $b.netWeight
            $pDate = $b.productionDate
            $eDate = $b.expireDate
            $so = $b.salesOrder
            $res = $b.reservation
            $upd = $b.updatedAt

            $sw.WriteLine(('"{0}","{1}","{2}","{3}","{4}","{5}","{6}","{7}","{8}","{9}","{10}","{11}","{12}","{13}"' -f $boxId, $sku, $prodName, $estOfi, $estFae, $lpn, $cons, $wGross, $wNet, $pDate, $eDate, $so, $res, $upd))
        }
        $sw.Close()
    } else {
        Log "Descargando stream desde: $Url"
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout = $TimeoutSeconds * 1000
        $req.UserAgent = "StockAlmacen-Downloader/2.0"
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($tempPath)
        try {
            $stream.CopyTo($fs)
        } finally {
            $fs.Close()
            $stream.Close()
            $resp.Close()
        }
    }

    $fileSize = (Get-Item $tempPath).Length
    if ($fileSize -lt 1000) {
        throw "El archivo descargado es demasiado pequeno ($fileSize bytes)."
    }

    Move-Item -LiteralPath $tempPath -Destination $finalPath -Force
    Log "Descarga completada con exito: $finalFileName ($([Math]::Round($fileSize/1MB, 2)) MB)"

    # Ejecutar rotacion y retencion de archivos
    Rotar-ArchivosStock $DestinoDir

    # Notificar refresco al servidor local si esta activo y no se omitio
    if (-not $SkipNotify) {
        try {
            $html = (Invoke-WebRequest -Uri "http://localhost:8090/" -UseBasicParsing -TimeoutSec 3).Content
            $tokenMatch = [regex]::Match($html, '<meta\s+name="csrf-token"\s+content="([^"]+)">')
            if ($tokenMatch.Success) {
                $csrf = $tokenMatch.Groups[1].Value
                $refReq = [System.Net.HttpWebRequest]::Create("http://localhost:8090/refrescar")
                $refReq.Headers.Add("X-Local-Token", $csrf)
                $refReq.Timeout = 120000
                $refResp = $refReq.GetResponse()
                $stream = $refResp.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                while (-not $reader.EndOfStream) { [void]$reader.ReadLine() }
                $reader.Close()
                $refResp.Close()
                Log "Servidor notificado: stock en memoria actualizado exitosamente."
            }
        } catch {
            Log "Aviso: no se pudo notificar refresco al servidor local ($($_.Exception.Message))"
        }
    }

} catch {
    Log "ERROR en descarga: $($_.Exception.Message)"
    if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
    exit 1
}

exit 0
