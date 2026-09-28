# Gorina Pick — App de Picking de Materiales

Frigorífico Gorina · Escaneo QR → consumo por Centro de Costo → archivo para SAP.

## Contenido

| Carpeta | Qué es |
|---|---|
| `app\` | Aplicación Android (Flutter). APK generado en `app\build\app\outputs\flutter-apk\` |
| `servidor\` | API del servidor Windows (`Gorina.Api`) — ver `servidor\README.md` |
| `docs\PLAN.md` | Plan funcional y técnico completo |
| `CHANGELOG.md` | Seguimiento de versiones, mejoras y correcciones |
| `Ejemplos\` | Excel provistos: modelo de salida y maestros |

## Puesta en marcha (resumen)

1. **Servidor** (ver detalle en `servidor\README.md`):
   - Copiar `servidor\publicar\` al servidor Windows.
   - Editar `config.json` (carpeta de salida SAP, puerto, valores fijos).
   - Importar maestros: `Gorina.Api.exe --importar-equivalencias Equivalencias.xlsx` etc.
   - Ejecutar `Gorina.Api.exe`. Usuario inicial: **admin / PIN 1234** (cambiarlo).

2. **Teléfonos**:
   - Instalar el APK (`app-release.apk`).
   - En Login → "Servidor": cargar `http://IP-DEL-SERVIDOR:8080`.
   - Ingresar con usuario/PIN creado por el ADMIN.

## Compilar la app desde cero

Requiere Flutter SDK + Android SDK:

```
cd app
flutter pub get
flutter build apk --release
```

## Regenerar el EXE del servidor desde cero

Requiere .NET 8 SDK:

```
servidor\publicar.bat
```

## Configuración local

Los datos operativos, bases SQLite, respaldos y binarios generados no se guardan
en Git. Antes de ejecutar el servidor por primera vez, copie
`servidor\Gorina.Api\config.example.json` como
`servidor\Gorina.Api\config.json` y ajuste sus valores locales.
