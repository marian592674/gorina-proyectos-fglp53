using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using Gorina.Stock.Api;

var config = Config.Cargar(args);
var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(o =>
{
    o.SingleLine = true;
    o.TimestampFormat = "yyyy-MM-dd HH:mm:ss ";
});

builder.Services.AddSingleton(config);
builder.Services.AddSingleton<Database>();
builder.Services.AddSingleton<StockEngine>();
builder.Services.AddSingleton<CapaService>();

var app = builder.Build();

// Asegurar esquema MySQL al inicio
var db = app.Services.GetRequiredService<Database>();
var stockEngine = app.Services.GetRequiredService<StockEngine>();
var capaService = app.Services.GetRequiredService<CapaService>();
try
{
    db.AsegurarEsquema();
    app.Logger.LogInformation("Esquema MySQL asegurado en p002.stock.almacen.congelado");
}
catch (Exception ex)
{
    app.Logger.LogError(ex, "Error asegurando esquema MySQL");
}

const string CsrfToken = "GORINA-STOCK-2026";

// Helper para servir index.template.html
IResult ServirHtml()
{
    var baseDir = AppContext.BaseDirectory;
    var candidates = new[]
    {
        Path.Combine(baseDir, "index.template.html"),
        Path.Combine(baseDir, "index.html"),
        @"D:\PROYECTOS\P002.Stock.Almacen.Congelado\Fuente A PROBAR\index.template.html",
        @"D:\PROYECTOS\P002.Stock.Almacen.Congelado\A PROBAR\index.template.html"
    };

    string? ruta = candidates.FirstOrDefault(File.Exists);
    if (ruta == null) return Results.NotFound("index.template.html no encontrado");

    var html = File.ReadAllText(ruta);
    html = html.Replace("@@CSRF_TOKEN@@", CsrfToken);
    return Results.Content(html, "text/html; charset=utf-8");
}

// Helper para servir exceljs.min.js
IResult ServirExcelJs()
{
    var baseDir = AppContext.BaseDirectory;
    var candidates = new[]
    {
        Path.Combine(baseDir, "exceljs.min.js"),
        @"D:\PROYECTOS\P002.Stock.Almacen.Congelado\Fuente A PROBAR\exceljs.min.js",
        @"D:\PROYECTOS\P002.Stock.Almacen.Congelado\A PROBAR\exceljs.min.js"
    };

    string? ruta = candidates.FirstOrDefault(File.Exists);
    if (ruta == null) return Results.NotFound("exceljs.min.js no encontrado");

    return Results.File(ruta, "application/javascript; charset=utf-8");
}

// ── Rutas Web y Frontend (Raíz y /stock_almacen) ──
app.MapGet("/", ServirHtml);
app.MapGet("/index.html", ServirHtml);
app.MapGet("/stock_almacen", ServirHtml);
app.MapGet("/stock_almacen/index.html", ServirHtml);

app.MapGet("/exceljs.min.js", ServirExcelJs);
app.MapGet("/stock_almacen/exceljs.min.js", ServirExcelJs);

// ── Ping / Pulso ──
object HandlePing(string? loaded)
{
    var latest = stockEngine.ObtenerUltimoStockCsv();
    bool hasNew = false;
    string latestName = "";
    string latestTime = "";

    if (latest != null)
    {
        latestName = latest.Name;
        var ft = StockEngine.ExtraerFechaNombre(latest.Name) ?? latest.LastWriteTime;
        latestTime = ft.ToString("dd/MM HH:mm") + " hs";
        if (!string.IsNullOrWhiteSpace(loaded) && !string.Equals(loaded, latestName, StringComparison.OrdinalIgnoreCase))
        {
            hasNew = true;
        }
    }

    return new
    {
        ok = true,
        hasNew,
        latestCsv = latestName,
        latestTime,
        serverTime = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")
    };
}

app.MapGet("/ping", (string? loaded) => Results.Ok(HandlePing(loaded)));
app.MapGet("/stock_almacen/ping", (string? loaded) => Results.Ok(HandlePing(loaded)));

