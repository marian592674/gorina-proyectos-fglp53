using System.Globalization;
using System.Text;

namespace Gorina.Api;

public static class CsvGenerator
{
    private static readonly string[] Encabezados =
    {
        "Orden", "Cl.movimiento", "Centro", "Almacen", "Material",
        "Unidad de medida", "Centro de costo", "Lote", "Cantidad",
        "Texto cabecera", "texto posicion"
    };

    public static (string NombreArchivo, string RutaCompleta) Generar(
        Config config,
        Dictionary<string, object?> operacion,
        List<Dictionary<string, object?>> posiciones)
    {
        if (!Directory.Exists(config.RutaCarpetaSalida))
            throw new DirectoryNotFoundException("Carpeta de salida no disponible: " + config.RutaCarpetaSalida);

        bool esAuditoria = Texto(operacion["tipo"]).Equals("AUDITORIA", StringComparison.OrdinalIgnoreCase) ||
                           Texto(operacion["clase_movimiento"]).Contains("AUD", StringComparison.OrdinalIgnoreCase);

        string prefijo = esAuditoria ? $"{config.PrefijoNombre}_AUD" : config.PrefijoNombre;
        string orden = Texto(operacion["orden"]);
        string marcaTiempo = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        string nombre = $"{prefijo}_{marcaTiempo}_{Suficiente(orden)}.csv";
        string ruta = Path.Combine(config.RutaCarpetaSalida, nombre);

        int sufijo = 2;
        while (File.Exists(ruta))
        {
            nombre = $"{prefijo}_{marcaTiempo}_{Suficiente(orden)}_{sufijo++}.csv";
            ruta = Path.Combine(config.RutaCarpetaSalida, nombre);
        }

        var sb = new StringBuilder();
        sb.AppendLine(string.Join(";", Encabezados));

        bool primeraFilaDatos = true;

        foreach (var posicion in posiciones.OrderBy(p => Convert.ToInt64(p["linea"])))
        {
            string textoCabecera = primeraFilaDatos || config.CabeceraEnTodasLasFilas
                ? Texto(operacion["texto_cabecera"])
                : string.Empty;

            if (esAuditoria && (primeraFilaDatos || config.CabeceraEnTodasLasFilas))
            {
                if (!textoCabecera.Contains(config.LeyendaAuditoria, StringComparison.OrdinalIgnoreCase))
                {
                    textoCabecera = string.IsNullOrWhiteSpace(textoCabecera)
                        ? config.LeyendaAuditoria
                        : $"{textoCabecera} [{config.LeyendaAuditoria}]";
                }
            }
            primeraFilaDatos = false;

            double cantidad = Convert.ToDouble(posicion["cantidad_sap"], CultureInfo.InvariantCulture);

            var campos = new[]
            {
                Escapar(Texto(operacion["orden"])),
                Escapar(Texto(operacion["clase_movimiento"])),
                Escapar(Texto(operacion["centro"])),
                Escapar(Texto(operacion["almacen"])),
                Escapar(Texto(posicion["material_sap"])),
                Escapar(Texto(posicion["unidad_sap"])),
                Escapar(Texto(operacion["ceco"])),
                Escapar(config.LoteDefault),
                cantidad.ToString(CultureInfo.InvariantCulture),
                Escapar(textoCabecera),
                Escapar(Texto(posicion["texto_posicion"]))
            };

            sb.AppendLine(string.Join(";", campos));
        }

        File.WriteAllText(ruta, sb.ToString(), new UTF8Encoding(false));
        return (nombre, ruta);
    }

    private static string Escapar(string? valor)
    {
        if (string.IsNullOrEmpty(valor)) return string.Empty;
        if (valor.Contains(';') || valor.Contains('"') || valor.Contains('\n') || valor.Contains('\r'))
        {
            return $"\"{valor.Replace("\"", "\"\"")}\"";
        }
        return valor;
    }

    private static string Suficiente(string orden) =>
        string.IsNullOrWhiteSpace(orden) ? "SINORDEN" : string.Join("_", orden.Split(Path.GetInvalidFileNameChars()));

    private static string Texto(object? valor) => valor?.ToString() ?? string.Empty;
}
