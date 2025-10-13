// ============================================================================
// Archivo: estado_cuenta_conductor.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito del archivo
// ---------------------
// Define el modelo **EstadoCuentaConductor**, encargado de representar el
// estado financiero y operativo de la cuenta de cada conductor dentro del
// sistema Qorinti App. Este modelo almacena los saldos, deudas, ingresos,
// comisiones acumuladas y el estado actual de la cuenta.
//
// Alcance e integración
// ---------------------
// - Se vincula con la entidad `Conductor` mediante `idConductor`.
// - Proporciona valores acumulados para cálculos financieros y control de
//   pagos automáticos o retenciones.
// - Utiliza funciones auxiliares de `utils.dart` (`fsts`, `dt`, `toDoubleF`)
//   para la conversión y persistencia de datos en Firestore.
// - La enumeración `EstadoCuenta` controla la condición operativa del conductor
//   (ACTIVA, BLOQUEADA o CERRADA).
// ============================================================================

import 'utils.dart';

/// Enumeración que define los estados posibles de una cuenta de conductor.
enum EstadoCuenta { activa, bloqueada, cerrada }

/// Extensión con utilidades para manipular la enumeración `EstadoCuenta`,
/// incluyendo conversiones entre texto y tipo enumerado.
extension EstadoCuentaX on EstadoCuenta {
  String get name => toString().split('.').last.toUpperCase();

  static EstadoCuenta fromString(String v) {
    switch (v.toUpperCase()) {
      case 'BLOQUEADA':
        return EstadoCuenta.bloqueada;
      case 'CERRADA':
        return EstadoCuenta.cerrada;
      default:
        return EstadoCuenta.activa;
    }
  }
}

/// ----------------------------------------------------------------------------
/// Entidad de dominio: EstadoCuentaConductor
/// ----------------------------------------------------------------------------
/// Registra los movimientos y balances acumulados de un conductor.
/// Permite calcular disponibilidad, deudas y comisiones retenidas, así como
/// auditar la última transacción registrada.
/// ----------------------------------------------------------------------------
class EstadoCuentaConductor {
  final String? id;
  final String idConductor;

  final double saldoDisponible;
  final double saldoRetenido;
  final double deudaComision;
  final double totalIngresosAcum;
  final double totalComisionesAcum;

  final EstadoCuenta estado;

  final String? ultimaTransaccionId;
  final DateTime? ultimaTransaccion;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Constructor inmutable con valores financieros iniciales en cero y estado activo.
  const EstadoCuentaConductor({
    this.id,
    required this.idConductor,
    this.saldoDisponible = 0.0,
    this.saldoRetenido = 0.0,
    this.deudaComision = 0.0,
    this.totalIngresosAcum = 0.0,
    this.totalComisionesAcum = 0.0,
    this.estado = EstadoCuenta.activa,
    this.ultimaTransaccionId,
    this.ultimaTransaccion,
    this.creadoEn,
    this.actualizadoEn,
  });

  /// Serialización a Map para Firestore.
  /// - Incluye valores financieros y estado de cuenta.
  /// - Convierte fechas con `fsts` para formato compatible con Timestamp.
  Map<String, dynamic> toMap() => {
        'idConductor': idConductor,
        'saldoDisponible': saldoDisponible,
        'saldoRetenido': saldoRetenido,
        'deudaComision': deudaComision,
        'totalIngresosAcum': totalIngresosAcum,
        'totalComisionesAcum': totalComisionesAcum,
        'estado': estado.name,
        'ultimaTransaccionId': ultimaTransaccionId,
        'ultimaTransaccion': fsts(ultimaTransaccion),
        'creadoEn': fsts(creadoEn),
        'actualizadoEn': fsts(actualizadoEn),
      }..removeWhere((k, v) => v == null);

  /// Factoría para reconstruir una instancia desde un documento Firestore.
  /// - Realiza conversiones seguras con `toDoubleF` y `dt`.
  /// - Asigna valores por defecto cuando no existen en el documento.
  factory EstadoCuentaConductor.fromMap(Map<String, dynamic> map, {String? id}) =>
      EstadoCuentaConductor(
        id: id,
        idConductor: (map['idConductor'] ?? '') as String,
        saldoDisponible: toDoubleF(map['saldoDisponible']) ?? 0.0,
        saldoRetenido: toDoubleF(map['saldoRetenido']) ?? 0.0,
        deudaComision: toDoubleF(map['deudaComision']) ?? 0.0,
        totalIngresosAcum: toDoubleF(map['totalIngresosAcum']) ?? 0.0,
        totalComisionesAcum: toDoubleF(map['totalComisionesAcum']) ?? 0.0,
        estado: EstadoCuentaX.fromString(map['estado'] ?? 'ACTIVA'),
        ultimaTransaccionId: map['ultimaTransaccionId'] as String?,
        ultimaTransaccion: dt(map['ultimaTransaccion']),
        creadoEn: dt(map['creadoEn']),
        actualizadoEn: dt(map['actualizadoEn']),
      );

  /// Crea una copia modificada del estado de cuenta, conservando los valores
  /// originales de los campos no especificados.
  EstadoCuentaConductor copyWith({
    String? id,
    String? idConductor,
    double? saldoDisponible,
    double? saldoRetenido,
    double? deudaComision,
    double? totalIngresosAcum,
    double? totalComisionesAcum,
    EstadoCuenta? estado,
    String? ultimaTransaccionId,
    DateTime? ultimaTransaccion,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
  }) {
    return EstadoCuentaConductor(
      id: id ?? this.id,
      idConductor: idConductor ?? this.idConductor,
      saldoDisponible: saldoDisponible ?? this.saldoDisponible,
      saldoRetenido: saldoRetenido ?? this.saldoRetenido,
      deudaComision: deudaComision ?? this.deudaComision,
      totalIngresosAcum: totalIngresosAcum ?? this.totalIngresosAcum,
      totalComisionesAcum: totalComisionesAcum ?? this.totalComisionesAcum,
      estado: estado ?? this.estado,
      ultimaTransaccionId: ultimaTransaccionId ?? this.ultimaTransaccionId,
      ultimaTransaccion: ultimaTransaccion ?? this.ultimaTransaccion,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }
}
