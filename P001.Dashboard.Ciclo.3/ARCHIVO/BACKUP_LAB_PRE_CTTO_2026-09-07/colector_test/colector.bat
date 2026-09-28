@echo off
REM Colector Gorina - una corrida (genera/actualiza datos.json)
cd /d "%~dp0"
REM usar python absoluto para evitar alias Store y PATH de SYSTEM
set "PY=C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe"
if not exist "%PY%" set "PY=python"
"%PY%" colector.py
exit /b %errorlevel%
