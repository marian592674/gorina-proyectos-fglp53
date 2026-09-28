# Bitácora de Cambios — P004.Carniceria.Tablero

## [v2.0.0] - 2026-09-28
### Migración a Base de Datos MySQL `p004.carniceria.tablero` y .NET 8
- Migrada la base de datos a MySQL 8.0 local bajo el nombre en minúsculas `` `p004.carniceria.tablero` ``.
- Backend reescrito en C# .NET 8 Minimal API (`Gorina.Carniceria.Api.exe`) en puerto 8765.
- Tarea programada `Gorina - Carniceria Tablero 24-7` configurada con auto-inicio `AtStartup` y repetición cada 5 minutos.
