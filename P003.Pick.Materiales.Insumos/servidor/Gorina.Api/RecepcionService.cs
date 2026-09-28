using MySqlConnector;

namespace Gorina.Api;

public sealed class OperacionEntrada
{
    public string Id { get; set; } = "";
    public string Tipo { get; set; } = "PICK";
    public string Usuario { get; set; } = "";
    public string FechaCreacion { get; set; } = "";
    public string FechaCierre { get; set; } = "";
    public string Orden { get; set; } = "";
    public string Ceco { get; set; } = "";
    public string ClaseMovimiento { get; set; } = "";
    public string Centro { get; set; } = "";
    public string Almacen { get; set; } = "";
    public string? TextoCabecera { get; set; }
    public List<PosicionEntrada> Posiciones { get; set; } = new();
}

public sealed class PosicionEntrada
{
    public int Linea { get; set; }
    public string? QrLeido { get; set; }
    public string MaterialSap { get; set; } = "";
    public string? Descripcion { get; set; }
    public string? UnidadLectura { get; set; }
    public double CantidadLectura { get; set; }
    public string UnidadSap { get; set; } = "";
    public double CantidadSap { get; set; }
    public string? TextoPosicion { get; set; }
    public string Origen { get; set; } = "EQUIVALENCIA";
}

