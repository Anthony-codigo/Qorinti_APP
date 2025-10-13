// -----------------------------------------------------------------------------
// Archivo: mis_servicios_screen.dart
// Descripción general:
//   Pantalla que muestra los servicios *activos* del usuario (cliente o conductor).
//   Permite:
//     - Alternar entre vista como cliente o conductor.
//     - Ver detalles básicos del servicio (origen, destino, precio, fecha).
//     - Cancelar servicios activos.
//     - Abrir viaje en curso o revisar ofertas.
//     - Ver comprobantes demo asociados.
//
// Dependencias:
//   - Firebase (Auth, Firestore).
//   - Bloc (ServicioRepository).
//   - Navegación hacia otras pantallas: OfertasServicioScreen, ViajeEnCursoScreen, HistorialServiciosScreen.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_qorinti/modelos/servicio.dart';
import 'package:app_qorinti/repos/servicio_repository.dart';
import 'ofertas_servicio_screen.dart';
import 'viaje_en_curso_screen.dart';
import 'historial_servicios_screen.dart';

/// Widget principal que contiene la vista de “Mis servicios”
class MisServiciosScreen extends StatefulWidget {
  const MisServiciosScreen({super.key});

  @override
  State<MisServiciosScreen> createState() => _MisServiciosScreenState();
}

class _MisServiciosScreenState extends State<MisServiciosScreen> {
  // Formateadores de fecha y moneda según configuración local (Perú)
  final _fmtFecha = DateFormat('dd/MM/yyyy HH:mm', 'es_PE');
  final _fmtMoneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/', decimalDigits: 2);

  // Control de vista actual y rol del usuario
  bool _verComoConductor = false; // alterna entre "como cliente" o "como conductor"
  bool _esConductor = false;      // indica si el usuario tiene perfil de conductor

  // Cache local para guardar nombres ya consultados desde Firestore
  final Map<String, String> _cacheNombres = {};

  @override
  void initState() {
    super.initState();
    _cargarRol(); // carga inicial para determinar si el usuario es conductor
  }

