import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/db.dart';
import '../services/sync.dart';
import 'detalle_pick_local_screen.dart';
import 'escaneo_screen.dart';

class MisPicksScreen extends StatefulWidget {
  const MisPicksScreen({super.key});
  @override
  State<MisPicksScreen> createState() => _MisPicksScreenState();
}

class _MisPicksScreenState extends State<MisPicksScreen> {
  List<Map<String, Object?>> _ops = [];
  bool _sincronizando = false;
  String _filtro = '';
  int? _filtroDias;
  DateTimeRange? _rangoFechas;
  final Set<String> _seleccionados = {};

  bool get _modoSeleccion => _seleccionados.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _cargar();
    Sync.sincronizarTodo().then((_) => _cargar());
  }

  Future<void> _cargar() async {
    final ops = await Db.operaciones(
      estados: 'PENDIENTE,ERROR,PROCESADO,ABIERTA',
    );
    if (!mounted) return;
    setState(() => _ops = ops);
  }

  Future<void> _sincronizar() async {
    if (_sincronizando) return;
    setState(() => _sincronizando = true);
    await Sync.sincronizarTodo();
    await _cargar();
    if (!mounted) return;
    setState(() => _sincronizando = false);
  }

  Future<void> _eliminarSeleccionados() async {
    if (_seleccionados.isEmpty) return;
    final cant = _seleccionados.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar picks pendientes'),
        content: Text('¿Eliminar $cant pick(s) pendiente(s) seleccionado(s)?'),
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
      await Db.eliminarOperacionesPendientes(_seleccionados.toList());
      setState(() => _seleccionados.clear());
      await _cargar();
    }
  }

  Future<void> _seleccionarRangoFechas() async {
    final ahora = DateTime.now();
    final inicial = _rangoFechas ??
        DateTimeRange(
          start: ahora.subtract(const Duration(days: 7)),
          end: ahora,
        );
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: ahora.add(const Duration(days: 365)),
      initialDateRange: inicial,
      helpText: 'SELECCIONAR RANGO DE FECHAS',
      cancelText: 'CANCELAR',
      confirmText: 'APLICAR',
    );
    if (rango != null) {
      setState(() {
        _rangoFechas = rango;
        _filtroDias = null;
      });
    }
  }

  List<Map<String, Object?>> get _filtradas {
    Iterable<Map<String, Object?>> res = _ops;
    if (_filtro.isNotEmpty) {
      res = res.where(
        (op) =>
            estadoPick(
              (op['estado_local'] ?? '').toString(),
              op['estado_sap'],
            ) ==
            _filtro,
      );
    }
    if (_filtroDias != null && _filtroDias! > 0) {
      final limite = DateTime.now().subtract(Duration(days: _filtroDias!));
      res = res.where((op) {
        final f = DateTime.tryParse(
          (op['fecha_creacion'] ?? op['fecha_cierre'] ?? '').toString(),
        );
        return f == null || !f.isBefore(limite);
      });
    } else if (_rangoFechas != null) {
      final inicio = DateTime(
        _rangoFechas!.start.year,
        _rangoFechas!.start.month,
        _rangoFechas!.start.day,
        0,
        0,
        0,
      );
      final fin = DateTime(
        _rangoFechas!.end.year,
        _rangoFechas!.end.month,
        _rangoFechas!.end.day,
        23,
        59,
        59,
      );
      res = res.where((op) {
        final f = DateTime.tryParse(
          (op['fecha_creacion'] ?? op['fecha_cierre'] ?? '').toString(),
        );
        return f != null && !f.isBefore(inicio) && !f.isAfter(fin);
      });
    }
    return res.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _modoSeleccion
          ? AppBar(
              backgroundColor: AppColors.rojoOscuro,
              foregroundColor: AppColors.blanco,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _seleccionados.clear()),
              ),
              title: Text('${_seleccionados.length} seleccionados'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Seleccionar todos los pendientes',
                  onPressed: () {
                    final pendientes = _filtradas
                        .where(
                          (op) =>
                              (op['estado_local'] ?? '').toString() ==
                              'PENDIENTE',
                        )
                        .map((op) => op['id'] as String)
                        .toSet();
                    setState(() => _seleccionados.addAll(pendientes));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Eliminar pendientes seleccionados',
                  onPressed: _eliminarSeleccionados,
                ),
              ],
            )
          : AppBar(
              title: const Text('MIS PICKS'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: 'Selección múltiple (Solo pendientes)',
                  onPressed: () {
                    final primerPendiente = _filtradas.firstWhere(
                      (op) =>
                          (op['estado_local'] ?? '').toString() == 'PENDIENTE',
                      orElse: () => {},
                    );
                    if (primerPendiente.isNotEmpty) {
                      setState(
                        () => _seleccionados.add(
                          primerPendiente['id'] as String,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No hay picks pendientes para seleccionar',
                          ),
                        ),
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Qué significa cada estado',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Estados'),
                      content: const Text(
                        'ABIERTA: borrador guardado en el teléfono, podés continuarlo.\n'
                        'PENDIENTE: cerrado y encolado para generar el CSV.\n'
                        'ESPERANDO SAP: CSV generado y todavía sin respuesta.\n'
                        'SAP NP: SAP no pudo procesarlo y volverá a intentar.\n'
                        'SAP OK: consumo procesado correctamente en SAP.\n'
                        'ERROR: falló la generación (ej. carpeta no disponible). Reintentar.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                for (final f in const [
                  '',
                  'ABIERTA',
                  'PENDIENTE',
                  'ESPERANDO SAP',
                  'SAP NP',
                  'SAP OK',
                  'ERROR',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.isEmpty ? 'TODOS' : f),
                      selected: _filtro == f,
                      selectedColor: AppColors.rojo.withValues(alpha: .18),
                      onSelected: (_) => setState(() => _filtro = f),
                    ),
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('TODAS LAS FECHAS'),
                    selected: _filtroDias == null && _rangoFechas == null,
                    onSelected: (_) => setState(() {
                      _filtroDias = null;
                      _rangoFechas = null;
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('7 DÍAS'),
                    selected: _filtroDias == 7 && _rangoFechas == null,
                    onSelected: (_) => setState(() {
                      _filtroDias = 7;
                      _rangoFechas = null;
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      _rangoFechas == null
                          ? 'CALENDARIO (DESDE - HASTA)'
                          : '${_rangoFechas!.start.day.toString().padLeft(2, '0')}/${_rangoFechas!.start.month.toString().padLeft(2, '0')} - ${_rangoFechas!.end.day.toString().padLeft(2, '0')}/${_rangoFechas!.end.month.toString().padLeft(2, '0')}',
                    ),
                    backgroundColor: _rangoFechas != null
                        ? AppColors.rojo.withValues(alpha: .18)
                        : null,
                    onPressed: _seleccionarRangoFechas,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _sincronizar,
              child: _filtradas.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            _ops.isEmpty
                                ? 'No hay operaciones en este equipo'
                                : 'Sin operaciones con estado $_filtro',
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _filtradas.length,
                      itemBuilder: (_, i) {
                        final op = _filtradas[i];
                        final opId = op['id'] as String;
                        final esPendiente =
                            (op['estado_local'] ?? '').toString() ==
                            'PENDIENTE';
                        final seleccionado = _seleccionados.contains(opId);

                        Widget tarjeta = Card(
                          color: seleccionado
                              ? AppColors.rojo.withValues(alpha: .12)
                              : null,
                          child: ListTile(
                            leading: _modoSeleccion && esPendiente
                                ? Checkbox(
                                    value: seleccionado,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _seleccionados.add(opId);
                                        } else {
                                          _seleccionados.remove(opId);
                                        }
                                      });
                                    },
                                  )
                                : null,
                            title: Text(
                              'Orden ${op['orden']}   ·   ${op['ceco']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${op['fecha_creacion']}${((op['texto_cabecera'] ?? '') as String).isNotEmpty ? '\n${op['texto_cabecera']}' : ''}\n${_infoExtra(op)}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            isThreeLine: true,
                            trailing: ChipEstado(
                              estado: estadoPick(
                                (op['estado_local'] ?? '').toString(),
                                op['estado_sap'],
                              ),
                            ),
                            onLongPress: esPendiente
                                ? () {
                                    setState(() {
                                      if (seleccionado) {
                                        _seleccionados.remove(opId);
                                      } else {
                                        _seleccionados.add(opId);
                                      }
                                    });
                                  }
                                : null,
                            onTap: () async {
                              if (_modoSeleccion) {
                                if (esPendiente) {
                                  setState(() {
                                    if (seleccionado) {
                                      _seleccionados.remove(opId);
                                    } else {
                                      _seleccionados.add(opId);
                                    }
                                  });
                                }
                                return;
                              }
                              final estado = (op['estado_local'] ?? '')
                                  .toString();
                              if (estado == 'ABIERTA') {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EscaneoScreen(
                                      orden: (op['orden'] ?? '').toString(),
                                      ceco: (op['ceco'] ?? '').toString(),
                                      almacen: (op['almacen'] ?? '').toString(),
                                      claseMovimiento:
                                          (op['clase_movimiento'] ?? '201')
                                              .toString(),
                                      centro: (op['centro'] ?? '1001')
                                          .toString(),
                                      textoCabecera:
                                          (op['texto_cabecera'] ?? '')
                                              .toString(),
                                      opIdExistente: opId,
                                    ),
                                  ),
                                );
                              } else {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DetallePickLocalScreen(
                                      opId: opId,
                                    ),
                                  ),
                                );
                              }
                              _cargar();
                            },
                          ),
                        );

                        if (_modoSeleccion && !esPendiente) {
                          return Opacity(
                            opacity: 0.38,
                            child: tarjeta,
                          );
                        }
                        return tarjeta;
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _infoExtra(Map<String, Object?> op) {
    final estado = (op['estado_local'] ?? '').toString();
    if (estado == 'PROCESADO') {
      final sap = (op['estado_sap'] ?? '').toString();
      final archivoSap = (op['archivo_sap_nombre'] ?? '').toString();
      final docSap = (op['doc_sap'] ?? '').toString();
      final detalle = (op['estado_sap_detalle'] ?? '').toString();
      final error = (op['msg_error'] ?? '').toString();

      if (sap == 'OK') {
        if (docSap.isNotEmpty) return 'Consumo confirmado · Doc SAP: $docSap';
        return 'Consumo confirmado por SAP · $archivoSap';
      }
      if (sap == 'NP') {
        final motivo = detalle.isNotEmpty
            ? detalle
            : (error.isNotEmpty ? error : 'Reintento pendiente');
        return 'SAP NP: $motivo';
      }
      return 'Esperando respuesta SAP · Archivo: ${op['archivo_nombre'] ?? '-'}';
    }
    if (estado == 'ERROR') {
      return 'Error: ${op['msg_error']}'.trim();
    }
    if (estado == 'PENDIENTE') return 'Esperando envío al servidor';
    if (estado == 'ABIERTA') return 'Borrador — tocá para continuar';
    return '';
  }
}
