# Servidor Gorina.Api

API mínima para la app de PICKING de Frigorífico Gorina.
Un solo ejecutable autocontenido, sin IIS, sin SQL Server.

## Qué hace

- Autentica usuarios (perfil ADMIN / PICK) y mantiene sesiones persistentes.
- Guarda los maestros: equivalencias QR→SAP, centros de costo, almacenes, usuarios.
- Recibe operaciones de PICK cerradas desde los teléfonos (idempotente por ID interno).
- Genera el archivo CSV (delimitado por ;) con las columnas exactas del modelo SAP y lo escribe en la carpeta configurada.
- Detecta resultados SAP `OK` y `NP`, incluso cuando un `NP` pierde el nombre original y debe vincularse por Orden.
- Permite validar e importar los cinco catálogos Excel desde la app ADMIN y conserva los archivos procesados.
- Expone control de picks, casos "sin equivalencia" y reintento de errores.

## Requisitos

- Windows (el que sea; no necesita nada instalado: el EXE es autocontenido).
- Permisos de escritura sobre la carpeta de red de destino (`\\SERVIDOR\...`).

## Instalación (3 pasos)

1. **Publicar** (en una máquina con .NET 8 SDK): ejecutar `servidor\publicar.bat`.
   Se genera `servidor\publicar\` con `Gorina.Api.exe` + `config.json`.

2. **Configurar** `config.json`:

Copiar `Gorina.Api\config.example.json` como `Gorina.Api\config.json`. El archivo
real queda excluido de Git porque contiene rutas y parámetros propios de cada
instalación.

```json
{
  "Puerto": 8080,
  "BaseDatos": "gorina.db",
  "CarpetaSalida": "\\\\SERVIDOR\\INTERFAZ_SAP\\CONSUMOS",
  "ClaseMovimiento": "201",
  "Centro": "1001",
  "LoteDefault": "1",
  "CabeceraEnTodasLasFilas": false,
  "PrefijoNombre": "PICK",
  "UsuarioAdminInicial": "admin",
  "PinAdminInicial": "1234",
  "IntervaloMonitoreoSapSegundos": 30,
  "DiasHistorialApp": 30,
  "CarpetaCatalogos": "Catalogos"
}
```

| Clave | Significado |
|---|---|
| Puerto | Puerto HTTP donde escucha la API |
| BaseDatos | Archivo SQLite (relativo al EXE o ruta absoluta). Respaldo = copiar este archivo |
| CarpetaSalida | Carpeta donde se escriben los CSV (ruta UNC del servidor). Si no existe → operación queda en ERROR |
| ClaseMovimiento / Centro / LoteDefault | Valores fijos que van a cada fila del archivo |
| CabeceraEnTodasLasFilas | false = texto cabecera solo en primera fila de la Orden; true = en todas |
| PrefijoNombre | Prefijo del archivo generado (PICK_yyyymmdd_hhmmss_orden.csv) |
| IntervaloMonitoreoSapSegundos | Cada cuántos segundos revisar archivos `OK/NP` |
| DiasHistorialApp | Período predeterminado que conservan y muestran los teléfonos |
| CarpetaCatalogos | Carpeta donde se archivan los Excel confirmados, dentro de `Procesados` |

3. **Importar maestros** (una vez, con Excel cerrado):

```
Gorina.Api.exe --importar-equivalencias Equivalencias.xlsx
Gorina.Api.exe --importar-cecos "Centros de Costo.xlsx"
Gorina.Api.exe --importar-almacenes Almacenes.xlsx
```

Los importes pueden repetirse: actualizan por clave (QR / CECO / código de almacén).
También pueden hacerse desde `ADMINISTRACIÓN → IMPORTAR CATÁLOGOS` en la app. La app
valida primero el Excel, muestra filas válidas/omitidas y pide confirmación antes de escribir.

## Arrancar

```
Gorina.Api.exe
```

Queda escuchando en `http://0.0.0.0:8080`. Los teléfonos se configuran apuntando a
`http://IP-DEL-SERVIDOR:8080`.

> Para dejarlo como servicio de Windows use un wrapper como NSSM hasta que se incorpore
> el instalador definitivo. No use `sc create` directamente con esta versión.

## Primer ingreso

- Usuario inicial: `admin` / PIN `1234` (**cambiarlo desde la app: Usuarios**).
- Desde la app, perfil ADMIN: crear usuarios PICK, revisar equivalencias, etc.

## Endpoints principales

| Método | Ruta | Quién |
|---|---|---|
| POST | /api/login {usuario, pin} | todos |
| GET | /api/maestros | todos (réplica offline) |
| POST | /api/operaciones | todos (envío de picks cerrados) |
| GET | /api/operaciones, /api/operaciones/{id} | todos |
| POST | /api/operaciones/{id}/reintentar | ADMIN |
| GET/POST/PUT | /api/equivalencias | ADMIN |
| POST/PUT | /api/cecos | ADMIN |
| GET/POST/PUT | /api/usuarios | ADMIN |
| POST | /api/catalogos/importar | ADMIN |
| GET | /api/catalogos/importaciones | ADMIN |
| GET | /api/sinequivalencia | ADMIN |

## Diagnóstico rápido

- `GET http://localhost:8080/api/ping` → debe responder OK.
- La consola registra cada CSV generado y cada error.
- La consola registra cada resultado SAP nuevo y la app muestra `ESPERANDO SAP`, `SAP NP` o `SAP OK`.
- Operaciones en ERROR: mensaje visible en Control de Picks; botón REINTENTAR cuando la carpeta vuelva a estar disponible.
