import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../services/sync.dart';

class CierrePickScreen extends StatefulWidget {
  final String opId;
  const CierrePickScreen({super.key, required this.opId});
  @override
  State<CierrePickScreen> createState() => _CierrePickScreenState();
}

class _CierrePickScreenState extends State<CierrePickScreen> {
  Map<String, Object?>? _op;
  List<Map<String, Object?>> _posiciones = [];
  bool _confirmando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _op = await Db.operacion(widget.opId);
    _posiciones = await Db.posiciones(widget.opId);
    if (mounted) setState(() {});
  }

  String _cecoDescripcion() => _op == null
      ? ''
      : (_op!['ceco'] ?? '').toString();

  double get _totalUnidades =>
      _posiciones.fold(0, (t, p) => t + ((p['cantidad_sap'] as num?) ?? 0).toDouble());

  Future<void> _confirmar() async {
    setState(() => _confirmando = true);
    await Db.cerrarOperacion(widget.opId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('PICK cerrado. Enviando al servidor...'),
        backgroundColor: AppColors.verdeOk));

    Sync.sincronizarTodo().then((r) {
      if (!mounted) return;
      final msg = r.ok && r.enviadas > 0
          ? 'Operación enviada y archivo generado'
          : 'Sin conexión ahora: se enviará automáticamente al sincronizar';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    });

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CIERRE DEL PICK')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.summarize, color: AppColors.rojo),
                  SizedBox(width: 8),
                  Text('RESUMEN', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
                const Divider(height: 26),
                _fila('Orden', (_op?['orden'] ?? '').toString()),
                _fila('Centro de costo', _cecoDescripcion()),
                _fila('Almacén', (_op?['almacen'] ?? '').toString()),
                _fila('Posiciones', '${_posiciones.length}'),
                _fila('Total de materiales', _fmt(_totalUnidades)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: AppColors.blanco,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Column(children: _posiciones.map(_filaResumen).toList()),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Al confirmar, la operación queda cerrada y no podrá modificarse.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _confirmando ? null : _confirmar,
            icon: _confirmando
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.blanco))
                : const Icon(Icons.check_circle_outline, size: 26),
            label: const Text('CONFIRMAR CIERRE', style: TextStyle(fontSize: 19)),
          ),
        ],
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(etiqueta, style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
          Text(valor,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      );

  Widget _filaResumen(Map<String, Object?> p) {
    final manual = p['origen'] == 'MANUAL';
    return ListTile(
      dense: true,
      title: Text('${p['material_sap']} | ${_fmt((p['cantidad_sap'] as num?)?.toDouble() ?? 0)} ${p['unidad_sap']}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: manual
          ? const Text('Sin equivalencia', style: TextStyle(color: AppColors.rojoOscuro, fontSize: 12))
          : Text(p['texto_posicion'].toString(),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
    );
  }

  static String _fmt(double d) =>
      d == d.truncateToDouble() ? d.toInt().toString() : d.toStringAsFixed(3);
}
