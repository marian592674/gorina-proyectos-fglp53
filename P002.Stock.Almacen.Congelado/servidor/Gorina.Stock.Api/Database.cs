using MySqlConnector;
using System.Text.Json;

namespace Gorina.Stock.Api;

public sealed class Database(Config config)
{
    private string CadenaConexion => new MySqlConnectionStringBuilder
    {
        Server = config.DbHost,
        Port = (uint)config.DbPort,
        UserID = config.DbUser,
        Password = config.DbPass,
        Database = config.DbName,
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

    public void AsegurarEsquema()
    {
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = """
            CREATE TABLE IF NOT EXISTS `catalogo_skus` (
                `sku` VARCHAR(50) PRIMARY KEY,
                `nombre` VARCHAR(255) NOT NULL DEFAULT '',
                `destino` VARCHAR(50) NOT NULL DEFAULT '',
                `material_sap` VARCHAR(50) NOT NULL DEFAULT '',
                `activo` TINYINT NOT NULL DEFAULT 1,
                `actualizado_utc` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS `cargas` (
                `id` VARCHAR(50) PRIMARY KEY,
                `fecha` DATE NULL,
                `hora` VARCHAR(20) NULL,
                `estado` VARCHAR(50) NOT NULL DEFAULT 'En Proceso',
                `cliente` VARCHAR(100) NULL,
                `pallets_solicitados` INT NOT NULL DEFAULT 0,
                `kilos_estimados` DOUBLE NOT NULL DEFAULT 0,
                `kilos_reales` DOUBLE NULL,
                `desvio_kilos` DOUBLE NULL,
                `observaciones` TEXT NULL,
                `ordenes_count` INT NOT NULL DEFAULT 0,
                `items_json` JSON NULL,
                `romaneos_json` JSON NULL,
                `creado_utc` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `actualizado_utc` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX `idx_cargas_fecha` (`fecha`),
                INDEX `idx_cargas_estado` (`estado`)
            );
            CREATE TABLE IF NOT EXISTS `romaneos_resumen` (
                `romaneo` VARCHAR(50) PRIMARY KEY,
                `tipo` VARCHAR(20) NOT NULL DEFAULT 'RS',
                `fecha` VARCHAR(20) NULL,
                `hora` VARCHAR(20) NULL,
                `observacion` VARCHAR(255) NULL,
                `con` VARCHAR(50) NULL,
                `conservacion` VARCHAR(50) NULL,
                `patente` VARCHAR(50) NULL,
                `destino` VARCHAR(50) NULL,
                `cajas` INT NOT NULL DEFAULT 0,
                `kg_neto` DOUBLE NOT NULL DEFAULT 0,
                `ofertas` VARCHAR(255) NULL,
                `cliente` VARCHAR(100) NULL,
                `deposito` VARCHAR(50) NULL,
                `archivo` VARCHAR(255) NULL,
                `ticks` BIGINT NULL,
                `actualizado_utc` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX `idx_romaneos_fecha` (`fecha`),
                INDEX `idx_romaneos_patente` (`patente`)
            );
            CREATE TABLE IF NOT EXISTS `analisis_manual` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `tipo` ENUM('PALLET', 'CAJA') NOT NULL,
                `codigo_lpn` VARCHAR(50) NOT NULL,
                `activo` TINYINT NOT NULL DEFAULT 1,
                `fecha_marcado` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY `ux_analisis_tipo_lpn` (`tipo`, `codigo_lpn`)
            );
            CREATE TABLE IF NOT EXISTS `configuracion` (
                `clave` VARCHAR(50) PRIMARY KEY,
                `valor` TEXT NOT NULL,
                `actualizado_utc` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            );
            """;
        cmd.ExecuteNonQuery();
    }

    public Dictionary<string, CatalogoItem> GetCatalogo()
    {
        var dic = new Dictionary<string, CatalogoItem>(StringComparer.OrdinalIgnoreCase);
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = "SELECT sku, nombre, destino, material_sap FROM catalogo_skus WHERE activo = 1";
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var item = new CatalogoItem
            {
                Sku = reader.GetString(0),
                Nombre = reader.IsDBNull(1) ? "" : reader.GetString(1),
                Destino = reader.IsDBNull(2) ? "" : reader.GetString(2),
                MaterialSap = reader.IsDBNull(3) ? "" : reader.GetString(3)
            };
            dic[item.Sku] = item;
        }
        return dic;
    }

