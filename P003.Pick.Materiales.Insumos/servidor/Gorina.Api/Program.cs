using Gorina.Api;
using MySqlConnector;
using System.Text.Json;

var (config, importes) = Config.Cargar(args);

var database = new Database(config);
var recepcion = new RecepcionService(database, config);

foreach (var importe in importes)
{
    var partes = importe.Split('|', 2);
    string tipo = partes[0];
    string archivo = partes[1];
    try
    {
        int n = tipo switch
        {
            "equivalencias" => Importador.ImportarEquivalencias(database, archivo),
            "cecos" => Importador.ImportarCecos(database, archivo),
            "almacenes" => Importador.ImportarAlmacenes(database, archivo),
            "clases" => Importador.ImportarClasesMovimiento(database, archivo),
            "centros" => Importador.ImportarCentrosSap(database, archivo),
            _ => 0
        };
        Console.WriteLine($"Importados {n} registros de {tipo} desde {archivo}");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"ERROR importando {tipo}: {ex.Message}");
        Environment.Exit(1);
    }
    if (importes.Count > 0 && importes.Last() == importe)
        return;
}

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(o =>
{
    o.SingleLine = true;
    o.TimestampFormat = "yyyy-MM-dd HH:mm:ss ";
});
builder.Services.AddSingleton(config);
builder.Services.AddSingleton(database);
builder.Services.AddHostedService<SapMonitorService>();
var app = builder.Build();

app.Use(async (ctx, next) =>
{
    await next();
    
    // Solo registrar POST, PUT, DELETE para no llenar de GETs irrelevantes
    if (ctx.Request.Method != "GET")
    {
        try
        {
            var auth = Autenticar(ctx);
            var usuario = auth?.Usuario?["usuario"]?.ToString() ?? "anonimo";
            var logLine = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss},{usuario},{ctx.Request.Method},{ctx.Request.Path},{ctx.Response.StatusCode}\n";
            
            var logFile = Path.Combine(AppContext.BaseDirectory, "auditoria.csv");
            if (!File.Exists(logFile))
                File.AppendAllText(logFile, "Fecha,Usuario,Metodo,Ruta,EstadoHttp\n");
                
            File.AppendAllText(logFile, logLine);
        }
        catch
        {
            // Evitar que fallos en auditoría bloqueen la respuesta
        }
    }
});

(string? Token, Dictionary<string, object?> Usuario)? Autenticar(HttpContext ctx)
{
    var header = ctx.Request.Headers.Authorization.ToString();
    if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) return null;
    var token = header["Bearer ".Length..].Trim();
    if (token.Length == 0) return null;
    var filas = database.Consultar("""
        SELECT u.usuario, u.nombre, u.perfil, u.activo
        FROM sesiones s JOIN usuarios u ON u.usuario = s.usuario
        WHERE s.token = @t
        """, p => p.AddWithValue("@t", token));
    if (filas.Count == 0) return null;
    var u = filas[0];
    if (Convert.ToInt64(u["activo"]) != 1) return null;
    return (token, u);
}

IResult NoAutorizado() => Results.Json(new { error = "Sesión expirada o no autorizada. Inicie sesión nuevamente" }, statusCode: 401);
IResult Prohibido() => Results.Json(new { error = "Requiere perfil ADMIN" }, statusCode: 403);

