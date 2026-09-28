---
name: vanilla-web-quality
description: Audits and enforces vanilla HTML5, CSS3, and modern JavaScript (ES6+) standards with zero frameworks. Focuses on DOM XSS prevention, memory leaks, performance (DOM fragments, debouncing), and clean separation of concerns. Use when writing or reviewing frontend code in single-page apps or HTML templates.
---

# Vanilla HTML5 / CSS3 / JavaScript Quality & Security

## Scope & Applicability
Aplica a interfaces web autocontenidas (`index.template.html`, scripts JS vanilla, estilos CSS nativos) sin dependencias de frameworks pesados (React, Angular, Vue).

## AI Agent Audit Checklist

### 1. Prevención de Vulnerabilidades XSS en el DOM
- [ ] **Prohibido `innerHTML` con datos no confiables:** No asignar cadenas interpoladas con datos externos a `innerHTML`, `outerHTML` o `insertAdjacentHTML()`.
- [ ] **Uso de APIs seguras:** Usar `textContent` o `innerText` para inyectar texto.
- [ ] **Creación imperativa de elementos:** Construir elementos complejos con `document.createElement()`, `setAttribute()` o `dataset`.
- [ ] **Sanitización de enlaces dinámicos:** Enlaces `<a>` dinámicos deben verificar protocolos seguros (`https://`, `http://`, `#`, o `/`) y rechazar pseudoprotocolos `javascript:`.
- [ ] **Atributos de seguridad en enlaces externos:** Si se usa `target="_blank"`, incluir siempre `rel="noopener noreferrer"`.

### 2. Rendimiento y Manipulación del DOM
- [ ] **Mutaciones en bloque (Batching):** Para renderizar miles de filas o tarjetas, usar `document.createDocumentFragment()` o `container.replaceChildren(...)` en lugar de apéndices individuales en un loop (`appendChild` dentro de `forEach`).
- [ ] **Debounce en eventos frecuentes:** Eventos como `input`, `keyup`, `resize` o `scroll` en inputs de búsqueda deben implementar debouncing (200ms - 300ms) para evitar congelar el hilo principal.
- [ ] **Separación entre Modelo y Vista:** Mantener las funciones de filtrado y cálculo puras (sin tocar el DOM) antes de invocar la capa de renderizado.

### 3. Manejo de Eventos y Arquitectura Limpia
- [ ] **Cero manejadores inline en HTML:** Evitar atributos inline `onclick="..."`, `onchange="..."` en strings de plantillas.
- [ ] **Delegación de eventos:** Usar un único listener en el contenedor padre (`element.addEventListener('click', e => { const row = e.target.closest('tr'); ... })`) en lugar de añadir miles de listeners individuales.
- [ ] **Limpieza de timers:** Asegurarse de cancelar timeouts pendientes (`clearTimeout`) al reiniciar búsquedas.

---

## Ejemplos

### ❌ Inseguro y Lento (XSS en DOM + Repaint masivo)
```javascript
function renderGrid(items) {
  const table = document.getElementById('table-body');
  // Lento y vulnerable a XSS si item.nombre contiene tags HTML
  items.forEach(item => {
    table.innerHTML += `<tr onclick="verDetalle('${item.id}')"><td>${item.nombre}</td></tr>`;
  });
}
```

### ✅ Seguro, Rápido y Limpio
```javascript
function renderGrid(items) {
  const tbody = document.getElementById('table-body');
  const fragment = document.createDocumentFragment();

  items.forEach(item => {
    const tr = document.createElement('tr');
    tr.dataset.id = item.id;

    const td = document.createElement('td');
    td.textContent = item.nombre; // Inmune a XSS

    tr.appendChild(td);
    fragment.appendChild(tr);
  });

  tbody.replaceChildren(fragment); // Render atómico único
}

// Delegación en contenedor padre:
document.getElementById('table-body').addEventListener('click', (e) => {
  const tr = e.target.closest('tr[data-id]');
  if (tr) {
    verDetalle(tr.dataset.id);
  }
});
```
