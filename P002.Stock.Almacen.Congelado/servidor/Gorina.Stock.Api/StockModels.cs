using System.Text.Json.Serialization;

namespace Gorina.Stock.Api;

public sealed class CatalogoItem
{
    public string Sku { get; set; } = "";
    public string Nombre { get; set; } = "";
    public string Destino { get; set; } = "";
    public string MaterialSap { get; set; } = "";
}

public sealed class Carga
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("fecha")]
    public string? Fecha { get; set; }

    [JsonPropertyName("hora")]
    public string? Hora { get; set; }

    [JsonPropertyName("estado")]
    public string Estado { get; set; } = "En Proceso";

    [JsonPropertyName("cliente")]
    public string? Cliente { get; set; }

    [JsonPropertyName("conservacion")]
    public string? Conservacion { get; set; }

    [JsonPropertyName("pallets_solicitados")]
    public int PalletsSolicitados { get; set; }

    [JsonPropertyName("kilos_estimados")]
    public double KilosEstimados { get; set; }

    [JsonPropertyName("kilos_reales")]
    public double? KilosReales { get; set; }

    [JsonPropertyName("desvio_kilos")]
    public double? DesvioKilos { get; set; }

    [JsonPropertyName("patente")]
    public string? Patente { get; set; }

    [JsonPropertyName("observaciones")]
    public string? Observaciones { get; set; }

    [JsonPropertyName("ordenes_count")]
    public int OrdenesCount { get; set; }

    [JsonPropertyName("origen_automatico")]
    public bool? OrigenAutomatico { get; set; }

    [JsonPropertyName("items")]
    public List<Dictionary<string, object?>> Items { get; set; } = new();

    [JsonPropertyName("romaneos")]
    public List<Dictionary<string, object?>> Romaneos { get; set; } = new();
}

public sealed class Romaneo
{
    [JsonPropertyName("romaneo")]
    public string RomaneoId { get; set; } = "";

    [JsonPropertyName("tipo")]
    public string Tipo { get; set; } = "RS";

    [JsonPropertyName("fecha")]
    public string? Fecha { get; set; }

    [JsonPropertyName("hora")]
    public string? Hora { get; set; }

    [JsonPropertyName("observacion")]
    public string? Observacion { get; set; }

    [JsonPropertyName("con")]
    public string? Con { get; set; }

    [JsonPropertyName("conservacion")]
    public string? Conservacion { get; set; }

    [JsonPropertyName("patente")]
    public string? Patente { get; set; }

    [JsonPropertyName("destino")]
    public string? Destino { get; set; }

    [JsonPropertyName("cajas")]
    public int Cajas { get; set; }

    [JsonPropertyName("kgNeto")]
    public double KgNeto { get; set; }

    [JsonPropertyName("ofertas")]
    public string? Ofertas { get; set; }

    [JsonPropertyName("cliente")]
    public string? Cliente { get; set; }

    [JsonPropertyName("dep")]
    public string? Deposito { get; set; }

    [JsonPropertyName("archivo")]
    public string? Archivo { get; set; }

    [JsonPropertyName("ticks")]
    public long? Ticks { get; set; }
}

public sealed class AnalisisManualDto
{
    [JsonPropertyName("pallets")]
    public List<string> Pallets { get; set; } = new();

    [JsonPropertyName("cajas")]
    public List<string> Cajas { get; set; } = new();
}
