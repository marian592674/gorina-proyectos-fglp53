using ClosedXML.Excel;

namespace Gorina.Api;

public static class Importador
{
    public static readonly IReadOnlySet<string> TiposPermitidos =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "equivalencias", "cecos", "almacenes", "clases", "centros"
        };

    public static int Importar(Database db, string tipo, string rutaArchivo) =>
        tipo.ToLowerInvariant() switch
        {
            "equivalencias" => ImportarEquivalencias(db, rutaArchivo),
            "cecos" => ImportarCecos(db, rutaArchivo),
            "almacenes" => ImportarAlmacenes(db, rutaArchivo),
            "clases" => ImportarClasesMovimiento(db, rutaArchivo),
            "centros" => ImportarCentrosSap(db, rutaArchivo),
            _ => throw new ArgumentException("Tipo de catalogo invalido: " + tipo)
        };

    public static ValidacionImportacion Validar(string tipo, string rutaArchivo)
    {
        if (!TiposPermitidos.Contains(tipo))
            throw new ArgumentException("Tipo de catalogo invalido: " + tipo);

        var filas = LeerHoja(rutaArchivo);
        var errores = new List<string>();
        var muestra = new List<Dictionary<string, string>>();
        int validas = 0;

        for (int i = 0; i < filas.Count; i++)
        {
            var fila = filas[i];
            string? error = tipo.ToLowerInvariant() switch
            {
                "equivalencias" when string.IsNullOrWhiteSpace(
                    Valor(fila, "codigo_limpio", "codigo_qr", "codigo")) => "falta codigo QR",
                "equivalencias" when string.IsNullOrWhiteSpace(
                    Valor(fila, "material_sap", "material")) => "falta material SAP",
                "cecos" when string.IsNullOrWhiteSpace(Valor(fila, "ceco")) => "falta CECO",
                "almacenes" when string.IsNullOrWhiteSpace(
                    Valor(fila, "codigo", "almacen", "codigo_almacen")) => "falta codigo de almacen",
                "almacenes" when string.IsNullOrWhiteSpace(
                    Valor(fila, "descripcion")) => "falta descripcion",
                "clases" when string.IsNullOrWhiteSpace(
                    Valor(fila, "clase_de_movimientos", "clase", "codigo")) => "falta clase",
                "centros" when string.IsNullOrWhiteSpace(
                    Valor(fila, "centro", "codigo")) => "falta centro",
                _ => null
            };

            if (error is null)
            {
                validas++;
                if (muestra.Count < 5) muestra.Add(fila);
            }
            else if (errores.Count < 20)
            {
                errores.Add($"Fila {i + 2}: {error}");
            }
        }

        return new ValidacionImportacion
        {
            Tipo = tipo.ToLowerInvariant(),
            FilasTotales = filas.Count,
            FilasValidas = validas,
            FilasOmitidas = filas.Count - validas,
            Errores = errores,
            Muestra = muestra
        };
    }

    public static int ImportarEquivalencias(Database db, string rutaArchivo)
    {
        var filas = LeerHoja(rutaArchivo);
        var validas = filas.Where(f => !string.IsNullOrWhiteSpace(Valor(f, "codigo_limpio", "codigo_qr", "codigo"))
                                    && !string.IsNullOrWhiteSpace(Valor(f, "material_sap", "material"))).ToList();
        if (validas.Count == 0) return 0;

        // PISAR catálogo anterior
        db.Ejecutar("DELETE FROM equivalencias;");

        var codigosUnicos = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var fila in validas)
        {
            string codigo = LimpiarCodigo(Valor(fila, "codigo_limpio", "codigo_qr", "codigo"));
            string material = LimpiarCodigo(Valor(fila, "material_sap", "material"));
            if (!long.TryParse(codigo, out _) && codigo.Length > 100)
                continue;

            db.Ejecutar("""
                INSERT INTO equivalencias (codigo_qr, material_sap, descripcion, unidad_sap, unidad_lectura,
                                           factor_conversion, activo, fecha_alta, fecha_modif, usuario_modif)
                VALUES (@qr, @mat, @desc, @usap, @ulec, @fac, @act, @f, @f, 'IMPORTACION')
                ON DUPLICATE KEY UPDATE
                    material_sap = VALUES(material_sap),
                    descripcion = VALUES(descripcion),
                    unidad_sap = VALUES(unidad_sap),
                    unidad_lectura = VALUES(unidad_lectura),
                    factor_conversion = VALUES(factor_conversion),
                    activo = VALUES(activo),
                    fecha_modif = VALUES(fecha_modif),
                    usuario_modif = VALUES(usuario_modif)
                """,
                p =>
                {
                    p.AddWithValue("@qr", codigo);
                    p.AddWithValue("@mat", material);
                    p.AddWithValue("@desc", Valor(fila, "descripcion_sap", "descripcion"));
                    p.AddWithValue("@usap", Valor(fila, "unidad_sap", "unidad"));
                    p.AddWithValue("@ulec", Valor(fila, "unidad_lectura"));
                    p.AddWithValue("@fac", Numero(Valor(fila, "factor_conversion"), 1));
                    p.AddWithValue("@act", EsActivo(Valor(fila, "activo")) ? 1 : 0);
                    p.AddWithValue("@f", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                });
            codigosUnicos.Add(codigo);
        }
        return codigosUnicos.Count;
    }

    public static int ImportarCecos(Database db, string rutaArchivo)
    {
        var filas = LeerHoja(rutaArchivo);
        var validas = filas.Where(f => !string.IsNullOrWhiteSpace(Valor(f, "ceco"))).ToList();
        if (validas.Count == 0) return 0;

        // PISAR catálogo anterior
        db.Ejecutar("DELETE FROM centros_costo;");

        var codigosUnicos = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var fila in validas)
        {
            string ceco = LimpiarCodigo(Valor(fila, "ceco"));
            db.Ejecutar("""
                INSERT INTO centros_costo (ceco, descripcion, activo)
                VALUES (@c, @d, @a)
                ON DUPLICATE KEY UPDATE
                    descripcion = VALUES(descripcion),
                    activo = VALUES(activo)
                """,
                p =>
                {
                    p.AddWithValue("@c", ceco);
                    p.AddWithValue("@d", Valor(fila, "descripcion_ceco", "descripcion"));
                    p.AddWithValue("@a", EsActivo(Valor(fila, "activo")) ? 1 : 0);
                });
            codigosUnicos.Add(ceco);
        }
        return codigosUnicos.Count;
    }

    public static int ImportarAlmacenes(Database db, string rutaArchivo)
    {
        var filas = LeerHoja(rutaArchivo);
        var validas = filas.Where(f => !string.IsNullOrWhiteSpace(Valor(f, "codigo", "almacen", "codigo_almacen"))).ToList();
        if (validas.Count == 0) return 0;

        // PISAR catálogo anterior: se eliminan registros previos para que solo quede lo del último archivo
        db.Ejecutar("DELETE FROM almacenes;");

        var codigosUnicos = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var fila in validas)
        {
            string codigo = LimpiarCodigo(Valor(fila, "codigo", "almacen", "codigo_almacen"));
            string centro = LimpiarCodigo(Valor(fila, "centro"));
            string descripcion = Valor(fila, "descripcion");

            db.Ejecutar("""
                INSERT INTO almacenes (codigo, centro, descripcion, activo)
                VALUES (@c, @ce, @d, 1)
                ON DUPLICATE KEY UPDATE
                    centro = VALUES(centro),
                    descripcion = VALUES(descripcion),
                    activo = 1
                """,
                p =>
                {
                    p.AddWithValue("@c", codigo);
                    p.AddWithValue("@ce", centro);
                    p.AddWithValue("@d", descripcion);
                });
            codigosUnicos.Add(codigo);
        }
        return codigosUnicos.Count;
    }

    public static int ImportarClasesMovimiento(Database db, string rutaArchivo)
    {
        var filas = LeerHoja(rutaArchivo);
        var validas = filas.Where(f => !string.IsNullOrWhiteSpace(Valor(f, "clase_de_movimientos", "clase", "codigo"))).ToList();
        if (validas.Count == 0) return 0;

        // PISAR catálogo anterior
        db.Ejecutar("DELETE FROM clases_movimiento;");

        var codigosUnicos = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var fila in validas)
        {
            string codigo = LimpiarCodigo(Valor(fila, "clase_de_movimientos", "clase", "codigo"));
            db.Ejecutar("""
                INSERT INTO clases_movimiento (codigo, descripcion, activo)
                VALUES (@c, @d, 1)
                ON DUPLICATE KEY UPDATE
                    descripcion = VALUES(descripcion),
                    activo = 1
                """,
                p =>
                {
                    p.AddWithValue("@c", codigo);
                    p.AddWithValue("@d", Valor(fila, "descripcion"));
                });
            codigosUnicos.Add(codigo);
        }
        return codigosUnicos.Count;
    }

    public static int ImportarCentrosSap(Database db, string rutaArchivo)
    {
        var filas = LeerHoja(rutaArchivo);
        var validas = filas.Where(f => !string.IsNullOrWhiteSpace(Valor(f, "centro", "codigo"))).ToList();
        if (validas.Count == 0) return 0;

        // PISAR catálogo anterior
        db.Ejecutar("DELETE FROM centros_sap;");

        var codigosUnicos = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var fila in validas)
        {
            string codigo = LimpiarCodigo(Valor(fila, "centro", "codigo"));
            db.Ejecutar("""
                INSERT INTO centros_sap (codigo, descripcion, activo)
                VALUES (@c, @d, 1)
                ON DUPLICATE KEY UPDATE
                    descripcion = VALUES(descripcion),
                    activo = 1
                """,
                p =>
                {
                    p.AddWithValue("@c", codigo);
                    p.AddWithValue("@d", Valor(fila, "descripcion"));
                });
            codigosUnicos.Add(codigo);
        }
        return codigosUnicos.Count;
    }

    public static void DiagnosticarArchivo(string rutaArchivo)
    {
        using var libro = new XLWorkbook(rutaArchivo);
        foreach (var hoja in libro.Worksheets)
        {
            Console.WriteLine($"HOJA: '{hoja.Name}'");
            var rango = hoja.RangeUsed();
            Console.WriteLine($"  RangeUsed: {(rango is null ? "NULL" : $"{rango.RangeAddress.FirstAddress} -> {rango.RangeAddress.LastAddress}")}");
            var lr = hoja.LastRowUsed();
            var lc = hoja.LastColumnUsed();
            Console.WriteLine($"  LastRowUsed: {lr?.RowNumber()} LastColumnUsed: {lc?.ColumnNumber()}");
            for (int c = 1; c <= (lc?.ColumnNumber() ?? 0); c++)
                Console.WriteLine($"  Col {c}: '{hoja.Cell(1, c).GetString()}' tipo={hoja.Cell(1, c).DataType} normalizada='{Normalizar(hoja.Cell(1, c).GetString())}'");

            for (int f = 2; f <= (lr?.RowNumber() ?? 0); f++)
            {
                var valores = new List<string>();
                for (int c = 1; c <= (lc?.ColumnNumber() ?? 0); c++)
                    valores.Add($"col{c}='{hoja.Cell(f, c).GetString()}'(t={hoja.Cell(f, c).DataType})");
                Console.WriteLine($"  Fila {f}: {string.Join(", ", valores)}");
            }
        }
    }

    private static List<Dictionary<string, string>> LeerHoja(string rutaArchivo)
    {
        if (!File.Exists(rutaArchivo))
            throw new FileNotFoundException("No existe el archivo: " + rutaArchivo);

        using var libro = new XLWorkbook(rutaArchivo);
        var hoja = libro.Worksheets.First();
        var rangoUsado = hoja.RangeUsed();
        if (rangoUsado is null) return new List<Dictionary<string, string>>();

        var encabezados = new Dictionary<int, string>();
        var ultimaCol = rangoUsado.LastColumn().ColumnNumber();
        for (int c = 1; c <= ultimaCol; c++)
        {
            string titulo = Normalizar(hoja.Cell(1, c).GetString());
            if (!string.IsNullOrEmpty(titulo))
                encabezados[c] = titulo;
        }

        var resultado = new List<Dictionary<string, string>>();
        var ultimaFila = rangoUsado.LastRow().RowNumber();
        for (int f = 2; f <= ultimaFila; f++)
        {
            var fila = new Dictionary<string, string>();
            bool tieneDatos = false;
            foreach (var (columna, titulo) in encabezados)
            {
                var celda = hoja.Cell(f, columna);
                string valor = "";
                if (celda.DataType == XLDataType.Number)
                {
                    double d = celda.GetDouble();
                    valor = (d % 1 == 0 && Math.Abs(d) < 9e15)
                        ? ((long)d).ToString(System.Globalization.CultureInfo.InvariantCulture)
                        : d.ToString(System.Globalization.CultureInfo.InvariantCulture);
                }
                else
                {
                    valor = celda.GetString().Trim();
                }
                fila[titulo] = valor;
                if (!string.IsNullOrEmpty(valor)) tieneDatos = true;
            }
            if (tieneDatos) resultado.Add(fila);
        }

        // Reconciliar desplazamientos verticales comunes en edición manual de Excel (ej. código pegado una fila abajo)
        for (int i = 0; i < resultado.Count - 1; i++)
        {
            var f1 = resultado[i];
            var f2 = resultado[i + 1];
            bool f1SinCod = string.IsNullOrWhiteSpace(Valor(f1, "codigo", "almacen", "codigo_almacen"));
            bool f1ConDesc = !string.IsNullOrWhiteSpace(Valor(f1, "descripcion", "centro"));
            bool f2ConCod = !string.IsNullOrWhiteSpace(Valor(f2, "codigo", "almacen", "codigo_almacen"));
            bool f2SinDesc = string.IsNullOrWhiteSpace(Valor(f2, "descripcion"));

            if (f1SinCod && f1ConDesc && f2ConCod && f2SinDesc)
            {
                foreach (var kvp in f1)
                {
                    if (!string.IsNullOrWhiteSpace(kvp.Value) && string.IsNullOrWhiteSpace(Valor(f2, kvp.Key)))
                        f2[kvp.Key] = kvp.Value;
                }
            }
        }

        return resultado;
    }

    private static string LimpiarCodigo(string texto)
    {
        var t = texto.Trim();
        if (t.EndsWith(".0") && double.TryParse(t, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out _))
            t = t[..^2];
        return t;
    }

    private static readonly Dictionary<char, char> MapaAcentos = new()
    {
        ['á'] = 'a',
        ['é'] = 'e',
        ['í'] = 'i',
        ['ó'] = 'o',
        ['ú'] = 'u',
        ['ü'] = 'u',
        ['ñ'] = 'n',
        ['à'] = 'a',
        ['è'] = 'e',
        ['ì'] = 'i',
        ['ò'] = 'o',
        ['ù'] = 'u',
        ['Á'] = 'a',
        ['É'] = 'e',
        ['Í'] = 'i',
        ['Ó'] = 'o',
        ['Ú'] = 'u',
        ['Ü'] = 'u',
        ['Ñ'] = 'n'
    };

    private static string Normalizar(string texto)
    {
        var sb = new System.Text.StringBuilder(texto.Trim().Length);
        foreach (var ch in texto.Trim().ToLowerInvariant())
            sb.Append(MapaAcentos.TryGetValue(ch, out var reemplazo) ? reemplazo : ch);
        return sb.ToString().Replace(" ", "_").Replace(".", "");
    }

    private static string Valor(Dictionary<string, string> fila, params string[] clavesAlternativas)
    {
        foreach (var clave in clavesAlternativas)
            if (fila.TryGetValue(clave, out var valor) && !string.IsNullOrWhiteSpace(valor))
                return valor.Trim();
        return string.Empty;
    }

    private static double Numero(string texto, double porDefecto) =>
        double.TryParse(texto.Replace(",", "."), System.Globalization.NumberStyles.Float,
            System.Globalization.CultureInfo.InvariantCulture, out var numero) ? numero : porDefecto;

    private static bool EsActivo(string texto)
    {
        var t = texto.Trim().ToUpperInvariant();
        return t is not ("NO" or "N" or "INACTIVO" or "0" or "FALSE");
    }
}

public sealed class ValidacionImportacion
{
    public string Tipo { get; set; } = "";
    public int FilasTotales { get; set; }
    public int FilasValidas { get; set; }
    public int FilasOmitidas { get; set; }
    public List<string> Errores { get; set; } = [];
    public List<Dictionary<string, string>> Muestra { get; set; } = [];
}
