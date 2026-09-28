import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import 'equivalencia_edit_screen.dart';

class EquivalenciasScreen extends StatefulWidget {
  const EquivalenciasScreen({super.key});
  @override
  State<EquivalenciasScreen> createState() => _EquivalenciasScreenState();
}

class _EquivalenciasScreenState extends State<EquivalenciasScreen> {
  final _busqueda = TextEditingController();
  List<dynamic> _lista = [];
  bool _cargando = true;
  String _error = '';
  String _filtroActivo = '';

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
      final q = _busqueda.text.trim().isEmpty
          ? ''
          : '?busqueda=${Uri.encodeComponent(_busqueda.text.trim())}';
      final r = await Api.get('/api/equivalencias$q', token: Config.token);
      _lista = r is List ? r : [];
    } on ApiException catch (e) {
      _error = e.mensaje;
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EQUIVALENCIAS')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.rojo,
        foregroundColor: AppColors.blanco,
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const EquivalenciaEditScreen()));
          _cargar();
        },
        icon: const Icon(Icons.add),
        label: const Text('NUEVA'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _busqueda,
            onSubmitted: (_) => _cargar(),
            decoration: InputDecoration(
                hintText: 'Buscar QR, material o descripción',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _cargar)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final f in const [
              {'label': 'TODAS', 'val': ''},
              {'label': 'ACTIVAS', 'val': '1'},
              {'label': 'INACTIVAS', 'val': '0'}
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(f['label']!),
                  selected: _filtroActivo == f['val'],
                  selectedColor: AppColors.rojo.withValues(alpha: .18),
                  onSelected: (_) => setState(() => _filtroActivo = f['val']!),
                ),
              ),
          ]),
        ),
        Expanded(child: _contenido()),
      ]),
    );
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return ListView(children: [
        Padding(
            padding: const EdgeInsets.all(20),
            child: Text('$_error\n\nVerifique conexión y deslice para reintentar.',
                textAlign: TextAlign.center)),
      ]);
    }
    final filtrada = _filtroActivo.isEmpty
        ? _lista
        : _lista.where((e) => (e as Map)['activo'].toString() == _filtroActivo).toList();
    if (filtrada.isEmpty) {
      return const Center(child: Text('Sin resultados'));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: filtrada.length,
        itemBuilder: (_, i) {
          final e = filtrada[i] as Map;
          final activo = e['activo'].toString() == '1';
          return Card(
            child: ListTile(
              title: Text('${e['codigo_qr']}  →  ${e['material_sap']}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: activo ? AppColors.texto : Colors.grey.shade500)),
              subtitle: Text(
                  '${e['descripcion'] ?? ''}\n${e['unidad_sap']} / ${e['unidad_lectura']} × ${e['factor_conversion']}',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
              trailing: ChipEstado(estado: activo ? 'ACTIVA' : 'INACTIVA'),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => EquivalenciaEditScreen(datos: e)));
                _cargar();
              },
            ),
          );
        },
      ),
    );
  }
}
