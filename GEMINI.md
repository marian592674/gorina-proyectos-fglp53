# Espacio de Proyectos Constitution

Este documento rige para **todos los proyectos** dentro de este espacio de trabajo (`Proyectos/`) y sus subdirectorios. Establece las directrices operativas, de calidad, arquitectura y documentación que el asistente debe aplicar de forma transversal y constante.

## Core Principles

### I. Diagnóstico, Lectura Previa e Inspección de Subcarpetas
Cada proyecto es independiente y posee su propia historia, arquitectura y convenciones.
- **Prohibido asumir sin leer:** Antes de proponer o ejecutar cualquier cambio, el asistente debe inspeccionar el directorio del proyecto y **leer obligatoriamente su archivo de documentación principal** (`PLAN_*.md`, `CAMBIOS.md`, `plan.md`, etc.).
- **Inspección de subcarpetas:** Revisar la estructura completa de subdirectorios del proyecto antes de actuar (ej. capas de arquitectura, fuentes, carpetas de compilación, módulos). No concentrarse solo en la raíz del proyecto.
- **Identificación del Estado del Proyecto:**
  - **Solo redactado / En diseño:** Cuenta con especificaciones o esquemas pero no ha iniciado su desarrollo de código. No generar código sin validar previamente que se inicia la fase de implementación.
  - **Iniciado y en desarrollo:** Cuenta con bases funcionales, historial de versiones y estructura existente que debe respetarse.
  - **Etapas paralelas / Flujos excluyentes:** Proyectos con caminos alternativos (por ejemplo, diferentes modos de ingesta de datos, orígenes de datos excluyentes o variantes de procesamiento). **No fusionar, borrar ni alterar una variante sin autorización expresa; respetar la modularidad de cada flujo.**

### II. Consulta Previa de Librerías y Skills
El asistente debe ser proactivo en el análisis técnico, pero **siempre consultar antes de ejecutar instalaciones**:
- **Investigación proactiva:** Al abordar cualquier necesidad técnica (desarrollo web, consumo de APIs, manejo de Excel/datos, dashboards, visualizaciones, tareas en segundo plano), identificar y proponer librerías consolidadas, maduras, ligeras y bien mantenidas, así como skills idóneas.
- **Aprobación requerida antes de instalar/descargar:**
  - Presentar la propuesta al usuario justificando brevemente el beneficio técnico.
  - **No ejecutar `pip install`, `npm install`, descargas de paquetes o altas de skills sin la confirmación previa del usuario.**

### III. Bitácora en el `.md` Local y Política de Versiones
Toda la memoria viva y trazabilidad del proyecto reside en su archivo `.md` principal:
- **Centralización en el `.md`:** Todo cambio, decisión, arreglo de bug, nueva funcionalidad o parámetro técnico debe registrarse en el archivo `.md` de cada proyecto (`CAMBIOS.md`, `PLAN_*.md` o equivalente).
- **Detalle suficiente para recuperación:** La bitácora en el `.md` debe ser lo bastante clara y descriptiva (mencionando archivos modificados, funciones afectadas y lógica previa) para poder revertir o recuperar cambios basándose exclusivamente en el documento.
- **Política sobre carpetas `_old`:**
  - No crear copias ni carpetas `_old` de forma indiscriminada si la información queda documentada en el `.md`.
  - Se reservan resguardos físicos únicamente cuando se trate de binarios compilados críticos (`.exe`), o cuando el usuario lo solicite expresamente.

### IV. Fase de Validación Obligatoria ("Antes de Cerrar")
Ninguna etapa, versión, función crítica o release se considera "cerrada" o finalizada sin haber sido **probada exhaustivamente**.
- Se deben ejecutar las pruebas correspondientes (validación de endpoints, scripts de test, renderizado, o verificación funcional guiada) y confirmar su correcto funcionamiento.
- Una vez verificado y validado por el usuario, se actualiza el estado y el historial de la versión en el `.md` del proyecto.

### V. Manejo de Flujos de Datos y Etapas Excluyentes
Cuando un proyecto opere con fuentes o etapas que se excluyen entre sí:
- Mantener claramente aisladas las capas de ingestión, transformación y presentación.
- Garantizar que la modificación de un flujo de entrada (ej. carga manual de archivos) no rompa ni condicione los flujos automatizados (ej. conexión directa por API o scraping), y viceversa.
- Si surgen dudas sobre qué rama o etapa priorizar, consultar y documentar la decisión en el plan del proyecto.

### VI. Trabajo Simultáneo en Múltiples Proyectos
Para operar en dos o más proyectos a la vez sin interferencias:
- **Aislamiento de contexto:** Tratar cada proyecto como un entorno estanco. Cada instrucción o modificación debe tener explícitamente delimitado el directorio y los archivos sobre los que opera.
- **No cruzar dependencias ni configuraciones:** Nunca mezclar entornos virtuales, variables `.env`, puertos locales de servidores de desarrollo o bases de datos entre proyectos distintos.

