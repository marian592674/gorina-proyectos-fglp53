import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../services/sync.dart';

class ImportarCatalogosScreen extends StatefulWidget {
  const ImportarCatalogosScreen({super.key});

  @override
  State<ImportarCatalogosScreen> createState() =>
      _ImportarCatalogosScreenState();
}

class _ImportarCatalogosScreenState extends State<ImportarCatalogosScreen> {
  static const _tipos = <String, String>{
    'equivalencias': 'Equivalencias QR → Material SAP',
    'cecos': 'Centros de costo',
    'almacenes': 'Almacenes',
    'clases': 'Clases de movimiento',
    'centros': 'Centros SAP',
  };

  String _tipo = 'equivalencias';
  String? _nombreArchivo;
  Uint8List? _bytes;
  Map<String, dynamic>? _validacion;
  List<dynamic> _historial = [];
  bool _procesando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    try {
      final resultado = await Api.get(
        '/api/catalogos/importaciones',
        token: Config.token,
      );
      if (mounted) {
        setState(() => _historial = resultado is List ? resultado : []);
      }
    } catch (_) {}
  }

  Future<void> _seleccionarArchivo() async {
    final archivo = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    if (!mounted) return;
    setState(() {
      _nombreArchivo = archivo.name;
      _bytes = bytes;
      _validacion = null;
      _error = null;
    });
  }

  Future<Map<String, dynamic>?> _enviar({required bool confirmar}) async {
    final bytes = _bytes;
    final nombre = _nombreArchivo;
    if (bytes == null || nombre == null) {
      setState(() => _error = 'Seleccione un archivo Excel.');
      return null;
    }
    setState(() {
      _procesando = true;
      _error = null;
    });
    try {
      final respuesta = await Api.subirArchivo(
        '/api/catalogos/importar',
        bytes: bytes,
        nombre: nombre,
        campos: {'tipo': _tipo, 'confirmar': confirmar.toString()},
        token: Config.token,
      );
      if (!mounted) return null;
      return Map<String, dynamic>.from(respuesta as Map);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
      return null;
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _validar() async {
    final respuesta = await _enviar(confirmar: false);
    if (respuesta == null || !mounted) return;
    setState(() {
      _validacion = Map<String, dynamic>.from(respuesta['validacion'] as Map);
    });
  }

  Future<void> _confirmar() async {
    final validacion = _validacion;
    if (validacion == null) return;
    final validas = (validacion['filasValidas'] as num?)?.toInt() ?? 0;
    if (validas == 0) return;
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar importación'),
        content: Text(
          'Se actualizarán $validas registro(s) de ${_tipos[_tipo]}.\n\n'
          'Los códigos existentes se actualizarán y los nuevos se agregarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('IMPORTAR'),
          ),
        ],
      ),
    );
    if (aceptar != true) return;

    final respuesta = await _enviar(confirmar: true);
    if (respuesta == null || !mounted) return;
    final registros = respuesta['registros'] ?? 0;
    try {
      await Sync.bajarMaestros();
    } catch (_) {}
    await _cargarHistorial();
    if (!mounted) return;
    setState(() {
      _nombreArchivo = null;
      _bytes = null;
      _validacion = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Importación completada: $registros registro(s).'),
        backgroundColor: AppColors.verdeOk,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IMPORTAR CATÁLOGOS')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'NUEVA IMPORTACIÓN',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _tipo,
                    items: _tipos.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: _procesando
                        ? null
                        : (valor) {
                            if (valor == null) return;
                            setState(() {
                              _tipo = valor;
                              _validacion = null;
                            });
                          },
                    decoration: const InputDecoration(
                      labelText: 'Tipo de catálogo',
                      prefixIcon: Icon(Icons.table_view_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _procesando ? null : _seleccionarArchivo,
                    icon: const Icon(Icons.attach_file),
                    label: Text(_nombreArchivo ?? 'SELECCIONAR EXCEL .XLSX'),
                  ),
                  if (_nombreArchivo != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _nombreArchivo!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.rojoOscuro,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _procesando || _bytes == null ? null : _validar,
                    icon: _procesando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.blanco,
                            ),
                          )
                        : const Icon(Icons.fact_check_outlined),
                    label: const Text('VALIDAR ARCHIVO'),
                  ),
                ],
              ),
            ),
          ),
          if (_validacion != null) _resumenValidacion(_validacion!),
          const SizedBox(height: 16),
          Text(
            'ÚLTIMAS IMPORTACIONES',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
          if (_historial.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Todavía no hay importaciones registradas.'),
            )
          else
            ..._historial.map((item) {
              final fila = item as Map;
              return Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.verdeOk,
                  ),
                  title: Text(
                    _tipos[fila['tipo']] ?? fila['tipo']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${fila['fecha']} · ${fila['usuario']}\n'
                    '${fila['registros']} registro(s) · ${fila['archivo_nombre']}',
                  ),
                  isThreeLine: true,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _resumenValidacion(Map<String, dynamic> validacion) {
    final validas = (validacion['filasValidas'] as num?)?.toInt() ?? 0;
    final omitidas = (validacion['filasOmitidas'] as num?)?.toInt() ?? 0;
    final errores = (validacion['errores'] as List?) ?? [];
    final muestra = (validacion['muestra'] as List?) ?? [];
    return Card(
      color: validas > 0 ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              validas > 0 ? 'ARCHIVO VÁLIDO' : 'ARCHIVO SIN DATOS VÁLIDOS',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: validas > 0 ? AppColors.verdeOk : AppColors.rojoOscuro,
              ),
            ),
            const SizedBox(height: 8),
            Text('Filas válidas: $validas · Omitidas: $omitidas'),
            if (errores.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...errores
                  .take(5)
                  .map(
                    (e) => Text(
                      '• $e',
                      style: const TextStyle(color: AppColors.rojoOscuro),
                    ),
                  ),
            ],
            if (muestra.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Primera fila válida:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                (muestra.first as Map).entries
                    .take(5)
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n'),
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _procesando || validas == 0 ? null : _confirmar,
              icon: const Icon(Icons.upload_file),
              label: const Text('CONFIRMAR IMPORTACIÓN'),
            ),
          ],
        ),
      ),
    );
  }
}