app.MapGet("/api/ping", () => Results.Ok(new { estado = "OK", servidor = "Gorina.Api", fecha = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") }));

app.MapGet("/api/app/version", () =>
{
    var rutaVersion = Path.Combine(AppContext.BaseDirectory, "version.json");
    if (!File.Exists(rutaVersion))
    {
        var def = new
        {
            versionCode = 7,
            versionName = "1.4.0",
            minimoRequerido = 7,
            apkUrl = "/api/app/latest.apk",
            fechaPublicacion = DateTime.Now.ToString("yyyy-MM-dd"),
            novedades = "Versión en producción"
        };
        File.WriteAllText(rutaVersion, JsonSerializer.Serialize(def, new JsonSerializerOptions { WriteIndented = true }));
        return Results.Ok(def);
    }
    var json = File.ReadAllText(rutaVersion);
    var obj = JsonSerializer.Deserialize<Dictionary<string, object?>>(json);
    return Results.Ok(obj);
});

app.MapGet("/api/app/latest.apk", () =>
{
    var rutaApk = Path.Combine(AppContext.BaseDirectory, "apk", "GorinaPick.apk");
    if (!File.Exists(rutaApk))
    {
        var rutaAlt = @"C:\EGalli\GorinaPick\Instaladores\1_Android_APK\GorinaPick_v1.0_Android.apk";
        if (File.Exists(rutaAlt)) rutaApk = rutaAlt;
    }

    if (!File.Exists(rutaApk))
        return Results.NotFound(new { error = "Instalador APK no disponible en el servidor" });

    return Results.File(rutaApk, "application/vnd.android.package-archive", "GorinaPick.apk", enableRangeProcessing: true);
});

app.MapGet("/api/app/apk/{version}", (string version) =>
{
    var nombre = $"GorinaPick_v{version}.apk";
    var rutaApk = Path.Combine(AppContext.BaseDirectory, "apk", nombre);
    if (!File.Exists(rutaApk))
        return Results.NotFound(new { error = $"Version {version} no encontrada" });

    return Results.File(rutaApk, "application/vnd.android.package-archive", nombre, enableRangeProcessing: true);
});

app.MapPost("/api/login", (LoginEntrada datos) =>
{
    if (datos is null || string.IsNullOrWhiteSpace(datos.Usuario) || string.IsNullOrWhiteSpace(datos.Pin))
        return Results.Json(new { error = "Usuario y PIN requeridos" }, statusCode: 400);

    var filas = database.Consultar(
        "SELECT usuario, nombre, pin_hash, salt, perfil, activo FROM usuarios WHERE usuario = @u",
        p => p.AddWithValue("@u", datos.Usuario.Trim()));
    if (filas.Count == 0 || Convert.ToInt64(filas[0]["activo"]) != 1)
        return Results.Json(new { error = "Usuario o PIN incorrecto" }, statusCode: 401);

    var u = filas[0];
    if (!PasswordHasher.Verificar(datos.Pin, u["salt"]?.ToString() ?? "", u["pin_hash"]?.ToString() ?? ""))
        return Results.Json(new { error = "Usuario o PIN incorrecto" }, statusCode: 401);

    var token = Guid.NewGuid().ToString("N");
    database.Ejecutar("INSERT INTO sesiones (token, usuario, creada) VALUES (@t, @u, @f)",
        p =>
        {
            p.AddWithValue("@t", token);
            p.AddWithValue("@u", u["usuario"]?.ToString());
            p.AddWithValue("@f", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        });

    return Results.Ok(new
    {
        token,
        usuario = u["usuario"]?.ToString(),
        nombre = u["nombre"]?.ToString(),
        perfil = u["perfil"]?.ToString()
    });
});

app.MapGet("/api/maestros", (HttpContext ctx) =>
{
    // Permitir consulta de maestros a la app para sincronizar catálogos incluso si la sesión local no tiene token vigente
    var equivalencias = database.Consultar(
        "SELECT id, codigo_qr, material_sap, descripcion, unidad_sap, unidad_lectura, factor_conversion FROM equivalencias WHERE activo = 1");
    var cecos = database.Consultar("SELECT ceco, descripcion FROM centros_costo WHERE activo = 1 ORDER BY ceco");
    var almacenes = database.Consultar("SELECT codigo, centro, descripcion FROM almacenes WHERE activo = 1 ORDER BY codigo");
    var clasesMovimiento = database.Consultar("SELECT codigo, descripcion FROM clases_movimiento ORDER BY codigo");
    var centros = database.Consultar("SELECT codigo, descripcion FROM centros_sap ORDER BY codigo");
    var usuarios = database.Consultar(
        "SELECT usuario, nombre, email, perfil, pin_hash, salt FROM usuarios WHERE activo = 1");

    return Results.Ok(new
    {
        fecha_servidor = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
        parametros = new
        {
            claseMovimiento = config.ClaseMovimiento,
            centro = config.Centro,
            loteDefault = config.LoteDefault,
            diasHistorialApp = Math.Max(1, config.DiasHistorialApp)
        },
        equivalencias,
        cecos,
        almacenes,
        clasesMovimiento,
        centros,
        usuarios
    });
});

app.MapGet("/api/equivalencias", (HttpContext ctx, string? busqueda) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();

    string filtro = $"%{(busqueda ?? "").Trim()}%";
    var filas = database.Consultar("""
        SELECT id, codigo_qr, material_sap, descripcion, unidad_sap, unidad_lectura,
               factor_conversion, activo, fecha_alta, fecha_modif, usuario_modif
        FROM equivalencias
        WHERE codigo_qr LIKE @f OR material_sap LIKE @f OR descripcion LIKE @f
        ORDER BY codigo_qr
        LIMIT 500
        """, p => p.AddWithValue("@f", filtro));
    return Results.Ok(filas);
});

app.MapPost("/api/equivalencias", (HttpContext ctx, EquivalenciaEntrada e) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();
    if (string.IsNullOrWhiteSpace(e.CodigoQr) || string.IsNullOrWhiteSpace(e.MaterialSap))
        return Results.Json(new { error = "Codigo QR y Material SAP son obligatorios" }, statusCode: 400);

    var existe = database.Escalar("SELECT COUNT(*) FROM equivalencias WHERE codigo_qr = @q",
        p => p.AddWithValue("@q", e.CodigoQr.Trim()));
    if (Convert.ToInt64(existe) > 0)
        return Results.Json(new { error = "Ya existe una equivalencia para ese codigo QR" }, statusCode: 409);

    var ahora = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
    database.Ejecutar("""
        INSERT INTO equivalencias (codigo_qr, material_sap, descripcion, unidad_sap, unidad_lectura,
                                   factor_conversion, activo, fecha_alta, fecha_modif, usuario_modif)
        VALUES (@qr, @mat, @desc, @usap, @ulec, @fac, @act, @f, @f, @usr)
        """,
        p =>
        {
            CompletarParametrosEquivalencia(p, e, ahora, auth.Value.Usuario["usuario"]!.ToString()!);
            p.AddWithValue("@f", ahora);
        });
    return Results.Ok(new { ok = true });
});

app.MapPut("/api/equivalencias/{id:long}", (HttpContext ctx, long id, EquivalenciaEntrada e) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();

    var actual = database.Consultar("SELECT * FROM equivalencias WHERE id = @id",
        p => p.AddWithValue("@id", id)).FirstOrDefault();
    if (actual is null) return Results.NotFound(new { error = "No encontrada" });
    if (!string.Equals(actual["codigo_qr"]?.ToString(), e.CodigoQr.Trim(), StringComparison.Ordinal))
        return Results.Json(new { error = "El codigo QR no se puede modificar; elimine y cree nuevamente" }, statusCode: 400);

    var ahora = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
    database.Ejecutar("""
        UPDATE equivalencias SET material_sap = @mat, descripcion = @desc, unidad_sap = @usap,
                                 unidad_lectura = @ulec, factor_conversion = @fac, activo = @act,
                                 fecha_modif = @ahora, usuario_modif = @usr
        WHERE id = @id
        """,
        p =>
        {
            CompletarParametrosEquivalencia(p, e, ahora, auth.Value.Usuario["usuario"]!.ToString()!);
            p.AddWithValue("@id", id);
        });
    return Results.Ok(new { ok = true });
});

static bool EsAdmin(Dictionary<string, object?> usuario) =>
    string.Equals(usuario["perfil"]?.ToString(), "ADMIN", StringComparison.Ordinal);

static void CompletarParametrosEquivalencia(MySqlParameterCollection p, EquivalenciaEntrada e,
    string ahora, string usuario)
{
    p.AddWithValue("@qr", e.CodigoQr.Trim());
    p.AddWithValue("@mat", e.MaterialSap.Trim());
    p.AddWithValue("@desc", e.Descripcion ?? "");
    p.AddWithValue("@usap", e.UnidadSap ?? "");
    p.AddWithValue("@ulec", e.UnidadLectura ?? "");
    p.AddWithValue("@fac", e.FactorConversion <= 0 ? 1 : e.FactorConversion);
    p.AddWithValue("@act", e.Activo ? 1 : 0);
    p.AddWithValue("@ahora", ahora);
    p.AddWithValue("@usr", usuario);
}

app.MapGet("/api/cecos", (HttpContext ctx) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();
    return Results.Ok(database.Consultar("SELECT ceco, descripcion, activo FROM centros_costo ORDER BY ceco"));
});