  /// Muestra un mensaje flotante (SnackBar) en la parte inferior.
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Carga desde Firestore si el usuario tiene rol de conductor.
  /// Si no lo tiene, fuerza la vista como cliente.
  Future<void> _cargarRol() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('conductores').doc(uid).get();
      if (!mounted) return;
      setState(() {
        _esConductor = snap.exists;
        if (!_esConductor) _verComoConductor = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _esConductor = false;
        _verComoConductor = false;
      });
    }
  }

  /// Obtiene el nombre corto del usuario o conductor a partir de su UID.
  /// Si no existe registro en “usuarios”, intenta buscar en “conductores”.
  Future<String> _getNombreCorto(String uid) async {
    if (uid.isEmpty) return '-';
    if (_cacheNombres.containsKey(uid)) return _cacheNombres[uid]!;

    String? nombre;

    // Buscar en colección de usuarios
    final u = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (u.exists) {
      final m = u.data() ?? {};
      nombre = (m['nombre'] ?? m['displayName'] ?? m['fullName'])?.toString();
    }

    // Si no tiene nombre, buscar en colección de conductores
    if ((nombre == null || nombre.trim().isEmpty)) {
      final c = await FirebaseFirestore.instance.collection('conductores').doc(uid).get();
      if (c.exists) {
        final m = c.data() ?? {};
        nombre = (m['nombreCompleto'] ?? '${m['nombres'] ?? ''} ${m['apellidos'] ?? ''}').toString().trim();
      }
    }

    // Si no hay nombre, mostrar parte del UID
    nombre = (nombre == null || nombre.isEmpty)
        ? uid.substring(0, uid.length.clamp(0, 6))
        : nombre;

    _cacheNombres[uid] = nombre;
    return nombre;
  }

  // ---------------------------------------------------------------------------
  // CONSTRUCCIÓN PRINCIPAL DE LA PANTALLA
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Si no hay sesión activa, mostrar mensaje
    if (uid == null) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No hay sesión activa'),
          ),
        ),
      );
    }

    // Acceso al repositorio de servicios a través de Bloc
    final repo = context.read<ServicioRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis servicios'),
        centerTitle: true,
        actions: [
          // Acceso directo al historial completo de servicios
          IconButton(
            tooltip: 'Historial',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistorialServiciosScreen()),
              );
            },
            icon: const Icon(Icons.history),
          ),
          // Botón para recargar manualmente los servicios
          IconButton(
            tooltip: 'Recargar',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),

          // Si es conductor, mostrar botón segmentado (cliente / conductor)
          if (_esConductor)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Como cliente'),
                    icon: Icon(Icons.person_outline),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Como conductor'),
                    icon: Icon(Icons.local_taxi),
                  ),
                ],
                selected: {_verComoConductor},
                onSelectionChanged: (s) => setState(() => _verComoConductor = s.first),
              ),
            )
          // Si no es conductor, se mantiene la vista como cliente fija
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: const [
                  Icon(Icons.person_outline, size: 18, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('Viendo como cliente'),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // -------------------------------------------------------------------
          // STREAMBUILDER: Escucha servicios activos (cliente o conductor)
          // -------------------------------------------------------------------
          Expanded(
            child: StreamBuilder<List<Servicio>>(
              stream: _verComoConductor
                  ? repo.escucharServiciosActivosConductor(uid)
                  : repo.escucharServiciosActivosCliente(uid),
              builder: (context, snap) {
                // Estado: Cargando
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Estado: Error
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Error cargando servicios: ${snap.error}'),
                    ),
                  );
                }

                // Obtener datos del stream
                final items = snap.data ?? const <Servicio>[];

                // Si no hay servicios activos
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _verComoConductor
                            ? 'No tienes servicios activos como conductor.\nRevisa “Servicios cercanos” para ofertar.'
                            : 'No tienes servicios activos como cliente.\nCrea una nueva solicitud para empezar.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  );
                }

                // Ordenar los servicios por fecha más reciente (aceptación o solicitud)
                items.sort((a, b) {
                  final da = a.fechaAceptacion ?? a.fechaSolicitud;
                  final db = b.fechaAceptacion ?? b.fechaSolicitud;
                  final na = da?.millisecondsSinceEpoch ?? -1;
                  final nb = db?.millisecondsSinceEpoch ?? -1;
                  return nb.compareTo(na);
                });

                // Colores de tema actual
                final cs = Theme.of(context).colorScheme;

                // -----------------------------------------------------------------
                // LISTA DE SERVICIOS ACTIVOS
                // -----------------------------------------------------------------
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = items[i];
                    final origen = s.ruta.isNotEmpty ? s.ruta.first.direccion : 'Origen';
                    final destino = s.ruta.isNotEmpty ? s.ruta.last.direccion : 'Destino';
                    final fecha = s.fechaAceptacion ?? s.fechaSolicitud;
                    final precio = s.precioFinal ?? s.precioEstimado;

                    // Acción inferior (botones dinámicos según estado y rol)
                    final Widget? action = _buildAction(context, s);

                    // Tarjeta del servicio
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Encabezado: tipo de servicio + estado actual
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _tituloTipo(s.tipoServicio),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                _chipEstado(s.estado),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Ruta (origen → destino)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Icon(Icons.route, size: 18, color: Colors.grey),
                                SizedBox(width: 6),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Text(
                                '$origen → $destino',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Fecha y monto
                            Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  fecha != null ? _fmtFecha.format(fecha.toLocal()) : '—',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(width: 14),
                                if (precio != null) ...[
                                  const Icon(Icons.account_balance_wallet, size: 18, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(
                                    _fmtMoneda.format(precio),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Chips de usuario y conductor
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (s.idUsuarioSolicitante.isNotEmpty)
                                  FutureBuilder<String>(
                                    future: _getNombreCorto(s.idUsuarioSolicitante),
                                    builder: (_, snap) => _miniChip(
                                      Icons.person,
                                      'Cliente: ${snap.data ?? '…'}',
                                    ),
                                  ),
                                if ((s.idConductor?.isNotEmpty ?? false))
                                  FutureBuilder<String>(
                                    future: _getNombreCorto(s.idConductor!),
                                    builder: (_, snap) => _miniChip(
                                      Icons.local_taxi,
                                      'Conductor: ${snap.data ?? '…'}',
                                    ),
                                  ),
                              ],
                            ),

                            // Bloque de comprobante demo (si existe)
                            _comprobanteDemoBlock(s),

                            const SizedBox(height: 8),

                            // Acciones dinámicas (ver ofertas, abrir viaje, cancelar)
                            if (action != null)
                              SizedBox(
                                width: double.infinity,
                                child: action,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  // ---------------------------------------------------------------------------
  // CONSTRUCCIÓN DE ACCIONES DINÁMICAS POR SERVICIO
  // ---------------------------------------------------------------------------

  /// Crea los botones de acción según el estado del servicio y el rol del usuario.
  /// - Si es cliente: puede ver ofertas, abrir viaje o cancelar.
  /// - Si es conductor: puede abrir viaje en curso.
  Widget? _buildAction(BuildContext context, Servicio s) {
    final repo = context.read<ServicioRepository>();
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final children = <Widget>[];

    // -----------------------------------------------------------------------
    // ACCIONES PARA EL CLIENTE
    // -----------------------------------------------------------------------
    if (!_verComoConductor) {
      // Si el servicio está pendiente, mostrar botón para ver ofertas recibidas
      if (s.estado == EstadoServicio.pendiente_ofertas) {
        children.add(
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => OfertasServicioScreen(idServicio: s.id!)),
              );
            },
            icon: const Icon(Icons.local_offer),
            label: const Text('Ver ofertas'),
          ),
        );
      }

      // Si el servicio está aceptado o en curso, permitir abrir el mapa del viaje
      if (s.estado == EstadoServicio.aceptado || s.estado == EstadoServicio.en_curso) {
        children.add(
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ViajeEnCursoScreen(
                    idServicio: s.id!,
                    esConductor: false,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map),
            label: const Text('Abrir viaje'),
          ),
        );
      }

      // Si el servicio no está finalizado ni cancelado → puede cancelarse
      final cancelable = s.estado != EstadoServicio.finalizado && s.estado != EstadoServicio.cancelado;
      if (cancelable) {
        children.add(const SizedBox(height: 8));
        children.add(
          OutlinedButton.icon(
            onPressed: () async {
              // Confirmación con diálogo modal
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Cancelar servicio'),
                  content: const Text(
                    '¿Seguro que deseas cancelar este servicio? Esta acción no se puede deshacer.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('No'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sí, cancelar'),
                      style: FilledButton.styleFrom(),
                    ),
                  ],
                ),
              );
              if (ok != true) return;

              // Intentar cancelar desde el repositorio
              try {
                await repo.cancelarServicio(
                  s.id!,
                  motivo: 'Cancelado por cliente desde MisServicios',
                  canceladoPor: uid,
                );
                if (!mounted) return;
                _showSnack('Servicio cancelado');
                setState(() {}); // refresca la lista
              } catch (e) {
                if (!mounted) return;
                _showSnack('Error al cancelar: $e');
              }
            },
            icon: const Icon(Icons.cancel),
            label: const Text('Cancelar servicio'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error),
            ),
          ),
        );
      }
    }

    // -----------------------------------------------------------------------
    // ACCIONES PARA EL CONDUCTOR
    // -----------------------------------------------------------------------
    if (_verComoConductor) {
      // Si el viaje fue aceptado o está en curso → mostrar botón "Ir al viaje"
      if (s.estado == EstadoServicio.aceptado || s.estado == EstadoServicio.en_curso) {
        children.add(
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ViajeEnCursoScreen(
                    idServicio: s.id!,
                    esConductor: true,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.navigation),
            label: const Text('Ir al viaje'),
          ),
        );
      }
    }

    // Si no hay botones que mostrar, devolver null
    if (children.isEmpty) return null;

    // Si hay varias acciones, se muestran en columna
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ---------------------------------------------------------------------------
  // ELEMENTOS AUXILIARES VISUALES
  // ---------------------------------------------------------------------------

  /// Crea un chip pequeño con ícono y texto (usado para mostrar cliente/conductor).
  Widget _miniChip(IconData icon, String text) {
    return Chip(
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(text, overflow: TextOverflow.ellipsis),
    );
  }

  // ---------------------------------------------------------------------------
  // BLOQUE DE COMPROBANTE DEMO (VISUALIZACIÓN DEL PDF DE PRUEBA)
  // ---------------------------------------------------------------------------

  /// Muestra, si existe, un comprobante demo generado por el conductor (PDF en Firebase).
  Widget _comprobanteDemoBlock(Servicio s) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('servicios').doc(s.id).get(),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();

        final data = snap.data!.data() ?? {};
        final comp = data['comprobanteDemo'] as Map<String, dynamic>?;
        if (comp == null) return const SizedBox.shrink();

        final url = (comp['urlPdf'] ?? '') as String;
        if (url.isEmpty) return const SizedBox.shrink();

        final tipo = (comp['tipo'] ?? '—').toString();
        final emisor = (comp['emisor'] ?? '—').toString();
        final serieN = (comp['serieNumero'] ?? '—').toString();

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade200),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: Colors.brown),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Comprobante (DEMO) $tipo',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$serieN  •  Emisor: $emisor',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                // Botón para abrir el PDF externo
                TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Ver'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MÉTODOS DE FORMATEO DE INFORMACIÓN
  // ---------------------------------------------------------------------------

  /// Devuelve el texto descriptivo del tipo de servicio.
  String _tituloTipo(TipoServicio t) {
    switch (t) {
      case TipoServicio.carga_ligera:
        return 'Carga ligera';
      case TipoServicio.carga_pesada:
        return 'Carga pesada';
      case TipoServicio.mudanza:
        return 'Mudanza';
      case TipoServicio.taxi:
        return 'Pasajeros';
    }
  }

  /// Crea un chip con color e icono según el estado del servicio.
  Widget _chipEstado(EstadoServicio e) {
    Color bg;
    String label;

    switch (e) {
      case EstadoServicio.pendiente_ofertas:
        bg = Colors.blueGrey;
        label = 'PENDIENTE';
        break;
      case EstadoServicio.aceptado:
        bg = Colors.amber;
        label = 'ACEPTADO';
        break;
      case EstadoServicio.en_curso:
        bg = Colors.green;
        label = 'EN CURSO';
        break;
      case EstadoServicio.finalizado:
        bg = Colors.grey;
        label = 'FINALIZADO';
        break;
      case EstadoServicio.cancelado:
        bg = Colors.red;
        label = 'CANCELADO';
        break;
    }

    return Chip(
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      backgroundColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