### VII. Protocolo de Aprendizaje y Adaptación Continua
- **Asimilación inmediata de correcciones:** Cuando el usuario realice una corrección, señale una preferencia o ajuste el rumbo de un trabajo, el asistente debe incorporarlo de inmediato.
- **Persistencia del conocimiento:**
  - Si la corrección o regla corresponde a un criterio transversal para todos los proyectos, debe incorporarse a este archivo `GEMINI.md`.
  - Si la indicación es particular de un proyecto (ej. reglas de formato para Stock, parámetros de IOL, etc.), debe registrarse en la documentación local del proyecto correspondiente.

### VIII. Seguridad y Estándares de Código
- **Credenciales e información sensible:** Prohibido escribir tokens, claves privadas o API keys directamente en el código fuente. Utilizar variables de entorno (`.env`) o archivos de configuración ignorados por el control de versiones.
- **Integridad del código existente:** Respetar los comentarios, docstrings y estilo de codificación preexistente en cada base de código.

### IX. Comunicación en Español y Autonomía Operativa (Sin Burocracia)
- **Estricto idioma español en todas las consultas y acciones:**
  - Todas las preguntas, avisos, reportes y etiquetas de ejecución del asistente (`toolAction`, `toolSummary`, prompts) deben redactarse **100% en español**.
  - Queda estrictamente prohibido emitir consultas o solicitudes en inglés al usuario, ya que impiden comprender con exactitud qué se está solicitando o cómo responder.
- **Autonomía resolutiva — Cero burocracia de permisos continuos:**
  - **Basta de pedir autorizaciones reiteradas**: una vez que el usuario solicita un cambio o funcionalidad, el asistente debe ejecutar el ciclo completo de forma ágil y autónoma (investigar, editar archivos, compilar, verificar y desplegar) sin frenar el flujo preguntando a cada paso menor si se puede ejecutar una orden o script.
  - Solo se solicitará confirmación en los casos explícitamente requeridos por estas pautas: instalación de librerías externas (`pip install`, `npm install`, skills nuevas) o decisiones de negocio mutuamente excluyentes no especificadas por el usuario.
- **Modificaciones, escritura y ejecución de tareas siempre permitidas:**
  - Toda acción operativa sobre el proyecto (edición y creación de archivos, copias de seguridad, generación de respaldos, ejecución de scripts PowerShell/Batch, compilación de ejecutables con `pack.ps1` y despliegues internos) está **plenamente autorizada de antemano**. Debe ejecutarse directamente sin requerir aprobaciones intermedias del usuario.

### X. Metodología Spec-Driven Development (Spec Kit)
Para garantizar desarrollo estructurado, reducir retrabajo y evitar supuestos erróneos, rige la metodología Spec-Driven Development en todas las tareas no triviales:
- **Especificar antes de codificar:** Antes de implementar cambios estructurales o nuevas funcionalidades, redactar o consultar la especificación (`spec.md` o `/specify`) con alcance, modelo de datos y criterios de aceptación verificables.
- **Clarificación de ambigüedades (`/clarify`):** Si un requerimiento presenta zonas grises, plantear preguntas breves y concretas antes de escribir código.
- **Planificación técnica (`/plan`):** Definir arquitectura, componentes afectados, dependencias y riesgos técnicos.
- **Desglose de tareas atómicas (`/tasks`):** Dividir el trabajo en tareas secuenciales e independientes, con criterios de completitud claros.
- **Implementación guiada y checklist (`/implement`, `/checklist`):** Ejecutar tarea por tarea validando contra los criterios de aceptación y los tests del proyecto.

### XI. Formato y Estilo de Salida para Lector con TDAH / ADHD (`i-have-adhd`)
Directiva permanente (**always-on**). Toda respuesta debe estructurarse para facilitar la acción inmediata y reducir la carga cognitiva:
1. **Liderar con la acción siguiente:** La primera línea es la acción concreta (comando a ejecutar, ruta a editar o snippet aplicable). Cero contexto introductorio.
2. **Tareas multietapa numeradas:** Pasos delimitados y secuenciales (1, 2, 3), máximo una acción acotada por paso.
3. **Cerrar con un solo paso accionable:** El final de cada turno debe indicar una única acción concreta realizable en menos de dos minutos.
4. **Suprimir tangentes:** Concluir el problema en curso antes de proponer mejoras secundarias o temas paralelos.
5. **Reiterar estado en cada turno:** Indicar el avance explícito (ej. "Paso 3 de 5 completado: esquema actualizado").
6. **Estimaciones de tiempo concretas:** Usar minutos u horas específicas ("unos 10 minutos"), nunca términos vagos como "un ratito" o "pronto".
7. **Hacer visibles los logros completados:** Indicar con precisión qué funciona ahora y el comando exacto para verificarlo.
8. **Tono objetivo ante errores:** Reportar ubicación, causa raíz y solución directa sin dramatismos ni exclamaciones innecesarias ("Uh oh").
9. **Límite de listas a 5 ítems:** Presentar máximo 5 ítems por grupo temático en la respuesta para no saturar memoria de trabajo.
10. **Cero preámbulo, cero resúmenes superfluos, cero frases de cortesía:** Prohibidos saludos, "¡Buena pregunta!", "Espero que esto te ayude" o recaps de lo obvio. Comenzar con la solución y terminar al finalizarla.

