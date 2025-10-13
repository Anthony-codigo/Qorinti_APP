// ============================================================================
// Archivo: oferta.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Modelo de dominio **Oferta** para postulación de conductores a un Servicio,
// registrando precio ofrecido, ETA estimado, notas y estado del proceso
// (pendiente/aceptada/rechazada). Incluye utilidades de serialización con
// Firestore y comparadores básicos.
//
// Alcance
// -------
// - Persistencia: `toMap`/`fromMap` con manejo de `Timestamp` y limpieza de nulos.
// - Negocio: validaciones mínimas (precio >= 0, ETA > 0) y flags de emisor.
// - Comparación: ordenación por precio o por ETA para selección de oferta.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Estado del ciclo de vida de la oferta (workflow de selección).
enum EstadoOferta { pendiente, aceptada, rechazada }

/// Utilidades de mapeo/normalización para `EstadoOferta`.
extension EstadoOfertaX on EstadoOferta {
  String get code => toString().split('.').last.toUpperCase();

  static EstadoOferta fromString(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'ACEPTADA':
        return EstadoOferta.aceptada;
      case 'RECHAZADA':
        return EstadoOferta.rechazada;
      default:
        return EstadoOferta.pendiente;
    }
  }
}

/// Entidad que representa una oferta de un conductor sobre un servicio.
class Oferta extends Equatable {
  final String id;
  final String idServicio;        
  final String idConductor;
  final double precioOfrecido;   
  final int tiempoEstimadoMin;   
  final String? notas;
  final EstadoOferta estado;      
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Si es true, la empresa figura como emisor del comprobante correspondiente.
  final bool usaEmpresaComoEmisor;

  /// Constructor con aserciones de negocio para precio y ETA.
  const Oferta({
    required this.id,
    required this.idServicio,
    required this.idConductor,
    required this.precioOfrecido,
    required this.tiempoEstimadoMin,
    this.notas,
    this.estado = EstadoOferta.pendiente,
    this.creadoEn,
    this.actualizadoEn,
    this.usaEmpresaComoEmisor = false,
  })  : assert(precioOfrecido >= 0, 'precioOfrecido debe ser >= 0'),
        assert(tiempoEstimadoMin > 0, 'tiempoEstimadoMin debe ser > 0');

  /// Serialización para Firestore.
  /// - Aplica `serverTimestamp` opcional cuando no hay marca temporal local.
  Map<String, dynamic> toMap({bool serverTimestampsIfNull = false}) {
    return {
      'idServicio': idServicio,
      'idConductor': idConductor,
      'precioOfrecido': precioOfrecido,
      'tiempoEstimadoMin': tiempoEstimadoMin,
      'notas': notas,
      'estado': estado.code,
      'usaEmpresaComoEmisor': usaEmpresaComoEmisor,
      'creadoEn': creadoEn != null
          ? Timestamp.fromDate(creadoEn!)
          : (serverTimestampsIfNull ? FieldValue.serverTimestamp() : null),
      'actualizadoEn': actualizadoEn != null
          ? Timestamp.fromDate(actualizadoEn!)
          : (serverTimestampsIfNull ? FieldValue.serverTimestamp() : null),
    }..removeWhere((k, v) => v == null);
  }

  // Conversores internos robustos para lectura dinámica desde Firestore.
  static DateTime? _ts(dynamic x) =>
      x is Timestamp ? x.toDate() : (x is DateTime ? x : null);
  static double _d(dynamic x) =>
      x is num ? x.toDouble() : double.tryParse('${x ?? ''}') ?? 0;
  static int _i(dynamic x) =>
      x is num ? x.toInt() : int.tryParse('${x ?? ''}') ?? 0;
  static bool _b(dynamic v) =>
      v == true || (v is String && v.toLowerCase().trim() == 'true');

  /// Reconstrucción desde snapshot/map de Firestore con saneamiento de tipos.
  factory Oferta.fromMap(Map<String, dynamic> map, String id) => Oferta(
        id: id,
        idServicio: (map['idServicio'] ?? '') as String,
        idConductor: (map['idConductor'] ?? '') as String,
        precioOfrecido: _d(map['precioOfrecido']),
        tiempoEstimadoMin: _i(map['tiempoEstimadoMin']),
        notas: map['notas'] as String?,
        estado: EstadoOfertaX.fromString(map['estado'] ?? 'PENDIENTE'),
        creadoEn: _ts(map['creadoEn']),
        actualizadoEn: _ts(map['actualizadoEn']),
        usaEmpresaComoEmisor: _b(map['usaEmpresaComoEmisor']),
      );

  /// Ayudas de legibilidad para lógica de estado.
  bool get esPendiente => estado == EstadoOferta.pendiente;
  bool get esAceptada  => estado == EstadoOferta.aceptada;
  bool get esRechazada => estado == EstadoOferta.rechazada;

  /// Comparadores para ordenamiento por criterio (precio/ETA).
  int compareByPrecio(Oferta other) => precioOfrecido.compareTo(other.precioOfrecido);
  int compareByEta(Oferta other) => tiempoEstimadoMin.compareTo(other.tiempoEstimadoMin);

  /// Copia inmutable con cambios selectivos.
  Oferta copyWith({
    String? id,
    String? idServicio,
    String? idConductor,
    double? precioOfrecido,
    int? tiempoEstimadoMin,
    String? notas,
    EstadoOferta? estado,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
    bool? usaEmpresaComoEmisor,
  }) {
    return Oferta(
      id: id ?? this.id,
      idServicio: idServicio ?? this.idServicio,
      idConductor: idConductor ?? this.idConductor,
      precioOfrecido: precioOfrecido ?? this.precioOfrecido,
      tiempoEstimadoMin: tiempoEstimadoMin ?? this.tiempoEstimadoMin,
      notas: notas ?? this.notas,
      estado: estado ?? this.estado,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
      usaEmpresaComoEmisor: usaEmpresaComoEmisor ?? this.usaEmpresaComoEmisor,
    );
  }

  @override
  List<Object?> get props => [
        id,
        idServicio,
        idConductor,
        precioOfrecido,
        tiempoEstimadoMin,
        notas,
        estado,
        creadoEn,
        actualizadoEn,
        usaEmpresaComoEmisor,
      ];
}
