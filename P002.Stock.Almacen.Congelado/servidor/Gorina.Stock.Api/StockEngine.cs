using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Gorina.Stock.Api;

public sealed partial class StockEngine(Config config, Database db, ILogger<StockEngine> logger)
{
    private string? _cachedPayloadJson;
    private string? _cachedCsvName;
    private DateTime? _cachedCsvTime;
    private readonly object _lock = new();

    public string? CsvSeleccionado { get; set; }

    public FileInfo? ObtenerUltimoStockCsv()
    {
        var dir = config.CarpetaStock;
        if (!Directory.Exists(dir)) return null;

        if (!string.IsNullOrWhiteSpace(CsvSeleccionado) && File.Exists(CsvSeleccionado))
            return new FileInfo(CsvSeleccionado);

        var di = new DirectoryInfo(dir);
        var files = di.GetFiles("*.csv");
        if (files.Length == 0) return null;

        return files
            .OrderByDescending(f => ExtraerFechaNombre(f.Name) ?? f.LastWriteTime)
            .FirstOrDefault();
    }

    public static DateTime? ExtraerFechaNombre(string name)
    {
        // lista_cajas_yyyy-MM-dd_HH-mm-ss.csv
        var m = Regex.Match(name, @"lista_cajas_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})", RegexOptions.IgnoreCase);
        if (m.Success)
        {
            var f = m.Groups[1].Value + " " + m.Groups[2].Value.Replace('-', ':');
            if (DateTime.TryParseExact(f, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt))
                return dt;
        }
        return null;
    }

    public void InvalidarCache()
    {
        lock (_lock)
        {
            _cachedPayloadJson = null;
            _cachedCsvName = null;
            _cachedCsvTime = null;
        }
    }

    public string ObtenerPayload(bool forzar = false)
    {
        lock (_lock)
        {
            var csv = ObtenerUltimoStockCsv();
            if (csv == null)
            {
                return JsonSerializer.Serialize(new { error = "No se encontraron archivos de stock CSV en la carpeta configurada." });
            }

            var csvTime = ExtraerFechaNombre(csv.Name) ?? csv.LastWriteTime;
            if (!forzar && _cachedPayloadJson != null && _cachedCsvName == csv.Name && _cachedCsvTime == csvTime)
            {
                return _cachedPayloadJson;
            }

            logger.LogInformation("Procesando archivo CSV de Stock: {Nombre} ({Tamano:N0} bytes)", csv.Name, csv.Length);
            var payload = ProcesarCsv(csv);
            _cachedCsvName = csv.Name;
            _cachedCsvTime = csvTime;
            _cachedPayloadJson = JsonSerializer.Serialize(payload, new JsonSerializerOptions { PropertyNamingPolicy = null });
            return _cachedPayloadJson;
        }
    }

    private object ProcesarCsv(FileInfo csv)
    {
        var catalogo = db.GetCatalogo();
        var manual = db.GetAnalisisManual();
        var manualPallets = new HashSet<string>(manual.Pallets.Select(NormalizeLpn), StringComparer.OrdinalIgnoreCase);
        var manualCajas = new HashSet<string>(manual.Cajas.Select(NormalizeLpn), StringComparer.OrdinalIgnoreCase);

        var lineas = File.ReadAllLines(csv.FullName, Encoding.UTF8);
        if (lineas.Length < 2)
            throw new InvalidOperationException("El archivo CSV no contiene registros.");

        var delim = lineas[0].Contains(';') ? ';' : ',';
        var useQuotes = delim == ',';

        var headerLine = lineas[0];
        if (useQuotes && headerLine.StartsWith('"') && headerLine.EndsWith('"'))
            headerLine = headerLine.Substring(1, headerLine.Length - 2);

        var headerCols = useQuotes ? headerLine.Split("\",\"") : headerLine.Split(delim);
        var colMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < headerCols.Length; i++)
            colMap[headerCols[i].Trim()] = i;

        int iBox = colMap.GetValueOrDefault("Box ID", -1);
        int iSku = colMap.GetValueOrDefault("SKU", -1);
        int iProdName = colMap.GetValueOrDefault("Producto", -1);
        int iEstab = colMap.GetValueOrDefault("Est. Elaborador", -1);
        int iFaen = colMap.GetValueOrDefault("Est. Faenador", -1);
        int iLpn = colMap.GetValueOrDefault("LPN Pallet", -1);
        int iKilos = colMap.GetValueOrDefault("Peso neto (kg)", -1);
        int iVenta = colMap.GetValueOrDefault("Orden de venta", -1);
        int iProdDate = -1;

