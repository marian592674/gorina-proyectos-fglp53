# ─────────────────────────────────────────────────────────────
#  Stock Almacen Congelado - Exportador con servidor local
#  Levanta un servidor HTTP local, abre el HTML al instante y
#  sirve los datos con barra de progreso en tiempo real.
# ─────────────────────────────────────────────────────────────

$baseDir = if ($PSScriptRoot) { $PSScriptRoot }
           elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
           else { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$exeMode = ($Host.Name -ne 'ConsoleHost')

# ── Workspace oculto ──
# Todos los archivos internos (assets, logs, catalogo cache, archivo historico)
# viven en %LOCALAPPDATA%\StockAlmacenCongelado. El EXE queda como un solo
# archivo publico y no ensucia el Escritorio con archivos sueltos.
$localApp = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE "AppData\Local" }
$workDir = Join-Path $localApp "StockAlmacenCongelado"
if (-not (Test-Path -LiteralPath $workDir -PathType Container)) {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    try { (Get-Item -LiteralPath $workDir -Force).Attributes = [System.IO.FileAttributes]::Directory -bor [System.IO.FileAttributes]::Hidden } catch {}
}

$carpetaFile = Join-Path $baseDir "carpeta.json"
$datosDir = Join-Path $baseDir "STOCK"
$serverPort = 8080
$capaDir = if (Test-Path -LiteralPath "J:\UTIL\USER\CAPA" -PathType Container) { "J:\UTIL\USER\CAPA" } else { "\\svr\d\UTIL\USER\CAPA" }
if (Test-Path $carpetaFile) {
    try {
        $cfg = Get-Content $carpetaFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.carpeta -and (Test-Path -LiteralPath $cfg.carpeta -PathType Container)) { $datosDir = $cfg.carpeta }
        if ($cfg.puerto) { $serverPort = [int]$cfg.puerto }
        if ($cfg.carpeta_rs -and (Test-Path -LiteralPath $cfg.carpeta_rs -PathType Container)) { $capaDir = $cfg.carpeta_rs }
        elseif ($cfg.capa -and (Test-Path -LiteralPath $cfg.capa -PathType Container)) { $capaDir = $cfg.capa }
    } catch {}
}
$analisisManualFile = Join-Path $baseDir "analisis_manual.json"
$historicoCajasFile = Join-Path $workDir "historico_cajas.json"
$cargasHistorialFile = Join-Path $baseDir "cargas_historial.json"
$romaneosResumenFile = Join-Path $baseDir "romaneos_resumen.json"
$script:lastRomaneosSync = [datetime]::MinValue
if (-not (Test-Path -LiteralPath $analisisManualFile -PathType Leaf)) {
    try {
        @{ pallets = @(); cajas = @() } | ConvertTo-Json | Set-Content -LiteralPath $analisisManualFile -Encoding UTF8
    } catch {}
}
if (-not (Test-Path -LiteralPath $cargasHistorialFile -PathType Leaf)) {
    try {
        @() | ConvertTo-Json | Set-Content -LiteralPath $cargasHistorialFile -Encoding UTF8
    } catch {}
}
$excelPath = Join-Path $workDir "Stock.Almacen.Base.xlsx"
$outDir = $workDir
$logFile = Join-Path $workDir "exportar_stock.log"
$catalogoJson = Join-Path $workDir "catalogo.json"
$archivoDir = Join-Path $workDir "archivo"
$templatePath = Join-Path $workDir "index.template.html"
$exceljsPath = Join-Path $workDir "exceljs.min.js"

if (-not (Test-Path $archivoDir)) { New-Item -ItemType Directory -Path $archivoDir -Force | Out-Null }

$ErrorActionPreference = 'Stop'

$script:exportStream = $null
$script:carpetaRs = $null
$global:csvSeleccionado = $null
$global:cachedPayload = $null
$global:cachedPayloadJson = $null
$global:cachedCsvName = $null
$global:isSyncing = $false
$global:syncStartTime = $null
$global:lastSyncTime = $null

# Token CSRF para validar peticiones de la pagina (generado en cada inicio del servidor)
$script:csrfToken = [Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Maximum 256 }))

function Log([string]$msg) {
    try { [System.IO.File]::AppendAllText($logFile, "$msg`r`n", [System.Text.Encoding]::UTF8) } catch {}
}

# Se intenta materializar desde el paquete embebido mas abajo; si aun asi falta, PASO 1 lo reporta.
if (-not (Test-Path -LiteralPath $excelPath -PathType Leaf)) {
    Log "WARN: Stock.Almacen.Base.xlsx no encontrado en $workDir (se intentara materializar)"
}

# ── Assets embebidos (el paquete compilado funciona como un solo archivo) ──
$script:htmlB64 = @'
@@HTML_B64@@
'@
$script:exceljsB64 = @'
@@EXCELJS_B64@@
'@
$script:xlsxB64 = @'
@@XLSX_B64@@
'@
$script:catalogoB64 = @'
@@CATALOGO_B64@@
'@

function Get-B64OrNull([string]$b64) {
    if ($b64 -and $b64 -notmatch '@@') {
        try { return [Convert]::FromBase64String($b64) } catch {}
    }
    return $null
}

$script:htmlBytes = Get-B64OrNull $script:htmlB64
$script:exceljsBytes = Get-B64OrNull $script:exceljsB64
$script:xlsxBytes = Get-B64OrNull $script:xlsxB64
$script:catalogoBytes = Get-B64OrNull $script:catalogoB64

# ── Materializacion de assets en el workspace oculto ──
# Se escriben solo si faltan o si el paquete embebido cambio (EXE actualizado).
# Asi un EXE nuevo reemplaza assets viejos, pero un EXE igual no toca los
# archivos y se conserva el cache de catalogo y sus timestamps.
function Asset-FaltaOdistinto([string]$path, [byte[]]$bytes) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $true }
    try {
        $existing = [System.IO.File]::ReadAllBytes($path)
        if ($existing.Length -ne $bytes.Length) { return $true }
        return -not [System.Linq.Enumerable]::SequenceEqual([byte[]]$existing, [byte[]]$bytes)
    } catch { return $true }
}

foreach ($asset in @(
    @{ path = $templatePath;  bytes = $script:htmlBytes;     siempre = $true },
    @{ path = $exceljsPath;   bytes = $script:exceljsBytes;  siempre = $true },
    @{ path = $excelPath;     bytes = $script:xlsxBytes;     siempre = $true },
    @{ path = $catalogoJson;  bytes = $script:catalogoBytes; siempre = $true }
)) {
    $necesita = if ($asset.siempre) { Asset-FaltaOdistinto $asset.path $asset.bytes }
                else { -not (Test-Path -LiteralPath $asset.path -PathType Leaf) }
    if ($asset.bytes -and $necesita) {
        try {
            [System.IO.File]::WriteAllBytes($asset.path, $asset.bytes)
            Log "Materializado desde paquete: $($asset.path)"
        } catch { Log "ERROR materializando $($asset.path): $($_.Exception.Message)" }
    }
}

# ── Utilidades HTTP ──
function Read-HttpLine([System.Net.Sockets.NetworkStream]$s) {
    $sb = New-Object System.Text.StringBuilder
    $buf = New-Object byte[] 1
    while ($true) {
        $n = $s.Read($buf, 0, 1)
        if ($n -le 0) { if ($sb.Length -gt 0) { break } else { return $null } }
        $c = [char]$buf[0]
        if ($c -eq "`n") { break }
        if ($c -ne "`r") { [void]$sb.Append($c) }
        if ($sb.Length -gt 8192) { break }
    }
    return $sb.ToString()
}

function Send-Simple([System.Net.Sockets.NetworkStream]$s, [int]$status, [string]$contentType, [byte[]]$body) {
    $reason = switch ($status) { 200 {'OK'} 404 {'Not Found'} default {''} }
    $head = "HTTP/1.1 $status $reason`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $s.Write($hb, 0, $hb.Length)
    if ($body.Length -gt 0) { $s.Write($body, 0, $body.Length) }
    $s.Flush()
}

function Send-Text([System.Net.Sockets.NetworkStream]$s, [int]$status, [string]$contentType, [string]$text) {
    Send-Simple $s $status $contentType ([System.Text.Encoding]::UTF8.GetBytes($text))
}

function Send-File([System.Net.Sockets.NetworkStream]$s, [string]$path, [string]$contentType) {
    if (-not (Test-Path $path)) { Send-Text $s 404 'text/plain' 'Not found'; return }
    $len = (Get-Item $path).Length
    $head = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $len`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $s.Write($hb, 0, $hb.Length)
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $buf = New-Object byte[] 65536
        while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
            $s.Write($buf, 0, $n); $s.Flush()
        }
    } finally { $fs.Close() }
    $s.Flush()
}

function Send-Bytes([System.Net.Sockets.NetworkStream]$s, [string]$contentType, [byte[]]$bytes) {
    if (-not $bytes -or $bytes.Length -eq 0) { Send-Text $s 404 'text/plain' 'Not found'; return }
    $head = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $s.Write($hb, 0, $hb.Length)
    $s.Write($bytes, 0, $bytes.Length)
    $s.Flush()
}

function Write-ChunkedHeaders([System.Net.Sockets.NetworkStream]$s) {
    $head = "HTTP/1.1 200 OK`r`nContent-Type: text/plain; charset=utf-8`r`nTransfer-Encoding: chunked`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $s.Write($hb, 0, $hb.Length)
    $s.Flush()
}

function Send-Chunk([System.Net.Sockets.NetworkStream]$s, [string]$text) {
    if (-not $s) { return }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        if ($bytes.Length -gt 0) {
            $chunkHead = [System.Text.Encoding]::ASCII.GetBytes(('{0:X}' -f $bytes.Length) + "`r`n")
            $s.Write($chunkHead, 0, $chunkHead.Length)
            $offset = 0
            $bufSize = 65536
            while ($offset -lt $bytes.Length) {
                $count = [Math]::Min($bufSize, $bytes.Length - $offset)
                $s.Write($bytes, $offset, $count)
                $offset += $count
            }
            $s.Write([System.Text.Encoding]::ASCII.GetBytes("`r`n"), 0, 2)
            $s.Flush()
        }
    } catch {
        # Si el socket se cerro, desacoplar stream para que Run-Export continue en segundo plano y guarde cache
        $script:exportStream = $null
    }
}

function Send-TerminalChunk([System.Net.Sockets.NetworkStream]$s) {
    if (-not $s) { return }
    try {
        $s.Write([System.Text.Encoding]::ASCII.GetBytes("0`r`n`r`n"), 0, 5)
        $s.Flush()
    } catch {
        $script:exportStream = $null
    }
}

function Start-Stream([System.Net.Sockets.NetworkStream]$s) {
    $script:exportStream = $s
    Write-ChunkedHeaders $s
}

function Send-ErrorLine([string]$msg) {
    Log "ERROR: $msg"
    if ($script:exportStream) {
        Send-Chunk $script:exportStream "ERROR:$msg`n"
        Send-TerminalChunk $script:exportStream
    }
}

# ── Progreso ──
function Send-Progress([int]$pct, [string]$label) {
    Log $label
    if (-not $exeMode) { Write-Host $label }
    if ($script:exportStream) {
        try {
            Send-Chunk $script:exportStream "PASO:$($pct):$($label)`n"
        } catch {
            $script:exportStream = $null
        }
    }
}

trap {
    $errMsg = "ERROR: $($_.Exception.Message)"
    Log ""
    Log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    Log $errMsg
    if ($_.ScriptStackTrace) { Log $_.ScriptStackTrace }
    Log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    # Errores esperados (CSV faltante/ocupado/mal formato): NO se muestra
    # MessageBox nativo; se ven en la pagina via Send-ErrorLine. La ventana
    # queda solo para errores realmente inesperados.
    $esperados = @(
        'No hay archivos lista_cajas_',
        'no tiene el formato esperado',
        'no tiene filas de datos',
        'Todos los CSV estan en uso',
        'esta en uso (siendo escrito)'
    )
    $esEsperado = $false
    foreach ($p in $esperados) { if ($errMsg -like "*$p*") { $esEsperado = $true; break } }
    if (-not $exeMode) {
        Write-Host ""
        Write-Host $errMsg
        Read-Host "`nPresione Enter para cerrar..."
    } elseif (-not $esEsperado) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($errMsg, 'Stock Almacen Congelado', 'OK', 'Error') | Out-Null
    }
    exit 1
}

# ── Archivar log anterior ──
if (Test-Path $logFile) {
    $logTs = (Get-Date).ToString("yyyyMMdd_HHmmss")
    Copy-Item $logFile (Join-Path $archivoDir "exportar_stock_$logTs.log") -Force
    Remove-Item $logFile -Force
}

Log ""
Log "========================================"
Log " INICIO: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Log "========================================"
Log "Base dir: $baseDir"
Log "Excel path: $excelPath"
Log "Carpeta de busqueda: $datosDir"

# ── Utilidades de datos ──
# Acepta el nombre base y variantes comunes al descargar/reenviar por WhatsApp:
#   lista_cajas_2026-08-03_11-38-15.csv
#   lista_cajas_2026-08-03_11-38-15.csv.csv
#   lista_cajas_2026-08-03_11-38-15 (1).csv
#   lista_cajas_2026-08-03_11-38-15.csv (1).csv
#   lista_cajas_2026-08-03_11-38-15 (2).csv.csv
function Test-StockCsvName([string]$name) {
    return ($name -match '^lista_cajas_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}((\s*\(\d+\))?\.csv)+$')
}

