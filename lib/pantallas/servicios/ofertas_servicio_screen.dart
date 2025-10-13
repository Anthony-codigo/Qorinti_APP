// -----------------------------------------------------------------------------
// Archivo: lib/pantallas/servicios/ofertas_servicio_screen.dart
// Descripción:
//   Pantalla principal que muestra todas las ofertas enviadas por conductores
//   para un servicio solicitado por un cliente. Permite visualizar, aceptar
//   o rechazar ofertas, así como ver detalles de cada conductor y su vehículo.
//
//   Usa flujos en tiempo real desde Firestore para sincronizar los cambios.
//   Cuando se acepta una oferta, redirige a la pantalla de viaje en curso.
//
// Dependencias principales:
//   - Firebase Firestore: para escuchar colecciones 'servicios', 'ofertas', etc.
//   - ServicioRepository: para manejar lógica de negocio (aceptar/rechazar).
//   - Bloc y context.read: para acceder al repositorio.
//   - intl: para formato de moneda y fecha.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_qorinti/repos/servicio_repository.dart';
import 'package:app_qorinti/modelos/oferta.dart';
import 'package:app_qorinti/modelos/servicio.dart';
import 'viaje_en_curso_screen.dart';

// -----------------------------------------------------------------------------
// Clase principal de la pantalla: muestra todas las ofertas del servicio
// -----------------------------------------------------------------------------
class OfertasServicioScreen extends StatefulWidget {
  final String idServicio; // ID del servicio actual

  const OfertasServicioScreen({super.key, required this.idServicio});

  @override
  State<OfertasServicioScreen> createState() => _OfertasServicioScreenState();
}

// -----------------------------------------------------------------------------
// Estado interno: maneja streams, formato de moneda, timers y acciones
// -----------------------------------------------------------------------------
class _OfertasServicioScreenState extends State<OfertasServicioScreen> {
  late final ServicioRepository repo; // repositorio de servicios
  late final NumberFormat moneda; // formateador de moneda local
  late final DateFormat fmtFecha; // formateador de fecha y hora

  DateTime _now = DateTime.now(); // referencia temporal actual
  Timer? _ticker; // temporizador para refrescar tiempos en pantalla

