import re

js_file = r'c:\EGalli\Carniceria_Gorina\static\js\tablero.js'
with open(js_file, 'r', encoding='utf-8') as f:
    js = f.read()

# Replace fSinGrupo to fSinAgrupa
js = js.replace('const fSinGrupo = { ...f, grupo: [] };', 'const fSinAgrupa = { ...f, agrupa: [] };')
js = js.replace("API.getRanking(fSinGrupo, 'grupo', 10),", "API.getRanking(fSinAgrupa, 'agrupa', 10),")

# Replace rankingGrupos to rankingAgrupa in HTML and JS
js = js.replace("'rankingGrupos'", "'rankingAgrupa'")
js = js.replace("Filtros.toggleSegment('grupo', nombre);", "Filtros.toggleSegment('agrupa', nombre);")
js = js.replace("Filtros.isSelected('grupo', nombre)", "Filtros.isSelected('agrupa', nombre)")

# We also need to fix the variables
js = js.replace('topGrupos', 'topAgrupa')

with open(js_file, 'w', encoding='utf-8') as f:
    f.write(js)
