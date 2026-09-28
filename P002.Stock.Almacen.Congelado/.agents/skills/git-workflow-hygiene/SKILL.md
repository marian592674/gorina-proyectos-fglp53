---
name: git-workflow-hygiene
description: Enforces Git hygiene, Conventional Commits specification, branch synchronization rules (rebase vs merge), atomic commits, and pre-commit secret leak prevention. Use when preparing commits, reviewing git history, or staging files.
---

# Git Workflow & Hygiene Guidelines

## Scope & Applicability
Aplica a la preparación de commits, revisión de staged diffs, resolución de conflictos y políticas de versionado del proyecto.

## AI Agent Pre-Commit Checklist

### 1. Auditoría Pre-Commit (Higiene de Diff)
- [ ] **Sin archivos operativos o sensibles:** Asegurarse de que `git status` no contenga archivos CSV de prueba/operativos (`STOCK/*.csv`), logs de runtime (`*.log`), ni configuraciones locales privadas (`carpeta.json`).
- [ ] **Sin restos de debug:** Verificar que no queden llamadas residuales a `console.log`, `Write-Host` de depuración temporal o código comentado obsoleto.
- [ ] **Commits atómicos:** Cada commit debe representar un cambio lógico unitario. No mezclar refactorizaciones de formato con nuevas features de negocio en el mismo commit.

### 2. Estándar de Conventional Commits
Todo mensaje de commit debe seguir el formato:
`<tipo>(<ámbito opcional>): <descripción concisa>`

**Tipos válidos:**
- `feat:` Nuevas funcionalidades o mejoras visuales/lógicas.
- `fix:` Correcciones de bugs o errores de cálculo.
- `refactor:` Mejoras de arquitectura o rendimiento sin alterar comportamiento.
- `perf:` Optimizaciones de rendimiento de carga o cómputo.
- `docs:` Actualizaciones de documentación (`CAMBIOS.md`, `README.md`, etc.).
- `chore:` Tareas de empaquetado, dependencias o configuración.

### 3. Seguridad en la Sincronización
- [ ] **Sincronización previa:** Ejecutar siempre `git pull --rebase origin main` antes de iniciar cambios o antes de hacer push.
- [ ] **No Force Push destructivo:** Nunca realizar `git push --force` sobre ramas compartidas (`main`). Usar `--force-with-lease` únicamente en ramas de feature aisladas si se requirió un rebase interactivo justificado.