  @override
  void initState() {
    super.initState();
    // inicialización de repositorio y formatos
    repo = context.read<ServicioRepository>();
    moneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/', decimalDigits: 2);
    fmtFecha = DateFormat("dd/MM/yyyy HH:mm");

    // temporizador que actualiza el tiempo cada minuto (para SLA o TPA)
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Construcción de interfaz principal
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Stream del documento del servicio (para escuchar cambios de estado)
    final servicioStream = FirebaseFirestore.instance
        .collection('servicios')
        .doc(widget.idServicio)
        .snapshots()
        .map((s) => s.exists ? Servicio.fromMap(s.data()!, id: s.id) : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ofertas de conductores"),
        centerTitle: true,
      ),

      // Stream principal que observa el estado del servicio
      body: StreamBuilder<Servicio?>(
        stream: servicioStream,
        builder: (context, snapSrv) {
          if (snapSrv.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapSrv.hasError) {
            return Center(child: Text("Error cargando servicio: ${snapSrv.error}"));
          }

          final servicio = snapSrv.data;
          if (servicio == null) {
            return const Center(child: Text("Servicio no encontrado"));
          }

          // -------------------------------------------------------------------
          // Estructura visual: encabezado + lista de ofertas
          // -------------------------------------------------------------------
          return Column(
            children: [
              // Header superior con métricas del servicio (pago, SLA, etc.)
              _HeaderPago(servicio: servicio, now: _now),

              // -----------------------------------------------------------------
              // Listado de ofertas en tiempo real
              // -----------------------------------------------------------------
              Expanded(
                child: StreamBuilder<List<Oferta>>(
                  stream: repo.escucharOfertas(widget.idServicio),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text("Error cargando ofertas: ${snapshot.error}",
                              textAlign: TextAlign.center),
                        ),
                      );
                    }

                    // obtención de ofertas y filtrado
                    final todas = snapshot.data ?? const <Oferta>[];
                    final ofertas = todas.where((o) => o.estado != EstadoOferta.rechazada).toList();

                    // si aún no hay ofertas disponibles
                    if (ofertas.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            "Aún no hay ofertas visibles.\nCuando un conductor postule, aparecerá aquí.",
                            style: TextStyle(fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    // ordenamiento: aceptadas → pendientes → rechazadas
                    ofertas.sort((a, b) {
                      int rank(Oferta o) {
                        switch (o.estado) {
                          case EstadoOferta.aceptada:
                            return 0;
                          case EstadoOferta.pendiente:
                            return 1;
                          case EstadoOferta.rechazada:
                            return 2;
                        }
                      }

                      final r = rank(a).compareTo(rank(b));
                      if (r != 0) return r;

                      // orden secundario por fecha (más recientes primero)
                      final ta = (a.actualizadoEn ?? a.creadoEn)?.millisecondsSinceEpoch ?? 0;
                      final tb = (b.actualizadoEn ?? b.creadoEn)?.millisecondsSinceEpoch ?? 0;
                      return tb.compareTo(ta);
                    });

                    // detectar si ya existe una oferta aceptada
                    final yaHayAceptada = ofertas.any((o) => o.estado == EstadoOferta.aceptada);

                    // construcción de lista con pull-to-refresh
                    return RefreshIndicator(
                      onRefresh: () async =>
                          Future<void>.delayed(const Duration(milliseconds: 400)),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: ofertas.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final o = ofertas[i];
                          final esAceptada = o.estado == EstadoOferta.aceptada;
                          final esPendiente = o.estado == EstadoOferta.pendiente;

                          // widget individual de cada oferta
                          return _OfertaTile(
                            oferta: o,
                            moneda: moneda,
                            fmtFecha: fmtFecha,
                            yaHayAceptada: yaHayAceptada,
                            esAceptada: esAceptada,
                            esPendiente: esPendiente,

                            // acción aceptar
                            onAceptar: (esPendiente && !yaHayAceptada)
                                ? () => _onAceptarOferta(
                                      context: context,
                                      repo: repo,
                                      servicio: servicio,
                                      oferta: o,
                                      moneda: moneda,
                                    )
                                : null,

                            // acción rechazar
                            onRechazar: (esPendiente && !yaHayAceptada)
                                ? () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text("Rechazar oferta"),
                                        content: const Text(
                                            "¿Seguro que deseas rechazar esta oferta?"),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text("Cancelar")),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text("Rechazar")),
                                        ],
                                      ),
                                    );

                                    // ejecutar rechazo
                                    if (ok == true) {
                                      try {
                                        await repo.rechazarOferta(
                                            servicioId: widget.idServicio,
                                            ofertaId: o.id);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content:
                                                      Text("Oferta rechazada")));
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      "Error al rechazar: $e")));
                                        }
                                      }
                                    }
                                  }
                                : null,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Función que ejecuta la aceptación de una oferta
  // ---------------------------------------------------------------------------
  Future<void> _onAceptarOferta({
    required BuildContext context,
    required ServicioRepository repo,
    required Servicio servicio,
    required Oferta oferta,
    required NumberFormat moneda,
  }) async {
    // obtención de método de pago y comprobante
    final metodo = servicio.metodoPago;
    final comprobante = servicio.tipoComprobante;
    final compTexto = (comprobante == TipoComprobante.ninguno)
        ? "A definir al finalizar"
        : comprobante.name.toUpperCase();

    // diálogo de confirmación antes de aceptar
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Aceptar oferta"),
        content: Text(
          "Vas a elegir la oferta del conductor por ${moneda.format(oferta.precioOfrecido)}.\n\n"
          "Método de pago: ${metodo.name.toUpperCase()}\n"
          "Comprobante: $compTexto",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancelar")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Aceptar")),
        ],
      ),
    );

    if (ok != true) return;

    try {
      // ejecutar aceptación y configuración de pago
      await repo.aceptarOfertaYConfigurarPago(
        servicioId: widget.idServicio,
        ofertaId: oferta.id,
        conductorId: oferta.idConductor,
        precioFinal: oferta.precioOfrecido,
        metodoPago: metodo,
        tipoComprobante: comprobante,
        pagoDentroApp: false,
      );

      if (!context.mounted) return;

      // mostrar snackbar de éxito
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Oferta aceptada correctamente"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );

      await Future.delayed(const Duration(milliseconds: 800));
      if (!context.mounted) return;

      // redirección a pantalla de viaje en curso
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => ViajeEnCursoScreen(
            idServicio: widget.idServicio,
            esConductor: false,
          ),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error al aceptar oferta: $e")));
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Header con detalles del pago y métricas de tiempo (ETA, SLA, etc.)
// -----------------------------------------------------------------------------
class _HeaderPago extends StatelessWidget {
  final Servicio servicio;
  final DateTime now;

  const _HeaderPago({required this.servicio, required this.now});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // texto de método de pago y comprobante
    final metodo = servicio.metodoPago.name.toUpperCase();
    final comp = servicio.tipoComprobante == TipoComprobante.ninguno
        ? 'A DEFINIR AL FINALIZAR'
        : servicio.tipoComprobante.name.toUpperCase();

    final eta = servicio.tiempoEstimadoMin;
    final sla = servicio.slaMin;

    // cálculo de HS (hora de solicitud) y TPA (tiempo transcurrido)
    int? tpaMin;
    String? hsTexto;
    if (servicio.fechaSolicitud != null) {
      final hs = servicio.fechaSolicitud!;
      hsTexto = DateFormat("dd/MM HH:mm").format(hs.toLocal());
      final diff = now.difference(hs).inMinutes;
      tpaMin = diff < 0 ? 0 : diff;
    }

    // cálculo de minutos restantes o vencidos
    int? restante;
    int? vencido;
    if (sla != null && tpaMin != null) {
      final r = sla - tpaMin;
      if (r >= 0) {
        restante = r;
      } else {
        vencido = -r;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primaryContainer.withOpacity(0.55),
                cs.surfaceVariant.withOpacity(0.35)
              ],
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // ícono principal
              Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.payments, color: cs.onPrimary),
              ),
              const SizedBox(width: 12),

              // grupo de indicadores (KPIs)
              Expanded(
                child: Wrap(
                  runSpacing: 6,
                  spacing: 18,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _kv('Método', metodo),
                    _kv('Comprobante', comp),
                    if (hsTexto != null) _kv('HS', hsTexto),
                    if (tpaMin != null)
                      _pill(
                        icon: Icons.hourglass_bottom,
                        text: 'Promedio de asignación ${tpaMin} min',
                        bg: cs.tertiaryContainer,
                        fg: cs.onTertiaryContainer,
                      ),
                    if (eta != null) _kv('Llega en', '$eta min'),
                    if (sla != null) _kv('Debe llegar en', '$sla min'),
                    if (restante != null)
                      _pill(
                        icon: Icons.timer,
                        text: 'Quedan $restante min',
                        bg: Colors.green.shade600,
                        fg: Colors.white,
                      ),
                    if (vencido != null)
                      _pill(
                        icon: Icons.warning_amber_rounded,
                        text: 'Vencido +$vencido min',
                        bg: Colors.red.shade600,
                        fg: Colors.white,
                      ),
                    if ((servicio.distanciaKm ?? 0) > 0)
                      _kv('Distancia', '${servicio.distanciaKm!.toStringAsFixed(2)} km'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // formato de clave-valor
  Widget _kv(String k, String v) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(v),
        ],
      );

  // pastilla visual con color personalizado
  Widget _pill({
    required IconData icon,
    required String text,
    required Color bg,
    required Color fg,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(text,
                style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: .2)),
          ],
        ),
      );
}

