@echo off
cd /d "%~dp0"
if not exist "logs" mkdir "logs"
set PYTHON_EXE=C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe
if not exist "%PYTHON_EXE%" set PYTHON_EXE=python

echo [%date% %time%] Iniciando actualizacion diaria >> "logs\actualizaciones.log"
"%PYTHON_EXE%" importador.py diario >> "logs\actualizaciones.log" 2>&1
echo [%date% %time%] Fin de proceso (Errorlevel: %ERRORLEVEL%) >> "logs\actualizaciones.log"
exit /b %ERRORLEVEL%
