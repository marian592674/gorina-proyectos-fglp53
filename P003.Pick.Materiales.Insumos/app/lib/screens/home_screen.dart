import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../services/sync.dart';
import 'admin/cecos_screen.dart';
import 'admin/control_picks_screen.dart';
import 'admin/equivalencias_screen.dart';
import 'admin/importar_catalogos_screen.dart';
import 'admin/sin_equivalencia_screen.dart';
import 'admin/usuarios_screen.dart';
import 'mis_picks_screen.dart';
import 'login_screen.dart';
import 'nuevo_pick_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _sincronizando = false;
  int _pendientes = 0;

  @override
  void initState() {
    super.initState();
    _refrescar();
    Sync.sincronizarTodo().then((_) => _refrescar());
  }

  Future<void> _refrescar() async {
    try {
      final hay = await Db.hayOperacionesParaEnviar();
      if (!mounted) return;
      setState(() => _pendientes = hay ? _pendientes : _pendientes);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _sincronizarManual() async {
    if (_sincronizando) return;
    setState(() => _sincronizando = true);
    final r = await Sync.sincronizarTodo();
    await _refrescar();
    if (!mounted) return;
    setState(() => _sincronizando = false);
    final msg = r.ok
        ? (r.enviadas > 0
              ? 'Sincronizado: ${r.enviadas} operación(es) enviada(s)'
              : 'Sincronizado con el servidor')
        : 'Problemas de sincronización: ${r.errores.take(2).join(' | ')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: r.ok ? AppColors.verdeOk : AppColors.rojoOscuro,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esAdmin = Config.esAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Config.nombreUsuario ?? '',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              'Perfil ${Config.perfil ?? ''}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _sincronizando ? null : _sincronizarManual,
            icon: _sincronizando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.blanco,
                    ),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar',
          ),
          IconButton(
            onPressed: () async {
              await Config.cerrarSesion();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Salir',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _sincronizarManual,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Image.asset('assets/logo.png', height: 70),
            const SizedBox(height: 18),
            _BotonInicio(
              icono: Icons.qr_code_scanner,
              titulo: 'NUEVO PICK',
              subtitulo: 'Escanear materiales para consumo',
              color: AppColors.rojo,
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NuevoPickScreen()),
                );
                _refrescar();
              },
              destacado: true,
            ),
            const SizedBox(height: 12),
            _BotonInicio(
              icono: Icons.receipt_long,
              titulo: 'MIS PICKS',
              subtitulo: 'Operaciones cargadas en este equipo',
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MisPicksScreen()),
                );
                _refrescar();
              },
            ),
            if (esAdmin) ...[
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'ADMINISTRACIÓN',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    letterSpacing: 1,
                  ),
                ),
              ),
              _BotonInicio(
                icono: iconsControl(),
                titulo: 'CONTROL DE PICKS',
                subtitulo: 'Estado y archivos generados',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ControlPicksScreen()),
                ),
              ),
              const SizedBox(height: 10),
              _BotonInicio(
                icono: Icons.swap_horiz,
                titulo: 'EQUIVALENCIAS',
                subtitulo: 'Códigos QR → Material SAP',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EquivalenciasScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _BotonInicio(
                icono: Icons.help_outline,
                titulo: 'SIN EQUIVALENCIA',
                subtitulo: 'QR utilizados sin equivalencia',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SinEquivalenciaScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _BotonInicio(
                icono: Icons.account_tree_outlined,
                titulo: 'CENTROS DE COSTO',
                subtitulo: 'Maestro de CECOs',
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const CecosScreen())),
              ),
              const SizedBox(height: 10),
              _BotonInicio(
                icono: Icons.manage_accounts_outlined,
                titulo: 'USUARIOS',
                subtitulo: 'Altas, perfiles y PINs',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UsuariosScreen()),
                ),
              ),
              const SizedBox(height: 10),
              _BotonInicio(
                icono: Icons.upload_file_outlined,
                titulo: 'IMPORTAR CATÁLOGOS',
                subtitulo: 'Validar e importar maestros desde Excel',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ImportarCatalogosScreen(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Gorina Pick ${Config.versionCompleta}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData iconsControl() => Icons.fact_check_outlined;
}

class _BotonInicio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;
  final Color? color;
  final bool destacado;

  const _BotonInicio({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    this.color,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.texto;
    return Card(
      elevation: destacado ? 3 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: destacado ? 18 : 14,
          ),
          child: Row(
            children: [
              Icon(icono, size: destacado ? 40 : 30, color: c),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: destacado ? 19 : 16,
                        fontWeight: FontWeight.w800,
                        color: c,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