public sealed class RecepcionService(Database db, Config config)
{
    public Dictionary<string, object> ReservarOrden(string operacionId, string usuario)
    {
        if (string.IsNullOrWhiteSpace(operacionId))
            throw new ArgumentException("Falta el identificador interno de la operacion.");

        operacionId = operacionId.Trim();
        using var cnn = db.Abrir();
        using var transaccion = cnn.BeginTransaction();

        using (var existente = cnn.CreateCommand())
        {
            existente.Transaction = transaccion;
            existente.CommandText = "SELECT orden, usuario FROM reservas_operacion WHERE operacion_id = @id";
            existente.Parameters.AddWithValue("@id", operacionId);
            using var lector = existente.ExecuteReader();
            if (lector.Read())
            {
                if (!string.Equals(lector.GetString(1), usuario, StringComparison.OrdinalIgnoreCase))
                    throw new ArgumentException("La reserva pertenece a otro usuario.");
                var reservada = lector.GetInt64(0);
                transaccion.Commit();
                return new Dictionary<string, object> { ["id"] = operacionId, ["orden"] = reservada.ToString() };
            }
        }

        long orden;
        using (var siguiente = cnn.CreateCommand())
        {
            siguiente.Transaction = transaccion;
            siguiente.CommandText = "UPDATE secuencias SET ultimo_valor = ultimo_valor + 1 WHERE clave = 'operacion'";
            siguiente.ExecuteNonQuery();
            siguiente.CommandText = "SELECT ultimo_valor FROM secuencias WHERE clave = 'operacion'";
            orden = Convert.ToInt64(siguiente.ExecuteScalar());
        }

        using (var insertar = cnn.CreateCommand())
        {
            insertar.Transaction = transaccion;
            insertar.CommandText = """
                INSERT INTO reservas_operacion (operacion_id, orden, usuario, creada_utc)
                VALUES (@id, @orden, @usuario, @fecha)
                """;
            insertar.Parameters.AddWithValue("@id", operacionId);
            insertar.Parameters.AddWithValue("@orden", orden);
            insertar.Parameters.AddWithValue("@usuario", usuario);
            insertar.Parameters.AddWithValue("@fecha", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
            insertar.ExecuteNonQuery();
        }

        transaccion.Commit();
        return new Dictionary<string, object> { ["id"] = operacionId, ["orden"] = orden.ToString() };
    }

    public Dictionary<string, object?> Recibir(OperacionEntrada entrada)
    {
        if (string.IsNullOrWhiteSpace(entrada.Id))
            throw new ArgumentException("Falta el identificador interno de la operacion.");
        if (entrada.Posiciones.Count == 0)
            throw new ArgumentException("La operacion no tiene posiciones.");
        if (entrada.Tipo != "PICK" && entrada.Tipo != "INGRESO")
            entrada.Tipo = "PICK";

        foreach (var posicion in entrada.Posiciones.Where(p => p.Origen == "MANUAL"))
        {
            posicion.MaterialSap = posicion.MaterialSap.Trim();
            if (posicion.MaterialSap.Length != 7 ||
                posicion.MaterialSap.Any(c => c is < '0' or > '9'))
                throw new ArgumentException(
                    $"El Material SAP de la linea {posicion.Linea} debe tener exactamente 7 digitos numericos.");
        }

        var existente = db.Consultar(
            "SELECT orden, estado, archivo_nombre, estado_sap, archivo_sap_nombre, estado_sap_fecha FROM operaciones WHERE id = @id",
            p => p.AddWithValue("@id", entrada.Id)).FirstOrDefault();

        if (existente is not null && string.Equals(existente["estado"]?.ToString(), "PROCESADO", StringComparison.Ordinal))
        {
            return new Dictionary<string, object?>
            {
                ["id"] = entrada.Id,
                ["orden"] = existente["orden"]?.ToString(),
                ["duplicado"] = true,
                ["estado"] = "PROCESADO",
                ["archivo_nombre"] = existente["archivo_nombre"]?.ToString(),
                ["estado_sap"] = existente["estado_sap"]?.ToString() ?? "PENDIENTE",
                ["archivo_sap_nombre"] = existente["archivo_sap_nombre"]?.ToString(),
                ["estado_sap_fecha"] = existente["estado_sap_fecha"]?.ToString(),
                ["msg_error"] = null
            };
        }

        var reserva = db.Consultar(
            "SELECT orden, usuario FROM reservas_operacion WHERE operacion_id = @id",
            p => p.AddWithValue("@id", entrada.Id)).FirstOrDefault()
            ?? throw new ArgumentException("La operacion no tiene un numero reservado por el servidor.");
        if (!string.Equals(reserva["usuario"]?.ToString(), entrada.Usuario, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("La reserva de la operacion pertenece a otro usuario.");
        entrada.Orden = reserva["orden"]!.ToString()!;

        Guardar(entrada);

        return GenerarArchivo(entrada.Id);
    }

    private void Guardar(OperacionEntrada entrada)
    {
        using var cnn = db.Abrir();
        using var transaccion = cnn.BeginTransaction();
        try
        {
            using (var cmd = cnn.CreateCommand())
            {
                cmd.Transaction = transaccion;
                cmd.CommandText = "DELETE FROM posiciones WHERE operacion_id = @id";
                cmd.Parameters.AddWithValue("@id", entrada.Id);
                cmd.ExecuteNonQuery();
            }

            using (var cmd = cnn.CreateCommand())
            {
                cmd.Transaction = transaccion;
                cmd.CommandText = """
                    INSERT INTO operaciones (id, tipo, usuario, fecha_creacion, fecha_cierre, orden, ceco,
                                             clase_movimiento, centro, almacen, texto_cabecera,
                                             estado, archivo_nombre, archivo_fecha, msg_error, recibida_utc)
                    VALUES (@id, @tipo, @usuario, @fcreacion, @fcierre, @orden, @ceco,
                            @clase, @centro, @almacen, @tcabecera,
                            'PENDIENTE', NULL, NULL, NULL, @recibida)
                    ON DUPLICATE KEY UPDATE
                        tipo = VALUES(tipo),
                        usuario = VALUES(usuario),
                        fecha_creacion = VALUES(fecha_creacion),
                        fecha_cierre = VALUES(fecha_cierre),
                        orden = VALUES(orden),
                        ceco = VALUES(ceco),
                        clase_movimiento = VALUES(clase_movimiento),
                        centro = VALUES(centro),
                        almacen = VALUES(almacen),
                        texto_cabecera = VALUES(texto_cabecera),
                        estado = 'PENDIENTE',
                        archivo_nombre = NULL,
                        archivo_fecha = NULL,
                        msg_error = NULL,
                        recibida_utc = VALUES(recibida_utc)
                    """;
                string ordenStr = entrada.Orden?.Trim() ?? "";
                string rawCabecera = entrada.TextoCabecera?.Trim() ?? "";
                string cabeceraFormateada = rawCabecera;
                if (!string.IsNullOrWhiteSpace(ordenStr))
                {
                    if (!rawCabecera.StartsWith(ordenStr + "-", StringComparison.OrdinalIgnoreCase) &&
                        !rawCabecera.StartsWith(ordenStr + " -", StringComparison.OrdinalIgnoreCase))
                    {
                        cabeceraFormateada = string.IsNullOrWhiteSpace(rawCabecera)
                            ? ordenStr
                            : $"{ordenStr}-{rawCabecera}";
                    }
                }

                cmd.Parameters.AddWithValue("@id", entrada.Id);
                cmd.Parameters.AddWithValue("@tipo", entrada.Tipo);
                cmd.Parameters.AddWithValue("@usuario", entrada.Usuario);
                cmd.Parameters.AddWithValue("@fcreacion", entrada.FechaCreacion);
                cmd.Parameters.AddWithValue("@fcierre", entrada.FechaCierre);
                cmd.Parameters.AddWithValue("@orden", entrada.Orden);
                cmd.Parameters.AddWithValue("@ceco", entrada.Ceco);
                cmd.Parameters.AddWithValue("@clase", entrada.ClaseMovimiento);
                cmd.Parameters.AddWithValue("@centro", entrada.Centro);
                cmd.Parameters.AddWithValue("@almacen", entrada.Almacen);
                cmd.Parameters.AddWithValue("@tcabecera", string.IsNullOrWhiteSpace(cabeceraFormateada) ? (object)DBNull.Value : cabeceraFormateada);
                cmd.Parameters.AddWithValue("@recibida", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
                cmd.ExecuteNonQuery();
            }

            foreach (var p in entrada.Posiciones)
            {
                using var cmd = cnn.CreateCommand();
                cmd.Transaction = transaccion;
                cmd.CommandText = """
                    INSERT INTO posiciones (operacion_id, linea, qr_leido, material_sap, descripcion,
                                            unidad_lectura, cantidad_lectura, unidad_sap, cantidad_sap,
                                            texto_posicion, origen)
                    VALUES (@oid, @linea, @qr, @mat, @desc, @ulec, @clec, @usap, @csap, @tpos, @origen)
                    """;
                cmd.Parameters.AddWithValue("@oid", entrada.Id);
                cmd.Parameters.AddWithValue("@linea", p.Linea);
                cmd.Parameters.AddWithValue("@qr", (object?)p.QrLeido ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@mat", p.MaterialSap);
                cmd.Parameters.AddWithValue("@desc", (object?)p.Descripcion ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ulec", (object?)p.UnidadLectura ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@clec", p.CantidadLectura);
                cmd.Parameters.AddWithValue("@usap", p.UnidadSap);
                cmd.Parameters.AddWithValue("@csap", p.CantidadSap);
                cmd.Parameters.AddWithValue("@tpos", (object?)p.TextoPosicion ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@origen", p.Origen == "MANUAL" ? "MANUAL" : "EQUIVALENCIA");
                cmd.ExecuteNonQuery();
            }

            transaccion.Commit();
        }
        catch
        {
            transaccion.Rollback();
            throw;
        }
    }

    public Dictionary<string, object?> GenerarArchivo(string idOperacion)
    {
        var operacion = db.Consultar("SELECT * FROM operaciones WHERE id = @id",
            p => p.AddWithValue("@id", idOperacion)).FirstOrDefault()
            ?? throw new InvalidOperationException("Operacion inexistente: " + idOperacion);

        var posiciones = db.Consultar(
            "SELECT * FROM posiciones WHERE operacion_id = @id ORDER BY linea",
            p => p.AddWithValue("@id", idOperacion));

        try
        {
            var (nombre, _) = CsvGenerator.Generar(config, operacion, posiciones);
            MarcarEstado(idOperacion, "PROCESADO", nombre, null);
            Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] CSV generado: {nombre}");
            return Resultado(idOperacion, operacion["orden"]!.ToString()!, false, "PROCESADO", nombre, "PENDIENTE", null);
        }
        catch (Exception ex)
        {
            MarcarEstado(idOperacion, "ERROR", null, ex.Message);
            Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] ERROR generando {idOperacion}: {ex.Message}");
            return Resultado(idOperacion, operacion["orden"]!.ToString()!, false, "ERROR", null, null, ex.Message);
        }
    }

    private void MarcarEstado(string id, string estado, string? archivo, string? error)
    {
        db.Ejecutar(
            """
            UPDATE operaciones
            SET estado = @e, archivo_nombre = @a, archivo_fecha = @fa, msg_error = @m,
                estado_sap = CASE WHEN @e = 'PROCESADO' THEN 'PENDIENTE' ELSE estado_sap END,
                archivo_sap_nombre = CASE WHEN @e = 'PROCESADO' THEN NULL ELSE archivo_sap_nombre END,
                estado_sap_fecha = CASE WHEN @e = 'PROCESADO' THEN NULL ELSE estado_sap_fecha END
            WHERE id = @id
            """,
            p =>
            {
                p.AddWithValue("@e", estado);
                p.AddWithValue("@a", (object?)archivo ?? DBNull.Value);
                p.AddWithValue("@fa", estado == "PROCESADO"
                    ? DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")
                    : (object?)DBNull.Value);
                p.AddWithValue("@m", (object?)error ?? DBNull.Value);
                p.AddWithValue("@id", id);
            });
    }

    private static Dictionary<string, object?> Resultado(string id, string orden, bool duplicado, string estado,
        string? archivo, string? estadoSap, string? error) => new()
        {
            ["id"] = id,
            ["orden"] = orden,
            ["duplicado"] = duplicado,
            ["estado"] = estado,
            ["archivo_nombre"] = archivo,
            ["estado_sap"] = estadoSap,
            ["msg_error"] = error
        };
}
