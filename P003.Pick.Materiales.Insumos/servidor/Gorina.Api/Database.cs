using MySqlConnector;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace Gorina.Api;

public sealed partial class Database
{
    private readonly Config _config;

    public Database(Config config)
    {
        _config = config;
        AsegurarEsquema();
    }

    private string CadenaConexion => new MySqlConnectionStringBuilder
    {
        Server = Environment.GetEnvironmentVariable("DB_HOST") ?? _config.DbHost,
        Port = uint.TryParse(Environment.GetEnvironmentVariable("DB_PORT"), out var p) ? p : (uint)_config.DbPort,
        UserID = Environment.GetEnvironmentVariable("DB_USER") ?? _config.DbUser,
        Password = Environment.GetEnvironmentVariable("DB_PASS") ?? _config.DbPass,
        Database = Environment.GetEnvironmentVariable("DB_NAME") ?? _config.DbName,
        ConnectionTimeout = 30,
        AllowUserVariables = true,
        CharacterSet = "utf8mb4"
    }.ToString();

    public MySqlConnection Abrir()
    {
        var cnn = new MySqlConnection(CadenaConexion);
        cnn.Open();
        return cnn;
    }

    public static string TranslateQuery(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql)) return sql;

        // datetime('now', 'localtime', '-X hours') -> DATE_SUB(NOW(), INTERVAL X HOUR)
        var translated = Regex.Replace(sql, @"datetime\s*\(\s*'now'\s*,\s*'localtime'\s*,\s*'-(\d+)\s+hours?'\s*\)", "DATE_SUB(NOW(), INTERVAL $1 HOUR)", RegexOptions.IgnoreCase);
        translated = Regex.Replace(translated, @"datetime\s*\(\s*'now'\s*,\s*'localtime'\s*,\s*'-(\d+)\s+days?'\s*\)", "DATE_SUB(NOW(), INTERVAL $1 DAY)", RegexOptions.IgnoreCase);

        // INSERT OR IGNORE INTO -> INSERT IGNORE INTO
        translated = Regex.Replace(translated, @"INSERT\s+OR\s+IGNORE\s+INTO", "INSERT IGNORE INTO", RegexOptions.IgnoreCase);

        // INSERT OR REPLACE INTO -> REPLACE INTO
        translated = Regex.Replace(translated, @"INSERT\s+OR\s+REPLACE\s+INTO", "REPLACE INTO", RegexOptions.IgnoreCase);

        return translated;
    }

    public int Ejecutar(string sql, Action<MySqlParameterCollection>? bind = null)
    {
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = TranslateQuery(sql);
        bind?.Invoke(cmd.Parameters);
        return cmd.ExecuteNonQuery();
    }

    public object? Escalar(string sql, Action<MySqlParameterCollection>? bind = null)
    {
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = TranslateQuery(sql);
        bind?.Invoke(cmd.Parameters);
        return cmd.ExecuteScalar();
    }

    public List<Dictionary<string, object?>> Consultar(string sql, Action<MySqlParameterCollection>? bind = null)
    {
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = TranslateQuery(sql);
        bind?.Invoke(cmd.Parameters);
        using var lector = cmd.ExecuteReader();
        var filas = new List<Dictionary<string, object?>>();
        while (lector.Read())
        {
            var fila = new Dictionary<string, object?>();
            for (int i = 0; i < lector.FieldCount; i++)
                fila[lector.GetName(i)] = lector.IsDBNull(i) ? null : lector.GetValue(i);
            filas.Add(fila);
        }
        return filas;
    }

    private void AsegurarEsquema()
    {
        Ejecutar("""
            CREATE TABLE IF NOT EXISTS `usuarios` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `usuario` VARCHAR(50) NOT NULL UNIQUE,
                `nombre` VARCHAR(100) NOT NULL,
                `email` VARCHAR(100) DEFAULT '',
                `pin_hash` VARCHAR(255) NOT NULL,
                `salt` VARCHAR(255) NOT NULL,
                `perfil` VARCHAR(20) NOT NULL,
                `activo` TINYINT NOT NULL DEFAULT 1,
                `fecha_alta` DATETIME NOT NULL
            );
            CREATE TABLE IF NOT EXISTS `sesiones` (
                `token` VARCHAR(64) PRIMARY KEY,
                `usuario` VARCHAR(50) NOT NULL,
                `creada` DATETIME NOT NULL
            );
            CREATE TABLE IF NOT EXISTS `equivalencias` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `codigo_qr` VARCHAR(100) NOT NULL UNIQUE,
                `material_sap` VARCHAR(50) NOT NULL,
                `descripcion` VARCHAR(255) NOT NULL DEFAULT '',
                `unidad_sap` VARCHAR(20) NOT NULL DEFAULT '',
                `unidad_lectura` VARCHAR(20) NOT NULL DEFAULT '',
                `factor_conversion` DOUBLE NOT NULL DEFAULT 1,
                `activo` TINYINT NOT NULL DEFAULT 1,
                `fecha_alta` DATETIME NOT NULL,
                `fecha_modif` DATETIME NULL,
                `usuario_modif` VARCHAR(50) NULL
            );
            CREATE TABLE IF NOT EXISTS `centros_costo` (
                `ceco` VARCHAR(50) PRIMARY KEY,
                `descripcion` VARCHAR(255) NOT NULL DEFAULT '',
                `activo` TINYINT NOT NULL DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS `almacenes` (
                `codigo` VARCHAR(50) PRIMARY KEY,
                `centro` VARCHAR(50) NOT NULL DEFAULT '',
                `descripcion` VARCHAR(255) NOT NULL DEFAULT '',
                `activo` TINYINT NOT NULL DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS `clases_movimiento` (
                `codigo` VARCHAR(50) PRIMARY KEY,
                `descripcion` VARCHAR(255) NOT NULL DEFAULT '',
                `activo` TINYINT NOT NULL DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS `centros_sap` (
                `codigo` VARCHAR(50) PRIMARY KEY,
                `descripcion` VARCHAR(255) NOT NULL DEFAULT '',
                `activo` TINYINT NOT NULL DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS `operaciones` (
                `id` VARCHAR(50) PRIMARY KEY,
                `tipo` VARCHAR(20) NOT NULL DEFAULT 'PICK',
                `usuario` VARCHAR(50) NOT NULL,
                `fecha_creacion` DATETIME NOT NULL,
                `fecha_cierre` DATETIME NOT NULL,
                `orden` VARCHAR(50) NOT NULL UNIQUE,
                `ceco` VARCHAR(50) NOT NULL,
                `clase_movimiento` VARCHAR(50) NOT NULL,
                `centro` VARCHAR(50) NOT NULL,
                `almacen` VARCHAR(50) NOT NULL,
                `texto_cabecera` VARCHAR(255) NULL,
                `estado` VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
                `archivo_nombre` VARCHAR(255) NULL,
                `archivo_fecha` DATETIME NULL,
                `msg_error` TEXT NULL,
                `recibida_utc` DATETIME NULL,
                `estado_sap` VARCHAR(20) NULL,
                `archivo_sap_nombre` VARCHAR(255) NULL,
                `estado_sap_fecha` DATETIME NULL,
                `doc_sap` VARCHAR(50) NULL,
                `estado_sap_detalle` VARCHAR(255) NULL
            );
            CREATE TABLE IF NOT EXISTS `posiciones` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `operacion_id` VARCHAR(50) NOT NULL,
                `linea` INT NOT NULL,
                `qr_leido` VARCHAR(100) NULL,
                `material_sap` VARCHAR(50) NOT NULL,
                `descripcion` VARCHAR(255) NULL,
                `unidad_lectura` VARCHAR(20) NULL,
                `cantidad_lectura` DOUBLE NOT NULL DEFAULT 0,
                `unidad_sap` VARCHAR(20) NOT NULL,
                `cantidad_sap` DOUBLE NOT NULL,
                `texto_posicion` VARCHAR(255) NULL,
                `origen` VARCHAR(20) NOT NULL,
                INDEX `idx_posiciones_qr` (`qr_leido`),
                INDEX `idx_posiciones_op` (`operacion_id`)
            );
            CREATE TABLE IF NOT EXISTS `eventos_sap` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `operacion_id` VARCHAR(50) NOT NULL,
                `estado` VARCHAR(20) NOT NULL,
                `archivo_nombre` VARCHAR(255) NOT NULL UNIQUE,
                `fecha_sap` DATETIME NOT NULL,
                `detectado_utc` DATETIME NOT NULL,
                INDEX `idx_eventos_sap_op` (`operacion_id`, `fecha_sap`)
            );
            CREATE TABLE IF NOT EXISTS `secuencias` (
                `clave` VARCHAR(50) PRIMARY KEY,
                `ultimo_valor` BIGINT NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS `reservas_operacion` (
                `operacion_id` VARCHAR(50) PRIMARY KEY,
                `orden` BIGINT NOT NULL UNIQUE,
                `usuario` VARCHAR(50) NOT NULL,
                `creada_utc` DATETIME NOT NULL
            );
            CREATE TABLE IF NOT EXISTS `incidencias_sap` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `estado` VARCHAR(20) NOT NULL,
                `archivo_nombre` VARCHAR(255) NOT NULL UNIQUE,
                `orden_detectada` VARCHAR(50) NULL,
                `fecha_sap` DATETIME NOT NULL,
                `detectado_utc` DATETIME NOT NULL,
                `detalle` TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS `importaciones_catalogos` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `tipo` VARCHAR(50) NOT NULL,
                `archivo_nombre` VARCHAR(255) NOT NULL,
                `registros` INT NOT NULL,
                `usuario` VARCHAR(50) NOT NULL,
                `fecha` DATETIME NOT NULL,
                `estado` VARCHAR(20) NOT NULL,
                `mensaje` TEXT NULL
            );
            INSERT IGNORE INTO `secuencias` (`clave`, `ultimo_valor`) VALUES ('operacion', 0);
            """);

        var cantUsuarios = Convert.ToInt64(Escalar("SELECT COUNT(*) FROM usuarios"));
        if (cantUsuarios == 0)
        {
            var salt = PasswordHasher.NuevoSalt();
            Ejecutar(
                "INSERT INTO usuarios (usuario, nombre, pin_hash, salt, perfil, activo, fecha_alta) " +
                "VALUES (@u, @n, @h, @s, 'ADMIN', 1, @f)",
                p =>
                {
                    p.AddWithValue("@u", _config.UsuarioAdminInicial.Trim());
                    p.AddWithValue("@n", "Administrador");
                    p.AddWithValue("@h", PasswordHasher.Hash(_config.PinAdminInicial, salt));
                    p.AddWithValue("@s", salt);
                    p.AddWithValue("@f", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                });
            Console.WriteLine($"Usuario ADMIN inicial creado: {_config.UsuarioAdminInicial}");
        }
    }
}

public static class PasswordHasher
{
    private const int Iteraciones = 10000;

    public static string NuevoSalt()
    {
        var bytes = RandomNumberGenerator.GetBytes(16);
        return Convert.ToHexString(bytes);
    }

    public static string Hash(string pin, string saltHex)
    {
        var salt = Convert.FromHexString(saltHex);
        using var derivador = new Rfc2898DeriveBytes(pin, salt, Iteraciones, System.Security.Cryptography.HashAlgorithmName.SHA256);
        return Convert.ToHexString(derivador.GetBytes(32));
    }

    public static bool Verificar(string pin, string saltHex, string hashEsperado)
    {
        return CryptographicOperations.FixedTimeEquals(
            Convert.FromHexString(Hash(pin, saltHex)),
            Convert.FromHexString(hashEsperado));
    }
}