app.MapPost("/api/cecos", (HttpContext ctx, CecoEntrada c) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();
    if (string.IsNullOrWhiteSpace(c.Ceco))
        return Results.Json(new { error = "Codigo CECO obligatorio" }, statusCode: 400);

    var existe = database.Escalar("SELECT COUNT(*) FROM centros_costo WHERE ceco = @c",
        p => p.AddWithValue("@c", c.Ceco.Trim()));
    if (Convert.ToInt64(existe) > 0)
        return Results.Json(new { error = "Ya existe ese Centro de Costo" }, statusCode: 409);

    database.Ejecutar("INSERT INTO centros_costo (ceco, descripcion, activo) VALUES (@c, @d, @a)",
        p =>
        {
            p.AddWithValue("@c", c.Ceco.Trim());
            p.AddWithValue("@d", c.Descripcion ?? "");
            p.AddWithValue("@a", c.Activo ? 1 : 0);
        });
    return Results.Ok(new { ok = true });
});

app.MapPut("/api/cecos/{ceco}", (HttpContext ctx, string ceco, CecoEntrada c) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();

    var afectadas = database.Ejecutar("UPDATE centros_costo SET descripcion = @d, activo = @a WHERE ceco = @c",
        p =>
        {
            p.AddWithValue("@d", c.Descripcion ?? "");
            p.AddWithValue("@a", c.Activo ? 1 : 0);
            p.AddWithValue("@c", ceco);
        });
    return afectadas == 0 ? Results.NotFound(new { error = "No encontrado" }) : Results.Ok(new { ok = true });
});

