"""
Módulo de Persistencia y Conexión a MySQL 8.0 para Carnicería Gorina (P004).
Cumple con los lineamientos técnicos corporativos (D:\\LINEAMIENTOS_DE_TRABAJO).
"""
import json
import os
import re
from pathlib import Path
import pymysql

ROOT = Path(__file__).resolve().parent

def load_config():
    cfg_file = ROOT / 'config.json'
    if cfg_file.is_file():
        try:
            return json.loads(cfg_file.read_text(encoding='utf-8'))
        except Exception:
            pass
    return {}

CONFIG = load_config()

DB_HOST = os.getenv('DB_HOST', CONFIG.get('db_host', '127.0.0.1'))
DB_PORT = int(os.getenv('DB_PORT', CONFIG.get('db_port', 3306)))
DB_USER = os.getenv('DB_USER', CONFIG.get('db_user', 'root'))
DB_PASS = os.getenv('DB_PASS', CONFIG.get('db_pass', 'gorina2025'))
DB_NAME = os.getenv('DB_NAME', CONFIG.get('db_name', 'P004.Carniceria.Tablero'))

def translate_query(query):
    # Reemplaza INSERT OR REPLACE INTO por REPLACE INTO
    q = re.sub(r'INSERT\s+OR\s+REPLACE\s+INTO', 'REPLACE INTO', query, flags=re.IGNORECASE)
    # Reemplaza ? por %s para PyMySQL
    q = q.replace('?', '%s')
    return q

class MySQLCursorWrapper:
    def __init__(self, cursor):
        self._cursor = cursor

    def fetchone(self):
        return self._cursor.fetchone()

    def fetchall(self):
        return self._cursor.fetchall()

    def fetchmany(self, size=None):
        return self._cursor.fetchmany(size) if size else self._cursor.fetchmany()

    def __iter__(self):
        return iter(self._cursor)

    @property
    def rowcount(self):
        return self._cursor.rowcount

class MySQLWrapper:
    def __init__(self, conn):
        self._conn = conn

    def execute(self, sql, params=None):
        sql_trans = translate_query(sql)
        cur = self._conn.cursor()
        if params is not None:
            if isinstance(params, list):
                params = tuple(params)
            cur.execute(sql_trans, params)
        else:
            cur.execute(sql_trans)
        return MySQLCursorWrapper(cur)

    def executemany(self, sql, seq_of_params):
        sql_trans = translate_query(sql)
        cur = self._conn.cursor()
        cur.executemany(sql_trans, seq_of_params)
        return MySQLCursorWrapper(cur)

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
    CREATE TABLE IF NOT EXISTS ventas (
        id INT AUTO_INCREMENT PRIMARY KEY,
        fecha VARCHAR(20) NOT NULL,
        codigo VARCHAR(50),
        producto VARCHAR(255),
        tipo VARCHAR(50),
        comprobante VARCHAR(50),
        cliente VARCHAR(255),
        kg DECIMAL(14,3),
        precio DECIMAL(16,2),
        subtotal DECIMAL(18,2),
        grupo VARCHAR(100),
        agrupa VARCHAR(100),
        expone VARCHAR(100),
        condicion DECIMAL(10,2),
        neto DECIMAL(18,2),
        kg_neto DECIMAL(14,3),
        tipo_venta VARCHAR(100),
        donacion VARCHAR(50),
        origen VARCHAR(255),
        fila INT,
        INDEX idx_fecha (fecha),
        INDEX idx_cliente (cliente),
        INDEX idx_producto (producto),
        INDEX idx_tipo_venta (tipo_venta),
        INDEX idx_grupo (grupo),
        INDEX idx_tipo (tipo)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS cargas (
        fecha VARCHAR(20) PRIMARY KEY,
        archivo VARCHAR(255),
        filas INT,
        actualizado VARCHAR(50)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS estado (
        clave VARCHAR(50) PRIMARY KEY,
        valor VARCHAR(255)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)

    cur.execute("""
    CREATE OR REPLACE VIEW vw_carniceria_resumen AS
    SELECT 
        fecha,
        tipo_venta,
        COUNT(id) AS total_operaciones,
        SUM(kg_neto) AS total_kg_neto,
        SUM(neto) AS total_neto
    FROM ventas
    GROUP BY fecha, tipo_venta;
    """)
    conn.close()

if __name__ == '__main__':
    init_db()
    db = get_db()
    res = db.execute("SELECT COUNT(*), MAX(fecha) FROM ventas").fetchone()
    print(f"Prueba conexion MySQL exitosa: {res[0]} ventas registradas, ultima fecha: {res[1]}")
    db.close()
