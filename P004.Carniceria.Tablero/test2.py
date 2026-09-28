import sqlite3
conn = sqlite3.connect('datos/carniceria.sqlite')
cur = conn.cursor()
cur.execute("SELECT DISTINCT grupo FROM ventas LIMIT 5")
print("GRUPO:", cur.fetchall())
cur.execute("SELECT DISTINCT expone FROM ventas LIMIT 5")
print("EXPONE:", cur.fetchall())
