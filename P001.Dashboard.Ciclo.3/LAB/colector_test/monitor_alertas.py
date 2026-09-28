#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
monitor_alertas.py — Vigilancia y Alertas por Correo ante Caídas de Servicios Ciclo 3.

Monitorea continuamente:
1. Servicios HTTP IIS (Puerto 8080 y Directorio Virtual /tablero.ciclo3) y Stock Almacén (8090).
2. Tareas Programadas de Windows críticas (Colector LAB).
3. Frescura de datos.json (alerta si excede tiempo máximo durante horario operativo).

Gestión Sencilla:
- Destinatarios configurables directamente desde 'destinatarios_alertas.txt'.
- Posibilidad de pausar/subir/bajar cada alerta individual desde 'config.json' o por consola.
- Modo '--status' para ver en tiempo real qué se monitorea y qué está pausado.
"""
import os, sys, json, time, datetime, logging, urllib.request, smtplib
from email.message import EmailMessage
import email.utils

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')
DESTINATARIOS_FILE = os.path.join(BASE_DIR, 'destinatarios_alertas.txt')
LOGS_DIR = os.path.join(BASE_DIR, 'logs')
STATE_PATH = os.path.join(LOGS_DIR, 'monitor_state.json')
HISTORIAL_FILE = os.path.join(LOGS_DIR, 'historial_alertas.json')
MANUAL_HTML_PATH = r'C:\Users\gorinahostadmin\Desktop\Control de Aplicaciones\1_DIAGRAMA_Y_MANUAL.html'

CHECKS_DEF = {
    'web_red_corporativa': {
        'nombre': 'Acceso Red Corporativa (tablero.ciclo3)',
        'tipo': 'HTTP / IIS',
        'url_local': 'http://localhost/tablero.ciclo3/dashboard_operaciones.html',
        'url_display': 'http://fglp53/tablero.ciclo3/dashboard_operaciones.html'
    },
    'web_lab_puerto_8080': {
        'nombre': 'LAB Dashboard (Puerto 8080)',
        'tipo': 'HTTP / IIS',
        'url_local': 'http://localhost:8080/dashboard_operaciones.html',
        'url_display': 'http://localhost:8080/dashboard_operaciones.html'
    },
    'web_stock_puerto_8090': {
        'nombre': 'Stock Almacén (Puerto 8090)',
        'tipo': 'HTTP / IIS',
        'url_local': 'http://fglp53:8090/',
        'url_display': 'http://fglp53:8090/'
    },
    'api_gorinapick_5000': {
        'nombre': 'GorinaPick API Picking (Puerto 5000)',
        'tipo': 'HTTP API / .NET',
        'url_local': 'http://localhost:5000/api/ping',
        'url_display': 'http://localhost:5000/api/ping'
    },
    'tarea_colector_lab': {
        'nombre': 'Tarea Programada Gorina LAB - Colector datos',
        'tipo': 'Tarea Windows',
        'task_name': 'Gorina LAB - Colector datos'
    },
    'tarea_gorinapick': {
        'nombre': 'Tarea Programada Gorina - GorinaPick API 24-7',
        'tipo': 'Tarea Windows',
        'task_name': 'Gorina - GorinaPick API 24-7'
    },
    'frescura_datos_json': {
        'nombre': 'Frescura de Datos (datos.json)',
        'tipo': 'Datos en Tiempo Real',
        'path': r'D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\dashboard_test\datos.json'
    },
    'web_carniceria_8765': {
        'nombre': 'Tablero Carnicería Gorina (Puerto 8765)',
        'tipo': 'HTTP API / Python',
        'url_local': 'http://localhost:8765/api/estado',
        'url_display': 'http://fglp53:8765/tablero_carniceria'
    },
    'tarea_carniceria_tablero': {
        'nombre': 'Tarea Programada Gorina - Carniceria Tablero 24-7',
        'tipo': 'Tarea Windows',
        'task_name': 'Gorina - Carniceria Tablero 24-7'
    },
    'tarea_carniceria_diario': {
        'nombre': 'Tarea Programada Gorina - Carniceria Actualizacion Diaria',
        'tipo': 'Tarea Windows',
        'task_name': 'Gorina - Carniceria Actualizacion Diaria'
    }
}

def setup_log():
    os.makedirs(LOGS_DIR, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(levelname)-7s %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(os.path.join(LOGS_DIR, 'monitor_alertas.log'), encoding='utf-8'),
        ],
    )

def load_cfg():
    with open(CONFIG_PATH, encoding='utf-8-sig') as f:
        return json.load(f)

def save_cfg(cfg):
    with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=4, ensure_ascii=False)

def load_destinatarios_info(alert_cfg):
    """Carga destinatarios desde destinatarios_alertas.txt. Si no existe, recurre a config.json."""
    activos = []
    pausados = []
    if os.path.exists(DESTINATARIOS_FILE):
        try:
            for raw in open(DESTINATARIOS_FILE, encoding='utf-8', errors='ignore'):
                line = raw.strip()
                if not line or line.startswith('==='):
                    continue
                if line.startswith('#'):
                    # Comentario o mail pausado
                    c = line.lstrip('#').strip()
                    if '@' in c:
                        pausados.append(c)
                else:
                    if '@' in line:
                        activos.append(line)
        except Exception as e:
            logging.warning("Error al leer %s: %s", DESTINATARIOS_FILE, e)

    if not activos:
        activos = alert_cfg.get('to', ['mariano.diaz@friggorina.com'])

    return {
        'activos': list(dict.fromkeys(activos)),
        'pausados': list(dict.fromkeys(pausados)),
        'origen': DESTINATARIOS_FILE if os.path.exists(DESTINATARIOS_FILE) else 'config.json'
    }

def load_state():
    if os.path.exists(STATE_PATH):
        try:
            with open(STATE_PATH, encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            pass
    return {'last_state': 'OK', 'last_alert_time': 0, 'failing_services': []}

def save_state(state):
    try:
        with open(STATE_PATH, 'w', encoding='utf-8') as f:
            json.dump(state, f, indent=2, ensure_ascii=False)
    except Exception as e:
        logging.error("No se pudo guardar monitor_state.json: %s", e)

def load_historial():
    if os.path.exists(HISTORIAL_FILE):
        try:
            with open(HISTORIAL_FILE, encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            pass
    return []

def save_historial(hist):
    try:
        with open(HISTORIAL_FILE, 'w', encoding='utf-8') as f:
            json.dump(hist[:30], f, indent=2, ensure_ascii=False)
    except Exception as e:
        logging.error("Error al guardar historial_alertas.json: %s", e)

def record_event(tipo, servicio, detalle, to_list, asunto=""):
    now_str = datetime.datetime.now().strftime('%d/%m %H:%M:%S')
    ev = {
        'fecha': now_str,
        'tipo': tipo,
        'servicio': servicio,
        'detalle': detalle,
        'asunto': asunto,
        'destinatarios': to_list if isinstance(to_list, list) else [to_list],
        'estado': 'Enviado OK'
    }
    hist = load_historial()
    hist.insert(0, ev)
    save_historial(hist)
    update_manual_html(hist)
    return ev

def update_manual_html(hist=None):
    if not os.path.exists(MANUAL_HTML_PATH):
        return
    if hist is None:
        hist = load_historial()
    if not hist:
        return

    rows_html = ""
    for h in hist[:10]:
        badge_cls = "badge-off" if h['tipo'] == 'ALERTA' else ("badge-on" if h['tipo'] == 'RESTABLECIDO' else "badge-test")
        to_str = ", ".join(h.get('destinatarios', []))
        rows_html += f"""            <tr>
              <td style="font-family: monospace; font-size: 11.5px; color: #555;">{h['fecha']}</td>
              <td style="text-align: center;"><span class="badge {badge_cls}">{h['tipo']}</span></td>
              <td><strong>{h['servicio']}</strong><br><span style="color: #666; font-size: 11px;">{h['detalle']}</span></td>
              <td style="font-size: 11.5px; color: #333;">{to_str}</td>
            </tr>\n"""

    replacement_block = f"""<!-- INICIO_LOG_EVENTOS -->
      <div style="overflow-x: auto; max-height: 290px; overflow-y: auto; border: 1px solid var(--border); border-radius: 8px; background: #fff;">
        <table style="margin-top: 0; font-size: 12.5px; width: 100%;">
          <thead>
            <tr style="position: sticky; top: 0; background-color: #f8fafc; z-index: 1;">
              <th style="width: 130px;">Fecha / Hora</th>
              <th style="width: 110px; text-align: center;">Evento</th>
              <th>Servicio / Motivo</th>
              <th style="width: 170px;">Notificado A</th>
            </tr>
          </thead>
          <tbody>
{rows_html}          </tbody>
        </table>
      </div>
      <!-- FIN_LOG_EVENTOS -->"""

    try:
        with open(MANUAL_HTML_PATH, 'r', encoding='utf-8') as f:
            content = f.read()

        import re
        pattern = r'<!-- INICIO_LOG_EVENTOS -->.*?<!-- FIN_LOG_EVENTOS -->'
        if re.search(pattern, content, flags=re.DOTALL):
            new_content = re.sub(pattern, replacement_block, content, flags=re.DOTALL)
            with open(MANUAL_HTML_PATH, 'w', encoding='utf-8') as f:
                f.write(new_content)
    except Exception as e:
        logging.error("Error al actualizar 1_DIAGRAMA_Y_MANUAL.html: %s", e)

def get_recent_events_html(limit=4):
    hist = load_historial()
    if not hist:
        return ""
    rows = ""
    for h in hist[:limit]:
        bcolor = "#dc3545" if h.get('tipo') == 'ALERTA' else ("#28a745" if h.get('tipo') == 'RESTABLECIDO' else "#0284c7")
        rows += f"""
        <tr style="border-bottom: 1px solid #e0e0e0;">
          <td style="padding: 6px 10px; font-family: monospace; font-size: 11px; color: #555;">{h.get('fecha','')}</td>
          <td style="padding: 6px 10px; text-align: center;">
            <span style="background-color: {bcolor}; color: #fff; padding: 2px 6px; border-radius: 3px; font-size: 10px; font-weight: bold;">{h.get('tipo','')}</span>
          </td>
          <td style="padding: 6px 10px; font-size: 12px; color: #333;"><strong>{h.get('servicio','')}</strong>: {h.get('detalle','')}</td>
        </tr>
        """
    return f"""
    <h4 style="font-size: 13px; color: #0d233a; margin: 18px 0 8px; border-bottom: 1px solid #cbd5e1; padding-bottom: 4px;">
      Historial Reciente de Alertas y Eventos:
    </h4>
    <table style="width: 100%; border-collapse: collapse; background-color: #fff; border: 1px solid #e0e0e0; font-size: 12px; margin-bottom: 15px;">
      <thead>
        <tr style="background-color: #f1f5f9; text-align: left;">
          <th style="padding: 6px 10px; font-size: 11px; color: #475569; width: 110px;">Fecha / Hora</th>
          <th style="padding: 6px 10px; font-size: 11px; color: #475569; text-align: center; width: 90px;">Evento</th>
          <th style="padding: 6px 10px; font-size: 11px; color: #475569;">Detalle</th>
        </tr>
      </thead>
      <tbody>
        {rows}
      </tbody>
    </table>
    """

def get_recent_events_text(limit=4):
    hist = load_historial()
    if not hist:
        return ""
    txt = "\nHISTORIAL RECIENTE DE EVENTOS:\n"
    for h in hist[:limit]:
        txt += f"- [{h.get('tipo','')}] {h.get('fecha','')}: {h.get('servicio','')} ({h.get('detalle','')})\n"
    return txt

def check_url(url, timeout=4):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Serv-Monitor'})
        res = urllib.request.urlopen(req, timeout=timeout)
        code = res.getcode()
        return (code == 200), f"HTTP {code}"
    except Exception as e:
        return False, str(e)

def get_scheduled_task_states():
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
                    'last_result': t.LastTaskResult
                }
    except Exception as e:
        res['error'] = str(e)
    return res

def send_mail(subject, text_body, html_body, to_list, cfg, is_high_priority=False):
    mail_cfg = cfg.get('mail', {})
    host = mail_cfg.get('smtp_host', '192.168.0.234')
    port = int(mail_cfg.get('smtp_port', 25))
    frm = mail_cfg.get('from', 'ciclo3@friggorina.com')

    msg = EmailMessage()
    msg['From'] = f"Control de Operaciones Ciclo 3 <{frm}>"
    msg['To'] = ", ".join(to_list)
    msg['Subject'] = subject
    msg['Date'] = email.utils.formatdate(localtime=True)
    msg['Message-ID'] = email.utils.make_msgid(domain='friggorina.com')
    if is_high_priority:
        msg['X-Priority'] = '2'
        msg['Importance'] = 'High'
    else:
        msg['X-Priority'] = '3'
        msg['Importance'] = 'Normal'

    msg.set_content(text_body)
    if html_body:
        msg.add_alternative(html_body, subtype='html')

    logging.info("Enviando alerta a %s via SMTP %s:%d...", to_list, host, port)
    s = smtplib.SMTP(host, port, timeout=25)
    s.ehlo()
    s.send_message(msg)
    s.quit()
    logging.info("Correo enviado exitosamente: '%s'", subject)
    return True

def send_test_email():
    """Ejecuta una verificación en vivo y envía un correo de prueba formal sin alterar el historial."""
    setup_log()
    print("=" * 76)
    print("    ENVIANDO ALERTA DE PRUEBA POR CORREO — CONTROL DE APLICACIONES")
    print("=" * 76)
    cfg = load_cfg()
    alert_cfg = cfg.get('alerts', {})
    dest_info = load_destinatarios_info(alert_cfg)
    to_list = dest_info['activos']

    if not to_list:
        print("\n[ERROR] No hay destinatarios activos configurados en destinatarios_alertas.txt.")
        print("Edite la lista de destinatarios antes de realizar la prueba.")
        return False

    print(f"Destinatarios activos: {', '.join(to_list)}")
    print("Verificando estado actual de los servicios...")

    now = datetime.datetime.now()
    checks_cfg = alert_cfg.get('checks', {})
    tasks = get_scheduled_task_states()
    results = []

    for k, d in CHECKS_DEF.items():
        is_enabled = checks_cfg.get(k, True)
        if not is_enabled:
            results.append({'nombre': d['nombre'], 'tipo': d['tipo'], 'estado': 'PAUSADO', 'detalle': 'Pausado por usuario'})
            continue

        if d['tipo'].startswith('HTTP'):
            ok, msg = check_url(d['url_local'])
            st = 'OK' if ok else 'FALLA'
            results.append({'nombre': d['nombre'], 'tipo': d['tipo'], 'estado': st, 'detalle': msg})
        elif d['tipo'] == 'Tarea Windows':
            t = tasks.get(d['task_name'])
            if t:
                is_ok = (t['state'] != 'Disabled' and t['enabled'])
                st = 'OK' if is_ok else 'FALLA'
                results.append({'nombre': d['nombre'], 'tipo': d['tipo'], 'estado': st, 'detalle': f"Estado: {t['state']}"})
            else:
                results.append({'nombre': d['nombre'], 'tipo': d['tipo'], 'estado': 'FALLA', 'detalle': 'No encontrada'})
        elif d['tipo'] == 'Datos en Tiempo Real':
            p = d['path']
            if os.path.exists(p):
                mtime = datetime.datetime.fromtimestamp(os.path.getmtime(p))
                diff_min = int((now - mtime).total_seconds() / 60)
                max_age = alert_cfg.get('max_data_age_minutes', 20)
                st = 'OK' if diff_min <= max_age else 'DESACTUALIZADO'
                results.append({'nombre': d['nombre'], 'tipo': d['tipo'], 'estado': st, 'detalle': f"Hace {diff_min} min"})
            else:
                results.append({'nombre': d['nombre'], 'tipo': d['tipo'], 'estado': 'FALLA', 'detalle': 'Archivo no existe'})

    subject = f"[Prueba de Alertas] Verificación de Sistema — Servicios Ciclo 3 (FGLP53)"

    text_body = f"""FRIGORIFICO GORINA — CONTROL DE OPERACIONES CICLO 3
