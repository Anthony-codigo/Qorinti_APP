// ============================================================================
// Archivo: pago_comision.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Modelo **PagoComision** para registrar pagos de comisión realizados a
// conductores, incluyendo referencia de operación, observaciones y estado de
// revisión/aprobación. Provee utilidades de serialización para Firestore.
//
// Alcance e integración
// ---------------------
// - Persistencia: `toMap`/`fromMap` con soporte de `Timestamp` y limpieza de nulos.
// - Flujo de negocio: estados de ciclo de vida (EN_REVISION/APROBADO/RECHAZADO)
//   controlados por `EstadoPagoComision`.
// - Auditoría: marcas temporales `creadoEn`/`actualizadoEn` locales o con
//   `serverTimestamp` cuando se habilita la opción correspondiente.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// Enumeración de estados del pago de comisión en el flujo de validación.
enum EstadoPagoComision { en_revision, aprobado, rechazado }

/// Utilidades de normalización y parsing para `EstadoPagoComision`.
extension EstadoPagoComisionX on EstadoPagoComision {
  String get name => toString().split('.').last.toUpperCase();
  static EstadoPagoComision from(String v) {
    switch ((v).toString().toUpperCase()) {
      case 'APROBADO':
        return EstadoPagoComision.aprobado;
      case 'RECHAZADO':
        return EstadoPagoComision.rechazado;
      default:
        return EstadoPagoComision.en_revision;
    }
  }
}

/// Entidad de pago de comisión asociada a un conductor.
/// Contiene monto, referencias de operación y estado de aprobación.
class PagoComision {
  final String id;
  final String idConductor;
  final double monto;
  final String? referencia;     
  final String? observaciones;
  final EstadoPagoComision estado;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Constructor inmutable con estado por defecto EN_REVISION.
  const PagoComision({
    required this.id,
    required this.idConductor,
    required this.monto,
    this.referencia,
    this.observaciones,
    this.estado = EstadoPagoComision.en_revision,
    this.creadoEn,
    this.actualizadoEn,
  });

  /// Serialización a Map para Firestore.
  /// - Permite usar `serverTimestamp` cuando no se proveen fechas locales.
  Map<String, dynamic> toMap({bool serverNowIfNull = false}) => {
        'idConductor': idConductor,
        'monto': monto,
        'referencia': referencia,
        'observaciones': observaciones,
        'estado': estado.name,
        'creadoEn': creadoEn != null
            ? Timestamp.fromDate(creadoEn!)
            : (serverNowIfNull ? FieldValue.serverTimestamp() : null),
        'actualizadoEn': actualizadoEn != null
            ? Timestamp.fromDate(actualizadoEn!)
            : (serverNowIfNull ? FieldValue.serverTimestamp() : null),
      }..removeWhere((k, v) => v == null);

  /// Reconstrucción desde mapa de Firestore con conversiones seguras.
  factory PagoComision.fromMap(Map<String, dynamic> m, String id) => PagoComision(
        id: id,
        idConductor: (m['idConductor'] ?? '') as String,
        monto: (m['monto'] as num?)?.toDouble() ?? 0,
        referencia: m['referencia'] as String?,
        observaciones: m['observaciones'] as String?,
        estado: EstadoPagoComisionX.from(m['estado'] ?? 'EN_REVISION'),
        creadoEn: _dt(m['creadoEn']),
        actualizadoEn: _dt(m['actualizadoEn']),
      );

  /// Conversión robusta de `Timestamp`/`DateTime` a `DateTime?`.
  static DateTime? _dt(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}
