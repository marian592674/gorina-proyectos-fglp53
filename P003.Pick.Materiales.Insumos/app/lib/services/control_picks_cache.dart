import '../core/api.dart';
import '../core/config.dart';
import '../data/db.dart';

class ControlPicksCache {
  static Future<List<dynamic>>? _actualizacion;

  static Future<List<dynamic>> actualizar({int? dias}) {
    final enCurso = _actualizacion;
    if (enCurso != null) return enCurso;
    late final Future<List<dynamic>> nueva;
    nueva = _actualizar(dias: dias).whenComplete(() {
      if (identical(_actualizacion, nueva)) _actualizacion = null;
    });
    _actualizacion = nueva;
    return nueva;
  }

  static Future<List<dynamic>> _actualizar({int? dias}) async {
    var periodo = dias;
    if (periodo == null) {
      final parametros = await Db.parametros();
      periodo = int.tryParse(parametros['diasHistorialApp'] ?? '') ?? 30;
    }
    final parametrosUrl = <String>[];
    if (periodo > 0) {
      final desde = DateTime.now().subtract(Duration(days: periodo));
      String dos(int n) => n.toString().padLeft(2, '0');
      final fecha =
          '${desde.year}-${dos(desde.month)}-${dos(desde.day)} 00:00:00';
      parametrosUrl.add('desde=${Uri.encodeComponent(fecha)}');
    }
    final query = parametrosUrl.isEmpty ? '' : '?${parametrosUrl.join('&')}';
    final respuesta = await Api.get(
      '/api/operaciones$query',
      token: Config.token,
    );
    final operaciones = respuesta is List
        ? List<dynamic>.from(respuesta)
        : <dynamic>[];
    final incidencias = await Api.get(
      '/api/incidencias-sap$query',
      token: Config.token,
    );
    if (incidencias is List) {
      operaciones.addAll(
        incidencias.map((item) {
          final incidencia = Map<String, dynamic>.from(item as Map);
          return <String, dynamic>{
            'id': 'sap-incidencia-${incidencia['id']}',
            'tipo': 'INCIDENCIA_SAP',
            'usuario': 'SAP',
            'fecha_creacion': incidencia['detectado_utc'] ?? '',
            'fecha_cierre': incidencia['fecha_sap'] ?? '',
            'orden': incidencia['orden_detectada'] ?? 'sin identificar',
            'ceco': '',
            'clase_movimiento': '',
            'centro': '',
            'almacen': '',
            'texto_cabecera': '',
            'estado': 'ERROR',
            'estado_sap': 'NP',
            'archivo_nombre': '',
            'archivo_sap_nombre': incidencia['archivo_nombre'] ?? '',
            'msg_error': incidencia['detalle'] ?? '',
            'posiciones': 0,
          };
        }),
      );
    }
    operaciones.sort(
      (a, b) => (b as Map)['fecha_cierre'].toString().compareTo(
        (a as Map)['fecha_cierre'].toString(),
      ),
    );
    await Db.guardarCacheControl(operaciones, dias: periodo);
    return operaciones;
  }
}
