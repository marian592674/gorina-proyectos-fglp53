import re
html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

resumen_match = re.search(r'(<section class="page active" id="resumen">)(.*?)(</section>)', content, flags=re.DOTALL)
if resumen_match:
    resumen_html = resumen_match.group(2)
    
    # Extract KPIs
    kpis = re.search(r'(<div class="kpis">.*?</div>\s*</div>)', resumen_html, flags=re.DOTALL)
    if not kpis:
        kpis = re.search(r'(<div class="kpis">.*?</div\s*>\s*</div>)', resumen_html, flags=re.DOTALL)
        
    print("KPIs found:", bool(kpis))
