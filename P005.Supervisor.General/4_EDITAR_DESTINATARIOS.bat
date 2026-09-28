@echo off
chcp 65001 >nul
title Editar Destinatarios de Alertas
echo ==============================================================================
echo Abriendo lista de destinatarios en Bloc de Notas...
echo - Agregue o quite correos (uno por línea).
echo - Use '#' al inicio para pausar un correo sin borrarlo.
echo - Al guardar (Ctrl+G), el cambio se aplica automáticamente.
echo ==============================================================================
start notepad.exe "D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\colector_test\destinatarios_alertas.txt"
