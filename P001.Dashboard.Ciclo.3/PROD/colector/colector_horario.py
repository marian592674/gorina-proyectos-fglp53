#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
colector_horario.py — Módulo de recolección y almacenamiento horario para Dashboard Ciclo 3.

Funcionalidad:
1. Almacena en MySQL local (db_gorina_dashboard) métricas hora a hora por sistema:
   (sistema, fecha_operativa, turno, hora, inn, out, occ).
2. Regla de Turnos y Cruce de Medianoche:
   - Turno 1: 05:00 a 17:59 (fecha_operativa = día en curso).
   - Turno 2: 18:00 a 23:59 (fecha_operativa = día en curso).
   - Turno 2 (Noche): 00:00 a 04:59 (fecha_operativa = día anterior).
3. Recolección de Almacén Congelado (CTTO API):
   - Consulta el endpoint nativo de métricas horarias de CTTO.
4. Recolección de TRV1 / TRV2:
   - Ingesta en tiempo real desde MySQL registros_cam calibrado contra total oficial del día.
5. Sincronización Automática de Histórico (Auto-Backfill):
   - Verifica automáticamente que los días pasados (últimos 7 días) tengan sus horas completas.
6. Exporta `datos_horarios.json` y `datos_horarios.js` para el frontend con enteros garantizados.
"""
import os, sys, json, sqlite3, datetime, logging, urllib.request, re

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, 'historico_horario.db')
SNAPSHOT_PATH = os.path.join(BASE_DIR, 'logs', 'hourly_snapshot_state.json')

logger = logging.getLogger('colector_horario')


import db as db_module

def get_db():
    return db_module.get_db()

def init_db():
    db_module.init_db()


def registrar_telemetria_scada(sistema, dt_str, inn_val, out_val):
    if inn_val is None and out_val is None:
        return
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('''
            INSERT INTO telemetria_scada (fecha_hora, sistema, inn, out)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(fecha_hora, sistema) DO UPDATE SET
                inn = excluded.inn,
                out = excluded.out
        ''', (dt_str, sistema, float(inn_val or 0), float(out_val or 0)))
        conn.commit()
        conn.close()
    except Exception as e:
        logger.warning("Error registrando telemetría SCADA: %s", e)


def poblar_telemetria_desde_log(today_str):
    """
    Si la tabla telemetria_scada tiene pocos registros de hoy, sincroniza desde colector.log
    para garantizar la serie temporal completa de nuestra BD local.
    """
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM telemetria_scada WHERE fecha_hora LIKE ?", (today_str + '%',))
        count = cur.fetchone()[0]
        if count >= 12:
            conn.close()
            return

        log_file = os.path.join(BASE_DIR, 'logs', 'colector.log')
        if not os.path.exists(log_file):
            conn.close()
            return

        with open(log_file, encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        pattern = re.compile(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*WebRH.*TRV1 \(inn=([\d\.]+), out=([\d\.]+)\)')
        inserted = 0
        for l in lines:
            if today_str in l and 'WebRH' in l and 'inn=' in l:
                m = pattern.search(l)
                if m:
                    dt_str = m.group(1)
                    inn_v = float(m.group(2))
                    out_v = float(m.group(3))
                    cur.execute('''
                        INSERT OR IGNORE INTO telemetria_scada (fecha_hora, sistema, inn, out)
                        VALUES (?, 'trv', ?, ?)
                    ''', (dt_str, inn_v, out_v))
                    inserted += 1
        conn.commit()
        conn.close()
        if inserted > 0:
            logger.info("Telemetría SCADA local poblada con %d lecturas de hoy desde el colector.", inserted)
    except Exception as e:
        logger.warning("Error poblando telemetría SCADA: %s", e)


def calcular_deltas_desde_telemetria(sistema, today_str, now_hour):
    """
    Calcula los movimientos hora por hora directamente desde la tabla local telemetria_scada.
    100% independiente de cualquier base externa o archivo de texto.
    """
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('''
            SELECT fecha_hora, inn, out
            FROM telemetria_scada
            WHERE sistema = ? AND fecha_hora >= ? AND fecha_hora <= ?
            ORDER BY fecha_hora ASC
        ''', (sistema, today_str + ' 00:00:00', today_str + ' 23:59:59'))
        rows = cur.fetchall()
        conn.close()

        if not rows:
            return {}

        hourly_cum = {}
        for r in rows:
            dt_str = r['fecha_hora']
            h = int(dt_str[11:13])
            if h > now_hour:
                continue
            hourly_cum[h] = (float(r['inn']), float(r['out']))

        all_hours = sorted(hourly_cum.keys())
        if not all_hours:
            return {}
        min_h = min(all_hours)
        for h in range(min_h, now_hour + 1):
            if h not in hourly_cum and h - 1 in hourly_cum:
                hourly_cum[h] = hourly_cum[h - 1]

        deltas = {}
        prev_in, prev_out = 0.0, 0.0
        for h in sorted(hourly_cum.keys()):
            cin, cout = hourly_cum[h]
            din = max(0, int(round(cin - prev_in)))
            dout = max(0, int(round(cout - prev_out)))
            deltas[h] = {'inn': din, 'out': dout, 'cum_in': cin, 'cum_out': cout}
            prev_in, prev_out = cin, cout

        return deltas
    except Exception as e:
        logger.warning("Error calculando deltas desde telemetría SCADA: %s", e)
        return {}


def get_shift_and_op_date(dt=None):
    """
    Determina la fecha operativa y el turno en base a la hora:
    - 05:00 a 17:59 -> Turno 1, fecha_operativa = dt.date()
    - 18:00 a 23:59 -> Turno 2, fecha_operativa = dt.date()
    - 00:00 a 04:59 -> Turno 2 (noche), fecha_operativa = dt.date() - 1 día
    """
    if dt is None:
        dt = datetime.datetime.now()
    
    h = dt.hour
    if 5 <= h < 18:
        shift = 1
        op_date = dt.date()
    elif 18 <= h <= 23:
        shift = 2
        op_date = dt.date()
    else:  # 00:00 a 04:59
        shift = 2
        op_date = dt.date() - datetime.timedelta(days=1)
    
    hour_label = f"{h:02d}:00"
    return op_date.isoformat(), shift, hour_label


def upsert_hourly_record(sistema, fecha_operativa, turno, hora, inn, out, occ=None):
    now_iso = datetime.datetime.now().isoformat()
    conn = get_db()
    cur = conn.cursor()
    inn_int = int(round(float(inn or 0.0)))
    out_int = int(round(float(out or 0.0)))
    cur.execute('''
        INSERT INTO movimientos_horarios (sistema, fecha_operativa, turno, hora, inn, out, occ, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(sistema, fecha_operativa, hora) DO UPDATE SET
            turno = excluded.turno,
            inn = excluded.inn,
            out = excluded.out,
            occ = coalesce(excluded.occ, movimientos_horarios.occ),
            updated_at = excluded.updated_at
    ''', (sistema, fecha_operativa, turno, hora, inn_int, out_int, occ, now_iso))
    conn.commit()
    conn.close()


# ----------------------------------------------------------------------------
# Captura de Almacén Congelado (CTTO API REST con paginación)
# ----------------------------------------------------------------------------
def fetch_ctto_day_operations(cfg, date_str):
    ctto_cfg = cfg.get('ctto', {})
    base = ctto_cfg.get('base_url', 'http://fglp39v2:5000').rstrip('/')
    alt = ctto_cfg.get('alt_url', 'http://192.168.0.164:5000').rstrip('/') if ctto_cfg.get('alt_url') else None
    timeout = int(ctto_cfg.get('timeout', 8))

    all_ops = []
    page = 1
    urls_to_try = [base]
    if alt and alt != base:
        urls_to_try.append(alt)

    active_base = None
    for b in urls_to_try:
        test_url = f"{b}/stacker-1/api/operations?fromDate={date_str}&toDate={date_str}&limit=100&page=1"
        try:
            req = urllib.request.Request(test_url, headers={'User-Agent': 'GorinaHourlyCollector/1.0'})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                if r.status == 200:
                    active_base = b
                    break
        except Exception:
            continue

    if not active_base:
        return {}

    while True:
        u = f"{active_base}/stacker-1/api/operations?fromDate={date_str}&toDate={date_str}&limit=100&page={page}"
        try:
            req = urllib.request.Request(u, headers={'User-Agent': 'GorinaHourlyCollector/1.0'})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                d = json.loads(r.read().decode('utf-8'))
                ops = d.get('data', [])
                all_ops.extend(ops)
                if page >= d.get('totalPages', 1) or not ops:
                    break
                page += 1
        except Exception as e:
            logger.warning("Error paginando CTTO fecha %s pag %d: %s", date_str, page, e)
            break

    by_hour = {}
    for op in all_ops:
        created = op.get('createdAt', '')
        op_type = op.get('operation', '')
        if len(created) >= 13:
            h = created[11:13] + ':00'
            by_hour.setdefault(h, {'inn': 0, 'out': 0})
            if op_type == 'pallet_stored':
                by_hour[h]['inn'] += 1
            elif op_type in ('pallet_exited', 'manually_exited'):
                by_hour[h]['out'] += 1

    return by_hour


# ----------------------------------------------------------------------------
# Sincronización Automática de Histórico (Auto-Backfill)
# ----------------------------------------------------------------------------
def sync_recent_history(cfg, days_back=7):
    """
    Verifica que los últimos days_back días tengan registros en SQLite / MySQL.
    Si falta algún día hábil, lo reconstruye automáticamente desde MySQL y CTTO.
    """
    today = datetime.date.today()
    conn = get_db()
    cur = conn.cursor()

    missing_trv = []
    missing_crane = []
    for i in range(1, days_back + 1):
        past_d = today - datetime.timedelta(days=i)
        if past_d.weekday() >= 5:
            continue
        d_str = past_d.isoformat()
        cur.execute("SELECT COUNT(*) FROM movimientos_horarios WHERE fecha_operativa = ? AND sistema = 'trv' AND turno = 1", (d_str,))
        if cur.fetchone()[0] == 0:
            missing_trv.append(d_str)
        cur.execute("SELECT COUNT(*) FROM movimientos_horarios WHERE fecha_operativa = ? AND sistema = 'crane' AND turno = 1", (d_str,))
        if cur.fetchone()[0] == 0:
            missing_crane.append(d_str)
    conn.close()

    # Reconstruir TRV faltantes
    if missing_trv:
        logger.info("Detectados días pasados sin registros de TRV: %s. Sincronizando...", missing_trv)
        try:
            import pymysql
            srv = cfg.get('mysql', {}).get('servers', {}).get('TRV', {})
            cn = pymysql.connect(
                host=srv.get('host', '192.168.0.162'),
                port=int(srv.get('port', 3306)),
                user=srv.get('user', 'TABLERO_RO'),
                password=srv.get('password', 'GORINA2026!'),
                database=srv.get('database', 'p003148'),
                connect_timeout=10
            )
            m_cur = cn.cursor()
            for d_str in missing_trv:
                m_cur.execute("SELECT ing_inf_t1 + ing_sup_t1, sal_t1 FROM produccion_turnos WHERE fecha = %s AND turno = 1", (d_str,))
                r = m_cur.fetchone()
                ofic_in = float(r[0]) if r and r[0] else 0.0
                ofic_out = float(r[1]) if r and r[1] else 0.0

                m_cur.execute("""
                    SELECT HOUR(fecha_hora) as h,
                           SUM(CASE WHEN camara = 'SCF_AT1_06' THEN 1 ELSE 0 END) as c_in,
                           SUM(CASE WHEN camara = 'SCF_SE5_03' THEN 1 ELSE 0 END) as c_out
                    FROM registros_cam
                    WHERE fecha_hora >= %s AND fecha_hora <= %s
                    GROUP BY HOUR(fecha_hora) ORDER BY h
                """, (d_str + ' 00:00:00', d_str + ' 23:59:59'))
                rows = m_cur.fetchall()
                raw_in = float(sum(row[1] for row in rows))
                raw_out = float(sum(row[2] for row in rows))

                scale_in = (ofic_in / raw_in) if raw_in > 0 and ofic_in > 0 else 1.0
                scale_out = (ofic_out / raw_out) if raw_out > 0 and ofic_out > 0 else 1.0

                calibrated = []
                for h, cin, cout in rows:
                    h_lbl = f"{h:02d}:00"
                    fin_in = int(round(float(cin) * scale_in))
                    fin_out = int(round(float(cout) * scale_out))
                    calibrated.append({'h': h_lbl, 'inn': fin_in, 'out': fin_out})

                if ofic_in > 0 and calibrated:
                    diff_in = int(ofic_in) - sum(x['inn'] for x in calibrated)
                    if diff_in != 0:
                        calibrated[-1]['inn'] += diff_in
                if ofic_out > 0 and calibrated:
                    diff_out = int(ofic_out) - sum(x['out'] for x in calibrated)
                    if diff_out != 0:
                        calibrated[-1]['out'] += diff_out

                for item in calibrated:
                    upsert_hourly_record('trv', d_str, 1, item['h'], item['inn'], item['out'])
            m_cur.close()
            cn.close()
            logger.info("TRV auto-backfill completado para: %s", missing_trv)
        except Exception as e:
            logger.warning("Error en auto-backfill TRV: %s", e)

    # Reconstruir Crane faltantes
    if missing_crane:
        logger.info("Detectados días pasados sin registros de Crane: %s. Sincronizando...", missing_crane)
        try:
            for d_str in missing_crane:
                day_ops = fetch_ctto_day_operations(cfg, d_str)
                for h_str, h_vals in day_ops.items():
                    if h_vals['inn'] > 0 or h_vals['out'] > 0:
                        h_int = int(h_str.split(':')[0])
                        shift = 1 if 5 <= h_int < 18 else 2
                        upsert_hourly_record('crane', d_str, shift, h_str, h_vals['inn'], h_vals['out'])
            logger.info("Crane auto-backfill completado para: %s", missing_crane)
        except Exception as e:
            logger.warning("Error en auto-backfill Crane: %s", e)


# ----------------------------------------------------------------------------
# Contingencia: Deltas de Producción Horaria desde Siemens WebRH
# ----------------------------------------------------------------------------
def get_webrh_hourly_deltas(today_str, now_hour):
    """
    Calcula los deltas de producción hora por hora para hoy a partir de los
    registros periódicos de WebRH en colector.log.
    Actúa como contingencia automática cuando registros_cam en MySQL sufre interrupción o retraso.
    """
    log_file = os.path.join(BASE_DIR, 'logs', 'colector.log')
    if not os.path.exists(log_file):
        return {}
    try:
        with open(log_file, encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        pattern = re.compile(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*WebRH.*TRV1 \(inn=([\d\.]+), out=([\d\.]+)\)')
        today_points = []
        for l in lines:
            if today_str in l and 'WebRH' in l and 'inn=' in l:
                m = pattern.search(l)
                if m:
                    dt = datetime.datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S')
                    today_points.append((dt, float(m.group(2)), float(m.group(3))))
        if not today_points:
            return {}
        hourly_cum = {}
        for h in range(5, now_hour + 1):
            pts = [p for p in today_points if p[0].hour == h]
            if pts:
                hourly_cum[h] = pts[-1]
            elif h - 1 in hourly_cum:
                hourly_cum[h] = hourly_cum[h - 1]
        deltas = {}
        prev_in, prev_out = 0.0, 0.0
        for h in sorted(hourly_cum.keys()):
            dt, c_in, c_out = hourly_cum[h]
            d_in = max(0, int(round(c_in - prev_in)))
            d_out = max(0, int(round(c_out - prev_out)))
            deltas[h] = {'inn': d_in, 'out': d_out, 'cum_in': c_in, 'cum_out': c_out}
            prev_in, prev_out = c_in, c_out
        return deltas
    except Exception as e:
        logger.warning("Error calculando deltas horarios de WebRH: %s", e)
        return {}


# ----------------------------------------------------------------------------
# Captura de TRV1 / TRV2 en Tiempo Real para Hoy
# ----------------------------------------------------------------------------
def fetch_trv_mysql_hourly_today(cfg, webrh_data=None):
    try:
        import pymysql
    except ImportError:
        logger.warning("Falta pymysql para capturar TRV de MySQL")
        return 0

    srv = cfg.get('mysql', {}).get('servers', {}).get('TRV', {})
    host = srv.get('host', '192.168.0.162')
    port = int(srv.get('port', 3306))
    user = srv.get('user', 'TABLERO_RO')
    pwd = srv.get('password', 'GORINA2026!')
    db = srv.get('database', 'p003148')

    now = datetime.datetime.now()
    today_str = now.date().isoformat()
    today_cal = now.date()

    target_inn = None
    target_out = None
    if webrh_data and 'trv' in webrh_data:
        w_trv = webrh_data['trv']
        if (w_trv.get('inn') or 0) > 0:
            target_inn = float(w_trv['inn'])
        if (w_trv.get('out') or 0) > 0:
            target_out = float(w_trv['out'])

    if target_inn is None or target_out is None:
        try:
            dashboard_dir = os.path.dirname(cfg.get('out_path', ''))
            djson_path = os.path.join(dashboard_dir, 'datos.json')
            if os.path.exists(djson_path):
                with open(djson_path, encoding='utf-8-sig') as _f:
                    _dj = json.load(_f)
                for _r in _dj.get('trv', []):
                    if _r.get('k') == today_str:
                        if target_inn is None and _r.get('inn') is not None:
                            target_inn = float(_r['inn'])
                        if target_out is None and _r.get('out') is not None:
                            target_out = float(_r['out'])
        except Exception:
            pass

    count = 0
    try:
        cn = pymysql.connect(host=host, port=port, user=user, password=pwd, database=db, connect_timeout=10)
        cur = cn.cursor()

        cur.execute("""
            SELECT HOUR(fecha_hora) as h,
                   SUM(CASE WHEN camara = 'SCF_AT1_06' THEN 1 ELSE 0 END) as in_t1,
                   SUM(CASE WHEN camara = 'SCF_SE5_03' THEN 1 ELSE 0 END) as out_t1,
                   SUM(CASE WHEN camara = 'SCF_AT2_06' THEN 1 ELSE 0 END) as in_t2,
                   SUM(CASE WHEN camara = 'SCF_SE6_03' THEN 1 ELSE 0 END) as out_t2
            FROM registros_cam
            WHERE fecha_hora >= %s AND fecha_hora <= %s
            GROUP BY HOUR(fecha_hora)
            ORDER BY h
        """, (today_str + ' 00:00:00', today_str + ' 23:59:59'))
        rows = cur.fetchall()

        valid_rows = []
        raw_inn_tot = 0.0
        raw_out_tot = 0.0
        for h_int, in_t1, out_t1, in_t2, out_t2 in rows:
            if h_int > now.hour:
                continue
            in_v, out_v = float(in_t1 or 0), float(out_t1 or 0)
            raw_inn_tot += in_v
            raw_out_tot += out_v
            valid_rows.append((h_int, in_v, out_v, float(in_t2 or 0), float(out_t2 or 0)))

        cam_hours = [r[0] for r in valid_rows]
        min_cam_h = min(cam_hours) if cam_hours else 0
        max_cam_h = max(cam_hours) if cam_hours else 0
        # Si faltan horas intermedias entre el inicio y la hora actual, hay un hueco en registros_cam
        has_gaps = any(h not in cam_hours for h in range(min_cam_h, now.hour)) if (cam_hours and now.hour > min_cam_h) else False
        use_webrh_fallback = (max_cam_h < now.hour - 1 and now.hour >= 7) or (len(valid_rows) == 0) or has_gaps

        calibrated = []
        if use_webrh_fallback:
            logger.info("Detectada interrupción/huecos en MySQL registros_cam (horas presentes: %s vs actual: %02d:00). Activando contingencia horaria con Siemens WebRH...", cam_hours, now.hour)
            webrh_deltas = calcular_deltas_desde_telemetria('trv', today_str, now.hour)
            if not webrh_deltas:
                webrh_deltas = get_webrh_hourly_deltas(today_str, now.hour)
            if webrh_deltas:
                for h_int, vals in sorted(webrh_deltas.items()):
                    dummy_dt = datetime.datetime.combine(today_cal, datetime.time(int(h_int), 0))
                    o_date, s_num, h_lbl = get_shift_and_op_date(dummy_dt)
                    calibrated.append({
                        'date': o_date,
                        'shift': s_num,
                        'h': h_lbl,
                        'inn': vals['inn'],
                        'out': vals['out'],
                        'in_t2': 0,
                        'out_t2': 0
                    })
        else:
            scale_inn = (target_inn / raw_inn_tot) if (target_inn is not None and raw_inn_tot > 0) else 1.0
            scale_out = (target_out / raw_out_tot) if (target_out is not None and raw_out_tot > 0) else 1.0
            for h_int, in_t1_v, out_t1_v, in_t2_v, out_t2_v in valid_rows:
                dummy_dt = datetime.datetime.combine(today_cal, datetime.time(int(h_int), 0))
                o_date, s_num, h_lbl = get_shift_and_op_date(dummy_dt)
                final_in = int(round(in_t1_v * scale_inn)) if in_t1_v > 0 else 0
                final_out = int(round(out_t1_v * scale_out)) if out_t1_v > 0 else 0
                calibrated.append({'date': o_date, 'shift': s_num, 'h': h_lbl, 'inn': final_in, 'out': final_out, 'in_t2': in_t2_v, 'out_t2': out_t2_v})

        if target_inn is not None and calibrated:
            diff_in = int(round(target_inn)) - sum(x['inn'] for x in calibrated)
            if diff_in != 0:
                calibrated[-1]['inn'] += diff_in
        if target_out is not None and calibrated:
            diff_out = int(round(target_out)) - sum(x['out'] for x in calibrated)
            if diff_out != 0:
                calibrated[-1]['out'] += diff_out

        # Limpiar registros previos de hoy en MySQL para TRV antes de reinsertar calibrados
        if calibrated:
            conn_wipe = get_db()
            c_wipe = conn_wipe.cursor()
            c_wipe.execute("DELETE FROM movimientos_horarios WHERE sistema = 'trv' AND fecha_operativa = ?", (today_str,))
            conn_wipe.commit()
            conn_wipe.close()

        for item in calibrated:
            if item['inn'] > 0 or item['out'] > 0:
                upsert_hourly_record('trv', item['date'], item['shift'], item['h'], item['inn'], item['out'])
                count += 1
            if item['in_t2'] > 0 or item['out_t2'] > 0:
                upsert_hourly_record('trv2', item['date'], item['shift'], item['h'], int(round(item['in_t2'])), int(round(item['out_t2'])))

        cur.close()
        cn.close()

        # Limpiar horas espurias o registros anómalos de hoy
        op_date, shift, hour_label = get_shift_and_op_date(now)
        conn = get_db()
        c = conn.cursor()
        c.execute('''
            DELETE FROM movimientos_horarios
            WHERE sistema IN ('trv', 'trv2') AND fecha_operativa = ? AND hora > ?
        ''', (op_date, hour_label))
        c.execute('''
            DELETE FROM movimientos_horarios
            WHERE sistema = 'trv' AND fecha_operativa = ? AND hora = '17:00' AND inn > 5000
        ''', (op_date,))
        # Limpiar registro espurio a las 05:00 si no tuvo entradas ni salidas
        c.execute('''
            DELETE FROM movimientos_horarios
            WHERE sistema = 'trv' AND fecha_operativa = ? AND hora = '05:00' AND inn = 0 AND `out` = 0
        ''', (op_date,))
        conn.commit()
        conn.close()

        logger.info("TRV MySQL directo: %d registros horarios capturados/actualizados.", count)
        return count
    except Exception as e:
        logger.warning("Error capturando TRV directo de MySQL: %s", e)
        return 0


# ----------------------------------------------------------------------------
# Exportación de JSON para el Dashboard
# ----------------------------------------------------------------------------
def export_hourly_json(out_json_path):
    conn = get_db()
    cur = conn.cursor()
    cur.execute('''
        SELECT sistema, fecha_operativa, turno, hora, inn, `out`, occ
        FROM movimientos_horarios
        WHERE (inn > 0 OR `out` > 0)
        ORDER BY fecha_operativa ASC, hora ASC
    ''')
    rows = cur.fetchall()
    conn.close()

    payload = {}
    for r in rows:
        f_op = r['fecha_operativa']
        sis = r['sistema']
        if f_op not in payload:
            payload[f_op] = {'trv': [], 'trv2': [], 'crane': []}
        if sis not in payload[f_op]:
            payload[f_op][sis] = []

        payload[f_op][sis].append({
            'h': r['hora'],
            'inn': int(round(r['inn'])) if r['inn'] is not None else 0,
            'out': int(round(r['out'])) if r['out'] is not None else 0,
            'occ': r['occ'],
            'turno': r['turno']
        })

    # Guardrail de Integridad Estricta: Garantizar que la suma de horas de hoy coincida con datos.json
    try:
        dashboard_dir = os.path.dirname(os.path.abspath(out_json_path))
        djson_file = os.path.join(dashboard_dir, 'datos.json')
        if os.path.exists(djson_file):
            with open(djson_file, encoding='utf-8-sig') as f:
                dj = json.load(f)
            today_str = datetime.date.today().isoformat()
            for s_key in ['trv', 'crane']:
                recs = dj.get(s_key, [])
                if not recs:
                    continue
                last_rec = next((r for r in recs if r.get('k') == today_str), None)
                if not last_rec:
                    continue
                k_date = last_rec.get('k')
                tgt_in = last_rec.get('inn')
                tgt_out = last_rec.get('out')
                if k_date in payload and s_key in payload[k_date] and payload[k_date][s_key]:
                    h_list = payload[k_date][s_key]
                    if tgt_in is not None and tgt_in > 0:
                        s_in = sum(x['inn'] for x in h_list)
                        diff_in = int(round(tgt_in)) - s_in
                        if diff_in != 0:
                            h_list[-1]['inn'] += diff_in
                            logger.info("[GUARDRAIL] Ajustado residuo IN %s (%s): diff=%+d para cuadre exacto con datos.json", s_key, k_date, diff_in)
                    if tgt_out is not None and tgt_out > 0:
                        s_out = sum(x['out'] for x in h_list)
                        diff_out = int(round(tgt_out)) - s_out
                        if diff_out != 0:
                            h_list[-1]['out'] += diff_out
                            logger.info("[GUARDRAIL] Ajustado residuo OUT %s (%s): diff=%+d para cuadre exacto con datos.json", s_key, k_date, diff_out)
    except Exception as e:
        logger.warning("Error aplicando guardrail de integridad en export_hourly_json: %s", e)

    out_dir = os.path.dirname(os.path.abspath(out_json_path))
    os.makedirs(out_dir, exist_ok=True)
    tmp_json = out_json_path + '.tmp'
    with open(tmp_json, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)
    os.replace(tmp_json, out_json_path)

    js_path = os.path.splitext(out_json_path)[0] + '.js'
    tmp_js = js_path + '.tmp'
    with open(tmp_js, 'w', encoding='utf-8') as f:
        f.write('window.LOCAL_DATOS_HORARIOS = ')
        json.dump(payload, f, ensure_ascii=False, indent=1)
        f.write(';\n')
    os.replace(tmp_js, js_path)

    logger.info("Exportado %s (%d fechas operativas)", out_json_path, len(payload))
    return payload


# ----------------------------------------------------------------------------
# Proceso periódico de captura (llamado por colector.py)
# ----------------------------------------------------------------------------
def run_hourly_collection(cfg, webrh_data=None):
    init_db()
    now = datetime.datetime.now()
    op_date, shift, hour_label = get_shift_and_op_date(now)

    # 0. Registrar telemetría propia en MySQL y asegurar serie histórica de hoy
    now_iso = now.strftime('%Y-%m-%d %H:%M:%S')
    poblar_telemetria_desde_log(op_date)
    if webrh_data and 'trv' in webrh_data:
        w_in = webrh_data['trv'].get('inn')
        w_out = webrh_data['trv'].get('out')
        registrar_telemetria_scada('trv', now_iso, w_in, w_out)

    # 1. Sincronizar automáticamente días pasados si faltaran
    try:
        sync_recent_history(cfg, days_back=7)
    except Exception as e:
        logger.warning("Error en sync_recent_history: %s", e)

    # 2. CTTO: Consultar operaciones del día calendario en curso
    try:
        today_cal = now.date()
        days_to_query = [today_cal]
        if now.hour < 5:
            days_to_query.append(today_cal - datetime.timedelta(days=1))

        for q_date in days_to_query:
            d_str = q_date.isoformat()
            day_ops = fetch_ctto_day_operations(cfg, d_str)
            for h_str, h_vals in day_ops.items():
                if h_vals['inn'] > 0 or h_vals['out'] > 0:
                    h_int = int(h_str.split(':')[0])
                    if q_date == today_cal and h_int > now.hour:
                        continue
                    dummy_dt = datetime.datetime.combine(q_date, datetime.time(h_int, 0))
                    o_date, s_num, h_lbl = get_shift_and_op_date(dummy_dt)
                    upsert_hourly_record('crane', o_date, s_num, h_lbl, h_vals['inn'], h_vals['out'])

        conn = get_db()
        cur = conn.cursor()
        cur.execute('''
            DELETE FROM movimientos_horarios
            WHERE sistema = 'crane' AND fecha_operativa = ? AND hora > ?
        ''', (op_date, hour_label))
        conn.commit()
        conn.close()
    except Exception as e:
        logger.warning("Error capturando hora actual CTTO: %s", e)

    # 3. TRV1 / TRV2: Ingesta directa en tiempo real desde MySQL registros_cam
    try:
        fetch_trv_mysql_hourly_today(cfg, webrh_data)
    except Exception as e:
        logger.warning("Error capturando TRV horario de MySQL: %s", e)

    # 4. Exportar JSON actualizado
    dashboard_dir = os.path.dirname(cfg.get('out_path', ''))
    out_json = os.path.join(dashboard_dir, 'datos_horarios.json')
    export_hourly_json(out_json)


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)-7s %(message)s')
    init_db()
    with open(os.path.join(BASE_DIR, 'config.json'), encoding='utf-8-sig') as f:
        cfg = json.load(f)

    run_hourly_collection(cfg)