app.MapPost("/api/catalogos/importar", async (HttpContext ctx) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();
    if (!ctx.Request.HasFormContentType)
        return Results.Json(new { error = "Se esperaba un archivo Excel" }, statusCode: 400);

    var form = await ctx.Request.ReadFormAsync();
    var tipo = form["tipo"].ToString().Trim().ToLowerInvariant();
    var confirmar = bool.TryParse(form["confirmar"], out var valorConfirmar) && valorConfirmar;
    var archivo = form.Files.GetFile("archivo");
    if (!Importador.TiposPermitidos.Contains(tipo))
        return Results.Json(new { error = "Tipo de catalogo invalido" }, statusCode: 400);
    if (archivo is null || archivo.Length == 0)
        return Results.Json(new { error = "Seleccione un archivo Excel" }, statusCode: 400);
    if (archivo.Length > 20 * 1024 * 1024)
        return Results.Json(new { error = "El archivo supera el limite de 20 MB" }, statusCode: 400);
    if (!string.Equals(Path.GetExtension(archivo.FileName), ".xlsx", StringComparison.OrdinalIgnoreCase))
        return Results.Json(new { error = "Solo se admiten archivos .xlsx" }, statusCode: 400);

    var temporal = Path.Combine(Path.GetTempPath(), $"gorina_{Guid.NewGuid():N}.xlsx");
    try
    {
        await using (var destino = File.Create(temporal))
            await archivo.CopyToAsync(destino);

        var validacion = Importador.Validar(tipo, temporal);
        if (!confirmar)
            return Results.Ok(new { confirmado = false, validacion });
        if (validacion.FilasValidas == 0)
            return Results.Json(new { error = "El archivo no contiene filas validas", validacion }, statusCode: 400);

        string nombreGuardado = tipo switch
        {
            "equivalencias" => "Equivalencias.xlsx",
            "cecos" => "Centros de Costo.xlsx",
            "almacenes" => "Almacenes.xlsx",
            "clases" => "Clase de Movimientos.xlsx",
            "centros" => "Centros.xlsx",
            _ => $"{tipo}.xlsx"
        };

        var carpetaCatalogos = config.RutaCarpetaCatalogos;
        Directory.CreateDirectory(carpetaCatalogos);
        var rutaDestino = Path.Combine(carpetaCatalogos, nombreGuardado);

        // Pisar el archivo en la carpeta de catálogos configurada
        File.Copy(temporal, rutaDestino, overwrite: true);

        // Asegurar que siempre pise también en C:\EGalli\GorinaPick\Ejemplos
        var carpetaEjemplos = @"C:\EGalli\GorinaPick\Ejemplos";
        if (Directory.Exists(carpetaEjemplos) && !string.Equals(Path.GetFullPath(carpetaCatalogos).TrimEnd('\\'), Path.GetFullPath(carpetaEjemplos).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
        {
            try { File.Copy(temporal, Path.Combine(carpetaEjemplos, nombreGuardado), overwrite: true); } catch { }
        }

        var registros = Importador.Importar(database, tipo, temporal);
        var usuario = auth.Value.Usuario["usuario"]?.ToString() ?? "";

        // Limpiar registros viejos del histórico de este tipo para que solo quede la versión vigente
        database.Ejecutar("DELETE FROM importaciones_catalogos WHERE tipo = @tipo", p => p.AddWithValue("@tipo", tipo));
        database.Ejecutar("""
            INSERT INTO importaciones_catalogos
                (tipo, archivo_nombre, registros, usuario, fecha, estado, mensaje)
            VALUES (@tipo, @archivo, @registros, @usuario, @fecha, 'OK', NULL)
            """, p =>
        {
            p.AddWithValue("@tipo", tipo);
            p.AddWithValue("@archivo", nombreGuardado);
            p.AddWithValue("@registros", registros);
            p.AddWithValue("@usuario", usuario);
            p.AddWithValue("@fecha", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        });
        return Results.Ok(new { confirmado = true, registros, archivo = nombreGuardado, validacion });
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = "No se pudo procesar el Excel: " + ex.Message }, statusCode: 400);
    }
    finally
    {
        try { File.Delete(temporal); } catch { }
    }
});

