import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  final String mensaje;
  final int? codigo;
  ApiException(this.mensaje, [this.codigo]);
  @override
  String toString() => mensaje;
}

class Api {
  static String get _base {
    var url = Config.servidorUrl;
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  static Map<String, String> _headers({String? token}) {
    final h = {'Content-Type': 'application/json; charset=utf-8'};
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  static Future<dynamic> _procesar(http.Response r) async {
    dynamic datos;
    try {
      datos = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      datos = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return datos;
    final msg = (datos is Map && datos['error'] != null)
        ? datos['error'].toString()
        : 'Error del servidor (${r.statusCode})';
    throw ApiException(msg, r.statusCode);
  }

  static Future<dynamic> post(
    String ruta,
    Map<String, dynamic> cuerpo, {
    String? token,
  }) async {
    try {
      final r = await http
          .post(
            Uri.parse('$_base$ruta'),
            headers: _headers(token: token),
            body: jsonEncode(cuerpo),
          )
          .timeout(const Duration(seconds: 20));
      return await _procesar(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sin conexión con el servidor', null);
    }
  }

  static Future<dynamic> put(
    String ruta,
    Map<String, dynamic> cuerpo, {
    String? token,
  }) async {
    try {
      final r = await http
          .put(
            Uri.parse('$_base$ruta'),
            headers: _headers(token: token),
            body: jsonEncode(cuerpo),
          )
          .timeout(const Duration(seconds: 20));
      return await _procesar(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sin conexión con el servidor', null);
    }
  }

  static Future<dynamic> get(String ruta, {String? token}) async {
    try {
      final r = await http
          .get(Uri.parse('$_base$ruta'), headers: _headers(token: token))
          .timeout(const Duration(seconds: 25));
      return await _procesar(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sin conexión con el servidor', null);
    }
  }

  static Future<bool> servidorDisponible() async {
    try {
      final respuesta = await http
          .get(Uri.parse('$_base/api/ping'))
          .timeout(const Duration(seconds: 4));
      return respuesta.statusCode >= 200 && respuesta.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List> getBytes(String ruta, {String? token}) async {
    try {
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final r = await http
          .get(Uri.parse('$_base$ruta'), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
      dynamic datos;
      try {
        datos = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {}
      final msg = (datos is Map && datos['error'] != null)
          ? datos['error'].toString()
          : 'Error del servidor (${r.statusCode})';
      throw ApiException(msg, r.statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sin conexión con el servidor', null);
    }
  }

  static Future<dynamic> subirArchivo(
    String ruta, {
    required Uint8List bytes,
    required String nombre,
    required Map<String, String> campos,
    String? token,
  }) async {
    try {
      final solicitud = http.MultipartRequest('POST', Uri.parse('$_base$ruta'));
      if (token != null) solicitud.headers['Authorization'] = 'Bearer $token';
      solicitud.fields.addAll(campos);
      solicitud.files.add(
        http.MultipartFile.fromBytes('archivo', bytes, filename: nombre),
      );
      final enviada = await solicitud.send().timeout(
        const Duration(seconds: 60),
      );
      final respuesta = await http.Response.fromStream(enviada);
      return await _procesar(respuesta);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Sin conexión con el servidor', null);
    }
  }
}
