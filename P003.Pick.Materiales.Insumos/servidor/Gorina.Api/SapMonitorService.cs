using System.Globalization;
using System.Text.RegularExpressions;

namespace Gorina.Api;

public sealed partial class SapMonitorService(
    Database database,
    Config config,
    ILogger<SapMonitorService> logger) : BackgroundService
{
    [GeneratedRegex(@"^(?<base>.*)_(?<estado>OK|NP)_(?<fecha>\d{8})_(?<hora>\d{6})\.csv$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PatronResultado();

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Monitor SAP activo en {Carpeta}", config.RutaCarpetaSalida);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                RevisarResultados();
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error revisando resultados SAP");
            }

            var segundos = Math.Max(5, config.IntervaloMonitoreoSapSegundos);
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(segundos), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
        }
    }

    public void RevisarResultados()
    {
        var descartados = database.Ejecutar("""
            UPDATE operaciones
            SET estado_sap = 'NP', msg_error = 'Descartado por antiguedad (>120hs sin respuesta SAP)'
            WHERE (estado_sap IS NULL OR estado_sap = 'PENDIENTE')
              AND fecha_cierre IS NOT NULL
              AND fecha_cierre < DATE_SUB(NOW(), INTERVAL 120 HOUR)
            """);
        if (descartados > 0)
        {
            logger.LogInformation("Se descartaron {Cantidad} operaciones atascadas en SAP (> 120 hs).", descartados);
        }

        var carpeta = config.RutaCarpetaSalida;
        if (!Directory.Exists(carpeta))
        {
            logger.LogWarning("La carpeta SAP no existe o no esta disponible: {Carpeta}", carpeta);
            return;
        }

        // Purgar operaciones atascadas cuyo archivo ya no esta en SAP y supero 4 horas
        var pendientes = database.Consultar("""
            SELECT id, orden, archivo_nombre, archivo_fecha
            FROM operaciones
            WHERE estado = 'PROCESADO'
              AND (estado_sap IS NULL OR estado_sap = 'PENDIENTE')
              AND archivo_nombre IS NOT NULL
              AND archivo_fecha < DATE_SUB(NOW(), INTERVAL 4 HOUR)
            """);

        foreach (var op in pendientes)
        {
            var nombreOp = op["archivo_nombre"]?.ToString();
            if (string.IsNullOrWhiteSpace(nombreOp)) continue;
            var rutaEsperada = Path.Combine(carpeta, nombreOp);
            if (!File.Exists(rutaEsperada))
            {
                database.Ejecutar("""
                    UPDATE operaciones
                    SET estado_sap = 'NP',
                        msg_error = 'Archivo retirado de la carpeta SAP sin comprobante de respuesta'
                    WHERE id = @id AND (estado_sap IS NULL OR estado_sap = 'PENDIENTE')
                    """, p => p.AddWithValue("@id", op["id"]?.ToString()));
                logger.LogWarning("Operacion {Operacion} (Orden {Orden}): archivo {Archivo} desaparecio de SAP sin confirmacion.",
                    op["id"], op["orden"], nombreOp);
            }
        }

        var archivosProcesados = new HashSet<string>(
            database.Consultar("SELECT archivo_nombre FROM eventos_sap UNION SELECT archivo_nombre FROM incidencias_sap")
                .Select(f => f["archivo_nombre"]?.ToString() ?? ""),
            StringComparer.OrdinalIgnoreCase);

        var operaciones = database.Consultar("""
            SELECT id, orden, archivo_nombre, estado_sap, estado_sap_fecha
            FROM operaciones
            WHERE archivo_nombre IS NOT NULL AND archivo_nombre != ''
              AND (estado_sap IS NULL OR estado_sap != 'OK')
            """);
        var porBase = operaciones
            .Where(o => !string.IsNullOrWhiteSpace(o["archivo_nombre"]?.ToString()))
            .GroupBy(o => Path.GetFileNameWithoutExtension(o["archivo_nombre"]!.ToString()!),
                StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);
        var porOrden = operaciones
            .Where(o => !string.IsNullOrWhiteSpace(o["orden"]?.ToString()))
            .GroupBy(o => NormalizarOrden(o["orden"]!.ToString()!), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

        foreach (var ruta in Directory.EnumerateFiles(carpeta, "*.csv", SearchOption.AllDirectories))
        {
            try
            {
                var nombre = Path.GetFileName(ruta);
                if (archivosProcesados.Contains(nombre)) continue;
                var match = PatronResultado().Match(nombre);
                if (!match.Success) continue;

                var textoFecha = match.Groups["fecha"].Value + match.Groups["hora"].Value;
                if (!DateTime.TryParseExact(textoFecha, "yyyyMMddHHmmss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var fechaSap) &&
                    !DateTime.TryParseExact(textoFecha, "ddMMyyyyHHmmss", CultureInfo.InvariantCulture, DateTimeStyles.None, out fechaSap))
                    continue;

                Dictionary<string, object?>? operacion = null;
                var estado = match.Groups["estado"].Value.ToUpperInvariant();
                var nombreBase = match.Groups["base"].Value;
                if (!string.IsNullOrWhiteSpace(nombreBase))
                    porBase.TryGetValue(nombreBase, out operacion);

                var datosCsv = LeerDatosResultadoCsv(ruta);
                string? ordenDetectada = datosCsv.Orden;

                if (operacion is null)
                {
                    if (string.IsNullOrWhiteSpace(ordenDetectada))
                        ordenDetectada = LeerOrdenCsv(ruta);

                    if (string.IsNullOrWhiteSpace(ordenDetectada) && !string.IsNullOrWhiteSpace(nombreBase))
                    {
                        var matchOrden = Regex.Match(nombreBase, @"(?:^|_)(?<num>\d+)(?:_\d+)*$", RegexOptions.CultureInvariant);
                        if (matchOrden.Success) ordenDetectada = matchOrden.Groups["num"].Value;
                    }

                    if (!string.IsNullOrWhiteSpace(ordenDetectada))
                        porOrden.TryGetValue(NormalizarOrden(ordenDetectada), out operacion);
                }

                var fecha = fechaSap.ToString("yyyy-MM-dd HH:mm:ss");
                if (operacion is null)
                {
                    if (estado == "NP") RegistrarIncidencia(nombre, ordenDetectada, fecha);
                    continue;
                }

                string? docSap = estado == "OK" ? datosCsv.DocSap : null;
                string? estadoDetalle = datosCsv.EstadoDetalle;
                string? motivoRechazo = null;
                if (estado == "NP")
                {
                    motivoRechazo = !string.IsNullOrWhiteSpace(datosCsv.Mensaje)
                        ? datosCsv.Mensaje
                        : BuscarMotivoRechazoLucas(carpeta, ruta, ordenDetectada ?? operacion["orden"]?.ToString(), nombreBase);
                }

                RegistrarEvento(operacion["id"]!.ToString()!, estado, nombre, fecha, motivoRechazo, docSap, estadoDetalle);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "No se pudo procesar el resultado SAP {Archivo}", ruta);
            }
        }
    }

    private static string NormalizarOrden(string orden) =>
        long.TryParse(orden.Trim(), out var numero) ? numero.ToString() : orden.Trim();

    private record DatosResultadoCsv(string? Orden, string? DocSap, string? Mensaje, string? EstadoDetalle);

    private static DatosResultadoCsv LeerDatosResultadoCsv(string ruta)
    {
        try
        {
            var lineas = File.ReadLines(ruta).Take(5).ToList();
            if (lineas.Count < 2) return new(null, null, null, null);

            var headers = lineas[0].Split(';').Select(h => h.Trim()).ToList();
            int idxOrden = headers.FindIndex(h => h.Equals("Orden", StringComparison.OrdinalIgnoreCase));
            if (idxOrden < 0) idxOrden = 0;

            int idxDocSap = headers.FindIndex(h => h.Contains("Doc", StringComparison.OrdinalIgnoreCase) && h.Contains("SAP", StringComparison.OrdinalIgnoreCase));
            int idxMensaje = headers.FindIndex(h => h.Equals("Mensaje", StringComparison.OrdinalIgnoreCase) || h.StartsWith("Mensaje", StringComparison.OrdinalIgnoreCase));
            int idxEstado = headers.FindIndex(h => h.Equals("Estado", StringComparison.OrdinalIgnoreCase) || h.StartsWith("Estado", StringComparison.OrdinalIgnoreCase));

            for (int i = 1; i < lineas.Count; i++)
            {
                if (string.IsNullOrWhiteSpace(lineas[i])) continue;
                var cols = lineas[i].Split(';');
                string? orden = cols.Length > idxOrden ? cols[idxOrden].Trim() : null;

                string? docSap = null;
                if (idxDocSap >= 0 && cols.Length > idxDocSap) docSap = cols[idxDocSap].Trim();
                else if (cols.Length > 11 && !string.IsNullOrWhiteSpace(cols[11])) docSap = cols[11].Trim();

                string? mensaje = null;
                if (idxMensaje >= 0 && cols.Length > idxMensaje) mensaje = cols[idxMensaje].Trim();
                else if (cols.Length > 12 && !string.IsNullOrWhiteSpace(cols[12])) mensaje = cols[12].Trim();

                string? estadoDetalle = null;
                if (idxEstado >= 0 && cols.Length > idxEstado) estadoDetalle = cols[idxEstado].Trim();
                else if (cols.Length > 13 && !string.IsNullOrWhiteSpace(cols[13])) estadoDetalle = cols[13].Trim();

                return new DatosResultadoCsv(orden, docSap, mensaje, estadoDetalle);
            }
        }
        catch
        {
            // Omitir bloqueos de lectura
        }
        return new(null, null, null, null);
    }

    private static string? LeerOrdenCsv(string ruta)
    {
        try
        {
            foreach (var linea in File.ReadLines(ruta).Skip(1))
            {
                if (string.IsNullOrWhiteSpace(linea)) continue;
                var separador = linea.IndexOf(';');
                var orden = (separador >= 0 ? linea[..separador] : linea).Trim();
                if (!string.IsNullOrWhiteSpace(orden)) return orden;
            }
        }
        catch
        {
            // Omitir bloqueos temporales de lectura
        }
        return null;
    }

    private void RegistrarEvento(string operacionId, string estado, string archivo,
        string fechaSap, string? motivoRechazo = null, string? docSap = null, string? estadoDetalle = null)
    {
        var insertados = database.Ejecutar("""
            INSERT IGNORE INTO eventos_sap
                (operacion_id, estado, archivo_nombre, fecha_sap, detectado_utc)
            VALUES (@id, @estado, @archivo, @fecha, @detectado)
            """, p =>
        {
            p.AddWithValue("@id", operacionId);
            p.AddWithValue("@estado", estado);
            p.AddWithValue("@archivo", archivo);
            p.AddWithValue("@fecha", fechaSap);
            p.AddWithValue("@detectado", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
        });

        database.Ejecutar("""
            UPDATE operaciones
            SET estado_sap = @estado,
                archivo_sap_nombre = @archivo,
                estado_sap_fecha = @fecha,
                doc_sap = CASE WHEN @estado = 'OK' THEN COALESCE(@docSap, doc_sap) ELSE doc_sap END,
                estado_sap_detalle = COALESCE(@estadoDetalle, estado_sap_detalle),
                msg_error = CASE WHEN @estado = 'NP' THEN COALESCE(@motivo, msg_error, 'Rechazado por SAP (NP)')
                                 WHEN @estado = 'OK' THEN NULL
                                 ELSE msg_error END
            WHERE id = @id
              AND (estado_sap_fecha IS NULL OR estado_sap_fecha <= @fecha)
            """, p =>
        {
            p.AddWithValue("@estado", estado);
            p.AddWithValue("@archivo", archivo);
            p.AddWithValue("@fecha", fechaSap);
            p.AddWithValue("@docSap", string.IsNullOrWhiteSpace(docSap) ? (object)DBNull.Value : docSap.Trim());
            p.AddWithValue("@estadoDetalle", string.IsNullOrWhiteSpace(estadoDetalle) ? (object)DBNull.Value : estadoDetalle.Trim());
            p.AddWithValue("@motivo", string.IsNullOrWhiteSpace(motivoRechazo) ? (object)DBNull.Value : motivoRechazo.Trim());
            p.AddWithValue("@id", operacionId);
        });

        if (insertados > 0)
        {
            logger.LogInformation("Resultado SAP {Estado} detectado para operacion {Operacion}: {Archivo} | Doc: {Doc} | Detalle: {Detalle}",
                estado, operacionId, archivo, docSap ?? "-", estadoDetalle ?? "-");
        }
    }

    private static string? BuscarMotivoRechazoLucas(string carpeta, string rutaCsv, string? orden, string nombreBase)
    {
        try
        {
            var dir = Path.GetDirectoryName(rutaCsv) ?? carpeta;

            // 1. Archivo específico con el mismo nombre base (.txt o .log)
            var txtMismoNombre = Path.ChangeExtension(rutaCsv, ".txt");
            if (File.Exists(txtMismoNombre))
            {
                var txt = File.ReadAllText(txtMismoNombre).Trim();
                if (!string.IsNullOrWhiteSpace(txt)) return Limitar(txt, 250);
            }

            var logMismoNombre = Path.ChangeExtension(rutaCsv, ".log");
            if (File.Exists(logMismoNombre))
            {
                var txt = File.ReadAllText(logMismoNombre).Trim();
                if (!string.IsNullOrWhiteSpace(txt)) return Limitar(txt, 250);
            }

            // 2. Archivo que contenga el número de orden en su nombre dentro de la carpeta
            if (!string.IsNullOrWhiteSpace(orden))
            {
                foreach (var ext in new[] { "*.txt", "*.log" })
                {
                    foreach (var f in Directory.EnumerateFiles(dir, ext))
                    {
                        var fn = Path.GetFileNameWithoutExtension(f);
                        if (fn.Contains(orden, StringComparison.OrdinalIgnoreCase))
                        {
                            var txt = File.ReadAllText(f).Trim();
                            if (!string.IsNullOrWhiteSpace(txt)) return Limitar(txt, 250);
                        }
                    }
                }
            }

            // 3. Archivo central de log en la carpeta No Procesados (ej. log.txt, errores.log, rechazos.log)
            foreach (var central in new[] { "errores.log", "error.log", "log.txt", "rechazos.log" })
            {
                var rutaCentral = Path.Combine(dir, central);
                if (File.Exists(rutaCentral) && !string.IsNullOrWhiteSpace(orden))
                {
                    foreach (var linea in File.ReadLines(rutaCentral).Reverse())
                    {
                        if (linea.Contains(orden, StringComparison.OrdinalIgnoreCase))
                            return Limitar(linea.Trim(), 250);
                    }
                }
            }
        }
        catch
        {
            // Omitir bloqueos de lectura
        }
        return null;
    }

    private static string Limitar(string texto, int max) =>
        texto.Length <= max ? texto : texto[..max] + "...";

    private void RegistrarIncidencia(string archivo, string? orden, string fechaSap)
    {
        var insertados = database.Ejecutar("""
            INSERT IGNORE INTO incidencias_sap
                (estado, archivo_nombre, orden_detectada, fecha_sap, detectado_utc, detalle)
            VALUES ('NP', @archivo, @orden, @fecha, @detectado,
                    'Resultado SAP NP sin operacion asociada')
            """, p =>
        {
            p.AddWithValue("@archivo", archivo);
            p.AddWithValue("@orden", string.IsNullOrWhiteSpace(orden) ? (object?)DBNull.Value : orden.Trim());
            p.AddWithValue("@fecha", fechaSap);
            p.AddWithValue("@detectado", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
        });
        if (insertados > 0)
            logger.LogWarning("Resultado SAP NP sin operacion asociada: {Archivo}, orden {Orden}",
                archivo, orden ?? "no informada");
    }
}