// -----------------------------------------------------------------------------
// Tarjeta individual que representa cada oferta
// -----------------------------------------------------------------------------
class _OfertaTile extends StatelessWidget {
  final Oferta oferta;
  final NumberFormat moneda;
  final DateFormat fmtFecha;
  final bool yaHayAceptada;
  final bool esAceptada;
  final bool esPendiente;
  final VoidCallback? onAceptar;
  final VoidCallback? onRechazar;

  const _OfertaTile({
    required this.oferta,
    required this.moneda,
    required this.fmtFecha,
    required this.yaHayAceptada,
    required this.esAceptada,
    required this.esPendiente,
    required this.onAceptar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // color y texto del chip según estado
    final Color chipBg = esAceptada ? cs.primary : cs.tertiaryContainer;
    final Color chipFg = esAceptada ? cs.onPrimary : cs.onTertiaryContainer;
    final String chipText = esAceptada ? "ACEPTADA" : "PENDIENTE";

    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // cabecera: info conductor + estado
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _FichaConductorOferta(idConductor: oferta.idConductor)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(999)),
                      child: Text(chipText,
                          style: TextStyle(color: chipFg, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                    if (oferta.usaEmpresaComoEmisor)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(999)),
                          child: Text("EMPRESA",
                              style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // KPIs principales (precio y tiempo)
            Wrap(
              spacing: 18,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _KpiRow(icon: Icons.payments_rounded, iconColor: cs.primary, child: Text(moneda.format(oferta.precioOfrecido), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                _KpiRow(icon: Icons.timer_rounded, iconColor: cs.secondary, child: Text("${oferta.tiempoEstimadoMin} min", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              ],
            ),

            // notas opcionales del conductor
            if (oferta.notas != null && oferta.notas!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.notes_rounded, size: 18, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(oferta.notas!.trim(), style: TextStyle(fontSize: 14, color: cs.onSurface))),
                ],
              ),
            ],

            const SizedBox(height: 10),

            // fechas de creación y actualización
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _Info(icon: Icons.event_available_rounded, text: oferta.creadoEn != null ? "Creada: ${fmtFecha.format(oferta.creadoEn!.toLocal())}" : "Creada: —"),
                if (oferta.actualizadoEn != null) _Info(icon: Icons.update_rounded, text: "Act: ${fmtFecha.format(oferta.actualizadoEn!.toLocal())}"),
              ],
            ),

            // mensaje si ya hay otra oferta aceptada
            if (yaHayAceptada && !esAceptada) ...[
              const SizedBox(height: 10),
              Text("Ya existe una oferta aceptada para este servicio.", style: TextStyle(fontSize: 12, color: cs.error)),
            ],

            const SizedBox(height: 12),

            // botones de acción (aceptar / rechazar)
            Row(
              children: [
                const Spacer(),
                if (!esAceptada)
                  ElevatedButton(onPressed: onAceptar, style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)), child: const Text("Aceptar")),
                if (esPendiente && !yaHayAceptada) const SizedBox(width: 8),
                if (esPendiente && !yaHayAceptada)
                  OutlinedButton(onPressed: onRechazar, style: OutlinedButton.styleFrom(side: BorderSide(color: cs.error), foregroundColor: cs.error), child: const Text("Rechazar")),
                if (esAceptada) Icon(Icons.check_circle, color: cs.primary, size: 30),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Subcomponentes de soporte (KpiRow, Info, FichaConductorOferta, etc.)
// -----------------------------------------------------------------------------
class _KpiRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Widget child;
  const _KpiRow({required this.icon, required this.iconColor, required this.child});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: iconColor, size: 20), const SizedBox(width: 6), child]);
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Info({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: cs.onSurfaceVariant), const SizedBox(width: 4), Flexible(child: Text(text, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis))]);
  }
}

