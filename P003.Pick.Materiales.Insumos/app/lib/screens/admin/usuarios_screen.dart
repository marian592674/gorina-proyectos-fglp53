import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/theme.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});
  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  List<dynamic> _lista = [];
  bool _cargando = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r = await Api.get('/api/usuarios', token: Config.token);
      _lista = r is List ? r : [];
    } on ApiException catch (e) {
      _error = e.mensaje;
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _formUsuario({Map? existente}) async {
    final nuevo = existente == null;
    final usuarioCtrl = TextEditingController(
      text: (existente?['usuario'] ?? '').toString(),
    );
    final nombreCtrl = TextEditingController(
      text: (existente?['nombre'] ?? '').toString(),
    );
    final emailCtrl = TextEditingController(
      text: (existente?['email'] ?? '').toString(),
    );
    final pinCtrl = TextEditingController();
    String perfil = (existente?['perfil'] ?? 'PICK').toString();
    bool activo = existente == null
        ? true
        : existente['activo'].toString() == '1';
    String? emailError;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: Text(nuevo ? 'NUEVO USUARIO' : 'EDITAR USUARIO'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usuarioCtrl,
                enabled: nuevo,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Usuario *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nombreCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) {
                  if (emailError != null) setD(() => emailError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Email (opcional)',
                  hintText: 'usuario@ejemplo.com',
                  errorText: emailError,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: nuevo ? 'PIN *' : 'Nuevo PIN (opcional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: perfil,
                items: const [
                  DropdownMenuItem(
                    value: 'PICK',
                    child: Text('PICK (operario)'),
                  ),
                  DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN')),
                ],
                onChanged: (v) => setD(() => perfil = v ?? 'PICK'),
                decoration: const InputDecoration(labelText: 'Perfil'),
              ),
              if (!nuevo)
                SwitchListTile(
                  value: activo,
                  onChanged: (v) => setD(() => activo = v),
                  title: const Text('Activo'),
                  activeThumbColor: AppColors.rojo,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final email = emailCtrl.text.trim();
                if (email.isNotEmpty && !email.contains('@')) {
                  setD(() => emailError = 'Email inválido');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('GUARDAR'),
            ),
          ],
        ),
      ),
    );
    if (guardado != true) return;

    final emailVal = emailCtrl.text.trim();
    try {
      if (nuevo) {
        await Api.post('/api/usuarios', {
          'usuario': usuarioCtrl.text.trim(),
          'nombre': nombreCtrl.text.trim(),
          'email': emailVal,
          'pin': pinCtrl.text.trim(),
          'perfil': perfil,
        }, token: Config.token);
      } else {
        await Api.put(
          '/api/usuarios/${Uri.encodeComponent(usuarioCtrl.text.trim())}',
          {
            'nombre': nombreCtrl.text.trim(),
            'email': emailVal,
            'pin': pinCtrl.text.trim().isEmpty ? null : pinCtrl.text.trim(),
            'perfil': perfil,
            'activo': activo,
          },
          token: Config.token,
        );
      }
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.mensaje),
            backgroundColor: AppColors.rojoOscuro,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('USUARIOS')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.rojo,
        foregroundColor: AppColors.blanco,
        onPressed: () => _formUsuario(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('NUEVO'),
      ),
      body: _contenido(),
    );
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              '$_error\n\nVerifique conexión.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _lista.length,
        itemBuilder: (_, i) {
          final u = _lista[i] as Map;
          final activo = u['activo'].toString() == '1';
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    (u['perfil'] == 'ADMIN'
                            ? AppColors.rojo
                            : AppColors.grisMedio)
                        .withValues(alpha: .15),
                child: Icon(
                  u['perfil'] == 'ADMIN'
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                  color: u['perfil'] == 'ADMIN'
                      ? AppColors.rojo
                      : AppColors.grisMedio,
                ),
              ),
              title: Text(
                '${u['usuario']} — ${u['nombre']}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: activo ? AppColors.texto : Colors.grey.shade500,
                ),
              ),
              subtitle: Text(
                'Perfil ${u['perfil']} ${(u['email'] ?? '').toString().isNotEmpty ? '· ${u['email']}' : ''} · alta ${u['fecha_alta']}',
                style: const TextStyle(fontSize: 12.5),
              ),
              trailing: ChipEstado(estado: activo ? 'ACTIVO' : 'INACTIVO'),
              onTap: () => _formUsuario(existente: u),
            ),
          );
        },
      ),
    );
  }
}
