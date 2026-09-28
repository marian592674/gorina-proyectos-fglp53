# Bitácora de Cambios — P005.Supervisor.General

## [v1.0.0] - 2026-09-28
### Migración a Base de Datos MySQL `p005.supervisor.general` y Watchdog 24-7 Unificado

#### 1. Base de Datos MySQL
- Creado e inicializado el esquema `` `p005.supervisor.general` `` en MySQL 8.0 local (`127.0.0.1:3306`).
- Tablas creadas:
  - `servicios`: Catálogo de 9 servicios y tareas supervisadas de P001 a P005, con columnas para estado actual, último chequeo, último OK, latencia en ms, mensaje de estado y comando vigilante de auto-recuperación.
  - `incidentes`: Histórico de caídas, alertas, restablecimientos y pruebas, con detalle técnico, asunto de alerta, destinatarios y estado de notificación. Migrados los 20 incidentes previos.
  - `historial_checks`: Registro continuo de telemetría de salud (pings, tiempos de respuesta HTTP y estado de tareas) con purga automática de registros con más de 30 días.
  - `configuracion`: Parámetros operativos (intervalo de monitoreo, switches de alertas, servidor SMTP corporativo).

#### 2. Watchdog y Auto-Recuperación
- Actualizado [`supervisor_servicios_24-7.ps1`](file:///D:/PROYECTOS/P005.Supervisor.General/supervisor_servicios_24-7.ps1):
  - Monitorea periódicamente todos los endpoints HTTP (puertos 80, 8080, 8090, 5000, 8765) y el estado de las tareas de Windows.
  - Si detecta un servicio caído (`DOWN`), dispara automáticamente el vigilante correspondiente para reiniciarlo sin intervención humana.
  - Registra el incidente en MySQL y actualiza el snapshot en vivo.
- Actualizada la tarea programada `Gorina - Supervisor General 24-7` con disparador de inicio del sistema (`AtStartup` / `MSFT_TaskBootTrigger`) y repetición continua cada 3 minutos.

#### 3. Herramientas de Gestión y Manual Institucional
- Actualizado [`1_DIAGRAMA_Y_MANUAL.html`](file:///D:/PROYECTOS/P005.Supervisor.General/1_DIAGRAMA_Y_MANUAL.html):
  - Nuevo título: **Mapa de Proyectos y Flujo de Datos**.
  - Diseño y paleta institucional en **rojo y blanco** representativa de Frigorífico Gorina.
  - Integrado el logotipo oficial de Gorina en la barra superior izquierda (`Logo Gorina Solo letras.jpg` codificado en Base64).
  - Publicado y sincronizado en los sitios IIS de Producción (`http://fglp53/tablero.ciclo3/1_DIAGRAMA_Y_MANUAL.html`) y Laboratorio.
- Actualizado [`2_VER_ESTADO_DE_ALERTAS.bat`](file:///D:/PROYECTOS/P005.Supervisor.General/2_VER_ESTADO_DE_ALERTAS.bat) para consultar y formatear directamente la tabla de servicios e historial de incidentes desde MySQL.
- Corregida la ruta de logs en `supervisor_servicios_24-7.ps1` para operar dentro de `D:\PROYECTOS\P005.Supervisor.General\logs\` y eliminada la carpeta externa obsoleta `D:\GorinaData\P005.Supervisor.General`.
