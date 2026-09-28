import re

# 1. Update HTML
html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    html = f.read()

new_filters = '''
      <!-- Filtro Búsqueda Libre (Material) -->
      <div class="filter-group"><label>Material / Producto</label><select id="fMaterial"><option value="">Todos los materiales</option></select></div>
      <div class="filter-group"><label>Agrupa</label><select id="fGrupo"><option value="">Todos</option></select></div>
      <div class="filter-group"><label>Expone</label><select id="fAgrupa"><option value="">Todos</option></select></div>
      <div class="filter-group"><label>Apertura</label><select id="fExpone"><option value="">Todos</option></select></div>
'''
html = re.sub(
    r'<!-- Filtro Búsqueda Libre \(Material\).*?<div class="filter-group"><label>Apertura</label><select id="fApertura" disabled title="Columna no disponible en BD aún"><option value="">Todos</option></select></div>',
    new_filters.strip(),
    html,
    flags=re.DOTALL
)

# And fix the title of rankings
html = html.replace('Top Agrupa', 'Top Agrupa (Familias)') # just in case, but let's keep it "Top Agrupa ($)"
# Wait, if they renamed Grupo to Agrupa, maybe "Top Agrupa" means Top of DB `grupo`!
# Let's see what "Top Agrupa" was using. It was using DB `agrupa`. I'll leave that alone for now, or change it to DB `grupo`.
# I'll just change the title back to "Top Agrupa" if it was changed.

with open(html_file, 'w', encoding='utf-8') as f:
    f.write(html)

# 2. Update filtros.js
js_file = r'c:\EGalli\Carniceria_Gorina\static\js\filtros.js'
with open(js_file, 'r', encoding='utf-8') as f:
    js = f.read()

# I had removed fGrupo. I need to restore it.
restore_grupo_init = '''
      this.populateSelect('fGrupo', data.grupos);
      this.populateSelect('fAgrupa', data.agrupas);
      this.populateSelect('fExpone', data.expones);
'''
js = re.sub(r"this\.populateSelect\('fAgrupa', data\.agrupas\);\s*this\.populateSelect\('fExpone', data\.expones\);", restore_grupo_init.strip(), js)

restore_grupo_event = '''
    document.getElementById('fGrupo').addEventListener('change', e => {
      this.state.grupo = Array.from(e.target.selectedOptions).map(o => o.value).filter(v => v);
      this.notify();
    });
    document.getElementById('fAgrupa').addEventListener('change', e => {
'''
js = js.replace("document.getElementById('fAgrupa').addEventListener('change', e => {", restore_grupo_event.strip())

restore_grupo_clear = '''
    if(document.getElementById('fGrupo')) document.getElementById('fGrupo').value = '';
    if(document.getElementById('fAgrupa')) document.getElementById('fAgrupa').value = '';
'''
js = re.sub(r"if\s*\(document\.getElementById\('fAgrupa'\)\)\s*document\.getElementById\('fAgrupa'\)\.value\s*=\s*'';", restore_grupo_clear.strip(), js)

restore_grupo_state = '''
    this.state.grupo = [];
    this.state.agrupa = '';
'''
js = js.replace("this.state.agrupa = '';", restore_grupo_state.strip())

restore_grupo_cascaded = '''
      this.updateSelectOptions('fTipoVenta', data.tipos_venta, this.state.tipo_venta);
      this.updateSelectOptions('fGrupo', data.grupos, this.state.grupo);
      this.updateSelectOptions('fAgrupa', data.agrupas, this.state.agrupa);
      this.updateSelectOptions('fExpone', data.expones, this.state.expone);
'''
js = re.sub(r"this\.updateSelectOptions\('fTipoVenta', data\.tipos_venta, this\.state\.tipo_venta\);\s*this\.updateSelectOptions\('fAgrupa', data\.agrupas, this\.state\.agrupa\);\s*this\.updateSelectOptions\('fExpone', data\.expones, this\.state\.expone\);", restore_grupo_cascaded.strip(), js)

# Also fix the state mapping: it seems 'grupo', 'agrupa', 'expone' are all single select or multi select?
# The UI has standard <select> so it's single select. Wait, my code mapped them as Array?
# "this.state.grupo = Array.from(e.target.selectedOptions)..." this handles both.

with open(js_file, 'w', encoding='utf-8') as f:
    f.write(js)

# 3. Update tablero.js
tjs_file = r'c:\EGalli\Carniceria_Gorina\static\js\tablero.js'
with open(tjs_file, 'r', encoding='utf-8') as f:
    tjs = f.read()

# In loadResumen, Top Agrupa was calling API with 'agrupa'. Since they renamed Grupo to Agrupa, maybe "Top Agrupa" means DB 'grupo'!
# "Top por GRUPOS tiene que ser remplazado por TOP AGRUPA"
# So Top Agrupa should use DB 'grupo'.
tjs = tjs.replace("const fSinAgrupa = { ...f, agrupa: [] };", "const fSinGrupo = { ...f, grupo: [] };")
tjs = tjs.replace("API.getRanking(fSinAgrupa, 'agrupa', 10)", "API.getRanking(fSinGrupo, 'grupo', 10)")

tjs = tjs.replace("Filtros.toggleSegment('agrupa', nombre)", "Filtros.toggleSegment('grupo', nombre)")
tjs = tjs.replace("Filtros.isSelected('agrupa', nombre)", "Filtros.isSelected('grupo', nombre)")

with open(tjs_file, 'w', encoding='utf-8') as f:
    f.write(tjs)
