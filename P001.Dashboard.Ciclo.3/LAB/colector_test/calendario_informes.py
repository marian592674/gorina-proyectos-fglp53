#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
calendario_informes.py — Utilidad de calculo de dias habiles, feriados y disparos de informes.
"""
import os, json, datetime

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def load_feriados(base_dir=None):
    path = os.path.join(base_dir or BASE_DIR, 'feriados.json')
    if os.path.exists(path):
        try:
            with open(path, encoding='utf-8') as f:
                data = json.load(f)
                return set(data.get('feriados', []))
        except Exception:
            pass
    return set()

def is_dia_habil(d, feriados=None):
    """Lunes a viernes (weekday 0 a 4) y no feriado."""
    if feriados is None:
        feriados = load_feriados()
    return d.weekday() < 5 and d.isoformat() not in feriados

def is_ultimo_habil_semana(d, feriados=None):
    """
    Determina si 'd' es el ultimo dia habil de la semana laboral en curso.
    Si el viernes es habil, el viernes retorna True.
    Si el viernes es feriado, el jueves retorna True (o el dia habil previo).
    """
    if feriados is None:
        feriados = load_feriados()
    if not is_dia_habil(d, feriados):
        return False
    days_left = 6 - d.weekday()  # Dias restantes hasta domingo
    for i in range(1, days_left + 1):
        nxt = d + datetime.timedelta(days=i)
        if is_dia_habil(nxt, feriados):
            return False
    return True

def is_ultimo_habil_mes(d, feriados=None):
    """
    Determina si 'd' es el ultimo dia habil del mes en curso.
    Si el fin de mes es sabado/domingo o feriado, retrocede automaticamente al dia habil previo.
    """
    if feriados is None:
        feriados = load_feriados()
    if not is_dia_habil(d, feriados):
        return False
    nxt = d + datetime.timedelta(days=1)
    while nxt.month == d.month:
        if is_dia_habil(nxt, feriados):
            return False
        nxt += datetime.timedelta(days=1)
    return True

def evaluar_disparo_informes(d=None, base_dir=None):
    """
    Evalua si en la fecha dada corresponde emitir informe semanal y/o mensual.
    """
    if d is None:
        d = datetime.date.today()
    feriados = load_feriados(base_dir)
    es_habil = is_dia_habil(d, feriados)
    corresponde_semanal = is_ultimo_habil_semana(d, feriados)
    corresponde_mensual = is_ultimo_habil_mes(d, feriados)
    return {
        'fecha': d.isoformat(),
        'dia_semana': d.strftime('%A'),
        'es_habil': es_habil,
        'es_feriado': d.isoformat() in feriados,
        'corresponde_semanal': corresponde_semanal,
        'corresponde_mensual': corresponde_mensual
    }

if __name__ == '__main__':
    today = datetime.date.today()
    tomorrow = today + datetime.timedelta(days=1)
    print('HOY:', evaluar_disparo_informes(today))
    print('MANANA:', evaluar_disparo_informes(tomorrow))
