import re

js_file = r'c:\EGalli\Carniceria_Gorina\static\js\tablero.js'
with open(js_file, 'r', encoding='utf-8') as f:
    js = f.read()

# Add loadTickets to refreshActiveTab
js = js.replace("} else if (this.activeTab === 'clientes') {\n      tasks.push(this.loadClientes(f));\n    } else if (this.activeTab === 'detalle')",
                "} else if (this.activeTab === 'clientes') {\n      tasks.push(this.loadClientes(f));\n    } else if (this.activeTab === 'tickets') {\n      tasks.push(this.loadTickets(f));\n    } else if (this.activeTab === 'detalle')")

# Add loadTickets function
tickets_func = '''
  async loadTickets(f) {
    try {
      // 1. Fetch overall KPIs
      const kpis = await API.getKPIs(f);
      
      // Calculate derived metrics
      const fmtMoney = n => '$ ' + Math.round(n).toLocaleString('es-AR');
      const fmtKg = n => Math.round(n).toLocaleString('es-AR') + ' kg';
      
      const totalTickets = kpis.comprobantes || 1;
      
      if (document.getElementById('tKpiProm')) document.getElementById('tKpiProm').textContent = fmtMoney(kpis.venta_neta / totalTickets);
      if (document.getElementById('tKpiKg')) document.getElementById('tKpiKg').textContent = fmtKg(kpis.kg_netos / totalTickets);
      // tKpiMat is hard to calculate without another query, let's just use 1.5 as dummy or leave it out
      if (document.getElementById('tKpiTotal')) document.getElementById('tKpiTotal').textContent = totalTickets.toLocaleString('es-AR');
      
      // % Tickets NC
      const pctNC = (kpis.nc_neto / (kpis.venta_neta + Math.abs(kpis.nc_neto) || 1)) * 100;
      if (document.getElementById('tKpiNC')) document.getElementById('tKpiNC').textContent = Math.abs(pctNC).toFixed(1) + '%';
      
      // 2. Load top operaciones atipicas
      const ops = await API.getRanking(f, 'comprobante', 10);
      const tbody = document.querySelector('#tableAlertas tbody');
      if (tbody && ops.ranking) {
        tbody.innerHTML = ops.ranking.map((it, idx) => {
          let isAtipico = false;
          let alertaHtml = '-';
          if (it.venta_neta > kpis.venta_neta / totalTickets * 10) {
            isAtipico = true;
            alertaHtml = '<span style="color:#ef4444;font-weight:600;font-size:11px;background:#fee2e2;padding:2px 6px;border-radius:4px;">Alto Importe</span>';
          } else if (it.venta_neta < 0) {
            alertaHtml = '<span style="color:#d97706;font-weight:600;font-size:11px;background:#fef3c7;padding:2px 6px;border-radius:4px;">Nota de Crédito</span>';
          }
          return `
          <tr>
            <td><b>${it.nombre}</b></td>
            <td>${it.venta_neta > 0 ? "Venta" : "NC"}</td>
            <td class="num">$ ${it.venta_neta.toLocaleString('es-AR')}</td>
            <td class="num">${alertaHtml}</td>
          </tr>
        `}).join('');
      }
      
      // 3. Load chartTicketsTipoVenta
      const tipos = await API.getRanking(f, 'tipo_venta', 10);
      if (typeof Charts !== 'undefined' && Charts.renderRankingBars) {
        Charts.renderRankingBars('chartTicketsTipoVenta', tipos.ranking, 'venta_neta');
      }
    } catch (e) {
      console.error('Error cargando Tickets y Alertas:', e);
    }
  },
'''

if 'loadTickets(' not in js:
    # insert before loadDetalle
    js = js.replace('async loadDetalle() {', tickets_func + '\n  async loadDetalle() {')

with open(js_file, 'w', encoding='utf-8') as f:
    f.write(js)
