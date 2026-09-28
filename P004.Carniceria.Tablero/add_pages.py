import re

html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Add the sections before closing </main> or </div> wrap
# Let's see what is at the end.
# It ends with <section class="page" id="calidad">...</section></div>
new_sections = '''
  <!-- Pestaña: Clientes -->
  <section class="page" id="clientes">
    <div class="grid2">
      <div class="card">
        <div class="card-header">
          <div class="card-title">Top Clientes por Venta Neta ($)</div>
        </div>
        <div class="chart-container" id="chartClientesVenta" style="height:300px"></div>
      </div>
      <div class="card">
        <div class="card-header">
          <div class="card-title">Top Clientes por Kilos (kg)</div>
        </div>
        <div class="chart-container" id="chartClientesKg" style="height:300px"></div>
      </div>
    </div>
    <div class="card" style="margin-top:20px;">
      <div class="card-header">
        <div class="card-title">Detalle de Clientes</div>
      </div>
      <div class="table-wrap">
        <table id="tableClientesDetail">
          <thead>
            <tr>
              <th>Cliente</th>
              <th class="num">Venta Neta ($)</th>
              <th class="num">Kilos Netos (kg)</th>
              <th class="num">Precio Prom. ($/kg)</th>
              <th class="num">Comprobantes</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </div>
    </div>
  </section>

  <!-- Pestaña: Tickets y Alertas -->
  <section class="page" id="tickets">
    <div class="kpis" id="ticketsKpis">
      <div class="kpi" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">
        <div class="kpi-tag" style="margin:0 auto;text-align:center;">Ticket Promedio</div>
        <div class="kpi-value" id="tKpiProm">$ 0</div>
      </div>
      <div class="kpi" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">
        <div class="kpi-tag" style="margin:0 auto;text-align:center;">Kg Promedio</div>
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
          <div class="card-title">Distribución de Tickets por Importe</div>
        </div>
        <div class="chart-container" id="chartTicketsRotacion" style="height:300px">
          <!-- Placeholder para gráfico -->
          <div style="display:flex;align-items:center;justify-content:center;height:100%;color:#94a3b8;">Construyendo gráfico...</div>
        </div>
      </div>
      <div class="card">
        <div class="card-header">
          <div class="card-title">Operaciones Atípicas / Alertas</div>
          <div class="card-sub">Tickets que desvían significativamente del promedio</div>
        </div>
        <div class="table-wrap" style="max-height:300px;overflow-y:auto;">
          <table id="tableAlertas">
            <thead>
              <tr>
                <th>Fecha</th>
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

# We will inject new_sections right before <section class="page" id="detalle">
content = content.replace('<section class="page" id="detalle">', new_sections + '\n  <section class="page" id="detalle">')

with open(html_file, 'w', encoding='utf-8') as f:
    f.write(content)

