#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os, sys, json, datetime, smtplib, ssl, time, logging
from email.message import EmailMessage

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')

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
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(accept_downloads=True)
        page = ctx.new_page()
        page.goto(url, wait_until="networkidle", timeout=45000)
        page.wait_for_selector("#detailTable", timeout=20000)
        # setear periodo
        js_period = 'week' if period == 'week' else 'month'
        page.evaluate(f"() => {{ state.period='{js_period}'; state.anchor=defaultAnchor(); renderPeriod(); }}")
        time.sleep(2)
        # asegurar que datos estan
        page.wait_for_selector("#detailTable tbody tr", timeout=10000)
        with page.expect_download(timeout=45000) as dl_info:
            page.click("#pdfBtn")
        dl = dl_info.value
        dl.save_as(out_pdf)
        browser.close()
    logging.info("PDF generado correctamente: %s (%d bytes)", out_pdf, os.path.getsize(out_pdf))
    return out_pdf

def load_destinatarios():
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
    return None

def send_mail(cfg, subject, body, pdf_path):
    import mimetypes
    mail = cfg.get('mail', {})
    host = mail.get('smtp_host', '192.168.0.234')
    port = int(mail.get('smtp_port', 25))
    user = mail.get('smtp_user')
    pwd = mail.get('smtp_pass')
    frm = mail.get('from', 'ciclo3@friggorina.com')
    to_list = load_destinatarios()
    if not to_list:
        to_list = mail.get('weekly_to') if 'Semanal' in subject else mail.get('monthly_to')
    if not to_list:
        logging.error("No hay destinatarios para enviar el informe.")
        return False
    msg = EmailMessage()
    msg['From'] = frm
    msg['To'] = ", ".join(to_list)
    msg['Subject'] = subject
    msg.set_content(body)
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

if __name__ == '__main__':
    setup_log()
    cfg = load_cfg()
    is_weekly = '--weekly' in sys.argv
    is_monthly = '--monthly' in sys.argv
    is_test = '--test' in sys.argv
    if is_monthly and not is_test:
        today = datetime.date.today()
        if today.day != 1:
            logging.info("Hoy es %s (no es dia 1), no corresponde enviar mensual.", today)
            sys.exit(0)
    hoy = datetime.date.today().isoformat()
    if is_weekly or is_test:
        pdf_name = f"Informe_Semanal_Ciclo3_{hoy}.pdf"
        pdf = os.path.join(os.environ.get('TEMP', 'C:\\Temp'), pdf_name)
        gen_pdf_playwright('week', pdf)
        body = '''Este es un envío automático programado, favor de no responder el mismo.

En caso de consultas contactar a Diaz Mariano al mail mariano.diaz@friggorina.com o a su celular.

Gracias!

Saludos.-'''
        subject = cfg.get('mail', {}).get('weekly_subject', 'Informe Semanal Ciclo 3')
        send_mail(cfg, subject, body, pdf)
    elif is_monthly:
        pdf_name = f"Informe_Mensual_Ciclo3_{hoy}.pdf"
        pdf = os.path.join(os.environ.get('TEMP', 'C:\\Temp'), pdf_name)
        gen_pdf_playwright('month', pdf)
        body = '''Este es un envío automático programado, favor de no responder el mismo.

En caso de consultas contactar a Diaz Mariano al mail mariano.diaz@friggorina.com o a su celular.

Gracias!

Saludos.-'''
        subject = cfg.get('mail', {}).get('monthly_subject', 'Informe Mensual Ciclo 3')
        send_mail(cfg, subject, body, pdf)
    else:
        print("Uso: --weekly | --monthly | --test")
