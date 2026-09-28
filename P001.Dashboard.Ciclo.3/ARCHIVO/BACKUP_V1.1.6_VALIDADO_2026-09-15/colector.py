#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
colector.py â€” Genera/actualiza datos.json para el dashboard Gorina (ciclo 3).

Etapa 1 (source="sheet"): lee el Google Sheets (export CSV, sin autenticaciÃ³n).
Etapa 2 (source="sql"):   lee las vistas SQL Server (pyodbc + ODBC 17/18 en la VM central).

Reglas:
  - UPSERT por dÃ­a (k = "YYYY-MM-DD"): inserta dÃ­as nuevos, actualiza los existentes,
    conserva los dÃ­as que ya estaban (histÃ³rico acumulado). Nunca borra historia.
  - "occ" se normaliza a PORCENTAJE (0-100): si llega <= 1 se multiplica por 100
    (la hoja TRV lo guarda como fracciÃ³n); "2,98%" se parsea a 2.98.
  - Escritura atÃ³mica: datos.json.tmp + rename; se deja copia previa en datos.json.prev.
  - Cada sistema se procesa por separado: si uno falla, los demÃ¡s siguen y se conserva
    su Ãºltimo dato bueno.

Uso:
  python colector.py            # ejecuciÃ³n manual (una corrida)
  python colector.py --test     # imprime conteos sin escribir datos.json
