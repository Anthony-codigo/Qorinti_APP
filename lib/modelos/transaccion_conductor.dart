// ============================================================================
// Archivo: transaccion_conductor.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Modelo **TransaccionConductor** que representa los movimientos financieros
// entre el sistema Qorinti y los conductores, derivados de los servicios
// completados. Permite registrar montos brutos, comisiones, netos y estados
// de liquidación.
//
// Alcance e integración
// ---------------------
// - Se integra con el modelo `Servicio` para relacionar la transacción al viaje.
// - Compatible con Firestore (usa `Timestamp` y `FieldValue.serverTimestamp`).
// - Gestiona los estados de flujo financiero: pendiente, liquidado y anulado.
// - Usado para auditorías, liquidaciones y reportes de ingresos del conductor.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'utils.dart';

/// ----------------------------------------------------------------------------
/// ENUMERACIÓN: EstadoTransaccion
/// ----------------------------------------------------------------------------
/// Controla el estado de la transacción en el flujo financiero del conductor.
enum EstadoTransaccion { pendiente, liquidado, anulado }

extension EstadoTransaccionX on EstadoTransaccion {
  /// Devuelve el nombre del estado en mayúsculas (para almacenamiento).
  String get name => toString().split('.').last.toUpperCase();

  /// Conversión desde texto (Firestore o API) a enumeración segura.
  static EstadoTransaccion fromString(String v) {
    switch (v.toUpperCase()) {
      case 'LIQUIDADO':
        return EstadoTransaccion.liquidado;
      case 'ANULADO':
        return EstadoTransaccion.anulado;
      default:
        return EstadoTransaccion.pendiente;
    }
  }
}

/// ----------------------------------------------------------------------------
/// ENTIDAD: TransaccionConductor
/// ----------------------------------------------------------------------------
/// Representa una transacción económica relacionada con un conductor.
/// Cada registro contiene información sobre el monto bruto obtenido,
/// la comisión aplicada y el monto neto que se le liquida al conductor.
///
/// Campos principales
/// ------------------
/// - `idServicio`: referencia al viaje completado.
/// - `idConductor`: identificador del conductor beneficiario.
/// - `montoBruto`: ingreso total generado por el servicio.
/// - `comision`: descuento aplicado por la plataforma.
/// - `montoNeto`: resultado final a pagar.
/// - `estado`: controla el flujo contable (Pendiente, Liquidado, Anulado).
/// ----------------------------------------------------------------------------
class TransaccionConductor {
  final String id;
  final String idServicio;
  final String idConductor;
  final double montoBruto;
  final double comision;
  final double montoNeto;
  final String? referencia;
  final EstadoTransaccion estado;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Constructor inmutable principal.
  const TransaccionConductor({
    required this.id,
    required this.idServicio,
    required this.idConductor,
    required this.montoBruto,
    required this.comision,
    required this.montoNeto,
    this.referencia,
    this.estado = EstadoTransaccion.pendiente,
    this.creadoEn,
    this.actualizadoEn,
  });

  /// Serializa la entidad a formato Firestore.
  /// Si `serverNowIfNull = true`, usa el timestamp del servidor
  /// para campos de creación/actualización nulos.
  Map<String, dynamic> toMap({bool serverNowIfNull = false}) => {
        'idServicio': idServicio,
        'idConductor': idConductor,
        'montoBruto': montoBruto,
        'comision': comision,
        'montoNeto': montoNeto,
        'referencia': referencia,
        'estado': estado.name,
        'creadoEn': creadoEn != null
            ? Timestamp.fromDate(creadoEn!)
            : (serverNowIfNull ? FieldValue.serverTimestamp() : null),
        'actualizadoEn': actualizadoEn != null
            ? Timestamp.fromDate(actualizadoEn!)
            : (serverNowIfNull ? FieldValue.serverTimestamp() : null),
      }..removeWhere((k, v) => v == null);

  /// Reconstruye una instancia desde un documento Firestore.
  factory TransaccionConductor.fromMap(Map<String, dynamic> m, String id) =>
      TransaccionConductor(
        id: id,
        idServicio: (m['idServicio'] ?? '') as String,
        idConductor: (m['idConductor'] ?? '') as String,
        montoBruto: (m['montoBruto'] as num?)?.toDouble() ?? 0,
        comision: (m['comision'] as num?)?.toDouble() ?? 0,
        montoNeto: (m['montoNeto'] as num?)?.toDouble() ?? 0,
        referencia: m['referencia'] as String?,
        estado: EstadoTransaccionX.fromString(m['estado'] ?? 'PENDIENTE'),
        creadoEn: dt(m['creadoEn']),
        actualizadoEn: dt(m['actualizadoEn']),
      );
}
