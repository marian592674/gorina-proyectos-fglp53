@echo off
chcp 65001 >nul
title Panel Unificado - Configurar, Pausar Alertas y Editar Destinatarios
cd /d "D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\colector_test"
python monitor_alertas.py --toggle
