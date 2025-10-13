// lib/pantallas/servicios/calificar_servicio_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: CalificarServicioScreen
// Descripción:
//   Permite que un conductor o un cliente califique un servicio finalizado,
//   asignando entre 1 y 5 estrellas y un comentario opcional. 
//   Gestiona la lectura, creación y actualización de calificaciones en Firestore.
//
// Dependencias principales:
//   - FirebaseAuth: para identificar al usuario autenticado.
//   - Cloud Firestore: para persistir calificaciones y actualizar resumen del servicio.
//   - ServicioRepository: para escuchar datos actualizados del servicio calificado.
// -----------------------------------------------------------------------------

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:app_qorinti/modelos/servicio.dart';
import 'package:app_qorinti/modelos/calificacion.dart';
import 'package:app_qorinti/repos/servicio_repository.dart';

/// Widget principal que muestra la interfaz de calificación de un servicio.
///
/// Parámetros:
/// - [idServicio]: Identificador del servicio a calificar.
/// - [esConductor]: Indica si la calificación la realiza el conductor (true) o el cliente (false).
class CalificarServicioScreen extends StatefulWidget {
  final String idServicio;
  final bool esConductor;

  const CalificarServicioScreen({
    super.key,
    required this.idServicio,
    required this.esConductor,
  });

  @override
  State<CalificarServicioScreen> createState() => _CalificarServicioScreenState();
}

class _CalificarServicioScreenState extends State<CalificarServicioScreen> {
  // Controlador del campo de comentario
  final _comentarioCtrl = TextEditingController();
  // Formateador de fecha para mostrar detalles del servicio
  final _fmtFecha = DateFormat('dd/MM/yyyy HH:mm', 'es_PE');

  // Valor de estrellas seleccionadas (1 a 5)
  int _estrellas = 0;
  // Bandera de estado de envío para bloquear la UI
  bool _enviando = false;
  // ID del documento de calificación (si ya existe una previa)
  String? _calificacionDocId;

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  /// Obtiene el nombre o correo asociado a un usuario por su UID desde Firestore.
  /// Devuelve `null` si no se encuentra o si ocurre un error.
  Future<String?> _getNombreUsuario(String uid) async {
    try {
      final d = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (!d.exists) return null;
      final data = d.data() ?? {};
      final nombre = (data['nombre'] ?? '').toString().trim();
      final correo = (data['correo'] ?? '').toString().trim();
      if (nombre.isNotEmpty) return nombre;
      if (correo.isNotEmpty) return correo;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Carga la calificación previa del usuario para el servicio indicado (si existe).
  /// Permite editar una calificación ya creada, evitando duplicados.
  Future<void> _cargarCalificacionPrevia(Servicio servicio) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || servicio.id == null) return;

    final qs = await FirebaseFirestore.instance
        .collection('calificaciones')
        .where('idServicio', isEqualTo: servicio.id)
        .where('deUsuarioId', isEqualTo: uid)
        .limit(1)
        .get();

    if (qs.docs.isNotEmpty) {
      final d = qs.docs.first;
      final cal = Calificacion.fromMap(d.data(), d.id);
      setState(() {
        _calificacionDocId = d.id;
        _estrellas = cal.estrellas;
        _comentarioCtrl.text = cal.comentario ?? '';
      });
    }
  }