// ── Datos de Stock (Streaming / JSON) ──
IResult HandleDatos(bool refrescar = false)
{
    try
    {
        var json = stockEngine.ObtenerPayload(forzar: refrescar);
        var streamed = $"PASO:30:Leyendo datos de stock...\nPASO:70:Procesando registros...\nPASO:100:Completado\nDONE:{json}\n";
        return Results.Content(streamed, "text/plain; charset=utf-8");
    }
    catch (Exception ex)
    {
        return Results.Content($"ERROR:{ex.Message}\n", "text/plain; charset=utf-8");
    }
}

app.MapGet("/datos", () => HandleDatos(false));
app.MapGet("/stock_almacen/datos", () => HandleDatos(false));
app.MapGet("/refrescar", () => HandleDatos(true));
app.MapGet("/stock_almacen/refrescar", () => HandleDatos(true));

// ── Sincronización CTTO 2.1 ──
IResult HandleSincronizarCtto()
{
    try
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "descargar_stock.ps1"),
            @"D:\PROYECTOS\P002.Stock.Almacen.Congelado\Fuente A PROBAR\descargar_stock.ps1",
            @"D:\PROYECTOS\P002.Stock.Almacen.Congelado\A PROBAR\descargar_stock.ps1"
        };
        string? script = candidates.FirstOrDefault(File.Exists);
        if (script == null)
            return Results.Json(new { ok = false, mensaje = "Script descargar_stock.ps1 no encontrado" }, statusCode: 500);

        var pinfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-ExecutionPolicy Bypass -File \"{script}\" -SkipNotify",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var proc = Process.Start(pinfo);
        if (proc != null)
        {
            proc.WaitForExit(90000);
            stockEngine.InvalidarCache();
            return Results.Ok(new { ok = true, estado = "completado", mensaje = "Stock sincronizado con éxito desde CTTO 2.1" });
        }
        return Results.Json(new { ok = false, mensaje = "No se pudo iniciar el proceso de descarga" }, statusCode: 500);
    }
    catch (Exception ex)
    {
        return Results.Json(new { ok = false, error = ex.Message }, statusCode: 500);
    }
}

app.MapGet("/sincronizar-ctto", HandleSincronizarCtto);
app.MapGet("/stock_almacen/sincronizar-ctto", HandleSincronizarCtto);

// ── Análisis Manual (Brasil) ──
app.MapGet("/analisis-manual", () => Results.Ok(db.GetAnalisisManual()));
app.MapGet("/stock_almacen/analisis-manual", () => Results.Ok(db.GetAnalisisManual()));

app.MapPost("/marcar-analisis", async (HttpContext ctx) =>
{
    List<string>? pallets = null;
    List<string>? cajas = null;

    if (ctx.Request.HasJsonContentType())
    {
        try
        {
            var body = await JsonSerializer.DeserializeAsync<AnalisisManualDto>(ctx.Request.Body);
            pallets = body?.Pallets;
            cajas = body?.Cajas;
        }
        catch { }
    }

    var qTipo = ctx.Request.Query["tipo"].ToString();
    var qVal = ctx.Request.Query["valor"].ToString();
    if (!string.IsNullOrWhiteSpace(qVal))
    {
        if (string.Equals(qTipo, "pallet", StringComparison.OrdinalIgnoreCase))
            (pallets ??= new()).Add(qVal);
        else if (string.Equals(qTipo, "caja", StringComparison.OrdinalIgnoreCase))
            (cajas ??= new()).Add(qVal);
    }

    db.MarcarAnalisis(pallets, cajas);
    stockEngine.InvalidarCache();
    var actual = db.GetAnalisisManual();
    return Results.Ok(new { ok = true, totalPallets = actual.Pallets.Count, totalCajas = actual.Cajas.Count });
});

