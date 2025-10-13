// lib/pantallas/servicios/viaje_en_curso_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:app_qorinti/bloc/servicio/servicio_bloc.dart';
import 'package:app_qorinti/bloc/servicio/servicio_event.dart';
import 'package:app_qorinti/bloc/servicio/servicio_state.dart';
import 'package:app_qorinti/modelos/servicio.dart';
import 'package:app_qorinti/repos/servicio_repository.dart';
import 'calificar_servicio_screen.dart';
import 'finalizar_pago_sheet.dart' show FinalizarPagoResult, FinalizarPagoSheet;
import 'comprobante_demo_screen.dart';

// ---------------------------------------------------------------------------
// Función auxiliar para formatear valores monetarios en soles peruanos (PEN)
// ---------------------------------------------------------------------------
String formatPEN(num v) => 'S/ ${v.toStringAsFixed(2)}';

// ---------------------------------------------------------------------------
// Widget principal de pantalla de viaje en curso
// Muestra el seguimiento del viaje, ubicación y controles según rol (cliente o conductor)
// ---------------------------------------------------------------------------
class ViajeEnCursoScreen extends StatefulWidget {
  final String idServicio;  // ID del servicio en curso
  final bool esConductor;   // Indica si el usuario es conductor

  const ViajeEnCursoScreen({
    super.key,
    required this.idServicio,
    required this.esConductor,
  });

  @override
  State<ViajeEnCursoScreen> createState() => _ViajeEnCursoScreenState();
}

class _ViajeEnCursoScreenState extends State<ViajeEnCursoScreen> {
  GoogleMapController? _mapController;           // Controlador del mapa
  StreamSubscription<Position>? _posicionSub;    // Suscripción a flujo de posiciones GPS
  LatLng? _miUbicacion;                          // Última ubicación del usuario
  late ServicioBloc _bloc;                       // Bloc de servicio para manejar estado

  bool _yaMostroCalificacion = false;            // Control para evitar mostrar calificación más de una vez
  bool _iniciando = false;                       // Estado para bloqueo de acción de inicio
  bool _finalizando = false;                     // Estado para bloqueo de acción de fin
  bool _cancelando = false;                      // Estado para bloqueo de acción de cancelación

  // ValueNotifiers para markers y polilíneas (rutas) del mapa
  final ValueNotifier<Set<Marker>> _markersVN = ValueNotifier<Set<Marker>>({});
  final ValueNotifier<Set<Polyline>> _polylinesVN = ValueNotifier<Set<Polyline>>({});

  List<LatLng> _ultimaRuta = [];  // Guarda última ruta renderizada (para evitar recalcular si no cambió)

  // Colores institucionales y temáticos
  static const Color _brandBlue = Color(0xFF2A6DF4);
  static const Color _brandBlueDark = Color(0xFF1E4FBE);
  static const Color _ink = Color(0xFF0F172A);
  static const Color _slate = Color(0xFF64748B);
  static const Color _okGreenSoft = Color(0xFF24C17E);
  static const Color _amberSoft = Color(0xFFFFB020);
  static const Color _dangerRed = Color(0xFFE55252);

