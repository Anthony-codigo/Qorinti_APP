// ============================================================================
// Archivo: plan_ruta.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Modelo **PlanRuta** que define la planificación de una ruta solicitada en el
// sistema Qorinti, incluyendo tipo de servicio (taxi, carga, mudanza, etc.),
// puntos de origen/destino, datos de carga y estimaciones de distancia y tiempo.
//
// Alcance e integración
// ---------------------
// - Se integra con la entidad `Servicio` mediante el método `construirServicio()`,
//   que genera un servicio inicial a partir de los datos planificados.
// - Permite validación previa a la creación del servicio mediante `validar()`.
// - Incluye parámetros de carga (peso, volumen, ayudantes, montacargas) para
//   servicios de tipo carga o mudanza.
// - Compatible con Firestore (`toMap` / `fromMap`) mediante utilidades de
//   conversión de `utils.dart`.
// ============================================================================

import 'utils.dart';                 
import 'servicio.dart';               
import 'package:equatable/equatable.dart';

/// ----------------------------------------------------------------------------
/// Entidad de dominio: PlanRuta
/// ----------------------------------------------------------------------------
/// Representa la planificación completa de una ruta antes de generar un
/// `Servicio`. Contiene información geográfica, tipo de servicio, y detalles
/// específicos de carga si aplica.
/// ----------------------------------------------------------------------------
class PlanRuta extends Equatable {
  final TipoServicio tipoServicio;
  final List<PuntoRuta> ruta;

  final double? distanciaKm;
  final int? tiempoEstimadoMin;

  final double? pesoTon;
  final double? volumenM3;
  final bool? requiereAyudantes;
  final int? cantidadAyudantes;
  final bool? requiereMontacargas;
  final String? notasCarga;

  /// Constructor inmutable con campos opcionales para detalles de carga.
  const PlanRuta({
    required this.tipoServicio,
    required this.ruta,
    this.distanciaKm,
    this.tiempoEstimadoMin,
    this.pesoTon,
    this.volumenM3,
    this.requiereAyudantes,
    this.cantidadAyudantes,
    this.requiereMontacargas,
    this.notasCarga,
  });

  /// Determina si el tipo de servicio implica transporte de carga o mudanza.
  bool get _esCarga =>
      tipoServicio == TipoServicio.carga_pesada ||
      tipoServicio == TipoServicio.mudanza;

  /// Indica si se han definido dimensiones o peso de carga.
  bool get hasCargaDims =>
      ((pesoTon ?? 0) > 0) || ((volumenM3 ?? 0) > 0);

  /// Validación de consistencia de la planificación de ruta.
  /// - Exige al menos dos puntos (origen y destino).
  /// - Verifica coordenadas válidas en cada punto.
  /// - En servicios de carga/mudanza valida peso o volumen y ayudantes.
  String? validar() {
    if (ruta.length < 2) return 'Se requieren al menos ORIGEN y DESTINO.';
    final origen = ruta.first, destino = ruta.last;
    if (origen.lat == null || origen.lng == null) {
      return 'Selecciona un ORIGEN válido.';
    }
    if (destino.lat == null || destino.lng == null) {
      return 'Selecciona un DESTINO válido.';
    }
    for (int i = 1; i < ruta.length - 1; i++) {
      final p = ruta[i];
      if (p.lat == null || p.lng == null) {
        return 'Parada intermedia #$i sin coordenadas válidas.';
      }
    }
    if (_esCarga) {
      if (!hasCargaDims) {
        return 'Para carga/mudanza ingresa Peso (t) o Volumen (m³).';
      }
      if ((requiereAyudantes ?? false) && (cantidadAyudantes ?? 0) < 1) {
        return 'Cantidad de ayudantes inválida.';
      }
    }
    return null;
  }

