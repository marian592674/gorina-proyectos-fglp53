#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
webrh_reader.py — Lector en tiempo real para Siemens WinCC Unified Runtime (ASUAN Frontmatec).

Extrae los contadores en vivo de la pantalla 'ESTADÍSTICAS - Contadores' en https://192.168.196.36/device/WebRH:
- Túnel 1 (TRV1): ingresos inferiores + superiores, salidas túnel 1
- Túnel 2 (TRV2): ingresos inferiores + superiores, salidas túnel 2
- Turno 1 y Turno 2 (consolida Turno 1 + Turno 2)

Regla de oro:
- Cierra la sesión web de inmediato para liberar el cupo de licencia a los operadores humanos.
- Si la sesión está ocupada por un operador ("maximum number of allowed sessions"),
  no rompe ni reintenta agresivamente: retorna None con advertencia en log.
"""
import os, sys, time, datetime, logging

if 'PLAYWRIGHT_BROWSERS_PATH' not in os.environ:
    os.environ['PLAYWRIGHT_BROWSERS_PATH'] = r'C:\Users\gorinahostadmin\AppData\Local\ms-playwright'

from playwright.sync_api import sync_playwright

logger = logging.getLogger('webrh_reader')



def parse_screen_numbers(elements):
    """
    Mapea elementos de texto por posición en pantalla (x > 1000, rangos de y).
    """
    data = {
        'ing_sup_t1': 0.0,
        'ing_inf_t1': 0.0,
        'ing_sup_t2': 0.0,
        'ing_inf_t2': 0.0,
        'retorno_be': 0.0,
        'salida_diario': 0.0,
        'sal_t1': 0.0,
        'sal_t2': 0.0,
    }
    for el in elements:
        x, y, txt = el.get('x', 0), el.get('y', 0), el.get('text', '')
        try:
            val = float(txt.replace('.', '').replace(',', '.'))
        except (ValueError, AttributeError):
            continue

        if x > 1000:
            if 115 <= y <= 135: data['ing_sup_t1'] = val
            elif 165 <= y <= 185: data['ing_inf_t1'] = val
            elif 215 <= y <= 235: data['ing_sup_t2'] = val
            elif 265 <= y <= 285: data['ing_inf_t2'] = val
            elif 320 <= y <= 340: data['retorno_be'] = val
            elif 405 <= y <= 425: data['salida_diario'] = val
            elif 455 <= y <= 475: data['sal_t1'] = val
            elif 505 <= y <= 525: data['sal_t2'] = val
    return data


def fetch_webrh_today(webrh_cfg):
    """
    Conecta a WebRH de Siemens, extrae Turno 1 y Turno 2 y retorna los totales del día.
    Retorna None si no se puede conectar o si la sesión está ocupada por un operador.
    """
    url = webrh_cfg.get('url', 'https://192.168.196.36/device/WebRH')
    user = webrh_cfg.get('user', 'Ingenieria')
    pwd = webrh_cfg.get('password', 'Inge132!')
    timeout_ms = int(webrh_cfg.get('timeout_ms', 25000))

    today_str = datetime.date.today().isoformat()
    result = None

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(
                headless=True,
                args=['--ignore-certificate-errors', '--no-sandbox', '--disable-gpu']
            )
            context = browser.new_context(
                ignore_https_errors=True,
                viewport={'width': 1366, 'height': 768}
            )
            page = context.new_page()

            try:
                page.goto(url, timeout=timeout_ms)
            except Exception as e:
                logger.warning("WebRH goto timeout o error de red: %s", e)
                browser.close()
                return None

            page.wait_for_timeout(3500)

            # Verificar si las sesiones están llenas
            body_txt = page.inner_text('body') or ''
            if 'maximum number of allowed sessions' in body_txt.lower():
                logger.warning("WebRH: Cupo de sesiones ocupado por un operador humano. Se conservará dato previo/BD.")
                browser.close()
                return None

            # Login en el frame UMC
            login_frame = None
            for f in page.frames:
                try:
                    if f.query_selector('#username'):
                        login_frame = f
                        break
                except Exception:
                    pass

            if not login_frame:
                logger.info("WebRH: Formulario de login no detectado (posible sesión persistente).")
            else:
                try:
                    login_frame.fill('#username', user)
                    login_frame.fill('#password', pwd)
                    page.wait_for_timeout(500)
                    login_frame.click('#loginFormSubmit')
                    page.wait_for_timeout(5000)
                except Exception as e:
                    logger.warning("WebRH error al completar login: %s", e)
                    browser.close()
                    return None

            # Cerrar diálogo de bienvenida si está presente (x=639, y=492)
            try:
                page.mouse.click(639, 492)
                page.wait_for_timeout(1500)
            except Exception:
                pass

            # Clic en ESTADIS. en la barra derecha (x=1255, y=495)
            try:
                page.mouse.click(1255, 495)
                page.wait_for_timeout(3500)
            except Exception as e:
                logger.warning("WebRH error navegando a ESTADIS: %s", e)
                browser.close()
                return None

            # Extraer elementos de texto de la pantalla
            def extract_elements():
                return page.evaluate("""() => {
                    return Array.from(document.querySelectorAll('*'))
                        .filter(el => el.children.length === 0 && (el.innerText || el.textContent || '').trim())
                        .map(el => {
                            let r = el.getBoundingClientRect();
                            return { text: (el.innerText || el.textContent).trim(), x: Math.round(r.x), y: Math.round(r.y) };
                        });
                }""")

            # 1. Asegurar seleccionar "Hoy" en el desplegable de fecha
            try:
                # Clic en el desplegable de fecha (flecha)
                page.mouse.click(975, 32)
                page.wait_for_timeout(600)
                # Clic en la opción "Hoy"
                page.mouse.click(850, 75)
                page.wait_for_timeout(1500)
            except Exception as e:
                logger.warning("WebRH error al seleccionar 'Hoy': %s", e)

            # 2. Asegurar "Turno 1"
            try:
                page.mouse.click(1195, 32)
                page.wait_for_timeout(600)
                page.mouse.click(1114, 63)
                page.wait_for_timeout(1500)
            except Exception as e:
                logger.warning("WebRH error al seleccionar 'Turno 1': %s", e)

            t1_elems = extract_elements()
            t1_data = parse_screen_numbers(t1_elems)

            # 3. Consultar "Turno 2" (únicamente a partir de las 14:00 hs si Turno 2 inicia operaciones)
            t2_data = {
                'ing_sup_t1': 0.0, 'ing_inf_t1': 0.0,
                'ing_sup_t2': 0.0, 'ing_inf_t2': 0.0,
                'retorno_be': 0.0, 'salida_diario': 0.0,
                'sal_t1': 0.0, 'sal_t2': 0.0
            }
            now_h = datetime.datetime.now().hour
            if now_h >= 14:
                try:
                    page.mouse.click(1195, 32)
                    page.wait_for_timeout(800)
                    page.mouse.click(1020, 94)
                    page.wait_for_timeout(1500)
                    t2_elems = extract_elements()
                    t2_data = parse_screen_numbers(t2_elems)

                    # Blindaje contra fallo de conmutación: si Turno 2 repite exactamente los datos de Turno 1,
                    # significa que el desplegable no cambió y sigue mostrando la pantalla de Turno 1.
                    if (t1_data['sal_t1'] > 0 and t2_data['sal_t1'] == t1_data['sal_t1']) or \
                       (t1_data['ing_sup_t1'] > 0 and t2_data['ing_sup_t1'] == t1_data['ing_sup_t1']):
                        logger.warning("WebRH: Detección de fallo al conmutar a Turno 2 (valores idénticos a Turno 1). Se descarta Turno 2 para no duplicar.")
                        t2_data = {
                            'ing_sup_t1': 0.0, 'ing_inf_t1': 0.0,
                            'ing_sup_t2': 0.0, 'ing_inf_t2': 0.0,
                            'retorno_be': 0.0, 'salida_diario': 0.0,
                            'sal_t1': 0.0, 'sal_t2': 0.0
                        }
                except Exception as e:
                    logger.info("WebRH no se pudo alternar a Turno 2 (sin actividad): %s", e)

                # 4. Dejar siempre seleccionado "Turno 1" en pantalla para los operadores humanos
                try:
                    page.mouse.click(1195, 32)
                    page.wait_for_timeout(800)
                    page.mouse.click(1020, 63)
                    page.wait_for_timeout(1000)
                except Exception as e:
                    logger.info("WebRH no se pudo restablecer a Turno 1: %s", e)

            # Consolidar totales diarios (Turno 1 + Turno 2)
            ing_trv1 = (t1_data['ing_sup_t1'] + t1_data['ing_inf_t1']) + (t2_data['ing_sup_t1'] + t2_data['ing_inf_t1'])
            sal_trv1 = t1_data['sal_t1'] + t2_data['sal_t1']

            ing_trv2 = (t1_data['ing_sup_t2'] + t1_data['ing_inf_t2']) + (t2_data['ing_sup_t2'] + t2_data['ing_inf_t2'])
            sal_trv2 = t1_data['sal_t2'] + t2_data['sal_t2']



            result = {
                'k': today_str,
                'trv': {
                    'inn': float(ing_trv1),
                    'out': float(sal_trv1),
                    'occ': None
                },
                'trv2': {
                    'inn': float(ing_trv2),
                    'out': float(sal_trv2),
                    'occ': None
                }
            }
            logger.info("WebRH leído OK: TRV1 (inn=%.1f, out=%.1f) · TRV2 (inn=%.1f, out=%.1f)",
                        ing_trv1, sal_trv1, ing_trv2, sal_trv2)

            # Cierre limpio de sesión
            try:
                page.close()
                context.close()
            except Exception:
                pass
            browser.close()

    except Exception as e:
        logger.error("Error general en WebRH: %s", e)
        return None

    return result


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    cfg = {
        'url': 'https://192.168.196.36/device/WebRH',
        'user': 'Ingenieria',
        'password': 'Inge132!'
    }
    print("Probando fetch_webrh_today...")
    res = fetch_webrh_today(cfg)
    print("Resultado:", res)
