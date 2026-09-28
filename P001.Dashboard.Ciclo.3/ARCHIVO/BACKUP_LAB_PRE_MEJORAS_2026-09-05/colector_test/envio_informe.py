#!/usr/bin/env python3
import os, sys, json, datetime, smtplib, ssl, time
from email.message import EmailMessage

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')

def load_cfg():
    import json
    with open(CONFIG_PATH, encoding='utf-8-sig') as f:
        return json.load(f)

def gen_pdf_playwright(period, out_pdf):
    # period: 'week' o 'month'
    from playwright.sync_api import sync_playwright
    url="http://localhost:8080/dashboard_operaciones.html"
    with sync_playwright() as p:
        browser=p.chromium.launch(headless=True)
        ctx=browser.new_context(accept_downloads=True)
        page=ctx.new_page()
        page.goto(url, wait_until="networkidle", timeout=45000)
        page.wait_for_selector("#detailTable", timeout=20000)
        # setear periodo
        js_period = 'week' if period=='week' else 'month'
        page.evaluate(f"() => {{ state.period='{js_period}'; state.anchor=defaultAnchor(); renderPeriod(); }}")
        time.sleep(2)
        # asegurar que datos estan
        page.wait_for_selector("#detailTable tbody tr", timeout=10000)
        with page.expect_download(timeout=45000) as dl_info:
            page.click("#pdfBtn")
        dl=dl_info.value
        dl.save_as(out_pdf)
        browser.close()
    return out_pdf

def load_destinatarios():
    txt=os.path.join(BASE_DIR, '..', 'destinatarios.txt')
    # fallback si esta en LAB\destinatarios.txt
    alt=os.path.join(os.path.dirname(BASE_DIR), 'destinatarios.txt')
    # BASE_DIR es LAB\colector_test, destinatarios esta en LAB\destinatarios.txt
    p= os.path.join(os.path.dirname(BASE_DIR), 'destinatarios.txt') if os.path.exists(os.path.join(os.path.dirname(BASE_DIR), 'destinatarios.txt')) else txt
    candidates=[os.path.join(BASE_DIR,'..','destinatarios.txt'), os.path.join(os.path.dirname(BASE_DIR),'destinatarios.txt'), r'D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\destinatarios.txt']
    for cand in candidates:
        cand=os.path.abspath(cand)
        if os.path.exists(cand):
            lst=[]
            for line in open(cand,encoding='utf-8',errors='ignore'):
                line=line.strip()
                if not line or line.startswith('#') or line.startswith('['): continue
                # soporta 'mail' o 'mail, comentario'
                if ',' in line: line=line.split(',')[0].strip()
                if '@' in line: lst.append(line)
            if lst: return lst
    return None

def send_mail(cfg, subject, body, pdf_path):
    import smtplib, ssl
    from email.message import EmailMessage
    import mimetypes
    mail=cfg.get('mail',{})
    host=mail.get('smtp_host','smtp.gmail.com')
    port=int(mail.get('smtp_port',587))
    user=mail.get('smtp_user')
    pwd=mail.get('smtp_pass')
    frm=mail.get('from', user)
    to_list=load_destinatarios()
    if not to_list:
        to_list=mail.get('weekly_to') if 'Semanal' in subject else mail.get('monthly_to')
    if not to_list:
        print("No hay destinatarios")
        return
    msg=EmailMessage()
    msg['From']=frm
    msg['To']=", ".join(to_list)
    msg['Subject']=subject
    msg.set_content(body)
    if pdf_path and os.path.exists(pdf_path):
        ctype, _ = mimetypes.guess_type(pdf_path)
        maintype, subtype = (ctype or 'application/pdf').split('/',1)
        with open(pdf_path,'rb') as f:
            msg.add_attachment(f.read(), maintype=maintype, subtype=subtype, filename=os.path.basename(pdf_path))
    s=smtplib.SMTP(host, port, timeout=30)
    s.ehlo()
    if port == 587:
        s.starttls(context=ssl.create_default_context()); s.ehlo()
    if user and pwd:
        s.login(user, pwd)
    s.send_message(msg)
    s.quit()
    print(f"Mail enviado: {subject} -> {to_list} ({os.path.basename(pdf_path)} {os.path.getsize(pdf_path)} bytes)")

if __name__=='__main__':
    cfg=load_cfg()
    is_weekly='--weekly' in sys.argv
    is_monthly='--monthly' in sys.argv
    if is_monthly:
        today=datetime.date.today()
        if today.day != 1:
            print(f"Hoy es {today} no es dia 1, no se envia mensual (mensual es dia 1 06:00)")
            sys.exit(0)
    hoy=datetime.date.today().isoformat()
    if is_weekly:
        pdf_name = f"Informe_Semanal_Ciclo3_{hoy}.pdf"
        pdf=os.path.join(os.environ.get('TEMP','C:\\Temp'), pdf_name)
        gen_pdf_playwright('week', pdf)
        body='''Este es un envío automático programado, favor de no responder el mismo.

En caso de consultas contactar a Diaz Mariano al mail mariano.diaz@friggorina.com o a su celular.

Gracias!

Saludos.-'''
        send_mail(cfg, cfg.get('mail',{}).get('weekly_subject','Informe Semanal Ciclo 3'), body, pdf)
    elif is_monthly:
        pdf_name = f"Informe_Mensual_Ciclo3_{hoy}.pdf"
        pdf=os.path.join(os.environ.get('TEMP','C:\\Temp'), pdf_name)
        gen_pdf_playwright('month', pdf)
        body='''Este es un envío automático programado, favor de no responder el mismo.

En caso de consultas contactar a Diaz Mariano al mail mariano.diaz@friggorina.com o a su celular.

Gracias!

Saludos.-'''
        send_mail(cfg, cfg.get('mail',{}).get('monthly_subject','Informe Mensual Ciclo 3'), body, pdf)
    else:
        print("Uso: --weekly | --monthly")


