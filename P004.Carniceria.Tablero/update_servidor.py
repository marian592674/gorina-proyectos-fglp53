import re

py_file = r'c:\EGalli\Carniceria_Gorina\servidor.py'
with open(py_file, 'r', encoding='utf-8') as f:
    content = f.read()

kpis_replacement = '''
                    # Cuadrantes fijos
                    fixed_dia = 0
                    fixed_mes = 0
                    try:
                        max_fecha = db.execute("SELECT MAX(fecha) FROM ventas").fetchone()[0]
                        if max_fecha:
                            fixed_dia = db.execute("SELECT SUM(neto) FROM ventas WHERE fecha = ?", [max_fecha]).fetchone()[0] or 0
                            mes_prefix = max_fecha[:7] + '%'
                            total_mes = db.execute("SELECT SUM(neto) FROM ventas WHERE fecha LIKE ?", [mes_prefix]).fetchone()[0] or 0
                            if total_mes:
                                fixed_mes = fixed_dia / total_mes
                    except:
                        pass

                    kpis = {
                        'venta_neta': round(venta_neta, 2),
                        'kg_netos': round(kg_netos, 2),
                        'precio_promedio': round(precio_prom, 2),
                        'ticket_promedio': round(ticket_prom, 2),
                        'clientes': row[2],
                        'clientes_unicos': row[2],
                        'comprobantes': row[3],
                        'nc_neto': round(float(row[4]), 2),
                        'nc_kg': round(float(row[5]), 2),
                        'var_pct': var_pct,
                        'ultimo_mes': meses[0][0] if meses else None,
                        'ultimo_mes_neto': round(meses[0][1], 2) if meses else 0,
                        'fixed_dia': round(float(fixed_dia), 2),
                        'fixed_mes': float(fixed_mes)
                    }
'''

content = re.sub(r'kpis = \{\s*\'venta_neta\':.*?(?=\s*self.respond_cached)', kpis_replacement, content, flags=re.DOTALL)

# Now modify /api/filtros
filtros_old = '''
                if api_route == '/api/filtros':
                    cache_key = 'filtros'
                    if cache_key in CACHE:
                        self.respond_json(CACHE[cache_key], cache='public, max-age=300')
                        return
                    filtros = {
                        'tipos_venta': [r[0] for r in db.execute('SELECT DISTINCT tipo_venta FROM ventas WHERE tipo_venta != "" ORDER BY tipo_venta')],
                        'grupos': [r[0] for r in db.execute('SELECT DISTINCT grupo FROM ventas WHERE grupo != "" ORDER BY grupo')],
                        'agrupas': [r[0] for r in db.execute('SELECT DISTINCT agrupa FROM ventas WHERE agrupa != "" ORDER BY agrupa')],
                        'expones': [r[0] for r in db.execute('SELECT DISTINCT expone FROM ventas WHERE expone != "" ORDER BY expone')],
                        'tipos_comp': [r[0] for r in db.execute('SELECT DISTINCT tipo FROM ventas WHERE tipo != "" ORDER BY tipo')],
                        'rango_fechas': db.execute('SELECT MIN(fecha), MAX(fecha) FROM ventas').fetchone(),
                        'total_registros': db.execute('SELECT COUNT(*) FROM ventas').fetchone()[0]
                    }
                    CACHE[cache_key] = filtros
                    self.respond_json(filtros, cache='public, max-age=300')
                    return'''

filtros_new = '''
                if api_route == '/api/filtros':
                    w_sql, w_vals = build_filter_clause(params)
                    filtros = {
                        'tipos_venta': [r[0] for r in db.execute(f'SELECT DISTINCT tipo_venta FROM ventas {w_sql} AND tipo_venta != "" ORDER BY tipo_venta', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT tipo_venta FROM ventas WHERE tipo_venta != "" ORDER BY tipo_venta')],
                        'grupos': [r[0] for r in db.execute(f'SELECT DISTINCT grupo FROM ventas {w_sql} AND grupo != "" ORDER BY grupo', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT grupo FROM ventas WHERE grupo != "" ORDER BY grupo')],
                        'agrupas': [r[0] for r in db.execute(f'SELECT DISTINCT agrupa FROM ventas {w_sql} AND agrupa != "" ORDER BY agrupa', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT agrupa FROM ventas WHERE agrupa != "" ORDER BY agrupa')],
                        'expones': [r[0] for r in db.execute(f'SELECT DISTINCT expone FROM ventas {w_sql} AND expone != "" ORDER BY expone', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT expone FROM ventas WHERE expone != "" ORDER BY expone')],
                        'tipos_comp': [r[0] for r in db.execute(f'SELECT DISTINCT tipo FROM ventas {w_sql} AND tipo != "" ORDER BY tipo', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT tipo FROM ventas WHERE tipo != "" ORDER BY tipo')],
                        'rango_fechas': db.execute('SELECT MIN(fecha), MAX(fecha) FROM ventas').fetchone(),
                        'total_registros': db.execute('SELECT COUNT(*) FROM ventas').fetchone()[0]
                    }
                    self.respond_json(filtros, cache='public, max-age=1')
                    return'''

content = content.replace(filtros_old, filtros_new)
# Wait, build_filter_clause might not be available yet! build_filter_clause is defined inside handle_api_request ? Yes.
# And where_sql has "WHERE", so f'SELECT DISTINCT ... FROM ventas {w_sql} AND ...' is correct!

with open(py_file, 'w', encoding='utf-8') as f:
    f.write(content)
