// lib/pantallas/Admin/build_comprobante_qorinti.dart
// ============================================================================
// Archivo: build_comprobante_qorinti.dart
// Proyecto: Qorinti App – Módulo de Administración
// ----------------------------------------------------------------------------
// Descripción general:
// Este archivo contiene dos componentes principales:
//
// 1Clase [RucServicio]:
//    - Permite validar un número de RUC (Registro Único de Contribuyentes)
//      mediante una API pública (https://api.apis.net.pe/v1/ruc).
//    - Devuelve la información básica del contribuyente (razón social, etc.)
//      en formato JSON o `null` si el RUC no es válido.
//
// Función [buildComprobanteQorintiPdf]:
//    - Genera dinámicamente un comprobante PDF (boleta/factura electrónica)
//      de Transportes Qorinti S.A.C. a partir de los datos proporcionados.
//    - Incluye los datos de la empresa, el conductor (cliente),
//      monto, fecha de emisión y detalles de la comisión.
//    - Puede incorporar el logo de Qorinti (por bytes o descargado de URL),
//      y opcionalmente una marca de agua translúcida.
// ----------------------------------------------------------------------------
// Tecnologías utilizadas:
// - http → para consumo de API y descarga del logo.
// - pdf & pdf/widgets → para la creación y maquetación del comprobante PDF.
// - intl → para formatear fechas y montos.
// - modelo: TipoComprobanteQorinti (enum definido en modelos/comprobante_qorinti.dart).
// ============================================================================

import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import 'package:app_qorinti/modelos/comprobante_qorinti.dart';

// ============================================================================
// CLASE: RucServicio
// ----------------------------------------------------------------------------
// Encapsula la validación de un RUC a través de la API pública "apis.net.pe".
// ============================================================================

class RucServicio {
  // Token de autenticación para la API pública.
  final String _token = "apis-token-1234"; 

  /// Consulta la API para validar un RUC.
  /// Devuelve un mapa con la información del contribuyente o `null` si no existe.
  Future<Map<String, dynamic>?> validarRuc(String ruc) async {
    try {
      final url = Uri.parse("https://api.apis.net.pe/v1/ruc?numero=$ruc");
      final response = await http
          .get(url, headers: {"Authorization": "Bearer $_token"})
          .timeout(const Duration(seconds: 8));

      // Caso exitoso → retorna el cuerpo JSON decodificado.
      if (response.statusCode == 200) return jsonDecode(response.body);

      // Caso de RUC inválido.
      if (response.statusCode == 422) {
        print("RUC inválido o no encontrado");
        return null;
      }

      // Otros errores HTTP.
      print("Error en consulta: ${response.statusCode}");
      return null;
    } catch (e) {
      // Captura excepciones por tiempo de espera o conexión.
      print("Excepción en validarRuc: $e");
      return null;
    }
  }
}

// ============================================================================
// FUNCIÓN: buildComprobanteQorintiPdf
// ----------------------------------------------------------------------------
// Construye un comprobante PDF estandarizado para Transportes Qorinti S.A.C.
//
// Parámetros principales:
// - [tipo]: Tipo de comprobante (Boleta o Factura).
// - [rucQorinti], [razonQorinti], [direccionQorinti]: Datos de la empresa.
// - [conductorNombre], [conductorDoc]: Datos del cliente (conductor).
// - [monto], [fecha]: Datos de la transacción.
// - [logoBytes] o [logoUrl]: Imagen del logo (local o descargable).
// - [addWatermark]: Agrega marca de agua "Qorinti App" si es true.
//
// Retorna: Uint8List → bytes del archivo PDF generado.
// ============================================================================

