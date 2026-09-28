import re

html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

new_clientes_section = '''<section class="page" id="clientes">
    <div class="grid2" style="margin-bottom:20px;">
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
    <div class="card">
      <div class="card-header">
        <div class="card-title">Detalle de Clientes</div>
      </div>
      <div class="table-wrap">
        <table id="tableClientes">
          <thead>
            <tr>
              <th style="width:40px">#</th>
              <th>Cliente / Razón Social</th>
              <th class="num">Venta Neta</th>
              <th class="num">Kg Netos</th>
              <th class="num">$/Kg Promedio</th>
              <th class="num">Comprobantes</th>
              <th class="num">Part. %</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </div>
    </div>
  </section>'''

content = re.sub(r'<section class="page" id="clientes">.*?</section>', new_clientes_section, content, flags=re.DOTALL)

with open(html_file, 'w', encoding='utf-8') as f:
    f.write(content)
