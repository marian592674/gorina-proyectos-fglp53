import re

html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Extract the kpis block
kpis_match = re.search(r'<!-- Cuadrante con datos numéricos.*?-->\s*(<div class="kpis">.*?</div>)', content, flags=re.DOTALL)
if kpis_match:
    kpis_block = kpis_match.group(1)
    # Remove it from the bottom
    content = content.replace(kpis_match.group(0), "")
else:
    # Maybe it doesn't have the comment
    kpis_match = re.search(r'(<div class="kpis">.*?</div>)', content, flags=re.DOTALL)
    kpis_block = kpis_match.group(1)
    content = content.replace(kpis_block, "", 1)

# 2. Extract the grid3 block (Top Rankings)
grid3_match = re.search(r'(<div class="grid3">.*?</div>\s*</div>\s*</div>\s*</div>)', content, flags=re.DOTALL)
if not grid3_match:
    # Just match up to the end of the 3rd card
    grid3_match = re.search(r'(<div class="grid3">.*?</div>\s*</div>\s*</div>\s*</div>)', content, flags=re.DOTALL)

# Let's be safer and extract using start/end markers
def extract_block(html, start_marker, end_marker):
    start = html.find(start_marker)
    if start == -1: return None, html
    end = html.find(end_marker, start)
    if end == -1: return None, html
    end += len(end_marker)
    block = html[start:end]
    html = html[:start] + html[end:]
    return block, html

kpis_block, content = extract_block(content, '<div class="kpis">', '</div>\n    </div>\n\n    <!-- Gráfico') 
if not kpis_block:
    kpis_block, content = extract_block(content, '<!-- Cuadrante con datos numéricos (KPIs movidos abajo por pedido del usuario) -->', '</div>\n  </section>')
    kpis_block = kpis_block.replace('<!-- Cuadrante con datos numéricos (KPIs movidos abajo por pedido del usuario) -->\n    ', '').replace('\n  </section>', '')

evol_card_block, content = extract_block(content, '<!-- Gráfico de Evolución Temporal -->', '</table>\n      </div>\n    </div>')

grid3_block, content = extract_block(content, '<!-- Rankings Top con Selección Dinámica -->', '</div>\n    </div>')
# Wait, grid3 contains 3 cards. The last one ends with </div>\n    </div>\n    </div>
grid3_block, content = extract_block(content, '<!-- Rankings Top con Selección Dinámica -->', '<div class="ranking-list" id="rankingClientes"></div>\n      </div>\n    </div>')

# Wait, this string manipulation is too brittle. Let me just use BeautifulSoup or a robust regex.
