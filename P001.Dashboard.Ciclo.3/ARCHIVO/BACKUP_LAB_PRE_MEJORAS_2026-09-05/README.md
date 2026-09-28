# LAB_SQL_TEST - Entorno de pruebas aislado (NO afecta PROD)

## PROD (operativo, NO TOCAR)
- C:\Ciclo3\Servicios\dashboard\  -> http://192.168.0.126/dashboard_operaciones.html (sheet)
- C:\Ciclo3\Servicios\colector\   -> source=sheet
- Tarea: Gorina - Colector datos (cada 5 min)

## LAB (para probar SQL TRV sin romper PROD)
- C:\Ciclo3\Servicios\LAB_SQL_TEST\colector_test\   -> config apunta a dashboard_test
- C:\Ciclo3\Servicios\LAB_SQL_TEST\dashboard_test\ -> datos.json de prueba
- Probar: C:\Users\gorinahostadmin\AppData\Local\Programs\Python\Python312\python.exe C:\Ciclo3\Servicios\LAB_SQL_TEST\colector_test\colector.py --test
- Ver: http://192.168.0.126/LAB_datos.json  (si se expone) o abrir archivo directo

## Flujo incremental propuesto
1. Configurar solo TRV en LAB: completar sql.servers.TRV con IP/BD/PWD del TRV que ya tenes acceso, crear vista vw_tablero_trv1 (dba_entregables/02_vistas_trv.sql)
2. Probar LAB: python colector_test\colector.py --test -> debe dar trv OK, crane queda sheet
3. Cuando funcione, implementar modo hybrid real en colector.py (hoy ya tolera fallo parcial: si crane SQL falla, conserva ultimo dato sheet)
4. Solo cuando LAB este validado, copiar config a PROD: source=sql

## No exponer LAB por IIS
Por ahora LAB no tiene sitio IIS. Para ver dashboard_test, abrir archivo directo o crear sitio temporal en puerto 8080.