  // ---------------------------------------------------------------------------
  // Ciclo de vida del widget: inicialización
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _bloc = context.read<ServicioBloc>();                     // Obtiene instancia de Bloc activo
    _bloc.add(EscucharServicio(widget.idServicio));            // Empieza a escuchar actualizaciones del servicio
    _iniciarTrackingUbicacion();                               // Activa seguimiento de ubicación GPS
  }

  // ---------------------------------------------------------------------------
  // Limpieza de recursos al cerrar la pantalla
  // ---------------------------------------------------------------------------
  @override
  void dispose() {
    _posicionSub?.cancel();
    _mapController?.dispose();
    _markersVN.dispose();
    _polylinesVN.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Inicia el flujo de tracking de ubicación según plataforma
  // Configura permisos, ajustes de precisión y frecuencia de actualización
  // ---------------------------------------------------------------------------
  Future<void> _iniciarTrackingUbicacion() async {
    final servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      await Geolocator.openLocationSettings(); // Abre ajustes si está deshabilitado
      return;
    }

    // Solicita permisos de ubicación
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) return;
    }
    if (permiso == LocationPermission.deniedForever) return;

    // Configuración base de precisión y frecuencia
    LocationSettings settings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, 
    );

    // Ajustes específicos para Android e iOS
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
               defaultTargetPlatform == TargetPlatform.macOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
      );
    }

    // Suscribe al flujo continuo de posición
    _posicionSub?.cancel();
    _posicionSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      if (!mounted) return;

      setState(() {
        _miUbicacion = LatLng(pos.latitude, pos.longitude);
      });

      // Si el usuario es conductor, envía su ubicación al Bloc (Firebase o backend)
      if (widget.esConductor) {
        _bloc.add(
          ActualizarUbicacionConductor(
            widget.idServicio,
            pos.latitude,
            pos.longitude,
          ),
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Acción: el conductor inicia el viaje
  // ---------------------------------------------------------------------------
  Future<void> _iniciarViajeComoConductor(Servicio servicio) async {
    if (_iniciando) return;
    _iniciando = true;
    try {
      // Solo se puede iniciar si el estado actual es "aceptado"
      if (servicio.estado != EstadoServicio.aceptado) {
        _snack("El viaje no puede iniciarse en el estado actual.");
        return;
      }
      // Envía evento al Bloc para actualizar estado a "en_curso"
      _bloc.add(ActualizarEstado(widget.idServicio, EstadoServicio.en_curso));
      if (!mounted) return;
      _snack("🟢 Viaje iniciado");
    } finally {
      _iniciando = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Acción: el conductor finaliza el viaje, confirmando pago recibido (off-app)
  // ---------------------------------------------------------------------------
  Future<void> _finalizarViajeComoConductorConPago(Servicio servicio) async {
    if (_finalizando) return;
    _finalizando = true;

    try {
      if (servicio.estado != EstadoServicio.en_curso) {
        _snack("El viaje no puede finalizarse en el estado actual.");
        return;
      }

      // Despliega hoja modal inferior para confirmar pago directo
      final result = await showModalBottomSheet<FinalizarPagoResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => FinalizarPagoSheet(
          pagoDentroApp: false,
          metodoTexto: _labelMetodo(servicio.metodoPago),
          monto: servicio.precioFinal ?? servicio.precioEstimado,
          titulo: 'Finalizar viaje',
          mensaje:
              'Confirma que ya recibiste el pago directo y agrega una referencia si aplica.',
        ),
      );

      if (result == null) return;
      if (!result.pagoRecibido) {
        _snack('Debes confirmar que el pago fue recibido.');
        return;
      }

      // Actualiza datos del servicio en backend
      final repo = context.read<ServicioRepository>();
      await repo.finalizarServicioConPagoOffApp(
        servicioId: widget.idServicio,
        referenciaPagoExterno: result.referencia,
        observaciones: result.observaciones,
      );

      if (!mounted) return;

      // Si el servicio está asociado a empresa, se notifica
      final usaEmpresa =
          servicio.idEmpresa != null && servicio.idEmpresa!.isNotEmpty;
      if (usaEmpresa) {
        _snack('Este servicio se facturará a nombre de tu empresa.');
      }

      // Opción de generar comprobante DEMO
      final generarAhora = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('¿Generar comprobante (DEMO)?'),
          content: const Text(
            'Puedes emitir una boleta o factura DEMO con marca de agua para el cliente.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Después')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Generar ahora')),
          ],
        ),
      );

      // Generación opcional del comprobante
      if (generarAhora == true) {
        final total = servicio.precioFinal ?? servicio.precioEstimado ?? 0;
        final clienteTieneEmpresa = false;
        final empresaPreset = null;

        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ComprobanteDemoScreen(
              idServicio: widget.idServicio,
              total: total,
              fecha: DateTime.now(),
              clienteTieneEmpresa: clienteTieneEmpresa,
              empresaPreset: empresaPreset,
            ),
          ),
        );

        if (ok == true) {
          _snack('Comprobante DEMO generado y adjuntado');
        }
      }

      _snack("Viaje finalizado");

      // Redirige a pantalla de calificación post-servicio
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CalificarServicioScreen(
            idServicio: widget.idServicio,
            esConductor: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack("❌ Error al finalizar: $e");
    } finally {
      _finalizando = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Acción: el cliente cancela el viaje antes de que inicie o se complete
  // ---------------------------------------------------------------------------
  Future<void> _cancelarViajeComoCliente() async {
    if (_cancelando) return;
    _cancelando = true;

    try {
      // Diálogo de confirmación
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Cancelar viaje"),
          content: const Text("¿Seguro que deseas cancelar este viaje?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("No")),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Sí, cancelar")),
          ],
        ),
      );

      if (confirmar == true) {
        // Envía evento de actualización de estado
        _bloc.add(ActualizarEstado(widget.idServicio, EstadoServicio.cancelado));
        if (!mounted) return;
        _snack("Viaje cancelado");
        Navigator.pop(context);
      }
    } finally {
      _cancelando = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Cálculo de ruta “libre” (simulada) entre puntos del servicio
  // Genera trayectorias curvas suaves entre origen y destino para representación visual
  // ---------------------------------------------------------------------------
  Future<List<LatLng>?> _obtenerRutaLibre(List<LatLng> puntos) async {
    try {
      if (puntos.length < 2) return null;

      final result = <LatLng>[];
      for (int i = 0; i < puntos.length - 1; i++) {
        final a = puntos[i];
        final b = puntos[i + 1];

        // Crea una interpolación entre ambos puntos
        const steps = 40;
        for (int j = 0; j <= steps; j++) {
          final t = j / steps;
          final lat = a.latitude + (b.latitude - a.latitude) * t;
          final lng = a.longitude + (b.longitude - a.longitude) * t;

          // Aplica una pequeña curvatura visual
          final curveOffset = (math.sin(t * math.pi) * 0.0003);
          final curvedLat = lat + curveOffset;
          final curvedLng = lng - curveOffset / 2;

          result.add(LatLng(curvedLat, curvedLng));
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error generando ruta libre: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Actualiza la ruta dibujada en el mapa si ha habido cambios
  // ---------------------------------------------------------------------------
  Future<void> _actualizarRuta(List<LatLng> puntosValidos) async {
    if (puntosValidos.length < 2) return;

    // Evita redibujar si la ruta es igual a la última generada
    bool iguales = false;
    if (_ultimaRuta.length == puntosValidos.length) {
      iguales = true;
      for (int i = 0; i < puntosValidos.length; i++) {
        if (puntosValidos[i] != _ultimaRuta[i]) {
          iguales = false;
          break;
        }
      }
    }

    if (iguales) return;

    _ultimaRuta = List<LatLng>.from(puntosValidos);
    final decodedPoints = await _obtenerRutaLibre(puntosValidos);
    if (decodedPoints != null && decodedPoints.isNotEmpty && mounted) {
      _polylinesVN.value = {
        Polyline(
          polylineId: const PolylineId('ruta_libre'),
          width: 6,
          color: _brandBlue,
          points: decodedPoints,
        ),
      };
    }
  }
  // ---------------------------------------------------------------------------
  // Mapea el estado del servicio a un color para el chip informativo
  // ---------------------------------------------------------------------------
  Color _colorEstado(EstadoServicio estado) {
    switch (estado) {
      case EstadoServicio.aceptado:
        return _amberSoft;
      case EstadoServicio.en_curso:
        return _okGreenSoft;
      case EstadoServicio.finalizado:
        return Colors.grey.shade600;
      case EstadoServicio.cancelado:
        return _dangerRed;
      case EstadoServicio.pendiente_ofertas:
        return _brandBlueDark;
    }
  }

  // ---------------------------------------------------------------------------
  // Ajusta la cámara del mapa para que abarque todos los marcadores visibles
  // ---------------------------------------------------------------------------
  void _fitToAll(Set<Marker> markers) {
    if (_mapController == null || markers.isEmpty) return;
    final lats = markers.map((m) => m.position.latitude);
    final lngs = markers.map((m) => m.position.longitude);
    final sw =
        LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b));
    final ne =
        LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b));
    final bounds = LatLngBounds(southwest: sw, northeast: ne);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  // ---------------------------------------------------------------------------
  // Etiqueta amigable para el método de pago
  // ---------------------------------------------------------------------------
  String _labelMetodo(MetodoPago? m) {
    switch (m) {
      case MetodoPago.yape:
        return 'Yape';
      case MetodoPago.plin:
        return 'Plin';
      case MetodoPago.transferencia:
        return 'Transferencia';
      case MetodoPago.efectivo:
      default:
        return 'Efectivo';
    }
  }

  // ---------------------------------------------------------------------------
  // Helper para mostrar un SnackBar breve
  // ---------------------------------------------------------------------------
  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  // ---------- UI helpers (estéticos) ----------

  // Botón de acción con gradiente y sombra (estilo primario)
  Widget _gradientActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    List<Color>? colors,
  }) {
    final cs = colors ?? const [_brandBlue, _brandBlueDark];
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: cs),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: cs.last.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: ElevatedButton.icon(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: .2),
            ),
            icon: Icon(icon),
            label: Text(label),
          ),
        ),
      ),
    );
  }

  // Pastilla (pill) informativa con icono y color de fondo
  Widget _pill({
    required IconData icon,
    required String text,
    required Color color,
    Color? textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: color.withOpacity(.25), blurRadius: 8, offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: textColor ?? Colors.white),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: textColor ?? Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // Tarjeta translúcida (glass) con sombra suave para overlays sobre el mapa
  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(12),
    Color bg = const Color(0xCCFFFFFF),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 6))
        ],
      ),
      padding: padding,
      child: child,
    );
  }

  // Calcula padding del mapa según si hay botón primario y/o aviso de comisión
  EdgeInsets _calcMapPadding({required bool hasPrimaryBtn, required bool showCommission}) {
    const double top = 100.0;
    double bottom = hasPrimaryBtn ? 120.0 : 24.0;
    if (showCommission) bottom += 80.0;
    return EdgeInsets.fromLTRB(0, top, 0, bottom);
  }

  // ---------------------------------------------------------------------------
  // Build principal: arma el mapa, overlays, chips informativos y acciones
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Viaje en curso"),
        toolbarHeight: 56,
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0.5,
      ),
      // Listener para reaccionar a cambios de estado del servicio (vía Bloc)
      body: BlocListener<ServicioBloc, ServicioState>(
        listener: (context, state) {
          // Si el cliente detecta que el servicio finalizó, redirige a calificar
          if (state is ServicioExito &&
              !widget.esConductor &&
              state.servicio.estado == EstadoServicio.finalizado &&
              !_yaMostroCalificacion) {
            _yaMostroCalificacion = true;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CalificarServicioScreen(
                  idServicio: widget.idServicio,
                  esConductor: false,
                ),
              ),
            );
          }
        },
        child: BlocBuilder<ServicioBloc, ServicioState>(
          builder: (context, state) {
            // Cargando datos del servicio
            if (state is ServicioCargando) {
              return const Center(child: CircularProgressIndicator());
            }
            // Estado con datos del servicio
            if (state is ServicioExito) {
              final s = state.servicio;

              // Prepara puntos con coordenadas válidas y sus marcadores
              final puntosValidos = <LatLng>[];
              final markers = <Marker>{};

              for (int i = 0; i < s.ruta.length; i++) {
                final p = s.ruta[i];
                if (p.lat == null || p.lng == null) continue;
                final pos = LatLng(p.lat!, p.lng!);
                puntosValidos.add(pos);

                final esOrigen = i == 0;
                final esDestino = i == s.ruta.length - 1;
                markers.add(
                  Marker(
                    markerId: MarkerId('p$i'),
                    position: pos,
                    infoWindow: InfoWindow(
                        title: esOrigen
                            ? 'Origen'
                            : (esDestino ? 'Destino' : 'Parada ${i.toString()}'),
                        snippet: p.direccion),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        esOrigen
                            ? BitmapDescriptor.hueGreen
                            : (esDestino
                                ? BitmapDescriptor.hueRed
                                : BitmapDescriptor.hueAzure)),
                  ),
                );
              }

              // Tras el frame, actualiza marcadores y ruta si hubo cambios
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  final curr = _markersVN.value;
                  final changed = (curr.length != markers.length) ||
                      !_sameMarkers(curr, markers);
                  if (changed) {
                    _markersVN.value = markers;
                    _fitToAll(markers);
                  }
                  _actualizarRuta(puntosValidos);
                }
              });

              // Posición inicial por defecto si no hay puntos con coordenadas
              final initial = puntosValidos.isNotEmpty
                  ? puntosValidos.first
                  : const LatLng(-12.0464, -77.0428);

              // Callback de creación del mapa: ajusta cámara a todos los marcadores
              void onCreated(GoogleMapController c) {
                _mapController = c;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _fitToAll(_markersVN.value);
                });
              }

              // Determina el botón principal según rol y estado del servicio
              Widget? primaryButton;
              if (widget.esConductor) {
                if (s.estado == EstadoServicio.aceptado) {
                  primaryButton = _gradientActionButton(
                    onPressed: _iniciando ? null : () => _iniciarViajeComoConductor(s),
                    icon: Icons.play_arrow,
                    label: "Iniciar viaje",
                    colors: const [_brandBlue, _brandBlueDark],
                  );
                } else if (s.estado == EstadoServicio.en_curso) {
                  primaryButton = _gradientActionButton(
                    onPressed:
                        _finalizando ? null : () => _finalizarViajeComoConductorConPago(s),
                    icon: Icons.flag,
                    label: "Finalizar viaje",
                    colors: const [_okGreenSoft, Color(0xFF0FAF6A)],
                  );
                }
              } else {
                if (s.estado == EstadoServicio.aceptado) {
                  primaryButton = _gradientActionButton(
                    onPressed: _cancelando ? null : _cancelarViajeComoCliente,
                    icon: Icons.cancel,
                    label: "Cancelar viaje",
                    colors: const [_dangerRed, Color(0xFFB93131)],
                  );
                }
              }

              // Chips con info de método de pago y monto
              final chipsPago = <Widget>[];
              if (s.metodoPago case final m?) {
                chipsPago.add(_pill(
                  icon: Icons.payments_rounded, // ícono neutro (sin símbolo $)
                  text: _labelMetodo(m),
                  color: _brandBlueDark,
                ));
              }
              if ((s.precioFinal ?? s.precioEstimado) != null) {
                final monto = (s.precioFinal ?? s.precioEstimado)!;
                chipsPago.add(_pill(
                  icon: Icons.account_balance_wallet, 
                  text: formatPEN(monto),             
                  color: Colors.black87,
                ));
              }

              // Padding dinámico para no tapar elementos del mapa
              final mapPadding = _calcMapPadding(
                hasPrimaryBtn: primaryButton != null,
                showCommission: widget.esConductor,
              );

              // --------------------- UI apilada (Stack) ----------------------
              return Stack(
                children: [
                  // Mapa con markers y polylines reactive vía ValueListenableBuilders
                  ValueListenableBuilder<Set<Marker>>(
                    valueListenable: _markersVN,
                    builder: (_, markersValue, __) {
                      return ValueListenableBuilder<Set<Polyline>>(
                        valueListenable: _polylinesVN,
                        builder: (_, polylinesValue, __) {
                          return GoogleMap(
                            initialCameraPosition: CameraPosition(target: initial, zoom: 14),
                            onMapCreated: onCreated,
                            myLocationEnabled: true,
                            myLocationButtonEnabled: true,
                            markers: markersValue,
                            polylines: polylinesValue,
                            padding: mapPadding,
                          );
                        },
                      );
                    },
                  ),

                  // Overlay superior: estado del servicio y chips de pago/monto
                  Positioned(
                    top: 10,
                    left: 12,
                    right: 12,
                    child: SafeArea(
                      child: _glassCard(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            _pill(
                              icon: Icons.info,
                              text: "Estado: ${s.estado.name.toUpperCase()}",
                              color: _colorEstado(s.estado),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.end,
                                  children: chipsPago,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Aviso para conductor: recordatorio de comisión y cobro directo
                  if (widget.esConductor)
                    Positioned(
                      bottom: (primaryButton != null) ? 96 : 24,
                      left: 16,
                      right: 16,
                      child: _glassCard(
                        bg: const Color(0xE6FFFFFF),
                        child: Row(
                          children: const [
                            Icon(Icons.info_outline_rounded, color: _slate),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Recuerda: cobro directo al cliente. Se generará una comisión pendiente (5%).",
                                style:
                                    TextStyle(color: _slate, height: 1.25),
                                textAlign: TextAlign.left,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Aviso adicional si el conductor opera bajo empresa (facturación)
                  if (widget.esConductor &&
                      s.idEmpresa != null &&
                      s.idEmpresa!.isNotEmpty)
                    Positioned(
                      bottom: (primaryButton != null) ? 170 : 100,
                      left: 20,
                      right: 20,
                      child: _glassCard(
                        bg: const Color(0xE6FFFFFF),
                        child: Row(
                          children: const [
                            Icon(Icons.apartment_rounded,
                                color: _brandBlueDark),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Este servicio se emitirá a nombre de tu empresa.",
                                style:
                                    TextStyle(color: _brandBlueDark, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Botón primario flotante (iniciar/finalizar/cancelar)
                  if (primaryButton != null)
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: primaryButton,
                    ),
                ],
              );
            }
            // Estado de error del Bloc
            if (state is ServicioError) {
              return Center(child: Text("❌ Error: ${state.mensaje}"));
            }
            // Estado por defecto mientras no hay datos
            return const Center(child: Text("Esperando datos del viaje..."));
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Compara dos conjuntos de marcadores por id y posición (para evitar rebuilds)
  // ---------------------------------------------------------------------------
  bool _sameMarkers(Set<Marker> a, Set<Marker> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    final ma = {for (final m in a) m.markerId.value: m};
    for (final m in b) {
      final other = ma[m.markerId.value];
      if (other == null) return false;
      if (other.position != m.position) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Estilo base para botones elevados con color de fondo y esquinas redondeadas
  // (Helper no usado en este archivo, pero disponible para consistencia)
  // ---------------------------------------------------------------------------
  ButtonStyle _btnStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