"""
import sys, os, re, json, time, datetime, logging, shutil, urllib.request

try:
    from webrh_reader import fetch_webrh_today
except ImportError:
    fetch_webrh_today = None

try:
    from colector_horario import run_hourly_collection
except ImportError:
    run_hourly_collection = None



BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')


def setup_log():
    logs_dir = os.path.join(BASE_DIR, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(levelname)-7s %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(os.path.join(logs_dir, 'colector.log'), encoding='utf-8'),
        ],
    )


# ----------------------------------------------------------------------------
# Parsing genÃ©rico (misma intuiciÃ³n que el dashboard)
# ----------------------------------------------------------------------------
def parse_csv(text):
    """Parser CSV con comillas, igual que el del dashboard."""
    rows, row, cur = [], [], ''
    inq = False
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if inq:
            if c == '"':
                if i + 1 < n and text[i + 1] == '"':
                    cur += '"'; i += 2; continue
                inq = False
            else:
                cur += c
        elif c == '"':
            inq = True
        elif c == ',':
            row.append(cur); cur = ''
        elif c in '\r\n':
            if c == '\r' and i + 1 < n and text[i + 1] == '\n':
                i += 1
            row.append(cur); rows.append(row); row = []; cur = ''
        else:
            cur += c
        i += 1
    if cur or row:
        row.append(cur); rows.append(row)
    return rows


def parse_num(v):
    """NÃºmero es-AR: "1.234,56", "2,98%", "0.1028", "-2,868", Decimal, int, float."""
    if v is None:
        return None
    s = str(v).strip().replace(' ', '').replace('%', '')
    if not s or s in ('-', '.'):
        return None
    neg = s.startswith('-')
    if neg:
        s = s[1:]
    if ',' in s and '.' in s:
        if s.rfind('.') < s.rfind(','):          # "1.234,56" â†’ miles con punto, coma decimal
            s = s.replace('.', '').replace(',', '.')
        else:                                     # "1,234.56" â†’ coma de miles
            s = s.replace(',', '')
    elif ',' in s:
        s = s.replace(',', '.')
    try:
        n = float(s)
    except ValueError:
        return None
    return -n if neg else n


def parse_pct(v):
    """OcupaciÃ³n a % (0-100). Si el valor es fracciÃ³n (<=1) lo convierte a porcentaje."""
    n = parse_num(v)
    if n is None:
        return None
    return n * 100 if n <= 1 else n


def parse_date(v):
    """dd/mm/yyyy, dd-mm-yyyy o ISO yyyy-mm-dd â†’ datetime.date."""
    if v is None:
        return None
    s = str(v).strip()
    m = re.match(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})$', s)
    if m:
        d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if y < 100:
            y += 2000
    else:
        m = re.match(r'^(\d{4})-(\d{1,2})-(\d{1,2})$', s)
        if not m:
            return None
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    try:
        return datetime.date(y, mo, d)
    except ValueError:
        return None


def day_key(d):
    return '%04d-%02d-%02d' % (d.year, d.month, d.day)


# ----------------------------------------------------------------------------
# Fuente: Google Sheets (CSV export)
# ----------------------------------------------------------------------------
def fetch_csv(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read().decode('utf-8-sig')


def fetch_sheet_system(cfg, sys_key):
    L = cfg['sheet']['layout'][sys_key]
    url = ('https://docs.google.com/spreadsheets/d/%s/export?format=csv&gid=%s&_t=%d'
           % (cfg['sheet']['id'], L['gid'], int(time.time() * 1000)))
    rows = parse_csv(fetch_csv(url))[L['skip']:]
    res = []
    maxc = max(L['cInn'], L['cOut'], L['cPct'])
    for r in rows:
        if len(r) <= maxc:
            continue
        d = parse_date(r[0])
        if d is None:
            continue
        inn, out_v, occ = parse_num(r[L['cInn']]), parse_num(r[L['cOut']]), parse_pct(r[L['cPct']])
        if inn is None and out_v is None and occ is None:
            continue
        res.append({'k': day_key(d), 'inn': inn, 'out': out_v, 'occ': occ})
    res.sort(key=lambda x: x['k'])
    return res


# ----------------------------------------------------------------------------
# Fuente: SQL Server (Etapa 2 â€” vistas definidas por el DBA)
# ----------------------------------------------------------------------------
def fetch_mysql_system(cfg, sys_key):
    try:
        import pymysql
    except ImportError:
        raise RuntimeError('Falta pymysql. InstalÃ¡ antes:  pip install pymysql')
    v = cfg.get('mysql', {}).get('views', {}).get(sys_key)
    if not v:
        # fallback a sql.views para compatibilidad si config usa sql para mysql
        v = cfg.get('sql', {}).get('views', {}).get(sys_key)
    if not v:
        raise RuntimeError('config.json: falta la vista mysql para %s' % sys_key)
    srv_cfg = cfg.get('mysql', {}).get('servers', {}).get(v['server'])
    if not srv_cfg:
        srv_cfg = cfg.get('sql', {}).get('servers', {}).get(v['server'])
    if not srv_cfg:
        raise RuntimeError('config.json: falta conn para servidor mysql %s' % v['server'])
    # srv_cfg puede ser dict {host,port,database,user,password} o string DSN (no usado para mysql)
    if isinstance(srv_cfg, dict):
        host = srv_cfg.get('host', '192.168.0.162')
        port = int(srv_cfg.get('port', 3306))
        db = srv_cfg.get('database', srv_cfg.get('db', 'p003148'))
        user = srv_cfg.get('user', srv_cfg.get('uid', 'tablero_ro'))
        pwd = srv_cfg.get('password', srv_cfg.get('pwd', ''))
        cn = pymysql.connect(host=host, port=port, user=user, password=pwd, database=db, charset='utf8mb4', connect_timeout=20)
    else:
        # si es string, intentar parsear tipo MySQL (no implementado, requiere dict)
        raise RuntimeError('mysql.servers.%s debe ser dict {host, database, user, password}' % v['server'])
    cur = cn.cursor()
    if 'query' in v:
        cur.execute(v['query'])
    else:
        cur.execute('SELECT fecha, ingresos, salidas, ocupacion FROM %s' % v['view'])
    res = []
    for row in cur.fetchall():
        d = parse_date(row[0])
        if d is None:
            continue
        inn, out_v, occ = parse_num(row[1]), parse_num(row[2]), parse_pct(row[3])
        if inn is None and out_v is None and occ is None:
            continue
        res.append({'k': day_key(d), 'inn': inn, 'out': out_v, 'occ': occ})
    cur.close()
    cn.close()
    res.sort(key=lambda x: x['k'])
    return res


def fetch_sql_system(cfg, sys_key):
    try:
        import pyodbc
    except ImportError:
        raise RuntimeError('Falta pyodbc. InstalÃ¡ antes:  pip install pyodbc  (y ODBC Driver 17/18)')
    v = cfg.get('sql', {}).get('views', {}).get(sys_key)
    if not v:
        raise RuntimeError('config.json: falta la vista para %s' % sys_key)
    srv = cfg.get('sql', {}).get('servers', {}).get(v['server'])
    if not srv:
        raise RuntimeError('config.json: falta connstr para el servidor %s' % v['server'])
    cn = pyodbc.connect(srv, timeout=20)
    cur = cn.cursor()
    cur.execute('SELECT fecha, ingresos, salidas, ocupacion FROM %s' % v['view'])
    res = []
    for row in cur.fetchall():
        d = parse_date(row[0])
        if d is None:
            continue
        inn, out_v, occ = parse_num(row[1]), parse_num(row[2]), parse_pct(row[3])
        if inn is None and out_v is None and occ is None:
            continue
        res.append({'k': day_key(d), 'inn': inn, 'out': out_v, 'occ': occ})
    cur.close()
    cn.close()
    res.sort(key=lambda x: x['k'])
    return res


# ----------------------------------------------------------------------------
# Fuente: CTTO 2.1 API REST (Transelevadores 1 y 2 - Almacén Congelado)
# ----------------------------------------------------------------------------
def http_get_json(url, alt_url=None, timeout=10):
    urls = [url]
    if alt_url and alt_url != url:
        urls.append(alt_url)
    last_err = None
    for u in urls:
        try:
            req = urllib.request.Request(u, headers={'User-Agent': 'GorinaDashboardColector/1.0'})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode('utf-8'))
        except Exception as e:
            last_err = e
    raise last_err


def fetch_ctto_system(cfg, sys_key):
    ctto_cfg = cfg.get('ctto', {})
    base = ctto_cfg.get('base_url', 'http://fglp39v2:5000').rstrip('/')
    alt = ctto_cfg.get('alt_url', 'http://192.168.0.164:5000').rstrip('/') if ctto_cfg.get('alt_url') else None
    start_str = ctto_cfg.get('start_date', '2026-09-02')
    start_d = parse_date(start_str) or datetime.date(2026, 9, 2)
    end_d = datetime.date.today()
    timeout = int(ctto_cfg.get('timeout', 10))

    records = []
    curr = start_d
    one_day = datetime.timedelta(days=1)
    while curr <= end_d:
        k = day_key(curr)
        ep = f"/stacker-1/api/operations/metrics/summary?fromDate={k}&toDate={k}"
        u1 = base + ep
        u2 = (alt + ep) if alt else None
        try:
            data = http_get_json(u1, alt_url=u2, timeout=timeout)
            res_cat = data.get('data', {}).get('resultsByCategory', {})
            inn = res_cat.get('ingresos', {}).get('count', 0)
            out_v = res_cat.get('salidas', {}).get('count', 0)

            # Fin de semana sin operaciones: omitir para mantener consistencia operativa
            if inn == 0 and out_v == 0 and curr.weekday() >= 5:
                curr += one_day
                continue

            records.append({
                'k': k,
                'inn': float(inn),
                'out': float(out_v),
                'occ': None
            })
        except Exception as e:
            logging.warning('CTTO error en fecha %s: %s', k, e)
        curr += one_day

    records.sort(key=lambda x: x['k'])
    return records


# ----------------------------------------------------------------------------
# Merge (upsert) + escritura
# ----------------------------------------------------------------------------
# Capacidades máximas nominales de cada sistema (cajas / palets)
CAPACITIES = {
    'trv': 25200,
    'trv2': 25200,
    'crane': 3960,
}


def fill_missing_occupancy(sys_key, records):
    """
    Si la base de datos devuelve ocupación NULL (la vista SQL no acumula stock),
    calcula la ocupación acumulativa diaria basada en la capacidad del sistema:
    Stock_hoy = Stock_ayer + Ingresos_hoy - Salidas_hoy
    Ocupacion_hoy = (Stock_hoy / Capacidad) * 100
    """
    cap = CAPACITIES.get(sys_key)
    if not cap or not records:
        return records

    records = sorted(records, key=lambda r: r['k'])
    curr_stock = None
    for r in records:
        if r.get('occ') is not None:
            # Sincroniza el stock con el valor oficial o provisto
            curr_stock = (float(r['occ']) / 100.0) * cap
        elif curr_stock is not None:
            inn = float(r.get('inn') or 0.0)
            out = float(r.get('out') or 0.0)
            curr_stock = curr_stock + inn - out
            curr_stock = max(0.0, min(float(cap), curr_stock))
            r['occ'] = round((curr_stock / cap) * 100.0, 2)
    return records


def upsert(old_list, new_list):
    # Los registros hasta el 01/09/2026 inclusive son fijos y oficiales
    fijos = {x['k']: dict(x) for x in (old_list or []) if x['k'] <= '2026-09-01'}
    m = dict(fijos)
    # A partir del 02/09/2026, los datos provienen directamente de la fuente fresca (BD)
    for x in (new_list or []):
        k = x['k']
        if k <= '2026-09-01':
            continue
        m[k] = dict(x)
    return [m[k] for k in sorted(m)]


def write_atomic(out_path, payload):
    out_path = os.path.abspath(out_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    if os.path.exists(out_path):
        shutil.copyfile(out_path, out_path + '.prev')
    tmp = out_path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)
    os.replace(tmp, out_path)

    # Generar tambien datos.js para soportar apertura local file:// sin bloqueo CORS
    js_path = os.path.splitext(out_path)[0] + '.js'
    tmp_js = js_path + '.tmp'
    with open(tmp_js, 'w', encoding='utf-8') as f:
        f.write('window.LOCAL_DATOS = ')
        json.dump(payload, f, ensure_ascii=False, indent=1)
        f.write(';\n')
    os.replace(tmp_js, js_path)


# ----------------------------------------------------------------------------
def main():
    setup_log()
    args = [a for a in sys.argv[1:]]
    test_only = '--test' in args
    with open(CONFIG_PATH, encoding='utf-8-sig') as f:
        cfg = json.load(f)

    out_path = cfg.get('out_path', '../tablero_v4/datos.json')
    if not os.path.isabs(out_path):
        out_path = os.path.normpath(os.path.join(BASE_DIR, out_path))

    payload = {'trv': [], 'trv2': [], 'crane': []}
    if os.path.exists(out_path):
        try:
            with open(out_path, encoding='utf-8-sig') as f:
                payload = json.load(f)
            payload.setdefault('trv', []); payload.setdefault('trv2', []); payload.setdefault('crane', [])
        except Exception as e:
            logging.error('datos.json ilegible (%s), se regenera desde cero', e)

    # Regla: datos fijos hasta el 01/09/2026 inclusive; a partir del 02/09/2026 se toman de la BD
    fijo_path = os.path.join(BASE_DIR, 'historico_fijo_hasta_2026-09-01.json')
    if os.path.exists(fijo_path):
        try:
            with open(fijo_path, encoding='utf-8-sig') as f:
                base_fija = json.load(f)
            for s in ['trv', 'trv2', 'crane']:
                fijos_s = [x for x in base_fija.get(s, []) if x['k'] <= '2026-09-01']
                existentes_post = [x for x in payload.get(s, []) if x['k'] > '2026-09-01']
                payload[s] = fijos_s + existentes_post
        except Exception as e:
            logging.error('Error cargando historico fijo: %s', e)

    source = cfg.get('source', 'sheet')
    hybrid = cfg.get('source_hybrid', {})
    ok = 0
    for s in ['trv', 'trv2', 'crane']:
        try:
            src = hybrid.get(s, source) if isinstance(hybrid, dict) else source
            if src == 'sql':
                data = fetch_sql_system(cfg, s)
            elif src == 'mysql':
                data = fetch_mysql_system(cfg, s)
            elif src == 'ctto':
                data = fetch_ctto_system(cfg, s)
            else:
                data = fetch_sheet_system(cfg, s)
            merged = upsert(payload.get(s), data)
            merged = fill_missing_occupancy(s, merged)
            payload[s] = merged
            logging.info('%s: %d leÃ­dos Â· total %d dÃ­as', s, len(data), len(merged))
            ok += 1
        except Exception as e:
            logging.error('%s: ERROR â€” %s (se conserva el Ãºltimo dato bueno)', s, e)

    logging.info('Sistemas OK: %d/3 · fuente: %s (hybrid=%s)', ok, source, hybrid if hybrid else '-')

    # ------------------------------------------------------------------------
    # Tiempo Real: Siemens WinCC WebRH para TRV1 y TRV2 (día en curso)
    # ------------------------------------------------------------------------
    webrh_data = None
    webrh_cfg = cfg.get('webrh')

    if webrh_cfg and fetch_webrh_today:
        try:
            logging.info('Consultando Siemens WebRH en tiempo real (Turno 1 + Turno 2)...')
            webrh_data = fetch_webrh_today(webrh_cfg)
            if webrh_data and webrh_data.get('k'):
                k_today = webrh_data['k']
                for s in ['trv', 'trv2']:
                    if s in webrh_data:
                        s_data = webrh_data[s]
                        inn_v = float(s_data.get('inn') or 0.0)
                        out_v = float(s_data.get('out') or 0.0)

                        # Si no se registran movimientos en el día (inn == 0 y out == 0), no debe contarse
                        if inn_v == 0 and out_v == 0:
                            payload[s] = [item for item in payload.get(s, []) if item['k'] != k_today]
                            logging.info('WebRH %s (%s): sin movimientos (inn=0, out=0), no se cuenta.', s, k_today)
                            continue

                        matched = False
                        for item in payload.get(s, []):
                            if item['k'] == k_today:
                                item['inn'] = inn_v
                                item['out'] = out_v
                                item['occ'] = None  # forzar recálculo
                                matched = True
                                break
                        if not matched:
                            payload.setdefault(s, []).append({
                                'k': k_today,
                                'inn': inn_v,
                                'out': out_v,
                                'occ': None
                            })
                        payload[s] = fill_missing_occupancy(s, payload[s])
                        logging.info('WebRH aplicado en %s (%s): In=%.0f, Out=%.0f', s, k_today, inn_v, out_v)
        except Exception as e:
            logging.warning('WebRH: no se pudo actualizar en tiempo real (%s). Se conserva el dato BD existente.', e)

    # Filtrar cualquier día que no registre movimientos (inn == 0 y out == 0)
    for s in ['trv', 'trv2', 'crane']:
        payload[s] = [r for r in payload.get(s, []) if (r.get('inn') or 0) > 0 or (r.get('out') or 0) > 0]

    if test_only:
        total = sum(len(payload[s]) for s in payload)
        print('TEST OK Â· dÃ­as en datos.json: %s (total %d)' % (', '.join('%s=%d' % (s, len(payload[s])) for s in payload), total))
        return 0
    if ok == 0:
        logging.error('NingÃºn sistema pudo actualizarse: NO se toca datos.json')
        return 1
    write_atomic(out_path, payload)
    total = sum(len(payload[s]) for s in payload)
    logging.info('Escribo %s (%d dÃ­as en total)', out_path, total)

    # ------------------------------------------------------------------------
    # Actualización Horaria (SQLite + datos_horarios.json)
    # ------------------------------------------------------------------------
    if run_hourly_collection:
        try:
            run_hourly_collection(cfg, webrh_data)
        except Exception as e:
            logging.warning('Recolección horaria error: %s', e)

    return 0



if __name__ == '__main__':
    sys.exit(main())