app.MapGet("/api/catalogos/importaciones", (HttpContext ctx) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();
    return Results.Ok(database.Consultar("""
        SELECT id, tipo, archivo_nombre, registros, usuario, fecha, estado, mensaje
        FROM importaciones_catalogos ORDER BY fecha DESC, id DESC LIMIT 100
        """));
});

app.MapGet("/api/usuarios", (HttpContext ctx) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();
    return Results.Ok(database.Consultar(
        "SELECT usuario, nombre, email, perfil, activo, fecha_alta FROM usuarios ORDER BY usuario"));
});

app.MapPost("/api/usuarios", (HttpContext ctx, UsuarioEntrada u) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();
    if (string.IsNullOrWhiteSpace(u.Usuario) || string.IsNullOrWhiteSpace(u.Pin) ||
        (u.Perfil != "ADMIN" && u.Perfil != "PICK"))
        return Results.Json(new { error = "Datos incompletos o perfil invalido" }, statusCode: 400);

    var existe = database.Escalar("SELECT COUNT(*) FROM usuarios WHERE usuario = @u",
        p => p.AddWithValue("@u", u.Usuario.Trim()));
    if (Convert.ToInt64(existe) > 0)
        return Results.Json(new { error = "Ya existe ese usuario" }, statusCode: 409);

    var salt = PasswordHasher.NuevoSalt();
    database.Ejecutar(
        "INSERT INTO usuarios (usuario, nombre, email, pin_hash, salt, perfil, activo, fecha_alta) VALUES (@u, @n, @e, @h, @s, @p, 1, @f)",
        p =>
        {
            p.AddWithValue("@u", u.Usuario.Trim());
            p.AddWithValue("@n", string.IsNullOrWhiteSpace(u.Nombre) ? u.Usuario.Trim() : u.Nombre.Trim());
            p.AddWithValue("@e", string.IsNullOrWhiteSpace(u.Email) ? "" : u.Email.Trim());
            p.AddWithValue("@h", PasswordHasher.Hash(u.Pin, salt));
            p.AddWithValue("@s", salt);
            p.AddWithValue("@p", u.Perfil);
            p.AddWithValue("@f", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        });
    return Results.Ok(new { ok = true });
});