  /// Guarda o actualiza la calificación actual del usuario para el servicio.
  /// Incluye validaciones de estrellas, sesión y destinatario.
  Future<void> _guardar(BuildContext context, Servicio servicio) async {
    if (_estrellas <= 0) {
      _snack('Elige entre 1 y 5 estrellas');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _snack('Debes iniciar sesión.');
      return;
    }
    if (servicio.id == null) {
      _snack('Servicio inválido.');
      return;
    }

    // Determina el destinatario de la calificación:
    // - Si es conductor: califica al usuario solicitante.
    // - Si es cliente: califica al conductor.
    final String? paraUsuarioId = widget.esConductor
        ? servicio.idUsuarioSolicitante
        : (servicio.idConductor?.isNotEmpty == true ? servicio.idConductor! : null);

    if (paraUsuarioId == null || paraUsuarioId.isEmpty) {
      _snack('No se pudo identificar a quién calificar.');
      return;
    }

    setState(() => _enviando = true);
    try {
      final calRef = FirebaseFirestore.instance.collection('calificaciones');
      final nowServer = FieldValue.serverTimestamp();

      // Datos a registrar en Firestore
      final payload = {
        'idServicio': servicio.id!,
        'deUsuarioId': uid,
        'paraUsuarioId': paraUsuarioId,
        'estrellas': _estrellas,
        'comentario': _comentarioCtrl.text.trim().isEmpty ? null : _comentarioCtrl.text.trim(),
        'creadoEn': nowServer,
      };

      // Si existe calificación previa, actualiza; si no, crea una nueva
      if (_calificacionDocId != null) {
        await calRef.doc(_calificacionDocId!).set(payload, SetOptions(merge: true));
      } else {
        final newDoc = await calRef.add(payload);
        _calificacionDocId = newDoc.id;
      }

      // Actualiza la calificación resumida dentro del documento del servicio
      final campoResumen = widget.esConductor ? 'calificacionUsuario' : 'calificacionConductor';
      await FirebaseFirestore.instance.collection('servicios').doc(servicio.id!).update({
        campoResumen: _estrellas,
        'fechaActualizacion': nowServer,
      });

      if (!mounted) return;
      _snack('¡Gracias por calificar!');
      Navigator.of(context).pop(); // Cierra la pantalla tras guardar
    } catch (e) {
      _snack('Error al guardar calificación: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Muestra un mensaje tipo SnackBar en la parte inferior de la pantalla.
  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ServicioRepository>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.esConductor ? 'Califica al cliente' : 'Califica al conductor'),
        centerTitle: true,
      ),
      // Escucha en tiempo real los cambios del servicio seleccionado
      body: StreamBuilder<Servicio?>(
        stream: repo.escucharServicio(widget.idServicio),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final servicio = snap.data;
          if (servicio == null) {
            return const Center(child: Text('No se encontró el servicio.'));
          }

          // Carga la calificación previa si aún no se ha cargado
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_calificacionDocId == null) {
              _cargarCalificacionPrevia(servicio);
            }
          });

          // Datos del servicio para mostrar en la cabecera
          final origen = servicio.ruta.isNotEmpty ? servicio.ruta.first.direccion : 'Origen';
          final destino = servicio.ruta.isNotEmpty ? servicio.ruta.last.direccion : 'Destino';
          final fecha = servicio.fechaFin ?? servicio.fechaSolicitud;
          final idMostrado = widget.esConductor ? servicio.idUsuarioSolicitante : (servicio.idConductor ?? '-');

          // Obtiene el nombre del usuario calificado para mostrarlo
          return FutureBuilder<String?>(
            future: idMostrado != '-' ? _getNombreUsuario(idMostrado) : Future.value(null),
            builder: (_, nameSnap) {
              final showName = nameSnap.data?.trim();
              final displayPersona = (showName != null && showName.isNotEmpty) ? showName : idMostrado;

              // Contenido principal de la pantalla
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tarjeta con detalles del servicio y persona calificada
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  widget.esConductor ? Icons.person_outline : Icons.local_taxi,
                                  color: Colors.indigo,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.esConductor
                                        ? 'Cliente: $displayPersona'
                                        : 'Conductor: $displayPersona',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.route, size: 18, color: Colors.grey),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('$origen → $destino',
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  _fmtFecha.format(fecha.toLocal()),
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Sección de calificación con estrellas
                    const Text(
                      '¿Cómo fue tu experiencia?',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: List.generate(5, (i) {
                        final idx = i + 1;
                        final filled = idx <= _estrellas;
                        return IconButton(
                          tooltip: '$idx estrellas',
                          onPressed: _enviando ? null : () => setState(() => _estrellas = idx),
                          iconSize: 36,
                          icon: Icon(
                            filled ? Icons.star : Icons.star_border,
                            color: filled ? Colors.amber : Colors.grey,
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 12),

                    // Campo de comentario opcional
                    TextField(
                      controller: _comentarioCtrl,
                      maxLines: 4,
                      enabled: !_enviando,
                      decoration: const InputDecoration(
                        labelText: 'Comentario (opcional)',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                        hintText: '¿Algo que debamos saber sobre tu experiencia?',
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Botón para guardar o actualizar la calificación
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _enviando ? null : () => _guardar(context, servicio),
                        icon: _enviando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          _calificacionDocId == null
                              ? 'Guardar calificación'
                              : 'Actualizar calificación',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