        foreach (var kv in colMap)
        {
            if (kv.Key.Contains("Produc", StringComparison.OrdinalIgnoreCase) || kv.Key.Contains("Fecha Prod", StringComparison.OrdinalIgnoreCase))
            {
                iProdDate = kv.Value;
                break;
            }
        }

        if (iLpn < 0 || iSku < 0 || iKilos < 0)
            throw new InvalidOperationException("El formato del CSV no contiene las columnas mínimas requeridas (LPN Pallet, SKU, Peso neto).");

        // Agrupamiento
        var groups = new Dictionary<string, GroupBuilder>();
        var skuProducto = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        for (int k = 1; k < lineas.Length; k++)
        {
            var line = lineas[k];
            if (string.IsNullOrWhiteSpace(line)) continue;

            string[] cells;
            if (useQuotes)
            {
                if (line.StartsWith('"') && line.EndsWith('"'))
                    line = line.Substring(1, line.Length - 2);
                cells = line.Split("\",\"");
            }
            else
            {
                cells = line.Split(delim);
            }

            if (cells.Length <= iLpn || cells.Length <= iSku || cells.Length <= iKilos) continue;

            var lpn = cells[iLpn].Trim();
            if (string.IsNullOrWhiteSpace(lpn)) continue;

            var sku = cells[iSku].Trim();
            var venta = (iVenta >= 0 && cells.Length > iVenta) ? cells[iVenta].Trim() : "";
            var estab = (iEstab >= 0 && cells.Length > iEstab) ? cells[iEstab].Trim() : "";
            var faen = (iFaen >= 0 && cells.Length > iFaen) ? cells[iFaen].Trim() : "";
            var boxId = (iBox >= 0 && cells.Length > iBox) ? cells[iBox].Trim() : "";
            var prodDate = (iProdDate >= 0 && cells.Length > iProdDate) ? cells[iProdDate].Trim() : "";
            var prodName = (iProdName >= 0 && cells.Length > iProdName) ? cells[iProdName].Trim() : "";

            if (!skuProducto.ContainsKey(sku) && !string.IsNullOrWhiteSpace(prodName))
                skuProducto[sku] = prodName;

            double kilos = 0;
            if (double.TryParse(cells[iKilos].Trim(), NumberStyles.Any, CultureInfo.InvariantCulture, out var kvVal))
                kilos = kvVal;
            else if (double.TryParse(cells[iKilos].Trim().Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out var kvVal2))
                kilos = kvVal2;

            var groupKey = $"{sku}|{venta}|{estab}|{faen}";
            if (!groups.TryGetValue(groupKey, out var group))
            {
                group = new GroupBuilder(sku, venta, estab, faen);
                groups[groupKey] = group;
            }

            group.AgregarCaja(lpn, boxId, kilos, prodDate);
        }