app.MapPost("/stock_almacen/marcar-analisis", async (HttpContext ctx) =>
{
    List<string>? pallets = null;
    List<string>? cajas = null;

    if (ctx.Request.HasJsonContentType())
    {
        try
        {
            var body = await JsonSerializer.DeserializeAsync<AnalisisManualDto>(ctx.Request.Body);
            pallets = body?.Pallets;
            cajas = body?.Cajas;
        }
        catch { }
    }

    var qTipo = ctx.Request.Query["tipo"].ToString();
    var qVal = ctx.Request.Query["valor"].ToString();
    if (!string.IsNullOrWhiteSpace(qVal))
    {
        if (string.Equals(qTipo, "pallet", StringComparison.OrdinalIgnoreCase))
            (pallets ??= new()).Add(qVal);
        else if (string.Equals(qTipo, "caja", StringComparison.OrdinalIgnoreCase))
            (cajas ??= new()).Add(qVal);
    }

    db.MarcarAnalisis(pallets, cajas);
    stockEngine.InvalidarCache();
    var actual = db.GetAnalisisManual();
    return Results.Ok(new { ok = true, totalPallets = actual.Pallets.Count, totalCajas = actual.Cajas.Count });
});

app.MapPost("/desmarcar-analisis", async (HttpContext ctx) =>
{
    List<string>? pallets = null;
    List<string>? cajas = null;

    if (ctx.Request.HasJsonContentType())
    {
        try
        {
            var body = await JsonSerializer.DeserializeAsync<AnalisisManualDto>(ctx.Request.Body);
            pallets = body?.Pallets;
            cajas = body?.Cajas;
        }
        catch { }
    }

    var qTipo = ctx.Request.Query["tipo"].ToString();
    var qVal = ctx.Request.Query["valor"].ToString();
    if (!string.IsNullOrWhiteSpace(qVal))
    {
        if (string.Equals(qTipo, "pallet", StringComparison.OrdinalIgnoreCase))
            (pallets ??= new()).Add(qVal);
        else if (string.Equals(qTipo, "caja", StringComparison.OrdinalIgnoreCase))
            (cajas ??= new()).Add(qVal);
    }

    db.DesmarcarAnalisis(pallets, cajas);
    stockEngine.InvalidarCache();
    var actual = db.GetAnalisisManual();
    return Results.Ok(new { ok = true, totalPallets = actual.Pallets.Count, totalCajas = actual.Cajas.Count });
});

app.MapPost("/stock_almacen/desmarcar-analisis", async (HttpContext ctx) =>
{
    List<string>? pallets = null;
    List<string>? cajas = null;

    if (ctx.Request.HasJsonContentType())
    {
        try
        {
            var body = await JsonSerializer.DeserializeAsync<AnalisisManualDto>(ctx.Request.Body);
            pallets = body?.Pallets;
            cajas = body?.Cajas;
        }
        catch { }
    }

    var qTipo = ctx.Request.Query["tipo"].ToString();
    var qVal = ctx.Request.Query["valor"].ToString();
    if (!string.IsNullOrWhiteSpace(qVal))
    {
        if (string.Equals(qTipo, "pallet", StringComparison.OrdinalIgnoreCase))
            (pallets ??= new()).Add(qVal);
        else if (string.Equals(qTipo, "caja", StringComparison.OrdinalIgnoreCase))
            (cajas ??= new()).Add(qVal);
    }

    db.DesmarcarAnalisis(pallets, cajas);
    stockEngine.InvalidarCache();
    var actual = db.GetAnalisisManual();
    return Results.Ok(new { ok = true, totalPallets = actual.Pallets.Count, totalCajas = actual.Cajas.Count });
});

// ── APIs de Cargas y Romaneos ──
app.MapGet("/api/cargas", () => Results.Ok(db.GetCargas()));
app.MapGet("/stock_almacen/api/cargas", () => Results.Ok(db.GetCargas()));

app.MapGet("/api/romaneos", () => Results.Ok(capaService.SincronizarRomaneos()));
app.MapGet("/stock_almacen/api/romaneos", () => Results.Ok(capaService.SincronizarRomaneos()));

