#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
colector.py — Genera/actualiza datos.json para el dashboard Gorina (ciclo 3).

Etapa 1 (source="sheet"): lee el Google Sheets (export CSV, sin autenticación).
Etapa 2 (source="sql"):   lee las vistas SQL Server (pyodbc + ODBC 17/18 en la VM central).

Reglas:
  - UPSERT por día (k = "YYYY-MM-DD"): inserta días nuevos, actualiza los existentes,
    conserva los días que ya estaban (histórico acumulado). Nunca borra historia.
  - "occ" se normaliza a PORCENTAJE (0-100): si llega <= 1 se multiplica por 100
    (la hoja TRV lo guarda como fracción); "2,98%" se parsea a 2.98.
  - Escritura atómica: datos.json.tmp + rename; se deja copia previa en datos.json.prev.
  - Cada sistema se procesa por separado: si uno falla, los demás siguen y se conserva
    su último dato bueno.

Uso:
  python colector.py            # ejecución manual (una corrida)
  python colector.py --test     # imprime conteos sin escribir datos.json
"""
import sys, os, re, json, time, datetime, logging, shutil, urllib.request

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
# Parsing genérico (misma intuición que el dashboard)
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
    """Número es-AR: "1.234,56", "2,98%", "0.1028", "-2,868", Decimal, int, float."""
    if v is None:
        return None
    s = str(v).strip().replace(' ', '').replace('%', '')
    if not s or s in ('-', '.'):
        return None
    neg = s.startswith('-')
    if neg:
        s = s[1:]
    if ',' in s and '.' in s:
        if s.rfind('.') < s.rfind(','):          # "1.234,56" → miles con punto, coma decimal
            s = s.replace('.', '').replace(',', '.')
        else:                                     # "1,234.56" → coma de miles
            s = s.replace(',', '')
    elif ',' in s:
        s = s.replace(',', '.')
    try:
        n = float(s)
    except ValueError:
        return None
    return -n if neg else n


def parse_pct(v):
    """Ocupación a % (0-100). Si el valor es fracción (<=1) lo convierte a porcentaje."""
    n = parse_num(v)
    if n is None:
        return None
    return n * 100 if n <= 1 else n


def parse_date(v):
    """dd/mm/yyyy, dd-mm-yyyy o ISO yyyy-mm-dd → datetime.date."""
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
# Fuente: SQL Server (Etapa 2 — vistas definidas por el DBA)
# ----------------------------------------------------------------------------
def fetch_mysql_system(cfg, sys_key):
    try:
        import pymysql
    except ImportError:
        raise RuntimeError('Falta pymysql. Instalá antes:  pip install pymysql')
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
    # view ya debe existir en MySQL: ej p003148.vw_tablero_trv1
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
        raise RuntimeError('Falta pyodbc. Instalá antes:  pip install pyodbc  (y ODBC Driver 17/18)')
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
# Merge (upsert) + escritura
# ----------------------------------------------------------------------------
def upsert(old_list, new_list):
    m = {x['k']: x for x in (old_list or [])}
    for x in new_list:
        m[x['k']] = x                      # el dato fresco gana
    return [m[k] for k in sorted(m)]       # orden cronológico


def write_atomic(out_path, payload):
    out_path = os.path.abspath(out_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    if os.path.exists(out_path):
        shutil.copyfile(out_path, out_path + '.prev')
    tmp = out_path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)
    os.replace(tmp, out_path)


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
            else:
                data = fetch_sheet_system(cfg, s)
            merged = upsert(payload.get(s), data)
            payload[s] = merged
            logging.info('%s: %d leídos · total %d días', s, len(data), len(merged))
            ok += 1
        except Exception as e:
            logging.error('%s: ERROR — %s (se conserva el último dato bueno)', s, e)

    logging.info('Sistemas OK: %d/3 · fuente: %s (hybrid=%s)', ok, source, hybrid if hybrid else '-')
    if test_only:
        total = sum(len(payload[s]) for s in payload)
        print('TEST OK · días en datos.json: %s (total %d)' % (', '.join('%s=%d' % (s, len(payload[s])) for s in payload), total))
        return 0
    if ok == 0:
        logging.error('Ningún sistema pudo actualizarse: NO se toca datos.json')
        return 1
    write_atomic(out_path, payload)
    total = sum(len(payload[s]) for s in payload)
    logging.info('Escribo %s (%d días en total)', out_path, total)
    return 0


if __name__ == '__main__':
    sys.exit(main())