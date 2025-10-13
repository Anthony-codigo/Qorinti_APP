// lib/pantallas/servicios/seleccionar_tipo_ruta_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart' as places;
import 'package:app_qorinti/modelos/servicio.dart';
import 'package:app_qorinti/modelos/plan_ruta.dart';

class SeleccionarTipoRutaScreen extends StatefulWidget {
  const SeleccionarTipoRutaScreen({super.key});

  @override
  State<SeleccionarTipoRutaScreen> createState() => _SeleccionarTipoRutaScreenState();
}

class _SeleccionarTipoRutaScreenState extends State<SeleccionarTipoRutaScreen> {

  // Clave de Google Places para autocompletar/places. Usa String.fromEnvironment
  // para poder inyectarla en build-time sin hardcodear.
  static const String _PLACES_API_KEY =
      String.fromEnvironment('PLACES_API_KEY', defaultValue: 'Colocar aqui tu key de tu cuenta de google maps sdk primero tenerlo habilitado y pegar');

  // Paleta de colores base de la pantalla
  static const Color _brandBlue     = Color(0xFF2A6DF4);
  static const Color _brandBlueDark = Color(0xFF1E4FBE);
  static const Color _okGreenSoft   = Color(0xFF24C17E);
  static const Color _ink           = Color(0xFF0F172A);
  static const Color _slate         = Color(0xFF64748B);

  // Controlador del mapa (Google Maps)
  gmaps.GoogleMapController? _map;
  // Índice del punto de ruta actualmente seleccionado
  int _indexSeleccionado = 0;

  // Cliente de Google Places y bandera de disponibilidad
  late final places.FlutterGooglePlacesSdk _places;
  bool _placesOk = false;

  // Tipo de servicio seleccionado (taxi/carga/mudanza)
  TipoServicio _tipo = TipoServicio.taxi;

  // Lista de puntos que componen la ruta (origen, paradas intermedias, destino).
  // Inicializa con dos puntos vacíos (origen y destino).
  final List<PuntoRuta> _ruta = <PuntoRuta>[
    const PuntoRuta(direccion: ''), 
    const PuntoRuta(direccion: ''), 
  ];

  // Controladores de los TextField de dirección, mapeados por índice
  final Map<int, TextEditingController> _dirCtrls = {};

  // Campos auxiliares para detalle de carga
  final _pesoCtrl = TextEditingController();
  final _volCtrl = TextEditingController();
  bool _requiereAyudantes = false;
  final _ayudCtrl = TextEditingController(text: '1');
  bool _requiereMontacargas = false;
  final _notasCtrl = TextEditingController();
  bool _panelCargaAbierto = false;

  // Flag derivado: indica si el tipo actual es de carga/mudanza
  bool get _esCarga => _tipo == TipoServicio.carga_pesada || _tipo == TipoServicio.mudanza;

  // Manejo de permisos/estado de geolocalización
  bool _ubicacionDenegada = false;
  bool _resolviendoDireccion = false;

  // Debounce para autocompletar de Places y estado de sugerencias
  Timer? _debounce;
  int _focusedIndex = -1;
  List<places.AutocompletePrediction> _sugs = [];
  bool _sugsLoading = false;

  // Indicadores de ruta calculados localmente
  double? _distanciaKmCalc; // distancia total (Haversine) entre puntos
  int? _etaMinCalc;         // ETA aproximado en minutos
  int? _slaMinSugerido;     // SLA objetivo en minutos

  // Velocidad promedio estimada (km/h) según tipo de servicio
  double get _velocidadKmH {
    switch (_tipo) {
      case TipoServicio.taxi:
        return 30;
      case TipoServicio.carga_ligera:
        return 24;
      case TipoServicio.carga_pesada:
        return 18;
      case TipoServicio.mudanza:
        return 15;
    }
  }

  @override
  void initState() {
    super.initState();
    // Inicializa Places SDK y verifica disponibilidad
    _places = places.FlutterGooglePlacesSdk(_PLACES_API_KEY);
    _probePlaces();
    // Intenta obtener ubicación del dispositivo para precargar origen
    _initUbicacion();
    // Calcula indicadores (distancia/ETA/SLA) con estado inicial
    _recalcularIndicadores();
  }

  // Realiza una consulta mínima para verificar si el API de Places responde OK.
  Future<void> _probePlaces() async {
    try {
      await _places.findAutocompletePredictions('Lima', countries: const ['pe']);
      if (mounted) setState(() => _placesOk = true);
    } catch (_) {
      if (mounted) setState(() => _placesOk = false);
    }
  }