app.MapPost("/api/guardar-carga", (Carga carga) =>
{
    if (string.IsNullOrWhiteSpace(carga.Id))
        carga.Id = $"CRG-{DateTime.Now:yyyyMMdd-HHmmss}";

    db.GuardarCarga(carga);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true, id = carga.Id });
});
app.MapPost("/stock_almacen/api/guardar-carga", (Carga carga) =>
{
    if (string.IsNullOrWhiteSpace(carga.Id))
        carga.Id = $"CRG-{DateTime.Now:yyyyMMdd-HHmmss}";

    db.GuardarCarga(carga);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true, id = carga.Id });
});

app.MapPost("/api/actualizar-carga", (Carga carga) =>
{
    if (string.IsNullOrWhiteSpace(carga.Id))
        return Results.BadRequest(new { ok = false, error = "Falta ID de carga" });

    db.GuardarCarga(carga);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true });
});
app.MapPost("/stock_almacen/api/actualizar-carga", (Carga carga) =>
{
    if (string.IsNullOrWhiteSpace(carga.Id))
        return Results.BadRequest(new { ok = false, error = "Falta ID de carga" });

    db.GuardarCarga(carga);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true });
});

app.MapPost("/api/eliminar-carga", (Dictionary<string, string> body) =>
{
    if (!body.TryGetValue("id", out var id) || string.IsNullOrWhiteSpace(id))
        return Results.BadRequest(new { ok = false, error = "Falta ID de carga" });

    db.EliminarCarga(id);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true });
});
app.MapPost("/stock_almacen/api/eliminar-carga", (Dictionary<string, string> body) =>
{
    if (!body.TryGetValue("id", out var id) || string.IsNullOrWhiteSpace(id))
        return Results.BadRequest(new { ok = false, error = "Falta ID de carga" });

    db.EliminarCarga(id);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true });
});

app.MapPost("/api/guardar-kilos-reales", (Dictionary<string, object?> body) =>
{
    if (!body.TryGetValue("id", out var idObj) || idObj is null)
        return Results.BadRequest(new { ok = false, error = "Falta ID de carga" });

    var id = idObj.ToString()!;
    var cargas = db.GetCargas();
    var carga = cargas.FirstOrDefault(c => string.Equals(c.Id, id, StringComparison.OrdinalIgnoreCase));
    if (carga == null) return Results.NotFound(new { ok = false, error = "Carga no encontrada" });

    if (body.TryGetValue("kilos_reales", out var kObj) && kObj != null)
    {
        if (double.TryParse(kObj.ToString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var k))
        {
            carga.KilosReales = k;
            carga.DesvioKilos = Math.Round(k - carga.KilosEstimados, 2);
        }
    }

    db.GuardarCarga(carga);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true });
});

app.MapPost("/stock_almacen/api/guardar-kilos-reales", (Dictionary<string, object?> body) =>
{
    if (!body.TryGetValue("id", out var idObj) || idObj is null)
        return Results.BadRequest(new { ok = false, error = "Falta ID de carga" });

    var id = idObj.ToString()!;
    var cargas = db.GetCargas();
    var carga = cargas.FirstOrDefault(c => string.Equals(c.Id, id, StringComparison.OrdinalIgnoreCase));
    if (carga == null) return Results.NotFound(new { ok = false, error = "Carga no encontrada" });

    if (body.TryGetValue("kilos_reales", out var kObj) && kObj != null)
    {
        if (double.TryParse(kObj.ToString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var k))
        {
            carga.KilosReales = k;
            carga.DesvioKilos = Math.Round(k - carga.KilosEstimados, 2);
        }
    }

    db.GuardarCarga(carga);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true });
});

