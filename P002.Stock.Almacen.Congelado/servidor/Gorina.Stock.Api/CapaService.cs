using System.Globalization;
using System.Text.RegularExpressions;

namespace Gorina.Stock.Api;

public sealed class CapaService(Config config, Database db, ILogger<CapaService> logger)
{
    public string ResolverCarpetaCapa()
    {
        if (Directory.Exists(config.CarpetaCapa)) return config.CarpetaCapa;
        var unc = @"\\svr\d\UTIL\USER\CAPA";
        if (Directory.Exists(unc)) return unc;
        return config.CarpetaCapa;
    }

    public List<Romaneo> SincronizarRomaneos()
    {
        var carpeta = ResolverCarpetaCapa();
        if (!Directory.Exists(carpeta))
        {
            logger.LogWarning("Carpeta de romaneos CAPA no disponible: {Carpeta}", carpeta);
            return db.GetRomaneos();
        }

        var romaneosDb = db.GetRomaneos().ToDictionary(r => r.RomaneoId, StringComparer.OrdinalIgnoreCase);
        var nuevosRomaneos = new List<Romaneo>();

        var di = new DirectoryInfo(carpeta);
        var files = di.GetFiles("*.csv").OrderByDescending(f => f.LastWriteTime).Take(500);

        foreach (var file in files)
        {
            try
            {
                var m = Regex.Match(file.Name, @"(?:^|_)(?:00)?(\d{6,8})\.csv$", RegexOptions.IgnoreCase);
                if (!m.Success) continue;

                var romaneoNum = m.Groups[1].Value.TrimStart('0');
                if (romaneosDb.TryGetValue(romaneoNum, out var existente) && existente.Ticks.HasValue && existente.Ticks.Value >= file.LastWriteTimeUtc.Ticks)
                {
                    continue;
                }

                var lineas = File.ReadAllLines(file.FullName);
                if (lineas.Length < 2) continue;

                var headers = lineas[0].Split(';').Select(h => h.Trim()).ToList();
                int idxPatente = headers.FindIndex(h => h.Equals("Patente", StringComparison.OrdinalIgnoreCase));
                int idxDestino = headers.FindIndex(h => h.Equals("Destino", StringComparison.OrdinalIgnoreCase));
                int idxObs = headers.FindIndex(h => h.Equals("Observacion", StringComparison.OrdinalIgnoreCase) || h.Equals("Observaciones", StringComparison.OrdinalIgnoreCase));
                int idxCon = headers.FindIndex(h => h.Equals("Con", StringComparison.OrdinalIgnoreCase));
                int idxCons = headers.FindIndex(h => h.Equals("Conservacion", StringComparison.OrdinalIgnoreCase));
                int idxKg = headers.FindIndex(h => h.Contains("Neto", StringComparison.OrdinalIgnoreCase));
                int idxFecha = headers.FindIndex(h => h.Equals("Fecha", StringComparison.OrdinalIgnoreCase));
                int idxHora = headers.FindIndex(h => h.Equals("Hora", StringComparison.OrdinalIgnoreCase));
                int idxDep = headers.FindIndex(h => h.Equals("Dep", StringComparison.OrdinalIgnoreCase) || h.Equals("Deposito", StringComparison.OrdinalIgnoreCase));

                double totalKg = 0;
                int totalCajas = 0;
                string patente = "";
                string destino = "";
                string observacion = "";
                string con = "";
                string conservacion = "";
                string fecha = "";
                string hora = "";
                string dep = "";

                for (int i = 1; i < lineas.Length; i++)
                {
                    if (string.IsNullOrWhiteSpace(lineas[i])) continue;
                    var cols = lineas[i].Split(';');
                    totalCajas++;

                    if (idxKg >= 0 && cols.Length > idxKg && double.TryParse(cols[idxKg].Trim().Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out var kg))
                        totalKg += kg;

                    if (string.IsNullOrEmpty(patente) && idxPatente >= 0 && cols.Length > idxPatente) patente = cols[idxPatente].Trim();
                    if (string.IsNullOrEmpty(destino) && idxDestino >= 0 && cols.Length > idxDestino) destino = cols[idxDestino].Trim();
                    if (string.IsNullOrEmpty(observacion) && idxObs >= 0 && cols.Length > idxObs) observacion = cols[idxObs].Trim();
                    if (string.IsNullOrEmpty(con) && idxCon >= 0 && cols.Length > idxCon) con = cols[idxCon].Trim();
                    if (string.IsNullOrEmpty(conservacion) && idxCons >= 0 && cols.Length > idxCons) conservacion = cols[idxCons].Trim();
                    if (string.IsNullOrEmpty(fecha) && idxFecha >= 0 && cols.Length > idxFecha) fecha = cols[idxFecha].Trim();
                    if (string.IsNullOrEmpty(hora) && idxHora >= 0 && cols.Length > idxHora) hora = cols[idxHora].Trim();
                    if (string.IsNullOrEmpty(dep) && idxDep >= 0 && cols.Length > idxDep) dep = cols[idxDep].Trim();
                }

                var rObj = new Romaneo
                {
                    RomaneoId = romaneoNum,
                    Tipo = "RS",
                    Fecha = fecha,
                    Hora = hora,
                    Observacion = observacion,
                    Con = con,
                    Conservacion = conservacion,
                    Patente = patente,
                    Destino = destino,
                    Cajas = totalCajas,
                    KgNeto = Math.Round(totalKg, 2),
                    Deposito = dep,
                    Archivo = file.Name,
                    Ticks = file.LastWriteTimeUtc.Ticks
                };

                nuevosRomaneos.Add(rObj);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Error al leer romaneo CAPA {Archivo}", file.Name);
            }
        }

        if (nuevosRomaneos.Count > 0)
        {
            db.GuardarRomaneos(nuevosRomaneos);
            logger.LogInformation("Sincronizados {Cantidad} romaneos CAPA en MySQL", nuevosRomaneos.Count);
        }

        return db.GetRomaneos();
    }
}
