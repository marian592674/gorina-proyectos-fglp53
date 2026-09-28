#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
envio_informe.py — Generacion y envio automatico de Informes Semanal y Mensual (Ciclo 3).

Lanzado al cierre de operaciones de forma coordinada con cierre_jornada.py:
- Semanal: Se dispara el ultimo dia habil de la semana laboral (viernes, o dia anterior si es feriado)
  en el mismo momento que el cierre de operaciones.
- Mensual: Se dispara el ultimo dia habil del mes en curso (o dia anterior si fin de mes cae fin de semana/feriado)
  en el mismo momento que el cierre de operaciones.
"""
import os, sys, json, datetime, smtplib, ssl, time, logging
from email.message import EmailMessage

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')

# Importar modulo de calendario para calculo de dias habiles y feriados
try:
    import calendario_informes
except ImportError:
    sys.path.append(BASE_DIR)
    import calendario_informes

# Asegurar que Playwright encuentre Chromium incluso bajo cuenta SYSTEM de tareas programadas
if 'PLAYWRIGHT_BROWSERS_PATH' not in os.environ:
    os.environ['PLAYWRIGHT_BROWSERS_PATH'] = r'C:\Users\gorinahostadmin\AppData\Local\ms-playwright'

def setup_log():
    logs_dir = os.path.join(BASE_DIR, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(levelname)-7s %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(os.path.join(logs_dir, 'envio_informe.log'), encoding='utf-8'),
        ],
    )

def load_cfg():
    with open(CONFIG_PATH, encoding='utf-8-sig') as f:
        return json.load(f)

def gen_pdf_playwright(period, out_pdf):
    # period: 'week' o 'month'
    from playwright.sync_api import sync_playwright
    url = "http://localhost:8080/dashboard_operaciones.html"
    logging.info("Iniciando Playwright para renderizar PDF periodo '%s' desde %s", period, url)
    os.makedirs(os.path.dirname(os.path.abspath(out_pdf)), exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(accept_downloads=True)
        page = ctx.new_page()
        page.goto(url, wait_until="networkidle", timeout=45000)
        page.wait_for_selector("#detailTable", timeout=20000)
        # Setear periodo
        js_period = 'week' if period == 'week' else 'month'
        page.evaluate(f"() => {{ state.period='{js_period}'; state.anchor=defaultAnchor(); renderPeriod(); }}")
        time.sleep(2)
        # Asegurar que datos estan
        page.wait_for_selector("#detailTable tbody tr", timeout=10000)
        with page.expect_download(timeout=45000) as dl_info:
            page.click("#pdfBtn")
        dl = dl_info.value
        dl.save_as(out_pdf)
        browser.close()
    logging.info("PDF generado correctamente: %s (%d bytes)", out_pdf, os.path.getsize(out_pdf))
    return out_pdf

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

def send_mail(cfg, subject, body, pdf_path, to_list=None, html_body=None):
    import mimetypes, email.utils
    mail = cfg.get('mail', {})
    host = mail.get('smtp_host', '192.168.0.234')
    port = int(mail.get('smtp_port', 25))
    user = mail.get('smtp_user')
    pwd = mail.get('smtp_pass')
    frm = mail.get('from', 'ciclo3@friggorina.com')
    if not to_list:
        to_list = load_destinatarios()
    if not to_list:
        to_list = mail.get('weekly_to') if 'Semanal' in subject else mail.get('monthly_to')
    if not to_list:
        logging.error("No hay destinatarios para enviar el informe.")
        return False
    msg = EmailMessage()
    msg['From'] = f"Control de Operaciones Ciclo 3 <{frm}>"
    msg['To'] = ", ".join(to_list)
    msg['Subject'] = subject
    msg['Date'] = email.utils.formatdate(localtime=True)
    msg['Message-ID'] = email.utils.make_msgid(domain='friggorina.com')
    msg.set_content(body)
    if html_body:
        msg.add_alternative(html_body, subtype='html')

    if pdf_path and os.path.exists(pdf_path):
        ctype, _ = mimetypes.guess_type(pdf_path)
        maintype, subtype = (ctype or 'application/pdf').split('/', 1)
        with open(pdf_path, 'rb') as f:
            msg.add_attachment(f.read(), maintype=maintype, subtype=subtype, filename=os.path.basename(pdf_path))
    logging.info("Conectando a servidor SMTP %s:%d...", host, port)
    s = smtplib.SMTP(host, port, timeout=30)
    s.ehlo()
    if port == 587:
        s.starttls(context=ssl.create_default_context())
        s.ehlo()
    if user and pwd:
        s.login(user, pwd)
    s.send_message(msg)
    s.quit()
    logging.info("Mail enviado con exito: '%s' -> %s (%s, %d bytes)", subject, to_list, os.path.basename(pdf_path), os.path.getsize(pdf_path))
    return True

def enviar_informe_semanal(cfg=None, test_mode=False, override_to=None, date_ref=None, force=False):
    if cfg is None:
        cfg = load_cfg()
    now_date = date_ref or datetime.date.today()
    hoy = now_date.isoformat()
    logs_dir = os.path.join(BASE_DIR, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    flag_path = os.path.join(logs_dir, f'informe_semanal_enviado_{hoy}.json')

    if os.path.exists(flag_path) and not force and not test_mode:
        logging.info("Informe Semanal ya fue enviado hoy (%s). Omitiendo.", hoy)
        return True

    lunes = now_date - datetime.timedelta(days=now_date.weekday())
    viernes = lunes + datetime.timedelta(days=4)
    f_ini = lunes.strftime('%d/%m')
    f_fin = viernes.strftime('%d/%m/%Y')
    rango_sem = f"{lunes.strftime('%d_%m')}-{viernes.strftime('%d_%m')}"
    pdf_name = f"gorina_ciclo3_Semana_{rango_sem}.pdf"
    pdf = os.path.join(os.environ.get('TEMP', r'C:\Temp'), pdf_name)
    subject = cfg.get('mail', {}).get('weekly_subject', f'Ciclo 3 - Informe Semanal ({lunes.strftime("%d/%m")} al {viernes.strftime("%d/%m")})')
    to_list = load_destinatarios(override_to)

    logging.info(">>> Iniciando generacion de Informe Semanal para %s", hoy)
    gen_pdf_playwright('week', pdf)

    text_body = f"""Estimados, buenas tardes.

