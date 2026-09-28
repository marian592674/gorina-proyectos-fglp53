import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/db.dart';
import '../../services/control_picks_cache.dart';

class ControlPicksScreen extends StatefulWidget {
  const ControlPicksScreen({super.key});
  @override
  State<ControlPicksScreen> createState() => _ControlPicksScreenState();
}

class _ControlPicksScreenState extends State<ControlPicksScreen>
    with WidgetsBindingObserver {
  String _filtro = '';
  String? _filtroUsuario;
  String? _filtroAlmacen;
  List<dynamic> _ops = [];
  List<dynamic> _todasOps = [];
  List<dynamic> _abiertas = [];
  List<String> _usuarios = [];
  List<Map<String, Object?>> _almacenes = [];
  int _diasHistorial = 30;
  int _diasConfigurados = 30;
  DateTimeRange? _rangoFechas;
  bool _cargando = true;
  bool _offline = false;
  bool _recuperandoConexion = false;
  String _error = '';
  String? _ultimaActualizacion;
  StreamSubscription<List<ConnectivityResult>>? _conexion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conexion = Connectivity().onConnectivityChanged.listen((resultados) {
      final hayRed = resultados.any((r) => r != ConnectivityResult.none);
      if (hayRed && _offline) _intentarRecuperarConexion();
    });
    _cargarFiltros();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _offline) {
      _intentarRecuperarConexion();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conexion?.cancel();
    super.dispose();
  }

  Future<void> _cargarFiltros() async {
    try {
      _almacenes = await Db.almacenes();
    } catch (_) {}
    try {
      final params = await Db.parametros();
      _diasHistorial = int.tryParse(params['diasHistorialApp'] ?? '') ?? 30;
      _diasConfigurados = _diasHistorial;
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    await _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = '';
    });
    await _cargarAbiertas();
    try {
      if (!await Api.servidorDisponible()) {
        throw ApiException('Servidor Gorina no disponible');
      }
      final periodoCache = _diasHistorial == 0
          ? 0
          : _diasHistorial > _diasConfigurados
          ? _diasHistorial
          : _diasConfigurados;
      _todasOps = await ControlPicksCache.actualizar(dias: periodoCache);
      _offline = false;
    } on ApiException catch (e) {
      _todasOps = await Db.leerCacheControl();
      _offline = true;
      if (_todasOps.isEmpty) _error = e.mensaje;
    }
    final info = await Db.infoCacheControl();
    _ultimaActualizacion = info['control_picks_actualizado'];
    _actualizarUsuariosDesdeCache();
    _aplicarFiltros(notificar: false);
    if (mounted) {
      setState(() => _cargando = false);
    }
  }

  Future<void> _cargarAbiertas() async {
    final locales = await Db.operaciones(estados: 'ABIERTA');
    final resultado = <dynamic>[];
    for (final operacion in locales) {
      final posiciones = await Db.posiciones(operacion['id'] as String);
      resultado.add({
        ...operacion,
        'fecha_cierre': operacion['fecha_creacion'],
        'posiciones': posiciones.length,
        'estado': 'ABIERTA',
      });
    }
    _abiertas = resultado;
  }

  void _actualizarUsuariosDesdeCache() {
    final usuarios = {
      ..._usuarios,
      ..._todasOps
          .map((op) => (op as Map)['usuario']?.toString() ?? '')
          .where((usuario) => usuario.isNotEmpty),
    }.toList()..sort();
    _usuarios = usuarios;
  }

  void _aplicarFiltros({bool notificar = true}) {
    Iterable<dynamic> resultado = _filtro == 'ABIERTA' ? _abiertas : _todasOps;
    if (_filtro.isNotEmpty && _filtro != 'ABIERTA') {
      resultado = resultado.where((item) {
        final op = item as Map;
        return estadoPick(op['estado']?.toString() ?? '', op['estado_sap']) ==
            _filtro;
      });
    }
    if (_filtroUsuario?.isNotEmpty ?? false) {
      resultado = resultado.where(
        (item) => (item as Map)['usuario']?.toString() == _filtroUsuario,
      );
    }
    if (_filtroAlmacen?.isNotEmpty ?? false) {
      resultado = resultado.where(
        (item) => (item as Map)['almacen']?.toString() == _filtroAlmacen,
      );
    }
    if (_rangoFechas != null && _filtro != 'ABIERTA') {
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
      resultado = resultado.where((item) {
        final fecha = DateTime.tryParse(
          (item as Map)['fecha_cierre']?.toString() ?? '',
        );
        return fecha != null && !fecha.isBefore(inicio) && !fecha.isAfter(fin);
      });
    } else if (_diasHistorial > 0 && _filtro != 'ABIERTA') {
      final limite = DateTime.now().subtract(Duration(days: _diasHistorial));
      resultado = resultado.where((item) {
        final fecha = DateTime.tryParse(
          (item as Map)['fecha_cierre']?.toString() ?? '',
        );
        return fecha == null || !fecha.isBefore(limite);
      });
    }
    _ops = resultado.toList();
    if (notificar && mounted) setState(() {});
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
      helpText: 'FILTRAR POR FECHA',
      cancelText: 'CANCELAR',
      confirmText: 'APLICAR',
    );
    if (rango != null) {
      setState(() {
        _rangoFechas = rango;
      });
      _aplicarFiltros();
    }
  }

  Future<void> _intentarRecuperarConexion() async {
    if (_recuperandoConexion || _cargando) return;
    _recuperandoConexion = true;
    try {
      if (await Api.servidorDisponible()) await _cargar();
    } finally {
      _recuperandoConexion = false;
    }
  }

  Widget _statsHeader() {
    if (_filtro != '' || _ops.isEmpty || _cargando || _error.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final total = _ops.length;
    final porEstado = <String, int>{};
    for (final op in _ops) {
      final mapa = op as Map;
      final e = estadoPick(
        mapa['estado']?.toString() ?? '',
        mapa['estado_sap'],
      );
      porEstado[e] = (porEstado[e] ?? 0) + 1;
    }
    final enCurso =
        (porEstado['PENDIENTE'] ?? 0) + (porEstado['ESPERANDO SAP'] ?? 0);
    final conError = (porEstado['ERROR'] ?? 0) + (porEstado['SAP NP'] ?? 0);
    String pct(String e) => total == 0
        ? '0%'
        : '${((porEstado[e] ?? 0) * 100 / total).toStringAsFixed(0)}%';
    String pctCantidad(int cantidad) =>
        total == 0 ? '0%' : '${(cantidad * 100 / total).toStringAsFixed(0)}%';
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen ($total operaciones)',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _statChip(
                  'EN CURSO',
                  enCurso,
                  pctCantidad(enCurso),
                  AppColors.ambarPendiente,
                ),
                const SizedBox(width: 8),
                _statChip(
                  'SAP OK',
                  porEstado['SAP OK'] ?? 0,
                  pct('SAP OK'),
                  AppColors.verdeOk,
                ),
                const SizedBox(width: 8),
                _statChip(
                  'ERROR / NP',
                  conError,
                  pctCantidad(conError),
                  AppColors.rojoOscuro,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  if (enCurso > 0)
                    Expanded(
                      flex: enCurso,
                      child: Container(
                        height: 8,
                        color: AppColors.ambarPendiente,
                      ),
                    ),
                  if ((porEstado['SAP OK'] ?? 0) > 0)
                    Expanded(
                      flex: porEstado['SAP OK']!,
                      child: Container(height: 8, color: AppColors.verdeOk),
                    ),
                  if (conError > 0)
                    Expanded(
                      flex: conError,
                      child: Container(height: 8, color: AppColors.rojoOscuro),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, int count, String pct, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                '$count',
                style: TextStyle(fontWeight: FontWeight.w800, color: color),
              ),
              Text(pct, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CONTROL DE PICKS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Qué significa cada estado',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Estados'),
                content: const Text(
                  'ABIERTA: borrador guardado en el teléfono (solo visible en Mis Picks / aquí si filtrás ABIERTA).\n'
                  'PENDIENTE: cerrado y encolado, esperando generar el CSV en el servidor.\n'
                  'ESPERANDO SAP: CSV generado y todavía sin respuesta de SAP.\n'
                  'SAP NP: SAP no pudo procesarlo y volverá a intentar.\n'
                  'SAP OK: consumo procesado correctamente en SAP.\n'
                  'ERROR: falló la generación (ej. carpeta de red no disponible, ver msg_error). Usá Reintentar.',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _filtro == f
                              ? AppColors.rojo
                              : Colors.grey.shade700,
                        ),
                        onSelected: (_) {
                          _filtro = f;
                          _aplicarFiltros();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _filtroUsuario,
                    isDense: true,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Todos', style: TextStyle(fontSize: 13)),
                      ),
                      ..._usuarios.map(
                        (u) => DropdownMenuItem<String>(
                          value: u,
                          child: Text(
                            u,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      _filtroUsuario = v;
                      _aplicarFiltros();
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      labelText: 'Usuario',
                      labelStyle: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _filtroAlmacen,
                    isDense: true,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Todos', style: TextStyle(fontSize: 13)),
                      ),
                      ..._almacenes.map(
                        (a) => DropdownMenuItem<String>(
                          value: a['codigo'] as String,
                          child: Text(
                            '${a['codigo']}',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      _filtroAlmacen = v;
                      _aplicarFiltros();
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      labelText: 'Almacén',
                      labelStyle: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
            child: Row(
              children: [
                const Text(
                  'Período: ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                for (final dias in const [7, 30, 90, 0])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(dias == 0 ? 'TODO' : '$dias DÍAS'),
                      selected: _rangoFechas == null && _diasHistorial == dias,
                      onSelected: (_) {
                        setState(() {
                          _rangoFechas = null;
                          _diasHistorial = dias;
                        });
                        _cargar();
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.date_range, size: 16),
                    label: Text(
                      _rangoFechas == null
                          ? 'CALENDARIO'
                          : '${_rangoFechas!.start.day.toString().padLeft(2, '0')}/${_rangoFechas!.start.month.toString().padLeft(2, '0')} - ${_rangoFechas!.end.day.toString().padLeft(2, '0')}/${_rangoFechas!.end.month.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12),
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
          _bannerConexion(),
          _statsHeader(),
          Expanded(child: _contenido()),
        ],
      ),
    );
  }

  Widget _bannerConexion() {
    if (!_offline) return const SizedBox.shrink();
    final fecha = _ultimaActualizacion?.isNotEmpty == true
        ? _ultimaActualizacion!
        : 'sin actualización previa';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: AppColors.ambarPendiente),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'MODO OFFLINE · última actualización: $fecha\n'
              'Consulta de solo lectura.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: _cargando ? null : _intentarRecuperarConexion,
            tooltip: 'Reintentar conexión',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.cloud_off, size: 44, color: Colors.grey.shade500),
          const SizedBox(height: 10),
          Text(
            '$_error\n\nVerifique la conexión y deslice para reintentar.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    if (_ops.isEmpty) {
      return const Center(child: Text('Sin operaciones'));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        itemCount: _ops.length,
        itemBuilder: (_, i) {
          final op = _ops[i] as Map;
          final esIncidencia = op['tipo'] == 'INCIDENCIA_SAP';
          return Card(
            child: ListTile(
              title: Text(
                esIncidencia
                    ? 'ERROR/NP · Orden ${op['orden']}'
                    : 'Orden ${op['orden']}   ·   ${op['ceco']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                  children: [
                    TextSpan(
                      text: '${op['usuario']}',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: esIncidencia
                          ? ' · ${op['fecha_cierre']}\n${op['archivo_sap_nombre']}'
                          : ' · ${op['fecha_cierre']}\n${op['posiciones']} posición(es)${((op['doc_sap'] ?? '') as String).isNotEmpty ? ' · Doc SAP: ${op['doc_sap']}' : ''}',
                    ),
                  ],
                ),
              ),
              isThreeLine: true,
              trailing: ChipEstado(
                estado: estadoPick(
                  op['estado']?.toString() ?? '',
                  op['estado_sap'],
                ),
              ),
              onTap: () async {
                if (esIncidencia) {
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('ERROR/NP SIN ASOCIAR'),
                      content: Text(
                        'SAP informó NP pero no se encontró un pick asociado.\n\n'
                        'Orden detectada: ${op['orden']}\n'
                        'Archivo: ${op['archivo_sap_nombre']}\n'
                        'Fecha SAP: ${op['fecha_cierre']}\n\n'
                        '${op['msg_error']}',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('CERRAR'),
                        ),
                      ],
                    ),
                  );
                  return;
                }
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetallePickServerScreen(
                      opId: op['id'].toString(),
                      resumen: Map<String, dynamic>.from(op),
                    ),
                  ),
                );
                _cargar();
              },
            ),
          );
        },
      ),
    );
  }
}

