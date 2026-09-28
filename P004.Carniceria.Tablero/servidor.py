"""Servidor analítico optimizado para el Tablero de Ventas de Carnicería Gorina."""
import csv
import datetime as dt
import gzip
import io
import json
import mimetypes
import os
import re
import socket
import db as db_module
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parent
CONFIG = json.loads((ROOT / 'config.json').read_text(encoding='utf-8'))
HTML = ROOT / 'Tablero_Carniceria.html'
STATIC_DIR = ROOT / 'static'

# Cache en memoria para respuestas estáticas y de filtros con invalidación automática
CACHE = {}

def check_cache_validity():
    pass

def get_db():
    return db_module.get_db()

def build_filter_clause(params, include_date=True):
    clauses = []
    values = []

    def get_multi(key):
        items = []
        for val in params.get(key, []):
            if '||' in val:
                parts = val.split('||')
            elif ',' in val and key != 'cliente':
                parts = val.split(',')
            else:
                parts = [val]
            for part in parts:
                p = part.strip()
                if p and p not in items:
                    items.append(p)
        return items

    if include_date:
        desde = params.get('desde', [''])[0].strip()
        hasta = params.get('hasta', [''])[0].strip()
        if desde:
            clauses.append("fecha >= ?")
            values.append(desde)
        if hasta:
            clauses.append("fecha <= ?")
            values.append(hasta)

        # Soporte para filtrar por uno o varios meses específicos del gráfico
        meses = get_multi('mes')
        if meses:
            placeholders = ','.join('?' for _ in meses)
            clauses.append(f"substr(fecha, 1, 7) IN ({placeholders})")
            values.extend(meses)

        # Soporte para filtrar por una o varias fechas específicas
        fechas = get_multi('fecha')
        if fechas:
            placeholders = ','.join('?' for _ in fechas)
            clauses.append(f"fecha IN ({placeholders})")
            values.extend(fechas)

    # Campos con selección múltiple
    material = params.get('material', [''])[0].strip()
    search = params.get('search', [''])[0].strip()

    field_maps = [
        ('tipo_venta', 'tipo_venta'),
        ('cliente', 'cliente'),
        ('grupo', 'grupo'),
        ('agrupa', 'agrupa'),
        ('expone', 'expone'),
        ('expone', 'apertura'),
        ('tipo', 'tipo_comp'),
    ]
    for col, param_name in field_maps:
        vals = get_multi(param_name)
        if vals:
            placeholders = ','.join('?' for _ in vals)
            clauses.append(f"{col} IN ({placeholders})")
            values.extend(vals)

    if material:
        clauses.append("(codigo = ? OR producto LIKE ?)")
        values.extend([material, f"%{material}%"])

    if search:
        clauses.append("(cliente LIKE ? OR expone LIKE ? OR producto LIKE ? OR comprobante LIKE ?)")
        values.extend([f"%{search}%", f"%{search}%", f"%{search}%", f"%{search}%"])

    where_sql = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    return where_sql, values

