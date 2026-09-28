"""
Módulo de Persistencia y Conexión a MySQL 8.0 para Dashboard Ciclo 3 (P001).
Cumple con los lineamientos técnicos corporativos (D:\\LINEAMIENTOS_DE_TRABAJO).
"""
import json
import os
import re
from pathlib import Path
import pymysql
import pymysql.constants.FIELD_TYPE
import pymysql.converters

ROOT = Path(__file__).resolve().parent

def load_config():
    cfg_file = ROOT / 'config.json'
    if cfg_file.is_file():
        try:
            return json.loads(cfg_file.read_text(encoding='utf-8-sig'))
        except Exception:
            pass
    return {}

CONFIG = load_config()

# Intentar leer desde .env si existe en el proyecto
ENV_FILE = ROOT.parent.parent / '.env'
if ENV_FILE.is_file():
    try:
        for line in ENV_FILE.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                os.environ.setdefault(k.strip(), v.strip())
    except Exception:
        pass

DB_HOST = os.getenv('DB_HOST', CONFIG.get('mysql_local', {}).get('host', '127.0.0.1'))
DB_PORT = int(os.getenv('DB_PORT', CONFIG.get('mysql_local', {}).get('port', 3306)))
DB_USER = os.getenv('DB_USER', CONFIG.get('mysql_local', {}).get('user', 'root'))
DB_PASS = os.getenv('DB_PASS', CONFIG.get('mysql_local', {}).get('password', 'gorina2025'))
DB_NAME = os.getenv('DB_NAME', CONFIG.get('mysql_local', {}).get('database', 'P001.Dashboard.Ciclo.3'))

def translate_query(query):
    q = query
    # Reemplaza INSERT OR REPLACE INTO por REPLACE INTO
    q = re.sub(r'INSERT\s+OR\s+REPLACE\s+INTO', 'REPLACE INTO', q, flags=re.IGNORECASE)
    # Reemplaza INSERT OR IGNORE INTO por INSERT IGNORE INTO
    q = re.sub(r'INSERT\s+OR\s+IGNORE\s+INTO', 'INSERT IGNORE INTO', q, flags=re.IGNORECASE)
    # Reemplaza ON CONFLICT(...) DO UPDATE SET por ON DUPLICATE KEY UPDATE
    q = re.sub(r'ON\s+CONFLICT\s*\([^)]*\)\s*DO\s+UPDATE\s+SET', 'ON DUPLICATE KEY UPDATE', q, flags=re.IGNORECASE)
    # Reemplaza excluded.campo por VALUES(campo)
    q = re.sub(r'excluded\.([a-zA-Z0-9_]+)', r'VALUES(\1)', q, flags=re.IGNORECASE)
    # Reemplaza movimientos_horarios.occ por occ
    q = re.sub(r'movimientos_horarios\.occ', 'occ', q, flags=re.IGNORECASE)
    # Reemplaza ? por %s para PyMySQL
    q = q.replace('?', '%s')
    
    # Normalizar palabra reservada `out`
    q = q.replace('`out`', 'out')
    q = re.sub(r'\bout\b', '`out`', q, flags=re.IGNORECASE)
    return q

class Row:
    def __init__(self, cursor, values):
        self._keys = [col[0] for col in cursor.description] if cursor.description else []
        self._values = list(values) if values is not None else []
        self._dict = {k: v for k, v in zip(self._keys, self._values)}

    def __getitem__(self, item):
        if isinstance(item, int):
            return self._values[item]
        return self._dict[item]

    def __contains__(self, item):
        return item in self._dict

    def get(self, item, default=None):
        return self._dict.get(item, default)

    def keys(self):
        return self._keys

    def values(self):
        return self._values

    def items(self):
        return self._dict.items()

    def __repr__(self):
        return repr(self._dict)

class MySQLCursorWrapper:
    def __init__(self, cursor, conn_wrapper=None):
        self._cursor = cursor
        self._conn_wrapper = conn_wrapper

    def execute(self, sql, params=None):
        sql_trans = translate_query(sql)
        if params is not None:
            if isinstance(params, list):
                params = tuple(params)
            self._cursor.execute(sql_trans, params)
        else:
            self._cursor.execute(sql_trans)
        return self

    def executemany(self, sql, seq_of_params):
        sql_trans = translate_query(sql)
        self._cursor.executemany(sql_trans, seq_of_params)
        return self

    def fetchone(self):
        val = self._cursor.fetchone()
        if val is None:
            return None
        return Row(self._cursor, val)

    def fetchall(self):
        vals = self._cursor.fetchall()
        return [Row(self._cursor, v) for v in vals]

    def fetchmany(self, size=None):
        vals = self._cursor.fetchmany(size) if size else self._cursor.fetchmany()
        return [Row(self._cursor, v) for v in vals]

    def close(self):
        try:
            self._cursor.close()
        except Exception:
            pass

    def __iter__(self):
        while True:
            row = self.fetchone()
            if row is None:
                break
            yield row

    @property
    def rowcount(self):
        return self._cursor.rowcount

    @property
    def lastrowid(self):
        return self._cursor.lastrowid

    @property
    def description(self):
        return self._cursor.description