$script:carpetaFgCs = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Fg {
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_SHOWWINDOW = 0x0040;
    private const int SW_RESTORE = 9;
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOPMOST = 0x00000008;
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    public static bool IsTopmost(IntPtr hwnd) {
        return (GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
    }
    public static void ForceForeground(IntPtr hwnd) {
        IntPtr fg = GetForegroundWindow();
        uint thisThread = GetCurrentThreadId();
        uint fgThread = 0;
        if (fg != IntPtr.Zero) GetWindowThreadProcessId(fg, out fgThread);
        bool attached = false;
        if (fgThread != 0 && fgThread != thisThread) { AttachThreadInput(thisThread, fgThread, true); attached = true; }
        ShowWindow(hwnd, SW_RESTORE);
        BringWindowToTop(hwnd);
        SetForegroundWindow(hwnd);
        if (attached) AttachThreadInput(thisThread, fgThread, false);
    }
    public static void MakeTopmost(IntPtr hwnd) {
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
    }
    public static void EnsureDialogTopmost(int myPid) {
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            uint p;
            GetWindowThreadProcessId(hWnd, out p);
            if (p == (uint)myPid) {
                StringBuilder c = new StringBuilder(64);
                GetClassName(hWnd, c, 64);
                if (c.ToString() == "#32770" && IsWindowVisible(hWnd)) {
                    if (!IsTopmost(hWnd)) {
                        SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
                    }
                    DisableTransitions(hWnd);
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
    }
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    private const int DWMWA_TRANSITIONS_FORCEDISABLED = 3;
    public static void DisableTransitions(IntPtr hwnd) {
        try {
            int disabled = 1;
            DwmSetWindowAttribute(hwnd, DWMWA_TRANSITIONS_FORCEDISABLED, ref disabled, sizeof(int));
        } catch {}
    }
    [DllImport("dwmapi.dll")] private static extern int DwmFlush();
    [DllImport("user32.dll")] private static extern bool RedrawWindow(IntPtr hWnd, IntPtr lprcUpdate, IntPtr hrgnUpdate, uint flags);
    private const uint RDW_INVALIDATE = 0x0001;
    private const uint RDW_ERASE = 0x0002;
    private const uint RDW_ALLCHILDREN = 0x0004;
    private const uint RDW_UPDATENOW = 0x0100;
    public static void FlushScreen() {
        try { DwmFlush(); } catch {}
        try { RedrawWindow(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW); } catch {}
    }
}
'@

$script:carpetaWarmScript = @'
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
'@

try { Add-Type -TypeDefinition $script:carpetaFgCs | Out-Null; Log "Helper de foco (Fg) compilado" } catch { Log "ERROR compilando Fg: $($_.Exception.Message)" }

function Get-CarpetaRunspace {
    if ($script:carpetaRs -and $script:carpetaRs.RunspaceStateInfo.State -eq 'Opened') { return $script:carpetaRs }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs.Open()
    $warm = [powershell]::Create()
    $warm.Runspace = $rs
    [void]$warm.AddScript($script:carpetaWarmScript).Invoke()
    $warm.Dispose()
    $script:carpetaRs = $rs
    return $rs
}

function Show-FolderDialogSync([string]$startPath) {
    $code = {
        $start = $args[0]
        $lFile = $args[1]
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        Add-Type -AssemblyName System.Drawing | Out-Null
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description = 'Seleccione la carpeta donde se buscan los archivos lista_cajas_*.csv'
        $d.ShowNewFolderButton = $true
        if ($start -and (Test-Path -LiteralPath $start -PathType Container)) { $d.SelectedPath = $start }
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $owner.ShowInTaskbar = $false
        $owner.StartPosition = 'CenterScreen'
        $owner.Size = [System.Drawing.Size]::new(1, 1)
        $owner.Show()
        $owner.Activate()
        $owner.BringToFront()
        try { [Fg]::MakeTopmost($owner.Handle) } catch {}
        try { [Fg]::ForceForeground($owner.Handle) } catch {}
        try { [Fg]::DisableTransitions($owner.Handle) } catch {}
        $topTimer = New-Object System.Windows.Forms.Timer
        $topTimer.Interval = 200
        $topTimer.Add_Tick({
            try { [Fg]::EnsureDialogTopmost([System.Diagnostics.Process]::GetCurrentProcess().Id) } catch {}
        })
        $topTimer.Start()
        $choice = $null
        try {
            if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK -and $d.SelectedPath) { $choice = $d.SelectedPath }
        } catch {
            try { [System.IO.File]::AppendAllText($lFile, "ERROR folder dialog: $($_.Exception.Message)`r`n", [System.Text.Encoding]::UTF8) } catch {}
            throw
        } finally {
            $topTimer.Stop()
            $topTimer.Dispose()
            $owner.Close()
            $d.Dispose()
            try { [Fg]::FlushScreen() } catch {}
        }
        return $choice
    }
    $rs = Get-CarpetaRunspace
    $pw = [powershell]::Create()
    $pw.Runspace = $rs
    $pw.AddScript($code).AddArgument($startPath).AddArgument($logFile) | Out-Null
    try {
        $result = $pw.Invoke()
        if ($result -and $result.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$result[0])) { return [string]$result[0] }
    } catch {
        Log "ERROR folder dialog: $($_.Exception.Message)"
    } finally {
        $pw.Dispose()
    }
    return $null
}

function Show-FileDialogSync([string]$startPath) {
    $code = {
        $start = $args[0]
        $lFile = $args[1]
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        Add-Type -AssemblyName System.Drawing | Out-Null
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Title = 'Seleccione el archivo lista_cajas_*.csv'
        $d.Filter = 'Archivos CSV (*.csv)|*.csv|Todos los archivos (*.*)|*.*'
        $d.CheckFileExists = $true
        if ($start -and (Test-Path -LiteralPath $start -PathType Container)) { $d.InitialDirectory = $start }
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $owner.ShowInTaskbar = $false
        $owner.StartPosition = 'CenterScreen'
        $owner.Size = [System.Drawing.Size]::new(1, 1)
        $owner.Show()
        $owner.Activate()
        $owner.BringToFront()
        try { [Fg]::MakeTopmost($owner.Handle) } catch {}
        try { [Fg]::ForceForeground($owner.Handle) } catch {}
        try { [Fg]::DisableTransitions($owner.Handle) } catch {}
        $topTimer = New-Object System.Windows.Forms.Timer
        $topTimer.Interval = 200
        $topTimer.Add_Tick({
            try { [Fg]::EnsureDialogTopmost([System.Diagnostics.Process]::GetCurrentProcess().Id) } catch {}
        })
        $topTimer.Start()
        $choice = $null
        try {
            if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK -and $d.FileName) { $choice = $d.FileName }
        } catch {
            try { [System.IO.File]::AppendAllText($lFile, "ERROR file dialog: $($_.Exception.Message)`r`n", [System.Text.Encoding]::UTF8) } catch {}
            throw
        } finally {
            $topTimer.Stop()
            $topTimer.Dispose()
            $owner.Close()
            $d.Dispose()
            try { [Fg]::FlushScreen() } catch {}
        }
        return $choice
    }
    $rs = Get-CarpetaRunspace
    $pw = [powershell]::Create()
    $pw.Runspace = $rs
    $pw.AddScript($code).AddArgument($startPath).AddArgument($logFile) | Out-Null
    try {
        $result = $pw.Invoke()
        if ($result -and $result.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$result[0])) { return [string]$result[0] }
    } catch {
        Log "ERROR file dialog: $($_.Exception.Message)"
    } finally {
        $pw.Dispose()
    }
    return $null
}

function Get-FileTime([string]$name) {
    if ($name -match '(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})') {
        try {
            return [datetime]::new([int]$Matches[1],[int]$Matches[2],[int]$Matches[3],[int]$Matches[4],[int]$Matches[5],[int]$Matches[6])
        } catch {}
    }
    return $null
}

function Get-LatestStockCsv {
    $csvFiles = Get-ChildItem -Path $datosDir -Filter "*.csv" -ErrorAction SilentlyContinue | ForEach-Object {
        $t = Get-FileTime $_.Name
        [pscustomobject]@{ File=$_; Name=$_.Name; DataTime=if ($t) { $t } else { $_.LastWriteTime }; LastWrite=$_.LastWriteTime; EsPatron=(Test-StockCsvName $_.Name) }
    } | Sort-Object @{Expression='EsPatron'; Descending=$true}, @{Expression='DataTime'; Descending=$true}
    if ($csvFiles -and $csvFiles.Count -gt 0) { return $csvFiles[0].File }
    return $null
}

function Test-FileReady([string]$path) {
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', [System.IO.FileShare]::ReadWrite)
        $fs.Close()
        return $true
    } catch {
        return $false
    }
}

function ParseNum($s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return 0 }
    return [double]($s -replace ',', '.')
}

# ── Parseo CSV respetando comillas (el formato nuevo envuelve cada campo con "") ──
function Split-CsvLine([string]$line, [string]$delim) {
    $result = New-Object System.Collections.Generic.List[string]
    $field = New-Object System.Text.StringBuilder
    $inQuotes = $false
    for ($i = 0; $i -lt $line.Length; $i++) {
        $ch = $line[$i]
        if ($inQuotes) {
            if ($ch -eq '"') {
                if ($i + 1 -lt $line.Length -and $line[$i + 1] -eq '"') { [void]$field.Append('"'); $i++ }
                else { $inQuotes = $false }
            } else { [void]$field.Append($ch) }
        } else {
            if ($ch -eq '"') { $inQuotes = $true }
            elseif ($ch -eq $delim) { $result.Add($field.ToString()); [void]$field.Clear() }
            else { [void]$field.Append($ch) }
        }
    }
    $result.Add($field.ToString())
    return $result.ToArray()
}

function Detect-CsvDelim([string]$line) {
    $semi = 0; $comma = 0; $inQ = $false
    for ($i = 0; $i -lt $line.Length; $i++) {
        $ch = $line[$i]
        if ($inQ) {
            if ($ch -eq '"') {
                if ($i + 1 -lt $line.Length -and $line[$i + 1] -eq '"') { $i++ }
                else { $inQ = $false }
            }
        } else {
            if ($ch -eq '"') { $inQ = $true }
            elseif ($ch -eq ';') { $semi++ }
            elseif ($ch -eq ',') { $comma++ }
        }
    }
    if ($comma -gt $semi) { return ',' } else { return ';' }
}

# ── Modulo de Trazabilidad y Analisis Brasil ──
function Test-EsBrasil([string]$sku, [string]$destino, [string]$nombre) {
    if ($destino -and ($destino.Trim() -eq '10' -or $destino.ToUpper().Contains('BRASIL') -or $destino.ToUpper().Contains('BR'))) {
        return $true
    }
    if ($sku -and $sku.Length -ge 8 -and $sku.Substring(6, 2) -eq '10') {
        return $true
    }
    if ($nombre -and $nombre.ToUpper().Contains('BRASIL')) {
        return $true
    }
    return $false
}

function Normalize-Lpn([string]$lpn) {
    if ([string]::IsNullOrWhiteSpace($lpn)) { return '' }
    $s = $lpn.Trim()
    $trimmed = $s.TrimStart('0')
    if ($trimmed.Length -eq 0) { return '0' }
    return $trimmed
}

function Format-SkuNombre([string]$sku, [string]$nombre) {
    if ([string]::IsNullOrWhiteSpace($nombre)) { return $nombre }
    if ($sku -and $sku.Trim().EndsWith('08')) {
        if ($nombre -notmatch '-ANGUS-') {
            return "$($nombre.Trim()) -ANGUS-"
        }
    }
    return $nombre
}

function Get-AnalisisManual {
    if (Test-Path -LiteralPath $analisisManualFile -PathType Leaf) {
        try {
            $json = Get-Content -LiteralPath $analisisManualFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $pList = New-Object System.Collections.Generic.List[string]
            $cList = New-Object System.Collections.Generic.List[string]
            if ($json.pallets -is [System.Collections.IEnumerable] -and -not ($json.pallets -is [string])) {
                foreach ($p in $json.pallets) {
                    if ($p) {
                        $norm = Normalize-Lpn $p
                        if ($norm) { [void]$pList.Add($norm) }
                    }
                }
            }
            if ($json.cajas -is [System.Collections.IEnumerable] -and -not ($json.cajas -is [string])) {
                foreach ($c in $json.cajas) {
                    if ($c) {
                        $norm = Normalize-Lpn $c
                        if ($norm) { [void]$cList.Add($norm) }
                    }
                }
            }
            return @{ pallets = [string[]]$pList.ToArray(); cajas = [string[]]$cList.ToArray() }
        } catch {
            Log "ERROR leyendo ${analisisManualFile}: $($_.Exception.Message)"
        }
    }
    return @{ pallets = [string[]]@(); cajas = [string[]]@() }
}

function Save-AnalisisManual($data) {
    try {
        [string[]]$pArr = if ($data.pallets) { [string[]]@($data.pallets) } else { [string[]]@() }
        [string[]]$cArr = if ($data.cajas) { [string[]]@($data.cajas) } else { [string[]]@() }
        $obj = [ordered]@{ pallets = $pArr; cajas = $cArr }
        $json = $obj | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($analisisManualFile, $json, [System.Text.Encoding]::UTF8)
        Log "analisis_manual.json guardado: $($pArr.Length) pallets, $($cArr.Length) cajas"
    } catch {
        Log "ERROR guardando ${analisisManualFile}: $($_.Exception.Message)"
    }
}

function Get-HistorialCargas {
    if (Test-Path -LiteralPath $cargasHistorialFile -PathType Leaf) {
        try {
            $raw = [System.IO.File]::ReadAllText($cargasHistorialFile, [System.Text.Encoding]::UTF8)
            if ($raw -and $raw.Trim()) {
                $arr = $raw | ConvertFrom-Json
                if ($arr -is [System.Collections.IEnumerable] -and -not ($arr -is [string])) {
                    return @($arr)
                } elseif ($arr) {
                    return @($arr)
                }
            }
        } catch {
            Log "ERROR leyendo ${cargasHistorialFile}: $($_.Exception.Message)"
        }
    }
    return @()
}

function Save-HistorialCargas($cargasList) {
    try {
        $json = if ($cargasList -and @($cargasList).Count -gt 0) {
            @($cargasList) | ConvertTo-Json -Depth 6
        } else {
            "[]"
        }
        $tmpFile = "$cargasHistorialFile.tmp"
        [System.IO.File]::WriteAllText($tmpFile, $json, [System.Text.Encoding]::UTF8)
        Move-Item -LiteralPath $tmpFile -Destination $cargasHistorialFile -Force
        Log "cargas_historial.json guardado: $(@($cargasList).Count) cargas registradas"
        return $true
    } catch {
        Log "ERROR guardando ${cargasHistorialFile}: $($_.Exception.Message)"
        return $false
    }
}

function Set-Prop($obj, [string]$name, $val) {
    if ($obj.PSobject.Properties[$name]) {
        $obj.$name = $val
    } else {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue $val -Force
    }
}

function Extract-Ofertas($str) {
    if (-not $str) { return @() }
    $ofs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $clean = "$str".Trim()
    if ($clean -match '^\d{4,6}$') {
        [void]$ofs.Add($clean)
    }
    $matches1 = [regex]::Matches($str, '(?i)(?:OF(?:ERTA)?|COMPLEMENTO\s+(?:DE\s+)?OF(?:ERTA)?)\s*[,:\-\s]*(\d{4,6})')
    foreach ($m in $matches1) { if ($m.Groups[1].Value) { [void]$ofs.Add($m.Groups[1].Value) } }
    if ($ofs.Count -eq 0) {
        $matches3 = [regex]::Matches($str, '\b(2[5-9]\d{3})\b')
        foreach ($m in $matches3) { [void]$ofs.Add($m.Groups[1].Value) }
    }
    return [string[]]@($ofs)
}

function Extract-PedidoCliente($str) {
    if (-not $str) { return $null }
    if ($str -match '(?i)Pedido\s*:\s*\d+\s+([^|;]+)') {
        $cli = $Matches[1].Replace('|', '').Trim()
        if ($cli.Length -ge 3) { return $cli }
    }
    return $null
}

function Get-CapaDirectory {
    if ($script:capaDir -and (Test-Path -LiteralPath $script:capaDir -PathType Container)) {
        return $script:capaDir
    }
    $candidates = @("J:\UTIL\USER\CAPA", "\\svr\d\UTIL\USER\CAPA")
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath $cand -PathType Container) {
            $script:capaDir = $cand
            return $cand
        }
    }
    return $script:capaDir
}

