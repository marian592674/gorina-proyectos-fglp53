---
name: powershell-security-quality
description: Validates and audits PowerShell scripts (.ps1, .psm1) for code injection vulnerabilities, secure parameter handling, resource leaks, and PSScriptAnalyzer compliance. Use when creating, modifying, or reviewing PowerShell code.
---

# PowerShell Security and Code Quality

## Scope & Applicability
Aplica a todos los scripts PowerShell (`.ps1`), scripts empaquetadores (`pack.ps1`), scripts de servidor HTTP (`HttpListener`) y utilitarios del proyecto.

## AI Agent Audit Checklist

### 1. Inyección y Ejecución Dinámica
- [ ] **NO usar `Invoke-Expression` (`iex`):** Prohibido el uso de `Invoke-Expression` o bloques de script interpolados dinámicamente con strings no confiables.
- [ ] **Pasaje seguro de argumentos:** Comandos externos y cmdlets deben recibir argumentos como arrays o parámetros tipados, nunca strings concatenados.
- [ ] **Sanitización de rutas de archivo:** Evitar concatenación manual de strings para rutas (`$path = "$dir\$file"`). Usar siempre `Join-Path` o `[System.IO.Path]::Combine`.
- [ ] **Validación de rutas (Path Traversal):** Validar con `Test-Path -LiteralPath` o resolver rutas garantizando que permanezcan dentro del directorio raíz autorizado.

### 2. Manejo de Errores y Confiabilidad
- [ ] **Preferencia de errores estricta:** Establecer `$ErrorActionPreference = 'Stop'` en encabezados de script o bloques críticos para evitar fallos silenciosos.
- [ ] **Try/Catch granular:** Capturar excepciones específicas cuando sea posible (ej. `[System.IO.IOException]`) en vez de bloques vacíos `catch {}`.
- [ ] **Códigos de salida:** Validar y propagar adecuadamente códigos de salida `$LASTEXITCODE` en llamadas a herramientas externas.

### 3. Gestión de Recursos y Streams HTTP/IO
- [ ] **Cierre garantizado de Streams:** En servidores basados en `HttpListener`, garantizar que `OutputStream.Close()`, `StreamReader.Dispose()`, o listeners se cierren en bloques `finally`.
- [ ] **Fugas de memoria en procesos continuos:** Evitar acumular memoria indefinidamente en arrays estáticos durante loops de escucha prolongados.

### 4. Buenas Prácticas de Estilo y Naming
- [ ] **Evitar alias en scripts de producción:** Usar nombres canónicos de cmdlets (ej. `Get-ChildItem` en vez de `dir`/`ls`, `Select-Object` en vez de `select`, `Where-Object` en vez de `?`).
- [ ] **Aprobación de verbos oficiales:** Funciones personalizadas deben seguir la convención estándar `Verb-Noun` (ej. `Get-StockData`, `Export-StockReport`).

---

## Ejemplos

### ❌ Inseguro (Riesgo de inyección y fuga de stream)
```powershell
$filename = $Request.QueryString["file"]
$cmd = "Get-Content C:\Data\$filename"
Invoke-Expression $cmd
$response.OutputStream.Write($bytes, 0, $bytes.Length)
# Falta OutputStream.Close() en bloque protegido
```

### ✅ Seguro y Robusto
```powershell
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[a-zA-Z0-9_\-]+\.csv$')]
    [string]$FileName
)

$baseDir = "C:\Data"
$targetPath = Join-Path -Path $baseDir -ChildPath $FileName

if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    throw [System.IO.FileNotFoundException]"El archivo especificado no existe o es inválido."
}

try {
    $content = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
} finally {
    if ($Response.OutputStream) {
        $Response.OutputStream.Close()
    }
}
```
