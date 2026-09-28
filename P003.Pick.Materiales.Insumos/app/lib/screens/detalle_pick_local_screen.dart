import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../services/sync.dart';
import 'escaneo_screen.dart';

class DetallePickLocalScreen extends StatefulWidget {
  final String opId;
  const DetallePickLocalScreen({super.key, required this.opId});
  @override
  State<DetallePickLocalScreen> createState() => _DetallePickLocalScreenState();
}

class _DetallePickLocalScreenState extends State<DetallePickLocalScreen> {
  Map<String, Object?>? _op;
  List<Map<String, Object?>> _posiciones = [];
  List<dynamic> _eventosSap = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _op = await Db.operacion(widget.opId);
    _posiciones = await Db.posiciones(widget.opId);
    try {
      if ((Config.token ?? '').isNotEmpty) {
        final remoto = await Api.get(
          '/api/operaciones/${widget.opId}',
          token: Config.token,
        );
        if (remoto is Map) {
          _eventosSap = (remoto['eventosSap'] as List?) ?? [];
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _reenviar() async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Enviando operación...')));
    final r = await Sync.sincronizarTodo();
    await _cargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.ok ? 'Sincronización completada' : r.errores.join(' | '),
        ),
        backgroundColor: r.ok ? AppColors.verdeOk : AppColors.rojoOscuro,
      ),
    );
  }

  Future<void> _compartir() async {
    final op = _op;
    if (op == null) return;
    try {
      final bytes = await Api.getBytes(
        '/api/operaciones/${widget.opId}/archivo',
        token: Config.token,
      );
      final dir = await getTemporaryDirectory();
      final archivoOriginal = op['archivo_nombre']?.toString() ?? '';
      final nombre = archivoOriginal.isNotEmpty
          ? archivoOriginal
          : (op['archivo_sap_nombre']?.toString().isNotEmpty ?? false)
          ? op['archivo_sap_nombre'].toString()
          : 'pickquim_${widget.opId}.csv';
      final file = File('${dir.path}/$nombre');
      await file.writeAsBytes(bytes);
      final resumen =
          'Pick Gorina\nOrden: ${op['orden']}\nCECO: ${op['ceco']}\nClase: ${op['clase_movimiento']} Centro: ${op['centro']} Almacén: ${op['almacen']}\nTexto cabecera: ${op['texto_cabecera'] ?? ''}\nPosiciones: ${_posiciones.length}\nUsuario: ${op['usuario']}\nArchivo: $nombre\n\nDetalle:\n${_posiciones.map((p) => '- ${p['material_sap']} x ${p['cantidad_sap']} ${p['unidad_sap']}').join('\n')}';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Pick Orden ${op['orden']} - Gorina',
          text: resumen,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.mensaje),
            backgroundColor: AppColors.rojoOscuro,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al compartir: $e')));
      }
    }
  }

  Future<void> _eliminarOrdenPendiente() async {
    final op = _op;
    if (op == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar pick pendiente'),
        content: Text('¿Eliminar la orden ${(op['orden'] ?? '')} pendiente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rojoOscuro),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Db.eliminarOperacionPendiente(widget.opId);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _modificarCantidadPosicion(Map<String, Object?> p) async {
    final cantActual = (p['cantidad_lectura'] as num?)?.toDouble() ?? 0;
    final ctrl = TextEditingController(text: cantActual.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Modificar cantidad: ${p['material_sap']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p['descripcion'] ?? ''}', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Nueva cantidad (${p['unidad_lectura'] ?? p['unidad_sap'] ?? ''})',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final nueva = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (nueva != null && nueva > 0) {
        await Db.actualizarCantidadPosicion(p['id'] as int, nueva);
        await _cargar();
      }
    }
  }

  Future<void> _eliminarPosicion(Map<String, Object?> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar posición'),
        content: Text('¿Eliminar ${p['material_sap']} de esta orden pendiente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rojoOscuro),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Db.eliminarPosicion(p['id'] as int);
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final op = _op;
    if (op == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final estado = (op['estado_local'] ?? '').toString();
    final estadoVisible = estadoPick(estado, op['estado_sap']);
    final puedeReenviar =
        Config.esAdmin && (estado == 'ERROR' || estado == 'PENDIENTE');
    final esAbierta = estado == 'ABIERTA';

    return Scaffold(
      appBar: AppBar(
        title: Text('Orden ${(op['orden'] ?? '').toString()}'),
        actions: [
          if (estado == 'PROCESADO')
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Compartir CSV + resumen',
              onPressed: _compartir,
            ),
          if (estado == 'PENDIENTE')
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.rojoOscuro),
              tooltip: 'Eliminar pick pendiente',
              onPressed: _eliminarOrdenPendiente,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: ChipEstado(estado: estadoVisible)),
          ),
        ],
      ),
      floatingActionButton: esAbierta
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'eliminar',
                  backgroundColor: Colors.grey.shade200,
                  foregroundColor: AppColors.rojoOscuro,
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Eliminar borrador'),
                        content: const Text('¿Eliminar este pick guardado?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.rojoOscuro,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('ELIMINAR'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await Db.eliminarOperacionAbierta(widget.opId);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('ELIMINAR'),
                ),
                const SizedBox(width: 10),
                FloatingActionButton.extended(
                  heroTag: 'continuar',
                  backgroundColor: AppColors.verdeOk,
                  foregroundColor: AppColors.blanco,
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EscaneoScreen(
                          orden: (op['orden'] ?? '').toString(),
                          ceco: (op['ceco'] ?? '').toString(),
                          almacen: (op['almacen'] ?? '').toString(),
                          claseMovimiento: (op['clase_movimiento'] ?? '201')
                              .toString(),
                          centro: (op['centro'] ?? '1001').toString(),
                          textoCabecera: (op['texto_cabecera'] ?? '')
                              .toString(),
                          opIdExistente: widget.opId,
                        ),
                      ),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('CONTINUAR'),
                ),
              ],
            )
          : puedeReenviar
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.rojo,
              foregroundColor: AppColors.blanco,
              onPressed: _reenviar,
              icon: const Icon(Icons.refresh),
              label: Text(estado == 'ERROR' ? 'REINTENTAR' : 'ENVIAR'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fila('Usuario', (op['usuario'] ?? '').toString()),
                  _fila('Creado', (op['fecha_creacion'] ?? '').toString()),
                  _fila('Cerrado', (op['fecha_cierre'] ?? '-').toString()),
                  _fila('Centro de costo', (op['ceco'] ?? '').toString()),
                  _fila(
                    'Cl.mov / Centro / Almacén',
                    '${op['clase_movimiento']} / ${op['centro']} / ${op['almacen']}',
                  ),
                  if (((op['texto_cabecera'] ?? '') as String).isNotEmpty)
                    _fila('Texto cabecera', op['texto_cabecera'].toString()),
                  if (((op['archivo_nombre'] ?? '') as String).isNotEmpty)
                    _fila(
                      'Archivo generado',
                      op['archivo_nombre'].toString(),
                      verde: true,
                    ),
                  _fila(
                    'Estado SAP',
                    estadoVisible,
                    verde: estadoVisible == 'SAP OK',
                    rojo: estadoVisible == 'SAP NP',
                  ),
                  if ((op['doc_sap'] ?? '').toString().isNotEmpty)
                    _fila(
                      'Doc. Material SAP',
                      op['doc_sap'].toString(),
                      verde: true,
                    ),
                  if ((op['estado_sap_detalle'] ?? '').toString().isNotEmpty)
                    _fila(
                      'Detalle SAP',
                      op['estado_sap_detalle'].toString(),
                      rojo: estadoVisible == 'SAP NP',
                    ),
                  if ((op['archivo_sap_nombre'] ?? '').toString().isNotEmpty)
                    _fila(
                      'Archivo SAP',
                      op['archivo_sap_nombre'].toString(),
                      verde: estadoVisible == 'SAP OK',
                      rojo: estadoVisible == 'SAP NP',
                    ),
                  if ((op['estado_sap_fecha'] ?? '').toString().isNotEmpty)
                    _fila('Fecha SAP', op['estado_sap_fecha'].toString()),
                  if (((op['msg_error'] ?? '') as String).isNotEmpty)
                    _fila('Error / Mensaje', op['msg_error'].toString(), rojo: true),
                ],
              ),
            ),
          ),
          if (_eventosSap.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'HISTORIAL SAP',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            ..._eventosSap.map((evento) {
              final e = evento as Map;
              final estadoEvento = e['estado']?.toString() ?? '';
              return Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    estadoEvento == 'OK'
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: estadoEvento == 'OK'
                        ? AppColors.verdeOk
                        : AppColors.rojoOscuro,
                  ),
                  title: Text(
                    'SAP $estadoEvento',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${e['fecha_sap']}\n${e['archivo_nombre'] ?? ''}',
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 8),
          Text(
            'POSICIONES (${_posiciones.length})',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
          ..._posiciones.map(_filaPos),
        ],
      ),
    );
  }

  Widget _fila(
    String etiqueta,
    String valor, {
    bool verde = false,
    bool rojo = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              etiqueta,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: rojo
                    ? AppColors.rojoOscuro
                    : verde
                    ? AppColors.verdeOk
                    : AppColors.texto,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaPos(Map<String, Object?> p) {
    final manual = p['origen'] == 'MANUAL';
    final esPendiente = (_op?['estado_local'] ?? '').toString() == 'PENDIENTE';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        title: Text(
          '${p['linea']}. ${p['material_sap']} | ${p['cantidad_sap']} ${p['unidad_sap']}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (((p['qr_leido'] ?? '') as String).isNotEmpty)
              Text('QR: ${p['qr_leido']}'),
            if (((p['texto_posicion'] ?? '') as String).isNotEmpty)
              Text(p['texto_posicion'].toString()),
            if (manual)
              const Text(
                'SIN EQUIVALENCIA',
                style: TextStyle(
                  color: AppColors.rojoOscuro,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        trailing: esPendiente
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: AppColors.rojo, size: 22),
                    tooltip: 'Modificar cantidad',
                    onPressed: () => _modificarCantidadPosicion(p),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 22),
                    tooltip: 'Eliminar posición',
                    onPressed: () => _eliminarPosicion(p),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