function Sync-RomaneosCapa([switch]$Force) {
    $cache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $romaneosResumenFile -PathType Leaf) {
        try {
            $rawCache = [System.IO.File]::ReadAllText($romaneosResumenFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($rawCache) {
                foreach ($item in $rawCache) {
                    if ($item.archivo) {
                        $item.ofertas = Extract-Ofertas $item.observacion
                        $item.cliente = Extract-PedidoCliente $item.observacion
                        $cache[$item.archivo] = $item
                    }
                }
            }
        } catch {}
    }

    $activeCapaDir = Get-CapaDirectory
    if (-not (Test-Path -LiteralPath $activeCapaDir -PathType Container)) {
        Log "ADVERTENCIA: Carpeta CAPA no accesible (${activeCapaDir}). Retornando $(@($cache.Values).Count) romaneos desde cache local."
        return @($cache.Values)
    }

    $files = [System.IO.Directory]::GetFiles($activeCapaDir, "*.csv")
    $updated = $false

    foreach ($filePath in $files) {
        $fileName = [System.IO.Path]::GetFileName($filePath)
        $fi = [System.IO.FileInfo]::new($filePath)
        $lastWriteTicks = $fi.LastWriteTimeUtc.Ticks

        if (-not $Force -and $cache.ContainsKey($fileName)) {
            $cachedObj = $cache[$fileName]
            if ($cachedObj.ticks -and $cachedObj.ticks -eq $lastWriteTicks -and $cachedObj.dep -and $cachedObj.conservacion) {
                continue
            }
        }

        try {
            $lines = [System.IO.File]::ReadAllLines($filePath)
            if ($lines.Length -lt 2) { continue }
            $dataStart = -1
            for ($i = 0; $i -lt $lines.Length; $i++) {
                $l = $lines[$i].Trim()
                if (-not $l -or $l.StartsWith("Romaneo;")) { continue }
                $dataStart = $i
                break
            }
            if ($dataStart -eq -1) { continue }
            $lastIdx = -1
            for ($i = $lines.Length - 1; $i -ge $dataStart; $i--) {
                if (-not [string]::IsNullOrWhiteSpace($lines[$i])) {
                    $lastIdx = $i
                    break
                }
            }
            if ($lastIdx -eq -1) { continue }

            $firstParts = $lines[$dataStart].Split(';')
            $romaneo = if ($firstParts.Length -gt 0) { $firstParts[0].Trim() } else { "" }
            $tipo = if ($firstParts.Length -gt 1) { $firstParts[1].Trim() } else { "" }
            $fecha = if ($firstParts.Length -gt 2) { $firstParts[2].Trim() } else { "" }
            $obs = if ($firstParts.Length -gt 3) { $firstParts[3].Trim() } else { "" }
            $conCode = if ($firstParts.Length -gt 8) { $firstParts[8].Trim() } else { "" }
            $destino = if ($firstParts.Length -gt 9) { $firstParts[9].Trim() } else { "" }
            $patente = if ($firstParts.Length -gt 17) { $firstParts[17].Trim() } else { "" }
            $hora = if ($firstParts.Length -gt 19) { $firstParts[19].Trim() } else { "" }
            $dep = if ($firstParts.Length -gt 20) { $firstParts[20].Trim() } else { "" }

            $conDesc = switch ($conCode) {
                '1' { 'Enfriado' }
                '2' { 'Congelado' }
                '3' { 'Madurado' }
                default { 'Congelado' }
            }

            $cajas = 0
            $kgNeto = 0.0
            $lastLine = $lines[$lastIdx].Trim()
            if ($lastLine.StartsWith(";;;;;;;;;;;")) {
                $lastParts = $lastLine.Split(';')
                if ($lastParts.Length -gt 11 -and $lastParts[11].Trim()) {
                    [int]::TryParse($lastParts[11].Trim(), [ref]$cajas) | Out-Null
                }
                if ($lastParts.Length -gt 13 -and $lastParts[13].Trim()) {
                    $kgStr = $lastParts[13].Trim().Replace(',', '.')
                    [double]::TryParse($kgStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$kgNeto) | Out-Null
                }
            } else {
                for ($i = $dataStart; $i -le $lastIdx; $i++) {
                    $p = $lines[$i].Split(';')
                    $cajas++
                    if ($p.Length -gt 13 -and $p[13].Trim()) {
                        $v = 0.0
                        $kgStr = $p[13].Trim().Replace(',', '.')
                        if ([double]::TryParse($kgStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
                            $kgNeto += $v
                        }
                    }
                }
            }

            $ofs = Extract-Ofertas $obs
            $obj = [ordered]@{
                romaneo = $romaneo
                tipo = $tipo
                fecha = $fecha
                hora = $hora
                observacion = $obs
                con = $conCode
                conservacion = $conDesc
                patente = $patente
                destino = $destino
                cajas = $cajas
                kgNeto = [Math]::Round($kgNeto, 2)
                ofertas = $ofs
                cliente = (Extract-PedidoCliente $obs)
                dep = $dep
                archivo = $fileName
                ticks = $lastWriteTicks
            }
            $cache[$fileName] = $obj
            $updated = $true
        } catch {}
    }

    $allRomaneos = @($cache.Values)
    if ($updated -or (-not (Test-Path -LiteralPath $romaneosResumenFile))) {
        $json = $allRomaneos | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($romaneosResumenFile, $json, [System.Text.Encoding]::UTF8)
        Log "Indexados y guardados $($allRomaneos.Count) romaneos en romaneos_resumen.json"
    }
    $script:lastRomaneosSync = Get-Date
    return $allRomaneos
}

function Get-CargaConservacion($c) {
    if ($c.romaneos -and @($c.romaneos).Count -gt 0) {
        $cons = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($r in $c.romaneos) {
            if ($r.conservacion) { [void]$cons.Add($r.conservacion) }
            elseif ($r.con -eq '1') { [void]$cons.Add('Enfriado') }
            elseif ($r.con -eq '2') { [void]$cons.Add('Congelado') }
            elseif ($r.con -eq '3') { [void]$cons.Add('Madurado') }
        }
        if ($cons.Contains('Enfriado') -and ($cons.Contains('Congelado') -or $cons.Contains('Madurado'))) {
            return 'Mixto'
        }
        if ($cons.Contains('Enfriado')) { return 'Enfriado' }
        if ($cons.Contains('Madurado')) { return 'Madurado' }
        if ($cons.Contains('Congelado')) { return 'Congelado' }
    }
    if ($c.conservacion) { return $c.conservacion }
    return 'Congelado'
}

function Auto-VincularCargasPendientes {
    $romaneos = Sync-RomaneosCapa
    if (-not $romaneos -or $romaneos.Count -eq 0) { return }

    if (-not (Test-Path -LiteralPath $cargasHistorialFile -PathType Leaf)) { return }
    $rawCargas = Get-Content -LiteralPath $cargasHistorialFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $rawCargas) { return }

    $cargasList = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $rawCargas) { $cargasList.Add($item) }
    if ($cargasList.Count -eq 0) { return }

    $vinculadasCount = 0
    $todayStr = (Get-Date).ToString("yyyy-MM-dd")

    foreach ($c in $cargasList) {
        if ($c.estado -eq 'Anulada') { continue }
        if ($c.manual_rs -eq $true) { continue }

        $cargasOfs = @{}
        if ($c.items) {
            foreach ($it in $c.items) {
                $ext = Extract-Ofertas $it.oferta
                foreach ($o in $ext) { $cargasOfs[[string]$o] = $true }
            }
        }
        if ($cargasOfs.Count -eq 0) { continue }

        $cDate = $null
        try { $cDate = [datetime]::ParseExact($c.fecha, 'yyyy-MM-dd', $null) } catch {}

        $matches = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $romaneos) {
            if ($r.dep -ne '101') { continue }
            if (-not $r.ofertas) { continue }
            $hasOfMatch = $false
            foreach ($ro in $r.ofertas) {
                if ($cargasOfs.ContainsKey([string]$ro)) { $hasOfMatch = $true; break }
            }
            if (-not $hasOfMatch) { continue }

            if ($cDate -and $r.fecha) {
                $rDate = $null
                try { $rDate = [datetime]::ParseExact($r.fecha, 'dd/MM/yyyy', $null) } catch {}
                if ($rDate -and [Math]::Abs(($rDate - $cDate).TotalDays) -gt 4) {
                    continue
                }
            }

            $matches.Add($r)
        }

        if ($matches.Count -gt 0) {
            $rsObjects = @()
            $totalKg = 0.0
            $patente = ""

            foreach ($m in $matches) {
                $rsObjects += [ordered]@{
                    romaneo = [string]$m.romaneo
                    kgNeto = [double]$m.kgNeto
                    cajas = [int]$m.cajas
                    patente = [string]$m.patente
                    destino = [string]$m.destino
                    fecha = [string]$m.fecha
                    hora = [string]$m.hora
                    observacion = [string]$m.observacion
                    con = [string]$m.con
                    conservacion = [string]$m.conservacion
                    dep = [string]$m.dep
                }
                $totalKg += [double]$m.kgNeto
                if (-not $patente -and $m.patente) { $patente = [string]$m.patente }
            }

            Set-Prop $c "romaneos" $rsObjects
            Set-Prop $c "kilos_reales" ([Math]::Round($totalKg, 2))
            if ($patente) { Set-Prop $c "patente" $patente }
            Set-Prop $c "conservacion" (Get-CargaConservacion $c)

            if ($c.fecha -ne $todayStr -or $c.kilos_reales -gt 0) {
                Set-Prop $c "estado" "Cerrada"
            }

            $vinculadasCount++
            Log "Auto-vinculada carga $($c.id): $($matches.Count) RS ($($c.conservacion)), Total: $($c.kilos_reales) kg neto, Patente: $($c.patente)"
        }
    }

    # --- PASO 2: Creación automática de cargas para RS de Depósito 101 (Septiembre 2026 en adelante) ---
    $ofertasEnCargas = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($c in $cargasList) {
        if ($c.items) {
            foreach ($it in $c.items) {
                if ($it.oferta) { foreach ($o in (Extract-Ofertas "$($it.oferta)")) { [void]$ofertasEnCargas.Add($o) } }
                if ($it.venta) { foreach ($o in (Extract-Ofertas "$($it.venta)")) { [void]$ofertasEnCargas.Add($o) } }
            }
        }
        if ($c.romaneos) {
            foreach ($r in $c.romaneos) {
                if ($r.observacion) { foreach ($o in (Extract-Ofertas "$($r.observacion)")) { [void]$ofertasEnCargas.Add($o) } }
                if ($r.oferta) { foreach ($o in (Extract-Ofertas "$($r.oferta)")) { [void]$ofertasEnCargas.Add($o) } }
            }
        }
    }

    $rsParaCrear = [System.Collections.Generic.List[object]]::new()
    $minSept2026 = [datetime]::new(2026, 9, 1)

    foreach ($r in $romaneos) {
        if ($r.dep -ne '101') { continue }
        if (-not $r.ofertas -or @($r.ofertas).Count -eq 0) { continue }

        $rDate = $null
        try { $rDate = [datetime]::ParseExact($r.fecha, 'dd/MM/yyyy', $null) } catch {}
        if (-not $rDate -or $rDate -lt $minSept2026) { continue }

        $ofValidas = @()
        foreach ($ofCandidate in $r.ofertas) {
            $ofStr = [string]$ofCandidate
            if ($ofStr.Length -ge 4 -and -not $ofertasEnCargas.Contains($ofStr)) {
                $ofValidas += $ofStr
            }
        }
        if ($ofValidas.Count -eq 0) { continue }

        $rsParaCrear.Add(@{
            romaneo = $r
            ofertaPrincipal = $ofValidas[0]
            fechaDate = $rDate
        })
    }

    if ($rsParaCrear.Count -gt 0) {
        $grupos = $rsParaCrear | Group-Object {
            $r = $_.romaneo
            $fIso = $_.fechaDate.ToString("yyyy-MM-dd")
            "$($_.ofertaPrincipal)|$fIso|$($r.patente)"
        }

        foreach ($g in $grupos) {
            $first = $g.Group[0]
            $firstR = $first.romaneo
            $of = $first.ofertaPrincipal
            $fIso = $first.fechaDate.ToString("yyyy-MM-dd")
            $pat = $firstR.patente

            if ($ofertasEnCargas.Contains($of)) { continue }

            $totKg = 0.0
            $totCajas = 0
            $rsObjects = @()
            $horaMin = "23:59:59"

            foreach ($item in $g.Group) {
                $m = $item.romaneo
                $totKg += [double]$m.kgNeto
                $totCajas += [int]$m.cajas
                if ($m.hora -and $m.hora -lt $horaMin) { $horaMin = $m.hora }
                $rsObjects += [ordered]@{
                    romaneo = [string]$m.romaneo
                    kgNeto = [double]$m.kgNeto
                    cajas = [int]$m.cajas
                    patente = [string]$m.patente
                    destino = [string]$m.destino
                    fecha = [string]$m.fecha
                    hora = [string]$m.hora
                    observacion = [string]$m.observacion
                    con = [string]$m.con
                    conservacion = [string]$m.conservacion
                    dep = [string]$m.dep
                    oferta = $of
                }
            }

            if ($horaMin -eq "23:59:59") { $horaMin = "00:00:00" }
            if ($horaMin.Length -eq 5) { $horaMin += ":00" }

            $timePart = $horaMin.Replace(":", "")
            $datePart = $fIso.Replace("-", "")
            $newId = "CRG-$datePart-$timePart-OF$of"
            $suffix = 1
            while (($cargasList | Where-Object { $_.id -eq $newId })) {
                $newId = "CRG-$datePart-$timePart-OF$of-$suffix"
                $suffix++
            }

            $estPallets = [Math]::Max(1, [int][Math]::Ceiling($totCajas / 45.0))
            $totKgRound = [Math]::Round($totKg, 2)
            $cargaCons = if ($firstR.conservacion) { $firstR.conservacion } elseif ($firstR.con -eq '1') { 'Enfriado' } else { 'Congelado' }
            $skuCode = if ($cargaCons -eq 'Enfriado') { "EXP-ENFRIADO" } else { "EXP-DEP101" }

            $itemRow = [ordered]@{
                ord = 1
                sku = $skuCode
                destino = if ($firstR.destino) { [string]$firstR.destino } else { "66" }
                venta = $of
                estab_faenador = ""
                establecimiento = "2025"
                nombre = "CARGA EXPORTACION ($cargaCons) OF $of"
                pallets_stock = $estPallets
                kilos_stock = [int][Math]::Round($totKgRound)
                pallets_solicitados = $estPallets
                kilos_estimados = $totKgRound
                oferta = $of
                estado = "Cerrada"
            }

            $nuevaCarga = [ordered]@{
                id = $newId
                fecha = $fIso
                hora = $horaMin
                estado = "Cerrada"
                conservacion = $cargaCons
                pallets_solicitados = $estPallets
                kilos_estimados = $totKgRound
                kilos_reales = $totKgRound
                patente = $pat
                observaciones = "Generada automáticamente desde RS ($cargaCons, Dep $($firstR.dep), OF $of)"
                ordenes_count = 1
                items = @($itemRow)
                romaneos = $rsObjects
                origen_automatico = $true
            }

            $cargasList.Add($nuevaCarga)
            [void]$ofertasEnCargas.Add($of)
            $vinculadasCount++
            Log "Creada carga automática para OF $($of): $newId ($($rsObjects.Count) RS, $cargaCons, $totKgRound kg, Patente: $pat)"
        }
    }

    # --- PASO 3: Creación automática de salidas para Pedidos de Depósito 101 con cliente (Septiembre 2026 en adelante) ---
    $rsYaEnCargas = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($c in $cargasList) {
        if ($c.romaneos) {
            foreach ($r in $c.romaneos) {
                if ($r.romaneo) { [void]$rsYaEnCargas.Add([string]$r.romaneo) }
            }
        }
    }

    $pedidosParaCrear = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $romaneos) {
        if ($r.dep -ne '101') { continue }
        $cli = if ($r.cliente) { $r.cliente } else { Extract-PedidoCliente $r.observacion }
        if (-not $cli) { continue }
        if ($r.romaneo -and $rsYaEnCargas.Contains([string]$r.romaneo)) { continue }

        $rDate = $null
        try { $rDate = [datetime]::ParseExact($r.fecha, 'dd/MM/yyyy', $null) } catch {}
        if (-not $rDate -or $rDate -lt $minSept2026) { continue }

        $pedidosParaCrear.Add(@{
            romaneo = $r
            cliente = $cli
            fechaDate = $rDate
        })
    }

    if ($pedidosParaCrear.Count -gt 0) {
        $gruposPed = $pedidosParaCrear | Group-Object {
            $r = $_.romaneo
            $fIso = $_.fechaDate.ToString("yyyy-MM-dd")
            "$($_.cliente)|$fIso|$($r.patente)"
        }

        foreach ($g in $gruposPed) {
            $first = $g.Group[0]
            $firstR = $first.romaneo
            $cli = $first.cliente
            $fIso = $first.fechaDate.ToString("yyyy-MM-dd")
            $pat = $firstR.patente

            $totKg = 0.0
            $totCajas = 0
            $rsObjects = @()
            $horaMin = "23:59:59"

            foreach ($item in $g.Group) {
                $m = $item.romaneo
                $totKg += [double]$m.kgNeto
                $totCajas += [int]$m.cajas
                if ($m.hora -and $m.hora -lt $horaMin) { $horaMin = $m.hora }
                $rsObjects += [ordered]@{
                    romaneo = [string]$m.romaneo
                    kgNeto = [double]$m.kgNeto
                    cajas = [int]$m.cajas
                    patente = [string]$m.patente
                    destino = [string]$m.destino
                    fecha = [string]$m.fecha
                    hora = [string]$m.hora
                    observacion = [string]$m.observacion
                    con = [string]$m.con
                    conservacion = [string]$m.conservacion
                    dep = [string]$m.dep
                    oferta = $cli
                    cliente = $cli
                }
                if ($m.romaneo) { [void]$rsYaEnCargas.Add([string]$m.romaneo) }
            }

            if ($horaMin -eq "23:59:59") { $horaMin = "00:00:00" }
            if ($horaMin.Length -eq 5) { $horaMin += ":00" }

            $timePart = $horaMin.Replace(":", "")
            $datePart = $fIso.Replace("-", "")
            $cliClean = [regex]::Replace($cli.ToUpper(), '[^A-Z0-9]', '')
            if ($cliClean.Length -gt 15) { $cliClean = $cliClean.Substring(0, 15) }
            $newId = "CRG-$datePart-$timePart-PED-$cliClean"
            $suffix = 1
            while (($cargasList | Where-Object { $_.id -eq $newId })) {
                $newId = "CRG-$datePart-$timePart-PED-$cliClean-$suffix"
                $suffix++
            }

            $estPallets = [Math]::Max(1, [int][Math]::Ceiling($totCajas / 40.0))
            $totKgRound = [Math]::Round($totKg, 2)
            $cargaCons = if ($firstR.conservacion) { $firstR.conservacion } elseif ($firstR.con -eq '1') { 'Enfriado' } else { 'Congelado' }
            $skuCode = "PED-DEP101"

            $itemRow = [ordered]@{
                ord = 1
                sku = $skuCode
                destino = if ($firstR.destino) { [string]$firstR.destino } else { "66" }
                venta = "PED: $cli"
                estab_faenador = ""
                establecimiento = "2025"
                nombre = "SALIDA PEDIDO: $cli"
                pallets_stock = $estPallets
                kilos_stock = [int][Math]::Round($totKgRound)
                pallets_solicitados = $estPallets
                kilos_estimados = $totKgRound
                oferta = $cli
                estado = "Cerrada"
            }

            $nuevaCarga = [ordered]@{
                id = $newId
                fecha = $fIso
                hora = $horaMin
                estado = "Cerrada"
                conservacion = $cargaCons
                pallets_solicitados = $estPallets
                kilos_estimados = $totKgRound
                kilos_reales = $totKgRound
                patente = $pat
                observaciones = "Generada automáticamente desde RS ($cargaCons, Dep 101, Pedido: $cli)"
                ordenes_count = 1
                items = @($itemRow)
                romaneos = $rsObjects
                origen_automatico = $true
                cliente = $cli
            }

            $cargasList.Add($nuevaCarga)
            $vinculadasCount++
            Log "Creada carga automática para Pedido ($cli): $newId ($($rsObjects.Count) RS, $cargaCons, $totKgRound kg, Patente: $pat)"
        }
    }

    # Asegurar propiedad 'conservacion' para todas las cargas existentes
    foreach ($c in $cargasList) {
        if (-not $c.conservacion) {
            Set-Prop $c "conservacion" (Get-CargaConservacion $c)
            $vinculadasCount++
        }
    }

    if ($vinculadasCount -gt 0) {
        $json = @($cargasList) | ConvertTo-Json -Depth 6
        $tmpFile = "$cargasHistorialFile.tmp"
        [System.IO.File]::WriteAllText($tmpFile, $json, [System.Text.Encoding]::UTF8)
        Move-Item -LiteralPath $tmpFile -Destination $cargasHistorialFile -Force
        Log "Auto-vinculación guardada: $vinculadasCount cargas actualizadas con RS"
    }
}