app.MapPut("/api/usuarios/{usuario}", (HttpContext ctx, string usuario, UsuarioEntrada u) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();

    if (string.Equals(usuario, auth.Value.Usuario["usuario"]?.ToString(), StringComparison.Ordinal)
        && u.Activo == false)
        return Results.Json(new { error = "No puede desactivar su propio usuario" }, statusCode: 400);

    var afectadas = database.Ejecutar(
        "UPDATE usuarios SET nombre = COALESCE(@n, nombre), email = COALESCE(@e, email), perfil = COALESCE(@p, perfil), activo = COALESCE(@a, activo) WHERE usuario = @u",
        p =>
        {
            p.AddWithValue("@n", string.IsNullOrWhiteSpace(u.Nombre) ? (object?)DBNull.Value : u.Nombre.Trim());
            p.AddWithValue("@e", string.IsNullOrWhiteSpace(u.Email) ? (object?)DBNull.Value : u.Email.Trim());
            p.AddWithValue("@p", (u.Perfil == "ADMIN" || u.Perfil == "PICK") ? u.Perfil : (object?)DBNull.Value);
            p.AddWithValue("@a", u.Activo.HasValue ? (u.Activo.Value ? 1 : 0) : (object?)DBNull.Value);
            p.AddWithValue("@u", usuario);
        });

    if (afectadas == 0) return Results.NotFound(new { error = "No encontrado" });

    if (!string.IsNullOrWhiteSpace(u.Pin))
    {
        var salt = PasswordHasher.NuevoSalt();
        database.Ejecutar("UPDATE usuarios SET pin_hash = @h, salt = @s WHERE usuario = @u",
            p =>
            {
                p.AddWithValue("@h", PasswordHasher.Hash(u.Pin, salt));
                p.AddWithValue("@s", salt);
                p.AddWithValue("@u", usuario);
            });
    }
    return Results.Ok(new { ok = true });
});

app.MapPost("/api/operaciones/reservar", (HttpContext ctx, ReservaOperacionEntrada? entrada) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (entrada is null) return Results.Json(new { error = "Cuerpo vacio" }, statusCode: 400);
    try
    {
        return Results.Ok(recepcion.ReservarOrden(
            entrada.Id, auth.Value.Usuario["usuario"]!.ToString()!));
    }
    catch (ArgumentException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: 400);
    }
});

app.MapPost("/api/operaciones", (HttpContext ctx, OperacionEntrada? entrada) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (entrada is null) return Results.Json(new { error = "Cuerpo vacio" }, statusCode: 400);
    entrada.Usuario = auth.Value.Usuario["usuario"]!.ToString()!;
    try
    {
        return Results.Ok(recepcion.Recibir(entrada));
    }
    catch (ArgumentException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: 400);
    }
});

app.MapGet("/api/operaciones", (HttpContext ctx, string? estado, string? estadoSap,
    string? usuario, string? desde, string? almacen) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();

    var sql = """
        SELECT o.id, o.tipo, o.usuario, o.fecha_creacion, o.fecha_cierre, o.orden, o.ceco,
               o.clase_movimiento, o.centro, o.almacen, o.texto_cabecera,
               o.estado, o.archivo_nombre, o.msg_error,
               o.estado_sap, o.archivo_sap_nombre, o.estado_sap_fecha,
               o.doc_sap, o.estado_sap_detalle,
               COUNT(p.id) AS posiciones
        FROM operaciones o LEFT JOIN posiciones p ON p.operacion_id = o.id
        WHERE (@estado IS NULL OR o.estado = @estado)
          AND (@estadoSap IS NULL OR o.estado_sap = @estadoSap
               OR (@estadoSap = 'PENDIENTE' AND o.estado_sap IS NULL))
          AND (@usuario IS NULL OR o.usuario = @usuario)
          AND (@desde IS NULL OR o.fecha_cierre >= @desde)
          AND (@almacen IS NULL OR o.almacen = @almacen)
        GROUP BY o.id
        ORDER BY o.fecha_cierre DESC
        LIMIT 300
        """;
    var filas = database.Consultar(sql, p =>
    {
        p.AddWithValue("@estado", string.IsNullOrWhiteSpace(estado) ? (object?)DBNull.Value : estado);
        p.AddWithValue("@estadoSap", string.IsNullOrWhiteSpace(estadoSap) ? (object?)DBNull.Value : estadoSap);
        p.AddWithValue("@usuario", string.IsNullOrWhiteSpace(usuario) ? (object?)DBNull.Value : usuario);
        p.AddWithValue("@desde", string.IsNullOrWhiteSpace(desde) ? (object?)DBNull.Value : desde);
        p.AddWithValue("@almacen", string.IsNullOrWhiteSpace(almacen) ? (object?)DBNull.Value : almacen);
    });
    return Results.Ok(filas);
});

