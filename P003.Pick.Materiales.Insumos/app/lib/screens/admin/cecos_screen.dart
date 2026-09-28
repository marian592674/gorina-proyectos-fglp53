import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/theme.dart';

class CecosScreen extends StatefulWidget {
  const CecosScreen({super.key});
  @override
  State<CecosScreen> createState() => _CecosScreenState();
}

class _CecosScreenState extends State<CecosScreen> {
  List<dynamic> _lista = [];
  bool _cargando = true;
  String _error = '';
  String _filtro = '';

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
      final r = await Api.get('/api/cecos', token: Config.token);
      _lista = r is List ? r : [];
    } on ApiException catch (e) {
      _error = e.mensaje;
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _editarCeco({Map? existente}) async {
    final controller =
        TextEditingController(text: (existente?['ceco'] ?? '').toString());
    final descController =
        TextEditingController(text: (existente?['descripcion'] ?? '').toString());
    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existente == null ? 'NUEVO CENTRO DE COSTO' : 'EDITAR CECO'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: controller,
            enabled: existente == null,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Código CECO *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Descripción *'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('GUARDAR')),
        ],
      ),
    );
    if (guardado != true) return;
    try {
      if (existente == null) {
        await Api.post('/api/cecos',
            {'ceco': controller.text.trim(), 'descripcion': descController.text.trim(), 'activo': true},
            token: Config.token);
      } else {
        await Api.put('/api/cecos/${Uri.encodeComponent(existente['ceco'].toString())}',
            {'descripcion': descController.text.trim(), 'activo': true},
            token: Config.token);
      }
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.rojoOscuro));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CENTROS DE COSTO')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.rojo,
        foregroundColor: AppColors.blanco,
        onPressed: () => _editarCeco(),
        icon: const Icon(Icons.add),
        label: const Text('NUEVO'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _filtro = v),
            decoration:
                const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Expanded(child: _contenido()),
      ]),
    );
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return ListView(children: [
        Padding(padding: const EdgeInsets.all(20),
            child: Text('$_error\n\nVerifique conexión.', textAlign: TextAlign.center)),
      ]);
    }
    final listaFiltrada = _lista.where((c) {
      if (_filtro.isEmpty) return true;
      return '${c['ceco']} ${c['descripcion']}'
          .toLowerCase()
          .contains(_filtro.toLowerCase());
    }).toList();
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: listaFiltrada.length,
        itemBuilder: (_, i) {
          final c = listaFiltrada[i] as Map;
          return Card(
            child: ListTile(
              title: Text(c['ceco'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(c['descripcion'].toString()),
              onTap: () => _editarCeco(existente: c),
            ),
          );
        },
      ),
    );
  }
}
