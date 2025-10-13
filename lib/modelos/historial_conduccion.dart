// ============================================================================
// Archivo: historial_conduccion.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito del archivo
// ---------------------
// Define el modelo **HistorialConduccion**, que consolida indicadores de
// desempeño del conductor (viajes completados/cancelados, calificación promedio
// y última conducción) para análisis operativo y criterios de elegibilidad.
//
// Alcance e integración
// ---------------------
// - Persistencia: serializa/deserializa con Firestore mediante `toMap` y
//   `fromMap`, utilizando utilidades de `utils.dart` (`fsts`, `dt`, `toIntF`,
//   `toDoubleF`) para manejo consistente de tipos y fechas.
// - Uso: habilita paneles de monitoreo, reglas de negocio (p. ej., bloqueos por
//   alta tasa de cancelación) y cálculo de métricas agregadas por conductor.
// ============================================================================

import 'utils.dart';

/// ----------------------------------------------------------------------------
/// Entidad de dominio: HistorialConduccion
/// ----------------------------------------------------------------------------
/// Registra KPIs básicos de desempeño del conductor y sus marcas temporales.
/// `ultimaConduccion` permite auditoría de actividad reciente.
// ----------------------------------------------------------------------------
class HistorialConduccion {
  final String? id;
  final String idConductor;

  final int viajesCompletados;

  final int viajesCancelados;

  final double calificacionPromedio;

  final DateTime? ultimaConduccion;

  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Constructor inmutable con valores por defecto para métricas.
  const HistorialConduccion({
    this.id,
    required this.idConductor,
    this.viajesCompletados = 0,
    this.viajesCancelados = 0,
    this.calificacionPromedio = 0.0,
    this.ultimaConduccion,
    this.creadoEn,
    this.actualizadoEn,
  });

  /// Serialización a Map para persistencia en Firestore.
  /// - Convierte fechas con `fsts`.
  /// - Elimina claves nulas para evitar sobreescrituras parciales.
  Map<String, dynamic> toMap() => {
        'idConductor': idConductor,
        'viajesCompletados': viajesCompletados,
        'viajesCancelados': viajesCancelados,
        'calificacionPromedio': calificacionPromedio,
        'ultimaConduccion': fsts(ultimaConduccion),
        'creadoEn': fsts(creadoEn),
        'actualizadoEn': fsts(actualizadoEn),
      }..removeWhere((k, v) => v == null);

  /// Factoría desde Map (lectura Firestore) con conversiones seguras.
  factory HistorialConduccion.fromMap(Map<String, dynamic> map, {String? id}) =>
      HistorialConduccion(
        id: id,
        idConductor: (map['idConductor'] ?? '') as String,
        viajesCompletados: toIntF(map['viajesCompletados']) ?? 0,
        viajesCancelados: toIntF(map['viajesCancelados']) ?? 0,
        calificacionPromedio: toDoubleF(map['calificacionPromedio']) ?? 0.0,
        ultimaConduccion: dt(map['ultimaConduccion']),
        creadoEn: dt(map['creadoEn']),
        actualizadoEn: dt(map['actualizadoEn']),
      );
}
