import pandas as pd
df = pd.read_excel(r'J:\UTIL\USER\CARNI_VENTA\Catalogo_Carniceria_Gorina.xlsx', sheet_name='Hoja2')
print(df.head(2).to_dict('records'))
