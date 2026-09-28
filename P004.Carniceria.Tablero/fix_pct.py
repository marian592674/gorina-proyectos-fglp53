import re

js_file = r'c:\EGalli\Carniceria_Gorina\static\js\graficos.js'
with open(js_file, 'r', encoding='utf-8') as f:
    js = f.read()

# Update renderRankingBars to show percentage
old_code = '''<div class="ranking-val">${formatted}</div>'''
new_code = '''<div class="ranking-val">${formatted} <span style="font-size:10px; color:#64748b; margin-left:4px;">(${pct.toFixed(1)}%)</span></div>'''

js = js.replace(old_code, new_code)

with open(js_file, 'w', encoding='utf-8') as f:
    f.write(js)
