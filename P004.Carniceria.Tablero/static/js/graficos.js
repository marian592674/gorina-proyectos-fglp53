// Motor de renderizado de gráficos SVG interactivos y elegantes

const Charts = {
  formatMoney(num) {
    if (num >= 1e9) return '$' + (num / 1e9).toFixed(2) + ' B';
    if (num >= 1e6) return '$' + (num / 1e6).toFixed(1) + ' M';
    if (num >= 1e3) return '$' + (num / 1e3).toFixed(0) + ' k';
    return '$' + Math.round(num).toLocaleString('es-AR');
  },

  formatKg(num) {
    if (num >= 1e6) return (num / 1e6).toFixed(2) + ' M kg';
    if (num >= 1e3) return (num / 1e3).toFixed(1) + ' k kg';
    return Math.round(num).toLocaleString('es-AR') + ' kg';
  },

  renderEvolution(containerId, data, onPeriodClick, selectedPeriods = []) {
    const container = document.getElementById(containerId);
    if (!container) return;

    if (!data || !data.length) {
      container.innerHTML = '<div style="display:grid;place-items:center;height:100%;color:#94a3b8;font-size:12px">No hay datos para el período seleccionado</div>';
      return;
    }

    const rect = container.getBoundingClientRect();
    const w = rect.width || 800;
    const h = rect.height || 300;

    const padLeft = 65;
    const padRight = 65;
    const padTop = 30;
    const padBottom = 40;
    const plotW = w - padLeft - padRight;
    const plotH = h - padTop - padBottom;

    const maxBar = Math.max(...data.map(d => d.venta_neta || 0), 1);
    const maxLine = Math.max(...data.map(d => d.kg_netos || 0), 1);

    const n = data.length;
    const step = plotW / n;
    const barWidth = Math.min(step * 0.55, 45);

    // Eje Y Líneas horizontales de referencia
    let gridLines = '';
    for (let i = 0; i <= 4; i++) {
      const y = padTop + (plotH / 4) * i;
      const valBar = maxBar * (1 - i / 4);
      const valLine = maxLine * (1 - i / 4);
      gridLines += `
        <line x1="${padLeft}" y1="${y}" x2="${w - padRight}" y2="${y}" stroke="#f1f5f9" stroke-width="1" />
        <text x="${padLeft - 8}" y="${y + 4}" fill="#94a3b8" font-size="10" text-anchor="end">${this.formatMoney(valBar)}</text>
        <text x="${w - padRight + 8}" y="${y + 4}" fill="#94a3b8" font-size="10" text-anchor="start">${this.formatKg(valLine)}</text>
      `;
    }

    const DIAS_COLORS = {
      1: { nombre: 'Lunes', base: '#4f46e5', grad: '#6366f1' },       // Índigo
      2: { nombre: 'Martes', base: '#0284c7', grad: '#38bdf8' },      // Azul cielo
      3: { nombre: 'Miércoles', base: '#059669', grad: '#10b981' },   // Esmeralda
      4: { nombre: 'Jueves', base: '#d97706', grad: '#f59e0b' },      // Ámbar
      5: { nombre: 'Viernes', base: '#e11d48', grad: '#f43f5e' },     // Frambuesa
      6: { nombre: 'Sábado', base: '#7c3aed', grad: '#a855f7' },      // Violeta
      0: { nombre: 'Domingo', base: '#64748b', grad: '#94a3b8' }      // Gris
    };

    // Barras de Venta Neta y Coordenadas para la Línea de Kg
    let barsSvg = '';
    const points = [];

    const hasAnySel = Array.isArray(selectedPeriods) && selectedPeriods.length > 0;

    const isDaily = data.length > 0 && String(data[0].periodo).length === 10;
    const labelStep = isDaily ? Math.max(1, Math.ceil(n / 18)) : 1;

    data.forEach((d, idx) => {
      const cx = padLeft + idx * step + step / 2;
      const barH = ((d.venta_neta || 0) / maxBar) * plotH;
      const barY = padTop + plotH - barH;
      const barX = cx - barWidth / 2;

      const isSel = hasAnySel && selectedPeriods.includes(d.periodo);
      let colClass = 'chart-col';
      if (hasAnySel) {
        colClass += isSel ? ' selected' : ' dimmed';
      }

      const lineY = padTop + plotH - (((d.kg_netos || 0) / maxLine) * plotH);
      points.push({ x: cx, y: lineY, d });

      // Formato y color según si es Diario o Mensual
      let labelText = d.periodo;
      let barFill = '#b5121b';
      let activeColor = '#b5121b';

      if (isDaily) {
        const [y, m, dNum] = d.periodo.split('-').map(Number);
        const fechaObj = new Date(y, m - 1, dNum, 12, 0, 0);
        const diaIdx = fechaObj.getDay();
        const cObj = DIAS_COLORS[diaIdx] || DIAS_COLORS[0];
        barFill = cObj.base;
        activeColor = cObj.base;
        labelText = `${String(dNum).padStart(2, '0')}/${String(m).padStart(2, '0')}`;
      }

      const showLabel = (idx % labelStep === 0) || (idx === n - 1);
      const barOpacity = hasAnySel ? (isSel ? '1' : '0.22') : '0.92';
      const barStroke = isSel ? 'stroke="#0f172a" stroke-width="2.5"' : '';

      barsSvg += `
        <g class="${colClass}" data-idx="${idx}" style="cursor:pointer">
          <rect x="${barX}" y="${barY}" width="${barWidth}" height="${barH}" rx="3"
                fill="${barFill}" opacity="${barOpacity}" ${barStroke} class="bar-rect" />
          ${showLabel ? `
            <text x="${cx}" y="${padTop + plotH + 18}" fill="${isSel ? activeColor : '#64748b'}" font-size="10" font-weight="${isSel ? '800' : '600'}" text-anchor="middle">
              ${labelText}
            </text>
          ` : ''}
        </g>
      `;
    });

    // Línea y puntos de Kg Netos
    let linePath = '';
    points.forEach((p, idx) => {
      linePath += (idx === 0 ? `M ${p.x} ${p.y}` : ` L ${p.x} ${p.y}`);
    });

    let pointsSvg = points.map(p => `
      <circle cx="${p.x}" cy="${p.y}" r="${isDaily && n > 25 ? '2.5' : '4'}" fill="#2563eb" stroke="#ffffff" stroke-width="1.5" class="point-circle" />
    `).join('');

    container.innerHTML = `
      <svg viewBox="0 0 ${w} ${h}">
        ${gridLines}
        ${barsSvg}
        <path d="${linePath}" fill="none" stroke="#2563eb" stroke-width="${isDaily && n > 25 ? '2' : '3'}" stroke-linecap="round" stroke-linejoin="round" />
        ${pointsSvg}
      </svg>
      <div id="${containerId}_tooltip" class="chart-tooltip"></div>
    `;

    // Tooltip dinámico
    const tooltip = document.getElementById(`${containerId}_tooltip`);
    const cols = container.querySelectorAll('.chart-col');

    cols.forEach(col => {
      col.addEventListener('mouseenter', (e) => {
        const idx = col.dataset.idx;
        const d = data[idx];
        let tituloPeriodo = d.periodo;
        if (isDaily) {
          const [y, m, dNum] = d.periodo.split('-').map(Number);
          const fechaObj = new Date(y, m - 1, dNum, 12, 0, 0);
          const diasSemana = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
          const diaNom = diasSemana[fechaObj.getDay()];
          const colorDia = DIAS_COLORS[fechaObj.getDay()] ? DIAS_COLORS[fechaObj.getDay()].base : '#b5121b';
          tituloPeriodo = `<span style="display:inline-block;width:9px;height:9px;border-radius:50%;background:${colorDia};margin-right:6px"></span><b>${diaNom}</b> ${String(dNum).padStart(2, '0')}/${String(m).padStart(2, '0')}/${y}`;
        }
        tooltip.innerHTML = `
          <div style="font-weight:700;margin-bottom:4px;border-bottom:1px solid #374151;padding-bottom:3px">${tituloPeriodo}</div>
          <div style="display:flex;justify-content:space-between;gap:12px"><span>Venta Neta:</span> <b>$ ${d.venta_neta.toLocaleString('es-AR')}</b></div>
          <div style="display:flex;justify-content:space-between;gap:12px"><span>Kg Netos:</span> <b>${d.kg_netos.toLocaleString('es-AR')} kg</b></div>
          <div style="display:flex;justify-content:space-between;gap:12px"><span>Precio Promedio:</span> <b>$ ${d.precio_promedio.toLocaleString('es-AR')} /kg</b></div>
          <div style="display:flex;justify-content:space-between;gap:12px"><span>Comprobantes:</span> <b>${d.comprobantes}</b></div>
        `;
        tooltip.style.display = 'block';
      });

      col.addEventListener('mousemove', (e) => {
        const b = container.getBoundingClientRect();
        tooltip.style.left = `${e.clientX - b.left + 12}px`;
        tooltip.style.top = `${e.clientY - b.top - 15}px`;
      });

      col.addEventListener('mouseleave', () => {
        tooltip.style.display = 'none';
      });

      if (onPeriodClick) {
        col.addEventListener('click', () => {
          onPeriodClick(data[col.dataset.idx].periodo);
        });
      }
    });
  },

  renderRankingBars(containerId, items, valueKey = 'venta_neta', onSelect, isSelectedFn) {
    const container = document.getElementById(containerId);
    if (!container) return;

    if (!items || !items.length) {
      container.innerHTML = '<div style="color:#94a3b8;font-size:11px;padding:8px">Sin registros</div>';
      return;
    }

    const maxVal = Math.max(...items.map(x => x[valueKey] || 0), 1);

    container.innerHTML = items.map((it, idx) => {
      const val = it[valueKey] || 0;
      const pct = Math.min((val / maxVal) * 100, 100);
      const isMoney = valueKey === 'venta_neta';
      const formatted = isMoney ? this.formatMoney(val) : this.formatKg(val);
      const isSelected = isSelectedFn ? isSelectedFn(it.nombre) : false;

      return `
        <div class="ranking-item ${isSelected ? 'selected' : ''}" data-name="${encodeURIComponent(it.nombre)}" title="${it.nombre}">
          <div class="ranking-name">${it.nombre}</div>
          <div class="ranking-bar-track">
            <div class="ranking-bar-fill" style="width:${pct}%"></div>
          </div>
          <div class="ranking-val">
            <span class="ranking-val-num">${formatted}</span>
            <span class="ranking-val-pct">${pct.toFixed(1)}%</span>
          </div>
          <div class="ranking-check">${isSelected ? '✓' : ''}</div>
        </div>
      `;
    }).join('');

    if (onSelect) {
      container.querySelectorAll('.ranking-item').forEach(el => {
        el.addEventListener('click', () => {
          onSelect(decodeURIComponent(el.dataset.name));
        });
      });
    }
  }
};
