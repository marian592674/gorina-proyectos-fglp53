import re

html_file = r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html'
with open(html_file, 'r', encoding='utf-8') as f:
    content = f.read()

correct_resumen_section = '''  <!-- Pestaña 1: Resumen General -->
  <section class="page active" id="resumen">
    <!-- 1. KPIs Numéricos Principales -->
    <div class="kpis">
      <div class="kpi">
        <div class="kpi-tag">Venta Neta</div>
        <div class="kpi-value" id="kVenta">$ 0</div>
        <div class="kpi-sub">Signo neto FA / NC</div>
      </div>
      <div class="kpi">
        <div class="kpi-tag">Kilos Netos</div>
        <div class="kpi-value" id="kKg">0 kg</div>
        <div class="kpi-sub">Volumen entregado</div>
      </div>
      <div class="kpi">
        <div class="kpi-tag">Precio Promedio</div>
        <div class="kpi-value" id="kPrecio">$ 0/kg</div>
        <div class="kpi-sub">$ Neto / Kg Neto</div>
      </div>
      <div class="kpi">
        <div class="kpi-tag">Ticket Promedio</div>
        <div class="kpi-value" id="kTicket">$ 0</div>
        <div class="kpi-sub">Venta / Comprobantes</div>
      </div>
      <div class="kpi">
        <div class="kpi-tag">Clientes / Legajos</div>
        <div class="kpi-value" id="kClientes">0</div>
        <div class="kpi-sub">Clientes con compra</div>
      </div>
      <div class="kpi">
        <div class="kpi-tag">Comprobantes</div>
        <div class="kpi-value" id="kComprobantes">0</div>
        <div class="kpi-sub">Tickets emitidos</div>
      </div>
      <div class="kpi">
        <div class="kpi-tag">Notas de Crédito ($)</div>
        <div class="kpi-value" id="kNC">$ 0</div>
        <div class="kpi-sub">Impacto negativo</div>
      </div>
      <div class="kpi">
        <div class="kpi-tag">NC Volumen (Kg)</div>
        <div class="kpi-value" id="kNCKg">0 kg</div>
        <div class="kpi-sub">Kilos devueltos</div>
      </div>
      <div class="kpi">
        <div class="kpi-tag">Var. Intermensual</div>
        <div class="kpi-value" id="kVar">—</div>
        <div class="kpi-sub" id="kVarNote">Mes vs anterior</div>
      </div>
    </div>

    <!-- 2. Gráfico de Evolución Temporal (Mensual / Diario) -->
    <div class="card">
      <div class="card-header">
        <div>
          <div class="card-title" id="evolTitle">Evolución de Facturación Neta y Volumen</div>
          <div class="card-sub" id="evolSubText">Barras Rojas = $ Neto · Línea Azul = Kg Netos · Clic en un período para seleccionar/deseleccionar</div>
        </div>
        <div class="granularity-switch">
          <button type="button" class="btn-gran active" id="btnGranMes" onclick="App.setGranularity('mes')">Mensual</button>
          <button type="button" class="btn-gran" id="btnGranDia" onclick="App.setGranularity('dia')">Diario</button>
        </div>
      </div>

      <!-- Leyenda de colores para vista diaria interactiva -->
      <div class="chart-day-legend" id="chartDayLegend" style="display:none">
        <span class="chart-day-legend-title">Filtrar por Día:</span>
        <button type="button" class="day-legend-pill" id="pillDay1" data-day="1" onclick="App.toggleDayOfWeek(1)" title="Seleccionar/Deseleccionar todos los Lunes">
          <span class="day-dot" style="background:#4f46e5"></span> Lunes
        </button>
        <button type="button" class="day-legend-pill" id="pillDay2" data-day="2" onclick="App.toggleDayOfWeek(2)" title="Seleccionar/Deseleccionar todos los Martes">
          <span class="day-dot" style="background:#0284c7"></span> Martes
        </button>
        <button type="button" class="day-legend-pill" id="pillDay3" data-day="3" onclick="App.toggleDayOfWeek(3)" title="Seleccionar/Deseleccionar todos los Miércoles">
          <span class="day-dot" style="background:#059669"></span> Miércoles
        </button>
        <button type="button" class="day-legend-pill" id="pillDay4" data-day="4" onclick="App.toggleDayOfWeek(4)" title="Seleccionar/Deseleccionar todos los Jueves">
          <span class="day-dot" style="background:#d97706"></span> Jueves
        </button>
        <button type="button" class="day-legend-pill" id="pillDay5" data-day="5" onclick="App.toggleDayOfWeek(5)" title="Seleccionar/Deseleccionar todos los Viernes">
          <span class="day-dot" style="background:#e11d48"></span> Viernes
        </button>
        <button type="button" class="day-legend-pill" id="pillDay6" data-day="6" onclick="App.toggleDayOfWeek(6)" title="Seleccionar/Deseleccionar todos los Sábados">
          <span class="day-dot" style="background:#7c3aed"></span> Sábado
        </button>
        <button type="button" class="day-legend-pill" id="pillDay0" data-day="0" onclick="App.toggleDayOfWeek(0)" title="Seleccionar/Deseleccionar todos los Domingos">
          <span class="day-dot" style="background:#64748b"></span> Domingo
        </button>
      </div>

      <div class="chart-container" id="chartEvol"></div>
    </div>

    <!-- 3. Rankings Top con Selección Dinámica -->
    <div class="grid3" style="margin-top:20px;">
      <div class="card">
        <div class="card-header">
          <div class="card-title">Top Agrupa ($)</div>
          <div class="card-sub">Clic para seleccionar / deseleccionar (multiselección)</div>
        </div>
        <div class="ranking-list" id="rankingAgrupa"></div>
      </div>

      <div class="card">
        <div class="card-header">
          <div class="card-title">Top Productos ($)</div>
          <div class="card-sub">Por familia Expone · Clic para toggle</div>
        </div>
        <div class="ranking-list" id="rankingProductos"></div>
      </div>

      <div class="card">
        <div class="card-header">
          <div class="card-title">Top Clientes ($)</div>
          <div class="card-sub">Clic para seleccionar / deseleccionar (multiselección)</div>
        </div>
        <div class="ranking-list" id="rankingClientes"></div>
      </div>
    </div>

    <!-- 4. Detalle de Evolución (Tabla Detallada al Final) -->
    <div class="card" style="margin-top:20px;">
      <div class="card-header">
        <div class="card-title">Detalle de Evolución</div>
        <div class="card-sub">Desglose de facturación y volumen por período</div>
      </div>
      <div class="table-wrap" style="margin-top:10px">
        <table id="tableEvol"></table>
      </div>
    </div>
  </section>'''

# Reemplazar la sección #resumen completa
pattern = r'<!-- Pestaña 1: Resumen General -->\s*<section class="page active" id="resumen">.*?</section>'
match = re.search(pattern, content, flags=re.DOTALL)
if match:
    content = content[:match.start()] + correct_resumen_section + content[match.end():]
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Sección resumen reemplazada exitosamente y con etiquetas perfectamente cerradas.")
else:
    print("No se encontró el patrón exacto, buscando alternativo...")
    pattern_alt = r'<section class="page active" id="resumen">.*?</section>'
    match_alt = re.search(pattern_alt, content, flags=re.DOTALL)
    if match_alt:
        content = content[:match_alt.start()] + correct_resumen_section + content[match_alt.end():]
        with open(html_file, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Sección resumen reemplazada con patrón alternativo.")
