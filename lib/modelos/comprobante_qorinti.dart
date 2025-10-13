// ============================================================================
// Archivo: comprobante_qorinti.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito del archivo
// ---------------------
// Define el modelo de datos **ComprobanteQorinti**, que representa los
// comprobantes electrónicos emitidos por la empresa Qorinti S.A.C. a los
// conductores o servicios registrados en el sistema. Estos documentos sirven
// para el control contable y la trazabilidad de pagos dentro del módulo de
// finanzas.
//
// Alcance e integración
// ---------------------
// - Almacena información principal del comprobante (tipo, serie, número, monto,
//   fecha y enlace al PDF) sincronizada con Firestore.
// - Se relaciona con entidades de pago (`idPago`) y con el conductor
//   correspondiente (`idConductor`), pudiendo asociarse opcionalmente a un
//   servicio (`idServicio`).
// - Implementa métodos de conversión robustos (`toMap`, `fromMap`) y control de
//   tipos (`_toDate`, `_toDouble`, `_toBoolN`) para garantizar la consistencia
//   de datos provenientes de distintas fuentes.
// - Utiliza `Equatable` para soportar comparación estructural y compatibilidad
//   con la gestión de estados en BLoC.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Enumeración de los tipos de comprobantes válidos emitidos por Qorinti.
enum TipoComprobanteQorinti { boleta, factura }

/// Extensión que provee etiquetas legibles, conversiones y utilidades para
/// trabajar con `TipoComprobanteQorinti`.
extension TipoComprobanteQorintiX on TipoComprobanteQorinti {
  String get label => this == TipoComprobanteQorinti.factura ? 'Factura' : 'Boleta';
  String get toFirestore => this == TipoComprobanteQorinti.factura ? 'FACTURA' : 'BOLETA';

  static TipoComprobanteQorinti fromString(dynamic v) {
    final s = ('${v ?? ''}').toUpperCase().trim();
    return s == 'FACTURA' ? TipoComprobanteQorinti.factura : TipoComprobanteQorinti.boleta;
  }
}

/// Modelo que representa un comprobante electrónico emitido por Qorinti.
/// Contiene datos de identificación, tipo, valores económicos y referencias
/// relacionadas con pagos y servicios.
class ComprobanteQorinti extends Equatable {
  final String id;
  final String idPago;
  final String idConductor;

  final String? idServicio;

  final TipoComprobanteQorinti tipo;
  final String serie;
  final String numero;
  final String serieNumero;
  final double monto;
  final DateTime fecha;
  final String urlPdf;

  final bool? esCorrecta;

  const ComprobanteQorinti({
    required this.id,
    required this.idPago,
    required this.idConductor,
    this.idServicio,
    required this.tipo,
    required this.serie,
    required this.numero,
    required this.serieNumero,
    required this.monto,
    required this.fecha,
    required this.urlPdf,
    this.esCorrecta,
  });

  /// Conversión segura de valores dinámicos a `DateTime`.
  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Conversión controlada a `double` para el campo monto.
  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0.0;
  }

  /// Conversión segura a booleano nullable.
  static bool? _toBoolN(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is String) {
      final s = v.toLowerCase().trim();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return null;
  }

  /// Serialización del comprobante a formato Map para Firestore.
  Map<String, dynamic> toMap() => {
        'idPago': idPago,
        'idConductor': idConductor,
        'idServicio': idServicio,
        'tipo': tipo.toFirestore,
        'serie': serie,
        'numero': numero,
        'serieNumero': serieNumero,
        'monto': monto,
        'fecha': Timestamp.fromDate(fecha),
        'urlPdf': urlPdf,
        'esCorrecta': esCorrecta,
      }..removeWhere((k, v) => v == null);

  /// Factoría para crear una instancia de `ComprobanteQorinti` desde un Map.
  factory ComprobanteQorinti.fromMap(Map<String, dynamic> m, String id) {
    return ComprobanteQorinti(
      id: id,
      idPago: (m['idPago'] ?? '') as String,
      idConductor: (m['idConductor'] ?? '') as String,
      idServicio: m['idServicio'] as String?,
      tipo: TipoComprobanteQorintiX.fromString(m['tipo']),
      serie: (m['serie'] ?? '').toString(),
      numero: (m['numero'] ?? '').toString(),
      serieNumero: (m['serieNumero'] ?? '').toString(),
      monto: _toDouble(m['monto']),
      fecha: _toDate(m['fecha']),
      urlPdf: (m['urlPdf'] ?? '').toString(),
      esCorrecta: _toBoolN(m['esCorrecta']),
    );
  }

  /// Representación combinada legible de serie y número.
  String get serieNumeroPretty {
    if (serieNumero.trim().isNotEmpty) return serieNumero;
    final s = serie.trim();
    final n = numero.trim();
    return [s, n].where((e) => e.isNotEmpty).join('-');
  }

  /// Indica si el comprobante cuenta con un PDF asociado válido.
  bool get tienePdf => urlPdf.trim().isNotEmpty;

  /// Crea una copia del comprobante modificando solo los campos indicados.
  ComprobanteQorinti copyWith({
    String? id,
    String? idPago,
    String? idConductor,
    String? idServicio,
    TipoComprobanteQorinti? tipo,
    String? serie,
    String? numero,
    String? serieNumero,
    double? monto,
    DateTime? fecha,
    String? urlPdf,
    bool? esCorrecta,
  }) {
    return ComprobanteQorinti(
      id: id ?? this.id,
      idPago: idPago ?? this.idPago,
      idConductor: idConductor ?? this.idConductor,
      idServicio: idServicio ?? this.idServicio,
      tipo: tipo ?? this.tipo,
      serie: serie ?? this.serie,
      numero: numero ?? this.numero,
      serieNumero: serieNumero ?? this.serieNumero,
      monto: monto ?? this.monto,
      fecha: fecha ?? this.fecha,
      urlPdf: urlPdf ?? this.urlPdf,
      esCorrecta: esCorrecta ?? this.esCorrecta,
    );
  }

  @override
  List<Object?> get props => [
        id,
        idPago,
        idConductor,
        idServicio,
        tipo,
        serie,
        numero,
        serieNumero,
        monto,
        fecha,
        urlPdf,
        esCorrecta,
      ];
}