class Handler(BaseHTTPRequestHandler):
    def respond(self, payload, mime, cache='no-store', status=200):
        use_gzip = 'gzip' in self.headers.get('Accept-Encoding', '') and len(payload) > 512
        if use_gzip:
            payload = gzip.compress(payload, compresslevel=5)
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Cache-Control', cache)
        if use_gzip:
            self.send_header('Content-Encoding', 'gzip')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(payload)

    def respond_file(self, payload, filename, mime):
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(payload)

    def respond_json(self, data, cache='no-store', status=200):
        payload = json.dumps(data, default=lambda o: float(o) if isinstance(o, (float, int)) else str(o), ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        self.respond(payload, 'application/json; charset=utf-8', cache=cache, status=status)

    def respond_cached(self, key, data, cache='public, max-age=120'):
        if len(CACHE) > 500:
            CACHE.clear()
        CACHE[key] = data
        self.respond_json(data, cache=cache)

    def serve_static(self, rel_path):
        target = (STATIC_DIR / rel_path).resolve()
        if not str(target).startswith(str(STATIC_DIR)) or not target.is_file():
            self.send_error(404, 'Archivo no encontrado')
            return
        mime, _ = mimetypes.guess_type(str(target))
        mime = mime or 'application/octet-stream'
        cache = 'public, max-age=3600'
        self.respond(target.read_bytes(), mime, cache=cache)

    def do_GET(self):
        parsed = urlsplit(self.path)
        raw_path = parsed.path.rstrip('/')
        route = raw_path if raw_path else '/'
        params = parse_qs(parsed.query)

        # Rutas de interfaz web
        if route in ('/', '/index.html', '/tablero_carniceria'):
            self.respond(HTML.read_bytes(), 'text/html; charset=utf-8')
            return

        # Servir archivos estáticos
        if route.startswith('/static/'):
            self.serve_static(route[len('/static/'):])
            return
        if route.startswith('/tablero_carniceria/static/'):
            self.serve_static(route[len('/tablero_carniceria/static/'):])
            return

        # Normalizar prefijo de API
        api_route = route
        if api_route.startswith('/tablero_carniceria/api'):
            api_route = api_route[len('/tablero_carniceria'):]

        check_cache_validity()
        cache_key = f"{api_route}:{parsed.query}"
        if api_route not in ('/api/estado', '/api/ventas') and cache_key in CACHE:
            self.respond_json(CACHE[cache_key], cache='public, max-age=120')
            return

        try:
            with get_db() as db:
                # 1. ESTADO
                if api_route == '/api/estado':
                    total_reg = db.execute('SELECT COUNT(*) FROM ventas').fetchone()[0]
                    max_fecha = db.execute('SELECT MAX(fecha) FROM ventas').fetchone()[0] or ''
                    ult_carga = db.execute('SELECT MAX(actualizado) FROM cargas').fetchone()[0] or ''
                    
                    v_dia_neto = 0.0
                    v_dia_kg = 0.0
                    v_mes_neto = 0.0
                    v_mes_kg = 0.0
                    pct_dia_mes = 0.0
                    pct_dia_mes_kg = 0.0
                    mes_en_curso = max_fecha[:7] if max_fecha else ''
                    
                    if max_fecha:
                        r_dia = db.execute('SELECT COALESCE(SUM(neto), 0), COALESCE(SUM(kg_neto), 0) FROM ventas WHERE fecha = ?', [max_fecha]).fetchone()
                        v_dia_neto = float(r_dia[0] or 0)
                        v_dia_kg = float(r_dia[1] or 0)
                        
                        r_mes = db.execute('SELECT COALESCE(SUM(neto), 0), COALESCE(SUM(kg_neto), 0) FROM ventas WHERE substr(fecha, 1, 7) = ?', [mes_en_curso]).fetchone()
                        v_mes_neto = float(r_mes[0] or 0)
                        v_mes_kg = float(r_mes[1] or 0)
                        
                        pct_dia_mes = round((v_dia_neto / v_mes_neto) * 100, 2) if v_mes_neto else 0.0
                        pct_dia_mes_kg = round((v_dia_kg / v_mes_kg) * 100, 2) if v_mes_kg else 0.0

                    res = {
                        'registros': total_reg,
                        'ultima_venta': max_fecha,
                        'ultima_carga': ult_carga,
                        'ultimo_dia_fecha': max_fecha,
                        'ultimo_dia_neto': v_dia_neto,
                        'ultimo_dia_kg': v_dia_kg,
                        'mes_en_curso': mes_en_curso,
                        'mes_en_curso_neto': v_mes_neto,
                        'mes_en_curso_kg': v_mes_kg,
                        'pct_dia_mes': pct_dia_mes,
                        'pct_dia_mes_kg': pct_dia_mes_kg
                    }
                    self.respond_json(res)
                    return

                # 2. FILTROS DISPONIBLES
                if api_route == '/api/filtros':
                    w_sql, w_vals = build_filter_clause(params)
                    filtros = {
                        'tipos_venta': [r[0] for r in db.execute(f'SELECT DISTINCT tipo_venta FROM ventas {w_sql} AND tipo_venta != "" ORDER BY tipo_venta', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT tipo_venta FROM ventas WHERE tipo_venta != "" ORDER BY tipo_venta')],
                        'grupos': [r[0] for r in db.execute(f'SELECT DISTINCT grupo FROM ventas {w_sql} AND grupo != "" ORDER BY grupo', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT grupo FROM ventas WHERE grupo != "" ORDER BY grupo')],
                        'agrupas': [r[0] for r in db.execute(f'SELECT DISTINCT agrupa FROM ventas {w_sql} AND agrupa != "" ORDER BY agrupa', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT agrupa FROM ventas WHERE agrupa != "" ORDER BY agrupa')],
                        'aperturas': [r[0] for r in db.execute(f'SELECT DISTINCT expone FROM ventas {w_sql} AND expone != "" ORDER BY expone', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT expone FROM ventas WHERE expone != "" ORDER BY expone')],
                        'expones': [r[0] for r in db.execute(f'SELECT DISTINCT expone FROM ventas {w_sql} AND expone != "" ORDER BY expone', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT expone FROM ventas WHERE expone != "" ORDER BY expone')],
                        'tipos_comp': [r[0] for r in db.execute(f'SELECT DISTINCT tipo FROM ventas {w_sql} AND tipo != "" ORDER BY tipo', w_vals)] if w_sql else [r[0] for r in db.execute('SELECT DISTINCT tipo FROM ventas WHERE tipo != "" ORDER BY tipo')],
                        'rango_fechas': db.execute('SELECT MIN(fecha), MAX(fecha) FROM ventas').fetchone(),
                        'total_registros': db.execute('SELECT COUNT(*) FROM ventas').fetchone()[0]
                    }
                    self.respond_json(filtros, cache='public, max-age=1')
                    return

                # 3. LISTAS DE CLIENTES Y MATERIALES
                if api_route == '/api/opciones_clientes':
                    q = params.get('q', [''])[0].strip()
                    sql = 'SELECT DISTINCT cliente FROM ventas WHERE cliente != ""'
                    vals = []
                    if q:
                        sql += ' AND cliente LIKE ?'
                        vals.append(f'%{q}%')
                    sql += ' ORDER BY cliente'
                    rows = [r[0] for r in db.execute(sql, vals)]
                    self.respond_json({'clientes': rows})
                    return

                if api_route == '/api/opciones_materiales':
                    q = params.get('q', [''])[0].strip()
                    sql = 'SELECT DISTINCT codigo, producto FROM ventas WHERE codigo != ""'
                    vals = []
                    if q:
                        sql += ' AND (codigo LIKE ? OR producto LIKE ?)'
                        vals.extend([f'%{q}%', f'%{q}%'])
                    sql += ' ORDER BY producto'
                    rows = [{'codigo': r[0], 'producto': r[1]} for r in db.execute(sql, vals)]
                    self.respond_json({'materiales': rows})
                    return

                where_sql, vals = build_filter_clause(params)

                # 4. KPIS PRINCIPALES
                if api_route == '/api/kpis':
                    query = f'''
                        SELECT
                            COALESCE(SUM(neto), 0) as venta_neta,
                            COALESCE(SUM(kg_neto), 0) as kg_netos,
                            COUNT(DISTINCT cliente) as clientes_unicos,
                            COUNT(DISTINCT comprobante) as comprobantes_unicos,
                            COALESCE(SUM(CASE WHEN tipo IN ('NC', 'NCD', 'NCR') THEN neto ELSE 0 END), 0) as nc_neto,
                            COALESCE(SUM(CASE WHEN tipo IN ('NC', 'NCD', 'NCR') THEN kg_neto ELSE 0 END), 0) as nc_kg
                        FROM ventas {where_sql}
                    '''
                    row = db.execute(query, vals).fetchone()
                    venta_neta = float(row[0])
                    kg_netos = float(row[1])
                    precio_prom = (venta_neta / kg_netos) if kg_netos else 0.0

                    # Variación mensual: mes seleccionado (o último mes con datos) vs mes inmediatamente anterior
                    desde_p = params.get('desde', [''])[0].strip()
                    hasta_p = params.get('hasta', [''])[0].strip()
                    meses_p = [m.strip() for m in params.get('mes', []) if m.strip()]
                    fechas_p = [f.strip() for f in params.get('fecha', []) if f.strip()]

                    mes_objetivo = None
                    if meses_p:
                        mes_objetivo = meses_p[0][:7]
                    elif hasta_p and len(hasta_p) >= 7:
                        mes_objetivo = hasta_p[:7]
                    elif desde_p and len(desde_p) >= 7:
                        mes_objetivo = desde_p[:7]
                    elif fechas_p:
                        mes_objetivo = fechas_p[0][:7]

                    dim_where, dim_vals = build_filter_clause(params, include_date=False)

                    var_pct = None
                    mes_prev = None
                    total_obj = 0.0
                    total_prev = 0.0

                    if mes_objetivo:
                        try:
                            y, m = int(mes_objetivo[:4]), int(mes_objetivo[5:7])
                            mes_prev = f"{y-1:04d}-12" if m == 1 else f"{y:04d}-{m-1:02d}"
                        except Exception:
                            mes_prev = None

                        q_obj = f"SELECT COALESCE(SUM(neto), 0) FROM ventas " + (f"{dim_where} AND " if dim_where else "WHERE ") + "substr(fecha, 1, 7) = ?"
                        total_obj = float(db.execute(q_obj, dim_vals + [mes_objetivo]).fetchone()[0])

                        if mes_prev:
                            q_prev = f"SELECT COALESCE(SUM(neto), 0) FROM ventas " + (f"{dim_where} AND " if dim_where else "WHERE ") + "substr(fecha, 1, 7) = ?"
                            total_prev = float(db.execute(q_prev, dim_vals + [mes_prev]).fetchone()[0])

                        if total_prev > 0:
                            var_pct = round(((total_obj - total_prev) / total_prev) * 100, 1)
                        elif total_obj > 0 and total_prev == 0:
                            var_pct = 100.0
                    else:
                        meses_sql = f"SELECT substr(fecha, 1, 7) as m, SUM(neto) as total FROM ventas {dim_where} GROUP BY m ORDER BY m DESC LIMIT 2"
                        rows_m = db.execute(meses_sql, dim_vals).fetchall()
                        if rows_m:
                            mes_objetivo = rows_m[0][0]
                            total_obj = float(rows_m[0][1] or 0)
                            if len(rows_m) >= 2 and rows_m[1][1]:
                                mes_prev = rows_m[1][0]
                                total_prev = float(rows_m[1][1] or 0)
                                if total_prev:
                                    var_pct = round(((total_obj - total_prev) / abs(total_prev)) * 100, 1)

                    ticket_prom = round(venta_neta / row[3], 2) if row[3] else 0.0

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
                        'ultimo_mes': mes_objetivo,
                        'ultimo_mes_neto': round(total_obj, 2),
                        'mes_anterior': mes_prev,
                        'mes_anterior_neto': round(total_prev, 2),
                        'fixed_dia': round(float(fixed_dia), 2),
                        'fixed_mes': float(fixed_mes)
                    }

                    self.respond_cached(cache_key, kpis)
                    return

                # 5. EVOLUCION TEMPORAL (MENSUAL O DIARIA)
                if api_route == '/api/evolucion':
                    modo = params.get('modo', ['mes'])[0].strip()
                    grp_field = "fecha" if modo == 'dia' else "substr(fecha, 1, 7)"
                    query = f'''
                        SELECT {grp_field} as periodo,
                               ROUND(SUM(neto), 2) as venta_neta,
                               ROUND(SUM(kg_neto), 2) as kg_netos,
                               COUNT(DISTINCT comprobante) as comprobantes,
                               COUNT(DISTINCT cliente) as clientes
                        FROM ventas {where_sql}
                        GROUP BY periodo
                        ORDER BY periodo ASC
                    '''
                    rows = []
                    for r in db.execute(query, vals):
                        n = float(r[1] or 0)
                        k = float(r[2] or 0)
                        p = round(n / k, 2) if k else 0.0
                        rows.append({
                            'periodo': r[0],
                            'venta_neta': n,
                            'kg_netos': k,
                            'precio_promedio': p,
                            'comprobantes': r[3],
                            'clientes': r[4]
                        })
                    self.respond_cached(cache_key, {'evolucion': rows})
                    return

                # 6. RANKINGS (TOP PRODUCTOS, CLIENTES, GRUPOS)
                if api_route == '/api/ranking':
                    dim = params.get('dim', ['apertura'])[0].strip()
                    allowed_dims = {'apertura': 'expone', 'expone': 'expone', 'producto': 'producto', 'grupo': 'grupo',
                                    'agrupa': 'agrupa', 'cliente': 'cliente', 'tipo_venta': 'tipo_venta', 'comprobante': 'comprobante'}
                    col = allowed_dims.get(dim, 'expone')
                    limit = min(int(params.get('limit', [15])[0]), 100)

                    extra_clause = f"{col} IS NOT NULL AND {col} != ''"
                    full_where = f"{where_sql} AND {extra_clause}" if where_sql else f"WHERE {extra_clause}"

                    query = f'''
                        SELECT {col} as nombre,
                               ROUND(SUM(neto), 2) as venta_neta,
                               ROUND(SUM(kg_neto), 2) as kg_netos,
                               COUNT(DISTINCT comprobante) as comprobantes,
                               COUNT(DISTINCT cliente) as clientes
                        FROM ventas {full_where}
                        GROUP BY {col}
                        ORDER BY SUM(neto) DESC
                        LIMIT {limit}
                    '''
                    total_neto = db.execute(f"SELECT SUM(neto) FROM ventas {where_sql}", vals).fetchone()[0] or 1
                    total_kg = db.execute(f"SELECT SUM(kg_neto) FROM ventas {where_sql}", vals).fetchone()[0] or 1

                    items = []
                    for r in db.execute(query, vals):
                        n = float(r[1] or 0)
                        k = float(r[2] or 0)
                        items.append({
                            'nombre': r[0],
                            'venta_neta': n,
                            'kg_netos': k,
                            'precio_promedio': round(n / k, 2) if k else 0.0,
                            'comprobantes': r[3],
                            'clientes': r[4],
                            'share_neto': round((n / total_neto) * 100, 2) if total_neto else 0,
                            'share_kg': round((k / total_kg) * 100, 2) if total_kg else 0
                        })
                    self.respond_cached(cache_key, {'ranking': items, 'dimension': col})
                    return

                # 7. DRILLDOWN DE PRODUCTOS (JERARQUÍA COMPLETA)
                if api_route == '/api/drilldown':
                    query = f'''
                        SELECT grupo, agrupa, expone,
                               ROUND(SUM(neto), 2) as venta_neta,
                               ROUND(SUM(kg_neto), 2) as kg_netos,
                               COUNT(DISTINCT comprobante) as comprobantes
                        FROM ventas {where_sql}
                        GROUP BY grupo, agrupa, expone
                        ORDER BY grupo, agrupa, SUM(neto) DESC
                    '''
                    items = []
                    for r in db.execute(query, vals):
                        n = float(r[3] or 0)
                        k = float(r[4] or 0)
                        items.append({
                            'grupo': r[0] or '—',
                            'agrupa': r[1] or '—',
                            'expone': r[2] or '—',
                            'venta_neta': n,
                            'kg_netos': k,
                            'precio_promedio': round(n / k, 2) if k else 0.0,
                            'comprobantes': r[5]
                        })
                    self.respond_cached(cache_key, {'drilldown': items})
                    return

                # 8. DETALLE PAGINADO DE VENTAS
                if api_route == '/api/detalle':
                    page = max(int(params.get('page', [1])[0]), 1)
                    limit = min(max(int(params.get('limit', [50])[0]), 10), 500)
                    offset = (page - 1) * limit

                    sort_col = params.get('sort', ['fecha'])[0].strip()
                    allowed_sorts = {'fecha': 'fecha', 'comprobante': 'comprobante', 'cliente': 'cliente',
                                     'producto': 'producto', 'expone': 'expone', 'kg_neto': 'kg_neto',
                                     'neto': 'neto', 'precio': 'precio'}
                    sort_field = allowed_sorts.get(sort_col, 'fecha')
                    sort_dir = 'ASC' if params.get('dir', ['DESC'])[0].upper() == 'ASC' else 'DESC'

                    count_sql = f"SELECT COUNT(*) FROM ventas {where_sql}"
                    total_rows = db.execute(count_sql, vals).fetchone()[0]

                    query = f'''
                        SELECT fecha, tipo_venta, tipo, comprobante, cliente,
                               grupo, agrupa, expone, producto, kg_neto, neto, precio
                        FROM ventas {where_sql}
                        ORDER BY {sort_field} {sort_dir}
                        LIMIT {limit} OFFSET {offset}
                    '''
                    rows = []
                    for r in db.execute(query, vals):
                        rows.append({
                            'fecha': r[0],
                            'tipo_venta': r[1],
                            'tipo_comp': r[2],
                            'comprobante': r[3],
                            'cliente': r[4],
                            'grupo': r[5],
                            'agrupa': r[6],
                            'expone': r[7],
                            'producto': r[8],
                            'kg_neto': round(float(r[9] or 0), 2),
                            'neto': round(float(r[10] or 0), 2),
                            'precio': round(float(r[11] or 0), 2)
                        })

                    total_pages = (total_rows + limit - 1) // limit
                    self.respond_cached(cache_key, {
                        'data': rows,
                        'page': page,
                        'limit': limit,
                        'total_rows': total_rows,
                        'total_pages': total_pages
                    })
                    return

                # 9. CALIDAD DE DATOS Y AUDITORÍA DE DÍAS HÁBILES
                if api_route == '/api/calidad':
                    total_rows = db.execute('SELECT COUNT(*) FROM ventas').fetchone()[0]
                    na_rows = db.execute("SELECT COUNT(*) FROM ventas WHERE grupo='#N/A' OR agrupa='#N/A' OR expone='#N/A'").fetchone()[0]
                    nc_rows = db.execute("SELECT COUNT(*) FROM ventas WHERE tipo='NC'").fetchone()[0]
                    tipos_venta = [r[0] for r in db.execute('SELECT DISTINCT tipo_venta FROM ventas WHERE tipo_venta != ""')]

                    ejemplos_na = []
                    for r in db.execute("SELECT fecha, comprobante, cliente, producto, grupo, agrupa, expone, neto FROM ventas WHERE grupo='#N/A' OR agrupa='#N/A' OR expone='#N/A' LIMIT 50"):
                        ejemplos_na.append({
                            'fecha': r[0], 'comprobante': r[1], 'cliente': r[2], 'producto': r[3],
                            'grupo': r[4], 'agrupa': r[5], 'expone': r[6], 'neto': r[7]
                        })

                    # Feriados Nacionales Argentina 2026
                    FERIADOS_2026 = {
                        '2026-01-01': 'Año Nuevo',
                        '2026-02-16': 'Carnaval',
                        '2026-02-17': 'Carnaval',
                        '2026-03-24': 'Memoria por la Verdad',
                        '2026-04-02': 'Veteranos de Malvinas',
                        '2026-04-03': 'Viernes Santo',
                        '2026-05-01': 'Día del Trabajador',
                        '2026-05-25': 'Revolución de Mayo',
                        '2026-06-20': 'Gral. Belgrano',
                        '2026-07-09': 'Día de la Independencia',
                        '2026-08-17': 'Gral. San Martín',
                        '2026-10-12': 'Diversidad Cultural',
                        '2026-11-23': 'Soberanía Nacional',
                        '2026-12-08': 'Inmaculada Concepción',
                        '2026-12-25': 'Navidad'
                    }

                    rango = db.execute('SELECT MIN(fecha), MAX(fecha) FROM ventas').fetchone()
                    fechas_db = set(r[0] for r in db.execute('SELECT DISTINCT fecha FROM ventas').fetchall())
                    
                    dias_habiles_total = 0
                    dias_habiles_con_venta = 0
                    faltantes = []
                    domingos_con_datos = []
                    feriados_en_rango = []

                    dias_nombres = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo']

                    if rango and rango[0] and rango[1]:
                        try:
                            d_cur = dt.date.fromisoformat(rango[0])
                            d_max = dt.date.fromisoformat(rango[1])
                            while d_cur <= d_max:
                                iso = d_cur.isoformat()
                                w = d_cur.weekday() # 0=Lun .. 5=Sab, 6=Dom
                                is_dom = (w == 6)
                                is_fer = iso in FERIADOS_2026

                                if is_dom:
                                    if iso in fechas_db:
                                        domingos_con_datos.append(iso)
                                else:
                                    if is_fer:
                                        feriados_en_rango.append({'fecha': iso, 'dia': dias_nombres[w], 'feriado': FERIADOS_2026[iso]})
                                    else:
                                        dias_habiles_total += 1
                                        if iso in fechas_db:
                                            dias_habiles_con_venta += 1
                                        else:
                                            faltantes.append({'fecha': iso, 'dia': dias_nombres[w], 'motivo': 'Sin ventas registradas'})
                                d_cur += dt.timedelta(days=1)
                        except Exception as e:
                            pass

                    cobertura = round((dias_habiles_con_venta / dias_habiles_total) * 100, 1) if dias_habiles_total else 100.0

                    self.respond_cached(cache_key, {
                        'total_filas': total_rows,
                        'na_filas': na_rows,
                        'nc_filas': nc_rows,
                        'tipos_venta': tipos_venta,
                        'ejemplos_na': ejemplos_na,
                        'auditoria_fechas': {
                            'total_dias_db': len(fechas_db),
                            'dias_habiles_total': dias_habiles_total,
                            'dias_habiles_con_venta': dias_habiles_con_venta,
                            'cobertura_pct': cobertura,
                            'domingos_con_datos_count': len(domingos_con_datos),
                            'domingos_con_datos': domingos_con_datos,
                            'feriados_count': len(feriados_en_rango),
                            'feriados': feriados_en_rango,
                            'faltantes_count': len(faltantes),
                            'faltantes': faltantes,
                            'fecha_min': rango[0] if rango else '',
                            'fecha_max': rango[1] if rango else ''
                        }
                    })
                    return

                # 10. EXPORTACIÓN FILTRADA (EXCEL Y CSV)
                if api_route == '/api/exportar':
                    formato = params.get('formato', ['excel'])[0].lower().strip()
                    query = f'''
                        SELECT fecha, tipo_venta, tipo as tipo_comp, comprobante, cliente,
                               codigo, producto, grupo, agrupa, expone,
                               kg, precio, subtotal, neto, kg_neto
                        FROM ventas {where_sql}
                        ORDER BY fecha DESC, comprobante ASC, fila ASC
                    '''
                    rows = db.execute(query, vals).fetchall()
                    headers = [
                        'Fecha', 'Tipo Venta', 'Tipo Comprobante', 'Comprobante', 'Cliente',
                        'Código Material', 'Producto', 'Grupo', 'Agrupa', 'Apertura',
                        'Kg Brutos', 'Precio $/Kg', 'Subtotal', 'Neto Final ($)', 'Kg Netos'
                    ]
                    ts = dt.date.today().strftime('%Y-%m-%d')

                    if formato == 'csv':
                        buf = io.StringIO()
                        writer = csv.writer(buf, delimiter=';', lineterminator='\r\n')
                        writer.writerow(headers)
                        for r in rows:
                            writer.writerow([
                                r[0], r[1], r[2], r[3], r[4],
                                r[5], r[6], r[7], r[8], r[9],
                                str(r[10]).replace('.', ','),
                                str(r[11]).replace('.', ','),
                                str(r[12]).replace('.', ','),
                                str(r[13]).replace('.', ','),
                                str(r[14]).replace('.', ',')
                            ])
                        payload = ('\ufeff' + buf.getvalue()).encode('utf-8')
                        self.respond_file(payload, f"Ventas_Carniceria_Gorina_{ts}.csv", 'text/csv; charset=utf-8')
                        return

                    else: # formato == 'excel'
                        import openpyxl
                        from openpyxl.styles import Font, PatternFill, Alignment
                        from openpyxl.utils import get_column_letter

                        wb = openpyxl.Workbook()
                        ws = wb.active
                        ws.title = "Ventas Filtradas"

                        # Header Styling
                        header_fill = PatternFill(start_color="1E293B", end_color="1E293B", fill_type="solid")
                        header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")

                        ws.append(headers)
                        for col_idx in range(1, len(headers) + 1):
                            cell = ws.cell(row=1, column=col_idx)
                            cell.fill = header_fill
                            cell.font = header_font
                            cell.alignment = Alignment(horizontal="center", vertical="center")

                        ws.row_dimensions[1].height = 24

                        # Formatos numéricos rápidos
                        num_fmt_money = '$ #,##0.00'
                        num_fmt_kg = '#,##0.00'

                        # Agregar filas en lote
                        is_large = len(rows) > 5000
                        for row_idx, r in enumerate(rows, start=2):
                            ws.append(list(r))
                            if not is_large or row_idx <= 5000:
                                for c in (11, 12, 13, 14, 15):
                                    cell = ws.cell(row=row_idx, column=c)
                                    cell.number_format = num_fmt_money if c in (12, 13, 14) else num_fmt_kg

                        # Autoajustar ancho aproximado de columnas
                        col_widths = [12, 14, 16, 16, 26, 16, 28, 18, 18, 22, 12, 12, 14, 14, 12]
                        for i, w in enumerate(col_widths, start=1):
                            ws.column_dimensions[get_column_letter(i)].width = w

                        out = io.BytesIO()
                        wb.save(out)
                        out.seek(0)
                        payload = out.getvalue()
                        self.respond_file(payload, f"Ventas_Carniceria_Gorina_{ts}.xlsx", 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
                        return

                # 11. RETROCOMPATIBILIDAD CON /api/ventas
                if api_route == '/api/ventas':
                    rows = [r for r in db.execute('''SELECT fecha,codigo,producto,tipo,comprobante,cliente,
                        kg,precio,subtotal,grupo,agrupa,expone,condicion,neto,kg_neto,tipo_venta,donacion
                        FROM ventas ORDER BY fecha,comprobante,fila''')]
                    result = {'rows': rows, 'loaded': dt.datetime.now().isoformat(timespec='seconds')}
                    self.respond_json(result)
                    return

            self.send_error(404, 'Ruta de API no encontrada')
        except (Exception, OSError) as exc:
            self.send_error(500, str(exc))

if __name__ == '__main__':
    vm_name = socket.gethostname()
    puerto = int(CONFIG.get('puerto', 8765))
    print(f"Tablero analítico Gorina: http://{vm_name}:{puerto}/tablero_carniceria", flush=True)
    ThreadingHTTPServer((CONFIG.get('host', '0.0.0.0'), puerto), Handler).serve_forever()