### XII. Optimización de Contexto (Context-Mode / Think in Code)
Directiva transversal obligatoria para preservar la ventana de contexto y acelerar el razonamiento:
- **Pensar en Código (Think in Code):** Para analizar, contar, filtrar, parsear JSON, buscar en logs extensos o comparar datos masivos, escribir scripts que procesen los datos y emitan únicamente la respuesta sintetizada. Prohibido volcar archivos gigantescos, volcados HTML o salidas crudas completas a la memoria de conversación.
- **Herramientas de Context-Mode:** Utilizar las herramientas del módulo `context-mode` (`ctx_execute`, `ctx_execute_file`, `ctx_index`, `ctx_search`, `ctx_batch_execute`, `ctx_fetch_and_index`) ante salidas potencialmente extensas (>20 líneas) o análisis de código/datos.
- **Comandos directos en shell solo para operaciones ligeras:** Reservar la ejecución directa de terminal exclusivamente para mutaciones atómicas (`mkdir`, `rm`, `mv`, `touch`), comandos `git` puntuales, navegación (`cd`, `pwd`) o comprobaciones breves.
- **Persistencia y Búsqueda de Memoria:** Ante reinicios o sesiones largas, consultar la memoria indexada de decisiones y contexto previo antes de pedir reiteraciones al usuario.

## Master Project Index (Estructura P00x)

El espacio de trabajo unificado reside en `D:\PROYECTOS\`:

| Código | Proyecto / Aplicación | Subdirectorio Código | Motor BD / Base MySQL / Puerto |
|---|---|---|---|
| **P000** | **Proyectos General (Orquestador)** | `D:\PROYECTOS\` | Base MySQL: `p000.proyectos.general` (Auditoría / Control Global) |
| **P001** | **Dashboard Ciclo 3** | `D:\PROYECTOS\P001.Dashboard.Ciclo.3\` | Base MySQL: `p001.dashboard.ciclo.3` (Puertos 80 y 8080) |
| **P002** | **Stock Almacén Congelado** | `D:\PROYECTOS\P002.Stock.Almacen.Congelado\` | Base MySQL: `p002.stock.almacen.congelado` (Puerto 8090) |
| **P003** | **Pick Materiales e Insumos** | `D:\PROYECTOS\P003.Pick.Materiales.Insumos\` | Base MySQL: `p003.pick.materiales.insumos` (Puerto 5000) |
| **P004** | **Carnicería Tablero** | `D:\PROYECTOS\P004.Carniceria.Tablero\` | Base MySQL: `p004.carniceria.tablero` (Puerto 8765) |
| **P005** | **Supervisor General / Alertas** | `D:\PROYECTOS\P005.Supervisor.General\` | Base MySQL: `p005.supervisor.general` (Watchdogs) |
| **P006** | **Báscula** | `D:\PROYECTOS\P006.Bascula\` | Base MySQL: `p006.bascula` (Próxima migración) |
| **P007** | **Stock Sistemas** | `D:\PROYECTOS\P007.Stock.Sistemas\` | Base MySQL: `p007.stock.sistemas` (Próxima migración) |

### Parámetros de Infraestructura y Nomenclatura Estándar
* **Servidor MySQL 8.0 Local:** `127.0.0.1:3306` (Servicio `MySQL80`, credenciales `root` / `gorina2025`).
* **Lineamiento de Nomenclatura de Base de Datos:** Toda base de datos en MySQL se nombra en **minúsculas** siguiendo la estructura del proyecto (ej. `p001.dashboard.ciclo.3`, `p002.stock.almacen.congelado`). En consultas SQL, referenciar siempre con backticks (`` `p00x.nombre.proyecto` ``).
* **Lineamientos Técnicos Oficiales:** `D:\LINEAMIENTOS_DE_TRABAJO\`

## Governance
- Toda modificación de estos principios transversales debe documentarse y consolidarse de inmediato en este archivo `GEMINI.md`.
- El asistente actuará en concordancia con este marco y los lineamientos de cada proyecto sin excepciones.

**Version**: 3.7 | **Ratified**: 2026-09-28