app.MapPost("/api/vincular-rs-carga", (Dictionary<string, JsonElement> body) =>
{
    if (!body.TryGetValue("id", out var idElem))
        return Results.BadRequest(new { ok = false, error = "Falta ID de carga" });

    var id = idElem.GetString() ?? "";
    var cargas = db.GetCargas();
    var carga = cargas.FirstOrDefault(c => string.Equals(c.Id, id, StringComparison.OrdinalIgnoreCase));
    if (carga == null) return Results.NotFound(new { ok = false, error = "Carga no encontrada" });

    var allRomaneos = capaService.SincronizarRomaneos().ToDictionary(r => r.RomaneoId, StringComparer.OrdinalIgnoreCase);

    var selectedRs = new List<Dictionary<string, object?>>();
    double totalKg = 0;
    string patente = "";

    if (body.TryGetValue("romaneos", out var rsArrayElem) && rsArrayElem.ValueKind == JsonValueKind.Array)
    {
        foreach (var rsItem in rsArrayElem.EnumerateArray())
        {
            var rsNum = rsItem.GetString() ?? rsItem.ToString();
            if (allRomaneos.TryGetValue(rsNum, out var m))
            {
                selectedRs.Add(new Dictionary<string, object?>
                {
                    ["romaneo"] = m.RomaneoId,
                    ["kgNeto"] = m.KgNeto,
                    ["cajas"] = m.Cajas,
                    ["patente"] = m.Patente,
                    ["destino"] = m.Destino,
                    ["fecha"] = m.Fecha,
                    ["hora"] = m.Hora,
                    ["observacion"] = m.Observacion,
                    ["con"] = m.Con,
                    ["conservacion"] = m.Conservacion
                });
                totalKg += m.KgNeto;
                if (string.IsNullOrEmpty(patente) && !string.IsNullOrEmpty(m.Patente))
                    patente = m.Patente;
            }
        }
    }

    carga.Romaneos = selectedRs;
    carga.KilosReales = Math.Round(totalKg, 2);
    carga.DesvioKilos = Math.Round(totalKg - carga.KilosEstimados, 2);
    if (!string.IsNullOrEmpty(patente)) carga.Patente = patente;

    db.GuardarCarga(carga);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true, kilosReales = carga.KilosReales, romaneosVinculados = selectedRs.Count });
});

app.MapPost("/stock_almacen/api/vincular-rs-carga", (Dictionary<string, JsonElement> body) =>
{
    if (!body.TryGetValue("id", out var idElem))
        return Results.BadRequest(new { ok = false, error = "Falta ID de carga" });

    var id = idElem.GetString() ?? "";
    var cargas = db.GetCargas();
    var carga = cargas.FirstOrDefault(c => string.Equals(c.Id, id, StringComparison.OrdinalIgnoreCase));
    if (carga == null) return Results.NotFound(new { ok = false, error = "Carga no encontrada" });

    var allRomaneos = capaService.SincronizarRomaneos().ToDictionary(r => r.RomaneoId, StringComparer.OrdinalIgnoreCase);

    var selectedRs = new List<Dictionary<string, object?>>();
    double totalKg = 0;
    string patente = "";

    if (body.TryGetValue("romaneos", out var rsArrayElem) && rsArrayElem.ValueKind == JsonValueKind.Array)
    {
        foreach (var rsItem in rsArrayElem.EnumerateArray())
        {
            var rsNum = rsItem.GetString() ?? rsItem.ToString();
            if (allRomaneos.TryGetValue(rsNum, out var m))
            {
                selectedRs.Add(new Dictionary<string, object?>
                {
                    ["romaneo"] = m.RomaneoId,
                    ["kgNeto"] = m.KgNeto,
                    ["cajas"] = m.Cajas,
                    ["patente"] = m.Patente,
                    ["destino"] = m.Destino,
                    ["fecha"] = m.Fecha,
                    ["hora"] = m.Hora,
                    ["observacion"] = m.Observacion,
                    ["con"] = m.Con,
                    ["conservacion"] = m.Conservacion
                });
                totalKg += m.KgNeto;
                if (string.IsNullOrEmpty(patente) && !string.IsNullOrEmpty(m.Patente))
                    patente = m.Patente;
            }
        }
    }

    carga.Romaneos = selectedRs;
    carga.KilosReales = Math.Round(totalKg, 2);
    carga.DesvioKilos = Math.Round(totalKg - carga.KilosEstimados, 2);
    if (!string.IsNullOrEmpty(patente)) carga.Patente = patente;

    db.GuardarCarga(carga);
    stockEngine.InvalidarCache();
    return Results.Ok(new { ok = true, kilosReales = carga.KilosReales, romaneosVinculados = selectedRs.Count });
});

app.Run($"http://0.0.0.0:{config.Puerto}");
