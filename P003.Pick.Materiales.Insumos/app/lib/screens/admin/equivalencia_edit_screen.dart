import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/theme.dart';

class EquivalenciaEditScreen extends StatefulWidget {
  final Map? datos;
  const EquivalenciaEditScreen({super.key, this.datos});
  @override
  State<EquivalenciaEditScreen> createState() => _EquivalenciaEditScreenState();
}

class _EquivalenciaEditScreenState extends State<EquivalenciaEditScreen> {
  late TextEditingController _qr;
  late TextEditingController _material;
  late TextEditingController _descripcion;
  late TextEditingController _unidadSap;
  late TextEditingController _unidadLectura;
  late TextEditingController _factor;
  bool _activo = true;
  bool _guardando = false;
  String? _error;

  bool get esNueva => widget.datos == null;

  @override
  void initState() {
    super.initState();
    final d = widget.datos ?? {};
    _qr = TextEditingController(text: (d['codigo_qr'] ?? '').toString());
    _material = TextEditingController(text: (d['material_sap'] ?? '').toString());
    _descripcion = TextEditingController(text: (d['descripcion'] ?? '').toString());
    _unidadSap = TextEditingController(text: (d['unidad_sap'] ?? '').toString());
    _unidadLectura = TextEditingController(text: (d['unidad_lectura'] ?? '').toString());
    _factor = TextEditingController(text: (d['factor_conversion'] ?? 1).toString());
    _activo = (d['activo'] ?? 1).toString() == '1';
  }

  Future<void> _guardar() async {
    if (_qr.text.trim().isEmpty || _material.text.trim().isEmpty) {
      setState(() => _error = 'Código QR y Material SAP son obligatorios');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final cuerpo = {
      'codigoQr': _qr.text.trim(),
      'materialSap': _material.text.trim(),
      'descripcion': _descripcion.text.trim(),
      'unidadSap': _unidadSap.text.trim().toUpperCase(),
      'unidadLectura': _unidadLectura.text.trim().toUpperCase(),
      'factorConversion': double.tryParse(_factor.text.replaceAll(',', '.')) ?? 1,
      'activo': _activo,
    };
    try {
      if (esNueva) {
        await Api.post('/api/equivalencias', cuerpo, token: Config.token);
      } else {
        await Api.put('/api/equivalencias/${widget.datos!['id']}', cuerpo, token: Config.token);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Equivalencia guardada'), backgroundColor: AppColors.verdeOk));
      Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() {
        _error = e.mensaje;
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(esNueva ? 'NUEVA EQUIVALENCIA' : 'EDITAR EQUIVALENCIA')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _qr,
                enabled: esNueva,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                decoration: InputDecoration(
                    labelText: 'Código QR / código leído *',
                    helperText: esNueva ? null : 'El código QR no se puede modificar',
                    prefixIcon: const Icon(Icons.qr_code_2)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _material,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                decoration:
                    const InputDecoration(labelText: 'Material SAP *', prefixIcon: Icon(Icons.inventory_2_outlined)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _descripcion,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _unidadSap,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Unidad SAP'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _unidadLectura,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Unidad lectura'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: _factor,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Factor de conversión', helperText: 'Cantidad SAP = cantidad leída × factor'),
              ),
              SwitchListTile(
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
                title: const Text('ACTIVA', style: TextStyle(fontWeight: FontWeight.w700)),
                activeThumbColor: AppColors.rojo,
                contentPadding: EdgeInsets.zero,
              ),
            ]),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(_error!,
                style: const TextStyle(color: AppColors.rojoOscuro, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
          ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.blanco))
              : const Icon(Icons.save_outlined),
          label: const Text('GUARDAR'),
        ),
        if (!esNueva) ...[
          const SizedBox(height: 8),
          Text(
            'Última modificación: ${widget.datos!['fecha_modif'] ?? '-'} por ${widget.datos!['usuario_modif'] ?? '-'}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ]),
    );
  }
}