// ficha del conductor dentro de la oferta (nombre, rating, vehículo)
class _FichaConductorOferta extends StatelessWidget {
  final String idConductor;
  const _FichaConductorOferta({required this.idConductor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('conductores').doc(idConductor).snapshots(),
      builder: (context, cSnap) {
        final cData = cSnap.data?.data() ?? {};
        final fotoUrl = (cData['fotoUrl'] ?? '').toString().trim();
        final nombreC = (cData['nombre'] ?? '').toString().trim();
        final rating = (cData['ratingPromedio'] is num) ? (cData['ratingPromedio'] as num).toDouble() : 0.0;
        final rCount = (cData['ratingConteo'] is num) ? (cData['ratingConteo'] as num).toInt() : 0;
        final idVehiculoActivo = (cData['idVehiculoActivo'] ?? '').toString().trim();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 26, backgroundImage: (fotoUrl.isNotEmpty) ? NetworkImage(fotoUrl) : null, backgroundColor: cs.primaryContainer, child: (fotoUrl.isEmpty) ? Icon(Icons.person, color: cs.onPrimaryContainer, size: 28) : null),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NombreConductorFallback(idConductor: idConductor, nombreConductorDoc: nombreC),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.star, size: 16, color: Colors.amber), const SizedBox(width: 4), Text("${rating.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.w700)), Text(" ($rCount)", style: TextStyle(color: cs.onSurfaceVariant))]),
                  const SizedBox(height: 6),
                  if (idVehiculoActivo.isNotEmpty) _PlacaVehiculo(idVehiculo: idVehiculoActivo),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// muestra el nombre del conductor o, si no existe, el correo o UID
class _NombreConductorFallback extends StatelessWidget {
  final String idConductor;
  final String nombreConductorDoc;
  const _NombreConductorFallback({required this.idConductor, required this.nombreConductorDoc});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (nombreConductorDoc.isNotEmpty) {
      return Text(nombreConductorDoc, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface), overflow: TextOverflow.ellipsis, maxLines: 1);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(idConductor).snapshots(),
      builder: (_, uSnap) {
        final u = uSnap.data?.data();
        final nombre = (u?['nombre'] ?? '').toString().trim();
        final correo = (u?['correo'] ?? '').toString().trim();
        final mostrar = nombre.isNotEmpty ? nombre : (correo.isNotEmpty ? correo : idConductor);
        return Text(mostrar, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface), overflow: TextOverflow.ellipsis, maxLines: 1);
      },
    );
  }
}

// muestra la placa del vehículo activo del conductor
class _PlacaVehiculo extends StatelessWidget {
  final String idVehiculo;
  const _PlacaVehiculo({required this.idVehiculo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('vehiculos').doc(idVehiculo).snapshots(),
      builder: (_, vSnap) {
        final v = vSnap.data?.data() ?? {};
        final placa = (v['placa'] ?? '').toString().trim();
        if (placa.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.outlineVariant)),
          child: Text("Placa: $placa", style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer, fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}
