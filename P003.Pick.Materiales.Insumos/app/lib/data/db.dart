import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class Db {
  static Database? _instancia;
  static Future<Database>? _apertura;

  static Future<Database> abrir() {
    final instancia = _instancia;
    if (instancia != null) return Future.value(instancia);
    return _apertura ??= _abrir();
  }

  static Future<Database> _abrir() async {
    final dir = await getDatabasesPath();
    try {
      final db = await openDatabase(
        join(dir, 'gorina_pick.db'),
        version: 7,
        singleInstance: true,
        onCreate: (db, v) async {
          await db.execute('''
          CREATE TABLE usuarios (
            usuario TEXT PRIMARY KEY, nombre TEXT, email TEXT, perfil TEXT,
            pin_hash TEXT, salt TEXT, activo INTEGER
          )''');
          await db.execute('''
          CREATE TABLE equivalencias (
            codigo_qr TEXT PRIMARY KEY, material_sap TEXT, descripcion TEXT,
            unidad_sap TEXT, unidad_lectura TEXT, factor_conversion REAL
          )''');
          await db.execute('''
          CREATE TABLE cecos (
            ceco TEXT PRIMARY KEY, descripcion TEXT
          )''');
          await db.execute('''
          CREATE TABLE almacenes (
            codigo TEXT PRIMARY KEY, centro TEXT, descripcion TEXT
          )''');
          await db.execute('''
          CREATE TABLE clases_movimiento (
            codigo TEXT PRIMARY KEY, descripcion TEXT
          )''');
          await db.execute('''
          CREATE TABLE centros_sap (
            codigo TEXT PRIMARY KEY, descripcion TEXT
          )''');
          await db.execute('''
          CREATE TABLE parametros (
            clave TEXT PRIMARY KEY, valor TEXT
          )''');
          await db.execute('''
          CREATE TABLE operaciones (
            id TEXT PRIMARY KEY, tipo TEXT, usuario TEXT,
            fecha_creacion TEXT, fecha_cierre TEXT,
            orden TEXT, ceco TEXT, clase_movimiento TEXT,
            centro TEXT, almacen TEXT, texto_cabecera TEXT,
            estado_local TEXT, archivo_nombre TEXT, msg_error TEXT,
            estado_sap TEXT, archivo_sap_nombre TEXT, estado_sap_fecha TEXT,
            doc_sap TEXT, estado_sap_detalle TEXT
          )''');
          await db.execute(
            'CREATE INDEX idx_ops_estado ON operaciones(estado_local)',
          );
          await db.execute('''
          CREATE TABLE posiciones (
            id INTEGER PRIMARY KEY AUTOINCREMENT, operacion_id TEXT,
            linea INTEGER, qr_leido TEXT, material_sap TEXT, descripcion TEXT,
            unidad_lectura TEXT, cantidad_lectura REAL,
            unidad_sap TEXT, cantidad_sap REAL, texto_posicion TEXT,
            origen TEXT
          )''');
          await db.execute(
            'CREATE INDEX idx_pos_op ON posiciones(operacion_id)',
          );
          await _crearCacheControl(db);
        },
        onUpgrade: (db, oldV, newV) async {
          if (oldV < 2) {
            await db.execute('''
            CREATE TABLE IF NOT EXISTS clases_movimiento (
              codigo TEXT PRIMARY KEY, descripcion TEXT
            )''');
            await db.execute('''
            CREATE TABLE IF NOT EXISTS centros_sap (
              codigo TEXT PRIMARY KEY, descripcion TEXT
            )''');
          }
          if (oldV < 3) {
            try {
              await db.execute(
                "ALTER TABLE usuarios ADD COLUMN email TEXT DEFAULT ''",
              );
            } catch (_) {}
          }
          if (oldV < 4) {
            await db.execute(
              "ALTER TABLE operaciones ADD COLUMN estado_sap TEXT DEFAULT ''",
            );
            await db.execute(
              "ALTER TABLE operaciones ADD COLUMN archivo_sap_nombre TEXT DEFAULT ''",
            );
            await db.execute(
              "ALTER TABLE operaciones ADD COLUMN estado_sap_fecha TEXT DEFAULT ''",
            );
          }
          if (oldV < 5) await _crearCacheControl(db);
          if (oldV < 6) {
            await db.delete('posiciones');
            await db.delete('operaciones');
            await db.delete('control_pick_detalles_cache');
            await db.delete('control_picks_cache');
            await db.delete('cache_meta');
          }
          if (oldV < 7) {
            try {
              await db.execute(
                "ALTER TABLE operaciones ADD COLUMN doc_sap TEXT DEFAULT ''",
              );
            } catch (_) {}
            try {
              await db.execute(
                "ALTER TABLE operaciones ADD COLUMN estado_sap_detalle TEXT DEFAULT ''",
              );
            } catch (_) {}
          }
        },
      );
      _instancia = db;
      return db;
    } catch (_) {
      _apertura = null;
      rethrow;
    }
  }

  static Future<void> reemplazarMaestros({
    required List<Map<String, Object?>> usuarios,
    required List<Map<String, Object?>> equivalencias,
    required List<Map<String, Object?>> cecos,
    required List<Map<String, Object?>> almacenes,
    required List<Map<String, Object?>> clasesMovimiento,
    required List<Map<String, Object?>> centrosSap,
    required Map<String, String> parametros,
  }) async {
    final db = await abrir();
    final batch = db.batch();
    batch.delete('usuarios');
    for (final u in usuarios) {
      batch.insert('usuarios', {
        'usuario': u['usuario'],
        'nombre': u['nombre'] ?? '',
        'email': u['email'] ?? '',
        'perfil': u['perfil'] ?? 'PICK',
        'pin_hash': u['pin_hash'] ?? '',
        'salt': u['salt'] ?? '',
        'activo': 1,
      });
    }
    batch.delete('equivalencias');
    for (final e in equivalencias) {
      batch.insert('equivalencias', {
        'codigo_qr': e['codigo_qr']?.toString() ?? '',
        'material_sap': e['material_sap']?.toString() ?? '',
        'descripcion': e['descripcion']?.toString() ?? '',
        'unidad_sap': e['unidad_sap']?.toString() ?? '',
        'unidad_lectura': e['unidad_lectura']?.toString() ?? '',
        'factor_conversion':
            double.tryParse(e['factor_conversion'].toString()) ?? 1,
      });
    }
    batch.delete('cecos');
    for (final c in cecos) {
      batch.insert('cecos', {
        'ceco': c['ceco']?.toString() ?? '',
        'descripcion': c['descripcion']?.toString() ?? '',
      });
    }
    batch.delete('almacenes');
    for (final a in almacenes) {
      batch.insert('almacenes', {
        'codigo': a['codigo']?.toString() ?? '',
        'centro': a['centro']?.toString() ?? '',
        'descripcion': a['descripcion']?.toString() ?? '',
      });
    }
    batch.delete('clases_movimiento');
    for (final cm in clasesMovimiento) {
      batch.insert('clases_movimiento', {
        'codigo': cm['codigo']?.toString() ?? cm['clase']?.toString() ?? '',
        'descripcion': cm['descripcion']?.toString() ?? '',
      });
    }
    batch.delete('centros_sap');
    for (final c in centrosSap) {
      batch.insert('centros_sap', {
        'codigo': c['codigo']?.toString() ?? c['centro']?.toString() ?? '',
        'descripcion': c['descripcion']?.toString() ?? '',
      });
    }
    batch.delete('parametros');
    parametros.forEach(
      (k, v) => batch.insert('parametros', {'clave': k, 'valor': v}),
    );
    await batch.commit(noResult: true);
  }

  static Future<Map<String, String>> parametros() async {
    final db = await abrir();
    final filas = await db.query('parametros');
    return {
      for (final f in filas) f['clave'] as String: (f['valor'] ?? '') as String,
    };
  }

  static Future<Map<String, Object?>?> usuario(String nombre) async {
    final db = await abrir();
    final filas = await db.query(
      'usuarios',
      where: 'usuario = ? AND activo = 1',
      whereArgs: [nombre],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  static Future<Map<String, Object?>?> equivalencia(String codigoQr) async {
    final db = await abrir();
    final filas = await db.query(
      'equivalencias',
      where: 'codigo_qr = ?',
      whereArgs: [codigoQr.trim()],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  static Future<List<Map<String, Object?>>> almacenes() async {
    final db = await abrir();
    return db.query('almacenes', orderBy: 'codigo');
  }

  static Future<List<Map<String, Object?>>> cecos() async {
    final db = await abrir();
    return db.query('cecos', orderBy: 'ceco');
  }

  static Future<List<Map<String, Object?>>> clasesMovimiento() async {
    final db = await abrir();
    try {
      return await db.query('clases_movimiento', orderBy: 'codigo');
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, Object?>>> centros() async {
    final db = await abrir();
    try {
      return await db.query('centros_sap', orderBy: 'codigo');
    } catch (_) {
      return [];
    }
  }

  static Future<String> nuevaOperacion({
    String? id,
    required String orden,
    required String ceco,
    required String almacen,
    required String textoCabecera,
    required Map<String, String> params,
  }) async {
    final db = await abrir();
    final operacionId = id ?? nuevoIdOperacion();
    final ordenFinal = orden.trim();
    if (ordenFinal.isEmpty) {
      throw ArgumentError('La operación requiere un número reservado');
    }
    await db.insert('operaciones', {
      'id': operacionId,
      'tipo': 'PICK',
      'usuario': usuarioActual ?? '',
      'fecha_creacion': _ahora(),
      'fecha_cierre': '',
      'orden': ordenFinal,
      'ceco': ceco,
      'clase_movimiento': params['claseMovimiento'] ?? '201',
      'centro': params['centro'] ?? '1001',
      'almacen': almacen,
      'texto_cabecera': textoCabecera.trim(),
      'estado_local': 'ABIERTA',
      'archivo_nombre': '',
      'msg_error': '',
    });
    return operacionId;
  }

  static String nuevoIdOperacion() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      DateTime.now().millisecondsSinceEpoch.toRadixString(16).substring(0, 4);

  static String? usuarioActual;

  static Future<void> actualizarEncabezado(
    String opId, {
    required String orden,
    required String ceco,
    required String almacen,
    required String claseMovimiento,
    required String centro,
    required String textoCabecera,
  }) async {
    final db = await abrir();
    await db.update(
      'operaciones',
      {
        'orden': orden.trim(),
        'ceco': ceco,
        'almacen': almacen,
        'clase_movimiento': claseMovimiento,
        'centro': centro,
        'texto_cabecera': textoCabecera.trim(),
      },
      where: 'id = ? AND estado_local = ?',
      whereArgs: [opId, 'ABIERTA'],
    );
  }

  static Future<int> agregarPosicion({
    required String operacionId,
    required String? qrLeido,
    required String materialSap,
    required String descripcion,
    required String unidadLectura,
    required double cantidadLectura,
    required String unidadSap,
    required double cantidadSap,
    required String textoPosicion,
    required String origen,
  }) async {
    if (origen == 'MANUAL' && !RegExp(r'^[0-9]{7}$').hasMatch(materialSap)) {
      throw ArgumentError.value(
        materialSap,
        'materialSap',
        'Debe contener exactamente 7 dígitos ASCII para origen MANUAL',
      );
    }
    final db = await abrir();
    final maxFila = await db.rawQuery(
      'SELECT COALESCE(MAX(linea), 0) AS m FROM posiciones WHERE operacion_id = ?',
      [operacionId],
    );
    final linea = ((maxFila.first['m'] as num?) ?? 0).toInt() + 1;
    return db.insert('posiciones', {
      'operacion_id': operacionId,
      'linea': linea,
      'qr_leido': qrLeido,
      'material_sap': materialSap,
      'descripcion': descripcion,
      'unidad_lectura': unidadLectura,
      'cantidad_lectura': cantidadLectura,
      'unidad_sap': unidadSap,
      'cantidad_sap': cantidadSap,
      'texto_posicion': textoPosicion,
      'origen': origen,
    });
  }

  static Future<List<Map<String, Object?>>> posiciones(String opId) async {
    final db = await abrir();
    return db.query(
      'posiciones',
      where: 'operacion_id = ?',
      whereArgs: [opId],
      orderBy: 'linea',
    );
  }

  static Future<Map<String, Object?>?> operacion(String opId) async {
    final db = await abrir();
    final filas = await db.query(
      'operaciones',
      where: 'id = ?',
      whereArgs: [opId],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  static Future<List<Map<String, Object?>>> operaciones({
    String? estados,
  }) async {
    final db = await abrir();
    if (estados == null || estados.isEmpty) {
      return db.query(
        'operaciones',
        orderBy: 'fecha_creacion DESC',
        limit: 200,
      );
    }
    final lista = estados.split(',');
    return db.query(
      'operaciones',
      where: 'estado_local IN (${List.filled(lista.length, '?').join(',')})',
      whereArgs: lista,
      orderBy: 'fecha_creacion DESC',
      limit: 200,
    );
  }

  static Future<void> actualizarCantidadPosicion(
    int idPos,
    double cantidad, {
    String? textoPosicion,
  }) async {
    final db = await abrir();
    final pos = (await db.query(
      'posiciones',
      where: 'id = ?',
      whereArgs: [idPos],
      limit: 1,
    )).first;
    final factor = (pos['cantidad_lectura'] as num?) ?? 1;
    final nuevaSap = factor == 0
        ? cantidad
        : cantidad * (((pos['cantidad_sap'] as num?) ?? 0) / factor);
    final valores = <String, Object?>{
      'cantidad_lectura': cantidad,
      'cantidad_sap': nuevaSap,
    };
    if (textoPosicion != null) valores['texto_posicion'] = textoPosicion;
    await db.update('posiciones', valores, where: 'id = ?', whereArgs: [idPos]);
  }

  static Future<void> eliminarPosicion(int idPos) async {
    final db = await abrir();
    await db.delete('posiciones', where: 'id = ?', whereArgs: [idPos]);
  }

  static Future<void> cerrarOperacion(String opId) async {
    final db = await abrir();
    await db.update(
      'operaciones',
      {'estado_local': 'PENDIENTE', 'fecha_cierre': _ahora()},
      where: 'id = ?',
      whereArgs: [opId],
    );
  }

  static Future<void> marcarEstadoOp(
    String opId,
    String estado, {
    String? archivo,
    String? error,
    String? estadoSap,
    String? archivoSap,
    String? fechaSap,
    String? orden,
    String? docSap,
    String? estadoSapDetalle,
  }) async {
    final db = await abrir();
    await db.update(
      'operaciones',
      {
        'estado_local': estado,
        'archivo_nombre': archivo ?? '',
        'msg_error': error ?? '',
        if (estadoSap != null) 'estado_sap': estadoSap,
        if (archivoSap != null) 'archivo_sap_nombre': archivoSap,
        if (fechaSap != null) 'estado_sap_fecha': fechaSap,
        if (orden != null) 'orden': orden,
        if (docSap != null) 'doc_sap': docSap,
        if (estadoSapDetalle != null) 'estado_sap_detalle': estadoSapDetalle,
      },
      where: 'id = ?',
      whereArgs: [opId],
    );
  }

  static Future<void> eliminarOperacionAbierta(String opId) async {
    final db = await abrir();
    await db.delete('posiciones', where: 'operacion_id = ?', whereArgs: [opId]);
    await db.delete(
      'operaciones',
      where: 'id = ? AND estado_local = ?',
      whereArgs: [opId, 'ABIERTA'],
    );
  }

  static Future<void> eliminarOperacionPendiente(String opId) async {
    final db = await abrir();
    await db.delete('posiciones', where: 'operacion_id = ?', whereArgs: [opId]);
    await db.delete(
      'operaciones',
      where: 'id = ? AND estado_local = ?',
      whereArgs: [opId, 'PENDIENTE'],
    );
  }

  static Future<void> eliminarOperacionesPendientes(List<String> opIds) async {
    if (opIds.isEmpty) return;
    final db = await abrir();
    final marcas = List.filled(opIds.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.delete(
        'posiciones',
        where: 'operacion_id IN ($marcas)',
        whereArgs: opIds,
      );
      await txn.delete(
        'operaciones',
        where: 'id IN ($marcas) AND estado_local = ?',
        whereArgs: [...opIds, 'PENDIENTE'],
      );
    });
  }

  static Future<void> insertarOperacionesServidor(List<dynamic> ops) async {
    final db = await abrir();
    for (final op in ops) {
      final o = Map<String, Object?>.from(op as Map);
      final id = o['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final existente = await db.query(
        'operaciones',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existente.isNotEmpty) {
        await db.update(
          'operaciones',
          {
            'usuario': o['usuario']?.toString() ?? '',
            'estado_local': o['estado']?.toString() ?? 'PENDIENTE',
            'archivo_nombre': o['archivo_nombre']?.toString() ?? '',
            'msg_error': o['msg_error']?.toString() ?? '',
            'estado_sap': o['estado_sap']?.toString() ?? '',
            'archivo_sap_nombre': o['archivo_sap_nombre']?.toString() ?? '',
            'estado_sap_fecha': o['estado_sap_fecha']?.toString() ?? '',
            'doc_sap': o['doc_sap']?.toString() ?? '',
            'estado_sap_detalle': o['estado_sap_detalle']?.toString() ?? '',
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        await db.insert('operaciones', {
          'id': id,
          'tipo': o['tipo']?.toString() ?? 'PICK',
          'usuario': o['usuario']?.toString() ?? '',
          'fecha_creacion': o['fecha_creacion']?.toString() ?? '',
          'fecha_cierre': o['fecha_cierre']?.toString() ?? '',
          'orden': o['orden']?.toString() ?? '',
          'ceco': o['ceco']?.toString() ?? '',
          'clase_movimiento': o['clase_movimiento']?.toString() ?? '',
          'centro': o['centro']?.toString() ?? '',
          'almacen': o['almacen']?.toString() ?? '',
          'texto_cabecera': o['texto_cabecera']?.toString() ?? '',
          'estado_local': o['estado']?.toString() ?? 'PENDIENTE',
          'archivo_nombre': o['archivo_nombre']?.toString() ?? '',
          'msg_error': o['msg_error']?.toString() ?? '',
          'estado_sap': o['estado_sap']?.toString() ?? '',
          'archivo_sap_nombre': o['archivo_sap_nombre']?.toString() ?? '',
          'estado_sap_fecha': o['estado_sap_fecha']?.toString() ?? '',
          'doc_sap': o['doc_sap']?.toString() ?? '',
          'estado_sap_detalle': o['estado_sap_detalle']?.toString() ?? '',
        });
      }
    }
  }

  static Future<bool> hayOperacionesParaEnviar() async {
    final db = await abrir();
    final r = await db.rawQuery(
      "SELECT COUNT(*) AS n FROM operaciones WHERE estado_local IN ('PENDIENTE','ERROR')",
    );
    return ((r.first['n'] as num?) ?? 0).toInt() > 0;
  }

  static Future<void> guardarCacheControl(
    List<dynamic> operaciones, {
    required int dias,
  }) async {
    final db = await abrir();
    final ahora = _ahora();
    await db.transaction((txn) async {
      await txn.delete('control_picks_cache');
      for (final item in operaciones) {
        final op = Map<String, Object?>.from(item as Map);
        final id = op['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await txn.insert('control_picks_cache', {
          'id': id,
          'datos_json': jsonEncode(op),
          'fecha_cierre': op['fecha_cierre']?.toString() ?? '',
          'actualizado': ahora,
        });
      }
      await txn.insert('cache_meta', {
        'clave': 'control_picks_actualizado',
        'valor': ahora,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('cache_meta', {
        'clave': 'control_picks_dias',
        'valor': dias.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      if (operaciones.isEmpty) {
        await txn.delete('control_pick_detalles_cache');
      } else {
        final ids = operaciones
            .map((item) => (item as Map)['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        final marcas = List.filled(ids.length, '?').join(',');
        await txn.delete(
          'control_pick_detalles_cache',
          where: 'operacion_id NOT IN ($marcas)',
          whereArgs: ids,
        );
      }
    });
  }

  static Future<List<dynamic>> leerCacheControl() async {
    final db = await abrir();
    final filas = await db.query(
      'control_picks_cache',
      orderBy: 'fecha_cierre DESC',
    );
    return filas
        .map((fila) => jsonDecode(fila['datos_json'] as String))
        .toList();
  }

  static Future<Map<String, String>> infoCacheControl() async {
    final db = await abrir();
    final filas = await db.query('cache_meta');
    return {
      for (final fila in filas)
        fila['clave'] as String: fila['valor']?.toString() ?? '',
    };
  }

  static Future<void> guardarDetalleControl(
    String operacionId,
    Map<String, dynamic> detalle,
  ) async {
    final db = await abrir();
    await db.insert('control_pick_detalles_cache', {
      'operacion_id': operacionId,
      'datos_json': jsonEncode(detalle),
      'actualizado': _ahora(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> leerDetalleControl(
    String operacionId,
  ) async {
    final db = await abrir();
    final filas = await db.query(
      'control_pick_detalles_cache',
      where: 'operacion_id = ?',
      whereArgs: [operacionId],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return Map<String, dynamic>.from(
      jsonDecode(filas.first['datos_json'] as String) as Map,
    );
  }

  static Future<void> limpiarHistorialConfirmado() async {
    final db = await abrir();
    final params = await parametros();
    final dias = int.tryParse(params['diasHistorialApp'] ?? '') ?? 30;
    final limite = DateTime.now().subtract(Duration(days: dias.clamp(1, 3650)));
    String dos(int n) => n.toString().padLeft(2, '0');
    final fecha =
        '${limite.year}-${dos(limite.month)}-${dos(limite.day)} ${dos(limite.hour)}:${dos(limite.minute)}:${dos(limite.second)}';
    await db.transaction((txn) async {
      final vencidas = await txn.query(
        'operaciones',
        columns: ['id'],
        where: "estado_local = 'PROCESADO' AND estado_sap = 'OK' AND fecha_cierre < ?",
        whereArgs: [fecha],
      );
      if (vencidas.isEmpty) return;
      final ids = vencidas.map((o) => o['id']).toList();
      final marcas = List.filled(ids.length, '?').join(',');
      await txn.delete(
        'posiciones',
        where: 'operacion_id IN ($marcas)',
        whereArgs: ids,
      );
      await txn.delete('operaciones', where: 'id IN ($marcas)', whereArgs: ids);
    });
  }

  static String _ahora() {
    final d = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${dos(d.month)}-${dos(d.day)} ${dos(d.hour)}:${dos(d.minute)}:${dos(d.second)}';
  }

  static Future<void> _crearCacheControl(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS control_picks_cache (
        id TEXT PRIMARY KEY, datos_json TEXT NOT NULL,
        fecha_cierre TEXT, actualizado TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS control_pick_detalles_cache (
        operacion_id TEXT PRIMARY KEY, datos_json TEXT NOT NULL,
        actualizado TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_meta (
        clave TEXT PRIMARY KEY, valor TEXT NOT NULL
      )''');
  }
}