Se adjunta el Informe Semanal de Operaciones del Ciclo 3 en formato PDF, correspondiente al período comprendido entre el {f_ini} y el {f_fin}.

El reporte incluye el resumen de actividades, gráficos de evolución y detalle diario de:

TRV1 (Cajas): Ingresos, salidas y curvas de ocupación de túnel.
Almacén Congelado (Pallets): Ingresos, salidas y capacidad del almacén Ctto.

Saludos cordiales,

Control de Operaciones — Ciclo 3

Frigorífico Gorina

--
Este es un reporte automático generado al cierre de operaciones de la semana laboral del Ciclo 3. Favor de no responder a este correo. Ante consultas, contactar a Mariano Diaz (mariano.diaz@friggorina.com).
"""

    html_body = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
</head>
<body style="font-family: Calibri, Arial, Helvetica, sans-serif; font-size: 14px; color: #1f1f1f; line-height: 1.5; margin: 15px;">
  <p style="margin-bottom: 12px;">Estimados, buenas tardes.</p>

  <p style="margin-bottom: 12px;">Se adjunta el <strong>Informe Semanal de Operaciones del Ciclo 3</strong> en formato PDF, correspondiente al período comprendido entre el <strong>{f_ini}</strong> y el <strong>{f_fin}</strong>.</p>

  <p style="margin-bottom: 14px;">El reporte incluye el resumen de actividades, gráficos de evolución y detalle diario de:</p>
  <ul style="margin-top: 0; margin-bottom: 18px; padding-left: 22px; color: #333;">
    <li style="margin-bottom: 4px;"><strong>TRV1 (Cajas)</strong>: Ingresos, salidas y curvas de ocupación de túnel.</li>
    <li style="margin-bottom: 4px;"><strong>Almacén Congelado (Pallets)</strong>: Ingresos, salidas y capacidad del almacén Ctto.</li>
  </ul>

  <p style="margin-top: 24px; margin-bottom: 4px;">Saludos cordiales,</p>
  <p style="margin: 0; font-weight: bold; color: #111;">Control de Operaciones — Ciclo 3</p>
  <p style="margin: 0; color: #555;">Frigorífico Gorina</p>

  <p style="font-size: 12px; color: #555; border-top: 1px solid #ccc; padding-top: 10px; margin-top: 25px;">
    <em>Este es un reporte automático generado al cierre de operaciones de la semana laboral del Ciclo 3. Favor de no responder a este correo. Ante consultas, contactar a Mariano Diaz (mariano.diaz@friggorina.com).</em>
  </p>
</body>
</html>
"""

    if test_mode:
        logging.info("[TEST MODE] Informe Semanal generado en %s. No se envia correo.", pdf)
        return True

    ok = send_mail(cfg, subject, text_body, pdf, to_list, html_body=html_body)
    if ok:
        registro = {
            'fecha': hoy,
            'hora_envio': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'tipo': 'semanal',
            'asunto': subject,
            'destinatarios': to_list,
            'pdf': pdf
        }
        with open(flag_path, 'w', encoding='utf-8') as f:
            json.dump(registro, f, indent=2)
        logging.info("Informe Semanal completado y registrado en %s", flag_path)
        return True
    return False

