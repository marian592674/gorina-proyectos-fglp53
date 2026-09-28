import pandas as pd
df = pd.read_excel(r'J:\UTIL\USER\CARNI_VENTA\Catalogo_Carniceria_Gorina.xlsx', sheet_name='Hoja2')
print("Columnas de Hoja2:", df.columns.tolist())
