// Controlador maestro del Tablero de Carnicería Gorina

const App = {
  activeTab: 'resumen',
  evolGranularity: 'mes',
  detallePage: 1,
  detalleLimit: 50,
  detalleSort: 'fecha',
  detalleDir: 'DESC',

  async init() {
    this.bindTabs();
    this.bindDetailEvents();

    Filtros.onChange(async (filters) => {
      await this.refreshActiveTab();
    });

    await Filtros.init();
    await this.loadStatus();

    // Cerrar menú de descarga al hacer clic fuera
    document.addEventListener('click', (ev) => {
      const pop = document.getElementById('downloadPopover');
      const wrap = document.getElementById('downloadWrap');
      if (pop && pop.classList.contains('active') && wrap && !wrap.contains(ev.target)) {
        pop.classList.remove('active');
      }
    });
  },

  async setGranularity(gran) {
    if (this.evolGranularity === gran) return;
    this.evolGranularity = gran;
    document.getElementById('btnGranMes')?.classList.toggle('active', gran === 'mes');
    document.getElementById('btnGranDia')?.classList.toggle('active', gran === 'dia');
    const f = Filtros.state;
    await this.loadResumen(f);
  },

  cachedEvolRows: [],

  toggleDayOfWeek(diaIdx) {
    if (!this.cachedEvolRows || !this.cachedEvolRows.length) return;

    // Obtener todas las fechas del dataset visible que caen en este diaIdx
    const matchingDates = [];
    this.cachedEvolRows.forEach(r => {
      if (r.periodo && r.periodo.length === 10) {
        const [y, m, d] = r.periodo.split('-').map(Number);
        const day = new Date(y, m - 1, d, 12, 0, 0).getDay();
        if (day === diaIdx) {
          matchingDates.push(r.periodo);
        }
      }
    });

    if (!matchingDates.length) return;

    if (!Array.isArray(Filtros.state.fecha)) {
      Filtros.state.fecha = [];
    }

    const allSelected = matchingDates.every(dt => Filtros.state.fecha.includes(dt));

    if (allSelected) {
      // Si ya estaban todos seleccionados, los deselecciona
      Filtros.state.fecha = Filtros.state.fecha.filter(dt => !matchingDates.includes(dt));
    } else {
      // Si falta alguno, los agrega todos
      matchingDates.forEach(dt => {
        if (!Filtros.state.fecha.includes(dt)) {
          Filtros.state.fecha.push(dt);
        }
      });
    }

    this.updateDayPills();
    Filtros.notify();
  },

  updateDayPills() {
    const selFechas = Filtros.state.fecha || [];
    [0, 1, 2, 3, 4, 5, 6].forEach(dia => {
      const btn = document.getElementById(`pillDay${dia}`);
      if (!btn) return;
      if (!selFechas.length || !this.cachedEvolRows || !this.cachedEvolRows.length) {
        btn.classList.remove('active');
        return;
      }
      const matching = this.cachedEvolRows.filter(r => {
        if (!r.periodo || r.periodo.length !== 10) return false;
        const [y, m, d] = r.periodo.split('-').map(Number);
        return new Date(y, m - 1, d, 12, 0, 0).getDay() === dia;
      }).map(r => r.periodo);

      const isActive = matching.length > 0 && matching.every(dt => selFechas.includes(dt));
      btn.classList.toggle('active', isActive);
    });
  },

  bindTabs() {
    document.querySelectorAll('.tab').forEach(btn => {
      btn.addEventListener('click', async () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));

        btn.classList.add('active');
        const pageId = btn.dataset.page;
        const pageEl = document.getElementById(pageId);
        if (pageEl) pageEl.classList.add('active');

        this.activeTab = pageId;
        await this.refreshActiveTab();
      });
    });
  },

  bindDetailEvents() {
    const searchInput = document.getElementById('searchDetail');
    if (searchInput) {
      let timeout = null;
      searchInput.addEventListener('input', () => {
        clearTimeout(timeout);
        timeout = setTimeout(() => {
          this.detallePage = 1;
          this.loadDetalle();
        }, 300);
      });
    }

    const prevBtn = document.getElementById('btnPrevPage');
    const nextBtn = document.getElementById('btnNextPage');
    if (prevBtn) {
      prevBtn.addEventListener('click', () => {
        if (this.detallePage > 1) {
          this.detallePage--;
          this.loadDetalle();
        }
      });
    }
    if (nextBtn) {
      nextBtn.addEventListener('click', () => {
        this.detallePage++;
        this.loadDetalle();
      });
    }
  },

  ultimoDiaCargado: '',
  mesEnCurso: '',

  async loadStatus() {
    try {
      const st = await API.getEstado();
      this.ultimoDiaCargado = st.ultimo_dia_fecha || st.ultima_venta || '';
      this.mesEnCurso = st.mes_en_curso || '';

      const el = document.getElementById('statusInfo');
      if (el) {
        el.innerHTML = `
          <span><b>Base conectada:</b> MySQL 8.0</span> · 
          <span><b>Registros:</b> ${st.registros.toLocaleString('es-AR')}</span> · 
          <span><b>Última venta:</b> ${st.ultima_venta || '—'}</span> · 
          <span><b>Última carga:</b> ${st.ultima_carga || 'Base histórica'}</span>
        `;
      }

      // 1. KPI Fijo: Ventas Último Día Cargado (Importe $ y Kilos)
      const elDiaNeto = document.getElementById('fixKpiDiaNeto');
      const elDiaKg = document.getElementById('fixKpiDiaKg');
      const elDiaFecha = document.getElementById('fixKpiDiaFecha');
      if (elDiaNeto && st.ultimo_dia_neto !== undefined) {
        elDiaNeto.textContent = '$ ' + Math.round(st.ultimo_dia_neto).toLocaleString('es-AR');
      }
      if (elDiaKg && st.ultimo_dia_kg !== undefined) {
        elDiaKg.textContent = Math.round(st.ultimo_dia_kg).toLocaleString('es-AR') + ' kg';
      }
      if (elDiaFecha && this.ultimoDiaCargado) {
        const [y, m, d] = this.ultimoDiaCargado.split('-').map(Number);
        const dtObj = new Date(y, m - 1, d, 12, 0, 0);
        const diasNom = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
        elDiaFecha.textContent = `${diasNom[dtObj.getDay()]} ${String(d).padStart(2, '0')}/${String(m).padStart(2, '0')}/${y}`;
      }

      // 2. KPI Fijo: Ventas Último Día / Mes en Curso % (% $ y % Kg)
      const elPct = document.getElementById('fixKpiPct');
      const elPctKg = document.getElementById('fixKpiPctKg');
      const elMesSub = document.getElementById('fixKpiMesSub');
      if (elPct && st.pct_dia_mes !== undefined) {
        elPct.textContent = `${st.pct_dia_mes}%`;
      }
      if (elPctKg && st.pct_dia_mes_kg !== undefined) {
        elPctKg.textContent = `${st.pct_dia_mes_kg}% kg`;
      }
      if (elMesSub && this.mesEnCurso) {
        const [y, m] = this.mesEnCurso.split('-').map(Number);
        const mesesNom = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
        elMesSub.textContent = `Mes ${mesesNom[m - 1]} ${y}`;
      }
    } catch (e) {
      console.warn('No se pudo leer estado:', e);
    }
  },

  filterToUltimoDia() {
    if (this.ultimoDiaCargado) {
      Filtros.state.desde = this.ultimoDiaCargado;
      Filtros.state.hasta = this.ultimoDiaCargado;
      Filtros.state.fecha = [];
      Filtros.state.mes = [];
      document.querySelectorAll('.range-chip').forEach(c => c.classList.remove('active'));
      Filtros.notify();
    }
  },

  filterToMesEnCurso() {
    Filtros.setRange('mes_actual');
  },

  async refreshActiveTab() {
    const f = Filtros.state;
    // Disparamos en paralelo la carga de KPIs y el contenido de la pestaña activa para máxima velocidad
    const tasks = [this.loadKPIs(f)];

    if (this.activeTab === 'resumen') {
      tasks.push(this.loadResumen(f));
    } else if (this.activeTab === 'productos') {
      tasks.push(this.loadProductos(f));
    } else if (this.activeTab === 'drilldown') {
      tasks.push(this.loadDrilldown(f));
    } else if (this.activeTab === 'clientes') {
      tasks.push(this.loadClientes(f));
    } else if (this.activeTab === 'tickets') {
      tasks.push(this.loadTickets(f));
    } else if (this.activeTab === 'detalle') {
      tasks.push(this.loadDetalle());
    } else if (this.activeTab === 'calidad') {
      tasks.push(this.loadCalidad());
    }

    await Promise.all(tasks);
  },

  async loadKPIs(f) {
    try {
      const k = await API.getKPIs(f);
      const fmtMoney = n => '$ ' + Math.round(n).toLocaleString('es-AR');
      const fmtKg = n => Math.round(n).toLocaleString('es-AR') + ' kg';

      const elVenta = document.getElementById('kVenta');
      if (elVenta) elVenta.textContent = fmtMoney(k.venta_neta);

      const elKg = document.getElementById('kKg');
      if (elKg) elKg.textContent = fmtKg(k.kg_netos);

      const elPrecio = document.getElementById('kPrecio');
      if (elPrecio) elPrecio.textContent = fmtMoney(k.precio_promedio) + '/kg';

      const elTicket = document.getElementById('kTicket');
      if (elTicket) elTicket.textContent = fmtMoney(k.ticket_promedio || 0);

      const elCli = document.getElementById('kClientes');
      if (elCli) elCli.textContent = (k.clientes_unicos || k.clientes || 0).toLocaleString('es-AR');

      const elComp = document.getElementById('kComprobantes');
      if (elComp) elComp.textContent = (k.comprobantes || 0).toLocaleString('es-AR');

      const elNC = document.getElementById('kNC');
      if (elNC) elNC.textContent = fmtMoney(k.nc_neto);

      const varEl = document.getElementById('kVar');
      const noteEl = document.getElementById('kVarNote');
      if (varEl) {
        if (k.var_pct !== null && k.var_pct !== undefined) {
          const isUp = k.var_pct >= 0;
          varEl.textContent = `${isUp ? '+' : ''}${k.var_pct}%`;
          varEl.style.color = isUp ? 'var(--verde)' : 'var(--rojo)';
          if (noteEl) {
            if (k.mes_anterior && k.ultimo_mes) {
              noteEl.textContent = `${k.ultimo_mes} vs ${k.mes_anterior}`;
            } else {
              noteEl.textContent = `Mes ${k.ultimo_mes || ''} vs anterior`;
            }
          }
        } else {
          varEl.textContent = '—';
          varEl.style.color = '';
          if (noteEl) noteEl.textContent = 'Sin datos comparativos';
        }
      }
    } catch (e) {
      console.error('Error cargando KPIs:', e);
    }
  },

  async loadResumen(f) {
    try {
      const isDia = this.evolGranularity === 'dia';
      const fSinMes = { ...f, mes: isDia ? f.mes : [], fecha: isDia ? [] : f.fecha };
      const fSinAgrupa = { ...f, agrupa: [] };
      const fSinApertura = { ...f, apertura: [], expone: [] };
      const fSinCliente = { ...f, cliente: [] };

      // Actualizar textos de cabecera de evolución
      const evolTitle = document.getElementById('evolTitle');
      const evolSub = document.getElementById('evolSubText');
      if (evolTitle) {
        evolTitle.textContent = isDia ? 'Evolución Diaria: Facturación Neta y Volumen' : 'Evolución Mensual: Facturación Neta y Volumen';
      }
      if (evolSub) {
        evolSub.textContent = isDia
          ? 'Barras por Día de la Semana · Línea Azul = Kg Netos · Clic en un día para seleccionar/deseleccionar'
          : 'Barras Rojas = $ Neto mensual · Línea Azul = Kg Netos mensuales · Clic en un mes para filtrar';
      }

      // Mostrar / Ocultar leyenda de días de la semana
      const dayLegend = document.getElementById('chartDayLegend');
      if (dayLegend) {
        dayLegend.style.display = isDia ? 'flex' : 'none';
      }

      // Consultas 100% concurrentes en paralelo para respuesta instantánea
      const [evol, topAgrupa, topApertura, topClientes] = await Promise.all([
        API.getEvolucion(fSinMes, this.evolGranularity),
        API.getRanking(fSinAgrupa, 'agrupa', 10),
        API.getRanking(fSinApertura, 'apertura', 10),
        API.getRanking(fSinCliente, 'cliente', 10)
      ]);

      this.cachedEvolRows = evol.evolucion || [];
      if (isDia) {
        this.updateDayPills();
      }

      // Render de Evolución Gráfico y Tabla
      const activePeriods = isDia ? (Filtros.state.fecha || []) : (Filtros.state.mes || []);
      Charts.renderEvolution('chartEvol', evol.evolucion, (periodo) => {
        if (!isDia) {
          Filtros.toggleSegment('mes', periodo);
        } else {
          // En modo diario, al tocar un lunes se seleccionan o deseleccionan todos los lunes
          const [y, m, d] = periodo.split('-').map(Number);
          const diaIdx = new Date(y, m - 1, d, 12, 0, 0).getDay();
          this.toggleDayOfWeek(diaIdx);
        }
      }, activePeriods);

      const tEvol = document.getElementById('tableEvol');
      if (tEvol) {
        tEvol.innerHTML = `
          <thead>
            <tr>
              <th>Período (${isDia ? 'Día' : 'Mes'})</th>
              <th class="num">Venta Neta</th>
              <th class="num">Kg Netos</th>
              <th class="num">$/Kg Promedio</th>
              <th class="num">Comprobantes</th>
              <th class="num">Clientes</th>
            </tr>
          </thead>
          <tbody>
            ${evol.evolucion.map(d => `
              <tr>
                <td><b>${d.periodo}</b></td>
                <td class="num">$ ${d.venta_neta.toLocaleString('es-AR')}</td>
                <td class="num">${d.kg_netos.toLocaleString('es-AR')} kg</td>
                <td class="num"><b>$ ${d.precio_promedio.toLocaleString('es-AR')}</b></td>
                <td class="num">${d.comprobantes.toLocaleString('es-AR')}</td>
                <td class="num">${d.clientes.toLocaleString('es-AR')}</td>
              </tr>
            `).join('')}
          </tbody>
        `;
      }

      // Render de Rankings Top con preservación multi-segmento
      Charts.renderRankingBars('rankingAgrupa', topAgrupa.ranking, 'venta_neta', (nombre) => {
        Filtros.toggleSegment('agrupa', nombre);
      }, (nombre) => Filtros.isSelected('agrupa', nombre));

      Charts.renderRankingBars('rankingApertura', topApertura.ranking, 'venta_neta', (nombre) => {
        Filtros.toggleSegment('apertura', nombre);
      }, (nombre) => Filtros.isSelected('apertura', nombre));

      Charts.renderRankingBars('rankingClientes', topClientes.ranking, 'venta_neta', (nombre) => {
        Filtros.toggleSegment('cliente', nombre);
      }, (nombre) => Filtros.isSelected('cliente', nombre));

    } catch (e) {
      console.error('Error cargando Resumen:', e);
    }
  },

  async loadProductos(f) {
    try {
      const data = await API.getRanking(f, 'apertura', 50);
      const tbody = document.querySelector('#tableProductos tbody');
      if (tbody) {
        tbody.innerHTML = data.ranking.map((it, idx) => `
          <tr>
            <td>${idx + 1}</td>
            <td><b>${it.nombre}</b></td>
            <td class="num">$ ${it.venta_neta.toLocaleString('es-AR')}</td>
            <td class="num">${it.kg_netos.toLocaleString('es-AR')} kg</td>
            <td class="num"><b>$ ${it.precio_promedio.toLocaleString('es-AR')}</b></td>
            <td class="num">${it.comprobantes.toLocaleString('es-AR')}</td>
            <td class="num"><span class="kpi-badge up">${it.share_neto}%</span></td>
          </tr>
        `).join('');
      }
    } catch (e) {
      console.error('Error cargando Productos:', e);
    }
  },

  async loadDrilldown(f) {
    try {
      const data = await API.getDrilldown(f);
      const tbody = document.querySelector('#tableDrilldown tbody');
      if (tbody) {
        tbody.innerHTML = data.drilldown.slice(0, 200).map(it => `
          <tr>
            <td><b>${it.grupo}</b></td>
            <td>${it.agrupa}</td>
            <td>${it.expone}</td>
            <td class="num">$ ${it.venta_neta.toLocaleString('es-AR')}</td>
            <td class="num">${it.kg_netos.toLocaleString('es-AR')} kg</td>
            <td class="num"><b>$ ${it.precio_promedio.toLocaleString('es-AR')}</b></td>
            <td class="num">${it.comprobantes.toLocaleString('es-AR')}</td>
          </tr>
        `).join('');
      }
    } catch (e) {
      console.error('Error cargando Drilldown:', e);
    }
  },

  async loadClientes(f) {
    try {
      const data = await API.getRanking(f, 'cliente', 50);
      
      if (typeof Charts !== 'undefined' && Charts.renderRankingBars) {
        Charts.renderRankingBars('chartClientesVenta', data.ranking.slice(0, 10), 'venta_neta');
        Charts.renderRankingBars('chartClientesKg', data.ranking.slice(0, 10), 'kg_netos');
      }

      const tbody = document.querySelector('#tableClientes tbody');
      if (tbody) {
        tbody.innerHTML = data.ranking.map((it, idx) => `
          <tr>
            <td>${idx + 1}</td>
            <td><b>${it.nombre}</b></td>
            <td class="num">$ ${it.venta_neta.toLocaleString('es-AR')}</td>
            <td class="num">${it.kg_netos.toLocaleString('es-AR')} kg</td>
            <td class="num"><b>$ ${it.precio_promedio.toLocaleString('es-AR')}</b></td>
            <td class="num">${it.comprobantes.toLocaleString('es-AR')}</td>
            <td class="num"><span class="kpi-badge up">${it.share_neto}%</span></td>
          </tr>
        `).join('');
      }
    } catch (e) {
      console.error('Error cargando Clientes:', e);
    }
  },

  async loadTickets(f) {
    try {
      const kpis = await API.getKPIs(f);
      const fmtMoney = n => '$ ' + Math.round(n).toLocaleString('es-AR');
      const fmtKg = n => Math.round(n).toLocaleString('es-AR') + ' kg';

      const totalTickets = kpis.comprobantes || 1;
      const ventaNeta = kpis.venta_neta || 0;
      const ticketProm = kpis.ticket_promedio || (ventaNeta / totalTickets);
      const kgProm = (kpis.kg_netos || 0) / totalTickets;

      if (document.getElementById('tKpiProm')) document.getElementById('tKpiProm').textContent = fmtMoney(ticketProm);
      if (document.getElementById('tKpiKg')) document.getElementById('tKpiKg').textContent = kgProm.toFixed(1) + ' kg';
      if (document.getElementById('tKpiTotal')) document.getElementById('tKpiTotal').textContent = totalTickets.toLocaleString('es-AR');

      const ncNeto = Math.abs(kpis.nc_neto || 0);
      const pctNC = ventaNeta > 0 ? ((ncNeto / ventaNeta) * 100).toFixed(1) : '0.0';
      if (document.getElementById('tKpiNC')) document.getElementById('tKpiNC').textContent = `${pctNC}%`;
      if (document.getElementById('tKpiNCPct')) document.getElementById('tKpiNCPct').textContent = `${fmtMoney(ncNeto)} en notas de crédito`;

      // 1. Gráfico / Ranking de Distribución por Tipo de Venta
      const tiposData = await API.getRanking(f, 'tipo_venta', 10);
      if (typeof Charts !== 'undefined' && Charts.renderRankingBars) {
        Charts.renderRankingBars('chartTicketsTipoVenta', tiposData.ranking || [], 'venta_neta');
      }

      // 2. Tabla de Operaciones Atípicas / Alertas
      const ops = await API.getRanking(f, 'comprobante', 15);
      const tbody = document.querySelector('#tableAlertas tbody');
      if (tbody && ops.ranking) {
        tbody.innerHTML = ops.ranking.map(it => {
          let alertaBadge = '<span class="badge-auditoria ok">Normal</span>';
          if (it.venta_neta > ticketProm * 3) {
            alertaBadge = '<span class="badge-auditoria danger">Ticket Alto (&gt;3x Prom)</span>';
          } else if (it.venta_neta < 0) {
            alertaBadge = '<span class="badge-auditoria warn">Nota de Crédito</span>';
          }
          return `
            <tr>
              <td><b>${it.nombre}</b></td>
              <td>${it.venta_neta >= 0 ? 'Factura / Venta' : 'Nota de Crédito'}</td>
              <td class="num"><b>$ ${Math.round(it.venta_neta).toLocaleString('es-AR')}</b></td>
              <td class="num">${Math.round(it.kg_netos || 0).toLocaleString('es-AR')} kg</td>
              <td class="num">${alertaBadge}</td>
            </tr>
          `;
        }).join('');
      }
    } catch (e) {
      console.error('Error cargando Tickets y Alertas:', e);
    }
  },

  async loadDetalle() {
    try {
      const f = Filtros.state;
      const search = (document.getElementById('searchDetail')?.value || '').trim();
      const res = await API.getDetalle({ ...f, search }, this.detallePage, this.detalleLimit, this.detalleSort, this.detalleDir);

      const tbody = document.querySelector('#tableDetalle tbody');
      if (tbody) {
        tbody.innerHTML = res.data.map(r => `
          <tr>
            <td>${r.fecha}</td>
            <td>${r.tipo_comp} ${r.comprobante}</td>
            <td>${r.cliente}</td>
            <td>${r.producto}</td>
            <td>${r.grupo}</td>
            <td>${r.expone}</td>
            <td class="num">${r.kg_neto.toLocaleString('es-AR')} kg</td>
            <td class="num"><b>$ ${r.neto.toLocaleString('es-AR')}</b></td>
            <td class="num">$ ${r.precio.toLocaleString('es-AR')}</td>
          </tr>
        `).join('');
      }

      document.getElementById('detailPageInfo').textContent = `Página ${res.page} de ${res.total_pages} (${res.total_rows.toLocaleString('es-AR')} filas)`;
      document.getElementById('btnPrevPage').disabled = res.page <= 1;
      document.getElementById('btnNextPage').disabled = res.page >= res.total_pages;
    } catch (e) {
      console.error('Error cargando Detalle:', e);
    }
  },

  async loadCalidad() {
    try {
      const q = await API.getCalidad();
      document.getElementById('qFilas').textContent = q.total_filas.toLocaleString('es-AR');
      document.getElementById('qNA').textContent = q.na_filas.toLocaleString('es-AR');
      document.getElementById('qNC').textContent = q.nc_filas.toLocaleString('es-AR');

      const aud = q.auditoria_fechas || {};
      const cobEl = document.getElementById('qCobertura');
      if (cobEl) cobEl.textContent = `${aud.cobertura_pct || 100}%`;

      const habNote = document.getElementById('qHabilesNote');
      if (habNote) habNote.textContent = `${aud.dias_habiles_con_venta || 0} de ${aud.dias_habiles_total || 0} días`;

      const domEl = document.getElementById('qDomingos');
      if (domEl) {
        const domCount = aud.domingos_con_datos_count || 0;
        domEl.textContent = domCount === 0 ? '0 ventas' : `${domCount} con datos`;
        domEl.style.color = domCount === 0 ? 'var(--texto-principal)' : 'var(--rojo)';
      }

      const ferEl = document.getElementById('qFeriados');
      if (ferEl) ferEl.textContent = `${aud.feriados_count || 0} días`;

      const faltEl = document.getElementById('qFaltantes');
      if (faltEl) {
        const fCount = aud.faltantes_count || 0;
        faltEl.textContent = `${fCount} días`;
        faltEl.style.color = fCount === 0 ? 'var(--verde)' : (fCount <= 3 ? 'var(--texto-principal)' : 'var(--rojo)');
      }

      // Badge de estado de auditoría
      const badge = document.getElementById('badgeAuditoriaEstado');
      const subAud = document.getElementById('qAuditoriaSub');
      if (badge) {
        if ((aud.faltantes_count || 0) === 0 && (aud.domingos_con_datos_count || 0) === 0) {
          badge.className = 'badge-auditoria ok';
          badge.textContent = '✓ 100% Ingesta Completa';
        } else if ((aud.faltantes_count || 0) <= 2 && (aud.domingos_con_datos_count || 0) === 0) {
          badge.className = 'badge-auditoria ok';
          badge.textContent = `✓ Operativo (${aud.cobertura_pct}% cobertura)`;
        } else {
          badge.className = 'badge-auditoria warn';
          badge.textContent = `⚠ ${aud.faltantes_count} días sin registrar`;
        }
      }
      if (subAud) {
        subAud.textContent = `Período auditado: ${aud.fecha_min || '—'} al ${aud.fecha_max || '—'} · Lunes a Sábado requeridos`;
      }

      // Tabla de días con novedad (faltantes o feriados)
      const tbodyAud = document.querySelector('#tableAuditoriaDias tbody');
      if (tbodyAud) {
        const filasAud = [];
        if (aud.faltantes && aud.faltantes.length) {
          aud.faltantes.forEach(f => {
            filasAud.push(`
              <tr>
                <td><b>${f.fecha}</b></td>
                <td><b>${f.dia}</b></td>
                <td><span class="badge-auditoria danger">Día Laborable (Lun-Sáb)</span></td>
                <td><span style="color:var(--rojo);font-weight:700">Sin Ventas Registradas</span></td>
                <td>${f.motivo || 'Posible feriado puente, paro o falta de archivo'}</td>
              </tr>
            `);
          });
        }
        if (aud.feriados && aud.feriados.length) {
          aud.feriados.forEach(fe => {
            filasAud.push(`
              <tr>
                <td>${fe.fecha}</td>
                <td>${fe.dia}</td>
                <td><span class="badge-auditoria warn">Feriado Nacional</span></td>
                <td><span style="color:var(--texto-secundario)">Sin Actividad Comercial</span></td>
                <td>${fe.feriado} (Correcto no registrar)</td>
              </tr>
            `);
          });
        }
        if (!filasAud.length) {
          tbodyAud.innerHTML = '<tr><td colspan="5" style="text-align:center;padding:16px;color:#16a34a;font-weight:700">✓ Todos los días laborables de Lunes a Sábado cuentan con registros completos</td></tr>';
        } else {
          tbodyAud.innerHTML = filasAud.join('');
        }
      }

      // Tabla de clasificaciones incompletas
      const tbody = document.querySelector('#tableCalidadNA tbody');
      if (tbody) {
        tbody.innerHTML = q.ejemplos_na.map(r => `
          <tr>
            <td>${r.fecha}</td>
            <td>${r.comprobante}</td>
            <td>${r.cliente}</td>
            <td>${r.producto}</td>
            <td style="color:#b5121b;font-weight:700">${r.agrupa}</td>
            <td style="color:#b5121b;font-weight:700">${r.expone}</td>
            <td class="num">$ ${r.neto.toLocaleString('es-AR')}</td>
          </tr>
        `).join('');
      }
    } catch (e) {
      console.error('Error cargando Calidad:', e);
    }
  },

  toggleDownloadMenu(ev) {
    if (ev && ev.stopPropagation) ev.stopPropagation();
    const pop = document.getElementById('downloadPopover');
    if (!pop) return;
    pop.classList.toggle('active');
  },

  downloadExport(formato) {
    const pop = document.getElementById('downloadPopover');
    if (pop) pop.classList.remove('active');
    const q = API.buildQuery({ ...Filtros.state, formato });
    window.location.href = `/api/exportar?${q}`;
  }
};

window.addEventListener('DOMContentLoaded', () => {
  App.init();
});
