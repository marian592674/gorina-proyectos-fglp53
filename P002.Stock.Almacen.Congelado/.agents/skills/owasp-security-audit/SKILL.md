---
name: owasp-security-audit
description: Scans code, endpoints, and server configs against the OWASP Top 10 vulnerabilities (Injection, Broken Access Control, Security Misconfiguration, XSS, SSRF, Cryptographic failures). Use when reviewing backend services, HTTP listeners, or data-handling logic.
---

# OWASP Top 10 Security Audit Checklist

## Scope & Applicability
Aplica a endpoints HTTP, controladores backend, APIs JSON, persistencia de datos y manejo de entradas de usuario o archivos externos.

## AI Agent Audit Checklist

### 1. Inyección y Límites de Entrada (A03)
- [ ] **Sin inyecciones de comandos:** No concatenar variables de entrada en comandos de consola o intérpretes de comandos (`cmd.exe`, `powershell`).
- [ ] **Control de Path Traversal:** Validar que los nombres de archivo no incluyan secuencias `..`, diagonales inversas maliciosas o caracteres nulos `%00`. Resolver rutas absolutas y verificar que residan bajo la raíz permitida.
- [ ] **Validación y listas blancas:** Aplicar regex o listas blancas para formatos esperados (ej. IDs numéricos, nombres de archivo con extensión específica).

### 2. Configuración de Seguridad y Cabeceras (A05)
- [ ] **Cabeceras HTTP recomendadas:**
  - `Content-Security-Policy`: Definir fuentes permitidas estrictas (`default-src 'self'`).
  - `X-Content-Type-Options: nosniff`: Evitar MIME-sniffing.
  - `X-Frame-Options: SAMEORIGIN` o `DENY`: Prevenir Clickjacking.
- [ ] **Supresión de errores detallados (Information Disclosure):**
  - No devolver stack traces, rutas locales completas del servidor o dumps de excepción en respuestas HTTP 500 al cliente. Registrar el detalle en un log seguro y retornar un mensaje genérico.

### 3. Exposición de Datos y Secretos (A02, A07)
- [ ] **Cero credenciales en código:** Verificar que no haya contraseñas, tokens de API o rutas privadas fijas en el código fuente.
- [ ] **Configuraciones sensibles externalizadas:** Usar archivos de configuración locales excluidos por `.gitignore` (ej. `carpeta.json`) o variables de entorno.

### 4. Falsificación de Peticiones del Lado del Servidor / SSRF (A10)
- [ ] **Validación de URLs salientes:** Si el servidor descarga recursos remotos a petición del cliente, validar que no apunten a direcciones IP privadas o de loopback (`127.0.0.1`, `localhost`, `169.254.169.254`).
