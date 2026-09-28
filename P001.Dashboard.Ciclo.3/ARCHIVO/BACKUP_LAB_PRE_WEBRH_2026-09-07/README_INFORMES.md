# Instructivo Informes Automáticos - Gorina Ciclo 3 - LAB :8080

## Donde están
- PROD (Sheets, oficial): C:\Ciclo3\Servicios\DASHBOARD\PROD\dashboard\ -> http://192.168.0.126/dashboard_operaciones.html
- LAB (MySQL p003148 + PDF idéntico): C:\Ciclo3\Servicios\DASHBOARD\LAB\ -> http://192.168.0.126:8080/dashboard_operaciones.html
- Destinatarios (UNICO para semanal y mensual): C:\Ciclo3\Servicios\DASHBOARD\LAB\destinatarios.txt
- Script envio: C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\envio_informe.py

## Como agregar mails (sencillo, vale para ambos informes)
1. Abrir C:\Ciclo3\Servicios\DASHBOARD\LAB\destinatarios.txt con Notepad
2. Agregar un mail por linea, sin comas:
   mariano.diaz@friggorina.com
   juan.perez@friggorina.com
   notificaciones@friggorina.com
3. Guardar. La proxima ejecucion (viernes 18:00 o ultimo dia) les llegara a todos.

## Como saber si está activo
Abrir CMD como Admin:
  schtasks /query /tn "Gorina LAB - Informe Semanal" /v
  schtasks /query /tn "Gorina LAB - Informe Mensual" /v
Debe decir Estado: Listo, Habilitado, Proxima: viernes 18:00 / 31/08 18:00

## Prueba manual (sin esperar)
  C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\envio_informe.py --weekly
  C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\envio_informe.py --monthly
Debe decir "Mail enviado..." y llegar con PDF Informe_Semanal_Ciclo3_YYYY-MM-DD.pdf (8 paginas, idéntico al manual).

## PDF y Horarios
- Semanal: viernes 18:00 -> Informe_Semanal_Ciclo3_YYYY-MM-DD.pdf
- Mensual: ultimo dia mes 18:00 -> Informe_Mensual_Ciclo3_YYYY-MM-DD.pdf
- Contenido: identico al boton "Descargar informe" (4 sistemas TRV/TRV2/COMB/CRANE, KPIs, graficos, tablas) via Playwright

## SMTP
Host: smtp.gmail.com:587 TLS, From: ciclo3.almacen@friggorina.com, App Password en LAB\colector_test\config.json (mail.smtp_pass)
