import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../data/db.dart';
import 'cierre_pick_screen.dart';

class EscaneoScreen extends StatefulWidget {
  final String orden;
  final String ceco;
  final String almacen;
  final String claseMovimiento;
  final String centro;
  final String textoCabecera;
  final String? opIdExistente;
  final String? opIdReservado;

  const EscaneoScreen({
    super.key,
    required this.orden,
    required this.ceco,
    required this.almacen,
    this.claseMovimiento = '201',
    this.centro = '1001',
    required this.textoCabecera,
    this.opIdExistente,
    this.opIdReservado,
  });

  @override
  State<EscaneoScreen> createState() => _EscaneoScreenState();
}

class _EscaneoScreenState extends State<EscaneoScreen> {
  String? _opId;
  List<Map<String, Object?>> _posiciones = [];
  final _entradaManual = TextEditingController();
  final _focoManual = FocusNode();
  DateTime _ultimaDeteccion = DateTime.fromMillisecondsSinceEpoch(0);
  String? _ultimoCodigo;
  bool _procesando = false;
  bool _camaraInicializada = false;
  bool _camaraDisponible = true;
  String? _errorCamara;
  int _sesionCamara = 0;

  @override
  void initState() {
    super.initState();
    _prepararOperacion();
  }

  Future<void> _prepararOperacion() async {
    if (widget.opIdExistente != null) {
      _opId = widget.opIdExistente;
      await _recargarPosiciones();
    } else {
      final id = await Db.nuevaOperacion(
        id: widget.opIdReservado,
        orden: widget.orden,
        ceco: widget.ceco,
        almacen: widget.almacen,
        textoCabecera: widget.textoCabecera,
        params: {
          'claseMovimiento': widget.claseMovimiento,
          'centro': widget.centro,
        },
      );
      if (!mounted) return;
      setState(() => _opId = id);
    }
    await _inicializarCamara();
  }

