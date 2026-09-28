@echo off
REM ============================================================
REM  Publica Gorina.Api como UN solo ejecutable autocontenido
REM  Resultado en: servidor\publicar\Gorina.Api.exe
REM  (no requiere .NET instalado en el servidor de destino)
REM ============================================================
echo Compilando version de produccion...
dotnet publish "%~dp0Gorina.Api\Gorina.Api.csproj" -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o "%~dp0publicar"
if errorlevel 1 (
    echo ERROR: la compilacion fallo.
    pause
    exit /b 1
)
copy /y "%~dp0Gorina.Api\config.json" "%~dp0publicar\config.json" >nul
echo.
echo Listo. Archivos generados en servidor\publicar\
echo   Gorina.Api.exe  +  config.json
echo.
echo Pasos en el servidor:
echo   1) Copiar la carpeta publicar al servidor Windows.
echo   2) Editar config.json: CarpetaSalida, Puerto, etc.
echo   3) Importar maestros:
echo        Gorina.Api.exe --importar-equivalencias Equivalencias.xlsx
echo        Gorina.Api.exe --importar-cecos "Centros de Costo.xlsx"
echo        Gorina.Api.exe --importar-almacenes Almacenes.xlsx
echo   4) Ejecutar Gorina.Api.exe  (queda escuchando en el puerto configurado)
echo.
pause
