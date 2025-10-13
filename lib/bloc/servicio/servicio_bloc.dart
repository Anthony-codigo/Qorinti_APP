// BLoC de Servicios: orquesta eventos y estados relacionados al ciclo de vida de un Servicio.
// Coordina con el ServicioRepository para operaciones de creación, escucha en tiempo real,
// actualización de estado, inicio/cancelación de servicios, gestión de ofertas y ubicación.
//
// Diseño:
// - Registro explícito de handlers por evento en el constructor.
// - Emisiones de estados de carga/éxito/error para consumo en UI.
// - Throttling básico (1.2s) al publicar ubicación del conductor para reducir presión en red/Firestore.

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_qorinti/repos/servicio_repository.dart';
import 'package:app_qorinti/modelos/servicio.dart';
import 'servicio_event.dart';
import 'servicio_state.dart';

class ServicioBloc extends Bloc<ServicioEvent, ServicioState> {
  final ServicioRepository repo;

  // Marca temporal para regular la frecuencia de actualizaciones de ubicación.
  DateTime? _lastLocPushAt;

  ServicioBloc(this.repo) : super(ServicioInicial()) {
    // Registro de manejadores de eventos
    on<CrearServicio>(_onCrearServicio);
    on<EscucharServicio>(_onEscucharServicio);
    on<ActualizarEstado>(_onActualizarEstado);
    on<IniciarServicio>(_onIniciarServicio);     
    on<CancelarServicio>(_onCancelarServicio);   
    on<CrearOfertaEvt>(_onCrearOferta);
    on<AceptarOfertaEvt>(_onAceptarOferta);
    on<ActualizarUbicacionConductor>(_onActualizarUbicacionConductor);
  }

  /// Crea un servicio nuevo y emite su ID si el proceso concluye correctamente.
  Future<void> _onCrearServicio(
    CrearServicio event,
    Emitter<ServicioState> emit,
  ) async {
    emit(ServicioCargando());
    try {
      final id = await repo.crearServicio(event.servicio);
      emit(ServicioCreado(id));
    } catch (e) {
      emit(ServicioError('Error al crear servicio: $e'));
    }
  }

  /// Escucha en tiempo real un servicio por ID. Emite estado de éxito con el modelo
  /// o error si el documento no existe o falla la suscripción.
  Future<void> _onEscucharServicio(
    EscucharServicio event,
    Emitter<ServicioState> emit,
  ) async {
    emit(ServicioCargando());
    await emit.forEach<Servicio?>(
      repo.escucharServicio(event.idServicio),
      onData: (s) => s != null
          ? ServicioExito(s)
          : const ServicioError("No existe servicio"),
      onError: (_, __) => const ServicioError("Error al escuchar servicio"),
    );
  }

  /// Solicita el cambio de estado del servicio (en curso, finalizado, cancelado, etc.).
  Future<void> _onActualizarEstado(
    ActualizarEstado event,
    Emitter<ServicioState> emit,
  ) async {
    try {
      await repo.actualizarEstado(event.idServicio, event.nuevoEstado);
    } catch (e) {
      emit(ServicioError('Error al actualizar estado: $e'));
    }
  }

  /// Inicia un servicio previamente aceptado.
  Future<void> _onIniciarServicio(
    IniciarServicio event,
    Emitter<ServicioState> emit,
  ) async {
    try {
      await repo.iniciarServicio(event.idServicio);
    } catch (e) {
      emit(ServicioError('Error al iniciar servicio: $e'));
    }
  }

  /// Cancela un servicio y refleja el cambio en el repositorio.
  Future<void> _onCancelarServicio(
    CancelarServicio event,
    Emitter<ServicioState> emit,
  ) async {
    try {
      await repo.cancelarServicio(event.idServicio);
    } catch (e) {
      emit(ServicioError('Error al cancelar servicio: $e'));
    }
  }

  /// Registra una oferta del conductor para un servicio en estado de recepción de ofertas.
  Future<void> _onCrearOferta(
    CrearOfertaEvt event,
    Emitter<ServicioState> emit,
  ) async {
    try {
      await repo.crearOferta(event.oferta);
    } catch (e) {
      emit(ServicioError('Error al crear oferta: $e'));
    }
  }

  /// Acepta una oferta específica, rechaza el resto y actualiza el servicio.
  Future<void> _onAceptarOferta(
    AceptarOfertaEvt event,
    Emitter<ServicioState> emit,
  ) async {
    try {
      await repo.aceptarOfertaYRechazarResto(
        servicioId: event.servicioId,
        ofertaId: event.ofertaId,
        conductorId: event.conductorId,
        vehiculoId: event.vehiculoId,
      );
    } catch (e) {
      emit(ServicioError('Error al aceptar oferta: $e'));
    }
  }

  /// Actualiza la ubicación del conductor con control de frecuencia para evitar
  /// envíos excesivos (throttling de 1200 ms entre actualizaciones).
  Future<void> _onActualizarUbicacionConductor(
    ActualizarUbicacionConductor event,
    Emitter<ServicioState> emit,
  ) async {
    try {
      final now = DateTime.now();
      if (_lastLocPushAt != null &&
          now.difference(_lastLocPushAt!).inMilliseconds < 1200) {
        return;
      }
      _lastLocPushAt = now;

      await repo.actualizarUbicacionConductor(
        idServicio: event.idServicio,
        lat: event.lat,
        lng: event.lng,
      );
    } catch (e) {
      // Silencioso por diseño: la UI no se ve interrumpida por fallos intermitentes de ubicación.
    }
  }
}
