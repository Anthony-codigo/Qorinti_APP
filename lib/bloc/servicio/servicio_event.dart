// Definición de eventos del BLoC de Servicios.
// Cada evento representa una intención de usuario o del sistema que modifica
// el estado del flujo de servicios (creación, escucha, transición de estado,
// ofertas, ubicación, etc.). Se utiliza Equatable para comparación por valor.

import 'package:equatable/equatable.dart';
import 'package:app_qorinti/modelos/servicio.dart';
import 'package:app_qorinti/modelos/oferta.dart';

/// Clase base abstracta para todos los eventos del BLoC de Servicios.
/// Implementa `props` vacío por defecto; las subclases deben sobrescribirlo.
abstract class ServicioEvent extends Equatable {
  const ServicioEvent();
  @override
  List<Object?> get props => [];
}

/// Solicita la creación de un nuevo servicio.
class CrearServicio extends ServicioEvent {
  final Servicio servicio;
  const CrearServicio(this.servicio);
  @override
  List<Object?> get props => [servicio];
}

/// Inicia la suscripción/escucha en tiempo real de un servicio específico.
class EscucharServicio extends ServicioEvent {
  final String idServicio;
  const EscucharServicio(this.idServicio);
  @override
  List<Object?> get props => [idServicio];
}

/// Actualiza el estado del servicio (aceptado, en_curso, finalizado, cancelado, etc.).
class ActualizarEstado extends ServicioEvent {
  final String idServicio;
  final EstadoServicio nuevoEstado;
  const ActualizarEstado(this.idServicio, this.nuevoEstado);
  @override
  List<Object?> get props => [idServicio, nuevoEstado];
}

/// Inicia un servicio previamente aceptado.
class IniciarServicio extends ServicioEvent {
  final String idServicio;
  const IniciarServicio(this.idServicio);
  @override
  List<Object?> get props => [idServicio];
}

/// Cancela un servicio activo o pendiente.
class CancelarServicio extends ServicioEvent {
  final String idServicio;
  const CancelarServicio(this.idServicio);
  @override
  List<Object?> get props => [idServicio];
}

/// Crea una oferta de un conductor para un servicio en estado de recepción de ofertas.
class CrearOfertaEvt extends ServicioEvent {
  final Oferta oferta; 
  const CrearOfertaEvt(this.oferta);
  @override
  List<Object?> get props => [oferta];
}

/// Acepta una oferta concreta y (en la lógica del repositorio) rechaza el resto.
class AceptarOfertaEvt extends ServicioEvent {
  final String servicioId;
  final String ofertaId;
  final String conductorId;
  final String? vehiculoId; 
  const AceptarOfertaEvt({
    required this.servicioId,
    required this.ofertaId,
    required this.conductorId,
    this.vehiculoId,
  });
  @override
  List<Object?> get props => [servicioId, ofertaId, conductorId, vehiculoId];
}

/// Actualiza la ubicación actual del conductor asociada a un servicio.
class ActualizarUbicacionConductor extends ServicioEvent {
  final String idServicio;
  final double lat;
  final double lng;
  const ActualizarUbicacionConductor(this.idServicio, this.lat, this.lng);
  @override
  List<Object?> get props => [idServicio, lat, lng];
}