  /// Construye una instancia de `Servicio` a partir del plan definido.
  /// - Propaga parámetros de distancia, tiempo y carga si aplica.
  Servicio construirServicio({
    required String idUsuarioSolicitante,
    required double precioEstimado,
    MetodoPago metodoPago = MetodoPago.efectivo,
    TipoComprobante tipoComprobante = TipoComprobante.ninguno,
    DateTime? fechaSolicitud, 
    int? etaMin,          
    int? slaMin,            
    double? distanciaKm,       
  }) {
    return Servicio(
      idUsuarioSolicitante: idUsuarioSolicitante,
      ruta: ruta,
      tipoServicio: tipoServicio,
      precioEstimado: precioEstimado,
      metodoPago: metodoPago,
      tipoComprobante: tipoComprobante,
      estado: EstadoServicio.pendiente_ofertas,
      fechaSolicitud: fechaSolicitud,                  
      tiempoEstimadoMin: etaMin ?? this.tiempoEstimadoMin, 
      slaMin: slaMin,                                    
      distanciaKm: distanciaKm ?? this.distanciaKm,
      pesoTon: _esCarga ? pesoTon : null,
      volumenM3: _esCarga ? volumenM3 : null,
      requiereAyudantes: _esCarga ? requiereAyudantes : null,
      cantidadAyudantes: _esCarga ? cantidadAyudantes : null,
      requiereMontacargas: _esCarga ? requiereMontacargas : null,
      notasCarga: _esCarga ? notasCarga : null,
    );
  }

  /// Serialización a Map para persistencia.
  Map<String, dynamic> toMap() => {
        'tipoServicio': tipoServicio.code,
        'ruta': ruta.map((e) => e.toMap()).toList(),
        'distanciaKm': distanciaKm,
        'tiempoEstimadoMin': tiempoEstimadoMin,
        'pesoTon': pesoTon,
        'volumenM3': volumenM3,
        'requiereAyudantes': requiereAyudantes,
        'cantidadAyudantes': cantidadAyudantes,
        'requiereMontacargas': requiereMontacargas,
        'notasCarga': notasCarga,
      }..removeWhere((k, v) => v == null);

  /// Conversión segura a booleano desde múltiples formatos.
  static bool _b(v) => v == true || (v is String && v.toLowerCase().trim() == 'true');

  /// Reconstrucción desde mapa Firestore.
  factory PlanRuta.fromMap(Map<String, dynamic> m) => PlanRuta(
        tipoServicio: TipoServicioX.fromString(m['tipoServicio'] ?? 'TAXI'),
        ruta: (m['ruta'] as List<dynamic>? ?? [])
            .map((e) => PuntoRuta.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        distanciaKm: toDoubleF(m['distanciaKm']),
        tiempoEstimadoMin: toIntF(m['tiempoEstimadoMin']),
        pesoTon: toDoubleF(m['pesoTon']),
        volumenM3: toDoubleF(m['volumenM3']),
        requiereAyudantes: _b(m['requiereAyudantes']),
        cantidadAyudantes: toIntF(m['cantidadAyudantes']),
        requiereMontacargas: _b(m['requiereMontacargas']),
        notasCarga: m['notasCarga'] as String?,
      );

  /// Crea una copia modificada del plan, manteniendo valores originales.
  PlanRuta copyWith({
    TipoServicio? tipoServicio,
    List<PuntoRuta>? ruta,
    double? distanciaKm,
    int? tiempoEstimadoMin,
    double? pesoTon,
    double? volumenM3,
    bool? requiereAyudantes,
    int? cantidadAyudantes,
    bool? requiereMontacargas,
    String? notasCarga,
  }) {
    return PlanRuta(
      tipoServicio: tipoServicio ?? this.tipoServicio,
      ruta: ruta ?? this.ruta,
      distanciaKm: distanciaKm ?? this.distanciaKm,
      tiempoEstimadoMin: tiempoEstimadoMin ?? this.tiempoEstimadoMin,
      pesoTon: pesoTon ?? this.pesoTon,
      volumenM3: volumenM3 ?? this.volumenM3,
      requiereAyudantes: requiereAyudantes ?? this.requiereAyudantes,
      cantidadAyudantes: cantidadAyudantes ?? this.cantidadAyudantes,
      requiereMontacargas: requiereMontacargas ?? this.requiereMontacargas,
      notasCarga: notasCarga ?? this.notasCarga,
    );
  }

  @override
  List<Object?> get props => [
        tipoServicio,
        ruta,
        distanciaKm,
        tiempoEstimadoMin,
        pesoTon,
        volumenM3,
        requiereAyudantes,
        cantidadAyudantes,
        requiereMontacargas,
        notasCarga,
      ];
}