PRUEBA TÉCNICA DE ALERTA DE SERVICIOS
Servidor: FGLP53 (192.168.0.126)
Fecha y Hora: {now.strftime('%d/%m/%Y %H:%M:%S')}

Esta es una prueba manual de envío de alertas por correo electrónico.
Si recibe este mensaje, el circuito de notificación por correo funciona correctamente.

ESTADO ACTUAL DE LOS SERVICIOS EN EL SERVIDOR:
"""
    for r in results:
        text_body += f"- [{r['estado']}] {r['nombre']} ({r['tipo']}): {r['detalle']}\n"

    text_body += get_recent_events_text(limit=5)
    text_body += f"\nDestinatarios notificados: {', '.join(to_list)}\n"
    text_body += "\n--\nControl de Operaciones Ciclo 3 — Frigorífico Gorina SAIC\n"

    rows_html = ""
    for r in results:
        badge_bg = "#28a745" if r['estado'] == 'OK' else ("#dc3545" if r['estado'] == 'FALLA' else "#6c757d")
        rows_html += f"""
        <tr style="border-bottom: 1px solid #e0e0e0;">
          <td style="padding: 8px 12px; font-weight: bold; color: #333;">{r['nombre']}</td>
          <td style="padding: 8px 12px; color: #666; font-size: 12px;">{r['tipo']}</td>
          <td style="padding: 8px 12px; text-align: center;">
            <span style="background-color: {badge_bg}; color: #fff; padding: 3px 8px; border-radius: 3px; font-size: 11px; font-weight: bold;">{r['estado']}</span>
          </td>
          <td style="padding: 8px 12px; color: #555; font-size: 12px;">{r['detalle']}</td>
        </tr>
        """

    recent_events_section = get_recent_events_html(limit=5)

    html_body = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: Calibri, 'Segoe UI', Arial, sans-serif; font-size: 14px; color: #222; line-height: 1.5; margin: 20px;">
  <div style="background-color: #0d233a; color: #fff; padding: 14px 20px; border-radius: 6px 6px 0 0;">
    <h2 style="margin: 0; font-size: 18px; font-weight: 600;">Frigorífico Gorina &mdash; Control de Operaciones Ciclo 3</h2>
    <p style="margin: 4px 0 0; font-size: 12px; color: #cbd5e1;">Servidor FGLP53 (192.168.0.126) &bull; Sistema de Vigilancia y Alertas</p>
  </div>
  <div style="border: 1px solid #0d233a; border-top: none; border-radius: 0 0 6px 6px; padding: 20px; background-color: #fafbfc;">
    <div style="background-color: #e8f4fd; border: 1px solid #b8daff; border-radius: 4px; padding: 12px 16px; margin-bottom: 20px;">
      <p style="margin: 0; font-size: 14px; font-weight: bold; color: #004085;">
        &#9989; Prueba de Alerta Exitosa
      </p>
      <p style="margin: 4px 0 0; font-size: 13px; color: #333;">
        Este es un envío voluntario generado para comprobar la correcta recepción de avisos.
      </p>
    </div>

    <h3 style="font-size: 14px; color: #0d233a; margin-top: 0; margin-bottom: 10px; border-bottom: 2px solid #0d233a; padding-bottom: 4px;">
      Estado en Vivo de los Servicios Vigilados:
    </h3>
    <table style="width: 100%; border-collapse: collapse; background-color: #fff; border: 1px solid #e0e0e0; font-size: 13px; margin-bottom: 20px;">
      <thead>
        <tr style="background-color: #f1f5f9; border-bottom: 2px solid #cbd5e1; text-align: left;">
          <th style="padding: 8px 12px; font-weight: bold; color: #475569;">Servicio</th>
          <th style="padding: 8px 12px; font-weight: bold; color: #475569;">Tipo</th>
          <th style="padding: 8px 12px; font-weight: bold; color: #475569; text-align: center;">Estado</th>
          <th style="padding: 8px 12px; font-weight: bold; color: #475569;">Detalle</th>
        </tr>
      </thead>
      <tbody>
        {rows_html}
      </tbody>
    </table>

    {recent_events_section}

    <p style="font-size: 12px; color: #555; margin-bottom: 5px;">
      <strong>Destinatarios Notificados:</strong> {', '.join(to_list)}
    </p>
    <p style="font-size: 12px; color: #555; margin-top: 0;">
      <strong>Fecha y Hora de Emisión:</strong> {now.strftime('%d/%m/%Y %H:%M:%S')}
    </p>

    <div style="font-size: 11px; color: #888; border-top: 1px solid #e0e0e0; padding-top: 10px; margin-top: 20px;">
      Monitor de Servicios Ciclo 3 &bull; Frigorífico Gorina SAIC &bull; Servidor FGLP53
    </div>
  </div>
</body>
</html>"""

    try:
        send_mail(subject, text_body, html_body, to_list, cfg, is_high_priority=False)
        record_event("PRUEBA", "Sistema Completo (7 Servicios)", "Prueba técnica manual solicitada desde el Escritorio", to_list, subject)
        print("\n>> Correo de prueba enviado exitosamente al relay.")
        print(f">> Destinatario(s): {', '.join(to_list)}")
        print("\nAVISO IMPORTANTE:")
        print("Si el correo no aparece en su Bandeja de Entrada en 1-2 minutos:")
        print("1. Revise la carpeta 'Correo no deseado' (Spam) en Outlook o Gmail corporativo.")
        print("2. Si usa Outlook con pestañas, revise la pestaña 'Otros'.")
        return True
    except Exception as e:
        print(f"\n[ERROR] No se pudo enviar el correo: {e}")
        logging.error("Fallo al enviar correo de prueba: %s", e)
        return False

