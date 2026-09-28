import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../data/db.dart';
import 'escaneo_screen.dart';

class NuevoPickScreen extends StatefulWidget {
  const NuevoPickScreen({super.key});
  @override
  State<NuevoPickScreen> createState() => _NuevoPickScreenState();
}

class _NuevoPickScreenState extends State<NuevoPickScreen> {
  final _orden = TextEditingController();
  final _cabecera = TextEditingController();
  List<Map<String, Object?>> _cecos = [];
  List<Map<String, Object?>> _almacenes = [];
  List<Map<String, Object?>> _clases = [];
  List<Map<String, Object?>> _centros = [];
  String? _cecoSel;
  String? _almacenSel;
  String? _claseSel;
  String? _centroSel;
  bool _cargando = true;
  bool _reservando = false;
  String? _errorCarga;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _errorCarga = null;
      });
    }

    try {
      await Db.abrir().timeout(const Duration(seconds: 5));
      final resultados = await Future.wait<Object?>([
        _conLimite(Db.cecos(), <Map<String, Object?>>[]),
        _conLimite(Db.almacenes(), <Map<String, Object?>>[]),
        _conLimite(Db.clasesMovimiento(), <Map<String, Object?>>[]),
        _conLimite(Db.centros(), <Map<String, Object?>>[]),
        _conLimite(Db.parametros(), <String, String>{}),
      ]);
      final cecos = _normalizar(
        resultados[0] as List<Map<String, Object?>>,
        'ceco',
      );
      final almacenes = _normalizar(
        resultados[1] as List<Map<String, Object?>>,
        'codigo',
      );
      final clases = _normalizar(
        resultados[2] as List<Map<String, Object?>>,
        'codigo',
      );
      final centros = _normalizar(
        resultados[3] as List<Map<String, Object?>>,
        'codigo',
      );
      final params = resultados[4] as Map<String, String>;

      cecos.sort(
        (a, b) => (a['ceco'] as String).compareTo(b['ceco'] as String),
      );
      almacenes.sort(
        (a, b) => (a['codigo'] as String).compareTo(b['codigo'] as String),
      );
      clases.sort(
        (a, b) => (a['codigo'] as String).compareTo(b['codigo'] as String),
      );
      centros.sort(
        (a, b) => (a['codigo'] as String).compareTo(b['codigo'] as String),
      );

      if (!mounted) return;
      setState(() {
        _cecos = cecos;
        _almacenes = almacenes;
        _clases = clases;
        _centros = centros;
        _orden.text = 'Se asigna al comenzar';

        if (almacenes.isEmpty) {
          _almacenSel = null;
        } else {
          final a1 = almacenes.where(
            (a) => (a['codigo'] as String).toUpperCase() == 'A1',
          );
          _almacenSel =
              (a1.isNotEmpty ? a1.first : almacenes.first)['codigo'] as String;
        }

        final defClase = params['claseMovimiento'] ?? '201';
        _claseSel = clases.any((c) => c['codigo'] == defClase)
            ? defClase
            : (clases.isNotEmpty ? clases.first['codigo'] as String : '201');
        final defCentro = params['centro'] ?? '1001';
        _centroSel = centros.any((c) => c['codigo'] == defCentro)
            ? defCentro
            : (centros.isNotEmpty ? centros.first['codigo'] as String : '1001');
        if (cecos.isEmpty || almacenes.isEmpty) {
          _errorCarga = 'No hay datos maestros disponibles. Sincronice o reintente la carga.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorCarga =
              'No se pudo abrir la base local. Reintente en unos segundos.';
        });
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<T> _conLimite<T>(Future<T> consulta, T valorAlternativo) async {
    try {
      return await consulta.timeout(const Duration(seconds: 5));
    } catch (_) {
      return valorAlternativo;
    }
  }

  List<Map<String, Object?>> _normalizar(
    List<Map<String, Object?>> filas,
    String clave,
  ) {
    return filas
        .map(
          (fila) => <String, Object?>{
            ...fila,
            clave: fila[clave]?.toString().trim() ?? '',
            'descripcion': fila['descripcion']?.toString() ?? '',
          },
        )
        .where((fila) => (fila[clave] as String).isNotEmpty)
        .toList();
  }

  Future<void> _elegirCeco() async {
    final sel = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SelectorCeco(cecos: _cecos),
    );
    if (sel != null) setState(() => _cecoSel = sel);
  }

  Future<void> _continuar() async {
    if (_cecoSel == null) {
      _aviso('Seleccione el Centro de Costo');
      return;
    }
    if (_almacenSel == null) {
      _aviso('Seleccione el Almacén');
      return;
    }
    if (_reservando) return;
    setState(() => _reservando = true);
    try {
      final id = Db.nuevoIdOperacion();
      final respuesta = await Api.post('/api/operaciones/reservar', {
        'id': id,
      }, token: Config.token);
      final orden = respuesta is Map
          ? respuesta['orden']?.toString() ?? ''
          : '';
      if (orden.isEmpty) {
        throw ApiException('El servidor no asignó el número de pick');
      }
      if (!mounted) return;
      _orden.text = orden;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EscaneoScreen(
            orden: orden,
            ceco: _cecoSel!,
            almacen: _almacenSel!,
            claseMovimiento: _claseSel ?? '201',
            centro: _centroSel ?? '1001',
            textoCabecera: _cabecera.text.trim(),
            opIdReservado: id,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        if (e.codigo == 401 || e.mensaje.toLowerCase().contains('no autorizado')) {
          _aviso('Sesión vencida. Vuelva a iniciar sesión con su PIN.');
        } else {
          _aviso('${e.mensaje}. No se puede iniciar el pick sin servidor.');
        }
      }
    } finally {
      if (mounted) setState(() => _reservando = false);
    }
  }

  void _aviso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.rojoOscuro),
    );
  }

  @override
  void dispose() {
    _orden.dispose();
    _cabecera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NUEVO PICK')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_cargando) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
          ],
          if (_errorCarga != null) ...[
            Card(
              color: const Color(0xFFFFEBEE),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.rojoOscuro,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_errorCarga!)),
                    TextButton(
                      onPressed: _cargando ? null : _cargarDatos,
                      child: const Text('REINTENTAR'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 4, height: 18, color: AppColors.rojo),
                      const SizedBox(width: 8),
                      const Text(
                        'DATOS GENERALES',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _orden,
                    readOnly: true,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Orden (auto)',
                      prefixIcon: Icon(Icons.confirmation_number),
                      suffixIcon: Icon(Icons.lock_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: _elegirCeco,
                    borderRadius: BorderRadius.circular(10),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Centro de Costo *',
                        prefixIcon: const Icon(Icons.account_tree_outlined),
                        suffixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: AppColors.blanco,
                      ),
                      child: Text(
                        _cecoTexto(),
                        style: TextStyle(
                          fontSize: 16,
                          color: _cecoSel == null
                              ? Colors.grey.shade600
                              : AppColors.texto,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_almacenSel),
                    initialValue: _almacenSel,
                    items: _almacenes
                        .map(
                          (a) => DropdownMenuItem(
                            value: a['codigo'] as String,
                            child: Text(
                              '${a['codigo']} - ${a['descripcion']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _almacenSel = v),
                    decoration: const InputDecoration(
                      labelText: 'Almacén',
                      prefixIcon: Icon(Icons.warehouse_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _cabecera,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Texto cabecera (opcional)',
                      prefixIcon: Icon(Icons.notes),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              key: ValueKey(_claseSel),
              initialValue: _claseSel,
              items:
                  (_clases.isNotEmpty
                          ? _clases
                          : [
                              {
                                'codigo': '201',
                                'descripcion': 'SM para centro coste',
                              },
                            ])
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['codigo'] as String,
                          child: Text(
                            '${c['codigo']} - ${c['descripcion']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (v) => setState(() => _claseSel = v),
              decoration: const InputDecoration(
                labelText: 'Clase de movimiento',
                prefixIcon: Icon(Icons.swap_horiz),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              key: ValueKey(_centroSel),
              initialValue: _centroSel,
              items:
                  (_centros.isNotEmpty
                          ? _centros
                          : [
                              {
                                'codigo': '1001',
                                'descripcion': 'Planta Gorina',
                              },
                            ])
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['codigo'] as String,
                          child: Text(
                            '${c['codigo']} - ${c['descripcion']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (v) => setState(() => _centroSel = v),
              decoration: const InputDecoration(
                labelText: 'Centro',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _cargando || _reservando ? null : _continuar,
            icon: _reservando
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_scanner, size: 28),
            label: Text(
              _reservando ? 'RESERVANDO NÚMERO...' : 'COMENZAR A ESCANEAR',
              style: const TextStyle(fontSize: 19),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  String _cecoTexto() {
    if (_cecoSel == null) return 'Seleccionar...';
    final c = _cecos.where((x) => x['ceco'] == _cecoSel).toList();
    if (c.isEmpty) return _cecoSel!;
    return '$_cecoSel - ${c.first['descripcion']}';
  }
}

class _SelectorCeco extends StatefulWidget {
  final List<Map<String, Object?>> cecos;
  const _SelectorCeco({required this.cecos});
  @override
  State<_SelectorCeco> createState() => __SelectorCecoState();
}

class __SelectorCecoState extends State<_SelectorCeco> {
  String _filtro = '';

  @override
  Widget build(BuildContext context) {
    final lista = widget.cecos.where((c) {
      if (_filtro.isEmpty) return true;
      final t = '${c['ceco']} ${c['descripcion']}'.toLowerCase();
      return t.contains(_filtro.toLowerCase());
    }).toList();
    return SafeArea(
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _filtro = v),
                decoration: const InputDecoration(
                  labelText: 'Buscar centro de costo',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final c = lista[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${c['ceco']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(c['descripcion'].toString()),
                    trailing: const Icon(
                      Icons.check_circle_outline,
                      color: AppColors.grisMedio,
                    ),
                    onTap: () => Navigator.pop(context, c['ceco'] as String),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
