// -----------------------------------------------------------------------------
// Archivo: crear_servicio_screen.dart
// Descripción general:
//   Pantalla para que el cliente cree una nueva solicitud de servicio en Qorinti.
//   Permite seleccionar tipo y ruta, establecer un precio estimado y elegir
//   el medio de pago preferido. Una vez validada la información, se publica
//   el servicio a través del BLoC correspondiente.
//
// Estructura principal:
//   - Enum interno _MedioUi: define las opciones de pago disponibles.
//   - Clase CrearServicioScreen: pantalla con formulario y control de estado.
//   - Clase _PlanResumen: widget auxiliar que muestra un resumen visual
//     del plan de ruta seleccionado.
//
// Dependencias:
//   - BLoC: ServicioBloc, ServicioEvent, ServicioState.
//   - FirebaseAuth: para identificar al usuario solicitante.
//   - ServicioRepository: para registrar el servicio en Firestore.
//   - Modelos: PlanRuta y Servicio.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:app_qorinti/bloc/servicio/servicio_bloc.dart';
import 'package:app_qorinti/bloc/servicio/servicio_event.dart';
import 'package:app_qorinti/bloc/servicio/servicio_state.dart';
import 'package:app_qorinti/repos/servicio_repository.dart';
import 'package:app_qorinti/modelos/plan_ruta.dart';
import 'package:app_qorinti/modelos/servicio.dart';
import 'seleccionar_tipo_ruta_screen.dart';
import 'ofertas_servicio_screen.dart';

// Enum privado que representa las opciones visuales de medio de pago
enum _MedioUi { efectivo, transferencia, yape, plin }

/// Pantalla principal donde el usuario crea un nuevo servicio.
/// Incluye selección de tipo de ruta, monto estimado y medio de pago.
class CrearServicioScreen extends StatefulWidget {
  const CrearServicioScreen({super.key});

  @override
  State<CrearServicioScreen> createState() => _CrearServicioScreenState();
}

class _CrearServicioScreenState extends State<CrearServicioScreen> {
  // Controlador del campo de precio
  final _precioCtrl = TextEditingController();
  // Formato de moneda local
  final _moneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/', decimalDigits: 2);

  // Plan de ruta seleccionado por el usuario
  PlanRuta? _plan;

  // Repositorio de servicios
  late ServicioRepository repo;

  // Medio de pago seleccionado (modelo)
  MetodoPago _metodoPago = MetodoPago.efectivo;

  // Medio de pago seleccionado (interfaz)
  _MedioUi _medioUi = _MedioUi.efectivo;

  /// Mapeo entre valores del enum UI y el enum del modelo [MetodoPago].
  MetodoPago _mapUiToMetodoPago(_MedioUi v) {
    switch (v) {
      case _MedioUi.efectivo:
        return MetodoPago.efectivo;
      case _MedioUi.transferencia:
        return MetodoPago.transferencia;
      case _MedioUi.yape:
        return MetodoPago.yape;
      case _MedioUi.plin:
        return MetodoPago.plin;
    }
  }

  @override
  void initState() {
    super.initState();
    // Obtiene la instancia del repositorio desde el contexto
    repo = context.read<ServicioRepository>();
  }

  @override
  void dispose() {
    _precioCtrl.dispose();
    super.dispose();
  }

  /// Limpia y convierte el texto del campo de precio a un valor numérico.
  double _parsePrecio(String raw) {
    final cleaned = raw
        .replaceAll('S/.', '')
        .replaceAll('s/.', '')
        .replaceAll('S/', '')
        .replaceAll('s/', '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0;
  }

  /// Navega a la pantalla de selección de tipo y ruta de servicio.
  /// Si el usuario confirma, valida los datos y actualiza el estado local.
  Future<void> _seleccionarTipoYRuta() async {
    final result = await Navigator.push<PlanRuta>(
      context,
      MaterialPageRoute(builder: (_) => const SeleccionarTipoRutaScreen()),
    );
    if (!mounted) return;
    if (result != null) {
      final error = result.validar();
      if (error != null) {
        _snack(error);
      }
      setState(() => _plan = result);
    }
  }

  /// Publica la solicitud de servicio tras validar todos los datos requeridos.
  void _publicar() {
    final plan = _plan;
    if (plan == null) {
      _snack('Primero selecciona el tipo de servicio y la ruta.');
      return;
    }

    final val = plan.validar();
    if (val != null) {
      _snack(val);
      return;
    }

    final precio = _parsePrecio(_precioCtrl.text);
    if (precio <= 0) {
      _snack('Ingresa un precio estimado válido.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _snack('Debes iniciar sesión.');
      return;
    }

    _metodoPago = _mapUiToMetodoPago(_medioUi);

    final ahora = DateTime.now();

    // Tiempo estimado y SLA (tiempo máximo tolerado)
    final int? etaMin = plan.tiempoEstimadoMin;
    final int sla = (etaMin ?? 30);

    // Construye el objeto de servicio final a publicar
    final servicio = plan.construirServicio(
      idUsuarioSolicitante: uid,
      precioEstimado: precio,
      metodoPago: _metodoPago,
      tipoComprobante: TipoComprobante.ninguno,
      fechaSolicitud: ahora,
      etaMin: etaMin,
      slaMin: sla,
    );

    // Envía el evento BLoC para crear el servicio
    context.read<ServicioBloc>().add(CrearServicio(servicio));
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;

    // Colores base de la interfaz
    const brandBlue = Color(0xFF2A6DF4);
    final cardBg = const Color(0xFFEEF4FF);
    final border = BorderSide(color: brandBlue.withOpacity(.18));

    return Scaffold(
      appBar: AppBar(
        title: const Text(' Crear servicio '),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
      ),

      // Escucha el estado del BLoC y reacciona a cambios (creación, error, etc.)
      body: BlocConsumer<ServicioBloc, ServicioState>(
        listener: (context, state) async {
          if (state is ServicioCreado) {
            _snack('Servicio creado (${state.idServicio})');
            if (!mounted) return;
            // Redirige automáticamente a la pantalla de ofertas
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => OfertasServicioScreen(idServicio: state.idServicio),
              ),
            );
          }
          if (state is ServicioError) {
            _snack('❌ ${state.mensaje}');
          }
        },

        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              // Botón para seleccionar tipo y ruta
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.alt_route),
                  label: Text(plan == null
                      ? 'Seleccionar tipo y ruta'
                      : 'Editar tipo y ruta'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: border,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    foregroundColor: brandBlue,
                  ),
                  onPressed: _seleccionarTipoYRuta,
                ),
              ),

