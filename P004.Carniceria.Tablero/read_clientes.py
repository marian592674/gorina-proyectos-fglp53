import re

html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

match = re.search(r'<section class="page" id="clientes">.*?</section>', content, flags=re.DOTALL)
if match:
    print(match.group(0)[:1500])
