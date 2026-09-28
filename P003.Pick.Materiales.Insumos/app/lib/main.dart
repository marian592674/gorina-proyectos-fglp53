import 'package:flutter/material.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/db.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GorinaPickApp());
}

class GorinaPickApp extends StatelessWidget {
  const GorinaPickApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gorina Pick',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.get(),
      home: const Arranque(),
    );
  }
}

class Arranque extends StatefulWidget {
  const Arranque({super.key});
  @override
  State<Arranque> createState() => _ArranqueState();
}

class _ArranqueState extends State<Arranque> {
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    await Config.cargar();
    Db.usuarioActual = Config.usuario;
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Config.haySesion ? const HomeScreen() : const LoginScreen();
  }
}
