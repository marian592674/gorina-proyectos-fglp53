import re

html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix the duplicate kpi-sub for kTicket
content = re.sub(
    r'<div class="kpi-sub" style="text-align:center;">Venta Neta ÷ Tickets</div>\s*</div>\s*<div class="kpi" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">\s*<div class="kpi-tag" style="margin:0 auto;text-align:center;">Clientes / Legajos</div>\s*<div class="kpi-value" id="kClientes" style="text-align:center;">0</div>\s*<div class="kpi-sub" style="text-align:center;">Únicos con venta</div>\s*</div>\s*<div class="kpi-sub" style="text-align:center;">Venta Neta ÷ Comprobante</div>\s*</div>',
    '''<div class="kpi-sub" style="text-align:center;">Venta Neta ÷ Tickets</div>
      </div>
      <div class="kpi" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">
        <div class="kpi-tag" style="margin:0 auto;text-align:center;">Clientes / Legajos</div>
        <div class="kpi-value" id="kClientes" style="text-align:center;">0</div>
        <div class="kpi-sub" style="text-align:center;">Únicos con venta</div>
      </div>''',
    content
)

# Rename "Top Grupos" to "Top Agrupa" in HTML
content = content.replace('>Top Grupos<', '>Top Agrupa<')
content = content.replace('<th>Grupo</th>', '<th>Agrupa</th>')
content = content.replace('<tbody id="tTopGrupos">', '<tbody id="tTopAgrupa">')

with open(html_file, 'w', encoding='utf-8') as f:
    f.write(content)

# Update css
css_file = r'c:\EGalli\Carniceria_Gorina\static\css\estilos.css'
with open(css_file, 'r', encoding='utf-8') as f:
    css = f.read()

if '.half-width' not in css:
    css = css.replace('.filters-grid {', '.filters-grid {\n  align-items: end;\n')
    css += '\n.filter-group.half-width { flex: 1 1 45%; min-width: 100px; }'
    with open(css_file, 'w', encoding='utf-8') as f:
        f.write(css)

# Update tablero.js
js_file = r'c:\EGalli\Carniceria_Gorina\static\js\tablero.js'
with open(js_file, 'r', encoding='utf-8') as f:
    js = f.read()

js = js.replace("document.getElementById('kTicket').textContent = Formatter.moneda(d.ticket_promedio);", 
'''document.getElementById('kTicket').textContent = Formatter.moneda(d.ticket_promedio);
  document.getElementById('kClientes').textContent = d.clientes_unicos || 0;''')

js = js.replace('// Popular Top Productos', 
'''
  // Popular Cuadrantes Fijos (si vienen)
  if (d.fixed_dia !== undefined) document.getElementById('kFixedDia').textContent = Formatter.moneda(d.fixed_dia);
  if (d.fixed_mes !== undefined) document.getElementById('kFixedMes').textContent = (d.fixed_mes * 100).toFixed(1) + '%';

  // Popular Top Productos''')

with open(js_file, 'w', encoding='utf-8') as f:
    f.write(js)