    public List<Carga> GetCargas()
    {
        var lista = new List<Carga>();
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = """
            SELECT id, fecha, hora, estado, cliente, pallets_solicitados, kilos_estimados,
                   kilos_reales, desvio_kilos, observaciones, ordenes_count, items_json, romaneos_json
            FROM cargas
            ORDER BY id DESC
            """;
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var c = new Carga
            {
                Id = reader.GetString(0),
                Fecha = reader.IsDBNull(1) ? null : reader.GetDateTime(1).ToString("yyyy-MM-dd"),
                Hora = reader.IsDBNull(2) ? null : reader.GetString(2),
                Estado = reader.IsDBNull(3) ? "En Proceso" : reader.GetString(3),
                Cliente = reader.IsDBNull(4) ? null : reader.GetString(4),
                PalletsSolicitados = reader.IsDBNull(5) ? 0 : reader.GetInt32(5),
                KilosEstimados = reader.IsDBNull(6) ? 0 : reader.GetDouble(6),
                KilosReales = reader.IsDBNull(7) ? null : reader.GetDouble(7),
                DesvioKilos = reader.IsDBNull(8) ? null : reader.GetDouble(8),
                Observaciones = reader.IsDBNull(9) ? null : reader.GetString(9),
                OrdenesCount = reader.IsDBNull(10) ? 0 : reader.GetInt32(10)
            };

            if (!reader.IsDBNull(11))
            {
                try { c.Items = JsonSerializer.Deserialize<List<Dictionary<string, object?>>>(reader.GetString(11)) ?? new(); } catch { }
            }
            if (!reader.IsDBNull(12))
            {
                try { c.Romaneos = JsonSerializer.Deserialize<List<Dictionary<string, object?>>>(reader.GetString(12)) ?? new(); } catch { }
            }

            lista.Add(c);
        }
        return lista;
    }

    public void GuardarCarga(Carga c)
    {
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = """
            INSERT INTO cargas (id, fecha, hora, estado, cliente, pallets_solicitados,
                                kilos_estimados, kilos_reales, desvio_kilos, observaciones,
                                ordenes_count, items_json, romaneos_json)
            VALUES (@id, @fecha, @hora, @estado, @cliente, @pallets, @k_est, @k_real, @desvio, @obs, @ord_cnt, @items, @romaneos)
            ON DUPLICATE KEY UPDATE
                fecha = VALUES(fecha),
                hora = VALUES(hora),
                estado = VALUES(estado),
                cliente = VALUES(cliente),
                pallets_solicitados = VALUES(pallets_solicitados),
                kilos_estimados = VALUES(kilos_estimados),
                kilos_reales = VALUES(kilos_reales),
                desvio_kilos = VALUES(desvio_kilos),
                observaciones = VALUES(observaciones),
                ordenes_count = VALUES(ordenes_count),
                items_json = VALUES(items_json),
                romaneos_json = VALUES(romaneos_json)
            """;
        cmd.Parameters.AddWithValue("@id", c.Id);
        cmd.Parameters.AddWithValue("@fecha", string.IsNullOrWhiteSpace(c.Fecha) ? (object)DBNull.Value : c.Fecha);
        cmd.Parameters.AddWithValue("@hora", (object?)c.Hora ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@estado", c.Estado ?? "En Proceso");
        cmd.Parameters.AddWithValue("@cliente", (object?)c.Cliente ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@pallets", c.PalletsSolicitados);
        cmd.Parameters.AddWithValue("@k_est", c.KilosEstimados);
        cmd.Parameters.AddWithValue("@k_real", (object?)c.KilosReales ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@desvio", (object?)c.DesvioKilos ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@obs", (object?)c.Observaciones ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@ord_cnt", c.OrdenesCount);
        cmd.Parameters.AddWithValue("@items", JsonSerializer.Serialize(c.Items));
        cmd.Parameters.AddWithValue("@romaneos", JsonSerializer.Serialize(c.Romaneos));
        cmd.ExecuteNonQuery();
    }

    public void EliminarCarga(string id)
    {
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = "DELETE FROM cargas WHERE id = @id";
        cmd.Parameters.AddWithValue("@id", id);
        cmd.ExecuteNonQuery();
    }

    public List<Romaneo> GetRomaneos()
    {
        var lista = new List<Romaneo>();
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = """
            SELECT romaneo, tipo, fecha, hora, observacion, con, conservacion, patente,
                   destino, cajas, kg_neto, ofertas, cliente, deposito, archivo, ticks
            FROM romaneos_resumen
            ORDER BY ticks DESC, romaneo DESC
            """;
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            lista.Add(new Romaneo
            {
                RomaneoId = reader.GetString(0),
                Tipo = reader.IsDBNull(1) ? "RS" : reader.GetString(1),
                Fecha = reader.IsDBNull(2) ? null : reader.GetString(2),
                Hora = reader.IsDBNull(3) ? null : reader.GetString(3),
                Observacion = reader.IsDBNull(4) ? null : reader.GetString(4),
                Con = reader.IsDBNull(5) ? null : reader.GetString(5),
                Conservacion = reader.IsDBNull(6) ? null : reader.GetString(6),
                Patente = reader.IsDBNull(7) ? null : reader.GetString(7),
                Destino = reader.IsDBNull(8) ? null : reader.GetString(8),
                Cajas = reader.IsDBNull(9) ? 0 : reader.GetInt32(9),
                KgNeto = reader.IsDBNull(10) ? 0 : reader.GetDouble(10),
                Ofertas = reader.IsDBNull(11) ? null : reader.GetString(11),
                Cliente = reader.IsDBNull(12) ? null : reader.GetString(12),
                Deposito = reader.IsDBNull(13) ? null : reader.GetString(13),
                Archivo = reader.IsDBNull(14) ? null : reader.GetString(14),
                Ticks = reader.IsDBNull(15) ? null : reader.GetInt64(15)
            });
        }
        return lista;
    }

    public void GuardarRomaneos(IEnumerable<Romaneo> romaneos)
    {
        using var cnn = Abrir();
        foreach (var r in romaneos)
        {
            using var cmd = cnn.CreateCommand();
            cmd.CommandText = """
                INSERT INTO romaneos_resumen (romaneo, tipo, fecha, hora, observacion, con, conservacion, patente, destino, cajas, kg_neto, ofertas, cliente, deposito, archivo, ticks)
                VALUES (@rom, @tipo, @fecha, @hora, @obs, @con, @conserv, @pat, @dest, @cajas, @kg_neto, @ofertas, @cliente, @dep, @archivo, @ticks)
                ON DUPLICATE KEY UPDATE
                    tipo = VALUES(tipo),
                    fecha = VALUES(fecha),
                    hora = VALUES(hora),
                    observacion = VALUES(observacion),
                    con = VALUES(con),
                    conservacion = VALUES(conservacion),
                    patente = VALUES(patente),
                    destino = VALUES(destino),
                    cajas = VALUES(cajas),
                    kg_neto = VALUES(kg_neto),
                    ofertas = VALUES(ofertas),
                    cliente = VALUES(cliente),
                    deposito = VALUES(deposito),
                    archivo = VALUES(archivo),
                    ticks = VALUES(ticks)
                """;
            cmd.Parameters.AddWithValue("@rom", r.RomaneoId);
            cmd.Parameters.AddWithValue("@tipo", r.Tipo ?? "RS");
            cmd.Parameters.AddWithValue("@fecha", (object?)r.Fecha ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@hora", (object?)r.Hora ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@obs", (object?)r.Observacion ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@con", (object?)r.Con ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@conserv", (object?)r.Conservacion ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@pat", (object?)r.Patente ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@dest", (object?)r.Destino ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@cajas", r.Cajas);
            cmd.Parameters.AddWithValue("@kg_neto", r.KgNeto);
            cmd.Parameters.AddWithValue("@ofertas", (object?)r.Ofertas ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@cliente", (object?)r.Cliente ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@dep", (object?)r.Deposito ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@archivo", (object?)r.Archivo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ticks", (object?)r.Ticks ?? DBNull.Value);
            cmd.ExecuteNonQuery();
        }
    }

    public AnalisisManualDto GetAnalisisManual()
    {
        var dto = new AnalisisManualDto();
        using var cnn = Abrir();
        using var cmd = cnn.CreateCommand();
        cmd.CommandText = "SELECT tipo, codigo_lpn FROM analisis_manual WHERE activo = 1";
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var tipo = reader.GetString(0);
            var lpn = reader.GetString(1);
            if (tipo == "PALLET") dto.Pallets.Add(lpn);
            else if (tipo == "CAJA") dto.Cajas.Add(lpn);
        }
        return dto;
    }

    public void MarcarAnalisis(IEnumerable<string>? pallets, IEnumerable<string>? cajas)
    {
        using var cnn = Abrir();
        if (pallets != null)
        {
            foreach (var p in pallets)
            {
                var clean = p.Trim().TrimStart('0');
                if (string.IsNullOrEmpty(clean)) clean = "0";
                using var cmd = cnn.CreateCommand();
                cmd.CommandText = "INSERT INTO analisis_manual (tipo, codigo_lpn, activo) VALUES ('PALLET', @lpn, 1) ON DUPLICATE KEY UPDATE activo = 1";
                cmd.Parameters.AddWithValue("@lpn", clean);
                cmd.ExecuteNonQuery();
            }
        }
        if (cajas != null)
        {
            foreach (var c in cajas)
            {
                var clean = c.Trim().TrimStart('0');
                if (string.IsNullOrEmpty(clean)) clean = "0";
                using var cmd = cnn.CreateCommand();
                cmd.CommandText = "INSERT INTO analisis_manual (tipo, codigo_lpn, activo) VALUES ('CAJA', @lpn, 1) ON DUPLICATE KEY UPDATE activo = 1";
                cmd.Parameters.AddWithValue("@lpn", clean);
                cmd.ExecuteNonQuery();
            }
        }
    }

    public void DesmarcarAnalisis(IEnumerable<string>? pallets, IEnumerable<string>? cajas)
    {
        using var cnn = Abrir();
        if (pallets != null)
        {
            foreach (var p in pallets)
            {
                var clean = p.Trim().TrimStart('0');
                if (string.IsNullOrEmpty(clean)) clean = "0";
                using var cmd = cnn.CreateCommand();
                cmd.CommandText = "DELETE FROM analisis_manual WHERE tipo = 'PALLET' AND codigo_lpn = @lpn";
                cmd.Parameters.AddWithValue("@lpn", clean);
                cmd.ExecuteNonQuery();
            }
        }
        if (cajas != null)
        {
            foreach (var c in cajas)
            {
                var clean = c.Trim().TrimStart('0');
                if (string.IsNullOrEmpty(clean)) clean = "0";
                using var cmd = cnn.CreateCommand();
                cmd.CommandText = "DELETE FROM analisis_manual WHERE tipo = 'CAJA' AND codigo_lpn = @lpn";
                cmd.Parameters.AddWithValue("@lpn", clean);
                cmd.ExecuteNonQuery();
            }
        }
    }
}
