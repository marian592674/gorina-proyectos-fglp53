# Guía de Entorno de Desarrollo Local

Este documento detalla cómo levantar el proyecto en un equipo personal (PC de desarrollo) sin afectar el servidor de producción.

## Requerimientos del Sistema (Prerrequisitos)

Para trabajar de forma escalable y compilar ambas partes del proyecto, tu equipo necesita:

1. **Backend (.NET API):**
   - [.NET 8.0 SDK](https://dotnet.microsoft.com/es-es/download/dotnet/8.0)
   - Visual Studio 2022 o Visual Studio Code (con extensión C# Dev Kit).
2. **Frontend (Flutter App):**
   - [Flutter SDK](https://docs.flutter.dev/get-started/install) (versión 3.13.0 o superior).
   - Android Studio (para las herramientas de compilación y emuladores).
   - Dispositivo físico Android (recomendado) o emulador para pruebas de cámara (el emulador no escanea QR físicos).
3. **Control de Versiones:**
   - Git.

## Pasos para Levantar el Proyecto Localmente

Al clonar el repositorio en tu PC nueva, notarás que faltan ciertos archivos operativos (`config.json`, `gorina.db`, etc.). Esto es por diseño (protegido por `.gitignore`) para no cruzar credenciales ni bases de datos.

### 1. Configurar la API (.NET) Local

1. Abre una terminal y dirígete a `servidor/Gorina.Api/`.
2. Duplica el archivo `config.example.json` y renómbralo a `config.json`.
3. Edita tu nuevo `config.json` y cambia las rutas de red por carpetas locales en tu PC. Por ejemplo:
   ```json
   {
     "Puerto": 8080,
     "RutaCarpetaSalida": "C:\\Temp\\GorinaSalidaSAP",
     "RutaCarpetaCatalogos": "C:\\Temp\\GorinaCatalogos",
     "PrefijoNombre": "PICKQUIM"
   }
   ```
4. Crea esas carpetas locales (`C:\Temp\GorinaSalidaSAP`).
5. Ejecuta el servidor desde tu entorno de desarrollo:
   ```bash
   dotnet run
   ```
6. El sistema creará automáticamente la base local (`gorina.db`) vacía. Usa la API o la utilidad de comandos para cargar los Excel de ejemplo de la carpeta `Ejemplos/`.

### 2. Configurar la App (Flutter) Local

1. Dirígete a la carpeta `app/`.
2. Descarga las dependencias:
   ```bash
   flutter pub get
   ```
3. Conecta tu celular por USB (modo depuración) o inicia un emulador.
4. Ejecuta la aplicación:
   ```bash
   flutter run
   ```
5. En la pantalla de login de la app en tu celular, toca el ícono de engranaje (Servidor) y coloca la dirección IP de tu computadora (ej. `http://192.168.0.15:8080`).

## Pendientes de Configuración y Futuras Implementaciones

Si decides avanzar con implementaciones futuras (como la **Plataforma Web**), ten en cuenta lo siguiente:
- **Almacenamiento Web:** El código base actual funciona en móviles. Si compilas para web (`flutter build web`), se requiere migrar la librería `sqflite` a `sqflite_common_ffi_web`.
- **CORS:** El `Program.cs` de la API requerirá agregar reglas de CORS para aceptar peticiones desde un navegador (evitando bloqueos de seguridad cruzada).
- **HTTPS:** La cámara web en un navegador exige un certificado de seguridad. Deberás configurar Kestrel (.NET) para usar HTTPS en un puerto específico.

## Buenas Prácticas de Control de Versiones

Mantén siempre el repositorio ordenado usando **Conventional Commits**:
- `feat(modulo): descripción` -> Para nuevas funcionalidades.
- `fix(modulo): descripción` -> Para corrección de errores.
- `docs: descripción` -> Para cambios en la documentación.
- Nunca subas archivos `config.json`, `.apk`, o `.db` (ya están protegidos por el `.gitignore`).
- Trabaja siempre en ramas paralelas (`git checkout -b feature/nombre-rama`) y haz fusiones (merge) a `main` cuando esté probado.
