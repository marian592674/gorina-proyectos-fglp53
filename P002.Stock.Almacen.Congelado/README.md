# Stock.Almacen

Aplicación portable para gestión, consulta en tiempo real, trazabilidad de cargas y exportación de stock de almacén congelado a Excel (Frigorífico Gorina).

## 🚀 Características Principales

- **Servidor 24/7 Local y Red:** Backend ligero en PowerShell (`HttpListener`) empaquetado en un único ejecutable (`ExportarStock.exe`), operando como tarea programada en puerto `8090`.
- **Frontend SPA Interactivo:** Interfaz web moderna (HTML5, CSS3, Vanilla JS) con búsqueda en tiempo real, debounce (250ms), paginación y caché en memoria de más de 2.500 SKUs y 48.000 cajas sin bloqueo de UI.
- **Filtros Avanzados y Fechas:** Filtro normalizado por SKU, Venta, Destino, Establecimiento y Rango de Fecha de Producción (Desde / Hasta) con selectores de calendario desplegables individuales.
- **Módulo de Análisis Brasil:** Panel modal para asignación y desasignación rápida de pallets aptos y pendientes con persistencia en el servidor (`analisis_manual.json`).
- **Historial de Cargas y Descargas:** Registro automático de descargas al exportar desde *Cargas Gorina* con persistencia en `cargas_historial.json` e histórico para todos los usuarios.
- **Pesaje Real de Balanza:** Registro y ajuste directo de los kilos reales pesados por camión/carga, calculando desvíos contra los kilos estimados.
- **Resumen Ejecutivo y Comparativas:** Métricas gerenciales (KPIs), comparativa semanal estricta (Lunes a Viernes vs. semana anterior), desglose diario por destino y establecimiento, y descarga de informe formal en Excel con ExcelJS.
- **Exportación de Stock:** Generación de planillas de stock enriquecidas con catálogo corporativo en el cliente mediante `exceljs.min.js`.

## 📁 Estructura del Repositorio (Mínima y Limpia)

- `Fuente A PROBAR/`: Código fuente editable de la aplicación (`index.template.html`, `exportar_stock.ps1`, `pack.ps1`, `catalogo.json`, `exceljs.min.js`, etc.).
- `A PROBAR/`: Entorno de distribución y prueba con el ejecutable activo (`ExportarStock.exe`), `cargas_historial.json` y `analisis_manual.json`.
- `CAMBIOS.md`: Bitácora detallada de todas las versiones, rondas y cierres de jornada.
- `GEMINI.md`: Guía de arquitectura, convenciones y contexto para asistentes de IA.
- `README.md`: Descripción general del proyecto y características.

## 📋 Hoja de Ruta y Próximas Etapas

- **Migración a C# .NET 8 y MySQL 8.0**: Migración del backend PowerShell a .NET 8 (`Gorina.Stock.Api`), trasladando la persistencia de los archivos JSON (`cargas_historial.json`, `romaneos_resumen.json`, `analisis_manual.json`, `catalogo.json`) hacia la base MySQL `` `P002.Stock.Almacen.Congelado` `` (Puerto `8090`).
- **[Pendiente] Ingesta de Mensajes XML para Pallets**: Creación de endpoint receptor de mensajes XML de movimientos (ingresos, egresos y traslados) para generar histórico y trazabilidad de pallets en base de datos. Los campos y el endpoint se definirán en dicha etapa.

## 🛠️ Compilación / Empaquetado

Para compilar el ejecutable a partir del código fuente:
1. Abrir PowerShell en la carpeta `Fuente A PROBAR/`.
2. Ejecutar `.\pack.ps1`.
3. El script embebe los recursos estáticos en Base64 dentro de `exportar_stock.ps1` y compila el ejecutable `ExportarStock.exe` mediante `ps2exe`.
4. El ejecutable compilado se ubica en `Fuente A PROBAR/ExportarStock.exe` y se copia a `A PROBAR/ExportarStock.exe`.