  @override
  void dispose() {
    // Libera controladores y timers
    _pesoCtrl.dispose();
    _volCtrl.dispose();
    _ayudCtrl.dispose();
    _notasCtrl.dispose();
    for (final c in _dirCtrls.values) {
      c.dispose();
    }
    _debounce?.cancel();
    super.dispose();
  }

  // Obtiene (o crea) el controlador de texto para el índice i
  TextEditingController _ctrlFor(int i) {
    return _dirCtrls.putIfAbsent(
      i,
      () => TextEditingController(text: _ruta[i].direccion),
    );
  }

  // Inicializa la ubicación: pide permisos, toma la posición y resuelve dirección
  Future<void> _initUbicacion() async {
    try {
      final on = await Geolocator.isLocationServiceEnabled();
      if (!on) {
        setState(() => _ubicacionDenegada = true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _ubicacionDenegada = true);
        return;
      }

      setState(() => _ubicacionDenegada = false);

      // Toma posición GPS y hace reverse geocoding para completar texto
      final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final dir = await _reverse(p.latitude, p.longitude);

      setState(() {
        _ruta[0] = PuntoRuta(direccion: dir, lat: p.latitude, lng: p.longitude);
        _ctrlFor(0).text = dir;
        _indexSeleccionado = 0;
      });

      // Centra el mapa en la posición detectada
      _map?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(gmaps.LatLng(p.latitude, p.longitude), 16),
      );

      _recalcularIndicadores();
    } catch (_) {
      // Silencioso: si falla, el usuario puede escribir la dirección manualmente
    }
  }

  // Reverse geocoding: coord -> dirección legible
  Future<String> _reverse(double lat, double lng) async {
    setState(() => _resolviendoDireccion = true);
    try {
      final rs = await placemarkFromCoordinates(lat, lng);
      if (rs.isNotEmpty) {
        final p = rs.first;
        final calle = (p.street ?? '').trim();
        final dist = (p.subLocality ?? p.locality ?? '').trim();
        final out = [calle, dist].where((e) => e.isNotEmpty).join(', ');
        return out.isEmpty ? 'Dirección aproximada' : out;
      }
    } catch (_) {
      // Errores de red o permisos se manejan mostrando estado genérico
    } finally {
      if (mounted) setState(() => _resolviendoDireccion = false);
    }
    return 'Dirección';
  }

  // Actualiza el punto seleccionado con una posición elegida en el mapa
  Future<void> _setDesdeMapa(gmaps.LatLng pos) async {
    final i = _indexSeleccionado.clamp(0, _ruta.length - 1);
    final dir = await _reverse(pos.latitude, pos.longitude);
    setState(() {
      _ruta[i] = PuntoRuta(direccion: dir, lat: pos.latitude, lng: pos.longitude);
      _ctrlFor(i).text = dir;
    });
    _recalcularIndicadores();
  }

  // Geocoding por texto ingresado: busca coordenadas a partir de la dirección
  Future<void> _ubicarPorTexto(int index) async {
    final q = _ctrlFor(index).text.trim();
    if (q.isEmpty) return;
    try {
      final rs = await locationFromAddress(q);
      if (rs.isEmpty) {
        _snack('No se encontró la dirección.');
        return;
      }
      final loc = rs.first;
      final resolved = await _reverse(loc.latitude, loc.longitude);
      setState(() {
        _ruta[index] = PuntoRuta(direccion: resolved, lat: loc.latitude, lng: loc.longitude);
        _ctrlFor(index).text = resolved;
        _indexSeleccionado = index;
      });
      _map?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(gmaps.LatLng(loc.latitude, loc.longitude), 16),
      );
      _recalcularIndicadores();
    } catch (e) {
      _snack('No se pudo ubicar: $e');
    }
  }

  // Manejo de cambios en el campo de dirección (con debounce para Places)
  void _onQueryChanged(int index, String v) {
    // Mantiene el texto mientras conserva coordenadas previas si existen
    _ruta[index] = PuntoRuta(direccion: v, lat: _ruta[index].lat, lng: _ruta[index].lng);
    _focusedIndex = index;

    if (!_placesOk) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = v.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _sugs = []);
        return;
      }
      try {
        if (mounted) setState(() => _sugsLoading = true);
        final pred = await _places.findAutocompletePredictions(
          q,
          countries: const ['pe'],
        );
        final list = pred.predictions;
        if (mounted) {
          setState(() {
            _sugs = list.length > 6 ? list.sublist(0, 6) : list;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _sugs = []);
      } finally {
        if (mounted) setState(() => _sugsLoading = false);
      }
    });
  }

  // Aplica una predicción de Autocomplete al punto (coloca dirección + coords)
  Future<void> _aplicarPrediccion(int index, places.AutocompletePrediction it) async {
    try {
      final det = await _places.fetchPlace(
        it.placeId,
        fields: const [places.PlaceField.Location, places.PlaceField.Address],
      );
      final loc = det.place?.latLng;
      if (loc == null) return;
      final address = det.place?.address ?? it.fullText;
      setState(() {
        _ruta[index] = PuntoRuta(direccion: address, lat: loc.lat, lng: loc.lng);
        _ctrlFor(index).text = address;
        _sugs = [];
        _focusedIndex = -1;
        _indexSeleccionado = index;
      });
      _map?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(gmaps.LatLng(loc.lat, loc.lng), 16),
      );
      _recalcularIndicadores();
    } catch (e) {
      _snack('No se pudo obtener la dirección.');
    }
  }

  // Inserta una parada intermedia antes del destino
  void _agregarParada() {
    setState(() {
      final insertAt = _ruta.length - 1;
      _ruta.insert(insertAt, const PuntoRuta(direccion: ''));
      _dirCtrls[insertAt] = TextEditingController(text: '');
      _indexSeleccionado = insertAt;
    });
    _recalcularIndicadores();
  }

  // Elimina una parada intermedia (no permite eliminar origen/destino)
  void _eliminarPunto(int index) {
    if (index == 0 || index == _ruta.length - 1) return;
    setState(() {
      _ruta.removeAt(index);
      _dirCtrls.remove(index)?.dispose();
      // Reindexa controladores para mantener coherencia con _ruta
      final newMap = <int, TextEditingController>{};
      for (int i = 0; i < _ruta.length; i++) {
        newMap[i] = _dirCtrls[i] ?? TextEditingController(text: _ruta[i].direccion);
      }
      _dirCtrls
        ..clear()
        ..addAll(newMap);
      _indexSeleccionado = 0;
      _sugs = [];
      _focusedIndex = -1;
    });
    _recalcularIndicadores();
  }

  // Reordena una parada hacia arriba (sin mover origen)
  void _moverArriba(int index) {
    if (index <= 1) return;
    setState(() {
      final tmp = _ruta[index];
      _ruta.removeAt(index);
      _ruta.insert(index - 1, tmp);

      // Sincroniza controladores de texto
      final c = _dirCtrls.remove(index) ?? TextEditingController(text: tmp.direccion);
      final other = _dirCtrls.remove(index - 1);
      _dirCtrls[index - 1] = c;
      if (other != null) _dirCtrls[index] = other;

      _indexSeleccionado = index - 1;
    });
    _recalcularIndicadores();
  }

  // Reordena una parada hacia abajo (sin mover destino)
  void _moverAbajo(int index) {
    if (index >= _ruta.length - 2) return;
    setState(() {
      final tmp = _ruta[index];
      _ruta.removeAt(index);
      _ruta.insert(index + 1, tmp);

      // Sincroniza controladores de texto
      final c = _dirCtrls.remove(index) ?? TextEditingController(text: tmp.direccion);
      final other = _dirCtrls.remove(index + 1);
      _dirCtrls[index + 1] = c;
      if (other != null) _dirCtrls[index] = other;

      _indexSeleccionado = index + 1;
    });
    _recalcularIndicadores();
  }

  // Distancia entre dos puntos (km) usando fórmula de Haversine
  double _distKmHaversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Radio de la Tierra en km
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) *
            math.cos(lat2 * (math.pi / 180.0)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  // Recalcula indicadores: distancia total, ETA y SLA sugerido
  void _recalcularIndicadores() {
  double totalKm = 0.0;
  for (int i = 0; i < _ruta.length - 1; i++) {
    final a = _ruta[i];
    final b = _ruta[i + 1];
    if (a.lat != null && a.lng != null && b.lat != null && b.lng != null) {
      totalKm += _distKmHaversine(a.lat!, a.lng!, b.lat!, b.lng!);
    }
  }

  final origenOk = _ruta.first.lat != null && _ruta.first.lng != null;
  final destinoOk = _ruta.last.lat != null && _ruta.last.lng != null;

  if (!origenOk || !destinoOk) {
    setState(() {
      _distanciaKmCalc = null;
      _etaMinCalc = null;
      _slaMinSugerido = 30;
    });
    return;
  }

  final v = _velocidadKmH;

  int eta = ((totalKm / v) * 60).round();

  // Penalización/tiempo adicional por paradas intermedias según tipo
  int paradas = (_ruta.length - 2).clamp(0, 10);
  int extraPorParada;
  switch (_tipo) {
    case TipoServicio.taxi:
      extraPorParada = 1;
      break;
    case TipoServicio.carga_ligera:
      extraPorParada = 2;
      break;
    case TipoServicio.carga_pesada:
      extraPorParada = 4;
      break;
    case TipoServicio.mudanza:
      extraPorParada = 5;
      break;
  }

  eta += paradas * extraPorParada;

  // ETA mínimo de 5 minutos para evitar valores irreales
  if (eta < 5) eta = 5;

  // SLA sugerido = 120% del ETA, acotado entre 30 y 180 min
  final sla = (eta * 1.2).round().clamp(30, 180);

  setState(() {
    _distanciaKmCalc = totalKm;
    _etaMinCalc = eta;
    _slaMinSugerido = sla;
  });
}

  // Helper: determina si un punto tiene coordenadas válidas
  bool _puntoTieneCoords(PuntoRuta p) => (p.lat != null && p.lng != null);

  // Confirma y retorna el PlanRuta construido a la pantalla anterior
  void _confirmar() {
    final origenOK = _puntoTieneCoords(_ruta.first);
    final destinoOK = _puntoTieneCoords(_ruta.last);
    if (!origenOK || !destinoOK) {
      _snack('Selecciona ubicaciones válidas para origen y destino.');
      return;
    }

    final plan = PlanRuta(
      tipoServicio: _tipo,
      ruta: _ruta,
      distanciaKm: _distanciaKmCalc,
      tiempoEstimadoMin: _etaMinCalc,
      pesoTon: _esCarga ? (double.tryParse(_pesoCtrl.text.replaceAll(',', '.')) ?? 0) : null,
      volumenM3: _esCarga ? (double.tryParse(_volCtrl.text.replaceAll(',', '.')) ?? 0) : null,
      requiereAyudantes: _esCarga ? _requiereAyudantes : null,
      cantidadAyudantes: _esCarga ? int.tryParse(_ayudCtrl.text) : null,
      requiereMontacargas: _esCarga ? _requiereMontacargas : null,
      notasCarga: _esCarga ? (_notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim()) : null,
    );

    // Valida reglas de PlanRuta (por ejemplo: origen/destino, campos de carga, etc.)
    final err = plan.validar();
    if (err != null) {
      _snack(err);
      return;
    }
    // Devuelve el plan a la pantalla que la invocó
    Navigator.pop(context, plan);
  }

  // Chip estilizado para seleccionar tipo de servicio
  Widget _chipServicio(String label, IconData icon, TipoServicio v) {
    final sel = _tipo == v;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: sel ? Colors.white : _brandBlueDark),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: sel,
      onSelected: (_) => setState(() {
        _tipo = v;
        // Si deja de ser carga, cierra el panel de detalles de carga
        if (!_esCarga) _panelCargaAbierto = false;
        _recalcularIndicadores();
      }),
      selectedColor: _brandBlue,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: sel ? Colors.white : _ink,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: sel ? _brandBlueDark : Colors.black12),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  // Pequeña pastilla de texto+icono usada en indicadores
  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _brandBlueDark),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  // Tarjeta que muestra los indicadores estimados de la ruta (distancia, ETA, SLA)
  Widget _indicadoresCard() {
    final distTxt = (_distanciaKmCalc ?? 0) > 0 ? '${_distanciaKmCalc!.toStringAsFixed(2)} km' : '—';
    final etaTxt  = _etaMinCalc != null ? '${_etaMinCalc!} min' : '—';
    final slaTxt  = _slaMinSugerido != null ? '${_slaMinSugerido!} min' : '—';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6))],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Indicadores (estimados)', style: TextStyle(fontWeight: FontWeight.w800)),
          _pill(Icons.social_distance, '📍Distancia estimada: $distTxt'),
          _pill(Icons.timer, '⏱ Tiempo estimado de viaje: $etaTxt'),
          _pill(Icons.flag, '🎯 Tiempo objetivo de servicio: $slaTxt'),
        ],
      ),
    );
  }

  // Botón con gradiente usado para CTA principal (Usar esta ruta)
  Widget _gradientButton({
    required VoidCallback onPressed,
    required String label,
    IconData? icon,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_okGreenSoft, Color(0xFF0FAF6A)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.20), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: .2),
        ),
        icon: Icon(icon ?? Icons.check),
        label: Text(label),
      ),
    );
  }

  // Snackbar helper
  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }
  // ---------------------------------------------------------------------------
  // MÉTODO BUILD: construye toda la interfaz de usuario principal
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Genera marcadores del mapa en base a los puntos de la ruta
    final markers = <gmaps.Marker>{};
    for (int i = 0; i < _ruta.length; i++) {
      final p = _ruta[i];
      if (p.lat != null && p.lng != null) {
        markers.add(
          gmaps.Marker(
            markerId: gmaps.MarkerId('p$i'),
            position: gmaps.LatLng(p.lat!, p.lng!),
            draggable: true,
            onDragEnd: (pos) => _setDesdeMapa(pos),
            infoWindow: gmaps.InfoWindow(
              title: i == 0 ? 'Origen' : (i == _ruta.length - 1 ? 'Destino' : 'Parada ${i.toString()}'),
            ),
            // Cambia color del marcador según tipo de punto
            icon: i == 0
                ? gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueGreen)
                : (i == _ruta.length - 1
                    ? gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueRed)
                    : gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueAzure)),
            onTap: () => setState(() => _indexSeleccionado = i),
          ),
        );
      }
    }

    // Ajustes para teclado y altura del mapa
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final tecladoAbierto = bottomInset > 0;
    final mapHeight = tecladoAbierto ? 180.0 : 300.0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Seleccionar tipo y ruta'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Alerta si la ubicación está deshabilitada o denegada
            if (_ubicacionDenegada)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: MaterialBanner(
                  backgroundColor: Colors.amber.shade50,
                  leading: const Icon(Icons.location_off, color: Colors.orange),
                  content: const Text(
                    'La ubicación está desactivada o sin permisos. Actívala para fijar el origen automáticamente.',
                  ),
                  actions: [
                    TextButton(onPressed: _initUbicacion, child: const Text('Reintentar')),
                  ],
                ),
              ),

            // Mapa principal con markers y animaciones
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: mapHeight,
                  child: Stack(
                    children: [
                      gmaps.GoogleMap(
                        initialCameraPosition: const gmaps.CameraPosition(
                          target: gmaps.LatLng(-12.0464, -77.0428),
                          zoom: 12,
                        ),
                        onMapCreated: (c) => _map = c,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        markers: markers,
                        onTap: _setDesdeMapa,
                        padding: EdgeInsets.only(bottom: tecladoAbierto ? 0 : 12),
                      ),
                      // Indicador de carga mientras se resuelve dirección por coordenadas
                      if (_resolviendoDireccion)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Row(
                                children: const [
                                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                  SizedBox(width: 8),
                                  Text('Resolviendo dirección…'),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Panel inferior scrollable con chips, lista de puntos y controles
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + bottomInset),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Chips para elegir tipo de servicio
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6))],
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chipServicio('Taxi', Icons.local_taxi, TipoServicio.taxi),
                              _chipServicio('Carga ligera', Icons.local_shipping_outlined, TipoServicio.carga_ligera),
                              _chipServicio('Carga pesada', Icons.local_shipping_rounded, TipoServicio.carga_pesada),
                              _chipServicio('Mudanza', Icons.home_work_outlined, TipoServicio.mudanza),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Indicadores de distancia, tiempo, SLA
                        _indicadoresCard(),
                        const SizedBox(height: 10),

                        // Lista de puntos (origen, paradas, destino)
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _ruta.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _itemRuta(i),
                        ),
                        const SizedBox(height: 12),

                        // Panel de carga opcional
                        if (_esCarga) _panelCarga(),
                        const SizedBox(height: 14),

                        // Botones inferiores: agregar parada y confirmar ruta
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _agregarParada,
                                icon: const Icon(Icons.add_location_alt),
                                label: const Text('Agregar parada'),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _gradientButton(
                                onPressed: _confirmar,
                                label: 'Usar esta ruta',
                                icon: Icons.check,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Construcción de cada tarjeta de punto de ruta (origen, parada, destino)
  // ---------------------------------------------------------------------------
  Widget _itemRuta(int i) {
    final esOrigen = i == 0;
    final esDestino = i == _ruta.length - 1;
    final titulo = esOrigen ? 'Origen' : (esDestino ? 'Destino' : 'Parada ${i.toString()}');
    final ctrl = _ctrlFor(i);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado con ícono y botones de mover/eliminar
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: esOrigen
                      ? _okGreenSoft.withOpacity(.15)
                      : (esDestino ? Colors.red.withOpacity(.15) : _brandBlue.withOpacity(.15)),
                  child: Icon(
                    esOrigen ? Icons.trip_origin : (esDestino ? Icons.flag : Icons.location_on_outlined),
                    size: 18,
                    color: esOrigen ? _okGreenSoft : (esDestino ? Colors.red : _brandBlueDark),
                  ),
                ),
                const SizedBox(width: 8),
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
                const Spacer(),
                // Controles solo para paradas intermedias
                if (!esOrigen && !esDestino) ...[
                  IconButton(tooltip: 'Mover arriba', icon: const Icon(Icons.arrow_upward), onPressed: () => _moverArriba(i)),
                  IconButton(tooltip: 'Mover abajo', icon: const Icon(Icons.arrow_downward), onPressed: () => _moverAbajo(i)),
                  IconButton(tooltip: 'Eliminar parada', icon: const Icon(Icons.delete_outline), onPressed: () => _eliminarPunto(i)),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Campo de texto para escribir dirección o usar sugerencias
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: 'Escribe la dirección…',
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
              ),
              onTap: () => setState(() {
                _indexSeleccionado = i;
                _focusedIndex = i;
              }),
              onChanged: (v) => _onQueryChanged(i, v),
              onSubmitted: (_) => _ubicarPorTexto(i),
              textInputAction: TextInputAction.search,
            ),

            // Despliega sugerencias de Google Places (autocomplete)
            if (_placesOk && _focusedIndex == i && (_sugsLoading || _sugs.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                ),
                constraints: const BoxConstraints(maxHeight: 180),
                child: _sugsLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                          child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _sugs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, j) {
                          final it = _sugs[j];
                          final sec = it.secondaryText; 
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(it.primaryText),
                            subtitle: sec.isEmpty ? null : Text(sec),
                            onTap: () => _aplicarPrediccion(i, it),
                          );
                        },
                      ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Panel de detalles adicionales cuando el servicio es de tipo CARGA/MUDANZA
  // ---------------------------------------------------------------------------
  Widget _panelCarga() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        initiallyExpanded: _panelCargaAbierto,
        onExpansionChanged: (v) => setState(() => _panelCargaAbierto = v),
        leading: const Icon(Icons.inventory_2_outlined),
        title: const Text('Detalles de carga', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: !_panelCargaAbierto ? _resumenCarga() : null,
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        children: [
          _seccionCarga(),
        ],
      ),
    );
  }

  // Resumen breve de los datos de carga (visible cuando el panel está cerrado)
  Widget _resumenCarga() {
    final piezas = <String>[];
    final peso = double.tryParse(_pesoCtrl.text.replaceAll(',', '.'));
    final vol = double.tryParse(_volCtrl.text.replaceAll(',', '.'));
    if (peso != null && peso > 0) piezas.add('${peso.toStringAsFixed(1)} t');
    if (vol != null && vol > 0) piezas.add('${vol.toStringAsFixed(1)} m³');
    if (_requiereAyudantes) piezas.add('Ayudantes: ${_ayudCtrl.text}');
    if (_requiereMontacargas) piezas.add('Montacargas');
    final txt = piezas.isEmpty ? 'Toca para completar' : piezas.join(' • ');
    return Text(txt, style: const TextStyle(color: _slate, fontSize: 12));
  }

  // Cuerpo del panel con campos editables (peso, volumen, ayudantes, notas)
  Widget _seccionCarga() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.04),
        border: Border(top: BorderSide(color: Colors.orange.withOpacity(0.2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Campos de peso y volumen
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pesoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Peso (ton)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.scale),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _volCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Volumen (m³)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.view_in_ar),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Switch para ayudantes + campo cantidad
          Row(
            children: [
              Expanded(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requiere ayudantes'),
                  value: _requiereAyudantes,
                  onChanged: (v) => setState(() => _requiereAyudantes = v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _ayudCtrl,
                  enabled: _requiereAyudantes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Switch de montacargas
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Requiere montacargas'),
            value: _requiereMontacargas,
            onChanged: (v) => setState(() => _requiereMontacargas = v),
          ),
          const SizedBox(height: 8),

          // Campo de notas adicionales
          TextField(
            controller: _notasCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
            ),
          ),
        ],
      ),
    );
  }
}
