#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generate_manual_html.py — Genera 1_DIAGRAMA_Y_MANUAL.html con:
- Tipografía limpia estándar Segoe UI / Arial
- Header institucional estilizado con degrade rojo Gorina elegante
- Subtítulo con 'Origen de Datos' en lugar de 'Ingesta'
- Todo texto en negro (#111827) con fondos pasteles suaves
"""
import os, base64

LOGO_PATH = r"D:\PROYECTOS\P005.Supervisor.General\Logo Gorina Solo letras.jpg"
HTML_OUTPUT = r"D:\PROYECTOS\P005.Supervisor.General\1_DIAGRAMA_Y_MANUAL.html"

with open(LOGO_PATH, "rb") as f:
    logo_b64 = base64.b64encode(f.read()).decode("utf-8")

html_content = f"""<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mapa de Proyectos y Flujo de Datos — Servidor FGLP53</title>
  <style>
    :root {{
      --gorina-red: #d9001d;
      --gorina-red-dark: #9e0015;
      --gorina-red-light: #e61933;
      --gorina-red-pastel: #fef2f2;
      --gorina-red-border: #fecaca;
      --white: #ffffff;
      --bg: #f8fafc;
      --card-bg: #ffffff;
      --text: #111827;
      --text-muted: #374151;
      --border: #e2e8f0;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: "Segoe UI", -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
      background-color: var(--bg);
      color: #111827;
      line-height: 1.5;
      padding: 24px;
      -webkit-font-smoothing: antialiased;
    }}
    .container {{
      max-width: 1280px;
      margin: 0 auto;
    }}
    header {{
      background: linear-gradient(135deg, #880012 0%, #b80018 35%, #d9001d 70%, #9e0015 100%);
      color: var(--white);
      padding: 20px 28px;
      border-radius: 12px;
      margin-bottom: 24px;
      box-shadow: 0 4px 16px rgba(185, 28, 28, 0.22), 0 1px 3px rgba(0,0,0,0.1);
      display: flex;
      align-items: center;
      gap: 24px;
      border-bottom: 3px solid #6b000e;
    }}
    .logo-container {{
      background: #ffffff;
      padding: 8px 18px;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 2px 8px rgba(0,0,0,0.15);
      flex-shrink: 0;
    }}
    .logo-img {{
      height: 44px;
      width: auto;
      display: block;
    }}
    .header-text h1 {{
      font-family: "Segoe UI", -apple-system, BlinkMacSystemFont, Arial, sans-serif;
      font-size: 25px;
      font-weight: 700;
      letter-spacing: -0.3px;
      margin-bottom: 4px;
      color: #ffffff;
    }}
    .header-text p {{
      color: #ffffff;
      opacity: 0.95;
      font-size: 13.5px;
      font-weight: 400;
    }}
    
    .grid-cards {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
      gap: 20px;
      margin-bottom: 24px;
    }}
    .card {{
      background: var(--card-bg);
      border-radius: 12px;
      padding: 22px;
      border: 1px solid var(--border);
      box-shadow: 0 2px 6px rgba(0,0,0,0.03);
    }}
    .card h2 {{
      font-size: 17px;
      color: #111827;
      font-weight: 700;
      margin-bottom: 14px;
      display: flex;
      align-items: center;
      gap: 8px;
      border-bottom: 2px solid var(--gorina-red-pastel);
      padding-bottom: 8px;
    }}
    
    /* Diagrama SVG */
    .flow-container {{
      background: #ffffff;
      padding: 24px;
      border-radius: 12px;
      border: 1px solid var(--border);
      margin-bottom: 24px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.03);
    }}
    .flow-container h2 {{
      font-size: 18px;
      color: #111827;
      font-weight: 700;
      margin-bottom: 16px;
      border-bottom: 2px solid var(--gorina-red-pastel);
      padding-bottom: 8px;
    }}
    .diagram-svg {{
      width: 100%;
      height: auto;
      display: block;
      margin: 0 auto;
    }}
    
    /* Tablas */
    .table-container {{
      overflow-x: auto;
      background: #fff;
      border-radius: 8px;
      border: 1px solid var(--border);
      margin-top: 10px;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
      color: #111827;
    }}
    th, td {{
      padding: 10px 14px;
      border-bottom: 1px solid var(--border);
      text-align: left;
      vertical-align: middle;
      color: #111827;
    }}
    th {{
      background-color: #fff1f2;
      color: #111827;
      font-weight: 700;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.3px;
    }}
    tr:last-child td {{ border-bottom: none; }}
    tr:hover td {{ background-color: #fff5f5; }}
    
    /* Badges con texto SIEMPRE en negro y fondos pasteles sutiles */
    .badge {{
      display: inline-block;
      padding: 4px 9px;
      border-radius: 5px;
      font-size: 11.5px;
      font-weight: 600;
      font-family: inherit;
      color: #111827 !important;
      border: 1px solid #cbd5e1;
      background-color: #f1f5f9;
    }}
    .badge-on {{ background-color: #ecfdf5; border-color: #a7f3d0; }}
    .badge-off {{ background-color: #fef2f2; border-color: #fecaca; }}
    .badge-db {{ background-color: #fff1f2; border-color: #fecaca; }}
    .badge-net {{ background-color: #f5f3ff; border-color: #ddd6fe; }}
    .badge-iis {{ background-color: #f0f9ff; border-color: #bae6fd; }}

    .url-link {{
      color: #111827;
      text-decoration: underline;
      text-decoration-color: #d9001d;
      font-weight: 600;
      font-family: Consolas, monospace;
      font-size: 12.5px;
    }}
    .url-link:hover {{ color: #d9001d; }}

    .url-sublink {{
      color: #374151;
      text-decoration: none;
      font-size: 11.5px;
      font-family: Consolas, monospace;
      display: block;
      margin-top: 2px;
    }}

    .db-tag {{
      font-family: Consolas, monospace;
      font-size: 11.5px;
      color: #111827;
      font-weight: 600;
      background: #fff1f2;
      padding: 3px 7px;
      border-radius: 4px;
      border: 1px solid #fecaca;
    }}

    .step-box {{
      background: #fafafa;
      border-left: 4px solid #d9001d;
      padding: 12px 14px;
      border-radius: 0 8px 8px 0;
      margin-bottom: 10px;
      font-size: 13px;
      color: #111827;
    }}
    .step-box strong {{ color: #111827; }}

    footer {{
      text-align: center;
      color: #374151;
      font-size: 12px;
      margin-top: 24px;
      padding: 16px;
    }}
  </style>
</head>
<body>
<div class="container">

  <header>
    <div class="logo-container">
      <img src="data:image/jpeg;base64,{logo_b64}" alt="Gorina" class="logo-img">
    </div>
    <div class="header-text">
      <h1>Mapa de Proyectos y Flujo de Datos</h1>
      <p>Origen de Datos, Procesamiento 24/7, Bases de Datos MySQL 8.0 y Accesos Corporativos FGLP53</p>
    </div>
  </header>

  <!-- DIAGRAMA DE FLUJO Y ARQUITECTURA SVG CON TEXTO 100% NEGRO Y FONDOS PASTELES -->
  <div class="flow-container">
    <h2>Esquema de Flujos: Origen de Datos → Servicios FGLP53 → MySQL 8.0 → Tableros</h2>
    <svg class="diagram-svg" viewBox="0 0 1100 520" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <marker id="arrow" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#475569" />
        </marker>
        <marker id="arrow-red" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#d9001d" />
        </marker>
      </defs>

      <!-- COLUMNA 1: ORIGEN DE DATOS -->
      <g>
        <rect x="20" y="20" width="220" height="480" rx="10" fill="#fff5f5" stroke="#fecaca" stroke-width="1.5" />
        <text x="130" y="45" fill="#111827" font-size="13" font-weight="bold" text-anchor="middle">1. ORIGEN DE DATOS</text>
        
        <!-- P001 -->
        <rect x="35" y="65" width="190" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="45" y="85" fill="#111827" font-size="11" font-weight="bold">P001 Ciclo 3</text>
        <text x="45" y="102" fill="#111827" font-size="10">WebRH / CAPA / Excel Desposte</text>

        <!-- P002 -->
        <rect x="35" y="125" width="190" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="45" y="145" fill="#111827" font-size="11" font-weight="bold">P002 Stock Congelado</text>
        <text x="45" y="162" fill="#111827" font-size="10">CAPA / Excel / XML Pallets</text>

        <!-- P003 -->
        <rect x="35" y="185" width="190" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="45" y="205" fill="#111827" font-size="11" font-weight="bold">P003 Pick Insumos</text>
        <text x="45" y="222" fill="#111827" font-size="10">SAP Insumos / Android APK</text>

        <!-- P004 -->
        <rect x="35" y="245" width="190" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="45" y="265" fill="#111827" font-size="11" font-weight="bold">P004 Carnicería</text>
        <text x="45" y="282" fill="#111827" font-size="10">Planillas Faena / CSV Diario</text>

        <!-- P005 -->
        <rect x="35" y="305" width="190" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="45" y="325" fill="#111827" font-size="11" font-weight="bold">P005 Supervisor</text>
        <text x="45" y="342" fill="#111827" font-size="10">Pings HTTP / Tareas Windows</text>

        <!-- P006 -->
        <rect x="35" y="365" width="190" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="45" y="385" fill="#111827" font-size="11" font-weight="bold">P006 Báscula</text>
        <text x="45" y="402" fill="#111827" font-size="10">Balanza Hacienda / Camiones</text>

        <!-- P007 -->
        <rect x="35" y="425" width="190" height="60" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="45" y="445" fill="#111827" font-size="11" font-weight="bold">P007 Stock Sistemas</text>
        <text x="45" y="462" fill="#111827" font-size="10">Inventario IT / Periféricos</text>
      </g>

      <!-- FLECHAS COLUMNA 1 -> 2 -->
      <line x1="240" y1="90" x2="290" y2="90" stroke="#475569" stroke-width="1.5" marker-end="url(#arrow)" />
      <line x1="240" y1="150" x2="290" y2="150" stroke="#475569" stroke-width="1.5" marker-end="url(#arrow)" />
      <line x1="240" y1="210" x2="290" y2="210" stroke="#475569" stroke-width="1.5" marker-end="url(#arrow)" />
      <line x1="240" y1="270" x2="290" y2="270" stroke="#475569" stroke-width="1.5" marker-end="url(#arrow)" />
      <line x1="240" y1="330" x2="290" y2="330" stroke="#475569" stroke-width="1.5" marker-end="url(#arrow)" />
      <line x1="240" y1="390" x2="290" y2="390" stroke="#475569" stroke-width="1.5" marker-end="url(#arrow)" />
      <line x1="240" y1="455" x2="290" y2="455" stroke="#475569" stroke-width="1.5" marker-end="url(#arrow)" />

      <!-- COLUMNA 2: MOTORES Y SERVICIOS 24/7 EN FGLP53 -->
      <g>
        <rect x="295" y="20" width="240" height="480" rx="10" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
        <text x="415" y="45" fill="#111827" font-size="13" font-weight="bold" text-anchor="middle">2. SERVICIOS (FGLP53)</text>
        
        <rect x="310" y="65" width="210" height="50" rx="6" fill="#ffffff" stroke="#fecaca" stroke-width="1.2" />
        <text x="320" y="85" fill="#111827" font-size="11" font-weight="bold">IIS 10 + Python Colector</text>
        <text x="320" y="102" fill="#111827" font-size="10">Puertos 80 (Prod) y 8080 (Lab)</text>

        <rect x="310" y="125" width="210" height="50" rx="6" fill="#ffffff" stroke="#fecaca" stroke-width="1.2" />
        <text x="320" y="145" fill="#111827" font-size="11" font-weight="bold">ExportarStock.exe (.NET 8)</text>
        <text x="320" y="162" fill="#111827" font-size="10">Puerto 8090 / Minimal API</text>

        <rect x="310" y="185" width="210" height="50" rx="6" fill="#ffffff" stroke="#fecaca" stroke-width="1.2" />
        <text x="320" y="205" fill="#111827" font-size="11" font-weight="bold">Gorina.Api.exe (.NET 8)</text>
        <text x="320" y="222" fill="#111827" font-size="10">Puerto 5000 / API Picking</text>

        <rect x="310" y="245" width="210" height="50" rx="6" fill="#ffffff" stroke="#fecaca" stroke-width="1.2" />
        <text x="320" y="265" fill="#111827" font-size="11" font-weight="bold">Gorina.Carniceria.Api.exe</text>
        <text x="320" y="282" fill="#111827" font-size="10">Puerto 8765 / .NET 8 API</text>

        <rect x="310" y="305" width="210" height="50" rx="6" fill="#ffffff" stroke="#fecaca" stroke-width="1.2" />
        <text x="320" y="325" fill="#111827" font-size="11" font-weight="bold">Supervisor 24-7 (PS1)</text>
        <text x="320" y="342" fill="#111827" font-size="10">Watchdog cada 3m + SMTP</text>

        <rect x="310" y="365" width="210" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="320" y="385" fill="#111827" font-size="11" font-weight="bold">Báscula Service (.NET 8)</text>
        <text x="320" y="402" fill="#111827" font-size="10">Puerto 8095 (En diseño)</text>

        <rect x="310" y="425" width="210" height="60" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="320" y="445" fill="#111827" font-size="11" font-weight="bold">Stock Sistemas API (.NET 8)</text>
        <text x="320" y="462" fill="#111827" font-size="10">Puerto 8096 (En diseño)</text>
      </g>

      <!-- FLECHAS COLUMNA 2 -> 3 -->
      <line x1="535" y1="90" x2="575" y2="90" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="535" y1="150" x2="575" y2="150" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="535" y1="210" x2="575" y2="210" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="535" y1="270" x2="575" y2="270" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="535" y1="330" x2="575" y2="330" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="535" y1="390" x2="575" y2="390" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="535" y1="455" x2="575" y2="455" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />

      <!-- COLUMNA 3: BASES DE DATOS MYSQL 8.0 LOCAL -->
      <g>
        <rect x="580" y="20" width="235" height="480" rx="10" fill="#fff5f5" stroke="#fecaca" stroke-width="1.5" />
        <text x="697" y="45" fill="#111827" font-size="13" font-weight="bold" text-anchor="middle">3. MYSQL 8.0 (127.0.0.1)</text>

        <rect x="595" y="65" width="205" height="50" rx="6" fill="#ffffff" stroke="#fecaca" />
        <text x="605" y="85" fill="#111827" font-size="11" font-weight="bold">p001.dashboard.ciclo.3</text>
        <text x="605" y="102" fill="#111827" font-size="10">Métricas, desposte, turnos</text>

        <rect x="595" y="125" width="205" height="50" rx="6" fill="#ffffff" stroke="#fecaca" />
        <text x="605" y="145" fill="#111827" font-size="11" font-weight="bold">p002.stock.almacen.congelado</text>
        <text x="605" y="162" fill="#111827" font-size="10">Catálogo SKUs, cargas, stock</text>

        <rect x="595" y="185" width="205" height="50" rx="6" fill="#ffffff" stroke="#fecaca" />
        <text x="605" y="205" fill="#111827" font-size="11" font-weight="bold">p003.pick.materiales.insumos</text>
        <text x="605" y="222" fill="#111827" font-size="10">Artículos, stock almacén, picks</text>

        <rect x="595" y="245" width="205" height="50" rx="6" fill="#ffffff" stroke="#fecaca" />
        <text x="605" y="265" fill="#111827" font-size="11" font-weight="bold">p004.carniceria.tablero</text>
        <text x="605" y="282" fill="#111827" font-size="10">Faena, cortes, stock carnicería</text>

        <rect x="595" y="305" width="205" height="50" rx="6" fill="#ffffff" stroke="#fecaca" />
        <text x="605" y="325" fill="#111827" font-size="11" font-weight="bold">p005.supervisor.general</text>
        <text x="605" y="342" fill="#111827" font-size="10">Incidentes, servicios, pings</text>

        <rect x="595" y="365" width="205" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="605" y="385" fill="#111827" font-size="11" font-weight="bold">p006.bascula</text>
        <text x="605" y="402" fill="#111827" font-size="10">Pesajes, camiones, hacienda</text>

        <rect x="595" y="425" width="205" height="60" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="605" y="445" fill="#111827" font-size="11" font-weight="bold">p007.stock.sistemas</text>
        <text x="605" y="462" fill="#111827" font-size="10">Hardware, licencias, stock IT</text>
      </g>

      <!-- FLECHAS COLUMNA 3 -> 4 -->
      <line x1="815" y1="90" x2="855" y2="90" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="815" y1="150" x2="855" y2="150" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="815" y1="210" x2="855" y2="210" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="815" y1="270" x2="855" y2="270" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="815" y1="330" x2="855" y2="330" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="815" y1="390" x2="855" y2="390" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />
      <line x1="815" y1="455" x2="855" y2="455" stroke="#d9001d" stroke-width="1.5" marker-end="url(#arrow-red)" />

      <!-- COLUMNA 4: ACCESO CORPORATIVO (FGLP53) -->
      <g>
        <rect x="860" y="20" width="220" height="480" rx="10" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5" />
        <text x="970" y="45" fill="#111827" font-size="13" font-weight="bold" text-anchor="middle">4. ACCESO (FGLP53)</text>

        <rect x="870" y="65" width="200" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="880" y="85" fill="#111827" font-size="11" font-weight="bold">fglp53/tablero.ciclo3/</text>
        <text x="880" y="102" fill="#111827" font-size="10">http://fglp53:8080 (Lab)</text>

        <rect x="870" y="125" width="200" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="880" y="145" fill="#111827" font-size="11" font-weight="bold">fglp53:8090/stock_almacen</text>
        <text x="880" y="162" fill="#111827" font-size="10">SPA + Fast CSV Stream</text>

        <rect x="870" y="185" width="200" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="880" y="205" fill="#111827" font-size="11" font-weight="bold">fglp53:5000/api/materiales</text>
        <text x="880" y="222" fill="#111827" font-size="10">Consumo APK Picking</text>

        <rect x="870" y="245" width="200" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="880" y="265" fill="#111827" font-size="11" font-weight="bold">fglp53:8765/tablero_carniceria</text>
        <text x="880" y="282" fill="#111827" font-size="10">Tablero TV Producción</text>

        <rect x="870" y="305" width="200" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="880" y="325" fill="#111827" font-size="11" font-weight="bold">fglp53 (Panel de Alertas)</text>
        <text x="880" y="342" fill="#111827" font-size="10">2_VER_ESTADO_ALERTAS.bat</text>

        <rect x="870" y="365" width="200" height="50" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="880" y="385" fill="#111827" font-size="11" font-weight="bold">fglp53:8095/bascula</text>
        <text x="880" y="402" fill="#111827" font-size="10">Próxima implementación</text>

        <rect x="870" y="425" width="200" height="60" rx="6" fill="#ffffff" stroke="#cbd5e1" />
        <text x="880" y="445" fill="#111827" font-size="11" font-weight="bold">fglp53:8096/stock_sistemas</text>
        <text x="880" y="462" fill="#111827" font-size="10">Próxima implementación</text>
      </g>
    </svg>
  </div>

  <!-- TABLA MAESTRA DETALLADA -->
  <div class="card" style="margin-bottom: 24px;">
    <h2>Matriz Maestra de Aplicaciones, Bases de Datos y Accesos FGLP53</h2>
    <div class="table-container">
      <table>
        <thead>
          <tr>
            <th>Proyecto</th>
            <th>Origen de Datos</th>
            <th>Base de Datos MySQL</th>
            <th>Dirección de Acceso Corporativo (`FGLP53`)</th>
            <th>Motor / Backend</th>
            <th>Auto-Inicio 24/7</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>P001.Dashboard.Ciclo.3</strong></td>
            <td>WebRH / CAPA / Excel Desposte</td>
            <td><span class="db-tag">p001.dashboard.ciclo.3</span></td>
            <td>
              <a class="url-link" href="http://fglp53/tablero.ciclo3/dashboard_operaciones.html" target="_blank">http://fglp53/tablero.ciclo3/</a>
              <span class="url-sublink">http://fglp53:8080 (Laboratorio)</span>
            </td>
            <td><span class="badge badge-iis">IIS 10 + Python</span></td>
            <td><span class="badge badge-on">W3SVC + Colector</span></td>
          </tr>
          <tr>
            <td><strong>P002.Stock.Almacen.Congelado</strong></td>
            <td>CAPA / Catálogo SKUs / XML Pallets</td>
            <td><span class="db-tag">p002.stock.almacen.congelado</span></td>
            <td>
              <a class="url-link" href="http://fglp53:8090/stock_almacen" target="_blank">http://fglp53:8090/stock_almacen</a>
              <span class="url-sublink">http://fglp53:8090/stock_almacen/ping</span>
            </td>
            <td><span class="badge badge-net">C# .NET 8</span></td>
            <td><span class="badge badge-on">AtStartup</span></td>
          </tr>
          <tr>
            <td><strong>P003.Pick.Materiales.Insumos</strong></td>
            <td>Catálogo SAP / Insumos / APK Móvil</td>
            <td><span class="db-tag">p003.pick.materiales.insumos</span></td>
            <td>
              <a class="url-link" href="http://fglp53:5000/api/materiales" target="_blank">http://fglp53:5000/api/materiales</a>
              <span class="url-sublink">http://fglp53:5000/api/ping</span>
            </td>
            <td><span class="badge badge-net">C# .NET 8</span></td>
            <td><span class="badge badge-on">AtStartup + Vigilante</span></td>
          </tr>
          <tr>
            <td><strong>P004.Carniceria.Tablero</strong></td>
            <td>Planillas Faena / CSV diario</td>
            <td><span class="db-tag">p004.carniceria.tablero</span></td>
            <td>
              <a class="url-link" href="http://fglp53:8765/tablero_carniceria" target="_blank">http://fglp53:8765/tablero_carniceria</a>
              <span class="url-sublink">http://fglp53:8765/api/estado</span>
            </td>
            <td><span class="badge badge-net">C# .NET 8</span></td>
            <td><span class="badge badge-on">AtStartup + Vigilante</span></td>
          </tr>
          <tr>
            <td><strong>P005.Supervisor.General</strong></td>
            <td>Pings HTTP + Tareas Windows</td>
            <td><span class="db-tag">p005.supervisor.general</span></td>
            <td>
              <span class="url-link" style="text-decoration: none;">2_VER_ESTADO_DE_ALERTAS.bat</span>
              <a class="url-sublink" href="http://fglp53/tablero.ciclo3/1_DIAGRAMA_Y_MANUAL.html" target="_blank">Manual FGLP53</a>
            </td>
            <td><span class="badge badge-on">PowerShell + SMTP</span></td>
            <td><span class="badge badge-on">AtStartup + 3 min</span></td>
          </tr>
          <tr>
            <td><strong>P006.Bascula</strong></td>
            <td>Pesaje Hacienda / Balanza Camiones</td>
            <td><span class="db-tag">p006.bascula</span></td>
            <td>
              <span class="url-link" style="text-decoration: none;">http://fglp53:8095/bascula</span>
            </td>
            <td><span class="badge badge-net">.NET 8 (En diseño)</span></td>
            <td><span class="badge">Próximo</span></td>
          </tr>
          <tr>
            <td><strong>P007.Stock.Sistemas</strong></td>
            <td>Inventario IT / Hardware y Licencias</td>
            <td><span class="db-tag">p007.stock.sistemas</span></td>
            <td>
              <span class="url-link" style="text-decoration: none;">http://fglp53:8096/stock_sistemas</span>
            </td>
            <td><span class="badge badge-net">.NET 8 (En diseño)</span></td>
            <td><span class="badge">Próximo</span></td>
          </tr>
          <tr>
            <td><strong>P000.Proyectos.General</strong></td>
            <td>Auditoría y control integral P001-P007</td>
            <td><span class="db-tag">p000.proyectos.general</span></td>
            <td>
              <span class="url-link" style="text-decoration: none;">http://fglp53/proyectos</span>
            </td>
            <td><span class="badge badge-db">Orquestador Central</span></td>
            <td><span class="badge badge-on">Activo</span></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <div class="grid-cards">
    <!-- TARJETA: GESTIÓN RÁPIDA -->
    <div class="card">
      <h2>Gestión y Operaciones Rápidas</h2>
      <div class="step-box">
        <strong>1. Ver Estado en Vivo: <code>2_VER_ESTADO_DE_ALERTAS.bat</code></strong><br>
        Consulta directamente MySQL <code>p005.supervisor.general</code> mostrando el estado de todos los servicios, tiempos de respuesta e incidentes recientes.
      </div>
      <div class="step-box">
        <strong>2. Enviar Alerta de Prueba: <code>5_ENVIAR_ALERTA_DE_PRUEBA.bat</code></strong><br>
        Dispara una prueba técnica al relay corporativo <code>192.168.0.234:25</code> para validar entrega en las casillas configuradas.
      </div>
      <div class="step-box">
        <strong>3. Auto-Recuperación Automática:</strong><br>
        Si un servicio se detiene, el supervisor general ejecuta su vigilante automáticamente sin requerir intervención manual.
      </div>
    </div>

    <!-- TARJETA: REGISTRO DE INCIDENTES RECIENTES -->
    <div class="card" id="card-log-eventos">
      <h2>Registro de Últimos Incidentes y Eventos (MySQL)</h2>
      <p style="font-size: 13px; color: #374151; margin-bottom: 12px;">
        Historial persistido en la tabla <code>incidentes</code> de la base de datos <code>p005.supervisor.general</code>:
      </p>

      <!-- INICIO_LOG_EVENTOS -->
      <div style="overflow-x: auto; max-height: 290px; overflow-y: auto; border: 1px solid var(--border); border-radius: 8px; background: #fff;">
        <table style="margin-top: 0; font-size: 12.5px; width: 100%;">
          <thead>
            <tr style="position: sticky; top: 0; background-color: #fff1f2; z-index: 1;">
              <th style="width: 130px;">Fecha / Hora</th>
              <th style="width: 110px; text-align: center;">Evento</th>
              <th>Servicio / Motivo</th>
              <th style="width: 170px;">Notificado A</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td style="font-family: monospace; font-size: 11.5px; color: #111827;">28/09 14:57:17</td>
              <td style="text-align: center;"><span class="badge badge-on">RESTABLECIDO</span></td>
              <td><strong>Infraestructura Dashboard</strong><br><span style="color: #374151; font-size: 11px;">Todos los servicios normalizados (HTTP 200 / Tareas Ready)</span></td>
              <td style="font-size: 11.5px; color: #111827;">sistemas@friggorina.com</td>
            </tr>
            <tr>
              <td style="font-family: monospace; font-size: 11.5px; color: #111827;">28/09 14:52:21</td>
              <td style="text-align: center;"><span class="badge badge-off">ALERTA</span></td>
              <td><strong>Stock Almacén (Puerto 8090)</strong><br><span style="color: #374151; font-size: 11px;">Falla de conexión (timed out) en http://fglp53:8090/</span></td>
              <td style="font-size: 11.5px; color: #111827;">sistemas@friggorina.com</td>
            </tr>
            <tr>
              <td style="font-family: monospace; font-size: 11.5px; color: #111827;">26/09 13:17:17</td>
              <td style="text-align: center;"><span class="badge badge-on">RESTABLECIDO</span></td>
              <td><strong>Infraestructura Dashboard</strong><br><span style="color: #374151; font-size: 11px;">Todos los servicios normalizados (HTTP 200 / Tareas Ready)</span></td>
              <td style="font-size: 11.5px; color: #111827;">sistemas@friggorina.com</td>
            </tr>
            <tr>
              <td style="font-family: monospace; font-size: 11.5px; color: #111827;">26/09 13:12:21</td>
              <td style="text-align: center;"><span class="badge badge-off">ALERTA</span></td>
              <td><strong>Stock Almacén (Puerto 8090)</strong><br><span style="color: #374151; font-size: 11px;">Falla de conexión (timed out) en http://fglp53:8090/</span></td>
              <td style="font-size: 11.5px; color: #111827;">sistemas@friggorina.com</td>
            </tr>
            <tr>
              <td style="font-family: monospace; font-size: 11.5px; color: #111827;">25/09 15:52:17</td>
              <td style="text-align: center;"><span class="badge badge-on">RESTABLECIDO</span></td>
              <td><strong>Infraestructura Dashboard</strong><br><span style="color: #374151; font-size: 11px;">Todos los servicios normalizados (HTTP 200 / Tareas Ready)</span></td>
              <td style="font-size: 11.5px; color: #111827;">sistemas@friggorina.com</td>
            </tr>
            <tr>
              <td style="font-family: monospace; font-size: 11.5px; color: #111827;">25/09 15:42:19</td>
              <td style="text-align: center;"><span class="badge badge-off">ALERTA</span></td>
              <td><strong>Acceso Red Corporativa (tablero.ciclo3)</strong><br><span style="color: #374151; font-size: 11px;">Falla de conexión (HTTP Error 500: Internal Server Error) en http://fglp53/tablero.ciclo3/</span></td>
              <td style="font-size: 11.5px; color: #111827;">sistemas@friggorina.com</td>
            </tr>
          </tbody>
        </table>
      </div>
      <!-- FIN_LOG_EVENTOS -->

      <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 12px; font-size: 12px; color: #374151;">
        <span>Persistencia directa en MySQL <code>p005.supervisor.general</code></span>
        <span style="font-weight: 700; color: #111827;">● Supervisor Activo 24/7</span>
      </div>
    </div>
  </div>

  <footer>
    Sistema de Control y Diagnóstico Integral · Servidor FGLP53 (192.168.0.126) · MySQL 8.0 Local
  </footer>

</div>
</body>
</html>
"""

with open(HTML_OUTPUT, "w", encoding="utf-8") as f:
    f.write(html_content)

print(f"1_DIAGRAMA_Y_MANUAL.html generado con tipografía estándar Segoe UI y degradé rojo Gorina.")