app.MapGet("/api/incidencias-sap", (HttpContext ctx, string? desde) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();
    return Results.Ok(database.Consultar("""
        SELECT id, estado, archivo_nombre, orden_detectada, fecha_sap, detectado_utc, detalle
        FROM incidencias_sap
        WHERE (@desde IS NULL OR fecha_sap >= @desde)
        ORDER BY fecha_sap DESC, id DESC
        LIMIT 300
        """, p => p.AddWithValue("@desde",
            string.IsNullOrWhiteSpace(desde) ? (object?)DBNull.Value : desde)));
});

app.MapGet("/api/operaciones/usuario/{usr}", (HttpContext ctx, string usr) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();

    var filas = database.Consultar("""
        SELECT o.id, o.tipo, o.usuario, o.fecha_creacion, o.fecha_cierre, o.orden, o.ceco,
               o.clase_movimiento, o.centro, o.almacen, o.texto_cabecera,
               o.estado, o.archivo_nombre, o.msg_error, o.estado_sap,
               o.archivo_sap_nombre, o.estado_sap_fecha,
               o.doc_sap, o.estado_sap_detalle,
               (SELECT COUNT(*) FROM posiciones WHERE operacion_id = o.id) AS posiciones
        FROM operaciones o
        WHERE o.usuario = @u
          AND (o.fecha_cierre >= @desde OR o.estado != 'PROCESADO'
               OR COALESCE(o.estado_sap, 'PENDIENTE') != 'OK')
        ORDER BY o.fecha_cierre DESC
        LIMIT 200
        """, p =>
        {
            p.AddWithValue("@u", usr);
            p.AddWithValue("@desde", DateTime.Now.AddDays(-Math.Max(1, config.DiasHistorialApp))
                .ToString("yyyy-MM-dd HH:mm:ss"));
        });
    return Results.Ok(filas);
});

app.MapGet("/api/operaciones/{id}", (HttpContext ctx, string id) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();

    var operacion = database.Consultar("SELECT * FROM operaciones WHERE id = @id",
        p => p.AddWithValue("@id", id)).FirstOrDefault();
    if (operacion is null) return Results.NotFound(new { error = "Operacion inexistente" });

    var posiciones = database.Consultar(
        "SELECT linea, qr_leido, material_sap, descripcion, unidad_lectura, cantidad_lectura, unidad_sap, cantidad_sap, texto_posicion, origen FROM posiciones WHERE operacion_id = @id ORDER BY linea",
        p => p.AddWithValue("@id", id));

    var eventosSap = database.Consultar("""
        SELECT estado, archivo_nombre, fecha_sap, detectado_utc
        FROM eventos_sap WHERE operacion_id = @id
        ORDER BY fecha_sap DESC, id DESC
        """, p => p.AddWithValue("@id", id));

    return Results.Ok(new { operacion, posiciones, eventosSap });
});

app.MapPost("/api/operaciones/{id}/reintentar", (HttpContext ctx, string id) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();

    var existe = database.Escalar("SELECT COUNT(*) FROM operaciones WHERE id = @id",
        p => p.AddWithValue("@id", id));
    if (Convert.ToInt64(existe) == 0) return Results.NotFound(new { error = "Operacion inexistente" });

    var estadoSapActual = database.Escalar("SELECT estado_sap FROM operaciones WHERE id = @id",
        p => p.AddWithValue("@id", id))?.ToString();
    if (estadoSapActual is "OK" or "NP")
        return Results.Json(
            new { error = "SAP ya informo un resultado; no corresponde regenerar el archivo" },
            statusCode: 409);

    return Results.Ok(recepcion.GenerarArchivo(id));
});

