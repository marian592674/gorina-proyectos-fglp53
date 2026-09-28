import re

html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

tickets_section = '''
  <!-- Pestaña: Tickets y Alertas -->
  <section class="page" id="tickets">
    <div class="kpis">
      <div class="kpi" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">
        <div class="kpi-tag" style="margin:0 auto;text-align:center;">Ticket Promedio</div>
        <div class="kpi-value" id="tKpiProm">$ 0</div>
      </div>
      <div class="kpi" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">
        <div class="kpi-tag" style="margin:0 auto;text-align:center;">Kg Promedio / Ticket</div>
        <div class="kpi-value" id="tKpiKg">0 kg</div>
      </div>
      <div class="kpi" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">
        <div class="kpi-tag" style="margin:0 auto;text-align:center;">Materiales / Ticket</div>
        <div class="kpi-value" id="tKpiMat">0</div>
      </div>
      <div class="kpi" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">
        <div class="kpi-tag" style="margin:0 auto;text-align:center;">% Tickets NC</div>
        <div class="kpi-value" id="tKpiNC">0%</div>
      </div>
      <div class="kpi" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">
        <div class="kpi-tag" style="margin:0 auto;text-align:center;">Tickets Analizados</div>
        <div class="kpi-value" id="tKpiTotal">0</div>
      </div>
    </div>

    <div class="grid2" style="margin-top:20px;">
      <div class="card">
        <div class="card-header">
          <div class="card-title">Distribución por Tipo de Venta</div>
        </div>
        <div class="chart-container" id="chartTicketsTipoVenta" style="height:300px;overflow-y:auto;">
        </div>
      </div>
      <div class="card">
        <div class="card-header">
          <div class="card-title">Top 10 Operaciones Atípicas</div>
          <div class="card-sub">Comprobantes de mayor importe</div>
        </div>
        <div class="table-wrap" style="max-height:300px;overflow-y:auto;">
          <table id="tableAlertas">
            <thead>
              <tr>
                <th>Comprobante</th>
                <th>Cliente</th>
                <th class="num">Neto ($)</th>
                <th class="num">Alerta</th>
              </tr>
            </thead>
            <tbody></tbody>
          </table>
        </div>
      </div>
    </div>
  </section>
'''

if 'id="tickets"' not in content:
    content = content.replace('<section class="page" id="detalle">', tickets_section + '\n  <section class="page" id="detalle">')
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(content)