def print_status():
    """Imprime en consola un resumen claro del estado del monitor para el operador."""
    cfg = load_cfg()
    alert_cfg = cfg.get('alerts', {})
    dest_info = load_destinatarios_info(alert_cfg)
    checks_cfg = alert_cfg.get('checks', {})
    state = load_state()
    now = datetime.datetime.now()

    sep = "=" * 80
    print(sep)
    print("      PANEL DE CONTROL — MONITOR DE SERVICIOS Y ALERTAS CICLO 3")
    print(sep)
    print(f"Fecha y Hora: {now.strftime('%d/%m/%Y %H:%M:%S')}")
    print(f"Estado General del Monitor: [{'ACTIVO' if alert_cfg.get('enabled', True) else 'PAUSADO TOTAL'}]")
    print(f"Cooldown Anti-Spam: {alert_cfg.get('cooldown_minutes', 60)} minutos")
    print()

    print("[1] DESTINATARIOS DE ALERTAS:")
    print(f"  * Origen de configuración: {dest_info['origen']}")
    print(f"  * Destinatarios Activos   : {', '.join(dest_info['activos']) if dest_info['activos'] else '(Ninguno)'}")
    if dest_info['pausados']:
        print(f"  * Destinatarios Pausados  : {', '.join(dest_info['pausados'])}")
    print()

    print("[2] ESTADO DE CADA ALERTA (SUBIR / BAJAR):")
    tasks = get_scheduled_task_states()
    for k, d in CHECKS_DEF.items():
        is_enabled = checks_cfg.get(k, True)
        status_tag = ""
        detail = ""

        if not is_enabled:
            status_tag = "[PAUSADA POR USUARIO]"
            detail = "No genera alertas de correo"
        else:
            if d['tipo'].startswith('HTTP'):
                ok, msg = check_url(d['url_local'])
                status_tag = "[ACTIVA - OK]" if ok else f"[ACTIVA - FALLA: {msg}]"
                detail = d['url_display']
            elif d['tipo'] == 'Tarea Windows':
                t = tasks.get(d['task_name'])
                if t:
                    is_ok = (t['state'] != 'Disabled' and t['enabled'])
                    status_tag = f"[ACTIVA - {t['state']}]" if is_ok else f"[ACTIVA - FALLA: {t['state']}]"
                    detail = f"Ultima: {t['last_run']}"
                else:
                    status_tag = "[ACTIVA - NO ENCONTRADA]"
            elif d['tipo'] == 'Datos en Tiempo Real':
                p = d['path']
                if os.path.exists(p):
                    mtime = datetime.datetime.fromtimestamp(os.path.getmtime(p))
                    diff_min = int((now - mtime).total_seconds() / 60)
                    status_tag = "[ACTIVA - AL DÍA]" if diff_min <= alert_cfg.get('max_data_age_minutes', 20) else f"[ACTIVA - DESACTUALIZADO ({diff_min} min)]"
                    detail = f"Modificado: {mtime.strftime('%H:%M:%S')} (hace {diff_min} min)"
                else:
                    status_tag = "[ACTIVA - ARCHIVO INEXISTENTE]"

        print(f"  * {d['nombre']:<45}: {status_tag:<28} {detail}")

    print()
    print("[3] ÚLTIMO REGISTRO DE EVENTOS:")
    last_state = state.get('last_state', 'OK')
    last_alert_time = state.get('last_alert_time', 0)
    last_alert_str = datetime.datetime.fromtimestamp(last_alert_time).strftime('%d/%m/%Y %H:%M:%S') if last_alert_time else 'Nunca'
    print(f"  * Último estado registrado: [{last_state}]")
    print(f"  * Última alerta enviada   : {last_alert_str}")
    if state.get('failing_services'):
        print(f"  * Servicios caídos        : {', '.join(state['failing_services'])}")

    print()
    print("[4] HISTORIAL DE ÚLTIMAS ALERTAS Y DESCONEXIONES:")
    hist = load_historial()
    if hist:
        for h in hist[:5]:
            print(f"  * {h['fecha']} [{h['tipo']}] {h['servicio']}: {h['detalle']}")
    else:
        print("  * No hay registros de eventos previos.")
    print(sep)

