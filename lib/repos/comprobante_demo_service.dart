// Servicio para la generación de comprobantes de demostración (boleta o factura) para los servicios Qorinti.
// 
// Este módulo crea un comprobante PDF (sin validez tributaria) para efectos de demostración o pruebas internas,
// vinculando datos del emisor (empresa o conductor) y del receptor (cliente).
// El comprobante se genera dinámicamente, se almacena en Firebase Storage y se registra en Firestore.
// 
// Características técnicas:
// - Construcción del PDF con la librería `pdf` (widgets personalizados).
// - Uso de Firestore para mantener correlativos por serie (colección `demo_counters`).
// - Validaciones de emisor y receptor con tolerancia a datos faltantes.
// - Integración con Firebase Storage y Firestore para persistencia y trazabilidad del comprobante.
// - Control de errores y tiempos de espera (timeouts) con manejo de excepciones específicas.

import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:app_qorinti/modelos/comprobante_demo.dart' as cd;

class _EmisorReal {
  final String nombre;
  final String docTipo;   // Tipo de documento: RUC, DNI o DEMO
  final String doc;       // Número de documento
  final String direccion;

  const _EmisorReal({
    required this.nombre,
    required this.docTipo,
    required this.doc,
    required this.direccion,
  });
}

class ComprobanteDemoService {
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  // Formatea valores numéricos a dos decimales
  static double _r2(num v) => double.parse(v.toDouble().toStringAsFixed(2));

  // Devuelve una cadena no vacía o un valor por defecto
  static String _nz(String? s, [String fallback = '-']) {
    final v = (s ?? '').trim();
    return v.isEmpty ? fallback : v;
  }

  // Limpia el mapa del receptor eliminando claves o valores vacíos
  static Map<String, String> _sanitizeReceptor(Map<String, String> raw) {
    final m = <String, String>{};
    for (final e in raw.entries) {
      final k = e.key.trim();
      final v = e.value.trim();
      if (k.isNotEmpty && v.isNotEmpty) m[k] = v;
    }
    return m;
  }

  /// Determina los datos reales del emisor (empresa o conductor) a partir del servicio.
  /// Si no se encuentra información válida, retorna valores por defecto de tipo "DEMO".
  static Future<_EmisorReal> _resolverEmisorDesdeServicio(String idServicio) async {
    final sDoc = await _db.collection('servicios').doc(idServicio).get();
    final s = sDoc.data() ?? {};

    final String? idEmpresa = s['idEmpresa'] as String?;
    final String? idConductor = s['idConductor'] as String?;

    // Caso: servicio emitido por una empresa registrada
    if (idEmpresa != null && idEmpresa.isNotEmpty) {
      final eDoc = await _db.collection('empresas').doc(idEmpresa).get();
      final e = eDoc.data() ?? {};

      final nombre = _nz((e['razonSocial'] ?? e['nombreComercial'])?.toString(), 'EMPRESA');
      final ruc = _nz(e['ruc']?.toString(), '');
      final dir = _nz((e['direccionFiscal'] ?? e['direccion'])?.toString());

      return _EmisorReal(
        nombre: nombre,
        docTipo: ruc.isNotEmpty ? 'RUC' : 'DEMO',
        doc: ruc.isNotEmpty ? ruc : '-',
        direccion: dir,
      );
    }

    // Caso: servicio emitido por un conductor independiente
    if (idConductor != null && idConductor.isNotEmpty) {
      final cDoc = await _db.collection('conductores').doc(idConductor).get();
      final c = cDoc.data() ?? {};

      String nombre = _nz(
        (c['nombreCompleto'] ??
                '${_nz(c['nombres']?.toString(), '')} ${_nz(c['apellidos']?.toString(), '')}')
            .toString(),
        '',
      ).trim();

      if (nombre.isEmpty) {
        final uDoc = await _db.collection('usuarios').doc(idConductor).get();
        final u = uDoc.data() ?? {};
        nombre = _nz(u['nombre']?.toString(), 'Conductor');
      }

      final ruc = _nz(c['ruc']?.toString(), '');
      final dni = _nz(c['dni']?.toString(), '');
      final dir = _nz((c['direccionFiscal'] ?? c['direccion'])?.toString());

      final docTipo = ruc.isNotEmpty ? 'RUC' : (dni.isNotEmpty ? 'DNI' : 'DEMO');
      final doc = ruc.isNotEmpty ? ruc : (dni.isNotEmpty ? dni : '-');

      return _EmisorReal(
        nombre: nombre,
        docTipo: docTipo,
        doc: doc,
        direccion: dir,
      );
    }

    // Caso: datos inexistentes o servicio incompleto
    return const _EmisorReal(
      nombre: 'EMISOR (DEMO)',
      docTipo: 'DEMO',
      doc: '-',
      direccion: '-',
    );
  }

