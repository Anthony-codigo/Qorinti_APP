// -----------------------------------------------------------------------------
// Archivo: comprobante_demo_pdf.dart (ejemplo)
// Descripción:
//   Genera un comprobante PDF de demostración (sin validez tributaria) usando
//   los paquetes `pdf` y `printing`. Incluye marca de agua, encabezado de emisor,
//   datos opcionales del cliente y un bloque de totales.
// Notas:
//   - Este documento es solo ilustrativo. No cumple requisitos tributarios.
//   - Requiere fuentes de Google a través de PdfGoogleFonts (descarga en runtime).
// -----------------------------------------------------------------------------

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Construye un PDF de comprobante en modo DEMO y devuelve los bytes.
///
/// Parámetros requeridos:
/// - [emisorNombre], [emisorDocTipo], [emisorDoc]: datos del emisor mostrados en el encabezado.
/// - [tipo]: tipo de comprobante (ej. "Boleta", "Factura") solo a título demostrativo.
/// - [subtotal], [igv], [total]: montos numéricos a mostrar.
///
/// Parámetros opcionales:
/// - [clienteNombre], [clienteDoc]: datos del cliente; si están vacíos no se renderiza el bloque.
///
/// Retorna:
/// - [Uint8List] con el contenido PDF listo para guardar/imprimir/compartir.
///
/// Consideraciones:
/// - Usa `PdfGoogleFonts.robotoRegular/robotoBold()` para tipografías.
/// - Agrega marca de agua diagonal "DEMO SIN VALIDEZ TRIBUTARIA".
Future<Uint8List> buildComprobanteDemoPdf({
  required String emisorNombre,
  required String emisorDocTipo,
  required String emisorDoc,
  required String tipo,         // Etiqueta del tipo de comprobante (no vinculante)
  String? clienteNombre,
  String? clienteDoc,
  required double subtotal,
  required double igv,
  required double total,
}) async {
  // Documento PDF en memoria
  final pdf = pw.Document();

  // Tema de página: tamaño A4, márgenes, tipografías, y fondo con marca de agua
  final theme = pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    theme: pw.ThemeData.withFont(
      base: await PdfGoogleFonts.robotoRegular(),
      bold: await PdfGoogleFonts.robotoBold(),
    ),
    // Fondo: marca de agua diagonal con baja opacidad
    buildBackground: (context) => pw.FullPage(
      ignoreMargins: true,
      child: pw.Center(
        child: pw.Transform.rotate(
          angle: -0.4,
          child: pw.Opacity(
            opacity: 0.08,
            child: pw.Text(
              'DEMO SIN VALIDEZ TRIBUTARIA',
              textAlign: pw.TextAlign.center,
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

  // Página principal con encabezado, bloque de cliente (opcional) y totales
  pdf.addPage(
    pw.Page(
      pageTheme: theme,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Encabezado: tipo (DEMO) + datos del emisor + sello "sin validez"
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('$tipo (DEMO)', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Emisor: $emisorNombre'),
                  pw.Text('$emisorDocTipo: $emisorDoc'),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text('SIN VALIDEZ TRIBUTARIA', style: const pw.TextStyle(fontSize: 10)),
              ),
            ],
          ),

          pw.SizedBox(height: 16),

          // Bloque de cliente (se muestra solo si hay datos)
          if ((clienteNombre?.trim().isNotEmpty ?? false) || (clienteDoc?.trim().isNotEmpty ?? false))
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (clienteNombre != null && clienteNombre.trim().isNotEmpty)
                    pw.Text('Cliente: $clienteNombre'),
                  if (clienteDoc != null && clienteDoc.trim().isNotEmpty)
                    pw.Text('Documento: $clienteDoc'),
                ],
              ),
            ),

          pw.SizedBox(height: 16),

          // Totales (líneas clave-valor y separadores)
          pw.Divider(),
          _kv('Subtotal', _soles(subtotal)),
          _kv('IGV (18%)', _soles(igv)),
          pw.Divider(),
          _kv('TOTAL', _soles(total), bold: true, big: true),

          pw.SizedBox(height: 8),
          // Leyenda legal aclaratoria (DEMO)
          pw.Text(
            'Este comprobante es una simulación generada por Qorinti (DEMO). No tiene validez tributaria.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );

  // Retorna los bytes del PDF listo para uso
  return pdf.save();
}

/// Renderiza una fila "clave: valor" con estilos opcionales.
///
/// Parámetros:
/// - [k]: etiqueta de la clave (ej. "Subtotal").
/// - [v]: valor ya formateado (ej. "S/ 100.00").
/// - [bold]: si true, aplica negrita.
/// - [big]: si true, incrementa tamaño de fuente (para resaltar totales).
pw.Widget _kv(String k, String v, {bool bold = false, bool big = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 3),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(k, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      pw.Text(
        v,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: big ? 14 : 12,
        ),
      ),
    ],
  ),
);

/// Formatea un número decimal a texto en soles con dos decimales.
/// Ejemplo: 12.5 -> "S/ 12.50"
String _soles(double n) => 'S/ ${n.toStringAsFixed(2)}';
