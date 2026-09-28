import re

js_file = r'c:\EGalli\Carniceria_Gorina\static\js\tablero.js'
with open(js_file, 'r', encoding='utf-8') as f:
    js = f.read()

charts_code = '''
      if (typeof Charts !== 'undefined' && Charts.renderRankingBars) {
        Charts.renderRankingBars('chartClientesVenta', data.ranking.slice(0, 10), 'venta_neta');
        Charts.renderRankingBars('chartClientesKg', data.ranking.slice(0, 10), 'kg_netos');
      }
'''

# insert before const tbody = ... in loadClientes
js = js.replace("const tbody = document.querySelector('#tableClientes tbody');", charts_code + "\n      const tbody = document.querySelector('#tableClientes tbody');")

with open(js_file, 'w', encoding='utf-8') as f:
    f.write(js)
