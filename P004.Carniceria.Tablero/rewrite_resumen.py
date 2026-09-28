import re
html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

resumen_match = re.search(r'(<section class="page active" id="resumen">)(.*?)(</section>\s*<!-- Pestaña 2: Productos -->)', content, flags=re.DOTALL)
if resumen_match:
    resumen_html = resumen_match.group(2)
    
    # 1. KPIs
    kpis_match = re.search(r'(<div class="kpis">.*?</div>\s*</div>)', resumen_html, flags=re.DOTALL)
    kpis_block = kpis_match.group(1) if kpis_match else ""
    
    # 2. Chart block (everything from <!-- Gráfico... to <div class="chart-container" id="chartEvol"></div>)
    chart_match = re.search(r'(<!-- Gráfico de Evolución Temporal -->\s*<div class="card">.*?<div class="chart-container" id="chartEvol"></div>)', resumen_html, flags=re.DOTALL)
    chart_block = chart_match.group(1) + '\n    </div>' if chart_match else ""
    
    # 3. Table Evol
    table_match = re.search(r'(<div class="table-wrap"[^>]*>\s*<table id="tableEvol"></table>\s*</div>)', resumen_html, flags=re.DOTALL)
    table_block = f'''
    <div class="card" style="margin-top:20px;">
      <div class="card-header">
        <div class="card-title">Detalle de Evolución</div>
      </div>
      {table_match.group(1)}
    </div>''' if table_match else ""
    
    # 4. grid3
    grid3_match = re.search(r'(<!-- Rankings Top con Selección Dinámica -->\s*<div class="grid3">.*?<div class="ranking-list" id="rankingClientes"></div>\s*</div>\s*</div>)', resumen_html, flags=re.DOTALL)
    grid3_block = grid3_match.group(1) if grid3_match else ""
    
    new_resumen = f"\n    {kpis_block}\n\n    {chart_block}\n\n    {grid3_block}\n\n    {table_block}\n  "
    
    content = content.replace(resumen_match.group(2), new_resumen)
    
    # Clean up any leftover comments
    content = content.replace('<!-- Cuadrante con datos numéricos (KPIs movidos abajo por pedido del usuario) -->', '')
    
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Rewritten successfully")