class DetallePickServerScreen extends StatefulWidget {
  final String opId;
  final Map<String, dynamic> resumen;
  const DetallePickServerScreen({
    super.key,
    required this.opId,
    required this.resumen,
  });
  @override
  State<DetallePickServerScreen> createState() =>
      _DetallePickServerScreenState();
}

class _DetallePickServerScreenState extends State<DetallePickServerScreen> {
  Map? _op;
  List<dynamic> _posiciones = [];
  List<dynamic> _eventosSap = [];
  bool _reintentando = false;
  bool _offline = false;
  bool _detalleCacheado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      if (!await Api.servidorDisponible()) {
        throw ApiException('Servidor Gorina no disponible');
      }
      final r = await Api.get(
        '/api/operaciones/${widget.opId}',
        token: Config.token,
      );
      final detalle = Map<String, dynamic>.from(r as Map);
      await Db.guardarDetalleControl(widget.opId, detalle);
      if (!mounted) return;
      setState(() {
        _op = detalle;
        _posiciones = (_op?['posiciones'] as List?) ?? [];
        _eventosSap = (_op?['eventosSap'] as List?) ?? [];
        _offline = false;
        _detalleCacheado = true;
      });
    } on ApiException {
      final cache = await Db.leerDetalleControl(widget.opId);
      if (!mounted) return;
      setState(() {
        _op =
            cache ??
            {
              'operacion': widget.resumen,
              'posiciones': <dynamic>[],
              'eventosSap': <dynamic>[],
            };
        _posiciones = (_op?['posiciones'] as List?) ?? [];
        _eventosSap = (_op?['eventosSap'] as List?) ?? [];
        _offline = true;
        _detalleCacheado = cache != null;
      });
    }
  }

  Future<void> _reintentar() async {
    setState(() => _reintentando = true);
    try {
      await Api.post(
        '/api/operaciones/${widget.opId}/reintentar',
        {},
        token: Config.token,
      );
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reintento ejecutado'),
            backgroundColor: AppColors.verdeOk,
          ),
        );
      }
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
    if (mounted) setState(() => _reintentando = false);
  }

  Future<void> _compartir() async {
    final op = _op;
    if (op == null) return;
    final datosOp = op['operacion'] as Map;
    try {
      final bytes = await Api.getBytes(
        '/api/operaciones/${widget.opId}/archivo',
        token: Config.token,
      );
      final dir = await getTemporaryDirectory();
      final archivoOriginal = datosOp['archivo_nombre']?.toString() ?? '';
      final archivoSap = datosOp['archivo_sap_nombre']?.toString() ?? '';
      final nombre = archivoOriginal.isNotEmpty
          ? archivoOriginal
          : archivoSap.isNotEmpty
          ? archivoSap
          : 'pickquim_${widget.opId}.csv';
      final file = File('${dir.path}/$nombre');
      await file.writeAsBytes(bytes);
      final resumen =
          'Pick Gorina\nOrden: ${datosOp['orden']}\nCECO: ${datosOp['ceco']}\nClase: ${datosOp['clase_movimiento']} Centro: ${datosOp['centro']} Almacén: ${datosOp['almacen']}\nTexto cabecera: ${datosOp['texto_cabecera'] ?? ''}\nPosiciones: ${_posiciones.length}\nUsuario: ${datosOp['usuario']}\nArchivo: $nombre\n\nDetalle:\n${_posiciones.map((p) => '- ${p['material_sap']} x ${p['cantidad_sap']} ${p['unidad_sap']}').join('\n')}';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Pick Orden ${datosOp['orden']} - Gorina',
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

  @override
  Widget build(BuildContext context) {
    final op = _op;
    if (op == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final datosOp = op['operacion'] as Map;
    final estado = datosOp['estado'].toString();
    final estadoVisible = estadoPick(estado, datosOp['estado_sap']);

    return Scaffold(
      appBar: AppBar(
        title: Text('Orden ${datosOp['orden']}'),
        actions: [
          if (estado == 'PROCESADO' && !_offline)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Compartir CSV + resumen',
              onPressed: _compartir,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: ChipEstado(estado: estadoVisible)),
          ),
        ],
      ),
      floatingActionButton: (Config.esAdmin && estado == 'ERROR' && !_offline)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.rojo,
              foregroundColor: AppColors.blanco,
              onPressed: _reintentando ? null : _reintentar,
              icon: _reintentando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.blanco,
                      ),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('REINTENTAR'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (_offline)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, color: AppColors.ambarPendiente),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _detalleCacheado
                          ? 'Detalle guardado · modo offline de solo lectura.'
                          : 'Cabecera disponible offline. Este detalle no fue abierto antes con conexión.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fila('Usuario', datosOp['usuario'].toString()),
                  _fila('Creado', datosOp['fecha_creacion'].toString()),
                  _fila('Cerrado', datosOp['fecha_cierre'].toString()),
                  _fila('Centro de costo', datosOp['ceco'].toString()),
                  _fila(
                    'Cl.mov / Centro / Almacén',
                    '${datosOp['clase_movimiento']} / ${datosOp['centro']} / ${datosOp['almacen']}',
                  ),
                  if ((datosOp['texto_cabecera'] ?? '').toString().isNotEmpty)
                    _fila(
                      'Texto cabecera',
                      datosOp['texto_cabecera'].toString(),
                    ),
                  if ((datosOp['archivo_nombre'] ?? '').toString().isNotEmpty)
                    _fila(
                      'Archivo generado',
                      datosOp['archivo_nombre'].toString(),
                      verde: true,
                    ),
                  _fila(
                    'Estado SAP',
                    estadoVisible,
                    verde: estadoVisible == 'SAP OK',
                    rojo: estadoVisible == 'SAP NP',
                  ),
                  if ((datosOp['doc_sap'] ?? '').toString().isNotEmpty)
                    _fila(
                      'Doc. Material SAP',
                      datosOp['doc_sap'].toString(),
                      verde: true,
                    ),
                  if ((datosOp['estado_sap_detalle'] ?? '')
                      .toString()
                      .isNotEmpty)
                    _fila(
                      'Detalle SAP',
                      datosOp['estado_sap_detalle'].toString(),
                      rojo: estadoVisible == 'SAP NP',
                    ),
                  if ((datosOp['archivo_sap_nombre'] ?? '')
                      .toString()
                      .isNotEmpty)
                    _fila(
                      'Archivo SAP',
                      datosOp['archivo_sap_nombre'].toString(),
                      verde: estadoVisible == 'SAP OK',
                      rojo: estadoVisible == 'SAP NP',
                    ),
                  if ((datosOp['estado_sap_fecha'] ?? '').toString().isNotEmpty)
                    _fila('Fecha SAP', datosOp['estado_sap_fecha'].toString()),
                  if ((datosOp['msg_error'] ?? '').toString().isNotEmpty)
                    _fila('Error / Mensaje', datosOp['msg_error'].toString(), rojo: true),
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
          if (_offline && !_detalleCacheado)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Las posiciones estarán disponibles después de abrir este pick una vez con conexión.',
                textAlign: TextAlign.center,
              ),
            ),
          ..._posiciones.map(_pos),
        ],
      ),
    );
  }

  Widget _fila(
    String etiqueta,
    String valor, {
    bool verde = false,
    bool rojo = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(etiqueta, style: TextStyle(color: Colors.grey.shade600)),
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

  Widget _pos(dynamic p) {
    p as Map;
    final manual = p['origen'] == 'MANUAL';
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
            if ((p['qr_leido'] ?? '').toString().isNotEmpty)
              Text('QR: ${p['qr_leido']}'),
            if ((p['texto_posicion'] ?? '').toString().isNotEmpty)
              Text(p['texto_posicion']),
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
      ),
    );
  }
}