  /// Genera y adjunta un comprobante de demostración (PDF) al servicio especificado.
  /// El documento se guarda en Firebase Storage y se actualiza en Firestore.
  static Future<void> generateAndAttach({
    required String idServicio,
    required cd.EmisorDemo emisor,
    required cd.TipoComprobanteDemo tipo,
    required double total,
    required DateTime fecha,
    required Map<String, String> receptor,
  }) async {
    try {
      // === 1) Identificación del emisor ===
      _EmisorReal emisorReal = await _resolverEmisorDesdeServicio(idServicio);
      if (emisorReal.docTipo == 'DEMO' && emisorReal.nombre == 'EMISOR (DEMO)') {
        emisorReal = const _EmisorReal(
          nombre: 'CONDUCTOR SIN DATOS',
          docTipo: 'DEMO',
          doc: '-',
          direccion: '-',
        );
      }

      // === 2) Definición de numeración y formato ===
      final esFactura = tipo == cd.TipoComprobanteDemo.factura;
      final serie = esFactura ? 'FDEMO' : 'BDEMO';
      final numero = await _siguienteNumeroDemo(serie);
      final serieNumero = '$serie-$numero';

      final dfFecha = DateFormat('dd/MM/yyyy HH:mm', 'es_PE');
      final dfMoneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/.', decimalDigits: 2);

      final totalR = _r2(total);
      final subtotal = _r2(totalR / 1.18);
      final igv = _r2(totalR - subtotal);
      final rec = _sanitizeReceptor(receptor);

      // === 3) Construcción del documento PDF ===
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageTheme: _pageThemeWithWatermark(),
          build: (context) => [
            // Encabezado: Emisor y tipo de comprobante
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        emisorReal.nombre,
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('${emisorReal.docTipo}: ${emisorReal.doc}'),
                      pw.Text(emisorReal.direccion),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey700, width: 1),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        esFactura ? 'FACTURA' : 'BOLETA',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text('N°: $serieNumero', style: const pw.TextStyle(fontSize: 12)),
                      pw.Text('Fecha: ${dfFecha.format(fecha)}',
                          style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Datos del cliente
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Cliente', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  if (esFactura) ...[
                    pw.Text('RUC: ${_nz(rec['ruc'])}'),
                    pw.Text('Razón Social: ${_nz(rec['razon'])}'),
                    pw.Text('Dirección: ${_nz(rec['direccion'])}'),
                  ] else ...[
                    pw.Text('Nombre: ${_nz(rec['nombre'])}'),
                    if (_nz(rec['dni'], '').isNotEmpty) pw.Text('DNI: ${rec['dni']}'),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Detalle del servicio
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(6),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _cellHeader('Descripción'),
                    _cellHeader('Cant.'),
                    _cellHeader('P. Unit.'),
                    _cellHeader('Importe'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cell('Servicio de transporte'),
                    _cell('1'),
                    _cell(dfMoneda.format(totalR)),
                    _cell(dfMoneda.format(totalR)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),

            // Totales
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.SizedBox(
                  width: 240,
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
                    children: [
                      _rowTotal('Subtotal', dfMoneda.format(subtotal)),
                      _rowTotal('IGV (18%)', dfMoneda.format(igv)),
                      _rowTotal('Total', dfMoneda.format(totalR), bold: true),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Comprobante generado automáticamente por Qorinti.',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
      );

      // === 4) Guardado en Storage y Firestore ===
      final Uint8List bytes = await pdf.save();
      final path = 'comprobantes_demo/$idServicio/$serieNumero.pdf';
      final ref = _storage.ref().child(path);
      await ref
          .putData(bytes, SettableMetadata(contentType: 'application/pdf'))
          .timeout(const Duration(seconds: 30));
      final url = await ref.getDownloadURL().timeout(const Duration(seconds: 15));

      // Actualiza el documento del servicio con los datos del comprobante
      final docRef = _db.collection('servicios').doc(idServicio);
      final update = <String, dynamic>{
        'comprobanteDemo': {
          'emisor': 'CONDUCTOR',
          'tipo': esFactura ? 'FACTURA' : 'BOLETA',
          'serie': serie,
          'numero': numero,
          'serieNumero': serieNumero,
          'total': totalR,
          'fecha': Timestamp.fromDate(fecha),
          'urlPdf': url,
          'emisorNombre': emisorReal.nombre,
          'emisorDocTipo': emisorReal.docTipo,
          'emisorDoc': emisorReal.doc,
          'emisorDireccion': emisorReal.direccion,
          if (esFactura) 'ruc': _nz(rec['ruc'], '-'),
          if (esFactura) 'razonSocial': _nz(rec['razon'], '-'),
          if (esFactura) 'direccionFiscal': _nz(rec['direccion'], '-'),
          if (!esFactura) 'nombreCliente': _nz(rec['nombre'], '-'),
          if (!esFactura && _nz(rec['dni'], '').isNotEmpty) 'dniCliente': rec['dni'],
        },
        'comprobanteCliente': {
          'tipo': esFactura ? 'FACTURA' : 'BOLETA',
          'serieNumero': serieNumero,
          'total': totalR,
          'fecha': Timestamp.fromDate(fecha),
          'urlPdf': url,
        },
        'tipoComprobante': esFactura ? 'FACTURA' : 'BOLETA',
        'fechaActualizacion': FieldValue.serverTimestamp(),
      };

      await docRef.update(update).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw 'Tiempo de espera excedido (Storage o Firestore). Verifica conexión y permisos.';
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw 'Permiso denegado al escribir en Storage/Firestore.';
      }
      if (e.code == 'unauthenticated') {
        throw 'No autenticado. Inicia sesión nuevamente.';
      }
      throw 'Firebase error: ${e.message ?? e.code}';
    } catch (e) {
      throw 'Fallo generando o guardando el comprobante: $e';
    }
  }

  // ============================================================
  // Widgets y helpers para construcción del PDF
  // ============================================================

  static pw.TableRow _rowTotal(String k, String v, {bool bold = false}) {
    final s = pw.TextStyle(
      fontSize: 12,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.TableRow(children: [
      pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Text(k, style: s)),
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        alignment: pw.Alignment.centerRight,
        child: pw.Text(v, style: s),
      ),
    ]);
  }

  static pw.Widget _cellHeader(String t) => pw.Container(
        padding: const pw.EdgeInsets.all(8),
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _cell(String t) => pw.Container(
        padding: const pw.EdgeInsets.all(8),
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(t),
      );

  /// Define el tema de página del PDF con marca de agua "DEMO – SIN VALIDEZ TRIBUTARIA".
  static pw.PageTheme _pageThemeWithWatermark() {
    return pw.PageTheme(
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      buildBackground: (context) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Center(
          child: pw.Transform.rotate(
            angle: -0.4,
            child: pw.Opacity(
              opacity: 0.07,
              child: pw.Text(
                'DEMO – SIN VALIDEZ TRIBUTARIA',
                style: pw.TextStyle(
                  fontSize: 48,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.red900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Controla la numeración secuencial por serie de comprobantes de demostración.
  /// Usa una transacción para garantizar atomicidad en incrementos concurrentes.
  static Future<String> _siguienteNumeroDemo(String serie) async {
    final docRef = _db.collection('demo_counters').doc(serie);
    String numeroStr = '000001';

    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      int next = 1;
      if (snap.exists) {
        final last = (snap.data()!['last'] as num?)?.toInt() ?? 0;
        next = last + 1;
      }
      tx.set(docRef, {'last': next}, SetOptions(merge: true));
      numeroStr = next.toString().padLeft(6, '0');
    });

    return numeroStr;
  }
}
