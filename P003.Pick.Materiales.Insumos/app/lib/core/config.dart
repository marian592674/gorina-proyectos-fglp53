import 'package:shared_preferences/shared_preferences.dart';

class Config {
  static const versionApp = '1.5.1';
  static const buildApp = 8;
  static const versionCompleta = 'v$versionApp';

  static const servidorPorDefecto = 'http://192.168.0.126:5000';

  static String? _token;
  static String? usuario;
  static String? nombreUsuario;
  static String? perfil;

  static String get servidorUrl => servidorPorDefecto;
  static bool get haySesion => _token != null && usuario != null;
  static bool get esAdmin => perfil == 'ADMIN';

  static Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    usuario = prefs.getString('usuario');
    nombreUsuario = prefs.getString('nombreUsuario');
    perfil = prefs.getString('perfil');
  }

  static Future<void> guardarServidor(String url) async {
    // IP fija inmutable en producción
  }

  static Future<void> guardarSesion({
    required String token,
    required String usr,
    required String nombre,
    required String per,
  }) async {
    _token = token;
    usuario = usr;
    nombreUsuario = nombre;
    perfil = per;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('usuario', usr);
    await prefs.setString('nombreUsuario', nombre);
    await prefs.setString('perfil', per);
  }

  static String? get token => _token;

  static Future<void> cerrarSesion() async {
    _token = null;
    usuario = null;
    nombreUsuario = null;
    perfil = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('usuario');
    await prefs.remove('nombreUsuario');
    await prefs.remove('perfil');
  }
}
