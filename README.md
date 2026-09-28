# Ecosistema de Proyectos — Frigorífico Gorina SAIC (Servidor FGLP53)

Repositorio centralizado (**Monorepo**) que nuclea los desarrollos de software, tableros de control de operaciones, interfaces de picking, APIs de servicios y herramientas de supervisión del servidor corporativo **FGLP53** (`192.168.0.126`).

---

## 1. Índice Maestro de Proyectos

| Código | Proyecto | Directorio | Motor BD / Base MySQL | Dirección de Acceso Corporativo (`FGLP53`) | Backend / Tecnología | Estado |
|---|---|---|---|---|---|---|
| **P000** | **Proyectos General** | [`/`](file:///D:/PROYECTOS/) | `` `p000.proyectos.general` `` | `http://fglp53/proyectos` | Orquestador Global / Auditoría | Activo |
| **P001** | **Dashboard Ciclo 3** | [`P001.Dashboard.Ciclo.3/`](file:///D:/PROYECTOS/P001.Dashboard.Ciclo.3/) | `` `p001.dashboard.ciclo.3` `` | **Prod:** `http://fglp53/tablero.ciclo3/`<br/>**Lab:** `http://fglp53:8080/dashboard_operaciones.html` | IIS 10 + Python 3.12 (Colector) | En Producción |
| **P002** | **Stock Almacén Congelado** | [`P002.Stock.Almacen.Congelado/`](file:///D:/PROYECTOS/P002.Stock.Almacen.Congelado/) | `` `p002.stock.almacen.congelado` `` | `http://fglp53:8090/stock_almacen` | C# .NET 8 (`ExportarStock.exe`) | En Producción |
| **P003** | **Pick Materiales e Insumos** | [`P003.Pick.Materiales.Insumos/`](file:///D:/PROYECTOS/P003.Pick.Materiales.Insumos/) | `` `p003.pick.materiales.insumos` `` | `http://fglp53:5000/api/materiales` | C# .NET 8 (`Gorina.Api.exe`) + Android APK | En Producción |
| **P004** | **Carnicería Tablero** | [`P004.Carniceria.Tablero/`](file:///D:/PROYECTOS/P004.Carniceria.Tablero/) | `` `p004.carniceria.tablero` `` | `http://fglp53:8765/tablero_carniceria` | C# .NET 8 (`Gorina.Carniceria.Api.exe`) | En Producción |
| **P005** | **Supervisor General** | [`P005.Supervisor.General/`](file:///D:/PROYECTOS/P005.Supervisor.General/) | `` `p005.supervisor.general` `` | `http://fglp53/tablero.ciclo3/1_DIAGRAMA_Y_MANUAL.html` | PowerShell 24-7 + Relay SMTP | En Producción |
| **P006** | **Báscula** | [`P006.Bascula/`](file:///D:/PROYECTOS/P006.Bascula/) | `` `p006.bascula` `` | `http://fglp53:8095/bascula` *(a configurar)* | .NET 8 | En Diseño |
| **P007** | **Stock Sistemas** | [`P007.Stock.Sistemas/`](file:///D:/PROYECTOS/P007.Stock.Sistemas/) | `` `p007.stock.sistemas` `` | `http://fglp53:8096/stock_sistemas` *(a configurar)* | .NET 8 | En Diseño |

---

## 2. Arquitectura de Datos y Servicios

* **Servidor de Base de Datos:** MySQL 8.0 Community Server local (`127.0.0.1:3306`, servicio Windows `MySQL80`).
* **Lineamiento de Nomenclatura:** Todas las bases de datos se nombran en **minúsculas** siguiendo exactamente el código y nombre del proyecto (ej. `p001.dashboard.ciclo.3`, `p002.stock.almacen.congelado`).
* **Vigilancia y Auto-Recuperación:** [`P005.Supervisor.General`](file:///D:/PROYECTOS/P005.Supervisor.General/) supervisa la salud de los puertos HTTP y las tareas de Windows cada 3 minutos, reiniciando automáticamente cualquier servicio ante interrupciones y registrando la telemetría e incidentes en MySQL.
* **Supervivencia a Reinicios:** Todas las tareas críticas cuentan con disparador de inicio de sistema (`AtStartup` / `BootTrigger`) en el Programador de Tareas de Windows.

---

## 3. Documentación Técnica Detallada

* **[Mapa de Proyectos y Flujo de Datos (HTML Visual)](file:///D:/PROYECTOS/P005.Supervisor.General/1_DIAGRAMA_Y_MANUAL.html)**: Diagrama completo interactivo en SVG con matriz de accesos y servicios.
* **[Esquema Maestro de Flujos y Accesos](file:///D:/PROYECTOS/ESQUEMA_DE_FLUJOS_Y_ACCESOS.md)**: Documento técnico de detalle de ingesta, procesamiento, persistencia y rutas corporativas.
* **[Constitución y Pautas de Desarrollo (GEMINI.md)](file:///D:/PROYECTOS/GEMINI.md)**: Convenciones de código, estándares de arquitectura, gobernanza y reglas operativas.
