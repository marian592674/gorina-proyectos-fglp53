---
name: code-review-cleancode
description: Performs rigorous code review against Clean Code principles (SOLID, DRY, KISS), guard clauses, readability, naming conventions, and edge case handling. Use when asked to review pull requests, diffs, or existing files.
---

# Code Review & Clean Code Principles

## Scope & Applicability
Aplica a cualquier refactorización, revisión de pull request, nueva función o módulo tanto en frontend como en backend.

## AI Agent Review Checklist

### 1. Estructura y Complejidad
- [ ] **Profundidad de anidamiento:** Ninguna función debe superar 3 niveles de indentación anidada. Utilizar **Guard Clauses** (retorno temprano) para aplanar el código.
- [ ] **Responsabilidad Única (SRP):** Cada función debe hacer una sola cosa bien. Si una función procesa datos, actualiza la UI y escribe logs, debe dividirse en funciones auxiliares puras.
- [ ] **Longitud de función:** Idealmente menor a 40-50 líneas. Extraer lógica compleja o bucles pesados a helpers específicos.

### 2. Nombres Claros y Auto-documentados
- [ ] **Variables booleanas:** Deben prefijarse con `is`, `has`, `should`, o `can` (ej. `isLoading`, `hasStock`, `isValidSku`).
- [ ] **Sin nombres crípticos:** Evitar variables como `p`, `x`, `arr2`, `temp`. Usar nombres semánticos como `palletList`, `skuCatalog`, `totalCajas`.
- [ ] **Eliminación de números y strings mágicos:** Constantes de negocio repetidas o tiempos de espera deben extraerse como constantes con nombre (`DEBOUNCE_MS = 250`).

### 3. Manejo Defensivo y Casos Borde
- [ ] **Estados nulos o vacíos:** Tratar adecuadamente `null`, `undefined`, listas vacías `[]` o strings vacíos `""` sin generar excepciones no controladas.
- [ ] **Funciones puras preferidas:** Favorecer funciones que reciban parámetros y devuelvan resultados sin efectos secundarios mutables en objetos externos compartidos.

---

## Ejemplos

### ❌ Pirámide de anidamiento (Arrow Anti-Pattern)
```javascript
function procesarStock(sku, lote) {
  if (sku) {
    if (lote && lote.length > 0) {
      if (sku.activo) {
        return calcularTotales(sku, lote);
      } else {
        return null;
      }
    } else {
      return null;
    }
  } else {
    return null;
  }
}
```

### ✅ Guard Clauses limpios (Retorno temprano)
```javascript
function procesarStock(sku, lote) {
  if (!sku || !sku.activo) return null;
  if (!Array.isArray(lote) || lote.length === 0) return null;

  return calcularTotales(sku, lote);
}
```
