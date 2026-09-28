import re

html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Match the <div class="kpis"> block
match = re.search(r'(<div class="kpis">.*?</div\s*>\s*<!-- Gráfico de Evolución)', content, flags=re.DOTALL)
if match:
    # Need to match the entire <div class="kpis"> block precisely
    # It contains multiple <div class="kpi"> and ends before <!-- Gráfico
    kpis_block_match = re.search(r'(<div class="kpis">.*?</div>\s*)(?=<!-- Gráfico de Evolución)', content, flags=re.DOTALL)
    if kpis_block_match:
        kpis_block = kpis_block_match.group(1)
        
        # Remove the kpis_block from its current position
        content = content.replace(kpis_block, "")
        
        # Insert it after the grid3 div that closes the page section
        content = re.sub(
            r'(<div class="ranking-list" id="rankingClientes"></div>\s*</div>\s*</div>)',
            r'\1\n\n    <!-- Cuadrante con datos numéricos (KPIs movidos abajo por pedido del usuario) -->\n    ' + kpis_block.strip() + '\n',
            content
        )
        with open(html_file, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Layout moved!")
    else:
        print("Block content not found properly.")
else:
    print("Not found")