Future<Uint8List> buildComprobanteQorintiPdf({
  required TipoComprobanteQorinti tipo,
  required String rucQorinti,
  required String razonQorinti,
  required String direccionQorinti,
  required String conductorNombre,
  required String conductorDoc,
  required double monto,
  required DateTime fecha,

  // Logo del comprobante (opcional).
  Uint8List? logoBytes,
  String? logoUrl,
  bool addWatermark = true,
}) async {
  final pdf = pw.Document();
  final df = DateFormat('dd/MM/yyyy HH:mm', 'es_PE');
  final nf = NumberFormat.currency(locale: 'es_PE', symbol: 'S/');

  // URL predeterminada del logo (versión nueva y clara).
  final defaultLogoUrl =
      'https://firebasestorage.googleapis.com/v0/b/dbchavez05.firebasestorage.app/o/imagen_qorinti%2FImagen%20de%20WhatsApp%202025-10-04%20a%20las%2022.25.35_ac943c72.jpg?alt=media&token=553a2052-b211-4b25-86be-9ad780cc3373';

  // Determina qué URL usar efectivamente.
  final effectiveLogoUrl =
      (logoUrl == null || logoUrl.trim().isEmpty) ? defaultLogoUrl : logoUrl.trim();

  // Descarga el logo si no fue pasado como bytes.
  if (logoBytes == null && effectiveLogoUrl.isNotEmpty) {
    try {
      final resp = await http.get(Uri.parse(effectiveLogoUrl));
      if (resp.statusCode == 200) logoBytes = resp.bodyBytes;
    } catch (_) {}
  }

  // Paleta cromática usada en el PDF.
  const cBgCard   = 0xFFF7F7F7; // gris claro
  const cBgPanel  = 0xFFEFF2F6; // panel informativo
  const cTextMain = 0xFF111827; // gris oscuro casi negro
  const cTextSub  = 0xFF374151; // texto secundario
  const cDetailBg = 0xFFE9ECEF; // fondo detalles

  // Define el tema de página (márgenes, tipografía y marca de agua).
  pw.PageTheme _pageTheme() {
    return pw.PageTheme(
      margin: const pw.EdgeInsets.all(28),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
      buildBackground: (_) => pw.Stack(
        children: [
          pw.Positioned.fill(child: pw.Container(color: PdfColors.white)),
          if (addWatermark)
            pw.Positioned.fill(
              child: pw.Center(
                child: pw.Transform.rotate(
                  angle: -0.5, // Rotación de la marca de agua (~-28.6°)
                  child: pw.Opacity(
                    opacity: 0.05,
                    child: pw.Text(
                      'Qorinti App',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 90,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // CONSTRUCCIÓN DEL CONTENIDO DEL COMPROBANTE
  // --------------------------------------------------------------------------

  pdf.addPage(
    pw.Page(
      pageTheme: _pageTheme(),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ------------------------------------------------------------------
          // ENCABEZADO: LOGO + DATOS DE EMPRESA
          // ------------------------------------------------------------------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoBytes != null)
                pw.Container(
                  height: 80,
                  width: 80,
                  child: pw.Image(
                    pw.MemoryImage(logoBytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Transportes Qorinti S.A.C.',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(cTextMain),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text('RUC: $rucQorinti',
                      style: const pw.TextStyle(color: PdfColors.black)),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    '${tipo.label.toUpperCase()} ELECTRÓNICA',
                    style: pw.TextStyle(
                      color: PdfColors.orange,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 18),

          // ------------------------------------------------------------------
          // PANEL DE INFORMACIÓN DE LA EMPRESA
          // ------------------------------------------------------------------
          pw.Container(
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(cBgPanel),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Razón Social: $razonQorinti'),
                pw.Text('Nombre Comercial: Qorinti'),
                pw.Text('Dirección: $direccionQorinti'),
                pw.Text('Condición: Activo'),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // ------------------------------------------------------------------
          // DATOS DEL CLIENTE (CONDUCTOR)
          // ------------------------------------------------------------------
          pw.Text(
            'CLIENTE (CONDUCTOR)',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(cTextMain),
            ),
          ),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 6),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(cBgCard),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Nombre: $conductorNombre'),
                pw.Text('Documento: $conductorDoc'),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // ------------------------------------------------------------------
          // DETALLE DEL COMPROBANTE
          // ------------------------------------------------------------------
          pw.Text(
            'DETALLE DEL COMPROBANTE',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(cTextMain),
            ),
          ),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 6),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(cDetailBg),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Concepto: Comisión por uso de la plataforma Qorinti',
                  style: pw.TextStyle(color: const PdfColor.fromInt(cTextSub)),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Monto: ${nf.format(monto)}',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(cTextMain),
                  ),
                ),
                pw.Text(
                  'Fecha de emisión: ${df.format(fecha)}',
                  style: pw.TextStyle(color: const PdfColor.fromInt(cTextSub)),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // ------------------------------------------------------------------
          // PIE DE PÁGINA
          // ------------------------------------------------------------------
          pw.Center(
            child: pw.Text(
              'Comprobante generado automáticamente por Qorinti App',
              style: pw.TextStyle(
                color: const PdfColor.fromInt(cTextSub),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // Devuelve el PDF en formato de bytes
  return pdf.save();
}
