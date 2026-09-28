# Entorno LAB (Gorina Dashboard Ciclo 3)

## 1. Acceso y URLs
* **Dashboard LAB**: `http://192.168.0.126:8080/dashboard_operaciones.html`
* **Directorio Web**: `C:\Ciclo3\Servicios\DASHBOARD\LAB\dashboard_test\`
* **Colector y Scripts**: `C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\`
* **Archivos generados**: `datos.json` y `datos.js` (soporte `file://` local).

---

## 2. Fuentes de Datos (Modo Híbrido Automático)
* **TRV1 y TRV2**: MySQL `192.168.0.162:3306` (Base `p003148`, usuario `TABLERO_RO`).
* **Almacén Congelado (`crane`)**: **CTTO 2.1 API REST** (`http://fglp39v2:5000/stacker-1/api/operations/metrics/summary`).
* **Google Sheets**: Totalmente desactivado en LAB.

---

## 3. Automatización
* **Tarea en Programador de Tareas**: `Gorina LAB - Colector datos`
* **Frecuencia**: Cada 5 minutos (`PT5M`), 24/7 en segundo plano.
* **Comando**: `C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test\colector.bat`

---

## 4. Prueba Manual
Para probar una corrida manual en cualquier momento:
```cmd
cd /d C:\Ciclo3\Servicios\DASHBOARD\LAB\colector_test
python colector.py --test
```
O para ejecutar una actualización en caliente:
```cmd
colector.bat
```

