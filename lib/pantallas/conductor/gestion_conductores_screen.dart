// lib/pantallas/vehiculos/gestion_conductores_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: Gestión de Conductores asignados a un vehículo
// Permite al propietario de un vehículo visualizar, activar, suspender,
// reactivar o finalizar los vínculos de conductores asociados a su unidad.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_qorinti/modelos/conductor_vehiculo.dart';

class GestionConductoresScreen extends StatelessWidget {
  final String idVehiculo; // ID del vehículo
  final String placa;      // Placa del vehículo (para mostrar en título)

  const GestionConductoresScreen({
    super.key,
    required this.idVehiculo,
    required this.placa,
  });

  // --------------------------------------------------------------------------
  // Cambia el estado del vínculo (ej: APROBADO, SUSPENDIDO, etc.)
  // --------------------------------------------------------------------------
  Future<void> _setEstado(
    String relacionId,
    String nuevoEstado,
    BuildContext context,
  ) async {
    try {
      final up = <String, dynamic>{
        'estadoVinculo': nuevoEstado.toUpperCase(),
        'estado': nuevoEstado.toUpperCase(), // compatibilidad
        'actualizadoEn': FieldValue.serverTimestamp(),
        if (nuevoEstado.toUpperCase() == 'APROBADO')
          'fechaInicio': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('conductor_vehiculo')
          .doc(relacionId)
          .update(up);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Relación cambiada a $nuevoEstado")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al cambiar estado: $e")),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // Marca el vínculo como FINALIZADO (el conductor deja de estar activo)
  // --------------------------------------------------------------------------
  Future<void> _finalizarRelacion(
    String relacionId,
    BuildContext context,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('conductor_vehiculo')
          .doc(relacionId)
          .update({
        'estadoVinculo': 'FINALIZADO',
        'estado': 'FINALIZADO',
        'activo': false,
        'fechaFin': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Conductor finalizado")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al finalizar: $e")),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // Marca como ACTIVO un conductor y desactiva los demás del mismo vehículo.
  // Solo un vínculo puede estar activo por vehículo.
  // --------------------------------------------------------------------------
  Future<void> _marcarComoActivo(
    String relacionId,
    String idVehiculo,
    BuildContext context,
  ) async {
    final fs = FirebaseFirestore.instance;
    final batch = fs.batch();
    try {
      final otros = await fs
          .collection('conductor_vehiculo')
          .where('idVehiculo', isEqualTo: idVehiculo)
          .get();

      for (final d in otros.docs) {
        final isTarget = d.id == relacionId;
        if (isTarget) {
          batch.update(d.reference, {
            'activo': true,
            'estadoVinculo': 'APROBADO',
            'estado': 'APROBADO',
            'fechaInicio': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
        } else {
          batch.update(d.reference, {
            'activo': false,
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Vínculo marcado como ACTIVO")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al activar: $e")),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // Devuelve el estado legible (soporta compatibilidad con campos antiguos)
  // --------------------------------------------------------------------------
  String _estadoDisplay(ConductorVehiculo rel) {
    final e = rel.estadoVinculo.toUpperCase();
    if (e.isNotEmpty) return e;
    final legacy = (rel.toMap()['estado'] ?? '').toString().toUpperCase();
    return legacy.isNotEmpty ? legacy : 'PENDIENTE';
  }

  // --------------------------------------------------------------------------
  // Asigna color de fondo a cada estado
  // --------------------------------------------------------------------------
  Color _estadoBgColor(String estado) {
    switch (estado.toUpperCase()) {
      case 'APROBADO':
      case 'ACTIVO':
        return Colors.green.shade100;
      case 'PENDIENTE':
        return Colors.orange.shade100;
      case 'SUSPENDIDO':
        return Colors.yellow.shade100;
      case 'RECHAZADO':
      case 'FINALIZADO':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade300;
    }
  }

  // --------------------------------------------------------------------------
  // Construye un chip visual de estado
  // --------------------------------------------------------------------------
  Chip _chipEstado(String text, Color bg) => Chip(
        label: Text(text),
        backgroundColor: bg,
        visualDensity: VisualDensity.compact,
      );

  // --------------------------------------------------------------------------
  // Cuadro de confirmación antes de realizar acciones importantes
  // --------------------------------------------------------------------------
  Future<bool> _confirm(BuildContext context, String msg,
      {String ok = 'Aceptar'}) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirmar'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(ok),
              ),
            ],
          ),
        ) ??
        false;
  }

  // --------------------------------------------------------------------------
  // INTERFAZ PRINCIPAL
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final relRef = FirebaseFirestore.instance
        .collection('conductor_vehiculo')
        .where('idVehiculo', isEqualTo: idVehiculo);

    return Scaffold(
      appBar: AppBar(title: Text("Conductores de $placa")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: relRef.snapshots(),
        builder: (context, relSnap) {
          if (relSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!relSnap.hasData || relSnap.data!.docs.isEmpty) {
            return const Center(child: Text("No hay conductores asignados 🚗"));
          }

          // Convierte los documentos en objetos ConductorVehiculo
          final relaciones = relSnap.data!.docs
              .map((d) => ConductorVehiculo.fromMap(d.data(), id: d.id))
              .toList();

          // Orden lógico de visualización según estado
          const orden = {
            'ACTIVO': 0,
            'APROBADO': 1,
            'PENDIENTE': 2,
            'SUSPENDIDO': 3,
            'RECHAZADO': 4,
            'FINALIZADO': 5,
          };
          relaciones.sort((a, b) {
            final ea = a.activo == true ? 'ACTIVO' : _estadoDisplay(a);
            final eb = b.activo == true ? 'ACTIVO' : _estadoDisplay(b);
            return (orden[ea.toUpperCase()] ?? 99)
                .compareTo(orden[eb.toUpperCase()] ?? 99);
          });

          // Renderiza lista de relaciones con datos del conductor
          return ListView.separated(
            itemCount: relaciones.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            itemBuilder: (context, i) {
              final rel = relaciones[i];
              final estado = _estadoDisplay(rel);
              final estadoBg = _estadoBgColor(estado);
              final esActivo = rel.activo == true;
              final idConductor = rel.idConductor;

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(idConductor)
                    .get(),
                builder: (context, userSnap) {
                  if (userSnap.connectionState == ConnectionState.waiting) {
                    return const ListTile(title: Text("Cargando conductor..."));
                  }

                  // Datos básicos del conductor
                  final user = userSnap.data?.data() ?? {};
                  final nombre = (user['nombre'] ?? 'Sin nombre').toString();
                  final correo = (user['correo'] ?? '---').toString();
                  final fotoUrl = (user['fotoUrl'] ?? '').toString();

                  // Tarjeta visual por cada conductor
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundImage:
                            fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
                        child: fotoUrl.isEmpty
                            ? Text(
                                (nombre.isNotEmpty ? nombre[0] : '?')
                                    .toUpperCase(),
                              )
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              nombre,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (esActivo)
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 18),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(correo),
                            const SizedBox(height: 6),
                            _chipEstado(estado, estadoBg),
                          ],
                        ),
                      ),

                      // Menú contextual con acciones según estado
                      trailing: PopupMenuButton<String>(
                        onSelected: (op) async {
                          switch (op) {
                            case 'activar':
                              if (await _confirm(
                                  context, '¿Marcar este vínculo como ACTIVO?')) {
                                await _marcarComoActivo(
                                    rel.id!, idVehiculo, context);
                              }
                              break;
                            case 'suspender':
                              if (await _confirm(
                                  context, '¿Suspender al conductor?')) {
                                await _setEstado(rel.id!, 'SUSPENDIDO', context);
                              }
                              break;
                            case 'finalizar':
                              if (await _confirm(context,
                                  '¿Finalizar el vínculo? Esta acción detiene la operación.')) {
                                await _finalizarRelacion(rel.id!, context);
                              }
                              break;
                            case 'reactivar':
                              if (await _confirm(context,
                                  '¿Reactivar al conductor (APROBADO)?')) {
                                await _setEstado(rel.id!, 'APROBADO', context);
                              }
                              break;
                          }
                        },
                        itemBuilder: (c) {
                          final items = <PopupMenuEntry<String>>[];
                          final e = estado.toUpperCase();

                          // Acciones disponibles según estado actual
                          if (!esActivo && (e == 'APROBADO' || e == 'SUSPENDIDO')) {
                            items.add(const PopupMenuItem(
                              value: 'activar',
                              child: Text("Marcar como ACTIVO"),
                            ));
                          }

                          if (e == 'APROBADO') {
                            items.addAll(const [
                              PopupMenuItem(
                                value: 'suspender',
                                child: Text("Suspender"),
                              ),
                              PopupMenuItem(
                                value: 'finalizar',
                                child: Text("Finalizar"),
                              ),
                            ]);
                          } else if (e == 'SUSPENDIDO') {
                            items.addAll(const [
                              PopupMenuItem(
                                value: 'reactivar',
                                child: Text("Reactivar"),
                              ),
                              PopupMenuItem(
                                value: 'finalizar',
                                child: Text("Finalizar"),
                              ),
                            ]);
                          }

                          return items;
                        },
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
