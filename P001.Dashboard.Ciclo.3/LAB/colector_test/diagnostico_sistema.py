#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
diagnostico_sistema.py — Diagnostico integral de Dashboards, Stock Almacen e Informes.
"""
import os, sys, json, glob, datetime, urllib.request

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROD_DIR = r'D:\PROYECTOS\P001.Dashboard.Ciclo.3\PROD'
LAB_DIR = r'D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB'
STOCK_DIR = r'D:\PROYECTOS\P002.Stock.Almacen.Congelado\A PROBAR\STOCK'

try:
    import calendario_informes
except ImportError:
    sys.path.append(BASE_DIR)
    import calendario_informes

def check_url(url, timeout=3):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        res = urllib.request.urlopen(req, timeout=timeout)
        code = res.getcode()
        return (code == 200), f"HTTP {code}"
    except Exception as e:
        return False, str(e)

def get_file_info(path):
    if not os.path.exists(path):
        return None
    mtime = datetime.datetime.fromtimestamp(os.path.getmtime(path))
    size = os.path.getsize(path)
    return {'mtime': mtime, 'size': size}

def get_datos_status(path):
    info = get_file_info(path)
    if not info:
        return None
    try:
        with open(path, encoding='utf-8-sig') as f:
            d = json.load(f)
        trv_last = d.get('trv', [])[-1] if d.get('trv') else None
        crane_last = d.get('crane', [])[-1] if d.get('crane') else None
        return {
            'mtime': info['mtime'],
            'trv': trv_last,
            'crane': crane_last
        }
    except Exception as e:
        return {'mtime': info['mtime'], 'error': str(e)}

def get_latest_cierre():
    files = sorted(glob.glob(os.path.join(BASE_DIR, 'logs', 'cierre_enviado_*.json')))
    if not files:
        return None
    try:
        with open(files[-1], encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return None

def get_latest_semanal():
    files = sorted(glob.glob(os.path.join(BASE_DIR, 'logs', 'informe_semanal_enviado_*.json')))
    if files:
        try:
            with open(files[-1], encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            pass
    # Buscar en envio_informe.log
    log_path = os.path.join(BASE_DIR, 'logs', 'envio_informe.log')
    if os.path.exists(log_path):
        try:
            lines = [l.strip() for l in open(log_path, encoding='utf-8', errors='ignore') if 'Informe Semanal Ciclo 3' in l and 'Mail enviado con exito' in l]
            if lines:
                return {'raw_log': lines[-1]}
        except Exception:
            pass
    return None

def get_latest_mensual():
    files = sorted(glob.glob(os.path.join(BASE_DIR, 'logs', 'informe_mensual_enviado_*.json')))
    if files:
        try:
            with open(files[-1], encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            pass
    log_path = os.path.join(BASE_DIR, 'logs', 'envio_informe.log')
    if os.path.exists(log_path):
        try:
            lines = [l.strip() for l in open(log_path, encoding='utf-8', errors='ignore') if 'Informe Mensual Ciclo 3' in l and 'Mail enviado con exito' in l]
            if lines:
                return {'raw_log': lines[-1]}
        except Exception:
            pass
    return None

def get_latest_stock_csv():
    files = sorted(glob.glob(os.path.join(STOCK_DIR, 'lista_cajas_*.csv')))
    if not files:
        return None
    last_f = files[-1]
    info = get_file_info(last_f)
    return {'filename': os.path.basename(last_f), 'mtime': info['mtime'], 'size': info['size']}

def get_scheduled_tasks():
    res = {}
    try:
        import win32com.client
        s = win32com.client.Dispatch('Schedule.Service')
        s.Connect()
        f = s.GetFolder('\\')
        for t in f.GetTasks(0):
            if 'Gorina' in t.Name:
                state_str = {0:'Unknown', 1:'Disabled', 2:'Queued', 3:'Ready', 4:'Running'}.get(t.State, str(t.State))
                res[t.Name] = {
                    'state': state_str,
                    'enabled': t.Enabled,
                    'last_run': str(t.LastRunTime)[:19] if t.LastRunTime else 'Nunca',
                    'last_result': t.LastTaskResult,
                    'next_run': str(t.NextRunTime)[:19] if t.NextRunTime else 'Ninguna'
                }
    except Exception as e:
        res['error'] = str(e)
    return res

def print_diagnostic():
    now = datetime.datetime.now()
    sep = "=" * 80
    print(sep)
    print("       FRIGORIFICO GORINA — CONTROL DE OPERACIONES CICLO 3")
    print("                ESTADO Y DIAGNOSTICO DEL SISTEMA")
    print(sep)
    print(f"Fecha y Hora actual: {now.strftime('%d/%m/%Y %H:%M:%S')}")
    print()

    # 1. SERVICIOS Y PAGINAS
    print("[1] ESTADO DE SERVICIOS Y PAGINAS WEB:")
    u_red_ok, u_red_msg = check_url('http://localhost/tablero.ciclo3/dashboard_operaciones.html')
    u_lab_ok, u_lab_msg = check_url('http://localhost:8080/dashboard_operaciones.html')
    u_stock_ok, u_stock_msg = check_url('http://localhost:8090/')
    u_gorinapick_ok, u_gorinapick_msg = check_url('http://localhost:5000/api/ping')
    u_prod_ok, u_prod_msg = check_url('http://localhost/dashboard_operaciones.html')

    print(f"  * Acceso Red (tablero.ciclo3)  : [{'OK' if u_red_ok else 'FALLA'}] {u_red_msg} -> http://fglp53/tablero.ciclo3/dashboard_operaciones.html")
    print(f"  * LAB Dashboard  (Puerto 8080) : [{'OK' if u_lab_ok else 'FALLA'}] {u_lab_msg} -> http://localhost:8080/dashboard_operaciones.html")
    print(f"  * Stock Almacen  (Puerto 8090) : [{'OK' if u_stock_ok else 'FALLA'}] {u_stock_msg} -> http://fglp53:8090")
    print(f"  * GorinaPick API (Puerto 5000) : [{'OK' if u_gorinapick_ok else 'FALLA'}] {u_gorinapick_msg} -> http://localhost:5000/api/ping")
    print(f"  * PROD Dashboard (Archivado)   : [{'OK' if u_prod_ok else 'FALLA'}] {u_prod_msg} -> http://localhost/dashboard_operaciones.html")
    print()

    # 2. ACTUALIZACION DE DATOS
    print("[2] ACTUALIZACION DE DATOS (datos.json y Stock Almacen):")
    prod_datos = get_datos_status(os.path.join(PROD_DIR, 'dashboard', 'datos.json'))
    if prod_datos:
        diff_min = int((now - prod_datos['mtime']).total_seconds() / 60)
        status_tag = "AL DIA" if diff_min <= 10 else f"DESACTUALIZADO ({diff_min} min)"
        print(f"  * PROD (datos.json):")
        print(f"      - Modificado      : {prod_datos['mtime'].strftime('%d/%m/%Y %H:%M:%S')} (hace {diff_min} min) [{status_tag}]")
        if prod_datos.get('trv'):
            t = prod_datos['trv']
            print(f"      - Ultimo TRV1     : {t.get('k')} (IN: {int(t.get('inn',0))}, OUT: {int(t.get('out',0))}, Ocupacion: {t.get('occ',0)}%)")
        if prod_datos.get('crane'):
            c = prod_datos['crane']
            print(f"      - Ultimo Almacen  : {c.get('k')} (IN: {int(c.get('inn',0))}, OUT: {int(c.get('out',0))}, Ocupacion: {c.get('occ',0)}%)")
    else:
        print("  * PROD (datos.json) : NO ENCONTRADO")

    lab_datos = get_datos_status(os.path.join(LAB_DIR, 'dashboard_test', 'datos.json'))
    if lab_datos:
        diff_min = int((now - lab_datos['mtime']).total_seconds() / 60)
        status_tag = "AL DIA" if diff_min <= 10 else f"DESACTUALIZADO ({diff_min} min)"
        print(f"  * LAB (datos.json - Colector Hibrido TRV MySQL / Crane CTTO / WebRH):")
        print(f"      - Modificado      : {lab_datos['mtime'].strftime('%d/%m/%Y %H:%M:%S')} (hace {diff_min} min) [{status_tag}]")
        if lab_datos.get('trv'):
            t = lab_datos['trv']
            print(f"      - Ultimo TRV1     : {t.get('k')} (IN: {int(t.get('inn',0))}, OUT: {int(t.get('out',0))}, Ocupacion: {t.get('occ',0)}%)")
        if lab_datos.get('crane'):
            c = lab_datos['crane']
            print(f"      - Ultimo Almacen  : {c.get('k')} (IN: {int(c.get('inn',0))}, OUT: {int(c.get('out',0))}, Ocupacion: {c.get('occ',0)}%)")
    else:
        print("  * LAB (datos.json) : NO ENCONTRADO")

    stock_csv = get_latest_stock_csv()
    if stock_csv:
        diff_min = int((now - stock_csv['mtime']).total_seconds() / 60)
        status_tag = "AL DIA" if diff_min <= 45 else f"DESACTUALIZADO ({diff_min} min)"
        print(f"  * Stock Almacen (Descargas automaticas cada 30 min):")
        print(f"      - Ultimo CSV      : {stock_csv['filename']}")
        print(f"      - Modificado      : {stock_csv['mtime'].strftime('%d/%m/%Y %H:%M:%S')} (hace {diff_min} min) [{status_tag}]")
    else:
        print("  * Stock Almacen (CSV): NO ENCONTRADO")
    print()

    # 3. ULTIMOS ENVIOS DE CORREO
    print("[3] ULTIMOS ENVIOS DE INFORMES Y REPORTES (AUTOMATICOS):")
    cierre = get_latest_cierre()
    if cierre:
        print("  * Correo Diario de Cierre de Operaciones:")
        print(f"      - Fecha y Hora    : {cierre.get('hora_envio', cierre.get('fecha'))}")
        print(f"      - Asunto          : {cierre.get('asunto')}")
        print(f"      - Destinatarios   : {', '.join(cierre.get('destinatarios', []))}")
        print(f"      - Adjunto Excel   : {os.path.basename(cierre.get('excel', ''))}")
    else:
        print("  * Correo Diario de Cierre de Operaciones: Sin registros")

    semanal = get_latest_semanal()
    if semanal:
        print("  * Informe Semanal (PDF completo):")
        if 'hora_envio' in semanal:
            print(f"      - Fecha y Hora    : {semanal.get('hora_envio')}")
            print(f"      - Asunto          : {semanal.get('asunto')}")
            print(f"      - Destinatarios   : {', '.join(semanal.get('destinatarios', []))}")
            print(f"      - Adjunto PDF     : {os.path.basename(semanal.get('pdf', ''))}")
        else:
            print(f"      - Ultimo envio log: {semanal.get('raw_log')}")
    else:
        print("  * Informe Semanal: Sin registros")

    mensual = get_latest_mensual()
    if mensual:
        print("  * Informe Mensual (PDF completo):")
        if 'hora_envio' in mensual:
            print(f"      - Fecha y Hora    : {mensual.get('hora_envio')}")
            print(f"      - Periodo         : {mensual.get('periodo')}")
            print(f"      - Asunto          : {mensual.get('asunto')}")
            print(f"      - Destinatarios   : {', '.join(mensual.get('destinatarios', []))}")
        else:
            print(f"      - Ultimo envio log: {mensual.get('raw_log')}")
    else:
        print("  * Informe Mensual: Sin registros recientes")
    print()

    # 4. TAREAS PROGRAMADAS
    print("[4] TAREAS PROGRAMADAS DE WINDOWS:")
    tasks = get_scheduled_tasks()
    for name in ['Gorina LAB - Colector datos', 'Gorina LAB - Monitor Alertas Servicios', 'Gorina - GorinaPick API 24-7', 'Gorina - Stock Almacen 24-7', 'Gorina - Stock Almacen Descarga Automatica', 'Gorina - Colector datos']:
        t = tasks.get(name)
        if t:
            tag = f"[{t['state']}]"
            if name == 'Gorina - Colector datos':
                tag += " (Archivado)"
            print(f"  * {name:<42}: {tag:<18} Ultima: {t['last_run']} | Prox: {t['next_run']}")
        else:
            print(f"  * {name:<42}: [No encontrada]")
    print()

    # 5. CALENDARIO Y DISPARO
    print("[5] EVALUACION DE DISPARO DE INFORMES POR CALENDARIO:")
    disp = calendario_informes.evaluar_disparo_informes(now.date(), BASE_DIR)
    print(f"  * Dia actual: {disp['dia_semana']} ({disp['fecha']}) | Habil: {disp['es_habil']} | Feriado: {disp['es_feriado']}")
    if disp['corresponde_semanal']:
        print("  * Informe Semanal: CORRESPONDE DISPARO HOY AL CIERRE DE OPERACIONES.")
    else:
        print("  * Informe Semanal: No corresponde hoy (corresponde el ultimo dia habil de la semana).")
    if disp['corresponde_mensual']:
        print("  * Informe Mensual: CORRESPONDE DISPARO HOY AL CIERRE DE OPERACIONES.")
    else:
        print("  * Informe Mensual: No corresponde hoy (corresponde el ultimo dia habil del mes).")

    manana = now.date() + datetime.timedelta(days=1)
    disp_m = calendario_informes.evaluar_disparo_informes(manana, BASE_DIR)
    print(f"  * Proxima jornada ({disp_m['dia_semana']} {disp_m['fecha']}):")
    print(f"      - Semanal: {'SI (se enviara al cierre de operaciones de manana)' if disp_m['corresponde_semanal'] else 'No'}")
    print(f"      - Mensual: {'SI (se enviara al cierre de operaciones de manana)' if disp_m['corresponde_mensual'] else 'No'}")

    print(sep)

if __name__ == '__main__':
    print_diagnostic()
