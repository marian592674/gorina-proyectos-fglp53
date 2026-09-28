@echo off
echo Restaurando version anterior de Dashboards...
copy /Y "D:\PROYECTOS\P001.Dashboard.Ciclo.3\ARCHIVO\BACKUP_PRE_KPIS_FECHAS_2026-09-11\LAB_dashboard_operaciones.html" "D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\dashboard_test\dashboard_operaciones.html"
copy /Y "D:\PROYECTOS\P001.Dashboard.Ciclo.3\ARCHIVO\BACKUP_PRE_KPIS_FECHAS_2026-09-11\PROD_dashboard_operaciones.html" "D:\PROYECTOS\P001.Dashboard.Ciclo.3\PROD\dashboard\dashboard_operaciones.html"
echo Restauracion completada con exito.
pause
