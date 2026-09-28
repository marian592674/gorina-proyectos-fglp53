# Instructivo Informes Automáticos - Gorina Ciclo 3 - LAB :8080

## Donde están
- PROD (Sheets, oficial): C:\Ciclo3\Servicios\DASHBOARD\PROD\dashboard\ -> http://192.168.0.126/dashboard_operaciones.html
- LAB (MySQL p003148 + PDF idéntico): C:\Ciclo3\Servicios\DASHBOARD\LAB\ -> http://192.168.0.126:8080/dashboard_operaciones.html
- Config mail: C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\config.json (seccion "mail")
- Script envio: C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\envio_informe.py
- Destinatarios guia: C:\Ciclo3\Servicios\DASHBOARD\LAB\destinatarios.txt

## Como agregar mails
1. Abrir C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\config.json con Notepad
2. Buscar "weekly_to" y "monthly_to"
   "weekly_to": ["mariano.diaz@friggorina.com", "nuevo@friggorina.com"],
   "monthly_to": ["mariano.diaz@friggorina.com"]
3. Agregar mails entre comillas, separados por coma, guardar.

## Como saber si está activo
Abrir CMD como Admin y ejecutar:
  schtasks /query /tn "Gorina LAB - Informe Semanal" /v
  schtasks /query /tn "Gorina LAB - Informe Mensual" /v
Debe decir Estado: Listo, Habilitado, Proxima ejecucion: viernes 18:00 / ultimo dia 18:00
Ver logs: C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\logs\ (colector.log)

## Como hacer una prueba manual (sin esperar al viernes)
Abrir PowerShell o CMD:
  C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\envio_informe.py --weekly
  C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\envio_informe.py --monthly
Debe decir "Mail enviado: Informe Semanal..." y llegar a mariano.diaz@friggorina.com con PDF Informe_Semanal_Ciclo3_YYYY-MM-DD.pdf (8 paginas, idéntico al manual).

## PDF
Nombre: Informe_Semanal_Ciclo3_YYYY-MM-DD.pdf / Informe_Mensual_Ciclo3_YYYY-MM-DD.pdf
Contenido: idéntico al boton "Descargar informe" del dashboard (8 paginas, 4 sistemas TRV/TRV2/COMB/CRANE con KPIs, graficos y tablas), generado via Playwright desde http://localhost:8080

## SMTP
Host: smtp.gmail.com:587 TLS, From: ciclo3.almacen@friggorina.com, App Password en config.json mail.smtp_pass (16 letras sin espacios)
Si cambia la clave, actualizar config.json y probar con --weekly
