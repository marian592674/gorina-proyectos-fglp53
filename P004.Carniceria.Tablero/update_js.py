import re

js_file = r'c:\EGalli\Carniceria_Gorina\static\js\filtros.js'
with open(js_file, 'r', encoding='utf-8') as f:
    js = f.read()

# Remove fGrupo population
js = js.replace("this.populateSelect('fGrupo', data.grupos);", "")

# Remove event listener for fGrupo
js = re.sub(r"document\.getElementById\('fGrupo'\)\.addEventListener\('change',\s*e\s*=>\s*\{.*?this\.notify\(\);\s*\}\);", "", js, flags=re.DOTALL)

# In clearAll, remove fGrupo logic
js = js.replace("document.getElementById('fGrupo').value = '';", "")
js = js.replace("this.state.grupo = [];", "")

# Add cascaded filters logic to notify()
cascaded_code = '''
  async notify() {
    this.updatePills();
    this.updateCalTriggerText();
    this.listeners.forEach(fn => fn(this.state));
    
    // Filtros en cascada
    try {
      const data = await API.getFiltros(this.state);
      this.updateSelectOptions('fTipoVenta', data.tipos_venta, this.state.tipo_venta);
      this.updateSelectOptions('fAgrupa', data.agrupas, this.state.agrupa);
      this.updateSelectOptions('fExpone', data.expones, this.state.expone);
      this.updateSelectOptions('fTipoComp', data.tipos_comp, this.state.tipo_comp);
    } catch(e) {
      console.error("Error actualizando filtros en cascada", e);
    }
  },

  updateSelectOptions(id, options, currentValue) {
    const el = document.getElementById(id);
    if (!el) return;
    // Guardar el valor actual para restaurarlo si todavia es valido
    const current = Array.isArray(currentValue) ? currentValue : (currentValue ? [currentValue] : []);
    el.innerHTML = '<option value="">Todos</option>';
    if (options) {
      options.forEach(opt => {
        const o = document.createElement('option');
        o.value = opt;
        o.textContent = opt;
        if (current.includes(opt)) o.selected = true;
        el.appendChild(o);
      });
    }
  },
'''

# Replace notify()
js = re.sub(r'notify\(\)\s*\{\s*this\.updatePills\(\);\s*this\.updateCalTriggerText\(\);\s*this\.listeners\.forEach\(fn\s*=>\s*fn\(this\.state\)\);\s*\},', cascaded_code, js)

with open(js_file, 'w', encoding='utf-8') as f:
    f.write(js)

# Update api.js to pass params to getFiltros
api_file = r'c:\EGalli\Carniceria_Gorina\static\js\api.js'
with open(api_file, 'r', encoding='utf-8') as f:
    api = f.read()

api = api.replace('async getFiltros() {', 'async getFiltros(params = {}) {')
api = api.replace("return this.fetchJson('/api/filtros');", "const qs = this.buildQuery(params);\n    return this.fetchJson('/api/filtros?' + qs);")

with open(api_file, 'w', encoding='utf-8') as f:
    f.write(api)