def enviar_informe_mensual(cfg=None, test_mode=False, override_to=None, date_ref=None, force=False):
    if cfg is None:
        cfg = load_cfg()
    now_date = date_ref or datetime.date.today()
    hoy = now_date.isoformat()
    periodo_mes = f"{now_date.year}-{now_date.month:02d}"
    MESESL = ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre']
    mes_nombre = MESESL[now_date.month - 1]
    periodo_fmt = f"{mes_nombre} {now_date.year}"
    logs_dir = os.path.join(BASE_DIR, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    flag_path = os.path.join(logs_dir, f'informe_mensual_enviado_{periodo_mes}.json')

    if os.path.exists(flag_path) and not force and not test_mode:
        logging.info("Informe Mensual del periodo %s ya fue enviado. Omitiendo.", periodo_mes)
        return True

    pdf_name = f"gorina_ciclo3_Mes_{now_date.month:02d}_{now_date.year}.pdf"
    pdf = os.path.join(os.environ.get('TEMP', r'C:\Temp'), pdf_name)
    subject = cfg.get('mail', {}).get('monthly_subject', f'Ciclo 3 - Informe Mensual ({periodo_fmt})')
    to_list = load_destinatarios(override_to)

    logging.info(">>> Iniciando generacion de Informe Mensual para periodo %s (fecha %s)", periodo_mes, hoy)
    gen_pdf_playwright('month', pdf)

    text_body = f"""Estimados, buenas tardes.

Se adjunta el Informe Mensual de Operaciones del Ciclo 3 en formato PDF, correspondiente al período {periodo_fmt}.

El reporte incluye el resumen de actividades, gráficos de evolución y detalle día por día de:

TRV1 (Cajas): Ingresos, salidas y curvas de ocupación de túnel.
Almacén Congelado (Pallets): Ingresos, salidas y capacidad del almacén Ctto.

Saludos cordiales,

Control de Operaciones — Ciclo 3

Frigorífico Gorina

--
Este es un reporte automático generado al cierre mensual de operaciones del Ciclo 3. Favor de no responder a este correo. Ante consultas, contactar a Mariano Diaz (mariano.diaz@friggorina.com).
"""

    html_body = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
</head>
<body style="font-family: Calibri, Arial, Helvetica, sans-serif; font-size: 14px; color: #1f1f1f; line-height: 1.5; margin: 15px;">
  <p style="margin-bottom: 12px;">Estimados, buenas tardes.</p>

  <p style="margin-bottom: 12px;">Se adjunta el <strong>Informe Mensual de Operaciones del Ciclo 3</strong> en formato PDF, correspondiente al período <strong>{periodo_fmt}</strong>.</p>

  <p style="margin-bottom: 14px;">El reporte incluye el resumen de actividades, gráficos de evolución y detalle día por día de:</p>
  <ul style="margin-top: 0; margin-bottom: 18px; padding-left: 22px; color: #333;">
    <li style="margin-bottom: 4px;"><strong>TRV1 (Cajas)</strong>: Ingresos, salidas y curvas de ocupación de túnel.</li>
    <li style="margin-bottom: 4px;"><strong>Almacén Congelado (Pallets)</strong>: Ingresos, salidas y capacidad del almacén Ctto.</li>
  </ul>

  <p style="margin-top: 24px; margin-bottom: 4px;">Saludos cordiales,</p>
  <p style="margin: 0; font-weight: bold; color: #111;">Control de Operaciones — Ciclo 3</p>
  <p style="margin: 0; color: #555;">Frigorífico Gorina</p>

  <p style="font-size: 12px; color: #555; border-top: 1px solid #ccc; padding-top: 10px; margin-top: 25px;">
    <em>Este es un reporte automático generado al cierre mensual de operaciones del Ciclo 3. Favor de no responder a este correo. Ante consultas, contactar a Mariano Diaz (mariano.diaz@friggorina.com).</em>
  </p>
</body>
</html>
"""

    if test_mode:
        logging.info("[TEST MODE] Informe Mensual generado en %s. No se envia correo.", pdf)
        return True

    ok = send_mail(cfg, subject, text_body, pdf, to_list, html_body=html_body)
    if ok:
        registro = {
            'fecha': hoy,
            'periodo': periodo_mes,
            'hora_envio': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'tipo': 'mensual',
            'asunto': subject,
            'destinatarios': to_list,
            'pdf': pdf
        }
        with open(flag_path, 'w', encoding='utf-8') as f:
            json.dump(registro, f, indent=2)
        logging.info("Informe Mensual completado y registrado en %s", flag_path)
        return True
    return False

def verificar_y_enviar_informes(cfg=None, d=None, test_mode=False, override_to=None, force=False):
    """
    Evalua el calendario (dias habiles y feriados) y dispara los informes correspondientes a la fecha.
    """
    if cfg is None:
        cfg = load_cfg()
    if d is None:
        d = datetime.date.today()

    disp = calendario_informes.evaluar_disparo_informes(d, BASE_DIR)
    logging.info("Evaluacion calendario para informes (%s): Semanal=%s | Mensual=%s (Habil=%s, Feriado=%s)",
                 disp['fecha'], disp['corresponde_semanal'], disp['corresponde_mensual'],
                 disp['es_habil'], disp['es_feriado'])

    res = {'semanal': None, 'mensual': None}
    if disp['corresponde_semanal'] or force:
        res['semanal'] = enviar_informe_semanal(cfg, test_mode=test_mode, override_to=override_to, date_ref=d, force=force)
    else:
        logging.info("No corresponde Informe Semanal para hoy (%s).", disp['fecha'])

    if disp['corresponde_mensual'] or force:
        res['mensual'] = enviar_informe_mensual(cfg, test_mode=test_mode, override_to=override_to, date_ref=d, force=force)
    else:
        logging.info("No corresponde Informe Mensual para hoy (%s).", disp['fecha'])

    return res

if __name__ == '__main__':
    setup_log()
    cfg = load_cfg()
    args = sys.argv[1:]
    is_weekly = '--weekly' in args
    is_monthly = '--monthly' in args
    is_auto = '--auto' in args or (not is_weekly and not is_monthly and not '--test' in args)
    test_mode = '--test' in args
    force = '--force' in args

    override_to = None
    if '--to' in args:
        idx = args.index('--to')
        if idx + 1 < len(args):
            override_to = args[idx + 1]

    if is_weekly:
        enviar_informe_semanal(cfg, test_mode=test_mode, override_to=override_to, force=force)
    elif is_monthly:
        enviar_informe_mensual(cfg, test_mode=test_mode, override_to=override_to, force=force)
    else:
        # Modo automatico por calendario
        verificar_y_enviar_informes(cfg, test_mode=test_mode, override_to=override_to, force=force)
