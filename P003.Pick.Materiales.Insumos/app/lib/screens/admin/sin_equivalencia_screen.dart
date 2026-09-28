import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../admin/equivalencia_edit_screen.dart';

class SinEquivalenciaScreen extends StatefulWidget {
  const SinEquivalenciaScreen({super.key});
  @override
  State<SinEquivalenciaScreen> createState() => _SinEquivalenciaScreenState();
}

class _SinEquivalenciaScreenState extends State<SinEquivalenciaScreen> {
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
      final r = await Api.get('/api/sinequivalencia', token: Config.token);
      _lista = r is List ? r : [];
    } on ApiException catch (e) {
      _error = e.mensaje;
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SIN EQUIVALENCIA')),
      body: _contenido(),
    );
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return ListView(children: [
        Padding(padding: const EdgeInsets.all(20), child: Text('$_error\n\nVerifique conexión.', textAlign: TextAlign.center)),
      ]);
    }
    if (_lista.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 180),
        Center(child: Text('No hay casos pendientes de revisión')),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _lista.length,
        itemBuilder: (_, i) {
          final r = _lista[i] as Map;
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.qr_code_2, color: AppColors.rojo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r['qr_leido'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  ChipEstado(estado: '${r['veces']} usos'),
                ]),
                const SizedBox(height: 6),
                Text('Material SAP usado: ${r['material_usado'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Último: ${r['ultima_fecha'] ?? '-'} por ${r['ultimo_usuario'] ?? '-'}',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => EquivalenciaEditScreen(datos: {
                                'codigo_qr': r['qr_leido'],
                                'material_sap': (r['material_usado'] ?? '').toString(),
                              })));
                    },
                    icon: const Icon(Icons.add_link, size: 18),
                    label: const Text('CREAR EQUIVALENCIA'),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}
