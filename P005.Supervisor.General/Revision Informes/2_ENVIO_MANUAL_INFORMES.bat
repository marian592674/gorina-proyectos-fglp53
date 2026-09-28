@echo off
title Envio Manual de Informes - Ciclo 3 Frigorifico Gorina
chcp 65001 > nul
cd /d "D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\colector_test"
set "PY=C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe"
if not exist "%PY%" set "PY=python"
"%PY%" menu_envio_informes.py
