import sqlite3
conn = sqlite3.connect('datos/carniceria.sqlite')
cur = conn.cursor()
cur.execute("SELECT DISTINCT origen FROM ventas LIMIT 5")
print(cur.fetchall())
