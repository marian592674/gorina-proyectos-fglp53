#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cierre_jornada.py — Envío automático de correo de cierre de operaciones diarias (Ciclo 3).

Lógica de funcionamiento:
1. Se invoca cada 5 minutos (al final de colector.bat).
2. Ventana de vigilancia: lunes a viernes a partir de las 16:00 hs.
3. Detección de inactividad: compara lecturas de TRV y Almacén en datos.json.
   Si por 15 minutos consecutivos (3 ciclos) los contadores permanecen estables
   (o si se alcanzan las 18:00 hs como corte de seguridad), dispara el cierre.
4. Genera el archivo Excel oficial de stock conectando a http://localhost:8090 (#btnExportStock).
5. Calcula los valores de stock (unidades y % ocupación) y renderiza la tabla con los
   colores corporativos exactos de la planilla.
6. Envía el correo vía SMTP con el archivo adjunto a la lista de destinatarios.
7. Registra un archivo testigo diario para evitar cualquier reenvío.

Uso:
    python cierre_jornada.py            # Ejecución automática normal (vigila y envía si corresponde)
    python cierre_jornada.py --force    # Fuerza el envío inmediato sin esperar inactividad ni horario
    python cierre_jornada.py --test     # Muestra datos y genera HTML/Excel sin enviar correo
    python cierre_jornada.py --force --to usuario@friggorina.com  # Fuerza envío a destinatario puntual