def toggle_check_interactive():
    """Menú unificado para configurar, pausar alertas y editar destinatarios."""
    cfg = load_cfg()
    alert_cfg = cfg.setdefault('alerts', {})
    checks_cfg = alert_cfg.setdefault('checks', {})
    keys = list(CHECKS_DEF.keys())

    while True:
        os.system('cls' if os.name == 'nt' else 'clear')
        dest_info = load_destinatarios_info(alert_cfg)
        curr_all = alert_cfg.get('enabled', True)

        # Chequear estado real de la tarea en Windows
        tasks = get_scheduled_task_states()
        t_mon = tasks.get('Gorina LAB - Monitor Alertas Servicios', {})
        t_state = t_mon.get('state', 'Unknown')

        print("=" * 76)
        print("    PANEL UNIFICADO — CONFIGURAR, PAUSAR ALERTAS Y EDITAR DESTINATARIOS")
        print("=" * 76)
        print(f"  * Estado General del Monitor : [{'ACTIVADO' if curr_all else 'PAUSADO TOTAL'}]")
        print(f"  * Tarea Windows en segundo plano: [{t_state}]")
        print(f"  * Destinatarios Activos       : {', '.join(dest_info['activos']) if dest_info['activos'] else '(Ninguno)'}")
        if dest_info['pausados']:
            print(f"  * Destinatarios Pausados      : {', '.join(dest_info['pausados'])}")
        print("-" * 76)
        print("SUBIR / BAJAR ALERTAS POR SERVICIO INDIVIDUAL (Presione el número 1-" + str(len(keys)) + "):")
        for idx, k in enumerate(keys, 1):
            curr = checks_cfg.get(k, True)
            estado = "VIGILADA [ON]" if curr else "PAUSADA [OFF]"
            print(f"   [{idx}] {CHECKS_DEF[k]['nombre']:<48} -> {estado}")

        print("-" * 76)
        print("ACCIONES GENERALES:")
        print("   [T] ENVIAR CORREO DE PRUEBA AHORA (Dispara comprobación a destinatarios)")
        print("   [P] PAUSAR / ACTIVAR TODO el sistema (conmuta config y tarea Windows)")
        print("   [D] EDITAR DESTINATARIOS (Abre destinatarios_alertas.txt en Bloc de Notas)")
        print("   [S] Guardar y Salir")
        print("   [C] Cancelar / Salir sin guardar")
        print("=" * 76)
        opc = input("Seleccione una opción: ").strip().upper()

        if opc == 'S':
            save_cfg(cfg)
            print("\n>> Configuración guardada correctamente.")
            time.sleep(1.2)
            break
        elif opc == 'C':
            print("\n>> Operación cerrada.")
            time.sleep(0.8)
            break
        elif opc == 'T':
            print("\n>> Generando y enviando alerta de prueba técnica...")
            send_test_email()
            input("\nPresione [ENTER] para regresar al menú...")
        elif opc == 'D':
            print("\n>> Abriendo destinatarios_alertas.txt en Bloc de Notas...")
            os.system(f'start notepad.exe "{DESTINATARIOS_FILE}"')
            time.sleep(1)
        elif opc == 'P':
            nuevo_estado = not curr_all
            alert_cfg['enabled'] = nuevo_estado
            # Conmutar también tarea de Windows
            if os.name == 'nt':
                cmd = 'Enable-ScheduledTask' if nuevo_estado else 'Disable-ScheduledTask'
                os.system(f'powershell -Command "{cmd} -TaskName \'Gorina LAB - Monitor Alertas Servicios\'" >nul 2>&1')
            print(f"\n>> Sistema general {'ACTIVADO' if nuevo_estado else 'PAUSADO'}.")
            time.sleep(1)
        elif opc.isdigit() and 1 <= int(opc) <= len(keys):
            target_key = keys[int(opc) - 1]
            curr_val = checks_cfg.get(target_key, True)
            checks_cfg[target_key] = not curr_val
        else:
            print("\n>> Opción no válida.")
            time.sleep(1)

