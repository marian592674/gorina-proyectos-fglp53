#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
migrar_p005.py — Inicialización y migración de datos a MySQL p005.supervisor.general.
"""
import os, sys, json, re, datetime

# Usar driver pymysql o mysql.connector si existe, o generar SQL batch
HISTORIAL_JSON = r"D:\PROYECTOS\P001.Dashboard.Ciclo.3\LAB\colector_test\logs\historial_alertas.json"
SQL_OUTPUT = r"D:\PROYECTOS\P005.Supervisor.General\seed_data.sql"

SERVICIOS = [
    {
        "codigo": "p001_dashboard_80",
        "nombre": "Acceso Red Corporativa (tablero.ciclo3)",
        "proyecto": "P001.Dashboard.Ciclo.3",
        "tipo": "HTTP",
        "url_o_tarea": "http://localhost/tablero.ciclo3/dashboard_operaciones.html",
        "puerto": 80,
        "vigilante_cmd": "iisreset /noforce"
    },
    {
        "codigo": "p001_dashboard_8080",
        "nombre": "LAB Dashboard (Puerto 8080)",
        "proyecto": "P001.Dashboard.Ciclo.3",
        "tipo": "HTTP",
        "url_o_tarea": "http://localhost:8080/dashboard_operaciones.html",
        "puerto": 8080,
        "vigilante_cmd": "iisreset /noforce"
    },
    {
        "codigo": "p001_tarea_colector",
        "nombre": "Tarea Programada Colector LAB",
        "proyecto": "P001.Dashboard.Ciclo.3",
        "tipo": "TASK_WINDOWS",
        "url_o_tarea": "Gorina LAB - Colector datos",
        "puerto": None,
        "vigilante_cmd": "Start-ScheduledTask -TaskName 'Gorina LAB - Colector datos'"
    },
    {
        "codigo": "p002_stock_8090",
        "nombre": "Stock Almacén API/SPA (Puerto 8090)",
        "proyecto": "P002.Stock.Almacen.Congelado",
        "tipo": "HTTP",
        "url_o_tarea": "http://localhost:8090/stock_almacen/ping",
        "puerto": 8090,
        "vigilante_cmd": "Start-ScheduledTask -TaskName 'Gorina - Stock Almacen 24-7'"
    },
    {
        "codigo": "p002_tarea_stock",
        "nombre": "Tarea Windows Stock Almacén 24-7",
        "proyecto": "P002.Stock.Almacen.Congelado",
        "tipo": "TASK_WINDOWS",
        "url_o_tarea": "Gorina - Stock Almacen 24-7",
        "puerto": None,
        "vigilante_cmd": "Start-ScheduledTask -TaskName 'Gorina - Stock Almacen 24-7'"
    },
    {
        "codigo": "p003_pick_5000",
        "nombre": "GorinaPick API Picking (Puerto 5000)",
        "proyecto": "P003.Pick.Materiales.Insumos",
        "tipo": "HTTP",
        "url_o_tarea": "http://localhost:5000/api/ping",
        "puerto": 5000,
        "vigilante_cmd": "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\\PROYECTOS\\P003.Pick.Materiales.Insumos\\servidor\\vigilante_gorina_api.ps1"
    },
    {
        "codigo": "p003_tarea_pick",
        "nombre": "Tarea Windows GorinaPick API 24-7",
        "proyecto": "P003.Pick.Materiales.Insumos",
        "tipo": "TASK_WINDOWS",
        "url_o_tarea": "Gorina - GorinaPick API 24-7",
        "puerto": None,
        "vigilante_cmd": "Start-ScheduledTask -TaskName 'Gorina - GorinaPick API 24-7'"
    },
    {
        "codigo": "p004_carniceria_8765",
        "nombre": "Tablero Carnicería Gorina (Puerto 8765)",
        "proyecto": "P004.Carniceria.Tablero",
        "tipo": "HTTP",
        "url_o_tarea": "http://localhost:8765/api/estado",
        "puerto": 8765,
        "vigilante_cmd": "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\\PROYECTOS\\P004.Carniceria.Tablero\\vigilante_carniceria.ps1"
    },
    {
        "codigo": "p004_tarea_carniceria",
        "nombre": "Tarea Windows Carniceria Tablero 24-7",
        "proyecto": "P004.Carniceria.Tablero",
        "tipo": "TASK_WINDOWS",
        "url_o_tarea": "Gorina - Carniceria Tablero 24-7",
        "puerto": None,
        "vigilante_cmd": "Start-ScheduledTask -TaskName 'Gorina - Carniceria Tablero 24-7'"
    }
]

CONFIG = [
    ("intervalo_segundos", "60", "Frecuencia de chequeo del supervisor"),
    ("alertas_activadas", "1", "1 para enviar alertas por correo, 0 para pausar"),
    ("smtp_server", "192.168.0.234", "Servidor Relay SMTP Corporativo"),
    ("smtp_port", "25", "Puerto SMTP"),
    ("smtp_from", "alertas-sistemas@friggorina.com", "Remitente de alertas"),
    ("smtp_to", "sistemas@friggorina.com", "Destinatarios principales separados por coma"),
    ("cooldown_minutos", "15", "Minutos de espera entre alertas repetidas del mismo servicio")
]

def parse_date(date_str):
    # formats: "28/09 14:57:17" or "22/09/2026 09:50:01"
    try:
        if len(date_str.split('/')) == 2:
            # 28/09 14:57:17 -> add 2026
            parts = date_str.split(' ')
            d, m = parts[0].split('/')
            h, mi, s = parts[1].split(':')
            return f"2026-{int(m):02d}-{int(d):02d} {h}:{mi}:{s}"
        elif len(date_str.split('/')) == 3:
            # 22/09/2026 09:50:01
            parts = date_str.split(' ')
            d, m, y = parts[0].split('/')
            h, mi, s = parts[1].split(':')
            return f"{y}-{int(m):02d}-{int(d):02d} {h}:{mi}:{s}"
    except Exception:
        pass
    return datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

def escape_sql(val):
    if val is None:
        return "NULL"
    s = str(val).replace("\\", "\\\\").replace("'", "''")
    return f"'{s}'"

def main():
    lines = ["USE `p005.supervisor.general`;\n"]
    
    # Insert or update servicios
    for s in SERVICIOS:
        puerto_val = str(s['puerto']) if s['puerto'] is not None else "NULL"
        lines.append(
            f"INSERT INTO `servicios` (`codigo`, `nombre`, `proyecto`, `tipo`, `url_o_tarea`, `puerto`, `activo`, `estado_actual`, `ultimo_check`, `ultimo_ok`, `latencia_ms`, `mensaje_estado`, `vigilante_cmd`) "
            f"VALUES ({escape_sql(s['codigo'])}, {escape_sql(s['nombre'])}, {escape_sql(s['proyecto'])}, {escape_sql(s['tipo'])}, {escape_sql(s['url_o_tarea'])}, {puerto_val}, 1, 'OK', NOW(), NOW(), 0, 'Inicializado', {escape_sql(s['vigilante_cmd'])}) "
            f"ON DUPLICATE KEY UPDATE `nombre`=VALUES(`nombre`), `proyecto`=VALUES(`proyecto`), `tipo`=VALUES(`tipo`), `url_o_tarea`=VALUES(`url_o_tarea`), `puerto`=VALUES(`puerto`), `vigilante_cmd`=VALUES(`vigilante_cmd`);\n"
        )
        
    # Insert or update configuracion
    for k, v, desc in CONFIG:
        lines.append(
            f"INSERT INTO `configuracion` (`clave`, `valor`, `descripcion`) VALUES ({escape_sql(k)}, {escape_sql(v)}, {escape_sql(desc)}) "
            f"ON DUPLICATE KEY UPDATE `valor`=VALUES(`valor`), `descripcion`=VALUES(`descripcion`);\n"
        )
        
    # Import historical incidents
    if os.path.exists(HISTORIAL_JSON):
        with open(HISTORIAL_JSON, encoding='utf-8') as f:
            hist = json.load(f)
            
        for h in hist:
            fecha_str = parse_date(h.get('fecha', ''))
            tipo = h.get('tipo', 'ALERTA')
            servicio = h.get('servicio', 'General')
            # map to service code if possible
            srv_code = "general"
            for s in SERVICIOS:
                if s['nombre'].lower() in servicio.lower() or servicio.lower() in s['nombre'].lower():
                    srv_code = s['codigo']
                    break
            if 'stock' in servicio.lower():
                srv_code = 'p002_stock_8090'
            elif 'red corporativa' in servicio.lower() or 'tablero.ciclo3' in servicio.lower():
                srv_code = 'p001_dashboard_80'
            elif 'infraestructura' in servicio.lower():
                srv_code = 'p001_dashboard_8080'
                
            detalle = h.get('detalle', '')
            asunto = h.get('asunto', '')
            destinatarios = ", ".join(h.get('destinatarios', [])) if isinstance(h.get('destinatarios'), list) else str(h.get('destinatarios', ''))
            estado_envio = h.get('estado', 'Enviado OK')
            
            lines.append(
                f"INSERT INTO `incidentes` (`fecha_inicio`, `servicio_codigo`, `tipo_evento`, `detalle`, `asunto`, `destinatarios`, `estado_envio`, `creado_el`) "
                f"VALUES ({escape_sql(fecha_str)}, {escape_sql(srv_code)}, {escape_sql(tipo)}, {escape_sql(detalle)}, {escape_sql(asunto)}, {escape_sql(destinatarios)}, {escape_sql(estado_envio)}, {escape_sql(fecha_str)});\n"
            )
            
    with open(SQL_OUTPUT, 'w', encoding='utf-8') as f:
        f.writelines(lines)
        
    print(f"Archivo generado con éxito en {SQL_OUTPUT} con {len(lines)} sentencias SQL.")

if __name__ == '__main__':
    main()
