import '../core/api.dart';
import '../core/config.dart';
import '../data/db.dart';

class ResultadoSync {
  final bool ok;
  final int enviadas;
  final List<String> errores;
  ResultadoSync(this.ok, this.enviadas, this.errores);
}

class Sync {
  static Future<ResultadoSync>? _sincronizacion;

  static Future<ResultadoSync> sincronizarTodo() {
    final enCurso = _sincronizacion;
    if (enCurso != null) return enCurso;
    late final Future<ResultadoSync> nueva;
    nueva = _ejecutarSincronizacion().whenComplete(() {
      if (identical(_sincronizacion, nueva)) _sincronizacion = null;
    });
    _sincronizacion = nueva;
    return nueva;
  }

  static Future<ResultadoSync> _ejecutarSincronizacion() async {
    final errores = <String>[];
    var enviadas = 0;

    final pendientes = await Db.operaciones(estados: 'PENDIENTE,ERROR');
    for (final op in pendientes) {
      try {
        await _enviarOperacion(op);
        enviadas++;
      } on ApiException catch (e) {
        errores.add('Op ${op['orden']}: ${e.mensaje}');
      } catch (e) {
        errores.add('Op ${op['orden']}: $e');
      }
    }

    try {
      await bajarMaestros();
    } on ApiException catch (e) {
      errores.add(e.mensaje);
    } catch (_) {}

    return ResultadoSync(errores.isEmpty || enviadas > 0, enviadas, errores);
  }

  static Future<void> _enviarOperacion(Map<String, Object?> op) async {
    final posiciones = await Db.posiciones(op['id'] as String);
    final cuerpo = {
      'id': op['id'],
      'tipo': op['tipo'] ?? 'PICK',
      'usuario': op['usuario'],
      'fechaCreacion': op['fecha_creacion'],
      'fechaCierre': op['fecha_cierre'],
      'orden': op['orden'],
      'ceco': op['ceco'],
      'claseMovimiento': op['clase_movimiento'],
      'centro': op['centro'],
      'almacen': op['almacen'],
      'textoCabecera': op['texto_cabecera'] ?? '',
      'posiciones': posiciones
          .map(
            (p) => {
              'linea': p['linea'],
              'qrLeido': p['qr_leido'] ?? '',
              'materialSap': p['material_sap'],
              'descripcion': p['descripcion'] ?? '',
              'unidadLectura': p['unidad_lectura'] ?? '',
              'cantidadLectura': p['cantidad_lectura'],
              'unidadSap': p['unidad_sap'],
              'cantidadSap': p['cantidad_sap'],
              'textoPosicion': p['texto_posicion'] ?? '',
              'origen': p['origen'],
            },
          )
          .toList(),
    };
    final resp = await Api.post(
      '/api/operaciones',
      cuerpo,
      token: Config.token,
    );
    if (resp is Map) {
      final estado = resp['estado']?.toString() ?? 'ERROR';
      await Db.marcarEstadoOp(
        op['id'] as String,
        estado == 'PROCESADO' ? 'PROCESADO' : 'ERROR',
        archivo: resp['archivo_nombre']?.toString(),
        error: resp['msg_error']?.toString(),
        estadoSap: resp['estado_sap']?.toString(),
        archivoSap: resp['archivo_sap_nombre']?.toString(),
        fechaSap: resp['estado_sap_fecha']?.toString(),
        orden: resp['orden']?.toString(),
        docSap: resp['doc_sap']?.toString(),
        estadoSapDetalle: resp['estado_sap_detalle']?.toString(),
      );
    }
  }

  static Future<bool> bajarMaestros() async {
    final m = await Api.get('/api/maestros', token: Config.token);
    if (m is! Map) return false;
    List<Map<String, Object?>> listaDe(dynamic x) =>
        (x as List?)
            ?.map((e) => Map<String, Object?>.from(e as Map))
            .toList() ??
        [];
    final params = Map<String, Object?>.from(m['parametros'] as Map? ?? {});
    await Db.reemplazarMaestros(
      usuarios: listaDe(m['usuarios']),
      equivalencias: listaDe(m['equivalencias']),
      cecos: listaDe(m['cecos']),
      almacenes: listaDe(m['almacenes']),
      clasesMovimiento: listaDe(m['clasesMovimiento']),
      centrosSap: listaDe(m['centros']),
      parametros: params.map((k, v) => MapEntry(k.toString(), v.toString())),
    );
    try {
      if (Config.usuario != null && Config.usuario!.isNotEmpty) {
        final ops = await Api.get(
          '/api/operaciones/usuario/${Uri.encodeComponent(Config.usuario!)}',
          token: Config.token,
        );
        if (ops is List && ops.isNotEmpty) {
          await Db.insertarOperacionesServidor(ops);
        }
        await Db.limpiarHistorialConfirmado();
      }
    } catch (_) {}
    return true;
  }
}
