using System.Text.Json;

namespace Gorina.Stock.Api;

public sealed class Config
{
    public int Puerto { get; set; } = 8090;
    public string DbHost { get; set; } = "127.0.0.1";
    public int DbPort { get; set; } = 3306;
    public string DbUser { get; set; } = "root";
    public string DbPass { get; set; } = "gorina2025";
    public string DbName { get; set; } = "p002.stock.almacen.congelado";
    public string CarpetaStock { get; set; } = @"D:\PROYECTOS\P002.Stock.Almacen.Congelado\A PROBAR\STOCK";
    public string CarpetaCapa { get; set; } = @"J:\UTIL\USER\CAPA";

    public static Config Cargar(string[] args)
    {
        string? rutaConfig = null;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--config" && i + 1 < args.Length)
            {
                rutaConfig = args[++i];
            }
        }

        rutaConfig ??= Environment.GetEnvironmentVariable("GORINA_CONFIG")
            ?? Path.Combine(AppContext.BaseDirectory, "config.json");

        var config = new Config();
        if (File.Exists(rutaConfig))
        {
            try
            {
                var json = File.ReadAllText(rutaConfig);
                config = JsonSerializer.Deserialize<Config>(json, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true,
                    ReadCommentHandling = JsonCommentHandling.Skip,
                    AllowTrailingCommas = true
                }) ?? new Config();
            }
            catch { }
        }

        // Overrides desde variables de entorno
        if (Environment.GetEnvironmentVariable("DB_HOST") is string h && !string.IsNullOrWhiteSpace(h)) config.DbHost = h;
        if (int.TryParse(Environment.GetEnvironmentVariable("DB_PORT"), out var p)) config.DbPort = p;
        if (Environment.GetEnvironmentVariable("DB_USER") is string u && !string.IsNullOrWhiteSpace(u)) config.DbUser = u;
        if (Environment.GetEnvironmentVariable("DB_PASS") is string pass && !string.IsNullOrWhiteSpace(pass)) config.DbPass = pass;
        if (Environment.GetEnvironmentVariable("DB_NAME") is string db && !string.IsNullOrWhiteSpace(db)) config.DbName = db;
        if (Environment.GetEnvironmentVariable("CARPETA_STOCK") is string cs && !string.IsNullOrWhiteSpace(cs)) config.CarpetaStock = cs;

        return config;
    }
}
