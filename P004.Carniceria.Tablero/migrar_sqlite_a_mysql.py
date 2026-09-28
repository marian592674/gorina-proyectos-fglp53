import sqlite3
import pymysql
import sys
import time

print("Iniciando migracion SQLite -> MySQL...")

# 1. Conectar a MySQL y crear base de datos
conn_mysql = pymysql.connect(host='127.0.0.1', user='root', password='gorina2025', port=3306, autocommit=False)
cur_mysql = conn_mysql.cursor()

cur_mysql.execute("CREATE DATABASE IF NOT EXISTS db_gorina_carniceria CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
cur_mysql.execute("USE db_gorina_carniceria;")

# 2. Crear tablas
print("Creando tablas en MySQL...")
cur_mysql.execute("""
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

cur_mysql.execute("""
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

cur_mysql.execute("""
CREATE TABLE IF NOT EXISTS cargas (
    fecha VARCHAR(20) PRIMARY KEY,
    archivo VARCHAR(255),
    filas INT,
    actualizado VARCHAR(50)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
""")

cur_mysql.execute("""
CREATE TABLE IF NOT EXISTS estado (
    clave VARCHAR(50) PRIMARY KEY,
    valor VARCHAR(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
""")

# Vistas
cur_mysql.execute("""
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

conn_mysql.commit()

# 3. Leer de SQLite
con_sqlite = sqlite3.connect(r"D:\GorinaData\Carniceria_Gorina\carniceria.sqlite")
cur_sqlite = con_sqlite.cursor()

# Migrar estado
cur_sqlite.execute("SELECT clave, valor FROM estado")
rows_estado = cur_sqlite.fetchall()
cur_mysql.execute("TRUNCATE TABLE estado")
for r in rows_estado:
    cur_mysql.execute("INSERT INTO estado (clave, valor) VALUES (%s, %s)", r)
conn_mysql.commit()
print(f"Estado migrado: {len(rows_estado)} filas")

# Migrar cargas
cur_sqlite.execute("SELECT fecha, archivo, filas, actualizado FROM cargas")
rows_cargas = cur_sqlite.fetchall()
cur_mysql.execute("TRUNCATE TABLE cargas")
for r in rows_cargas:
    cur_mysql.execute("INSERT INTO cargas (fecha, archivo, filas, actualizado) VALUES (%s, %s, %s, %s)", r)
conn_mysql.commit()
print(f"Cargas migradas: {len(rows_cargas)} filas")

# Migrar ventas
cur_sqlite.execute("SELECT fecha, codigo, producto, tipo, comprobante, cliente, kg, precio, subtotal, grupo, agrupa, expone, condicion, neto, kg_neto, tipo_venta, donacion, origen, fila FROM ventas")
cur_mysql.execute("TRUNCATE TABLE ventas")

batch = []
total = 0
insert_sql = """
INSERT INTO ventas (fecha, codigo, producto, tipo, comprobante, cliente, kg, precio, subtotal, grupo, agrupa, expone, condicion, neto, kg_neto, tipo_venta, donacion, origen, fila)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
"""

t0 = time.time()
while True:
    rows = cur_sqlite.fetchmany(5000)
    if not rows:
        break
    cur_mysql.executemany(insert_sql, rows)
    conn_mysql.commit()
    total += len(rows)
    print(f"Migradas {total} filas de ventas...")

print(f"Ventas migradas: {total} filas en {time.time()-t0:.2f}s")

# 4. Validacion de consistencia
cur_sqlite.execute("SELECT COUNT(*), SUM(neto), SUM(kg_neto) FROM ventas")
sq_count, sq_neto, sq_kg = cur_sqlite.fetchone()

cur_mysql.execute("SELECT COUNT(*), SUM(neto), SUM(kg_neto) FROM ventas")
my_count, my_neto, my_kg = cur_mysql.fetchone()

print("="*60)
print(f"VALIDACION:")
print(f"SQLite: Count={sq_count}, Neto={sq_neto:,.2f}, KgNeto={sq_kg:,.2f}")
print(f"MySQL : Count={my_count}, Neto={float(my_neto):,.2f}, KgNeto={float(my_kg):,.2f}")

diff_count = abs(sq_count - my_count)
diff_neto = abs(float(sq_neto) - float(my_neto))
diff_kg = abs(float(sq_kg) - float(my_kg))

if diff_count == 0 and diff_neto < 0.01 and diff_kg < 0.01:
    print("MATCH 100% PERFECTO - CONSISTENCIA CONFIRMADA")
else:
    print("ERROR DE INCONSISTENCIA EN MIGRACION")
    sys.exit(1)

con_sqlite.close()
conn_mysql.close()