function Update-CachedPayloadAnalisis {
    if (-not $global:cachedPayload -or -not $global:cachedPayload.stockData) { return }
    $manual = Get-AnalisisManual
    $mPallets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $mBoxes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($manual.pallets) { foreach ($p in $manual.pallets) { if ($p) { [void]$mPallets.Add((Normalize-Lpn $p)) } } }
    if ($manual.cajas) { foreach ($c in $manual.cajas) { if ($c) { [void]$mBoxes.Add((Normalize-Lpn $c)) } } }

    foreach ($rec in $global:cachedPayload.stockData) {
        if (-not $rec.esBrasil -or -not $rec.detalle) { continue }
        $gPalletsOk = 0
        $gPalletsPend = 0
        $gCajasOk = 0
        $gCajasPend = 0
        $gKilosOk = 0.0
        $gKilosPend = 0.0

        foreach ($p in $rec.detalle) {
            $pNorm = Normalize-Lpn $p.lpn
            $palletIsManual = $mPallets.Contains($pNorm)
            $pCajasOk = 0
            $pCajasPend = 0
            $pKilosOk = 0.0
            $pKilosPend = 0.0

            if ($p.cajasDetalle) {
                foreach ($b in $p.cajasDetalle) {
                    $bNorm = Normalize-Lpn $b.boxId
                    $boxIsManual = ($palletIsManual -or $mBoxes.Contains($bNorm))
                    if ($boxIsManual) {
                        $b.analisis = 'OK'
                        $b.manual = $true
                    } elseif ($b.manual) {
                        $b.analisis = 'PENDIENTE'
                        $b.manual = $false
                    }

                    if ($b.analisis -eq 'OK') {
                        $pCajasOk++
                        $pKilosOk += [double]$b.kilosNeto
                    } else {
                        $pCajasPend++
                        $pKilosPend += [double]$b.kilosNeto
                    }
                }
            }

            $palletAnalisis = if ($pCajasPend -eq 0 -and $pCajasOk -gt 0) { 'OK' } else { 'PENDIENTE' }
            $p.analisis = $palletAnalisis
            $p.cajasConAnalisis = $pCajasOk
            $p.cajasSinAnalisis = $pCajasPend
            $p.kilosConAnalisis = [Math]::Round($pKilosOk, 2)
            $p.kilosSinAnalisis = [Math]::Round($pKilosPend, 2)

            if ($palletAnalisis -eq 'OK') { $gPalletsOk++ } else { $gPalletsPend++ }
            $gCajasOk += $pCajasOk
            $gCajasPend += $pCajasPend
            $gKilosOk += $pKilosOk
            $gKilosPend += $pKilosPend
        }

        $rec.detalle = @($rec.detalle | Sort-Object @{ Expression = { if ($_.analisis -eq 'OK') { 0 } elseif ($_.analisis -eq 'PENDIENTE') { 1 } else { 2 } } }, @{ Expression = 'lpn' })

        $rec.palletsConAnalisis = $gPalletsOk
        $rec.palletsSinAnalisis = $gPalletsPend
        $rec.cajasConAnalisis = $gCajasOk
        $rec.cajasSinAnalisis = $gCajasPend
        $rec.kilosConAnalisis = [Math]::Round($gKilosOk, 1)
        $rec.kilosSinAnalisis = [Math]::Round($gKilosPend, 1)

        $rec.analisis = if ($gCajasPend -eq 0 -and $gCajasOk -gt 0) {
            'OK'
        } elseif ($gCajasOk -eq 0 -and $gCajasPend -gt 0) {
            'PENDIENTE'
        } elseif ($gCajasOk -gt 0 -and $gCajasPend -gt 0) {
            'MIXTO'
        } else {
            'NA'
        }
    }

    $global:cachedPayloadJson = $global:cachedPayload | ConvertTo-Json -Depth 10 -Compress
    Log "Cache en memoria actualizado instantaneamente (modificacion analisis Brasil)."
}

function Get-HistoricoCajas {
    $hist = @{}
    if (Test-Path -LiteralPath $historicoCajasFile -PathType Leaf) {
        try {
            $json = Get-Content -LiteralPath $historicoCajasFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($json) {
                foreach ($prop in $json.PSObject.Properties) {
                    $hist[$prop.Name] = @{
                        sku              = [string]$prop.Value.sku
                        primer_ingreso   = [string]$prop.Value.primer_ingreso
                        ultima_aparicion = [string]$prop.Value.ultima_aparicion
                        reingreso_fecha  = [string]$prop.Value.reingreso_fecha
                        estado           = [string]$prop.Value.estado
                        manual           = [bool]$prop.Value.manual
                    }
                }
            }
            Log "historico_cajas.json cargado: $($hist.Count) cajas registradas"
        } catch {
            Log "ERROR leyendo ${historicoCajasFile}: $($_.Exception.Message)"
        }
    }
    return $hist
}

function Save-HistoricoCajas($hist) {
    try {
        $json = $hist | ConvertTo-Json -Depth 4 -Compress
        [System.IO.File]::WriteAllText($historicoCajasFile, $json, [System.Text.Encoding]::UTF8)
        Log "historico_cajas.json guardado: $($hist.Count) cajas registradas"
    } catch {
        Log "ERROR guardando ${historicoCajasFile}: $($_.Exception.Message)"
    }
}

