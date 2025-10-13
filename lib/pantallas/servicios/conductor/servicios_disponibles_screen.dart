// Importaciones de Flutter y dependencias utilizadas
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Modelos y repositorios internos del módulo de servicios
import 'package:app_qorinti/modelos/servicio.dart';
import 'package:app_qorinti/repos/servicio_repository.dart';
import 'package:app_qorinti/pantallas/servicios/conductor/crear_oferta_bottom_sheet.dart';

/// Pantalla que muestra los servicios solicitados por los clientes cercanos.
/// Permite a los conductores ofertar un servicio mientras esté disponible.
///
/// Lógica principal:
/// - Escucha en tiempo real los servicios solicitados mediante un Stream.
/// - Filtra si el servicio pertenece al mismo usuario autenticado.
/// - Habilita el botón “Ofertar” solo cuando el servicio está pendiente.
/// - Despliega un modal para enviar una oferta.
class ServiciosDisponiblesScreen extends StatelessWidget {
  const ServiciosDisponiblesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Acceso al repositorio de servicios (inyectado mediante Bloc/Provider)
    final repo = context.read<ServicioRepository>();
    // Obtención del UID del usuario autenticado
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servicios cercanos'),
        centerTitle: true,
      ),
      // StreamBuilder que escucha los servicios disponibles
      body: StreamBuilder<List<Servicio>>(
        stream: repo.escucharServiciosSolicitados(),
        builder: (context, snap) {
          // Estado de carga inicial
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // Error en la carga del stream
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          // Datos recibidos o lista vacía
          final servicios = snap.data ?? const <Servicio>[];
          if (servicios.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay solicitudes por ahora.\nSe mostrarán aquí cuando un cliente publique.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Colores del tema actual
          final cs = Theme.of(context).colorScheme;

          // Listado de servicios mostrados en tarjetas
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: servicios.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final s = servicios[i];

              // Origen y destino según la ruta
              final origen = s.ruta.isNotEmpty ? s.ruta.first.direccion : 'Origen';
              final destino = s.ruta.isNotEmpty ? s.ruta.last.direccion : 'Destino';

              // Determina si el servicio fue publicado por el mismo usuario
              final esMio = (uid != null && uid == s.idUsuarioSolicitante);
              // Verifica si el servicio sigue en estado pendiente para ofertas
              final esPendiente = s.estado == EstadoServicio.pendiente_ofertas;
              // Condición para permitir ofertar
              final puedeOfertar = !esMio && esPendiente && (s.id != null);

              // Tarjeta visual del servicio
              return Card(
                elevation: 0,
                color: cs.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.035),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ícono de tipo de servicio (color y forma según categoría)
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _colorTipo(s.tipoServicio),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(_iconoTipo(s.tipoServicio), color: Colors.white),
                      ),
                      const SizedBox(width: 10),

                      // Descripción del servicio: tipo, ruta y detalles
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_labelTipo(s.tipoServicio)} • $origen → $destino',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),

                            // Chips de información resumida: distancia, tiempo, precio, comprobante, pago
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                if (s.distanciaKm != null)
                                  _chipMini(Icons.route, '${s.distanciaKm!.toStringAsFixed(1)} km', cs),
                                if (s.tiempoEstimadoMin != null)
                                  _chipMini(Icons.timer, '${s.tiempoEstimadoMin} min', cs),
                                if (s.precioEstimado != null)
                                  _chipMini(Icons.account_balance_wallet, 'S/ ${s.precioEstimado!.toStringAsFixed(2)}', cs),
                                _chipMini(Icons.request_page, _labelComprobante(s.tipoComprobante), cs),
                                _chipMini(Icons.payment, _labelMetodo(s.metodoPago), cs),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 10),

                      // Botón de acción (Ofertar) con tooltip explicativo
                      Tooltip(
                        message: puedeOfertar
                            ? 'Ofertar a este servicio'
                            : (esMio
                                ? 'No puedes ofertar a tu propia solicitud'
                                : (!esPendiente ? 'Este servicio ya no acepta ofertas' : 'Solicitud inválida')),
                        child: FilledButton(
                          onPressed: !puedeOfertar
                              ? null
                              : () async {
                                  // Muestra el formulario inferior para crear oferta
                                  final ok = await showModalBottomSheet<bool>(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                    ),
                                    builder: (_) => CrearOfertaBottomSheet(idServicio: s.id!),
                                  );

                                  // Si la oferta se envió correctamente, muestra aviso
                                  if (ok == true && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('✅ Oferta enviada')),
                                    );
                                  }
                                },
                          child: const Text('Ofertar'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Crea un chip visual con ícono y texto, usado para mostrar datos del servicio.
  Widget _chipMini(IconData icon, String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: cs.onSecondaryContainer)),
        ],
      ),
    );
  }

  /// Devuelve la etiqueta de texto asociada a cada tipo de servicio.
  String _labelTipo(TipoServicio t) {
    switch (t) {
      case TipoServicio.taxi:
        return 'Pasajeros';
      case TipoServicio.carga_ligera:
        return 'Carga ligera';
      case TipoServicio.carga_pesada:
        return 'Carga pesada';
      case TipoServicio.mudanza:
        return 'Mudanza';
    }
  }

  /// Devuelve el ícono representativo según el tipo de servicio.
  IconData _iconoTipo(TipoServicio t) {
    switch (t) {
      case TipoServicio.taxi:
        return Icons.local_taxi;
      case TipoServicio.carga_ligera:
        return Icons.local_shipping;
      case TipoServicio.carga_pesada:
        return Icons.fire_truck;
      case TipoServicio.mudanza:
        return Icons.inventory_2;
    }
  }

  /// Devuelve el color base de la categoría del servicio.
  Color _colorTipo(TipoServicio t) {
    switch (t) {
      case TipoServicio.taxi:
        return Colors.indigo;
      case TipoServicio.carga_ligera:
        return Colors.teal;
      case TipoServicio.carga_pesada:
        return Colors.deepOrange;
      case TipoServicio.mudanza:
        return Colors.brown;
    }
  }

  /// Devuelve la etiqueta textual del tipo de comprobante solicitado.
  String _labelComprobante(TipoComprobante c) {
    switch (c) {
      case TipoComprobante.ninguno:
        return 'Sin comp.';
      case TipoComprobante.boleta:
        return 'Boleta';
      case TipoComprobante.factura:
        return 'Factura';
    }
  }

  /// Devuelve la etiqueta textual del método de pago requerido.
  String _labelMetodo(MetodoPago m) {
    switch (m) {
      case MetodoPago.efectivo:
        return 'Efectivo';
      case MetodoPago.yape:
        return 'Yape';
      case MetodoPago.plin:
        return 'Plin';
      case MetodoPago.transferencia:
        return 'Transferencia';
    }
  }
}
