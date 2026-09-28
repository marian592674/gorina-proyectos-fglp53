import sys
html = open('Tablero_Carniceria.html', encoding='utf-8').read()
idx = html.find('id="resumen"')
if idx != -1:
    print(html[idx:idx+3500])