def run_monitor(dry_run=False, force_alert=False):
    setup_log()
    logging.info("=== Iniciando ciclo de monitoreo de servicios ===")
    cfg = load_cfg()
    alert_cfg = cfg.get('alerts', {})
    if not alert_cfg.get('enabled', True) and not force_alert:
        logging.info("El sistema de alertas está deshabilitado en config.json. Omitiendo.")
        return

    dest_info = load_destinatarios_info(alert_cfg)
    to_list = dest_info['activos']
    if not to_list:
        logging.warning("No hay destinatarios de alerta activos. Omitiendo envío.")
        return

    cooldown_sec = alert_cfg.get('cooldown_minutes', 60) * 60
    max_data_age_min = alert_cfg.get('max_data_age_minutes', 20)
    checks_cfg = alert_cfg.get('checks', {})

    now = datetime.datetime.now()
    now_epoch = time.time()
    state = load_state()

    failures = []
    monitored_active = []
    monitored_paused = []

    # 1. Chequeos HTTP
    http_keys = ['web_red_corporativa', 'web_lab_puerto_8080', 'web_stock_puerto_8090', 'api_gorinapick_5000']
    for k in http_keys:
        d = CHECKS_DEF[k]
        if checks_cfg.get(k, True):
            monitored_active.append(d['nombre'])
            ok, msg = check_url(d['url_local'])
            if not ok:
                failures.append({
                    'tipo': d['tipo'],
                    'servicio': d['nombre'],
                    'detalle': f"Falla de conexión ({msg}) en {d['url_display']}"
                })
                logging.warning("[FALLA] %s: %s", d['nombre'], msg)
            else:
                logging.info("[OK] %s: %s", d['nombre'], msg)
        else:
            monitored_paused.append(d['nombre'])
            logging.info("[PAUSADO] %s (omitido por configuración)", d['nombre'])

    # 2. Tareas Programadas
    tasks_keys = ['tarea_colector_lab', 'tarea_gorinapick']
    tasks = get_scheduled_task_states()
    for k in tasks_keys:
        d = CHECKS_DEF[k]
        if checks_cfg.get(k, True):
            monitored_active.append(d['nombre'])
            if 'error' in tasks:
                logging.warning("No se pudo verificar Schedule.Service: %s", tasks['error'])
            else:
                t = tasks.get(d['task_name'])
                if t:
                    if t['state'] == 'Disabled' or not t['enabled']:
                        failures.append({
                            'tipo': d['tipo'],
                            'servicio': d['nombre'],
                            'detalle': f"La tarea programada está DESHABILITADA (Estado: {t['state']})"
                        })
                        logging.warning("[FALLA] %s está Disabled", d['nombre'])
                    else:
                        logging.info("[OK] %s: %s", d['nombre'], t['state'])
                else:
                    failures.append({
                        'tipo': d['tipo'],
                        'servicio': d['nombre'],
                        'detalle': "La tarea no fue encontrada en Windows Task Scheduler"
                    })
        else:
            monitored_paused.append(d['nombre'])
            logging.info("[PAUSADO] %s (omitido por configuración)", d['nombre'])

    # 3. Frescura de datos.json
    k_data = 'frescura_datos_json'
    d_data = CHECKS_DEF[k_data]
    if checks_cfg.get(k_data, True):
        monitored_active.append(d_data['nombre'])
        is_weekday = (now.weekday() < 5)
        is_work_hours = (6 <= now.hour < 20)
        datos_path = d_data['path']

        if is_weekday and is_work_hours:
            if os.path.exists(datos_path):
                mtime = datetime.datetime.fromtimestamp(os.path.getmtime(datos_path))
                diff_min = int((now - mtime).total_seconds() / 60)
                if diff_min > max_data_age_min:
                    failures.append({
                        'tipo': d_data['tipo'],
                        'servicio': d_data['nombre'],
                        'detalle': f"El archivo no se actualiza desde hace {diff_min} min (límite: {max_data_age_min} min). Última modificación: {mtime.strftime('%H:%M:%S')}"
                    })
                    logging.warning("[FALLA] datos.json desactualizado: %d min", diff_min)
                else:
                    logging.info("[OK] datos.json al día (%d min de antigüedad)", diff_min)
            else:
                failures.append({
                    'tipo': d_data['tipo'],
                    'servicio': d_data['nombre'],
                    'detalle': f"No existe el archivo {datos_path}"
                })
        else:
            logging.info("[OK] Fuera de horario operativo semanal: verificación de datos omitida.")
    else:
        monitored_paused.append(d_data['nombre'])
        logging.info("[PAUSADO] %s (omitido por configuración)", d_data['nombre'])

    hay_falla = len(failures) > 0
    prev_state = state.get('last_state', 'OK')
    last_alert_time = state.get('last_alert_time', 0)
    time_since_alert = now_epoch - last_alert_time

    if hay_falla:
        debe_enviar = (prev_state == 'OK') or (time_since_alert >= cooldown_sec)

        if debe_enviar:
            logging.info("Disparando ALERTA por anomalía en servicios...")
            asunto = f"[Aviso Operativo] Anomalía en Servicios Dashboard Ciclo 3 ({now.strftime('%d/%m %H:%M')})"
            
            cuerpo = f"""ATENCIÓN: Se detectaron anomalías en los servicios de Dashboard Ciclo 3.
Servidor: FGLP53 (192.168.0.126)
Fecha y Hora: {now.strftime('%d/%m/%Y %H:%M:%S')}

DETALLE DE FALLAS IDENTIFICADAS:
"""
            for i, f in enumerate(failures, 1):
                cuerpo += f"\n{i}. [{f['tipo']}] {f['servicio']}\n   Motivo: {f['detalle']}\n"

            cuerpo += "\nRESUMEN DE VIGILANCIA:\n"
            cuerpo += f"- Monitoreos Activos: {', '.join(monitored_active)}\n"
            if monitored_paused:
                cuerpo += f"- Monitoreos Pausados por Usuario: {', '.join(monitored_paused)}\n"
            cuerpo += f"- Destinatarios Notificados: {', '.join(to_list)}\n"
            cuerpo += get_recent_events_text(limit=4)

            cuerpo += """
ACCIONES SUGERIDAS:
1. Abrir la carpeta 'Control de Aplicaciones' en el Escritorio del servidor FGLP53.
2. Ejecutar '2_ESTADO_DE_ALERTAS.bat' para ver el diagnóstico en vivo.
3. Si requiere asistencia, revisar el diagrama en '1_DIAGRAMA_Y_MANUAL.html'.

Este aviso se reemitirá si las fallas persisten por más de 60 minutos.
Al restablecerse los servicios se enviará automáticamente un correo de confirmación.
--
Control de Operaciones Ciclo 3 — Frigorífico Gorina SAIC
"""

            rows_fail_html = ""
            for i, f in enumerate(failures, 1):
                rows_fail_html += f"""
                <tr style="border-bottom: 1px solid #f5c6cb;">
                  <td style="padding: 8px 12px; font-weight: bold; color: #721c24;">{f['servicio']}</td>
                  <td style="padding: 8px 12px; color: #666; font-size: 12px;">{f['tipo']}</td>
                  <td style="padding: 8px 12px; color: #721c24; font-size: 12px;">{f['detalle']}</td>
                </tr>
                """

            recent_events_fail_section = get_recent_events_html(limit=4)

            html_body = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: Calibri, 'Segoe UI', Arial, sans-serif; font-size: 14px; color: #222; line-height: 1.5; margin: 20px;">
  <div style="background-color: #0d233a; color: #fff; padding: 14px 20px; border-radius: 6px 6px 0 0;">
    <h2 style="margin: 0; font-size: 18px; font-weight: 600;">Frigorífico Gorina &mdash; Control de Operaciones Ciclo 3</h2>
    <p style="margin: 4px 0 0; font-size: 12px; color: #cbd5e1;">Servidor FGLP53 (192.168.0.126) &bull; Sistema de Vigilancia y Alertas</p>
  </div>
  <div style="border: 1px solid #0d233a; border-top: none; border-radius: 0 0 6px 6px; padding: 20px; background-color: #fafbfc;">
    <div style="background-color: #f8d7da; border: 1px solid #f5c6cb; border-radius: 4px; padding: 12px 16px; margin-bottom: 20px;">
      <p style="margin: 0; font-size: 14px; font-weight: bold; color: #721c24;">
        &#9888; ATENCIÓN: Anomalía detectada en servicios de Ciclo 3
      </p>
      <p style="margin: 4px 0 0; font-size: 13px; color: #491217;">
        Se detectaron interrupciones que requieren verificación en el servidor FGLP53.
      </p>
    </div>

    <h3 style="font-size: 14px; color: #721c24; margin-top: 0; margin-bottom: 10px; border-bottom: 2px solid #dc3545; padding-bottom: 4px;">
      Detalle de Fallas Identificadas:
    </h3>
    <table style="width: 100%; border-collapse: collapse; background-color: #fff; border: 1px solid #f5c6cb; font-size: 13px; margin-bottom: 20px;">
      <thead>
        <tr style="background-color: #fdf2f2; border-bottom: 2px solid #f5c6cb; text-align: left;">
          <th style="padding: 8px 12px; font-weight: bold; color: #721c24;">Servicio Afectado</th>
          <th style="padding: 8px 12px; font-weight: bold; color: #721c24;">Tipo</th>
          <th style="padding: 8px 12px; font-weight: bold; color: #721c24;">Motivo / Diagnóstico</th>
        </tr>
      </thead>
      <tbody>
        {rows_fail_html}
      </tbody>
    </table>

    <div style="background-color: #fff; border: 1px solid #e0e0e0; border-radius: 4px; padding: 12px 16px; margin-bottom: 20px; font-size: 13px;">
      <p style="margin: 0 0 6px; font-weight: bold; color: #333;">Acciones sugeridas:</p>
      <ol style="margin: 0; padding-left: 20px; color: #444;">
        <li>Abrir la carpeta <strong>'Control de Aplicaciones'</strong> en el Escritorio del servidor FGLP53.</li>
        <li>Ejecutar <strong>'2_ESTADO_DE_ALERTAS.bat'</strong> para ver el diagnóstico en tiempo real.</li>
        <li>Si requiere consultar diagramas, abrir <strong>'1_DIAGRAMA_Y_MANUAL.html'</strong>.</li>
      </ol>
    </div>

    {recent_events_fail_section}

    <p style="font-size: 12px; color: #555; margin-bottom: 4px;">
      <strong>Destinatarios Notificados:</strong> {', '.join(to_list)}
    </p>
    <p style="font-size: 12px; color: #555; margin-top: 0;">
      <strong>Fecha y Hora de Detección:</strong> {now.strftime('%d/%m/%Y %H:%M:%S')}
    </p>

    <div style="font-size: 11px; color: #888; border-top: 1px solid #e0e0e0; padding-top: 10px; margin-top: 20px;">
      Este aviso se reemitirá tras 60 minutos si la falla persiste. Al normalizarse se enviará un correo de confirmación.
    </div>
  </div>
