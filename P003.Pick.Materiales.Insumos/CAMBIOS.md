# Bitácora de Cambios — P003.Pick.Materiales.Insumos

## [v2.0.0] - 2026-09-28
### Migración a Base de Datos MySQL `p003.pick.materiales.insumos`
- Migrada la base de datos a MySQL 8.0 local bajo el nombre en minúsculas `` `p003.pick.materiales.insumos` ``.
- Backend en C# .NET 8 (`Gorina.Api.exe`) en puerto 5000.
- Servicio vigilante `vigilante_gorina_api.ps1` configurado con inicio `AtStartup` y repetición cada 5 minutos en el Programador de Tareas (`Gorina - GorinaPick API 24-7`).