  Future<void> _inicializarCamara() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _camaraDisponible = false;
        _errorCamara = 'En PC use carga manual o lectora USB. La cámara QR funciona en celular.';
        _camaraInicializada = true;
      });
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      if (!mounted) return;
      setState(() {
        _camaraDisponible = false;
        _errorCamara =
            'En esta PC use el campo manual de abajo o una lectora USB.';
        _camaraInicializada = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _camaraDisponible = true;
      _camaraInicializada = true;
      _errorCamara = null;
      _sesionCamara++;
    });
  }

  @override
  void dispose() {
    _entradaManual.dispose();
    _focoManual.dispose();
    super.dispose();
  }

  Future<void> _onDetectar(BarcodeCapture captura) async {
    if (_procesando || _opId == null) return;
    for (final codigo in captura.barcodes) {
      final valor = codigo.rawValue;
      if (valor == null || valor.isEmpty) continue;
      final ahora = DateTime.now();
      if (valor == _ultimoCodigo &&
          ahora.difference(_ultimaDeteccion).inMilliseconds < 1500) {
        return;
      }
      _ultimoCodigo = valor;
      _ultimaDeteccion = ahora;
      await _procesarCodigo(valor);
      return;
    }
  }

  Future<void> _procesarCodigo(String codigo) async {
    setState(() => _procesando = true);
    try {
      final eq = await Db.equivalencia(codigo);
      if (!mounted) return;
      if (eq != null) {
        await _pedirCantidad(
          qrLeido: codigo,
          materialSap: eq['material_sap'].toString(),
          descripcion: eq['descripcion'].toString(),
          unidadLectura: eq['unidad_lectura'].toString(),
          unidadSap: eq['unidad_sap'].toString(),
          factor: (eq['factor_conversion'] as num?)?.toDouble() ?? 1,
          origen: 'EQUIVALENCIA',
        );
      } else {
        await _pedirMaterialManual(codigo);
      }
    } finally {
      if (mounted) {
        setState(() => _procesando = false);
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _focoManual.requestFocus();
        });
      }
    }
  }

  Future<void> _pedirMaterialManual(String codigo) async {
    final controller = TextEditingController();
    final material = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.rojoOscuro),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'QR SIN EQUIVALENCIA',
                    style: TextStyle(fontSize: 17),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Código leído:',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                SelectableText(
                  codigo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 7,
                  onChanged: (_) {
                    if (error != null) setD(() => error = null);
                  },
                  decoration: InputDecoration(
                    labelText: 'MATERIAL SAP *',
                    hintText: 'Ej: 4000004',
                    errorText: error,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'La posición quedará marcada para revisión del ADMIN.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final valor = controller.text;
                  if (!RegExp(r'^[0-9]{7}$').hasMatch(valor)) {
                    setD(() => error = 'Ingrese exactamente 7 dígitos');
                    return;
                  }
                  Navigator.pop(ctx, valor);
                },
                child: const Text('CONTINUAR'),
              ),
            ],
          ),
        );
      },
    );
    if (material == null || material.isEmpty) return;

    if (!mounted) return;
    await _pedirCantidad(
      qrLeido: codigo,
      materialSap: material,
      descripcion: '(sin equivalencia - ingreso manual)',
      unidadLectura: '',
      unidadSap: '',
      factor: 1,
      origen: 'MANUAL',
    );
  }

  Future<void> _pedirCantidad({
    required String qrLeido,
    required String materialSap,
    required String descripcion,
    required String unidadLectura,
    required String unidadSap,
    required double factor,
    required String origen,
  }) async {
    final resultado = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      builder: (_) => _HojaCantidad(
        materialSap: materialSap,
        descripcion: descripcion,
        unidadLectura: unidadLectura,
        origenManual: origen == 'MANUAL',
      ),
    );
    if (resultado == null) return;

    final cantidad = resultado['cantidad'] as double;
    final textoPosicion = resultado['textoPosicion'] as String;
    await Db.agregarPosicion(
      operacionId: _opId!,
      qrLeido: qrLeido,
      materialSap: materialSap,
      descripcion: descripcion,
      unidadLectura: unidadLectura.isEmpty ? unidadSap : unidadLectura,
      cantidadLectura: cantidad,
      unidadSap: unidadSap.isEmpty ? unidadLectura : unidadSap,
      cantidadSap: cantidad * (factor <= 0 ? 1 : factor),
      textoPosicion: textoPosicion,
      origen: origen,
    );
    await _recargarPosiciones();
  }

  Future<void> _recargarPosiciones() async {
    final lista = await Db.posiciones(_opId!);
    if (!mounted) return;
    setState(() => _posiciones = lista);
  }

  Future<void> _guardarBorrador() async {
    if (_opId == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick guardado como borrador')),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  void _abrirCierre() async {
    if (_posiciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay posiciones cargadas'),
          backgroundColor: AppColors.rojoOscuro,
        ),
      );
      return;
    }
    final cerrado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CierrePickScreen(opId: _opId!)),
    );
    if (cerrado == true && mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _editarEncabezado() async {
    final op = await Db.operacion(_opId!);
    if (op == null || !mounted) return;
    final ordenCtrl = TextEditingController(text: op['orden'].toString());
    final cabeceraCtrl = TextEditingController(
      text: (op['texto_cabecera'] ?? '').toString(),
    );
    final cecos = await Db.cecos();
    final almacenes = await Db.almacenes();
    String cecoSel = op['ceco'].toString();
    String almacenSel = op['almacen'].toString();
    String claseSel = op['clase_movimiento'].toString();
    String centroSel = op['centro'].toString();
    final clases = await Db.clasesMovimiento();
    final centros = await Db.centros();
    if (!mounted) return;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Editar encabezado'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ordenCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Orden (auto)',
                    suffixIcon: Icon(Icons.lock_outline, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: clases.any((c) => c['codigo'] == claseSel)
                      ? claseSel
                      : null,
                  items: clases
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['codigo'] as String,
                          child: Text('${c['codigo']} - ${c['descripcion']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => claseSel = v ?? claseSel),
                  decoration: const InputDecoration(
                    labelText: 'Clase movimiento',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: centros.any((c) => c['codigo'] == centroSel)
                      ? centroSel
                      : null,
                  items: centros
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['codigo'] as String,
                          child: Text('${c['codigo']} - ${c['descripcion']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => centroSel = v ?? centroSel),
                  decoration: const InputDecoration(labelText: 'Centro'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: almacenes.any((a) => a['codigo'] == almacenSel)
                      ? almacenSel
                      : null,
                  items: almacenes
                      .map(
                        (a) => DropdownMenuItem(
                          value: a['codigo'] as String,
                          child: Text('${a['codigo']} - ${a['descripcion']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => almacenSel = v ?? almacenSel),
                  decoration: const InputDecoration(labelText: 'Almacén'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: cecos.any((c) => c['ceco'] == cecoSel)
                      ? cecoSel
                      : null,
                  items: cecos
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['ceco'] as String,
                          child: Text('${c['ceco']} - ${c['descripcion']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => cecoSel = v ?? cecoSel),
                  decoration: const InputDecoration(
                    labelText: 'Centro de costo',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cabeceraCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Texto cabecera',
                  ),
                ),
              ],
            ),
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
      ),
    );
    if (guardado != true) return;
    await Db.actualizarEncabezado(
      _opId!,
      orden: ordenCtrl.text.trim(),
      ceco: cecoSel,
      almacen: almacenSel,
      claseMovimiento: claseSel,
      centro: centroSel,
      textoCabecera: cabeceraCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Encabezado actualizado')));
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final esDesktop = kIsWeb || ancho > 600;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final salir = await _confirmarSalir();
        if (salir == true && mounted) Navigator.of(this.context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final salir = await _confirmarSalir();
              if (salir == true && context.mounted) Navigator.of(context).pop();
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ORDEN ${widget.orden}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(widget.ceco, style: const TextStyle(fontSize: 11)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar encabezado',
              onPressed: _editarEncabezado,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: ChipEstado(estado: '${_posiciones.length} POS'),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _guardarBorrador,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('GUARDAR'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _posiciones.isEmpty ? null : _abrirCierre,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _posiciones.isEmpty
                          ? Colors.grey.shade300
                          : AppColors.verdeOk,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 26),
                    label: const Text(
                      'CERRAR PICK',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            if (!esDesktop || _camaraDisponible)
              Expanded(flex: esDesktop ? 4 : 5, child: _vistaCamara()),
            if (esDesktop && !_camaraDisponible)
              Container(
                width: double.infinity,
                color: Colors.amber.shade50,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorCamara ?? '',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            Container(height: 4, color: AppColors.fondo),
            Expanded(
              flex: esDesktop ? 7 : 6,
              child: _listaPosiciones(esDesktop),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaCamara() {
    if (!_camaraInicializada) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_camaraDisponible) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                size: 48,
                color: Colors.grey.shade500,
              ),
              const SizedBox(height: 10),
              Text(
                _errorCamara ?? 'Cámara no disponible',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _inicializarCamara,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () async => openAppSettings(),
                    icon: const Icon(Icons.settings),
                    label: const Text('Ajustes'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Podés seguir cargando con el campo manual de abajo o con lectora USB.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        MobileScanner(
          key: ValueKey(_sesionCamara),
          onDetect: _onDetectar,
          errorBuilder: (context, error) {
            final mensaje = _mensajeErrorCamara(error);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _camaraDisponible) {
                setState(() {
                  _camaraDisponible = false;
                  _errorCamara = mensaje;
                });
              }
            });
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  mensaje,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            );
          },
        ),
        _marcoEscaneo(),
        Positioned(
          left: 0,
          right: 0,
          top: 8,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Apuntar al código QR',
                style: TextStyle(color: AppColors.blanco, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _mensajeErrorCamara(MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return 'Permiso de cámara denegado. Habilitá la cámara en Ajustes.';
    }
    if (error.errorCode == MobileScannerErrorCode.unsupported) {
      return 'Este dispositivo no permite usar la cámara para escanear.';
    }
    final detalle = error.errorDetails?.message?.trim();
    if (detalle != null && detalle.isNotEmpty) {
      return 'Error de cámara: $detalle';
    }
    return 'No se pudo abrir la cámara. Cerrá otras aplicaciones que la estén usando y reintentá.';
  }

  Widget _marcoEscaneo() {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 230,
          height: 230,
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.blanco.withValues(alpha: .85),
              width: 3,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget _listaPosiciones(bool esDesktop) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'POSICIONES CARGADAS',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.grisMedio,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _entradaManual,
                focusNode: _focoManual,
                autofocus: !esDesktop,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) {
                  final codigo = v.trim();
                  if (codigo.isNotEmpty) _procesarCodigo(codigo);
                  _entradaManual.clear();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) _focoManual.requestFocus();
                  });
                },
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  isDense: false,
                  hintText: 'Código manual / lectora USB — Enter para agregar',
                  prefixIcon: const Icon(Icons.keyboard),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      final codigo = _entradaManual.text.trim();
                      if (codigo.isNotEmpty) _procesarCodigo(codigo);
                      _entradaManual.clear();
                    },
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _posiciones.isEmpty
              ? Center(
                  child: Text(
                    'Escanee un código o ingréselo arriba para comenzar',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.builder(
                  itemCount: _posiciones.length,
                  itemBuilder: (_, i) => _filaPosicion(_posiciones[i]),
                ),
        ),
      ],
    );
  }

  Widget _filaPosicion(Map<String, Object?> p) {
    final manual = p['origen'] == 'MANUAL';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ListTile(
        dense: false,
        onTap: () => _editarCantidad(p),
        title: Text(
          '${p['material_sap']}  |  ${_fmtNum(p['cantidad_sap'])} ${p['unidad_sap'] ?? ''}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              manual
                  ? 'QR: ${p['qr_leido']} — Sin equivalencia'
                  : '${p['descripcion'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: manual ? AppColors.rojoOscuro : AppColors.grisMedio,
              ),
            ),
            if ((p['texto_posicion'] ?? '').toString().isNotEmpty)
              Text(
                'Pos: ${p['texto_posicion']}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
          ],
        ),
        trailing: const Icon(
          Icons.edit_outlined,
          size: 22,
          color: AppColors.grisMedio,
        ),
      ),
    );
  }

  Future<void> _editarCantidad(Map<String, Object?> p) async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Modificar cantidad'),
              onTap: () => Navigator.pop(context, 'EDITAR'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.rojoOscuro,
              ),
              title: const Text(
                'Eliminar posición',
                style: TextStyle(color: AppColors.rojoOscuro),
              ),
              onTap: () => Navigator.pop(context, 'ELIMINAR'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == 'ELIMINAR') {
      await Db.eliminarPosicion(p['id'] as int);
      await _recargarPosiciones();
      return;
    }

    final eq = await Db.equivalencia((p['qr_leido'] ?? '') as String);
    if (!mounted) return;
    final resultado = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaCantidad(
        materialSap: p['material_sap'].toString(),
        descripcion: p['descripcion'].toString(),
        unidadLectura: ((eq?['unidad_lectura'] ?? p['unidad_lectura']) ?? '')
            .toString(),
        origenManual: p['origen'] == 'MANUAL',
        cantidadInicial: (p['cantidad_lectura'] as num?)?.toDouble() ?? 0,
        textoPosInicial: (p['texto_posicion'] ?? '').toString(),
      ),
    );
    if (resultado == null) return;
    await Db.actualizarCantidadPosicion(
      p['id'] as int,
      resultado['cantidad'] as double,
      textoPosicion: resultado['textoPosicion'] as String?,
    );
    await _recargarPosiciones();
  }

  Future<bool?> _confirmarSalir() async {
    if (_posiciones.isEmpty) {
      if (_opId != null) await Db.eliminarOperacionAbierta(_opId!);
      return true;
    }
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir sin cerrar?'),
        content: Text(
          'Tenés ${_posiciones.length} posición(es) cargadas.\n\n• GUARDAR deja el pick en Mis Picks para continuarlo después.\n• ABANDONAR lo elimina.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('SEGUIR'),
          ),
          OutlinedButton(
            onPressed: () async => Navigator.pop(ctx, true),
            child: const Text('ABANDONAR'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              _guardarBorrador();
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
  }

  static String _fmtNum(Object? n) {
    final d = double.tryParse(n.toString()) ?? 0;
    return d == d.truncateToDouble()
        ? d.toInt().toString()
        : d
              .toStringAsFixed(3)
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.$'), '');
  }
}

class _HojaCantidad extends StatefulWidget {
  final String materialSap;
  final String descripcion;
  final String unidadLectura;
  final bool origenManual;
  final double cantidadInicial;
  final String textoPosInicial;

  const _HojaCantidad({
    required this.materialSap,
    required this.descripcion,
    required this.unidadLectura,
    required this.origenManual,
    this.cantidadInicial = 0,
    this.textoPosInicial = '',
  });

  @override
  State<_HojaCantidad> createState() => _HojaCantidadState();
}

class _HojaCantidadState extends State<_HojaCantidad> {
  final _cantidad = TextEditingController();
  final _textoPos = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.cantidadInicial > 0) {
      _cantidad.text = widget.cantidadInicial.toString();
    }
    _textoPos.text = widget.textoPosInicial;
  }

  void _agregar() {
    final cant = double.tryParse(_cantidad.text.replaceAll(',', '.'));
    if (cant == null || cant <= 0) return;
    Navigator.pop(context, {
      'cantidad': cant,
      'textoPosicion': _textoPos.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: SafeArea(
        child: Container(
          color: AppColors.blanco,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.origenManual)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.rojoOscuro.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'MATERIAL SIN EQUIVALENCIA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.rojoOscuro,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              SelectableText(
                'Material ${widget.materialSap}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.descripcion,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              if (widget.unidadLectura.isNotEmpty)
                Text(
                  'Unidad de lectura: ${widget.unidadLectura}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _cantidad,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,7}[.,]?\d{0,3}'),
                  ),
                ],
                onSubmitted: (_) => _agregar(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText:
                      'CANTIDAD${widget.unidadLectura.isEmpty ? '' : ' (${widget.unidadLectura})'}',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textoPos,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Texto posición (opcional)',
                  isDense: true,
                  prefixIcon: Icon(Icons.notes, size: 20),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _agregar,
                icon: const Icon(Icons.add_circle_outline, size: 24),
                label: const Text('AGREGAR', style: TextStyle(fontSize: 17)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