"""
import os, sys, json, time, datetime, logging, smtplib, mimetypes
from email.message import EmailMessage

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')

# Garantizar que Playwright encuentre Chromium incluso bajo SYSTEM
if 'PLAYWRIGHT_BROWSERS_PATH' not in os.environ:
    os.environ['PLAYWRIGHT_BROWSERS_PATH'] = r'C:\Users\gorinahostadmin\AppData\Local\ms-playwright'

CAPACITIES = {
    'trv': 25200,
    'crane': 3960
}


def setup_log():
    logs_dir = os.path.join(BASE_DIR, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(levelname)-7s %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(os.path.join(logs_dir, 'cierre_jornada.log'), encoding='utf-8'),
        ],
    )


def load_cfg():
    with open(CONFIG_PATH, encoding='utf-8-sig') as f:
        return json.load(f)


def load_destinatarios(override_to=None):
    if override_to:
        return [override_to]
    candidates = [
        os.path.join(BASE_DIR, 'destinatarios.txt'),
        os.path.join(os.path.dirname(BASE_DIR), 'destinatarios.txt'),
        r'D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\destinatarios.txt'
    ]
    for cand in candidates:
        cand = os.path.abspath(cand)
        if os.path.exists(cand):
            lst = []
            for line in open(cand, encoding='utf-8', errors='ignore'):
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                if ',' in line:
                    line = line.split(',')[0].strip()
                if '@' in line:
                    lst.append(line)
            if lst:
                return lst
    return ['informes.ciclo3@friggorina.com']



def export_stock_excel(out_path):
    """Descarga el Excel oficial de stock conectando a la SPA de Stock.Almacen en el puerto 8090."""
    from playwright.sync_api import sync_playwright
    url = "http://localhost:8090"
    logging.info("Descargando Excel oficial de Stock desde %s...", url)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(accept_downloads=True)
        page = ctx.new_page()
        page.goto(url, timeout=30000)
        page.wait_for_selector("#btnExportStock", timeout=15000)
        time.sleep(2)
        with page.expect_download(timeout=30000) as dl_info:
            page.click("#btnExportStock")
        dl = dl_info.value
        dl.save_as(out_path)
        browser.close()
    logging.info("Excel generado exitosamente: %s (%d bytes)", out_path, os.path.getsize(out_path))
    return out_path


def send_cierre_email(cfg, subject, html_body, excel_path, to_list):
    mail_cfg = cfg.get('mail', {})
    host = mail_cfg.get('smtp_host', '192.168.0.234')
    port = int(mail_cfg.get('smtp_port', 25))
    user = mail_cfg.get('smtp_user')
    pwd = mail_cfg.get('smtp_pass')
    frm = mail_cfg.get('from', 'ciclo3@friggorina.com')

    msg = EmailMessage()
    msg['From'] = frm
    msg['To'] = ", ".join(to_list)
    msg['Subject'] = subject

    # Contenido principal HTML
    msg.set_content("Estimados, se adjunta el reporte y stock del cierre diario de operaciones de Ciclo 3.")
    msg.add_alternative(html_body, subtype='html')

    # Adjuntar archivo Excel
    if excel_path and os.path.exists(excel_path):
        ctype, _ = mimetypes.guess_type(excel_path)
        maintype, subtype = (ctype or 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet').split('/', 1)
        with open(excel_path, 'rb') as f:
            msg.add_attachment(
                f.read(),
                maintype=maintype,
                subtype=subtype,
                filename=os.path.basename(excel_path)
            )

    logging.info("Enviando correo de cierre a: %s (SMTP %s:%d)...", ", ".join(to_list), host, port)
    with smtplib.SMTP(host, port, timeout=30) as server:
        if user and pwd:
            server.login(user, pwd)
        server.send_message(msg)
    logging.info("Correo de cierre enviado exitosamente.")
    return True


def check_inactivity(today_str, trv_inn, trv_out, crane_inn, crane_out):
    """
    Registra el estado en cierre_tracker.json.
    Retorna True si lleva 3 o más ciclos consecutivos (15 min) sin cambios en ningún contador.
    """
    logs_dir = os.path.join(BASE_DIR, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    tracker_path = os.path.join(logs_dir, 'cierre_tracker.json')
    now_str = datetime.datetime.now().strftime('%H:%M:%S')

    tracker = {}
    if os.path.exists(tracker_path):
        try:
            with open(tracker_path, encoding='utf-8') as f:
                tracker = json.load(f)
        except Exception:
            tracker = {}

    prev_date = tracker.get('date')
    if prev_date != today_str:
        # Nuevo día: reinicializar tracker
        tracker = {
            'date': today_str,
            'last_check': now_str,
            'trv_inn': trv_inn,
            'trv_out': trv_out,
            'crane_inn': crane_inn,
            'crane_out': crane_out,
            'stable_cycles': 1
        }
    else:
        # Mismo día: comparar contadores
        is_same = (
            tracker.get('trv_inn') == trv_inn and
            tracker.get('trv_out') == trv_out and
            tracker.get('crane_inn') == crane_inn and
            tracker.get('crane_out') == crane_out
        )
        if is_same:
            tracker['stable_cycles'] = tracker.get('stable_cycles', 0) + 1
        else:
            tracker['stable_cycles'] = 1
        tracker['last_check'] = now_str
        tracker['trv_inn'] = trv_inn
        tracker['trv_out'] = trv_out
        tracker['crane_inn'] = crane_inn
        tracker['crane_out'] = crane_out

    with open(tracker_path, 'w', encoding='utf-8') as f:
        json.dump(tracker, f, indent=2)

    stable = tracker.get('stable_cycles', 1)
    logging.info("Vigilancia cierre: ciclos estables = %d/3 (TRV: %s/%s | Crane: %s/%s)",
                 stable, trv_inn, trv_out, crane_inn, crane_out)
    return stable >= 3


def main():
    setup_log()
    args = sys.argv[1:]
    force = '--force' in args
    test_mode = '--test' in args
    dry_run = '--dry-run' in args

    override_to = None
    if '--to' in args:
        idx = args.index('--to')
        if idx + 1 < len(args):
            override_to = args[idx + 1]

    now = datetime.datetime.now()
    today_str = now.date().isoformat()
    logs_dir = os.path.join(BASE_DIR, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    enviado_flag = os.path.join(logs_dir, f'cierre_enviado_{today_str}.json')

    # 1. Verificar si ya se envió hoy
    if os.path.exists(enviado_flag) and not force:
        logging.info("Cierre diario ya enviado hoy (%s). Nada pendiente.", today_str)
        return 0

    # 2. Verificar día hábil (lunes a viernes: 0 a 4)
    if now.weekday() >= 5 and not force:
        logging.info("Fin de semana (día %d). No corresponde cierre automático.", now.weekday())
        return 0

    # 3. Verificar ventana horaria (>= 16:00 hs)
    if (now.hour < 16 or (now.hour == 16 and now.minute < 0)) and not force:
        # Aún no es hora de vigilancia
        return 0

    cfg = load_cfg()
    out_path = cfg.get('out_path', '../tablero_v4/datos.json')
    if not os.path.isabs(out_path):
        out_path = os.path.normpath(os.path.join(BASE_DIR, out_path))

    if not os.path.exists(out_path):
        logging.error("No se encontró datos.json en %s", out_path)
        return 1

    with open(out_path, encoding='utf-8-sig') as f:
        datos = json.load(f)

    # Obtener registros de hoy
    trv_rec = next((r for r in datos.get('trv', []) if r['k'] == today_str), None)
    crane_rec = next((r for r in datos.get('crane', []) if r['k'] == today_str), None)

    if not trv_rec and not crane_rec and not force:
        logging.info("Sin registros de producción para hoy (%s).", today_str)
        return 0

    trv_inn = int(round(trv_rec.get('inn', 0))) if trv_rec else 0
    trv_out = int(round(trv_rec.get('out', 0))) if trv_rec else 0
    trv_occ = float(trv_rec.get('occ', 0.0)) if (trv_rec and trv_rec.get('occ') is not None) else 0.0

    crane_inn = int(round(crane_rec.get('inn', 0))) if crane_rec else 0
    crane_out = int(round(crane_rec.get('out', 0))) if crane_rec else 0
    crane_occ = float(crane_rec.get('occ', 0.0)) if (crane_rec and crane_rec.get('occ') is not None) else 0.0

    # Si ambos sistemas tienen 0 ingresos y 0 salidas, no hubo actividad
    if trv_inn == 0 and trv_out == 0 and crane_inn == 0 and crane_out == 0 and not force:
        logging.info("Contadores en cero para hoy (%s). No se dispara cierre.", today_str)
        return 0

    # 4. Verificar regla de inactividad (o corte forzoso por hora >= 18:00)
    is_inactive = check_inactivity(today_str, trv_inn, trv_out, crane_inn, crane_out)
    is_hard_cutoff = (now.hour >= 18)

    if not is_inactive and not is_hard_cutoff and not force:
        logging.info("Producción aún en actividad. Se continuará monitoreando.")
        return 0

    if is_hard_cutoff and not is_inactive:
        logging.warning("Alcanzada hora de corte (18:00 hs). Se procede al cierre definitivo.")

    # 5. Calcular valores de unidades e inventario
    trv_unidades = int(round(CAPACITIES['trv'] * (trv_occ / 100.0)))
    trv_occ_fmt = f"{trv_occ:.2f}%".replace('.', ',')
    trv_unidades_fmt = f"{trv_unidades} CAJAS"

    crane_unidades = int(round(CAPACITIES['crane'] * (crane_occ / 100.0)))
    crane_occ_fmt = f"{crane_occ:.2f}%".replace('.', ',')
    crane_unidades_fmt = f"{crane_unidades} PALETS"

    # Formato Asunto: Ciclo 3 - Stock y Operaciones del D/MM (ej: 7/09)
    subject = f"Ciclo 3 - Stock y Operaciones del {now.day}/{now.month:02d}"

    # 6. Descargar Excel de Stock Almacén
    excel_filename = f"STOCK_ALMACEN_{today_str}.xlsx"
    excel_path = os.path.join(logs_dir, excel_filename)
    try:
        export_stock_excel(excel_path)
    except Exception as e:
        logging.error("No se pudo descargar el Excel de Stock desde puerto 8090: %s", e)
        excel_path = None

    # 7. Renderizar plantilla HTML idéntica al diseño solicitado
    html_body = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
</head>
<body style="font-family: Calibri, Arial, Helvetica, sans-serif; font-size: 14px; color: #1f1f1f; line-height: 1.5; margin: 15px;">
  <p style="margin-bottom: 12px;">Estimados, buenas tardes.</p>

  <p style="margin-bottom: 12px;">Adjunto excel con el stock del almacén de congelados.</p>

  <p style="margin-bottom: 16px;">Dejo cuadro resumen de ingresos y salidas de TRV y almacén, junto con la capacidad ocupada de los mismos:</p>

  <table style="border-collapse: collapse; font-family: Calibri, Arial, sans-serif; font-size: 13px; text-align: center; margin-top: 10px; margin-bottom: 20px;">
    <thead>
      <tr style="background-color: #D9D9D9; border: 1px solid #000;">
        <th style="padding: 5px 10px; border: 1px solid #000; font-weight: bold; width: 110px;"></th>
        <th style="padding: 5px 10px; border: 1px solid #000; font-weight: bold; width: 65px;">IN</th>
        <th style="padding: 5px 10px; border: 1px solid #000; font-weight: bold; width: 65px;">OUT</th>
        <th style="padding: 5px 10px; border: 1px solid #000; font-weight: bold; width: 110px;">Unidades</th>
        <th style="padding: 5px 10px; border: 1px solid #000; font-weight: bold; width: 85px;">% DEL TOTAL</th>
      </tr>
    </thead>
    <tbody>
      <tr style="border: 1px solid #000;">
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #D9E1F2; font-weight: bold; text-align: left;">TRV1 (Cajas)</td>
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #FCE4D6;">{trv_inn}</td>
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #FCE4D6;">{trv_out}</td>
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #FFFF00; font-weight: bold;">{trv_unidades_fmt}</td>
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #FFFF00; font-weight: bold;">{trv_occ_fmt}</td>
      </tr>
      <tr style="border: 1px solid #000;">
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #D9E1F2; font-weight: bold; text-align: left;">Crane (Palets)</td>
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #FCE4D6;">{crane_inn}</td>
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #FCE4D6;">{crane_out}</td>
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #FFFF00; font-weight: bold;">{crane_unidades_fmt}</td>
        <td style="padding: 5px 10px; border: 1px solid #000; background-color: #FFFF00; font-weight: bold;">{crane_occ_fmt}</td>
      </tr>
    </tbody>
  </table>

  <p style="margin-top: 24px; margin-bottom: 4px;">Saludos cordiales,</p>
  <p style="margin: 0; font-weight: bold; color: #111;">Control de Operaciones — Ciclo 3</p>
  <p style="margin: 0; color: #555;">Frigorífico Gorina</p>

  <p style="font-size: 13px; color: #555; border-top: 1px solid #ccc; padding-top: 10px; margin-top: 25px;">
    <em>Este es un reporte automático generado al cierre de operaciones diarias del Ciclo 3.</em>
  </p>
</body>
</html>
"""

    to_list = load_destinatarios(override_to)

    if test_mode or dry_run:
        logging.info("MODO TEST/DRY-RUN:")
        logging.info("Asunto: %s", subject)
        logging.info("Destinatarios: %s", ", ".join(to_list))
        logging.info("TRV1: In=%d, Out=%d, Unidades=%s, Occ=%s", trv_inn, trv_out, trv_unidades_fmt, trv_occ_fmt)
        logging.info("Crane: In=%d, Out=%d, Unidades=%s, Occ=%s", crane_inn, crane_out, crane_unidades_fmt, crane_occ_fmt)
        logging.info("Excel adjunto: %s", excel_path)
        sample_html = os.path.join(logs_dir, f'muestra_cierre_{today_str}.html')
        with open(sample_html, 'w', encoding='utf-8') as f:
            f.write(html_body)
        logging.info("Muestra HTML guardada en: %s", sample_html)
        return 0

    # 8. Envío efectivo
    ok = send_cierre_email(cfg, subject, html_body, excel_path, to_list)
    if ok:
        registro = {
            'fecha': today_str,
            'hora_envio': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'asunto': subject,
            'destinatarios': to_list,
            'trv': {'in': trv_inn, 'out': trv_out, 'unidades': trv_unidades, 'occ': trv_occ},
            'crane': {'in': crane_inn, 'out': crane_out, 'unidades': crane_unidades, 'occ': crane_occ},
            'excel': excel_path
        }
        with open(enviado_flag, 'w', encoding='utf-8') as f:
            json.dump(registro, f, indent=2)
        logging.info("Cierre diario completado y registrado en %s", enviado_flag)
        return 0
    else:
        logging.error("No se pudo completar el envío del cierre diario.")
        return 1


if __name__ == '__main__':
    sys.exit(main())