        // Armado de registros de salida
        var stockData = new List<Dictionary<string, object?>>();
        double totalKilos = 0;
        int totalCajas = 0;
        var uniquePallets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var group in groups.Values)
        {
            catalogo.TryGetValue(group.Sku, out var catInfo);
            var destino = (!string.IsNullOrWhiteSpace(catInfo?.Destino))
                ? catInfo.Destino
                : (group.Sku.Length >= 8 ? group.Sku.Substring(6, 2) : "");

            var nombre = (!string.IsNullOrWhiteSpace(catInfo?.Nombre))
                ? catInfo.Nombre
                : skuProducto.GetValueOrDefault(group.Sku, "");

            if (group.Sku.EndsWith("08") && !nombre.Contains("-ANGUS-", StringComparison.OrdinalIgnoreCase))
                nombre = $"{nombre.Trim()} -ANGUS-";

            bool esBrasil = TestEsBrasil(group.Sku, destino, nombre);

            int gPalletsOk = 0;
            int gPalletsPend = 0;
            int gCajasOk = 0;
            int gCajasPend = 0;
            double gKilosOk = 0;
            double gKilosPend = 0;

            var detallePallets = new List<Dictionary<string, object?>>();

            foreach (var pallet in group.Pallets.Values)
            {
                uniquePallets.Add(pallet.Lpn);
                var pNorm = NormalizeLpn(pallet.Lpn);
                bool palletIsManual = manualPallets.Contains(pNorm);

                int pCajasOk = 0;
                int pCajasPend = 0;
                double pKilosOk = 0;
                double pKilosPend = 0;

                var cajasDetalle = new List<Dictionary<string, object?>>();
                foreach (var b in pallet.Boxes)
                {
                    var bNorm = NormalizeLpn(b.BoxId);
                    bool boxIsManual = palletIsManual || manualCajas.Contains(bNorm);

                    string boxAnalisis = boxIsManual ? "OK" : "PENDIENTE";
                    if (boxAnalisis == "OK") { pCajasOk++; pKilosOk += b.Kilos; }
                    else { pCajasPend++; pKilosPend += b.Kilos; }

                    cajasDetalle.Add(new Dictionary<string, object?>
                    {
                        ["boxId"] = b.BoxId,
                        ["kilosNeto"] = b.Kilos,
                        ["fechaProd"] = b.FechaProd,
                        ["analisis"] = boxAnalisis,
                        ["manual"] = boxIsManual
                    });
                }

                string palletAnalisis = (pCajasPend == 0 && pCajasOk > 0) ? "OK" : "PENDIENTE";
                if (palletAnalisis == "OK") gPalletsOk++; else gPalletsPend++;

                gCajasOk += pCajasOk;
                gCajasPend += pCajasPend;
                gKilosOk += pKilosOk;
                gKilosPend += pKilosPend;

                detallePallets.Add(new Dictionary<string, object?>
                {
                    ["lpn"] = pallet.Lpn,
                    ["cajas"] = pallet.Cajas,
                    ["kilos"] = Math.Round(pallet.Kilos, 1),
                    ["analisis"] = palletAnalisis,
                    ["cajasConAnalisis"] = pCajasOk,
                    ["cajasSinAnalisis"] = pCajasPend,
                    ["kilosConAnalisis"] = Math.Round(pKilosOk, 1),
                    ["kilosSinAnalisis"] = Math.Round(pKilosPend, 1),
                    ["cajasDetalle"] = cajasDetalle
                });
            }

            string generalAnalisis = (gCajasPend == 0 && gCajasOk > 0) ? "OK"
                : (gCajasOk == 0 && gCajasPend > 0) ? "PENDIENTE"
                : (gCajasOk > 0 && gCajasPend > 0) ? "MIXTO" : "NA";

            totalKilos += group.TotalKilos;
            totalCajas += group.TotalCajas;

            stockData.Add(new Dictionary<string, object?>
            {
                ["sku"] = group.Sku,
                ["nombre"] = nombre,
                ["destino"] = destino,
                ["venta"] = group.Venta,
                ["establecimiento"] = group.Estab,
                ["estabFaenador"] = group.Faen,
                ["matSap"] = catInfo?.MaterialSap ?? "",
                ["pallets"] = group.Pallets.Count,
                ["cajas"] = group.TotalCajas,
                ["kilosNeto"] = Math.Round(group.TotalKilos, 1),
                ["esBrasil"] = esBrasil,
                ["analisis"] = generalAnalisis,
                ["palletsConAnalisis"] = gPalletsOk,
                ["palletsSinAnalisis"] = gPalletsPend,
                ["cajasConAnalisis"] = gCajasOk,
                ["cajasSinAnalisis"] = gCajasPend,
                ["kilosConAnalisis"] = Math.Round(gKilosOk, 1),
                ["kilosSinAnalisis"] = Math.Round(gKilosPend, 1),
                ["detalle"] = detallePallets
            });
        }

        // Agregar SKUs del catalogo sin stock
        var skusConStock = new HashSet<string>(groups.Values.Select(g => g.Sku), StringComparer.OrdinalIgnoreCase);
        foreach (var (sku, catInfo) in catalogo)
        {
            if (!skusConStock.Contains(sku))
            {
                var destino = (!string.IsNullOrWhiteSpace(catInfo?.Destino))
                    ? catInfo.Destino
                    : (sku.Length >= 8 ? sku.Substring(6, 2) : "");

                var nombre = catInfo?.Nombre ?? "";
                if (sku.EndsWith("08") && !nombre.Contains("-ANGUS-", StringComparison.OrdinalIgnoreCase))
                    nombre = $"{nombre.Trim()} -ANGUS-";

                bool esBrasil = TestEsBrasil(sku, destino, nombre);

                stockData.Add(new Dictionary<string, object?>
                {
                    ["sku"] = sku,
                    ["nombre"] = nombre,
                    ["destino"] = destino,
                    ["venta"] = "",
                    ["establecimiento"] = "",
                    ["estabFaenador"] = "",
                    ["matSap"] = catInfo?.MaterialSap ?? "",
                    ["pallets"] = 0,
                    ["cajas"] = 0,
                    ["kilosNeto"] = 0,
                    ["esBrasil"] = esBrasil,
                    ["analisis"] = "NA",
                    ["palletsConAnalisis"] = 0,
                    ["palletsSinAnalisis"] = 0,
                    ["cajasConAnalisis"] = 0,
                    ["cajasSinAnalisis"] = 0,
                    ["kilosConAnalisis"] = 0,
                    ["kilosSinAnalisis"] = 0,
                    ["detalle"] = new List<object>()
                });
            }
        }

        var cargas = db.GetCargas();
        var romaneos = db.GetRomaneos();
        var lastUpdate = (ExtraerFechaNombre(csv.Name) ?? csv.LastWriteTime).ToString("dd/MM/yyyy HH:mm");

        return new Dictionary<string, object?>
        {
            ["stockData"] = stockData,
            ["lastUpdate"] = lastUpdate,
            ["csvName"] = csv.Name,
            ["carpeta"] = config.CarpetaStock,
            ["fechaProdDisponible"] = (iProdDate >= 0),
            ["cargas"] = cargas,
            ["romaneos"] = romaneos,
            ["analisisManual"] = manual,
            ["metadata"] = new Dictionary<string, object?>
            {
                ["csvName"] = csv.Name,
                ["csvDate"] = (ExtraerFechaNombre(csv.Name) ?? csv.LastWriteTime).ToString("yyyy-MM-dd HH:mm:ss"),
                ["serverTime"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                ["totalPallets"] = uniquePallets.Count,
                ["totalCajas"] = totalCajas,
                ["totalKilos"] = Math.Round(totalKilos, 1)
            }
        };
    }

    private static bool TestEsBrasil(string sku, string destino, string nombre)
    {
        if (!string.IsNullOrWhiteSpace(destino))
        {
            if (destino.Trim() == "10" || destino.Contains("BRASIL", StringComparison.OrdinalIgnoreCase) || destino.Contains("BR", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        if (sku.Length >= 8 && sku.Substring(6, 2) == "10")
            return true;
        if (nombre.Contains("BRASIL", StringComparison.OrdinalIgnoreCase))
            return true;
        return false;
    }

    public static string NormalizeLpn(string lpn)
    {
        if (string.IsNullOrWhiteSpace(lpn)) return "";
        var trimmed = lpn.Trim().TrimStart('0');
        return string.IsNullOrEmpty(trimmed) ? "0" : trimmed;
    }

    private sealed class GroupBuilder(string sku, string venta, string estab, string faen)
    {
        public string Sku { get; } = sku;
        public string Venta { get; } = venta;
        public string Estab { get; } = estab;
        public string Faen { get; } = faen;
        public Dictionary<string, PalletBuilder> Pallets { get; } = new(StringComparer.OrdinalIgnoreCase);
        public int TotalCajas { get; private set; }
        public double TotalKilos { get; private set; }

        public void AgregarCaja(string lpn, string boxId, double kilos, string fechaProd)
        {
            if (!Pallets.TryGetValue(lpn, out var p))
            {
                p = new PalletBuilder(lpn);
                Pallets[lpn] = p;
            }
            p.Agregar(boxId, kilos, fechaProd);
            TotalCajas++;
            TotalKilos += kilos;
        }
    }

    private sealed class PalletBuilder(string lpn)
    {
        public string Lpn { get; } = lpn;
        public int Cajas { get; private set; }
        public double Kilos { get; private set; }
        public List<BoxRecord> Boxes { get; } = new();

        public void Agregar(string boxId, double kilos, string fechaProd)
        {
            Cajas++;
            Kilos += kilos;
            Boxes.Add(new BoxRecord(boxId, kilos, fechaProd));
        }
    }

    private sealed record BoxRecord(string BoxId, double Kilos, string FechaProd);
}
