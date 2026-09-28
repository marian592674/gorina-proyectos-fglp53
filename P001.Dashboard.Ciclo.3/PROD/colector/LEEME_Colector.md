# Colector Gorina Ciclo 3

Genera/actualiza el archivo `datos.json` que consume el tablero v4
(`tablero_v4/dashboard_operaciones.html`).

- **Etapa 1 (actual)**: fuente = **Google Sheets** (sin autenticación). Permite
  arrancar ya mismo la versión autónoma sin depender de las BDs.
- **Etapa 2 (futura)**: fuente = **SQL Server** (vistas del DBA). Solo cambia
  `source` en `config.json`; el `datos.json` ya acumulado se preserva.

## Archivos
| Archivo | Función |
|---|---|
| `colector.py` | El colector (Python 3.x, solo biblioteca estándar en Etapa 1) |
| `config.json` | Configuración (fuente, paths, layout del sheet, conexión SQL futura) |
| `colector.bat` | Ejecuta una corrida manual desde Windows |
| `logs/colector.log` | Bitácora de cada corrida |

## Comportamiento
- **UPSERT por día** (`k = YYYY-MM-DD`): inserta días nuevos, actualiza los
  existentes y **conserva el histórico acumulado** (nunca borra historia).
- `occ` se normaliza a **porcentaje 0–100** ("2,98%" → 2.98; 0.1028 → 10.28).
- Si **un sistema falla**, los demás siguen actualizándose y se conserva el
  último dato bueno de ese sistema.
- Escritura **atómica** (`datos.json.tmp` + rename) y copia previa en
  `datos.json.prev`. El tablero nunca lee un archivo a medio escribir.

## Puesta en marcha (requisitos)
1. Instalar **Python 3.12** en la máquina que correrá el colector (para la
   Etapa 2 además: `pip install pyodbc` y el **ODBC Driver 17/18** de Microsoft).
2. Dejar esta carpeta en un lugar fijo (no una carpeta compartida por usuarios).
3. Ajustar en `config.json`:
   - `out_path`: ruta donde el tablero sirve `datos.json`.
     - Desarrollo local: `"../tablero_v4/datos.json"` (por defecto).
     - VM productiva (esta instalación): `"C:/Ciclo3/Servicios/dashboard/datos.json"` (ya viene así).
4. Probar una corrida manual: `python colector.py` (o `colector.bat`).
   Debe verse: `trv: N leídos · total N días`, etc.

## Agendar (Windows Task Scheduler)
1. `win+R` → `taskschd.msc` → "Crear tarea básica".
2. Nombre: `Gorina - Colector datos` · desmarcar "con los privilegios más altos".
3. Desencadenador: **repetir cada 5 minutos**, duración indeterminada.
4. Acción: iniciar programa → `colector.bat` (o `python colector.py`).
5. Condición: **contraria a "iniciar solo si hay red"** se deja default;
   sí marcar "ejecutar aunque el equipo esté SI". Preferencia:
   marcar "Cerrar la tarea si dura más de: 2 horas".
6. Correr en la cuenta de servicio/por defecto de la VM; la VM queda siempre
   encendida (es requisito conocido).

## `config.json` — Etapa 2 (cuando el DBA entregue)
```jsonc
{
  "source": "sql",
  "out_path": "C:/Ciclo3/Servicios/dashboard/datos.json",
  "sql": {
    "servers": {
      "TRV":     "DRIVER={ODBC Driver 18 for SQL Server};SERVER=IP_TRV;DATABASE=...;UID=tablero_ro;PWD=***;TrustServerCertificate=yes",
      "ALMACEN": "DRIVER={ODBC Driver 18 for SQL Server};SERVER=IP_ALMACEN;DATABASE=...;UID=tablero_ro;PWD=***;TrustServerCertificate=yes"
    },
    "views": {
      "trv":   { "server": "TRV",     "view": "dbo.vw_tablero_trv1" },
      "trv2":  { "server": "TRV",     "view": "dbo.vw_tablero_trv2" },
      "crane": { "server": "ALMACEN", "view": "dbo.vw_tablero_almacen" }
    }
  }
}
```
El traspaso Sheet→SQL **no pierde** el histórico ya acumulado en `datos.json`.

## Resolución de problemas
| Síntoma | Causa típica | Solución |
|---|---|---|
| `trv: ERROR` entorno red/status | Sin internet a docs.google.com o el sheet dejó de estar público | Verificar red; dejar de usar sheet es el objetivo (Etapa 2) |
| `[ERROR] Python no esta instalado` | Python no está o no está en PATH | Instalar Python 3.12 con "Add to PATH" |
| `datos.json ilegible` | Archivo corrupto | El colector lo regenera desde cero en la próxima corrida |
| El tablero muestra datos viejos | El colector no se está ejecutando | Revisar `logs/colector.log` y la tarea programada |