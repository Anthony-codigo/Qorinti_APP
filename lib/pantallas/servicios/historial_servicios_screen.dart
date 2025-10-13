// -----------------------------------------------------------------------------
// Archivo: historial_servicios_screen.dart
// Descripción general:
//   Pantalla que muestra el historial de servicios (viajes) del usuario,
//   ya sea como cliente o como conductor. Permite ver detalles,
//   generar comprobantes (demo), revisar calificaciones y compartir PDFs.
//
// Estructura principal:
//   - Consulta en tiempo real a Firestore (stream de servicios).
//   - Permite alternar entre vista como cliente o conductor.
//   - Muestra detalles de cada viaje, incluyendo estado, ruta, monto, fecha,
//     conductor/cliente asociado, comprobantes y calificación.
//
// Dependencias:
//   - Firebase (Auth, Firestore, Storage).
//   - Bloc (ServicioRepository).
//   - HTTP y Printing para PDF.
//   - SharePlus y UrlLauncher para compartir o abrir comprobantes.
// -----------------------------------------------------------------------------

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'calificar_servicio_screen.dart';
import 'package:app_qorinti/modelos/servicio.dart';
import 'package:app_qorinti/repos/servicio_repository.dart';
import 'package:app_qorinti/pantallas/servicios/comprobante_demo_screen.dart';

/// Pantalla de historial de servicios.
/// Permite al usuario revisar los viajes realizados o recibidos.
class HistorialServiciosScreen extends StatefulWidget {
  const HistorialServiciosScreen({super.key});

  @override
  State<HistorialServiciosScreen> createState() => _HistorialServiciosScreenState();
}

class _HistorialServiciosScreenState extends State<HistorialServiciosScreen> {
  // Formatos de fecha y moneda usados en la UI
  final _fmtFecha = DateFormat('dd/MM/yyyy HH:mm', 'es_PE');
  final _fmtMoneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/', decimalDigits: 2);

  // Control de vista: si se muestra como conductor o cliente
  bool _verComoConductor = false;
  bool _esConductor = false;

  // Cache local para no repetir consultas de nombres
  final Map<String, String> _cacheNombres = {};

  @override
  void initState() {
    super.initState();
    _cargarRol();
  }

