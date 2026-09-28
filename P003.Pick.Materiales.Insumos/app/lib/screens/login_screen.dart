import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../core/password_hasher.dart';
import '../services/sync.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuario = TextEditingController();
  final _pin = TextEditingController();
  bool _enviando = false;
  String? _error;

  Future<void> _ingresar() async {
    final usr = _usuario.text.trim();
    final pin = _pin.text.trim();
    if (usr.isEmpty || pin.isEmpty) {
      setState(() => _error = 'Ingrese usuario y PIN');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });

    // 1. Intentar login online primero para obtener token vigente y actualizar sesión
    try {
      final resp = await Api.post('/api/login', {'usuario': usr, 'pin': pin});
      final tokenSesion = resp['token'] as String?;
      await _terminarLogin(
        resp['usuario']?.toString() ?? usr,
        resp['nombre']?.toString() ?? usr,
        resp['perfil']?.toString() ?? 'PICK',
        tokenSesion,
      );
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _enviando = false;
      });
      return;
    } catch (_) {
      // Servidor no alcanzable: intentar validación offline
    }

    // 2. Modo offline: validar contra base de datos local
    Map<String, Object?>? usuarioLocal;
    try {
      usuarioLocal = await Db.usuario(usr);
    } catch (_) {}

    if (usuarioLocal != null) {
      final hashLocal = PasswordHasher.hash(
        pin,
        (usuarioLocal['salt'] ?? '') as String,
      );
      if (hashLocal == usuarioLocal['pin_hash']) {
        await _terminarLogin(
          usr,
          (usuarioLocal['nombre'] ?? usr) as String,
          (usuarioLocal['perfil'] ?? 'PICK') as String,
          null,
        );
        return;
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'PIN incorrecto';
          _enviando = false;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _error = 'Sin conexión con el servidor y usuario no registrado localmente';
      _enviando = false;
    });
  }

  Future<void> _terminarLogin(
    String usr,
    String nombre,
    String perfil,
    String? token,
  ) async {
    await Config.guardarSesion(
      token: token ?? '',
      usr: usr,
      nombre: nombre,
      per: perfil,
    );
    Db.usuarioActual = usr;
    try {
      await Sync.bajarMaestros();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo.png', height: 110),
                  const SizedBox(height: 10),
                  Text(
                    'PICKING DE MATERIALES',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 34),
                  TextField(
                    controller: _usuario,
                    enabled: !_enviando,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pin,
                    enabled: !_enviando,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    onSubmitted: (_) => _ingresar(),
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      prefixIcon: Icon(Icons.lock_outline),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.rojoOscuro,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _enviando ? null : _ingresar,
                      icon: _enviando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.blanco,
                              ),
                            )
                          : const Icon(Icons.login),
                      label: Text(_enviando ? 'Ingresando...' : 'INGRESAR'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Versión ${Config.versionCompleta}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: .5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