class MySQLWrapper:
    def __init__(self, conn):
        self._conn = conn

    def cursor(self):
        return MySQLCursorWrapper(self._conn.cursor(), self)

    def execute(self, sql, params=None):
        cur = self.cursor()
        cur.execute(sql, params)
        return cur

    def executemany(self, sql, seq_of_params):
        cur = self.cursor()
        cur.executemany(sql, seq_of_params)
        return cur

    def commit(self):
        self._conn.commit()

    def rollback(self):
        self._conn.rollback()

    def close(self):
        try:
            self._conn.close()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            self.rollback()
        else:
            self.commit()
        return False

conv = pymysql.converters.conversions.copy()
conv[pymysql.constants.FIELD_TYPE.DECIMAL] = float
conv[pymysql.constants.FIELD_TYPE.NEWDECIMAL] = float

def get_db():
    conn = pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        charset='utf8mb4',
        autocommit=True,
        conv=conv
    )
    return MySQLWrapper(conn)

def init_db():
    conn = pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS,
        charset='utf8mb4',
        autocommit=True
    )
    cur = conn.cursor()
    cur.execute(f"CREATE DATABASE IF NOT EXISTS `{DB_NAME}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
    conn.select_db(DB_NAME)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS raw_ingest (
        id INT AUTO_INCREMENT PRIMARY KEY,
        fecha_ingreso DATETIME DEFAULT CURRENT_TIMESTAMP,
        origen VARCHAR(255) NOT NULL,
        payload LONGTEXT NOT NULL,
        estado_proceso ENUM('OK', 'ERROR') NOT NULL,
        detalle_error TEXT,
        INDEX idx_fecha (fecha_ingreso),
        INDEX idx_estado (estado_proceso)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS movimientos_horarios (
        id INT AUTO_INCREMENT PRIMARY KEY,
        sistema VARCHAR(50) NOT NULL,
        fecha_operativa VARCHAR(20) NOT NULL,
        turno INT NOT NULL,
        hora VARCHAR(10) NOT NULL,
        inn DECIMAL(12,2) DEFAULT 0,
        `out` DECIMAL(12,2) DEFAULT 0,
        occ DECIMAL(8,4) DEFAULT NULL,
        updated_at VARCHAR(50),
        UNIQUE KEY uk_sistema_fecha_hora (sistema, fecha_operativa, hora),
        INDEX idx_mov_horarios (fecha_operativa, sistema)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS telemetria_scada (
        id INT AUTO_INCREMENT PRIMARY KEY,
        fecha_hora VARCHAR(50) NOT NULL,
        sistema VARCHAR(50) NOT NULL,
        inn DECIMAL(12,2) DEFAULT 0,
        `out` DECIMAL(12,2) DEFAULT 0,
        UNIQUE KEY uk_scada (fecha_hora, sistema),
        INDEX idx_fecha_hora (fecha_hora)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS operaciones_diarias (
        id INT AUTO_INCREMENT PRIMARY KEY,
        sistema VARCHAR(50) NOT NULL,
        fecha VARCHAR(20) NOT NULL,
        inn DECIMAL(14,2) DEFAULT 0,
        `out` DECIMAL(14,2) DEFAULT 0,
        occ DECIMAL(8,4) DEFAULT NULL,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uk_sistema_fecha (sistema, fecha),
        INDEX idx_fecha (fecha),
        INDEX idx_sistema (sistema)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)

    cur.execute("""
    CREATE OR REPLACE VIEW vw_dashboard_horario AS
    SELECT 
        fecha_operativa,
        turno,
        hora,
        sistema,
        inn,
        `out`,
        occ
    FROM movimientos_horarios
    ORDER BY fecha_operativa, hora;
    """)

    cur.execute("""
    CREATE OR REPLACE VIEW vw_dashboard_diario AS
    SELECT 
        fecha,
        sistema,
        inn,
        `out`,
        occ
    FROM operaciones_diarias
    ORDER BY fecha DESC, sistema;
    """)
    conn.close()

if __name__ == '__main__':
    init_db()
    db = get_db()
    res = db.execute("SELECT COUNT(*) FROM movimientos_horarios").fetchone()
    print(f"Prueba conexion MySQL P001 exitosa: {res[0]} movimientos horarios.")
    db.close()