              // Resumen del plan si ya fue definido
              if (plan != null) _PlanResumen(plan: plan),

              const SizedBox(height: 8),

              // Campo para ingresar precio estimado
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _precioCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderSide: border,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: border,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: cardBg,
                    labelText: 'Precio estimado',
                    hintText: _moneda.format(15),
                    prefixIcon: const Icon(Icons.account_balance_wallet),
                    helperText:
                        'El conductor ofertará con base en este monto. El total final se confirmará al cerrar el viaje.',
                  ),
                ),
              ),

              // Selector de medio de pago
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.fromBorderSide(border),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.payments, color: brandBlue),
                          SizedBox(width: 8),
                          Text('Medio de pago',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 10),

                      DropdownButtonFormField<_MedioUi>(
                        value: _medioUi,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderSide: border,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: border,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: _MedioUi.efectivo,
                            child: Text('Efectivo'),
                          ),
                          DropdownMenuItem(
                            value: _MedioUi.transferencia,
                            child: Text('Transferencia'),
                          ),
                          DropdownMenuItem(
                            value: _MedioUi.yape,
                            child: Text('Yape'),
                          ),
                          DropdownMenuItem(
                            value: _MedioUi.plin,
                            child: Text('Plin'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _medioUi = v ?? _MedioUi.efectivo),
                      ),

                      const SizedBox(height: 8),
                      const Text(
                        'El comprobante y el cobro se confirman al finalizar el servicio.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),

              // Botón para publicar la solicitud de servicio
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: state is ServicioCargando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text(state is ServicioCargando
                        ? 'Publicando…'
                        : 'Publicar solicitud'),
                    onPressed: state is ServicioCargando ? null : _publicar,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: brandBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Muestra un mensaje tipo SnackBar en pantalla.
  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }
}

/// Widget auxiliar que muestra un resumen visual del plan seleccionado.
/// Incluye tipo de servicio, ruta, distancia, ETA y detalles de carga.
class _PlanResumen extends StatelessWidget {
  final PlanRuta plan;
  const _PlanResumen({required this.plan});

  @override
  Widget build(BuildContext context) {
    // Determina si el servicio involucra carga (para mostrar datos adicionales)
    final esCarga = plan.tipoServicio == TipoServicio.carga_pesada ||
        plan.tipoServicio == TipoServicio.mudanza;

    const brandBlue = Color(0xFF2A6DF4);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tipo de servicio
            Row(
              children: [
                const Icon(Icons.category, color: brandBlue),
                const SizedBox(width: 8),
                Text(
                  'Tipo: ${plan.tipoServicio.code}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Lista de puntos en la ruta
            ...List.generate(plan.ruta.length, (i) {
              final p = plan.ruta[i];
              final esOrigen = i == 0;
              final esDestino = i == plan.ruta.length - 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      esOrigen
                          ? Icons.trip_origin
                          : (esDestino ? Icons.flag : Icons.location_on),
                      color: esOrigen
                          ? Colors.green
                          : (esDestino ? Colors.red : Colors.blueGrey),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(p.direccion)),
                  ],
                ),
              );
            }),

            // Detalles adicionales de carga si aplica
            if (esCarga) ...[
              const Divider(),
              const Text('Detalles de carga',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if ((plan.pesoTon ?? 0) > 0) _badge('Peso', '${plan.pesoTon} t'),
                  if ((plan.volumenM3 ?? 0) > 0)
                    _badge('Volumen', '${plan.volumenM3} m³'),
                  if (plan.requiereAyudantes == true)
                    _badge('Ayudantes', '${plan.cantidadAyudantes ?? 1}'),
                  if (plan.requiereMontacargas == true)
                    _badge('Montacargas', 'Sí'),
                  if ((plan.notasCarga ?? '').isNotEmpty)
                    _badge('Notas', plan.notasCarga!),
                ],
              ),
            ],

            const SizedBox(height: 8),
            // Información de distancia y ETA
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if ((plan.distanciaKm ?? 0) > 0)
                  _badge('Distancia', '${plan.distanciaKm!.toStringAsFixed(1)} km'),
                if ((plan.tiempoEstimadoMin ?? 0) > 0)
                  _badge('ETA base', '${plan.tiempoEstimadoMin} min'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Crea una etiqueta tipo chip para mostrar un par clave-valor.
  Widget _badge(String k, String v) {
    return Chip(
      label: Text('$k: $v', style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF2A6DF4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