# ── Exportacion principal ──
function Run-Export {
    # ── PASO 1: Verificar carpetas ──
    Send-Progress 5 "PASO 1 de 8: Verificando carpetas..."
    Log "--- PASO 1: Carpetas ---"
    Log "STOCK dir: $datosDir"
    Log "Archive dir: $archivoDir"
    if (Test-Path $datosDir) { Log "  STOCK: OK" } else { Log "  STOCK: creando..."; New-Item -ItemType Directory -Path $datosDir -Force | Out-Null }
    if (Test-Path $excelPath) { Log "  Excel: OK" } else { throw "Excel NO EXISTE - $excelPath" }

    # ── PASO 2: Leer catalogo (desde JSON cache o Excel) ──
    Send-Progress 15 "PASO 2 de 8: Leyendo catalogo..."
    Log "--- PASO 2: Leyendo catalogo ---"
    $excelLastWrite = (Get-Item $excelPath).LastWriteTime
    $catalogo = $null

    if (Test-Path $catalogoJson) {
        $jsonLastWrite = (Get-Item $catalogoJson).LastWriteTime
        if ($jsonLastWrite -ge $excelLastWrite) {
            Log "  Usando cache: catalogo.json (mas reciente que el Excel)"
            $catalogoPS = Get-Content $catalogoJson -Raw -Encoding UTF8 | ConvertFrom-Json
            $catalogo = @{}
            foreach ($prop in $catalogoPS.PSObject.Properties) {
                $catalogo[$prop.Name] = @{
                    destino = $prop.Value.destino
                    nombre  = (Format-SkuNombre $prop.Name $prop.Value.nombre)
                    matSap  = $prop.Value.matSap
                }
            }
        } else {
            Log "  Cache desactualizado (Excel mas nuevo), re-leyendo Excel..."
        }
    }

    if (-not $catalogo) {
        Send-Progress 15 "PASO 2 de 8: Abriendo Excel (primera vez, puede demorar)..."
        Log "  Abriendo Excel (esto puede demorar)..."
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $wb = $excel.Workbooks.Open($excelPath)
            $ws = $wb.Sheets.Item(1)
            $rows = $ws.UsedRange.Rows.Count
            Log "  Sheet 1, filas totales: $rows"

            $catalogo = @{}
            $lineasVacias = 0
            for ($r = 7; $r -le $rows; $r++) {
                $sku = $ws.Cells.Item($r, 1).Text
                if ([string]::IsNullOrWhiteSpace($sku)) { $lineasVacias++; continue }
                $catalogo[$sku] = @{
                    destino = $ws.Cells.Item($r, 2).Text
                    nombre  = (Format-SkuNombre $sku $ws.Cells.Item($r, 5).Text)
                    matSap  = $ws.Cells.Item($r, 6).Text
                }
            }
            $wb.Close($false)
            $excel.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
            Log "  Lineas vacias saltadas: $lineasVacias"

            $catalogo | ConvertTo-Json -Depth 3 | Set-Content $catalogoJson -Encoding UTF8
            Log "  Cache guardado en catalogo.json"
        } catch {
            Log "  WARN: No se pudo abrir Excel COM: $($_.Exception.Message)"
            if (Test-Path $catalogoJson) {
                Log "  Usando catalogo.json como respaldo."
                $catalogoPS = Get-Content $catalogoJson -Raw -Encoding UTF8 | ConvertFrom-Json
                $catalogo = @{}
                foreach ($prop in $catalogoPS.PSObject.Properties) {
                    $catalogo[$prop.Name] = @{
                        destino = $prop.Value.destino
                        nombre  = (Format-SkuNombre $prop.Name $prop.Value.nombre)
                        matSap  = $prop.Value.matSap
                    }
                }
            } else {
                throw "No se pudo leer el catalogo desde Excel y catalogo.json no existe: $($_.Exception.Message)"
            }
        }
    }

    Send-Progress 20 "PASO 2 de 8: Catalogo OK - $($catalogo.Count) SKUs"

    # ── PASO 3: Buscar CSV mas nuevo ──
    Send-Progress 30 "PASO 3 de 8: Buscando CSV en STOCK..."
    Log "--- PASO 3: Buscando CSV en STOCK ---"
    $csvFiles = Get-ChildItem -Path $datosDir -Filter "*.csv" | ForEach-Object {
        $t = Get-FileTime $_.Name
        [pscustomobject]@{ File=$_; Name=$_.Name; DataTime=if ($t) { $t } else { $_.LastWriteTime }; LastWrite=$_.LastWriteTime; EsPatron=(Test-StockCsvName $_.Name) }
    } | Sort-Object @{Expression='EsPatron'; Descending=$true}, @{Expression='DataTime'; Descending=$true}

    Log "  CSV encontrados (por fecha del nombre):"
    foreach ($c in $csvFiles) {
        Log "    $($c.Name) - datos: $($c.DataTime.ToString('yyyy-MM-dd HH:mm'))"
    }
    if ($csvFiles.Count -eq 0) {
        throw "No hay archivos lista_cajas_*.csv en la carpeta seleccionada. Elegi el archivo manualmente o cambia de carpeta."
    }

    $latestCsv = $null
    if ($global:csvSeleccionado -and (Test-Path -LiteralPath $global:csvSeleccionado -PathType Leaf)) {
        $latestCsv = Get-Item -LiteralPath $global:csvSeleccionado
        Log "  CSV elegido manualmente: $($latestCsv.Name)"
        if (-not (Test-FileReady $latestCsv.FullName)) {
            Send-Progress 35 "PASO 3 de 8: Esperando que termine de escribirse el CSV..."
            for ($i = 0; $i -lt 12; $i++) {
                if (Test-FileReady $latestCsv.FullName) { break }
                Start-Sleep -Seconds 5
            }
        }
        if (-not (Test-FileReady $latestCsv.FullName)) { throw "El CSV $($latestCsv.Name) esta en uso (siendo escrito). Cierre el programa que lo genera y reintente." }
    } else {
        foreach ($c in $csvFiles) {
            if (Test-FileReady $c.File.FullName) { $latestCsv = $c.File; break }
            Log "  $($c.Name): en uso, probando el siguiente..."
        }
        if (-not $latestCsv) {
            $newest = $csvFiles | Select-Object -First 1
            Send-Progress 35 "PASO 3 de 8: Esperando que termine de escribirse el CSV..."
            for ($i = 0; $i -lt 12; $i++) {
                if (Test-FileReady $newest.File.FullName) { $latestCsv = $newest.File; break }
                Start-Sleep -Seconds 5
            }
        }
        if (-not $latestCsv) { throw "Todos los CSV estan en uso (siendo escritos). Cierre el programa que los genera y reintente." }
    }
    if ($global:csvSeleccionado -and -not (Test-Path -LiteralPath $global:csvSeleccionado -PathType Leaf)) {
        Log "  CSV manual ya no existe: $global:csvSeleccionado (se vuelve a la seleccion automatica)"
        $global:csvSeleccionado = $null
    }

    $unstable = $true
    for ($i = 0; $i -lt 3 -and $unstable; $i++) {
        $sz1 = (Get-Item $latestCsv.FullName).Length
        Start-Sleep -Milliseconds 400
        $sz2 = (Get-Item $latestCsv.FullName).Length
        $unstable = ($sz1 -ne $sz2)
    }
    Send-Progress 40 "PASO 3 de 8: Seleccionado $($latestCsv.Name)"
    Log "  SELECCIONADO: $($latestCsv.Name)"

    # ── PASO 4: Leer CSV ──
    Send-Progress 45 "PASO 4 de 8: Leyendo CSV..."
    Log "--- PASO 4: Leyendo CSV ---"
    Log "  Ruta: $($latestCsv.FullName)"
    Log "  Tamano: $([Math]::Round((Get-Item $latestCsv.FullName).Length/1KB, 1)) KB"
    $lines = [System.IO.File]::ReadAllLines($latestCsv.FullName, [System.Text.Encoding]::UTF8)
    if ($lines.Count -lt 2) { throw "El CSV $($latestCsv.Name) no tiene filas de datos" }
    $delim = Detect-CsvDelim $lines[0]
    Log "  Delimitador detectado: '$delim'"

    # Split rapido: para formato nuevo ("," con comillas) usa Substring+split nativo;
    # para formato viejo (;) usa split directo; si no, fallback al parser quote-aware.
    $csvUseComma = ($delim -eq ',')
    $headerLine = $lines[0]
    if ($csvUseComma -and $headerLine.StartsWith('"') -and $headerLine.EndsWith('"')) {
        $headerLine = $headerLine.Substring(1, $headerLine.Length - 2)
    }
    $header = @(if ($csvUseComma) { $headerLine -split '","' } else { $headerLine -split $delim }) | ForEach-Object { $_.Trim() }
    $colMap = @{}
    for ($i = 0; $i -lt $header.Count; $i++) { $colMap[$header[$i]] = $i }
    $csvRows = New-Object System.Collections.Generic.List[string[]]
    for ($k = 1; $k -lt $lines.Count; $k++) {
        $line = $lines[$k]
        if ($csvUseComma) {
            if ($line.StartsWith('"') -and $line.EndsWith('"')) { $line = $line.Substring(1, $line.Length - 2) }
            $cells = @($line -split '","')
        } else {
            $cells = @($line -split $delim)
        }
        if ($cells.Count -lt $header.Count) {
            $padded = New-Object string[] $header.Count
            for ($c = 0; $c -lt $header.Count; $c++) { if ($c -lt $cells.Count) { $padded[$c] = $cells[$c] } else { $padded[$c] = '' } }
            $cells = $padded
        }
        $csvRows.Add($cells)
    }
    $totalRows = $csvRows.Count
    Send-Progress 55 "PASO 4 de 8: $totalRows filas leidas"

    Log "  Columnas:"
    for ($i = 0; $i -lt $header.Count; $i++) { Log "    - $($header[$i])" }

    # ── PASO 5: Procesar datos ──
    Send-Progress 60 "PASO 5 de 8: Procesando datos..."
    Log "--- PASO 5: Procesando datos ---"

    $iLpn = if ($colMap.ContainsKey('LPN Pallet')) { $colMap['LPN Pallet'] } else { -1 }
    $iSku = if ($colMap.ContainsKey('SKU')) { $colMap['SKU'] } else { -1 }
    $iVenta = if ($colMap.ContainsKey('Orden de venta')) { $colMap['Orden de venta'] } else { -1 }
    $iEstab = if ($colMap.ContainsKey('Est. Elaborador')) { $colMap['Est. Elaborador'] } else { -1 }
    $iFaen = if ($colMap.ContainsKey('Est. Faenador')) { $colMap['Est. Faenador'] } else { -1 }
    $iBox = if ($colMap.ContainsKey('Box ID')) { $colMap['Box ID'] } else { -1 }
    $iKilos = if ($colMap.ContainsKey('Peso neto (kg)')) { $colMap['Peso neto (kg)'] } else { -1 }
    $iProducto = if ($colMap.ContainsKey('Producto')) { $colMap['Producto'] } else { -1 }

    # Deteccion de columna de produccion: prueba varios patrones
    function ResolveProduccionColumn($headers) {
        $patterns = @('Producci*', 'Fecha Prod*', 'F.*Prod*', 'Production*', 'prod_date*', 'ProdDate*')
        for ($pi = 0; $pi -lt $headers.Count; $pi++) {
            foreach ($p in $patterns) { if ($headers[$pi] -like $p) { return $pi } }
        }
        return -1
    }
    $iProd = ResolveProduccionColumn $header
    if ($iProd -lt 0) {
        Log "WARN: no se detecto columna de fecha de produccion en el CSV (patrones probados). El filtro de fechas estara deshabilitado en la pagina."
    }
    if ($iLpn -lt 0 -or $iSku -lt 0 -or $iKilos -lt 0) { throw "El CSV $($latestCsv.Name) no tiene el formato esperado (faltan columnas: LPN Pallet, SKU, Peso neto (kg)). Elegi el archivo correcto manualmente o cambia de carpeta." }

    Log "  Agrupando por LPN Pallet..."
    $lpnGroups = @{}
    $filasSinLpn = 0
    $skuProducto = @{}
    foreach ($row in $csvRows) {
        $sku = $row[$iSku]
        if (-not [string]::IsNullOrWhiteSpace($sku) -and -not $skuProducto.ContainsKey($sku)) { $skuProducto[$sku] = $row[$iProducto] }
        $lpn = $row[$iLpn]
        if ([string]::IsNullOrWhiteSpace($lpn)) { $filasSinLpn++; continue }
        $venta = if ([string]::IsNullOrWhiteSpace($row[$iVenta])) { "" } else { $row[$iVenta] }
        $estab = if ($iEstab -ge 0 -and -not [string]::IsNullOrWhiteSpace($row[$iEstab])) { $row[$iEstab] } else { "" }
        $faen = if ($iFaen -ge 0 -and -not [string]::IsNullOrWhiteSpace($row[$iFaen])) { $row[$iFaen] } else { "" }
        $box = @($sku, $venta, $estab, $row[$iBox], (ParseNum $row[$iKilos]), "", $faen)
        if ($iProd -ge 0) { $box[5] = $row[$iProd] }
        if (-not $lpnGroups.ContainsKey($lpn)) {
            $lpnGroups[$lpn] = [System.Collections.Generic.List[object]]::new()
        }
        $lpnGroups[$lpn].Add($box)
    }
    Send-Progress 70 "PASO 5 de 8: $($lpnGroups.Count) LPNs agrupados"
    Log "  LPNs unicos: $($lpnGroups.Count)"
    Log "  Filas sin LPN: $filasSinLpn"

    Log "  Agrupando por SKU real de cada caja (pallets multi-SKU se reparten)..."
    $groups = @{}
    $skuConStock = @{}
    $lpnSkus = @{}
    foreach ($lpn in $lpnGroups.Keys) {
        if (-not $lpnSkus.ContainsKey($lpn)) { $lpnSkus[$lpn] = @{} }
        foreach ($b in $lpnGroups[$lpn]) {
            $lpnSkus[$lpn][$b[0]] = $true
            $key = "$($b[0])|$($b[1])|$($b[2])|$($b[6])"
            if (-not $groups.ContainsKey($key)) {
                $groups[$key] = @{ sku=$b[0]; venta=$b[1]; estab=$b[2]; faen=$b[6]; pallets=@{}; cajas=0; kilos=0 }
            }
            $g = $groups[$key]
            $skuConStock[$b[0]] = $true
            if (-not $g.pallets.ContainsKey($lpn)) {
                $g.pallets[$lpn] = @{ lpn=$lpn; cajas=0; kilos=0; boxes=[System.Collections.Generic.List[object]]::new() }
            }
            $p = $g.pallets[$lpn]
            $p.cajas++; $p.kilos += $b[4]; $g.cajas++; $g.kilos += $b[4]
            $p.boxes.Add($b)
        }
    }
    Send-Progress 75 "PASO 5 de 8: $($groups.Count) grupos con stock (un LPN puede estar en varios)"

    # ── PASO 6: Generar registros ──
    Send-Progress 80 "PASO 6 de 8: Generando registros..."
    Log "--- PASO 6: Generando registros ---"

    # Carga de configuracion de analisis manual e historico de cajas Brasil
    $analisisManual = Get-AnalisisManual
    $manualPalletsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $manualBoxesSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($analisisManual.pallets) { foreach ($p in $analisisManual.pallets) { if ($p) { [void]$manualPalletsSet.Add((Normalize-Lpn $p)) } } }
    if ($analisisManual.cajas) { foreach ($c in $analisisManual.cajas) { if ($c) { [void]$manualBoxesSet.Add((Normalize-Lpn $c)) } } }

    $historico = Get-HistoricoCajas
    $csvDt = if ($latestCsv) { $t = Get-FileTime $latestCsv.Name; if ($t) { $t } else { $latestCsv.LastWriteTime } } else { Get-Date }
    $csvDtStr = $csvDt.ToString("yyyy-MM-dd HH:mm:ss")

    $records = [System.Collections.Generic.List[object]]::new()
    $gruposSinCatalogo = 0
    foreach ($key in $groups.Keys) {
        $g = $groups[$key]
        $info = $catalogo[$g.sku]
        if (-not $info) { $gruposSinCatalogo++ }
        $destino = if ($info -and $info.destino -ne "") { $info.destino } elseif ($g.sku.Length -ge 8) { $g.sku.Substring(6, 2) } else { "" }
        $nombre = if ($info) { $info.nombre } else { $skuProducto[$g.sku] }
        $nombre = Format-SkuNombre $g.sku $nombre
        $matSap = if ($info) { $info.matSap } else { "" }
        $esBrasil = Test-EsBrasil $g.sku $destino $nombre

        $palletsList = [System.Collections.Generic.List[object]]::new()
        $totalPallets = 0
        $gCajasOk = 0
        $gCajasPend = 0
        $gKilosOk = 0.0
        $gKilosPend = 0.0
        $gPalletsOk = 0
        $gPalletsPend = 0

        foreach ($lpnKey in $g.pallets.Keys) {
            $p = $g.pallets[$lpnKey]
            $boxesList = [System.Collections.Generic.List[object]]::new()
            $pCajasOk = 0
            $pCajasPend = 0
            $pKilosOk = 0.0
            $pKilosPend = 0.0

            foreach ($b in $p.boxes) {
                $bId = [string]$b[3]
                $bKilos = [double]$b[4]
                $boxAnalisis = "NA"
                $boxManual = $false

                if ($esBrasil) {
                    $bNorm = Normalize-Lpn $bId
                    $pNorm = Normalize-Lpn $p.lpn
                    $isManual = ($manualBoxesSet.Contains($bNorm) -or $manualPalletsSet.Contains($pNorm))
                    if ($historico.ContainsKey($bId)) {
                        $h = $historico[$bId]
                        if ($isManual) {
                            $h.estado = 'ANALISIS_OK'
                            $h.manual = $true
                            $boxAnalisis = 'OK'
                            $boxManual = $true
                        } elseif ($h.estado -eq 'ANALISIS_OK') {
                            $boxAnalisis = 'OK'
                            $boxManual = [bool]$h.manual
                        } else {
                            # Estaba SIN_ANALISIS. Verificar ausencia >= 2 dias
                            if (-not [string]::IsNullOrWhiteSpace($h.ultima_aparicion)) {
                                try {
                                    $prevDt = [DateTime]::Parse($h.ultima_aparicion)
                                    if ($csvDt -gt $prevDt) {
                                        $diasAus = ($csvDt - $prevDt).TotalDays
                                        if ($diasAus -ge 2.0) {
                                            $h.estado = 'ANALISIS_OK'
                                            $h.reingreso_fecha = $csvDtStr
                                            $boxAnalisis = 'OK'
                                            Log "  Caja $bId (SKU $($g.sku)): reingreso tras $([Math]::Round($diasAus, 1)) dias ausente -> ANALISIS_OK"
                                        } else {
                                            $boxAnalisis = 'PENDIENTE'
                                        }
                                    } else {
                                        $boxAnalisis = 'PENDIENTE'
                                    }
                                } catch {
                                    $boxAnalisis = 'PENDIENTE'
                                }
                            } else {
                                $boxAnalisis = 'PENDIENTE'
                            }
                        }
                        try {
                            if ([string]::IsNullOrWhiteSpace($h.ultima_aparicion) -or $csvDt -gt [DateTime]::Parse($h.ultima_aparicion)) {
                                $h.ultima_aparicion = $csvDtStr
                            }
                        } catch { $h.ultima_aparicion = $csvDtStr }
                    } else {
                        # Primera vez que se detecta esta caja Brasil
                        $estado = if ($isManual) { 'ANALISIS_OK' } else { 'SIN_ANALISIS' }
                        $boxAnalisis = if ($isManual) { 'OK' } else { 'PENDIENTE' }
                        $boxManual = $isManual
                        $historico[$bId] = @{
                            sku              = $g.sku
                            primer_ingreso   = $csvDtStr
                            ultima_aparicion = $csvDtStr
                            reingreso_fecha  = ''
                            estado           = $estado
                            manual           = [bool]$isManual
                        }
                    }

                    if ($boxAnalisis -eq 'OK') {
                        $pCajasOk++
                        $pKilosOk += $bKilos
                    } else {
                        $pCajasPend++
                        $pKilosPend += $bKilos
                    }
                } else {
                    $boxAnalisis = 'NA'
                }

                $boxesList.Add(@{
                    boxId      = $bId
                    kilosNeto  = [Math]::Round($bKilos, 2)
                    produccion = $b[5]
                    sku        = $b[0]
                    faenador   = $b[6]
                    analisis   = $boxAnalisis
                    manual     = $boxManual
                })
            }

            $palletAnalisis = if (-not $esBrasil) {
                'NA'
            } elseif ($pCajasPend -eq 0 -and $pCajasOk -gt 0) {
                'OK'
            } else {
                'PENDIENTE'
            }

            if ($palletAnalisis -eq 'OK') { $gPalletsOk++ }
            elseif ($palletAnalisis -eq 'PENDIENTE') { $gPalletsPend++ }

            $gCajasOk += $pCajasOk
            $gCajasPend += $pCajasPend
            $gKilosOk += $pKilosOk
            $gKilosPend += $pKilosPend

            $isMulti = ($lpnSkus[$lpnKey].Count -gt 1)
            $palletsList.Add(@{
                lpn              = $p.lpn
                cajas            = $p.cajas
                kilosNeto        = [Math]::Round($p.kilos, 2)
                cajasDetalle     = $boxesList
                isMulti          = $isMulti
                analisis         = $palletAnalisis
                cajasConAnalisis = $pCajasOk
                cajasSinAnalisis = $pCajasPend
                kilosConAnalisis = [Math]::Round($pKilosOk, 2)
                kilosSinAnalisis = [Math]::Round($pKilosPend, 2)
            })
            $totalPallets++
        }

        # Ordenar pallets: Con Analisis primero, luego Pendiente, luego por LPN
        $palletsArr = @($palletsList | Sort-Object @{ Expression = { if ($_.analisis -eq 'OK') { 0 } elseif ($_.analisis -eq 'PENDIENTE') { 1 } else { 2 } } }, @{ Expression = 'lpn' })

        $grupoAnalisis = if (-not $esBrasil) {
            'NA'
        } elseif ($gCajasPend -eq 0 -and $gCajasOk -gt 0) {
            'OK'
        } elseif ($gCajasOk -eq 0 -and $gCajasPend -gt 0) {
            'PENDIENTE'
        } elseif ($gCajasOk -gt 0 -and $gCajasPend -gt 0) {
            'MIXTO'
        } else {
            'NA'
        }

        $records.Add([PSCustomObject]@{
            sku                = $g.sku
            destino            = $destino
            venta              = $g.venta
            establecimiento    = $g.estab
            estabFaenador      = $g.faen
            nombre             = $nombre
            matSap             = $matSap
            pallets            = $totalPallets
            cajas              = $g.cajas
            kilosNeto          = [Math]::Round($g.kilos, 1)
            esBrasil           = $esBrasil
            analisis           = $grupoAnalisis
            palletsConAnalisis = $gPalletsOk
            palletsSinAnalisis = $gPalletsPend
            cajasConAnalisis   = $gCajasOk
            cajasSinAnalisis   = $gCajasPend
            kilosConAnalisis   = [Math]::Round($gKilosOk, 1)
            kilosSinAnalisis   = [Math]::Round($gKilosPend, 1)
            detalle            = $palletsArr
        })
    }
    Log "  Grupos sin catalogo: $gruposSinCatalogo"
    Save-HistoricoCajas $historico

    Log "  Aprendiendo SKUs del CSV no presentes en el catalogo..."
    $aprendidos = 0
    foreach ($sku in $skuProducto.Keys) {
        if (-not $catalogo.ContainsKey($sku)) {
            $catalogo[$sku] = @{
                destino = if ($sku.Length -ge 8) { $sku.Substring(6, 2) } else { "" }
                nombre  = (Format-SkuNombre $sku $skuProducto[$sku])
                matSap  = ""
            }
            $aprendidos++
        }
    }
    if ($aprendidos -gt 0) {
        try {
            $catalogo | ConvertTo-Json -Depth 3 | Set-Content $catalogoJson -Encoding UTF8
            Log "  SKUs aprendidos y persistidos: $aprendidos"
        } catch { Log "ERROR persistiendo catalogo: $($_.Exception.Message)" }
    } else {
        Log "  Sin SKUs nuevos para aprender"
    }

    Log "  Agregando productos sin stock..."
    $agregadosSinStock = 0
    foreach ($sku in $catalogo.Keys) {
        if (-not $skuConStock.ContainsKey($sku)) {
            $info = $catalogo[$sku]
            $destino = if ($info.destino -ne "") { $info.destino } elseif ($sku.Length -ge 8) { $sku.Substring(6, 2) } else { "" }
            $nom = Format-SkuNombre $sku $info.nombre
            $esBr = Test-EsBrasil $sku $destino $nom
            $records.Add([PSCustomObject]@{
                sku                = $sku
                destino            = $destino
                venta              = ""
                establecimiento    = ""
                estabFaenador      = ""
                nombre             = $nom
                matSap             = $info.matSap
                pallets            = 0
                cajas              = 0
                kilosNeto          = 0
                detalle            = @()
                esBrasil           = $esBr
                analisis           = 'NA'
                palletsConAnalisis = 0
                palletsSinAnalisis = 0
                cajasConAnalisis   = 0
                cajasSinAnalisis   = 0
                kilosConAnalisis   = 0
                kilosSinAnalisis   = 0
            })
            $agregadosSinStock++
        }
    }
    Log "  Sin stock agregados: $agregadosSinStock"

    $conStock = 0; $sinStock = 0
    foreach ($r in $records) { if ($r.pallets -gt 0) { $conStock++ } else { $sinStock++ } }
    Send-Progress 85 "PASO 6 de 8: $($records.Count) registros (con stock: $conStock)"

    # ── PASO 7: Generar JSON y ultima actualizacion ──
    Send-Progress 90 "PASO 7 de 8: Generando datos para la pagina..."
    Log "--- PASO 7: Preparando datos finales ---"
    # Se muestra el dia y hora de CREACION del archivo (no el timestamp del nombre)
    $lastUpdate = $latestCsv.CreationTime.ToString("dd/MM/yyyy HH:mm")

    # ── PASO 7: Comparar con version anterior y registrar cambios ──
    Log "--- PASO 7: Comparando cambios ---"
    $cambiosLog = Join-Path $archivoDir "cambios.log"

    # Rotar si el log actual > 5 MB
    if ((Test-Path -LiteralPath $cambiosLog -PathType Leaf) -and ((Get-Item -LiteralPath $cambiosLog).Length -gt 5242880)) {
        try {
            $rot = Join-Path $archivoDir ("cambios_" + (Get-Date).ToString("yyyyMMdd_HHmmss") + ".log")
            Move-Item -LiteralPath $cambiosLog -Destination $rot -Force
            Log "  cambios.log rotado a: $rot"
        } catch { Log "WARN no se pudo rotar cambios.log: $($_.Exception.Message)" }
    }
    $estadoFile = Join-Path $archivoDir "ultimo_estado.json"

    $totalLpnUnicos = $lpnGroups.Count
    $totalPalletsNow = $totalLpnUnicos
    Log "  Pallets unicos (multi-SKU no duplicados): $totalLpnUnicos"
    $totalCajasNow = ($records | ForEach-Object { $_.cajas } | Measure-Object -Sum).Sum
    $totalKilosNow = ($records | ForEach-Object { $_.kilosNeto } | Measure-Object -Sum).Sum
    $csvNameNow = $latestCsv.Name

    $diffLines = @()
    $diffLines += "========================================"
    $diffLines += "Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $diffLines += "CSV: $csvNameNow (creado: $lastUpdate)"
    $diffLines += ""

    if (Test-Path $estadoFile) {
        $old = Get-Content $estadoFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $diffLines += "Cambios respecto a la ejecucion anterior ($($old.fecha)):"

        $dReg = $records.Count - $old.total
        $dCon = $conStock - $old.conStock
        $dPal = $totalPalletsNow - $old.totalPallets
        $dCaj = $totalCajasNow - $old.totalCajas
        $dKil = $totalKilosNow - $old.totalKilos

        $diffLines += "  Registros totales: $($old.total) -> $($records.Count) ($(if($dReg -ge 0){'+'})$dReg)"
        $diffLines += "  Con stock:          $($old.conStock) -> $conStock ($(if($dCon -ge 0){'+'})$dCon)"
        $diffLines += "  Total pallets:      $($old.totalPallets) -> $totalPalletsNow ($(if($dPal -ge 0){'+'})$dPal)"
        $diffLines += "  Total cajas:        $($old.totalCajas) -> $totalCajasNow ($(if($dCaj -ge 0){'+'})$dCaj)"
        $diffLines += "  Total kilos:        $($old.totalKilos) -> $totalKilosNow ($(if($dKil -ge 0){'+'})$dKil)"

        if ($old.csvName -and $old.csvName -ne $csvNameNow) {
            $diffLines += "  CSV anterior: $($old.csvName)"
            $diffLines += "  CSV nuevo:    $csvNameNow"
        }

        if ($old.skusConStock) {
            $oldSkus = $old.skusConStock | ForEach-Object { "$_" } | Sort-Object
            $newSkus = ($records | Where-Object { $_.pallets -gt 0 } | ForEach-Object { $_.sku }) | Sort-Object
            $added = $newSkus | Where-Object { $_ -notin $oldSkus }
            $removed = $oldSkus | Where-Object { $_ -notin $newSkus }
            if ($added) { $diffLines += "  SKUs NUEVOS con stock: $($added -join ', ')" }
            if ($removed) { $diffLines += "  SKUs SIN stock ahora: $($removed -join ', ')" }
        }
    } else {
        $diffLines += "Primera ejecucion - no hay version anterior para comparar."
        $diffLines += "Registros totales: $($records.Count)"
        $diffLines += "Con stock: $conStock"
        $diffLines += "Total pallets: $totalPalletsNow"
        $diffLines += "Total cajas: $totalCajasNow"
        $diffLines += "Total kilos: $totalKilosNow"
    }

    $diffLines += ""
    $diffLines | Add-Content $cambiosLog -Encoding UTF8
    Log "  Cambios registrados en: $cambiosLog"

    $estadoActual = @{
        fecha = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        total = $records.Count
        conStock = $conStock
        sinStock = $sinStock
        totalPallets = $totalPalletsNow
        totalCajas = $totalCajasNow
        totalKilos = $totalKilosNow
        csvName = $csvNameNow
        skusConStock = @($records | Where-Object { $_.pallets -gt 0 } | ForEach-Object { $_.sku })
    } | ConvertTo-Json
    Set-Content $estadoFile $estadoActual -Encoding UTF8

    # ── PASO 8: Archivar index.html anterior ──
    Send-Progress 95 "PASO 8 de 8: Archivando version anterior..."
    Log "--- PASO 8: Archivando version anterior ---"
    $indexHtmlPath = Join-Path $outDir "index.html"
    if (Test-Path $indexHtmlPath) {
        $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $archivoPath = Join-Path $archivoDir "index_$ts.html"
        Copy-Item $indexHtmlPath $archivoPath -Force
        Log "  Archivado: $archivoPath"
    }

    # ── Enviar datos al navegador ──
    Log "--- PASO 8: Enviando datos ---"
    Log "  Ultima actualizacion: $lastUpdate"
    $payload = @{ stockData = @($records); lastUpdate = $lastUpdate; csvName = $latestCsv.Name; carpeta = $datosDir; fechaProdDisponible = ($iProd -ge 0) } | ConvertTo-Json -Depth 10 -Compress
    Log "  Payload: $([Math]::Round($payload.Length/1KB, 1)) KB"
    $global:cachedPayloadJson = $payload
    $global:cachedPayload = @{ stockData = @($records); lastUpdate = $lastUpdate; csvName = $latestCsv.Name; carpeta = $datosDir; fechaProdDisponible = ($iProd -ge 0) }
    $global:cachedCsvName = $latestCsv.Name
    if ($script:exportStream) {
        Send-Chunk $script:exportStream "DONE:$payload`n"
        Send-TerminalChunk $script:exportStream
    } else {
        Log "Exportacion completada en memoria (cache pre-calentado con $($records.Count) registros)."
    }
}

