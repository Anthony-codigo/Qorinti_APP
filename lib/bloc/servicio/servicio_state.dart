// Estados del BLoC de Servicios.
// Modelan la evolución del flujo: estado inicial, carga, éxito con datos,
// error con mensaje y confirmación de creación (ID del servicio).
// Se usa Equatable para comparar por valor y optimizar reconstrucciones en UI.

import 'package:equatable/equatable.dart';
import 'package:app_qorinti/modelos/servicio.dart';

/// Clase base para todos los estados del BLoC de Servicios.
abstract class ServicioState extends Equatable {
  const ServicioState();
  @override
  List<Object?> get props => [];
}

/// Estado inicial (sin operaciones en curso ni datos cargados).
class ServicioInicial extends ServicioState {}

/// Estado de carga (operación en progreso).
class ServicioCargando extends ServicioState {}

/// Estado de éxito con un modelo de [Servicio] obtenido/actualizado.
class ServicioExito extends ServicioState {
  final Servicio servicio;
  const ServicioExito(this.servicio);
  @override
  List<Object?> get props => [servicio];
}

/// Estado de error con un mensaje legible para UI/registro.
class ServicioError extends ServicioState {
  final String mensaje;
  const ServicioError(this.mensaje);
  @override
  List<Object?> get props => [mensaje];
}

/// Estado que confirma la creación de un servicio y expone su ID.
class ServicioCreado extends ServicioState {
  final String idServicio;
  const ServicioCreado(this.idServicio);
  @override
  List<Object?> get props => [idServicio];
}
