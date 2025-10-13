// ============================================================================
// Archivo: conductor_vehiculo.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito del archivo
// ---------------------
// Modelo de relación **ConductorVehiculo** que vincula un conductor con un
// vehículo, registrando el estado del vínculo (p. ej. PENDIENTE/ACTIVO),
// banderas de actividad y metadatos de auditoría. Se utiliza para controlar
// habilitaciones operativas y trazabilidad de cambios.
//
// Alcance e integración
// ---------------------
// - Serialización/deserialización compatible con Firestore mediante utilidades
//   de `utils.dart` (`dt`, `fsts`) para manejo de fechas.
// - Inmutabilidad por defecto, con valores predeterminados seguros para
//   `estadoVinculo` y `activo`.
// - Limpieza de nulos en `toMap` para evitar sobreescrituras innecesarias.
// ============================================================================

import 'utils.dart';

/// ----------------------------------------------------------------------------
/// Entidad de dominio: ConductorVehiculo
/// ----------------------------------------------------------------------------
/// Representa el vínculo operacional entre un conductor y un vehículo.
/// Incluye estado del vínculo, bandera de actividad y observaciones de control.
/// Fechas `creadoEn`/`actualizadoEn` permiten auditoría temporal.
// ----------------------------------------------------------------------------
class ConductorVehiculo {
  final String? id;
  final String idConductor;
  final String idVehiculo;

  final String estadoVinculo;

  final bool activo;

  final String? observaciones;

  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// --------------------------------------------------------------------------
  /// Constructor inmutable
  /// - Valores por defecto: `estadoVinculo = 'PENDIENTE'`, `activo = false`,
  ///   para asegurar estados iniciales consistentes en el alta del vínculo.
  /// --------------------------------------------------------------------------
  const ConductorVehiculo({
    this.id,
    required this.idConductor,
    required this.idVehiculo,
    this.estadoVinculo = 'PENDIENTE',
    this.activo = false,
    this.observaciones,
    this.creadoEn,
    this.actualizadoEn,
  });

  /// --------------------------------------------------------------------------
  /// Serialización a Map
  /// - Convierte fechas con `fsts` para compatibilidad con Firestore.
  /// - Normaliza `estadoVinculo` a mayúsculas para consistencia en consultas.
  /// - Remueve claves con valor nulo para evitar sobrescribir campos ausentes.
  /// --------------------------------------------------------------------------
  Map<String, dynamic> toMap() => {
        'idConductor': idConductor,
        'idVehiculo': idVehiculo,
        'estadoVinculo': estadoVinculo.toUpperCase(),
        'activo': activo,
        'observaciones': observaciones,
        'creadoEn': fsts(creadoEn),
        'actualizadoEn': fsts(actualizadoEn),
      }..removeWhere((k, v) => v == null);

  /// --------------------------------------------------------------------------
  /// Factoría desde Map
  /// - Sanitiza y normaliza campos críticos (ids y estado).
  /// - Interpreta booleanos y fechas con utilidades `dt`.
  /// --------------------------------------------------------------------------
  factory ConductorVehiculo.fromMap(Map<String, dynamic> map, {String? id}) =>
      ConductorVehiculo(
        id: id,
        idConductor: (map['idConductor'] ?? '') as String,
        idVehiculo: (map['idVehiculo'] ?? '') as String,
        estadoVinculo:
            (map['estadoVinculo'] ?? 'PENDIENTE').toString().toUpperCase(),
        activo: map['activo'] == true,
        observaciones: map['observaciones'] as String?,
        creadoEn: dt(map['creadoEn']),
        actualizadoEn: dt(map['actualizadoEn']),
      );
}