# ── Pre-calentar runspace del selector de carpeta (abre al instante) ──
try { [void](Get-CarpetaRunspace) } catch { Log "ERROR warm runspace: $($_.Exception.Message)" }

# ── Verificar archivos necesarios ──
if (-not (Test-Path $templatePath)) { throw "No se encontro index.template.html en $workDir" }
if (-not (Test-Path $exceljsPath)) { throw "No se encontro exceljs.min.js en $workDir" }

# ── Determinar puerto y levantar servidor ──
$desiredPort = if ($serverPort) { $serverPort } else { 8080 }
$port = $desiredPort
$listener = $null

try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $desiredPort)
    $listener.Start()
    $port = $desiredPort
} catch {
    Log "WARN: Puerto $desiredPort ocupado ($($_.Exception.Message)), buscando puerto libre..."
    $t = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 0)
    $t.Start()
    $port = ([System.Net.IPEndPoint]$t.LocalEndpoint).Port
    $t.Stop()
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
    $listener.Start()
}

$localIps = @()
try {
    $localIps = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.IPAddressToString -notlike '127.*' }
} catch {}
$primaryIp = if ($localIps.Count -gt 0) { $localIps[0].IPAddressToString } else { "127.0.0.1" }
$hostUrl = "http://$($env:COMPUTERNAME.ToLower()):$port/stock_almacen"
$url = "http://${primaryIp}:$port/stock_almacen"
$localUrl = "http://127.0.0.1:$port/stock_almacen"
Log "Servidor 24/7 iniciado en $hostUrl (red hostname), $url (red IP) y $localUrl (local)"
if (-not $exeMode) {
    Write-Host "========================================"
    Write-Host " Servidor Stock Almacen 24/7 ACTIVO"
    Write-Host " Acceso por Nombre: $hostUrl"
    Write-Host " Acceso por IP:     $url"
    Write-Host " Acceso local:      $localUrl"
    Write-Host "========================================"
}

