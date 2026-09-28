@echo off
echo ====================================================
echo ESTADO DE LA API (Gorina.Api)
echo ====================================================
curl -s http://localhost:5000/api/ping >nul
if errorlevel 1 (
    echo [ERROR] La API NO esta respondiendo.
    echo Asegurese de ejecutar el script de inicio primero.
) else (
    echo [OK] La API esta FUNCIONANDO en el puerto 5000.
)
echo.
echo ====================================================
echo ESTADISTICAS DE SESION
echo ====================================================
D:\PROYECTOS\P003.Pick.Materiales.Insumos\servidor\publicar\sqlite3.exe -header -column D:\PROYECTOS\P003.Pick.Materiales.Insumos\servidor\publicar\gorina.db "SELECT COUNT(DISTINCT usuario) as [Usuarios Conectados], COALESCE(MAX(creada), 'Nadie se logueo aun') as [Ultimo Login] FROM sesiones;"
echo ====================================================
echo ULTIMA ACTIVIDAD DE MATERIALES
echo ====================================================
D:\PROYECTOS\P003.Pick.Materiales.Insumos\servidor\publicar\sqlite3.exe -header -column D:\PROYECTOS\P003.Pick.Materiales.Insumos\servidor\publicar\gorina.db "SELECT p.material_sap as [Ultimo Material Agregado], p.cantidad_lectura as [Cantidad], o.fecha_cierre as [Fecha], o.usuario as [Usuario] FROM posiciones p JOIN operaciones o ON o.id = p.operacion_id ORDER BY o.fecha_cierre DESC LIMIT 1;"
echo ====================================================
echo ESTADO TABLERO CARNICERIA (Puerto 8765)
echo ====================================================
curl -s http://localhost:8765/api/estado >nul
if errorlevel 1 (
    echo [ERROR] El Tablero de Carniceria NO esta respondiendo.
) else (
    echo [OK] Tablero Carniceria FUNCIONANDO en http://fglp53:8765/tablero_carniceria
)
echo.
pause