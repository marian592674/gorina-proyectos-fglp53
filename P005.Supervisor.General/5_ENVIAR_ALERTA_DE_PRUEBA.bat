@echo off
chcp 65001 >nul
title Enviar Alerta de Prueba por Correo
echo ==============================================================================
echo        FRIGORIFICO GORINA — ENVIO DE ALERTA DE PRUEBA POR CORREO
echo ==============================================================================
echo.
echo Enviando alerta de prueba a los destinatarios activos...
echo.
cd /d "D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\colector_test"
python monitor_alertas.py --test-mail
echo.
echo ==============================================================================
echo Proceso finalizado.
echo Si no lo ve en la Bandeja de Entrada, revise la carpeta "Correo no deseado" (Spam)
echo o la pestaña "Otros" de Outlook.
echo ==============================================================================
echo.
pause
