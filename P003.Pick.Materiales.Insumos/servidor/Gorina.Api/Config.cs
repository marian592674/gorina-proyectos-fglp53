using System.Text.Json;

namespace Gorina.Api;

public sealed class Config
{
    public int Puerto { get; set; } = 8080;
    public string DbHost { get; set; } = "127.0.0.1";
    public int DbPort { get; set; } = 3306;
    public string DbUser { get; set; } = "root";
    public string DbPass { get; set; } = "gorina2025";
    public string DbName { get; set; } = "P003.Pick.Materiales.Insumos";
    public string BaseDatos { get; set; } = "P003.Pick.Materiales.Insumos";
    public string CarpetaSalida { get; set; } = @"C:\INTERFAZ_SAP\CONSUMOS";
    public string ClaseMovimiento { get; set; } = "201";
    public string Centro { get; set; } = "1001";
    public string LoteDefault { get; set; } = "1";
    public bool CabeceraEnTodasLasFilas { get; set; } = false;
    public string PrefijoNombre { get; set; } = "PICKQUIM";
    public string UsuarioAdminInicial { get; set; } = "admin";
    public string PinAdminInicial { get; set; } = "1234";
    public int IntervaloMonitoreoSapSegundos { get; set; } = 30;
    public int DiasHistorialApp { get; set; } = 30;
    public string CarpetaCatalogos { get; set; } = "Catalogos";
    public string LeyendaAuditoria { get; set; } = "AUDITORIA";

    public string RutaBaseDatos => Path.IsPathRooted(BaseDatos)
        ? BaseDatos
        : Path.Combine(AppContext.BaseDirectory, BaseDatos);

    public string RutaCarpetaSalida
    {
        get
        {
            var ruta = Path.IsPathRooted(CarpetaSalida)
                ? CarpetaSalida
                : Path.Combine(AppContext.BaseDirectory, CarpetaSalida);

            if (!Directory.Exists(ruta) && ruta.StartsWith(@"H:\", StringComparison.OrdinalIgnoreCase))
            {
                var unc = @"\\fglpsappro\archivos\" + ruta.Substring(3);
                if (Directory.Exists(unc)) return unc;
            }
            return ruta;
        }
    }

    public string RutaCarpetaCatalogos => Path.IsPathRooted(CarpetaCatalogos)
        ? CarpetaCatalogos
        : Path.Combine(AppContext.BaseDirectory, CarpetaCatalogos);

    private const string MensajeConfig =
        "Uso: Gorina.Api [--config <rutaconfig.json>] | --importar-equivalencias <archivo.xlsx> | " +
        "--importar-cecos <archivo.xlsx> | --importar-almacenes <archivo.xlsx> | " +
        "--importar-clases <archivo.xlsx> | --importar-centros <archivo.xlsx> (los importadores usan tambien --config)";

    public static (Config Config, List<string> Importes) Cargar(string[] args)
    {
        string? rutaConfig = null;
        var importes = new List<string>();

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--config" when i + 1 < args.Length:
                    rutaConfig = args[++i];
                    break;
                case "--importar-equivalencias" when i + 1 < args.Length:
                    importes.Add("equivalencias|" + args[++i]);
                    break;
                case "--importar-cecos" when i + 1 < args.Length:
                    importes.Add("cecos|" + args[++i]);
                    break;
                case "--importar-almacenes" when i + 1 < args.Length:
                    importes.Add("almacenes|" + args[++i]);
                    break;
                case "--importar-clases" when i + 1 < args.Length:
                    importes.Add("clases|" + args[++i]);
                    break;
                case "--importar-centros" when i + 1 < args.Length:
                    importes.Add("centros|" + args[++i]);
                    break;
                case "--ver-import" when i + 1 < args.Length:
                    Importador.DiagnosticarArchivo(args[++i]);
                    Environment.Exit(0);
                    break;
                default:
                    Console.WriteLine("Argumento no reconocido: " + args[i]);
                    Console.WriteLine(MensajeConfig);
                    Environment.Exit(2);
                    break;
            }
        }

        rutaConfig ??= Environment.GetEnvironmentVariable("GORINA_CONFIG")
            ?? Path.Combine(AppContext.BaseDirectory, "config.json");

        if (!File.Exists(rutaConfig))
        {
            Console.WriteLine("No se encontro el archivo de configuracion: " + rutaConfig);
            Console.WriteLine(MensajeConfig);
            Environment.Exit(2);
        }

        var json = File.ReadAllText(rutaConfig);
        var config = JsonSerializer.Deserialize<Config>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true
        }) ?? new Config();

        return (config, importes);
    }
}