</body>
</html>"""

            if not dry_run:
                try:
                    send_mail(asunto, cuerpo, html_body, to_list, cfg, is_high_priority=True)
                    failing_names = ", ".join([f['servicio'] for f in failures])
                    record_event("ALERTA", failing_names, "; ".join([f['detalle'] for f in failures]), to_list, asunto)
                    state['last_alert_time'] = now_epoch
                except Exception as e:
                    logging.error("Error al enviar correo de alerta: %s", e)
            else:
                logging.info("[DRY-RUN] Correo que se enviaría:\n%s\n%s", asunto, cuerpo)

            state['last_state'] = 'FAIL'
            state['failing_services'] = [f['servicio'] for f in failures]
            save_state(state)
        else:
            min_restantes = int((cooldown_sec - time_since_alert) / 60)
            logging.info("Falla activa pero en período de cooldown (próxima alerta en %d min si persiste).", min_restantes)
            state['failing_services'] = [f['servicio'] for f in failures]
            save_state(state)

    else:
        if prev_state == 'FAIL':
            logging.info("Servicios recuperados. Disparando AVISO DE RESTABLECIMIENTO...")
            asunto = f"[Normalizado] Servicios Dashboard Ciclo 3 operando correctamente ({now.strftime('%d/%m %H:%M')})"
            cuerpo = f"""NOTIFICACIÓN DE RESTABLECIMIENTO:
