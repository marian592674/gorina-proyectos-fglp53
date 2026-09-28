$ErrorActionPreference = 'Stop'

# Resuelve rutas relativas a la ubicacion de este script (portable)
$src = $PSScriptRoot
if (-not $src) { $src = Split-Path -Parent $MyInvocation.MyCommand.Path }

function Read-Utf8NoBom([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Wrap-B64([byte[]]$bytes, [int]$width = 100) {
    $b64 = [Convert]::ToBase64String($bytes)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $b64.Length) {
        $len = [Math]::Min($width, $b64.Length - $i)
        [void]$sb.Append($b64.Substring($i, $len))
        [void]$sb.Append("`r`n")
        $i += $len
    }
    return $sb.ToString().TrimEnd("`r", "`n")
}

$ps1 = Read-Utf8NoBom (Join-Path $src 'exportar_stock.ps1')

$assets = @(
    @{ token = '@@HTML_B64@@';      file = Join-Path $src 'index.template.html' },
    @{ token = '@@EXCELJS_B64@@';   file = Join-Path $src 'exceljs.min.js' },
    @{ token = '@@XLSX_B64@@';      file = Join-Path $src 'Stock.Almacen.Base.xlsx' },
    @{ token = '@@CATALOGO_B64@@';  file = Join-Path $src 'catalogo.json' }
)

foreach ($a in $assets) {
    if (-not (Test-Path -LiteralPath $a.file -PathType Leaf)) { throw "Falta asset: $($a.file)" }
    $b64 = Wrap-B64 ([System.IO.File]::ReadAllBytes($a.file))
    $ps1 = $ps1.Replace($a.token, $b64)
    Write-Host "Embebido: $($a.file) ($([Math]::Round((Get-Item $a.file).Length/1KB,1)) KB)"
}

if ($ps1 -match '@@[A-Z]+_B64@@') { throw 'Quedaron placeholders sin reemplazar' }

$built = Join-Path $src 'exportar_stock_packed.ps1'
[System.IO.File]::WriteAllText($built, $ps1, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "PS1 empaquetado: $built"

$exe = Join-Path $src 'ExportarStock.exe'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module PS2EXE -Force -ErrorAction Stop
ps2exe -inputFile $built -outputFile $exe -noConsole -noOutput -noError -title 'Stock Almacen Congelado' -version 1.5.0.0 -product 'Stock Almacen' -company 'Gorina' -verbose:$false
Write-Host "EXE compilado: $exe"

Remove-Item $built -Force -ErrorAction SilentlyContinue
Write-Host "Limpiado: $built"