  /// Determina si el usuario actual tiene rol de conductor o no.
  /// Esto define las opciones de visualización del historial.
  Future<void> _cargarRol() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('conductores').doc(uid).get();
      if (!mounted) return;
      setState(() {
        _esConductor = snap.exists;
        if (!_esConductor) _verComoConductor = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _esConductor = false;
        _verComoConductor = false;
      });
    }
  }

  /// Obtiene el nombre corto del usuario o conductor por su UID.
  /// Usa cache local para evitar múltiples lecturas a Firestore.
  Future<String> _getNombreCorto(String uid) async {
    if (uid.isEmpty) return '-';
    if (_cacheNombres.containsKey(uid)) return _cacheNombres[uid]!;
    String? nombre;

    // Buscar en colección "usuarios"
    final u = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (u.exists) {
      final m = u.data() ?? {};
      final dynamicN = (m['nombre'] ?? m['displayName'] ?? m['fullName']);
      nombre = dynamicN?.toString();
    }

    // Si no existe en usuarios, buscar en conductores
    if ((nombre == null || nombre.trim().isEmpty)) {
      final c = await FirebaseFirestore.instance.collection('conductores').doc(uid).get();
      if (c.exists) {
        final m = c.data() ?? {};
        nombre = (m['nombreCompleto'] ?? '${m['nombres'] ?? ''} ${m['apellidos'] ?? ''}')
            .toString()
            .trim();
      }
    }

    // Si no hay nombre, usar un fragmento del UID
    nombre = (nombre == null || nombre.isEmpty)
        ? uid.substring(0, uid.length.clamp(0, 6))
        : nombre;

    _cacheNombres[uid] = nombre;
    return nombre;
  }

  // ---------------------------------------------------------------------------
  // CONSTRUCCIÓN DE LA INTERFAZ PRINCIPAL
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // Si no hay sesión activa
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No hay sesión activa'),
          ),
        ),
      );
    }

    final repo = context.read<ServicioRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧾 Historial de servicios'),
        centerTitle: true,
        actions: [
          // Botón de recarga manual
          IconButton(
            tooltip: 'Recargar',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),

          // Toggle para alternar entre vista cliente/conductor
          if (_esConductor)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Como cliente'), icon: Icon(Icons.person_outline)),
                  ButtonSegment(value: true, label: Text('Como conductor'), icon: Icon(Icons.local_taxi)),
                ],
                selected: {_verComoConductor},
                onSelectionChanged: (s) => setState(() => _verComoConductor = s.first),
              ),
            )
          else
            // Mensaje fijo si no es conductor
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: const [
                  Icon(Icons.person_outline, size: 18, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('Historial de usuario'),
                ],
              ),
            ),
          const SizedBox(height: 8),

          // Contenido principal con StreamBuilder
          Expanded(
            child: StreamBuilder<List<Servicio>>(
              stream: repo.escucharHistorialServicios(uid, _verComoConductor),
              builder: (context, snap) {
                // Estado: cargando
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Estado: error
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Error cargando historial: ${snap.error}'),
                    ),
                  );
                }

                // Sin resultados
                final items = snap.data ?? const <Servicio>[];
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _verComoConductor
                            ? 'Aún no tienes viajes finalizados/cancelados como conductor.'
                            : 'Aún no tienes servicios finalizados/cancelados como cliente.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  );
                }

                // Lista de servicios
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = items[i];
                    final origen = s.ruta.isNotEmpty ? s.ruta.first.direccion : 'Origen';
                    final destino = s.ruta.isNotEmpty ? s.ruta.last.direccion : 'Destino';
                    final fechaLocal = (s.fechaFin ?? s.fechaSolicitud).toLocal();
                    final precio = s.precioFinal;

                    // Lógica para mostrar calificación
                    final int? valorResumen = _verComoConductor
                        ? s.calificacionUsuario
                        : s.calificacionConductor;
                    final bool finalizado = s.estado == EstadoServicio.finalizado;
                    final bool yaCalificado = valorResumen != null && valorResumen > 0;
                    final bool puedeCalificar = finalizado && !yaCalificado;

                    // Tarjeta principal de cada servicio
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título y estado
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _tituloTipo(s.tipoServicio),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                _chipEstado(s.estado),
                              ],
                            ),

                            const SizedBox(height: 6),

                            // Ruta (origen → destino)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.route, size: 18, color: Colors.grey),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$origen → $destino',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            // Fecha del viaje
                            Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  _fmtFecha.format(fechaLocal),
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),

                            // Precio si existe
                            if (precio != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.account_balance_wallet, size: 18, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(
                                    _fmtMoneda.format(precio),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 8),
                            // Mostrar cliente y conductor asociados
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (s.idUsuarioSolicitante.isNotEmpty)
                                  FutureBuilder<String>(
                                    future: _getNombreCorto(s.idUsuarioSolicitante),
                                    builder: (_, snap) => _miniChip(
                                      Icons.person,
                                      'Cliente: ${snap.data ?? '…'}',
                                    ),
                                  ),
                                if ((s.idConductor?.isNotEmpty ?? false))
                                  FutureBuilder<String>(
                                    future: _getNombreCorto(s.idConductor!),
                                    builder: (_, snap) => _miniChip(
                                      Icons.local_taxi,
                                      'Conductor: ${snap.data ?? '…'}',
                                    ),
                                  ),
                              ],
                            ),

                            // Bloque que muestra o genera el comprobante
                            _comprobanteBlock(s),

                            const SizedBox(height: 8),

                            // Sección de calificación (ver o dejar rating)
                            Row(
                              children: [
                                if (yaCalificado)
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: _ratingCompact(valorResumen),
                                    ),
                                  ),
                                if (puedeCalificar)
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.star_rate),
                                    label: const Text('Calificar'),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CalificarServicioScreen(
                                            idServicio: s.id!,
                                            esConductor: _verComoConductor,
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                else if (yaCalificado)
                                  TextButton.icon(
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text('Ver calificación'),
                                    onPressed: () => _verCalificacionDetalle(s),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _miniChip(Icons.badge, 'Servicio: ${s.id ?? '-'}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FUNCIONES DE CALIFICACIÓN Y DETALLES
  // ---------------------------------------------------------------------------

  /// Abre una hoja modal mostrando las estrellas y comentario de calificación.
  Future<void> _verCalificacionDetalle(Servicio s) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Buscar calificación en la colección 'calificaciones'
    final q = await FirebaseFirestore.instance
        .collection('calificaciones')
        .where('idServicio', isEqualTo: s.id)
        .where('deUsuarioId', isEqualTo: uid)
        .limit(1)
        .get();

    final data = q.docs.isNotEmpty ? q.docs.first.data() : null;
    final estrellas = (data?['estrellas'] as num?)?.toInt() ?? 0;
    final comentario = (data?['comentario'] as String?)?.trim();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tu calificación', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(children: _stars(estrellas)),
            const SizedBox(height: 12),
            if (comentario != null && comentario.isNotEmpty)
              Text(comentario)
            else
              const Text('Sin comentario.'),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MÉTODOS AUXILIARES PARA COMPROBANTES (URLs, DESCARGAS, GENERACIÓN)
  // ---------------------------------------------------------------------------

  /// Devuelve el primer campo no vacío de un mapa (útil para datos variables).
  String _firstNonEmpty(Map<String, dynamic> m, List<String> keys, {String def = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return def;
  }

  /// Devuelve una etiqueta limpia para el campo “emisor”.
  String _labelEmisor(dynamic v) {
    final s = (v ?? '').toString().toUpperCase().trim();
    if (s == 'CONDUCTOR') return 'Conductor (DEMO)';
    if (s == 'QORINTI')  return 'Qorinti (DEMO)';
    return s.isEmpty ? '—' : s;
  }

  /// Devuelve una etiqueta limpia para el tipo de comprobante.
  String _labelTipo(dynamic v) {
    final s = (v ?? '').toString().toUpperCase().trim();
    if (s == 'FACTURA') return 'Factura';
    if (s == 'BOLETA')  return 'Boleta';
    return s.isEmpty ? 'Comprobante' : s;
  }

  /// Convierte una referencia gs:// o ruta relativa en una URL HTTPS.
  Future<String?> _normalizeToHttps(String? urlOrPath) async {
    if (urlOrPath == null) return null;
    final v = urlOrPath.trim();
    if (v.isEmpty) return null;

    if (v.startsWith('http://') || v.startsWith('https://')) return v;

    // Si viene de Firebase Storage
    if (v.startsWith('gs://')) {
      try {
        final ref = FirebaseStorage.instance.refFromURL(v);
        return await ref.getDownloadURL();
      } catch (_) {
        return null;
      }
    }

    try {
      final ref = FirebaseStorage.instance.ref(v);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  /// Descarga y comparte el comprobante en formato PDF.
  Future<void> _downloadAndShare(String urlHttps, String fileName) async {
    try {
      final r = await http.get(Uri.parse(urlHttps));
      if (r.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final safe = (fileName.isEmpty ? 'Comprobante' : fileName).replaceAll('/', '-');
        final f = File('${dir.path}/$safe');
        await f.writeAsBytes(r.bodyBytes);
        await Share.shareXFiles([XFile(f.path)], text: 'Comprobante');
        return;
      }
    } catch (_) {}

    // Si no puede descargar, abre en navegador externo
    final uri = Uri.parse(urlHttps);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Intenta abrir el PDF externamente o mostrarlo embebido dentro de la app.
  Future<void> _viewPdfExternalOrInline(String urlHttps, {String? title}) async {
    final uri = Uri.parse(urlHttps);
    bool opened = false;

    // Intentar abrir con una app externa
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened) return;

    // Si no se pudo, abrir en vista interna (PdfPreview)
    try {
      final res = await http.get(uri);
      if (res.statusCode == 200 && mounted) {
        final bytes = res.bodyBytes;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(title ?? 'Comprobante')),
              body: PdfPreview(
                build: (format) async => bytes,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
              ),
            ),
          ),
        );
        return;
      }
    } catch (_) {}

    // Último intento: abrir con el navegador del sistema
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // MÉTODOS PARA LOCALIZAR COMPROBANTES (Firestore)
  // ---------------------------------------------------------------------------

  /// Busca el comprobante asociado a un servicio de manera flexible.
  /// Revisa múltiples campos o subcolecciones para distintos esquemas.
  Future<Map<String, dynamic>?> _findComprobanteFlexible(Servicio s, String uidActual) async {
    final doc = await FirebaseFirestore.instance.collection('servicios').doc(s.id).get();
    final data = doc.data() ?? {};

    // Intentar encontrar comprobante DEMO
    final demo = data['comprobanteDemo'];
    if (demo is Map<String, dynamic>) {
      final url = _firstNonEmpty(demo, ['urlPdf','url','downloadUrl','fileUrl','archivo','path','ruta','ref']);
      if (url.isNotEmpty) return demo;
    }

    // Buscar por posibles claves según el rol (cliente/conductor)
    final clavesPorRol = _verComoConductor
        ? ['comprobanteConductor', 'comprobante', 'recibo', 'factura', 'boleta']
        : ['comprobanteCliente', 'comprobante', 'recibo', 'factura', 'boleta'];

    for (final k in clavesPorRol) {
      final v = data[k];
      if (v is Map<String, dynamic>) {
        final url = _firstNonEmpty(v, ['urlPdf','url','downloadUrl','fileUrl','archivo','path','ruta','ref']);
        if (url.isNotEmpty) return v;
      }
    }

    // Buscar dentro de la subcolección 'comprobantes'
    final col = FirebaseFirestore.instance.collection('servicios').doc(s.id).collection('comprobantes');

    var q = await col
        .where('destinatarioId', isEqualTo: uidActual)
        .orderBy('creadoEn', descending: true)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) return q.docs.first.data();

    // Buscar según rol
    final rolBuscado = _verComoConductor ? 'conductor' : 'cliente';
    for (final campo in ['rol', 'para', 'destinatario']) {
      q = await col.where(campo, isEqualTo: rolBuscado).orderBy('creadoEn', descending: true).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.data();
    }

    // Buscar últimos registros si no hay coincidencias exactas
    q = await col.orderBy('creadoEn', descending: true).limit(2).get();
    final esParte = (s.idUsuarioSolicitante == uidActual) || (s.idConductor == uidActual);
    if (q.docs.length == 1 && esParte) return q.docs.first.data();

    if (q.docs.isNotEmpty) {
      for (final d in q.docs) {
        final m = d.data();
        final dest = (m['destinatarioId'] ?? '').toString();
        if (dest.isNotEmpty && (dest == s.idUsuarioSolicitante || dest == s.idConductor)) {
          return m;
        }
      }
    }

    if (esParte) {
      final q2 = await col.orderBy('creadoEn', descending: true).limit(1).get();
      if (q2.docs.isNotEmpty) return q2.docs.first.data();
    }

    if (kDebugMode) {
      debugPrint('[Historial] Sin comprobante para servicio ${s.id} (rol=$_verComoConductor)');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // GENERACIÓN DE COMPROBANTE DEMO
  // ---------------------------------------------------------------------------

  /// Carga los datos de empresa del conductor (RUC, razón social, dirección).
  Future<Map<String, String>?> _cargarEmpresaDelConductor(String uid) async {
    try {
      final fs = FirebaseFirestore.instance;

      // Buscar primero en "usuarios"
      final uDoc = await fs.collection('usuarios').doc(uid).get();
      Map<String, dynamic> u = uDoc.data() ?? const {};
      final rucU = (u['rucEmpresa'] ?? u['ruc'] ?? '').toString().trim();
      final razonU = (u['razonEmpresa'] ?? u['razonSocial'] ?? '').toString().trim();
      final dirU = (u['direccionEmpresa'] ?? u['direccionFiscal'] ?? u['direccion'] ?? '').toString().trim();
      if (rucU.length == 11 && razonU.isNotEmpty) {
        return {'ruc': rucU, 'razon': razonU, 'direccion': dirU};
      }

      // Si no, buscar en "conductores"
      final cDoc = await fs.collection('conductores').doc(uid).get();
      Map<String, dynamic> c = cDoc.data() ?? const {};
      final rucC = (c['rucEmpresa'] ?? c['ruc'] ?? '').toString().trim();
      final razonC = (c['razonEmpresa'] ?? c['razonSocial'] ?? '').toString().trim();
      final dirC = (c['direccionEmpresa'] ?? c['direccionFiscal'] ?? c['direccion'] ?? '').toString().trim();
      if (rucC.length == 11 && razonC.isNotEmpty) {
        return {'ruc': rucC, 'razon': razonC, 'direccion': dirC};
      }
    } catch (_) {}
    return null;
  }

  /// Botón que permite generar comprobante DEMO (solo conductor y servicio finalizado).
  Widget _btnGenerarDemo(Servicio s) {
    if (!_verComoConductor || s.estado != EstadoServicio.finalizado) {
      return const SizedBox.shrink();
    }
    if (s.id == null || s.id!.isEmpty) return const SizedBox.shrink();

    final double total = s.precioFinal ?? s.precioEstimado ?? 0.0;
    final DateTime fecha = s.fechaFin ?? s.fechaSolicitud;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.receipt_long),
          label: const Text('Generar comprobante (demo)'),
          onPressed: () async {
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            Map<String, String>? empresa = uid.isEmpty ? null : await _cargarEmpresaDelConductor(uid);

            final bool clienteTieneEmpresa = empresa != null;

            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ComprobanteDemoScreen(
                  idServicio: s.id!,
                  total: total,
                  fecha: fecha,
                  clienteTieneEmpresa: clienteTieneEmpresa,
                  empresaPreset: empresa,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Muestra un bloque visual con el comprobante del servicio (si existe)
  /// o el botón para generarlo en modo demo.
  Widget _comprobanteBlock(Servicio s) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<Map<String, dynamic>?>(
      future: _findComprobanteFlexible(s, uid),
      builder: (_, snap) {
        if (!snap.hasData || snap.data == null) {
          return _btnGenerarDemo(s);
        }

        final comp = snap.data!;
        final rawRef = _firstNonEmpty(comp, ['urlPdf','url','downloadUrl','fileUrl','archivo','path','ruta','ref']);
        if (rawRef.isEmpty) return _btnGenerarDemo(s);

        final tipo   = _labelTipo(comp['tipo']);
        final emisor = _labelEmisor(comp['emisor']);
        final serieN = _firstNonEmpty(comp, ['serieNumero', 'serie', 'numero', 'nro'], def: '—');

        return FutureBuilder<String?>( // Normaliza y carga la URL del PDF
          future: _normalizeToHttps(rawRef),
          builder: (_, sUrl) {
            if (!sUrl.hasData || sUrl.data == null || sUrl.data!.isEmpty) {
              if (kDebugMode) {
                debugPrint('[Historial] No se pudo normalizar URL/ruta de comprobante: $rawRef');
              }
              return _btnGenerarDemo(s);
            }
            final urlHttps = sUrl.data!;

            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, color: Colors.brown),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comprobante ($tipo)', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('$serieN  •  Emisor: $emisor',
                              style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await _viewPdfExternalOrInline(urlHttps, title: serieN);
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Ver'),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () async {
                        final nombre = '${serieN.isNotEmpty ? serieN : 'Comprobante'}.pdf';
                        await _downloadAndShare(urlHttps, nombre);
                      },
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Guardar'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ELEMENTOS VISUALES AUXILIARES
  // ---------------------------------------------------------------------------

  /// Devuelve el texto legible para el tipo de servicio.
  String _tituloTipo(TipoServicio t) {
    switch (t) {
      case TipoServicio.carga_ligera:
        return 'Carga ligera';
      case TipoServicio.carga_pesada:
        return 'Carga pesada';
      case TipoServicio.mudanza:
        return 'Mudanza';
      case TipoServicio.taxi:
        return 'Pasajeros';
    }
  }

  /// Muestra el estado del servicio en formato Chip.
  Widget _chipEstado(EstadoServicio e) {
    Color bg;
    String label;
    switch (e) {
      case EstadoServicio.finalizado:
        bg = Colors.grey;
        label = 'FINALIZADO';
        break;
      case EstadoServicio.cancelado:
        bg = Colors.red;
        label = 'CANCELADO';
        break;
      case EstadoServicio.aceptado:
        bg = Colors.amber;
        label = 'ACEPTADO';
        break;
      case EstadoServicio.en_curso:
        bg = Colors.green;
        label = 'EN CURSO';
        break;
      case EstadoServicio.pendiente_ofertas:
        bg = Colors.blueGrey;
        label = 'PENDIENTE';
        break;
    }
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  /// Crea un chip pequeño para mostrar información secundaria (cliente, id, etc.).
  Widget _miniChip(IconData icon, String text) {
    return Chip(
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(text, overflow: TextOverflow.ellipsis),
    );
  }

  /// Muestra las estrellas de calificación en formato compacto.
  Widget _ratingCompact(int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: _stars(value)),
    );
  }

  /// Genera la lista de estrellas llenas/vacías según el valor recibido.
  List<Widget> _stars(int value) {
    return List.generate(5, (i) {
      final filled = (i + 1) <= value;
      return Icon(
        filled ? Icons.star : Icons.star_border,
        size: 18,
        color: filled ? Colors.amber : Colors.grey,
      );
    });
  }
}