app.MapGet("/api/operaciones/{id}/archivo", (HttpContext ctx, string id) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    var op = database.Consultar("SELECT archivo_nombre FROM operaciones WHERE id = @id",
        p => p.AddWithValue("@id", id)).FirstOrDefault();
    if (op is null) return Results.NotFound(new { error = "Operacion inexistente" });
    var nombre = op["archivo_nombre"]?.ToString();
    if (string.IsNullOrWhiteSpace(nombre)) return Results.NotFound(new { error = "Sin archivo generado" });
    var ruta = Path.Combine(config.RutaCarpetaSalida, nombre);
    if (!File.Exists(ruta))
    {
        var archivos = Directory.GetFiles(config.RutaCarpetaSalida, nombre, SearchOption.AllDirectories);
        if (archivos.Length > 0) ruta = archivos[0];
    }
    if (!File.Exists(ruta)) return Results.NotFound(new { error = "Archivo no encontrado en servidor" });
    var bytes = File.ReadAllBytes(ruta);
    return Results.File(bytes, "text/csv", nombre);
});

app.MapGet("/api/sinequivalencia", (HttpContext ctx) =>
{
    var auth = Autenticar(ctx);
    if (auth is null) return NoAutorizado();
    if (!EsAdmin(auth.Value.Usuario)) return Prohibido();

    var resumen = database.Consultar("""
        SELECT p.qr_leido, COUNT(*) AS veces, MAX(o.fecha_cierre) AS ultima_fecha
        FROM posiciones p JOIN operaciones o ON o.id = p.operacion_id
        WHERE p.origen = 'MANUAL'
        GROUP BY p.qr_leido
        ORDER BY MAX(o.fecha_cierre) DESC
        """);

    var ultimos = database.Consultar("""
        SELECT qr_leido, material_sap, usuario FROM (
            SELECT p.qr_leido, p.material_sap, o.usuario,
                   ROW_NUMBER() OVER (PARTITION BY p.qr_leido ORDER BY o.fecha_cierre DESC) AS rn
            FROM posiciones p JOIN operaciones o ON o.id = p.operacion_id
            WHERE p.origen = 'MANUAL'
        ) WHERE rn = 1
        """);

    var ultimosPorQr = ultimos.ToDictionary(
        f => f["qr_leido"]?.ToString() ?? "",
        f => (material_sap: f["material_sap"]?.ToString(), ultimo_usuario: f["usuario"]?.ToString()));

    var resultado = resumen.Select(f =>
    {
        var qr = f["qr_leido"]?.ToString() ?? "";
        ultimosPorQr.TryGetValue(qr, out var extra);
        return new Dictionary<string, object?>
        {
            ["qr_leido"] = qr,
            ["material_usado"] = extra.material_sap,
            ["veces"] = f["veces"],
            ["ultima_fecha"] = f["ultima_fecha"],
            ["ultimo_usuario"] = extra.ultimo_usuario
        };
    }).ToList();

    return Results.Ok(resultado);
});

app.Run($"http://0.0.0.0:{config.Puerto}");

public sealed class LoginEntrada
{
    public string Usuario { get; set; } = "";
    public string Pin { get; set; } = "";
}

public sealed class ReservaOperacionEntrada
{
    public string Id { get; set; } = "";
}

public sealed class EquivalenciaEntrada
{
    public string CodigoQr { get; set; } = "";
    public string MaterialSap { get; set; } = "";
    public string? Descripcion { get; set; }
    public string? UnidadSap { get; set; }
    public string? UnidadLectura { get; set; }
    public double FactorConversion { get; set; } = 1;
    public bool Activo { get; set; } = true;
}

public sealed class CecoEntrada
{
    public string Ceco { get; set; } = "";
    public string? Descripcion { get; set; }
    public bool Activo { get; set; } = true;
}

public sealed class UsuarioEntrada
{
    public string Usuario { get; set; } = "";
    public string? Nombre { get; set; }
    public string? Email { get; set; }
    public string? Pin { get; set; }
    public string? Perfil { get; set; }
    public bool? Activo { get; set; }
}