$noBrowser = ($env:STOCK_NO_BROWSER -eq '1')
if (-not $noBrowser) {
    try { Start-Process $localUrl } catch {}
}

# Pre-calentar cache de datos inicial (apertura web instantanea < 0.05s)
try {
    Log "Pre-calentando cache de stock inicial..."
    $script:exportStream = $null
    Run-Export
    Log "Cache de stock inicial listo y pre-calentado."
} catch {
    Log "WARN pre-calentando cache inicial: $($_.Exception.Message)"
}

$lastActivity = Get-Date
$running = $true
while ($running) {
    if (-not $listener.Pending()) {
        Start-Sleep -Milliseconds 250
        continue
    }
    $client = $listener.AcceptTcpClient()
    $client.NoDelay = $true
    $client.SendBufferSize = 524288
    $client.ReceiveBufferSize = 524288
    $client.ReceiveTimeout = 60000
    $client.SendTimeout = 60000
    try {
        $stream = $client.GetStream()
        $reqLine = Read-HttpLine $stream
        if ($reqLine) {
            $tokens = $reqLine -split ' '
            $rawTarget = $tokens[1]
            $path = ($rawTarget -split '\?')[0]
            $query = if ($rawTarget -match '\?') { ($rawTarget -split '\?', 2)[1] } else { '' }

            # Normalizar subruta /stock_almacen para soportar URL corporativa /stock_almacen
            if ($path -match '^/stock_almacen/?$') {
                $path = '/'
            } elseif ($path -match '^/stock_almacen/(.*)$') {
                $path = '/' + $Matches[1]
            }
            $reqHeaders = @{}
            while ($true) {
                $h = Read-HttpLine $stream
                if ($h -eq $null -or $h -eq '') { break }
                $sep = $h.IndexOf(':')
                if ($sep -ge 0) {
                    $hn = $h.Substring(0, $sep).Trim()
                    $hv = $h.Substring($sep + 1).Trim()
                    $reqHeaders[$hn] = $hv
                }
            }

            # Leer cuerpo si viene Content-Length (POST)
            $body = ''
            if ($reqHeaders.ContainsKey('Content-Length')) {
                $contentLen = 0
                if ([int]::TryParse($reqHeaders['Content-Length'], [ref]$contentLen) -and $contentLen -gt 0 -and $contentLen -lt 10485760) {
                    $buf = New-Object byte[] $contentLen
                    $readTotal = 0
                    while ($readTotal -lt $contentLen) {
                        $r = $stream.Read($buf, $readTotal, $contentLen - $readTotal)
                        if ($r -le 0) { break }
                        $readTotal += $r
                    }
                    $body = [System.Text.Encoding]::UTF8.GetString($buf, 0, $readTotal)
                }
            }

            function Check-Csrf { return ($reqHeaders['X-Local-Token'] -eq $script:csrfToken) }
            switch ($path) {
                '/' {
                    $htmlContent = if (Test-Path (Join-Path $baseDir "index.template.html")) { Get-Content (Join-Path $baseDir "index.template.html") -Raw -Encoding UTF8 } elseif (Test-Path $templatePath) { Get-Content $templatePath -Raw -Encoding UTF8 } elseif ($script:htmlBytes) { [System.Text.Encoding]::UTF8.GetString($script:htmlBytes) } else { $null }
                    if ($htmlContent) {
                        $htmlContent = $htmlContent -replace '@@CSRF_TOKEN@@', $script:csrfToken
                        Send-Bytes $stream 'text/html; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes($htmlContent))
                    } else { Send-Text $stream 404 'text/plain' 'Not found' }
                }
                '/index.html' {
                    $htmlContent = if (Test-Path (Join-Path $baseDir "index.template.html")) { Get-Content (Join-Path $baseDir "index.template.html") -Raw -Encoding UTF8 } elseif (Test-Path $templatePath) { Get-Content $templatePath -Raw -Encoding UTF8 } elseif ($script:htmlBytes) { [System.Text.Encoding]::UTF8.GetString($script:htmlBytes) } else { $null }
                    if ($htmlContent) {
                        $htmlContent = $htmlContent -replace '@@CSRF_TOKEN@@', $script:csrfToken
                        Send-Bytes $stream 'text/html; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes($htmlContent))
                    } else { Send-Text $stream 404 'text/plain' 'Not found' }
                }
                '/exceljs.min.js' {
                    $localExcelJs = Join-Path $baseDir "exceljs.min.js"
                    if (Test-Path $localExcelJs) { Send-File $stream $localExcelJs 'application/javascript; charset=utf-8' }
                    elseif (Test-Path $exceljsPath) { Send-File $stream $exceljsPath 'application/javascript; charset=utf-8' }
                    elseif ($script:exceljsBytes) { Send-Bytes $stream 'application/javascript; charset=utf-8' $script:exceljsBytes }
                    else { Send-Text $stream 404 'text/plain' 'Not found' }
                }
                '/ping' {
                    $latest = Get-LatestStockCsv
                    $hasNew = $false
                    $latestName = ""
                    $latestTime = ""
                    if ($latest) {
                        $latestName = $latest.Name
                        $ft = Get-FileTime $latest.Name
                        $latestTime = if ($ft) { $ft.ToString("dd/MM HH:mm") + " hs" } else { $latest.LastWriteTime.ToString("dd/MM HH:mm") + " hs" }
                        if ($global:cachedCsvName -and ($latest.Name -ne $global:cachedCsvName)) {
                            $hasNew = $true
                        }
                    }
                    if ($query -match 'loaded=([^&]+)') {
                        $loadedVal = [System.Uri]::UnescapeDataString($Matches[1])
                        if ($loadedVal -and ($latestName -and ($latestName -ne $loadedVal))) {
                            $hasNew = $true
                        }
                    }
                    $resp = @{
                        ok         = $true
                        hasNew     = $hasNew
                        currentCsv = $global:cachedCsvName
                        latestCsv  = $latestName
                        latestTime = $latestTime
                    } | ConvertTo-Json -Compress
                    Send-Text $stream 200 'application/json' $resp
                }
                '/elegircarpeta' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' 'Token CSRF invalido'; break }
                    $choice = Show-FolderDialogSync $datosDir
                    if ($choice) {
                        $datosDir = $choice
                        $global:csvSeleccionado = $null
                        $global:cachedPayloadJson = $null
                        $global:cachedPayload = $null
                        try {
                            @{ carpeta = $datosDir; puerto = $port } | ConvertTo-Json | Set-Content $carpetaFile -Encoding UTF8
                            Log "Carpeta de busqueda cambiada a: $datosDir"
                        } catch {}
                        Send-Text $stream 200 'application/json; charset=utf-8' (@{ ok = $true; carpeta = $datosDir } | ConvertTo-Json -Compress)
                    } else {
                        Send-Text $stream 200 'application/json; charset=utf-8' (@{ ok = $false; cancelado = $true } | ConvertTo-Json -Compress)
                    }
                }
                '/elegircsv' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"csrf"}' ; break }
                    $choice = Show-FileDialogSync $datosDir
                    if ($choice) {
                        $global:csvSeleccionado = $choice
                        $global:cachedPayloadJson = $null
                        $global:cachedPayload = $null
                        Log "CSV elegido manualmente: $choice"
                        Send-Text $stream 200 'application/json; charset=utf-8' (@{ ok = $true; archivo = $choice } | ConvertTo-Json -Compress)
                    } else {
                        Send-Text $stream 200 'application/json; charset=utf-8' (@{ ok = $false; cancelado = $true } | ConvertTo-Json -Compress)
                    }
                }
                '/datos' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    # Detectar si hay un CSV mas nuevo en disco que invalide el cache
                    if ($global:cachedPayloadJson -and $global:cachedCsvName) {
                        $discoNewest = Get-LatestStockCsv
                        if ($discoNewest -and ($discoNewest.Name -ne $global:cachedCsvName)) {
                            Log "Nuevo CSV en disco detectado ($($discoNewest.Name) vs cache $($global:cachedCsvName)). Invalidando cache..."
                            $global:cachedPayloadJson = $null
                            $global:cachedPayload = $null
                        }
                    }

                    if ($global:cachedPayloadJson) {
                        Start-Stream $stream
                        try {
                            Send-Chunk $script:exportStream "DONE:$($global:cachedPayloadJson)`n"
                            Send-TerminalChunk $script:exportStream
                        } catch { Send-ErrorLine $_.Exception.Message }
                    } else {
                        Start-Stream $stream
                        try { Run-Export } catch { Send-ErrorLine $_.Exception.Message }
                    }
                }
                '/refrescar' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    $global:cachedPayloadJson = $null
                    $global:cachedPayload = $null
                    Start-Stream $stream
                    try { Run-Export } catch { Send-ErrorLine $_.Exception.Message }
                }
                '/sincronizar-ctto' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }

                    # 1. Verificar si ya hay una sincronización en curso
                    if ($global:isSyncing) {
                        $elapsed = if ($global:syncStartTime) { [Math]::Max(1, [Math]::Round(((Get-Date) - $global:syncStartTime).TotalSeconds)) } else { 1 }
                        Log "Sincronización rechazada: ya hay un proceso en curso (iniciado hace $elapsed seg)."
                        $resp = @{ ok = $false; estado = "en_progreso"; mensaje = "Ya hay una sincronización en curso con CTTO (iniciada hace $elapsed seg). Aguarde unos instantes..." } | ConvertTo-Json -Compress
                        Send-Text $stream 200 'application/json; charset=utf-8' $resp
                        break
                    }

                    # 2. Verificar cooldown anti-spam basado en la fecha del archivo de stock más reciente (180 seg = 3 min)
                    $cooldownSeconds = 180
                    $ultimoCsv = Get-ChildItem -LiteralPath $datosDir -Filter "lista_cajas_*.csv" -File -ErrorAction SilentlyContinue |
                                 Sort-Object LastWriteTime -Descending | Select-Object -First 1

                    if ($ultimoCsv) {
                        $antiguedadSeg = [Math]::Round(((Get-Date) - $ultimoCsv.LastWriteTime).TotalSeconds)
                        if ($antiguedadSeg -ge 0 -and $antiguedadSeg -lt $cooldownSeconds) {
                            $restante = $cooldownSeconds - $antiguedadSeg
                            Log "Sincronización en cooldown: último stock generado hace $antiguedadSeg seg. Restante: $restante seg."
                            $resp = @{ ok = $false; estado = "cooldown"; restante = $restante; mensaje = "El stock fue actualizado recientemente (hace $antiguedadSeg seg). Podrá sincronizar nuevamente en $restante seg." } | ConvertTo-Json -Compress
                            Send-Text $stream 200 'application/json; charset=utf-8' $resp
                            break
                        }
                    }

                    $global:isSyncing = $true
                    $global:syncStartTime = Get-Date
                    Log "Iniciando sincronización manual solicitada desde la interfaz web..."

                    try {
                        $downloaderScript = Join-Path $baseDir "descargar_stock.ps1"
                        if (-not (Test-Path $downloaderScript)) {
                            throw "No se encontró el script de descarga: $downloaderScript"
                        }

                        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
                        $pinfo.FileName = "powershell.exe"
                        $pinfo.Arguments = "-ExecutionPolicy Bypass -File `"$downloaderScript`" -SkipNotify"
                        $pinfo.UseShellExecute = $false
                        $pinfo.RedirectStandardOutput = $true
                        $pinfo.RedirectStandardError = $true
                        $pinfo.CreateNoWindow = $true
                        $proc = [System.Diagnostics.Process]::Start($pinfo)
                        $stdout = $proc.StandardOutput.ReadToEnd()
                        $stderr = $proc.StandardError.ReadToEnd()
                        $proc.WaitForExit(90000)

                        if ($proc.ExitCode -eq 0) {
                            $global:cachedPayloadJson = $null
                            $global:cachedPayload = $null
                            $global:csvSeleccionado = $null
                            Log "Sincronización manual completada con éxito. Pre-calentando cache..."
                            try {
                                $script:exportStream = $null
                                Run-Export
                                Log "Cache pre-calentado exitosamente tras descarga."
                            } catch { Log "WARN pre-calentando tras sync: $($_.Exception.Message)" }

                            $resp = @{ ok = $true; estado = "completado"; mensaje = "Stock sincronizado con éxito desde CTTO 2.1" } | ConvertTo-Json -Compress
                            Send-Text $stream 200 'application/json; charset=utf-8' $resp
                        } else {
                            Log "ERROR en sincronización manual: ExitCode $($proc.ExitCode) - $stderr"
                            $resp = @{ ok = $false; estado = "error"; mensaje = "Error al conectar con CTTO: $stderr" } | ConvertTo-Json -Compress
                            Send-Text $stream 500 'application/json; charset=utf-8' $resp
                        }
                    } catch {
                        Log "ERROR al ejecutar sincronización: $($_.Exception.Message)"
                        $resp = @{ ok = $false; estado = "error"; mensaje = $_.Exception.Message } | ConvertTo-Json -Compress
                        try { Send-Text $stream 500 'application/json; charset=utf-8' $resp } catch {}
                    } finally {
                        $global:isSyncing = $false
                    }
                }
                '/analisis-manual' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    $manualData = Get-AnalisisManual
                    $outObj = [ordered]@{ pallets = [string[]]@($manualData.pallets); cajas = [string[]]@($manualData.cajas) }
                    Send-Text $stream 200 'application/json; charset=utf-8' ($outObj | ConvertTo-Json -Compress)
                }
                '/marcar-analisis' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    try {
                        $manualData = Get-AnalisisManual
                        $palletsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        $cajasSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        if ($manualData.pallets) { foreach ($x in $manualData.pallets) { if ($x) { [void]$palletsSet.Add((Normalize-Lpn $x)) } } }
                        if ($manualData.cajas) { foreach ($x in $manualData.cajas) { if ($x) { [void]$cajasSet.Add((Normalize-Lpn $x)) } } }

                        $inputData = $null
                        if ($body) {
                            try { $inputData = $body | ConvertFrom-Json } catch {}
                        }
                        $nuevosPallets = 0
                        $nuevasCajas = 0
                        if ($inputData) {
                            if ($inputData.pallets) {
                                foreach ($p in $inputData.pallets) {
                                    $pStr = Normalize-Lpn $p
                                    if ($pStr -and $palletsSet.Add($pStr)) { $nuevosPallets++ }
                                }
                            }
                            if ($inputData.cajas) {
                                foreach ($c in $inputData.cajas) {
                                    $cStr = Normalize-Lpn $c
                                    if ($cStr -and $cajasSet.Add($cStr)) { $nuevasCajas++ }
                                }
                            }
                        }
                        if ($query) {
                            $qParams = @{}
                            $query -split '&' | ForEach-Object {
                                $kv = $_ -split '=', 2
                                if ($kv.Count -eq 2) { $qParams[$kv[0]] = [System.Uri]::UnescapeDataString($kv[1]) }
                            }
                            if ($qParams['tipo'] -eq 'pallet' -and $qParams['valor']) {
                                $val = Normalize-Lpn $qParams['valor']
                                if ($val -and $palletsSet.Add($val)) { $nuevosPallets++ }
                            } elseif ($qParams['tipo'] -eq 'caja' -and $qParams['valor']) {
                                $val = Normalize-Lpn $qParams['valor']
                                if ($val -and $cajasSet.Add($val)) { $nuevasCajas++ }
                            }
                        }

                        Save-AnalisisManual @{ pallets = @($palletsSet); cajas = @($cajasSet) }
                        Update-CachedPayloadAnalisis
                        Log "Marcado manual aplicado instantaneamente: $nuevosPallets nuevos pallets, $nuevasCajas nuevas cajas (Total: $($palletsSet.Count) pallets, $($cajasSet.Count) cajas)"
                        $resp = @{ ok = $true; nuevosPallets = $nuevosPallets; nuevasCajas = $nuevasCajas; totalPallets = $palletsSet.Count; totalCajas = $cajasSet.Count } | ConvertTo-Json -Compress
                        Send-Text $stream 200 'application/json; charset=utf-8' $resp
                    } catch {
                        Log "ERROR en /marcar-analisis: $($_.Exception.Message)"
                        Send-Text $stream 500 'application/json; charset=utf-8' (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                }
                '/desmarcar-analisis' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    try {
                        $manualData = Get-AnalisisManual
                        $palletsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        $cajasSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        if ($manualData.pallets) { foreach ($x in $manualData.pallets) { if ($x) { [void]$palletsSet.Add((Normalize-Lpn $x)) } } }
                        if ($manualData.cajas) { foreach ($x in $manualData.cajas) { if ($x) { [void]$cajasSet.Add((Normalize-Lpn $x)) } } }

                        $inputData = $null
                        if ($body) {
                            try { $inputData = $body | ConvertFrom-Json } catch {}
                        }
                        $remPallets = 0
                        $remCajas = 0
                        if ($inputData) {
                            if ($inputData.pallets) {
                                foreach ($p in $inputData.pallets) {
                                    $pStr = Normalize-Lpn $p
                                    if ($pStr -and $palletsSet.Remove($pStr)) { $remPallets++ }
                                }
                            }
                            if ($inputData.cajas) {
                                foreach ($c in $inputData.cajas) {
                                    $cStr = Normalize-Lpn $c
                                    if ($cStr -and $cajasSet.Remove($cStr)) { $remCajas++ }
                                }
                            }
                        }
                        if ($query) {
                            $qParams = @{}
                            $query -split '&' | ForEach-Object {
                                $kv = $_ -split '=', 2
                                if ($kv.Count -eq 2) { $qParams[$kv[0]] = [System.Uri]::UnescapeDataString($kv[1]) }
                            }
                            if ($qParams['tipo'] -eq 'pallet' -and $qParams['valor']) {
                                $val = Normalize-Lpn $qParams['valor']
                                if ($val -and $palletsSet.Remove($val)) { $remPallets++ }
                            } elseif ($qParams['tipo'] -eq 'caja' -and $qParams['valor']) {
                                $val = Normalize-Lpn $qParams['valor']
                                if ($val -and $cajasSet.Remove($val)) { $remCajas++ }
                            }
                        }

                        Save-AnalisisManual @{ pallets = @($palletsSet); cajas = @($cajasSet) }
                        Update-CachedPayloadAnalisis
                        Log "Desmarcado manual instantaneo: $remPallets pallets, $remCajas cajas removidas (Total: $($palletsSet.Count) pallets, $($cajasSet.Count) cajas)"
                        $resp = @{ ok = $true; totalPallets = $palletsSet.Count; totalCajas = $cajasSet.Count } | ConvertTo-Json -Compress
                        Send-Text $stream 200 'application/json; charset=utf-8' $resp
                    } catch {
                        Log "ERROR en /desmarcar-analisis: $($_.Exception.Message)"
                        Send-Text $stream 500 'application/json; charset=utf-8' (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                }
                '/api/cargas' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    try {
                        if ((Get-Date) - $script:lastRomaneosSync -gt [timespan]::FromSeconds(30)) {
                            try { Auto-VincularCargasPendientes } catch {}
                        }
                        $cargas = Get-HistorialCargas
                        $json = if ($cargas -and @($cargas).Count -gt 0) { @($cargas) | ConvertTo-Json -Depth 6 -Compress } else { "[]" }
                        Send-Text $stream 200 'application/json; charset=utf-8' $json
                    } catch {
                        Send-Text $stream 500 'application/json; charset=utf-8' (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                }
                '/api/romaneos' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    try {
                        $romaneos = Sync-RomaneosCapa
                        $json = if ($romaneos -and @($romaneos).Count -gt 0) { @($romaneos) | ConvertTo-Json -Depth 4 -Compress } else { "[]" }
                        Send-Text $stream 200 'application/json; charset=utf-8' $json
                    } catch {
                        Send-Text $stream 500 'application/json; charset=utf-8' (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                }
                '/api/vincular-rs-carga' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    try {
                        $inputData = $null
                        if ($body) {
                            try { $inputData = $body | ConvertFrom-Json } catch {}
                        }
                        if (-not $inputData -or -not $inputData.id) {
                            Send-Text $stream 400 'application/json; charset=utf-8' '{"ok":false,"error":"ID de carga requerido"}'
                            break
                        }
                        $cargas = @(Get-HistorialCargas)
                        $idx = -1
                        for ($i = 0; $i -lt $cargas.Count; $i++) {
                            if ($cargas[$i].id -eq $inputData.id) { $idx = $i; break }
                        }
                        if ($idx -lt 0) {
                            Send-Text $stream 404 'application/json; charset=utf-8' '{"ok":false,"error":"Carga no encontrada"}'
                            break
                        }

                        $allRomaneos = Sync-RomaneosCapa
                        $romaneosDict = @{}
                        foreach ($r in $allRomaneos) {
                            if ($r.romaneo) { $romaneosDict[[string]$r.romaneo] = $r }
                        }

                        $selectedRs = [System.Collections.Generic.List[object]]::new()
                        $totalKg = 0.0
                        $patente = ""

                        if ($inputData.romaneos) {
                            foreach ($rsNum in $inputData.romaneos) {
                                $rsKey = [string]$rsNum
                                if ($romaneosDict.ContainsKey($rsKey)) {
                                    $m = $romaneosDict[$rsKey]
                                    $obj = [ordered]@{
                                        romaneo = [string]$m.romaneo
                                        kgNeto = [double]$m.kgNeto
                                        cajas = [int]$m.cajas
                                        patente = [string]$m.patente
                                        destino = [string]$m.destino
                                        fecha = [string]$m.fecha
                                        hora = [string]$m.hora
                                        observacion = [string]$m.observacion
                                        con = [string]$m.con
                                        conservacion = [string]$m.conservacion
                                    }
                                    $selectedRs.Add($obj)
                                    $totalKg += [double]$m.kgNeto
                                    if (-not $patente -and $m.patente) { $patente = [string]$m.patente }
                                }
                            }
                        }

                        $item = $cargas[$idx]
                        Set-Prop $item "romaneos" @($selectedRs)
                        Set-Prop $item "kilos_reales" ([Math]::Round($totalKg, 2))
                        if ($patente) { Set-Prop $item "patente" $patente }
                        Set-Prop $item "conservacion" (Get-CargaConservacion $item)
                        Set-Prop $item "manual_rs" $true
                        $nuevoEstado = if ($totalKg -gt 0) { "Cerrada" } else { "En Proceso" }
                        Set-Prop $item "estado" $nuevoEstado

                        $cargas[$idx] = $item
                        Save-HistorialCargas $cargas
                        Log "RS vinculados manualmente para $($item.id): $($selectedRs.Count) RS ($($item.conservacion)), $($item.kilos_reales) kg neto"
                        Send-Text $stream 200 'application/json; charset=utf-8' (@{ ok = $true; carga = $item } | ConvertTo-Json -Depth 6 -Compress)
                    } catch {
                        Log "ERROR en /api/vincular-rs-carga: $($_.Exception.Message)"
                        Send-Text $stream 500 'application/json; charset=utf-8' (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                }
                '/api/sincronizar-romaneos' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    try {
                        $roms = Sync-RomaneosCapa -Force
                        Auto-VincularCargasPendientes
                        $cargas = Get-HistorialCargas
                        Send-Text $stream 200 'application/json; charset=utf-8' (@{ ok = $true; totalRomaneos = $roms.Count; cargas = $cargas } | ConvertTo-Json -Depth 6 -Compress)
                    } catch {
                        Send-Text $stream 500 'application/json; charset=utf-8' (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                }
                '/api/guardar-carga' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    try {
                        $inputData = $null
                        if ($body) {
                            try { $inputData = $body | ConvertFrom-Json } catch {}
                        }
                        if (-not $inputData) {
                            Send-Text $stream 400 'application/json; charset=utf-8' '{"ok":false,"error":"Cuerpo vacio o invalido"}'
                            break
                        }
                        $cargas = @(Get-HistorialCargas)
                        $now = Get-Date
                        $cargaId = if ($inputData.id) { [string]$inputData.id } else { "CRG-" + $now.ToString("yyyyMMdd-HHmmss") }

                        $nuevaCarga = [ordered]@{
                            id = $cargaId
                            fecha = if ($inputData.fecha) { [string]$inputData.fecha } else { $now.ToString("yyyy-MM-dd") }
                            hora = if ($inputData.hora) { [string]$inputData.hora } else { $now.ToString("HH:mm:ss") }
                            estado = if ($inputData.estado) { [string]$inputData.estado } else { "En Proceso" }
                            pallets_solicitados = if ($inputData.pallets_solicitados -ne $null) { [int]$inputData.pallets_solicitados } else { 0 }
                            kilos_estimados = if ($inputData.kilos_estimados -ne $null) { [double]$inputData.kilos_estimados } else { 0.0 }
                            kilos_reales = if ($inputData.kilos_reales -ne $null -and "$($inputData.kilos_reales)".Trim() -ne "") { [double]$inputData.kilos_reales } else { $null }
                            observaciones = if ($inputData.observaciones) { [string]$inputData.observaciones } else { "" }
                            ordenes_count = if ($inputData.ordenes_count -ne $null) { [int]$inputData.ordenes_count } else { 0 }
                            items = if ($inputData.items) { @($inputData.items) } else { @() }
                        }

                        $idx = -1
                        for ($i = 0; $i -lt $cargas.Count; $i++) {
                            if ($cargas[$i].id -eq $cargaId) { $idx = $i; break }
                        }
                        if ($idx -ge 0) {
                            $cargas[$idx] = $nuevaCarga
                        } else {
                            $cargas = @($nuevaCarga) + $cargas
                        }
                        Save-HistorialCargas $cargas
                        $resp = @{ ok = $true; id = $cargaId; carga = $nuevaCarga } | ConvertTo-Json -Depth 6 -Compress
                        Send-Text $stream 200 'application/json; charset=utf-8' $resp
                    } catch {
                        Log "ERROR en /api/guardar-carga: $($_.Exception.Message)"
                        Send-Text $stream 500 'application/json; charset=utf-8' (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                }
                '/api/actualizar-carga' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    try {
                        $inputData = $null
                        if ($body) {
                            try { $inputData = $body | ConvertFrom-Json } catch {}
                        }
                        if (-not $inputData -or -not $inputData.id) {
                            Send-Text $stream 400 'application/json; charset=utf-8' '{"ok":false,"error":"ID requerido"}'
                            break
                        }
                        $cargas = @(Get-HistorialCargas)
                        $idx = -1
                        for ($i = 0; $i -lt $cargas.Count; $i++) {
                            if ($cargas[$i].id -eq $inputData.id) { $idx = $i; break }
                        }
                        if ($idx -lt 0) {
                            Send-Text $stream 404 'application/json; charset=utf-8' '{"ok":false,"error":"Carga no encontrada"}'
                            break
                        }

                        $item = $cargas[$idx]
                        if ($inputData.PSobject.Properties['kilos_reales']) {
                            if ($inputData.kilos_reales -ne $null -and "$($inputData.kilos_reales)".Trim() -ne "") {
                                $item.kilos_reales = [double]$inputData.kilos_reales
                            } else {
                                $item.kilos_reales = $null
                            }
                        }
                        if ($inputData.PSobject.Properties['estado']) { $item.estado = [string]$inputData.estado }
                        if ($inputData.PSobject.Properties['observaciones']) { $item.observaciones = [string]$inputData.observaciones }
                        if ($inputData.PSobject.Properties['fecha']) { $item.fecha = [string]$inputData.fecha }

                        $cargas[$idx] = $item
                        Save-HistorialCargas $cargas
                        Send-Text $stream 200 'application/json; charset=utf-8' (@{ ok = $true; carga = $item } | ConvertTo-Json -Depth 6 -Compress)
                    } catch {
                        Log "ERROR en /api/actualizar-carga: $($_.Exception.Message)"
                        Send-Text $stream 500 'application/json; charset=utf-8' (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                }
                '/api/eliminar-carga' {
                    if (-not (Check-Csrf)) { Send-Text $stream 403 'text/plain' '{"error":"CSRF"}' ; break }
                    try {
                        $inputData = $null
                        if ($body) {
                            try { $inputData = $body | ConvertFrom-Json } catch {}
                        }
                        if (-not $inputData -or -not $inputData.id) {
                            Send-Text $stream 400 'application/json; charset=utf-8' '{"ok":false,"error":"ID requerido"}'
                            break
                        }
                        $cargas = @(Get-HistorialCargas)
                        $nuevas = @()
                        foreach ($c in $cargas) {
                            if ($c.id -eq $inputData.id) {
                                if ($inputData.anular -eq $true) {
                                    $c.estado = "Anulada"
                                    $nuevas += $c
                                }
                            } else {
                                $nuevas += $c
                            }
                        }
                        Save-HistorialCargas $nuevas
                        Send-Text $stream 200 'application/json; charset=utf-8' (@{ ok = $true; id = $inputData.id } | ConvertTo-Json -Compress)
                    } catch {
                        Log "ERROR en /api/eliminar-carga: $($_.Exception.Message)"
                        Send-Text $stream 500 'application/json; charset=utf-8' (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                }
                default { Send-Text $stream 404 'text/plain' 'Not found' }
            }
        }
    } catch {
        Log "ERROR servidor: $($_.Exception.Message)"
    }
    try { $client.Close() } catch {}
}
$listener.Stop()
Log ""
Log "========================================"
Log " FIN: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Log "========================================"
Log ""
exit 0