Los servicios de Dashboard Ciclo 3 se han normalizado satisfactoriamente.

Servidor: FGLP53 (192.168.0.126)
Fecha y Hora: {now.strftime('%d/%m/%Y %H:%M:%S')}

ESTADO ACTUAL:
- Acceso Red (tablero.ciclo3): [OK] HTTP 200
- LAB Dashboard (Puerto 8080): [OK] HTTP 200
- Stock Almacén (Puerto 8090): [OK] HTTP 200
- GorinaPick API (Puerto 5000): [OK] HTTP 200
- Tareas programadas de recolección: [OK] Activas
- Frescura de datos: [OK] Al día
"""
            cuerpo += get_recent_events_text(limit=4)
            cuerpo += f"""
Destinatarios notificados: {', '.join(to_list)}

Todos los sistemas operan dentro de los parámetros normales.
--
Control de Operaciones Ciclo 3 — Frigorífico Gorina SAIC
"""

            recent_events_rest_section = get_recent_events_html(limit=4)

            html_body = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: Calibri, 'Segoe UI', Arial, sans-serif; font-size: 14px; color: #222; line-height: 1.5; margin: 20px;">
  <div style="background-color: #0d233a; color: #fff; padding: 14px 20px; border-radius: 6px 6px 0 0;">
    <h2 style="margin: 0; font-size: 18px; font-weight: 600;">Frigorífico Gorina &mdash; Control de Operaciones Ciclo 3</h2>
    <p style="margin: 4px 0 0; font-size: 12px; color: #cbd5e1;">Servidor FGLP53 (192.168.0.126) &bull; Sistema de Vigilancia y Alertas</p>
  </div>
  <div style="border: 1px solid #0d233a; border-top: none; border-radius: 0 0 6px 6px; padding: 20px; background-color: #fafbfc;">
    <div style="background-color: #d4edda; border: 1px solid #c3e6cb; border-radius: 4px; padding: 12px 16px; margin-bottom: 20px;">
      <p style="margin: 0; font-size: 14px; font-weight: bold; color: #155724;">
        &#9989; SERVICIOS RESTABLECIDOS
      </p>
      <p style="margin: 4px 0 0; font-size: 13px; color: #155724;">
        Todos los componentes del Dashboard Ciclo 3 operan normalmente.
      </p>
    </div>

    <table style="width: 100%; border-collapse: collapse; background-color: #fff; border: 1px solid #c3e6cb; font-size: 13px; margin-bottom: 20px;">
      <tr style="border-bottom: 1px solid #e0e0e0;"><td style="padding: 8px 12px; font-weight: bold;">Acceso Red Corporativa (tablero.ciclo3)</td><td style="padding: 8px 12px; color: #155724; font-weight: bold;">[OK] HTTP 200</td></tr>
      <tr style="border-bottom: 1px solid #e0e0e0;"><td style="padding: 8px 12px; font-weight: bold;">LAB Dashboard (Puerto 8080)</td><td style="padding: 8px 12px; color: #155724; font-weight: bold;">[OK] HTTP 200</td></tr>
      <tr style="border-bottom: 1px solid #e0e0e0;"><td style="padding: 8px 12px; font-weight: bold;">Stock Almacén (Puerto 8090)</td><td style="padding: 8px 12px; color: #155724; font-weight: bold;">[OK] HTTP 200</td></tr>
      <tr style="border-bottom: 1px solid #e0e0e0;"><td style="padding: 8px 12px; font-weight: bold;">GorinaPick API Picking (Puerto 5000)</td><td style="padding: 8px 12px; color: #155724; font-weight: bold;">[OK] HTTP 200</td></tr>
      <tr style="border-bottom: 1px solid #e0e0e0;"><td style="padding: 8px 12px; font-weight: bold;">Tareas Programadas (Colector LAB y GorinaPick)</td><td style="padding: 8px 12px; color: #155724; font-weight: bold;">[OK] Activas</td></tr>
      <tr><td style="padding: 8px 12px; font-weight: bold;">Frescura de Datos (datos.json)</td><td style="padding: 8px 12px; color: #155724; font-weight: bold;">[OK] Al día</td></tr>
    </table>

    {recent_events_rest_section}

    <p style="font-size: 12px; color: #555; margin-bottom: 4px;">
      <strong>Destinatarios Notificados:</strong> {', '.join(to_list)}
    </p>
    <p style="font-size: 12px; color: #555; margin-top: 0;">
      <strong>Fecha y Hora:</strong> {now.strftime('%d/%m/%Y %H:%M:%S')}
    </p>

    <div style="font-size: 11px; color: #888; border-top: 1px solid #e0e0e0; padding-top: 10px; margin-top: 20px;">
      Monitor de Servicios Ciclo 3 &bull; Frigorífico Gorina SAIC &bull; Servidor FGLP53
    </div>
  </div>
</body>
</html>"""

            if not dry_run:
                try:
                    send_mail(asunto, cuerpo, html_body, to_list, cfg, is_high_priority=False)
                    record_event("RESTABLECIDO", "Infraestructura Dashboard", "Todos los servicios normalizados (HTTP 200 / Tareas Ready)", to_list, asunto)
                except Exception as e:
                    logging.error("Error al enviar correo de restablecimiento: %s", e)
            else:
                logging.info("[DRY-RUN] Correo de restablecimiento que se enviaría:\n%s\n%s", asunto, cuerpo)

        state['last_state'] = 'OK'
        state['last_check_time'] = now.strftime('%Y-%m-%d %H:%M:%S')
        state['failing_services'] = []
        save_state(state)
        logging.info("=== Monitoreo completado: Todos los servicios [OK] ===")

if __name__ == '__main__':
    if '--status' in sys.argv:
        print_status()
    elif '--toggle' in sys.argv:
        toggle_check_interactive()
    elif '--test-mail' in sys.argv or '--force-alert' in sys.argv:
        send_test_email()
    else:
        dry = '--dry-run' in sys.argv or '--test' in sys.argv
        run_monitor(dry_run=dry)
