// Manejo de filtros globales, Almanaque Gorina y selectores rápidos

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
const DIAS = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

const Filtros = {
  state: {
    desde: '',
    hasta: '',
    fecha: [],      // Soporta múltiples días específicos
    mes: [],        // Selección de meses específicos (ej. al cliquear barras)
    tipo_venta: '',
    cliente: [],    // Soporta múltiples clientes
    material: '',
    agrupa: [],     // Soporta múltiples familias Agrupa (ej. Costillar, Rueda)
    apertura: [],   // Soporta múltiples aperturas comerciales (ej. Asado Completo, Vacio)
    tipo_comp: ''
  },
  minFechaBase: '',
  maxFechaBase: '',
  calYear: null,
  calMonth: null,
  pickingStep: 'start', // 'start' o 'end'
  tempStart: null,
  listeners: [],

  onChange(callback) {
    this.listeners.push(callback);
  },

  
  async notify() {
    this.updatePills();
    this.updateCalTriggerText();
    this.listeners.forEach(fn => fn(this.state));
    
    // Filtros en cascada
    try {
      const data = await API.getFiltros(this.state);
      this.updateSelectOptions('fTipoVenta', data.tipos_venta, this.state.tipo_venta);
      this.updateSelectOptions('fAgrupa', data.agrupas, this.state.agrupa);
      this.updateSelectOptions('fApertura', data.aperturas || data.expones, this.state.apertura);
      this.updateSelectOptions('fTipoComp', data.tipos_comp, this.state.tipo_comp);
    } catch(e) {
      console.error("Error actualizando filtros en cascada", e);
    }
  },

  updateSelectOptions(id, options, currentValue) {
    const el = document.getElementById(id);
    if (!el) return;
    // Guardar el valor actual para restaurarlo si todavia es valido
    const current = Array.isArray(currentValue) ? currentValue : (currentValue ? [currentValue] : []);
    el.innerHTML = '<option value="">Todos</option>';
    if (options) {
      options.forEach(opt => {
        const o = document.createElement('option');
        o.value = opt;
        o.textContent = opt;
        if (current.includes(opt)) o.selected = true;
        el.appendChild(o);
      });
    }
  },


  async init() {
    try {
      const data = await API.getFiltros();
      this.minFechaBase = data.rango_fechas ? data.rango_fechas[0] : '';
      this.maxFechaBase = data.rango_fechas ? data.rango_fechas[1] : '';

      this.populateSelect('fTipoVenta', data.tipos_venta);
      this.populateSelect('fAgrupa', data.agrupas);
      this.populateSelect('fApertura', data.aperturas || data.expones);
      this.populateSelect('fTipoComp', data.tipos_comp);

      const cliData = await API.getOpcionesClientes();
      this.populateSelect('fCliente', cliData.clientes);

      const matData = await API.getOpcionesMateriales();
      const matSelect = document.getElementById('fMaterial');
      if (matSelect) {
        matSelect.innerHTML = '<option value="">Todos los materiales</option>' +
          matData.materiales.map(m => `<option value="${m.codigo}">${m.codigo} - ${m.producto}</option>`).join('');
      }

      this.bindSelectEvents();
      this.initAlmanaque();
      this.setRange('todo');
    } catch (e) {
      console.error('Error inicializando filtros:', e);
    }
  },

  populateSelect(id, items) {
    const el = document.getElementById(id);
    if (!el || !items) return;
    const current = el.value;
    el.innerHTML = '<option value="">Todos</option>' +
      items.map(it => `<option value="${it}">${it}</option>`).join('');
    el.value = current;
  },

  bindSelectEvents() {
    const map = {
      fTipoVenta: 'tipo_venta',
      fCliente: 'cliente',
      fMaterial: 'material',
      fAgrupa: 'agrupa',
      fApertura: 'apertura',
      fTipoComp: 'tipo_comp'
    };

    for (const [id, key] of Object.entries(map)) {
      const el = document.getElementById(id);
      if (el) {
        el.addEventListener('change', () => {
          if (Array.isArray(this.state[key])) {
            this.state[key] = el.value ? [el.value] : [];
          } else {
            this.state[key] = el.value;
          }
          this.notify();
        });
      }
    }

    // Botones de rangos rápidos (Chips)
    document.querySelectorAll('.range-chip').forEach(btn => {
      btn.addEventListener('click', () => {
        this.setRange(btn.dataset.range);
      });
    });

    // Cerrar almanaque al hacer clic fuera
    document.addEventListener('click', (ev) => {
      const pop = document.getElementById('calPopover');
      const wrap = document.getElementById('calTriggerWrap');
      if (pop && !pop.hidden && wrap && !wrap.contains(ev.target)) {
        pop.hidden = true;
      }
    });
  },

  /* ==========================================================================
     LÓGICA DEL ALMANAQUE (EL QUE USAMOS SIEMPRE)
     ========================================================================== */
  initAlmanaque() {
    const refDate = this.maxFechaBase ? new Date(this.maxFechaBase + 'T12:00:00') : new Date();
    this.calYear = refDate.getFullYear();
    this.calMonth = refDate.getMonth();
  },

  toggleAlmanaque(ev) {
    if (ev && ev.stopPropagation) ev.stopPropagation();
    const pop = document.getElementById('calPopover');
    if (!pop) return;
    const isOpening = pop.hidden;
    pop.hidden = !isOpening;
    if (isOpening) {
      if (this.state.hasta) {
        const d = new Date(this.state.hasta + 'T12:00:00');
        this.calYear = d.getFullYear();
        this.calMonth = d.getMonth();
      }
      this.pickingStep = 'start';
      this.tempStart = null;
      this.renderAlmanaque();
    }
  },

  navAlmanaque(dir, ev) {
    if (ev && ev.stopPropagation) ev.stopPropagation();
    this.calMonth += dir;
    if (this.calMonth < 0) {
      this.calMonth = 11;
      this.calYear--;
    } else if (this.calMonth > 11) {
      this.calMonth = 0;
      this.calYear++;
    }
    this.renderAlmanaque();
  },

  renderAlmanaque() {
    const grid = document.getElementById('calGrid');
    const title = document.getElementById('calTitle');
    if (!grid || !title) return;

    title.textContent = `${MESES[this.calMonth]} ${this.calYear}`;

    const first = new Date(this.calYear, this.calMonth, 1);
    const totalDays = new Date(this.calYear, this.calMonth + 1, 0).getDate();
    const lead = (first.getDay() + 6) % 7; // Lunes = 0

    const pad = n => String(n).padStart(2, '0');
    const todayISO = new Date().toISOString().slice(0, 10);

    const selFrom = this.tempStart || this.state.desde;
    const selTo = this.tempStart ? this.tempStart : this.state.hasta;

    let html = DIAS.map(d => `<div class="cdw">${d}</div>`).join('');

    for (let i = 0; i < lead; i++) {
      html += '<div class="cd off"></div>';
    }

    for (let d = 1; d <= totalDays; d++) {
      const iso = `${this.calYear}-${pad(this.calMonth + 1)}-${pad(d)}`;
      const hasData = iso >= this.minFechaBase && iso <= this.maxFechaBase;
      const isStart = iso === selFrom;
      const isEnd = iso === selTo;
      const inRange = iso > selFrom && iso < selTo;
      const isToday = iso === todayISO;

      let cls = 'cd';
      if (hasData) cls += ' has';
      if (isStart || isEnd) cls += ' sel';
      else if (inRange) cls += ' in-range';
      if (isToday) cls += ' today';

      html += `<div class="${cls}" onclick="Filtros.pickAlmanaqueDate('${iso}', event)">${d}</div>`;
    }

    grid.innerHTML = html;
  },

  pickAlmanaqueDate(iso, ev) {
    if (ev && ev.stopPropagation) ev.stopPropagation();

    if (this.pickingStep === 'start') {
      this.tempStart = iso;
      this.pickingStep = 'end';
      this.renderAlmanaque();
    } else {
      let from = this.tempStart;
      let to = iso;
      if (from > to) {
        const tmp = from;
        from = to;
        to = tmp;
      }
      this.state.desde = from;
      this.state.hasta = to;
      this.tempStart = null;
      this.pickingStep = 'start';

      const pop = document.getElementById('calPopover');
      if (pop) pop.hidden = true;

      this.clearActiveQuickRange();
      this.notify();
    }
  },

  setAlmanaqueRange(range, ev) {
    if (ev && ev.stopPropagation) ev.stopPropagation();
    const pop = document.getElementById('calPopover');
    if (pop) pop.hidden = true;
    this.setRange(range);
  },

  updateCalTriggerText() {
    const el = document.getElementById('calRangeText');
    if (!el) return;
    if (this.state.desde && this.state.hasta) {
      const fmt = s => {
        const p = s.split('-');
        return `${p[2]}/${p[1]}/${p[0]}`;
      };
      el.textContent = `${fmt(this.state.desde)} — ${fmt(this.state.hasta)}`;
    } else {
      el.textContent = 'Seleccionar período…';
    }
  },

  /* ==========================================================================
     RANGOS RÁPIDOS
     ========================================================================== */
  clearActiveQuickRange() {
    document.querySelectorAll('.range-chip').forEach(b => b.classList.remove('active'));
  },

  setRange(range) {
    this.clearActiveQuickRange();
    const btn = document.querySelector(`.range-chip[data-range="${range}"]`);
    if (btn) btn.classList.add('active');

    const maxDate = this.maxFechaBase ? new Date(this.maxFechaBase + 'T12:00:00') : new Date();
    const pad = n => String(n).padStart(2, '0');
    const toISO = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

    if (range === 'todo') {
      this.state.desde = this.minFechaBase;
      this.state.hasta = this.maxFechaBase;
    } else if (range === 'mes_actual') {
      const y = maxDate.getFullYear();
      const m = maxDate.getMonth();
      this.state.desde = `${y}-${pad(m + 1)}-01`;
      this.state.hasta = toISO(maxDate);
    } else if (range === 'mes_anterior') {
      const y = maxDate.getMonth() === 0 ? maxDate.getFullYear() - 1 : maxDate.getFullYear();
      const m = maxDate.getMonth() === 0 ? 11 : maxDate.getMonth() - 1;
      const lastDay = new Date(y, m + 1, 0).getDate();
      this.state.desde = `${y}-${pad(m + 1)}-01`;
      this.state.hasta = `${y}-${pad(m + 1)}-${pad(lastDay)}`;
    } else if (range === '30dias') {
      const d = new Date(maxDate);
      d.setDate(d.getDate() - 30);
      this.state.desde = toISO(d);
      this.state.hasta = toISO(maxDate);
    } else if (range === 'anio_2026') {
      this.state.desde = '2026-01-01';
      this.state.hasta = '2026-12-31';
    }

    this.notify();
  },

  /* ==========================================================================
     SELECCIÓN MULTISEGMENTO DINÁMICA (UN CLIC SELECCIONA, OTRO DESELECCIONA)
     ========================================================================== */
  toggleSegment(dim, value) {
    if (!value) return;
    if (!Array.isArray(this.state[dim])) {
      this.state[dim] = this.state[dim] ? [this.state[dim]] : [];
    }

    const idx = this.state[dim].indexOf(value);
    if (idx >= 0) {
      // Si ya estaba seleccionado, se deselecciona (toggle off)
      this.state[dim].splice(idx, 1);
    } else {
      // Si no estaba seleccionado, se agrega a la lista de filtros activos (toggle on)
      this.state[dim].push(value);
    }

    // Sincronizar select visual del DOM si existe
    const idMap = { agrupa: 'fAgrupa', apertura: 'fApertura', cliente: 'fCliente' };
    if (idMap[dim]) {
      const sel = document.getElementById(idMap[dim]);
      if (sel) {
        sel.value = this.state[dim].length === 1 ? this.state[dim][0] : '';
      }
    }

    this.notify();
  },

  isSelected(dim, value) {
    if (!value) return false;
    if (Array.isArray(this.state[dim])) {
      return this.state[dim].includes(value);
    }
    return this.state[dim] === value;
  },

  removeSegmentValue(dim, value) {
    if (Array.isArray(this.state[dim])) {
      this.state[dim] = this.state[dim].filter(v => v !== value);
      const idMap = { agrupa: 'fAgrupa', apertura: 'fApertura', cliente: 'fCliente' };
      if (idMap[dim]) {
        const sel = document.getElementById(idMap[dim]);
        if (sel) {
          sel.value = this.state[dim].length === 1 ? this.state[dim][0] : '';
        }
      }
      this.notify();
    } else {
      this.setFilterValue(dim, '');
    }
  },

  setFilterValue(key, value) {
    if (Array.isArray(this.state[key])) {
      this.state[key] = value ? [value] : [];
    } else {
      this.state[key] = value;
    }
    const idMap = {
      tipo_venta: 'fTipoVenta', cliente: 'fCliente', material: 'fMaterial',
      agrupa: 'fAgrupa', apertura: 'fApertura', tipo_comp: 'fTipoComp'
    };
    const el = document.getElementById(idMap[key]);
    if (el) el.value = value;
    this.notify();
  },

  clearAll() {
    this.state.desde = '';
    this.state.hasta = '';
    this.state.fecha = [];
    this.state.mes = [];
    this.state.tipo_venta = '';
    this.state.cliente = [];
    this.state.material = '';
    
    this.state.agrupa = [];
    this.state.apertura = [];
    this.state.tipo_comp = '';

    const ids = ['fTipoVenta', 'fCliente', 'fMaterial', 'fAgrupa', 'fApertura', 'fTipoComp'];
    ids.forEach(id => {
      const el = document.getElementById(id);
      if (el) el.value = '';
    });
    this.setRange('todo');
  },

  removeDayGroup(diaNombre) {
    const DIAS_NOM = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
    const diaIdx = DIAS_NOM.indexOf(diaNombre);
    if (diaIdx >= 0 && Array.isArray(this.state.fecha)) {
      this.state.fecha = this.state.fecha.filter(fStr => {
        const [y, m, d] = fStr.split('-').map(Number);
        return new Date(y, m - 1, d, 12, 0, 0).getDay() !== diaIdx;
      });
      this.notify();
    }
  },

  updatePills() {
    const pillsContainer = document.getElementById('filterPills');
    if (!pillsContainer) return;

    const labels = {
      desde: 'Desde', hasta: 'Hasta', fecha: 'Día', mes: 'Mes', tipo_venta: 'Tipo Venta', cliente: 'Cliente',
      material: 'Material', agrupa: 'Agrupa', apertura: 'Apertura', expone: 'Apertura', tipo_comp: 'Comprobante'
    };

    const active = [];
    for (const [k, v] of Object.entries(this.state)) {
      if (k === 'fecha' && Array.isArray(v) && v.length > 0) {
        // Agrupar fechas por día de la semana para una lectura limpia y ordenada
        const DIAS_NOM = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
        const porDia = {};
        v.forEach(fStr => {
          if (!fStr) return;
          const [y, m, d] = fStr.split('-').map(Number);
          const dayIdx = new Date(y, m - 1, d, 12, 0, 0).getDay();
          const diaNom = DIAS_NOM[dayIdx];
          if (!porDia[diaNom]) porDia[diaNom] = [];
          porDia[diaNom].push(fStr);
        });

        Object.entries(porDia).forEach(([dNom, fList]) => {
          const txt = fList.length > 1 ? `${dNom}s (${fList.length} fechas)` : `${dNom} ${fList[0]}`;
          active.push(`
            <span class="pill">
              <b>Día:</b> ${txt}
              <span class="pill-remove" onclick="Filtros.removeDayGroup('${dNom}')">×</span>
            </span>
          `);
        });
        continue;
      }

      if (Array.isArray(v)) {
        v.forEach(val => {
          if (val) {
            const escaped = String(val).replace(/&/g, '&amp;').replace(/'/g, '&#39;').replace(/"/g, '&quot;');
            active.push(`
              <span class="pill">
                <b>${labels[k]}:</b> ${escaped}
                <span class="pill-remove" onclick="Filtros.removeSegmentValue('${k}', '${escaped}')">×</span>
              </span>
            `);
          }
        });
      } else if (v && !(k === 'desde' && v === this.minFechaBase) && !(k === 'hasta' && v === this.maxFechaBase)) {
        const escaped = String(v).replace(/&/g, '&amp;').replace(/'/g, '&#39;').replace(/"/g, '&quot;');
        active.push(`
          <span class="pill">
            <b>${labels[k]}:</b> ${escaped}
            <span class="pill-remove" onclick="Filtros.setFilterValue('${k}', '')">×</span>
          </span>
        `);
      }
    }

    if (active.length > 0) {
      pillsContainer.innerHTML = active.join('');
      const btnClear = document.getElementById('btnClearFilters');
      if (btnClear) {
        btnClear.classList.remove('is-empty');
        btnClear.disabled = false;
        btnClear.title = 'Limpiar todos los filtros seleccionados';
      }
    } else {
      pillsContainer.innerHTML = '<span class="pills-empty-hint">Sin filtros adicionales activos</span>';
      const btnClear = document.getElementById('btnClearFilters');
      if (btnClear) {
        btnClear.classList.add('is-empty');
        btnClear.disabled = true;
        btnClear.title = 'No hay filtros aplicados para limpiar';
      }
    }
  }
};
