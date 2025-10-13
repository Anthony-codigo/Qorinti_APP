// lib/pantallas/vehiculos/invitaciones_vehiculo_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: Invitaciones de Vehículo para Conductores
// Permite al conductor visualizar las invitaciones recibidas de propietarios
// de vehículos y decidir si desea aceptar o rechazar la vinculación.
// También actualiza los estados correspondientes en la base de datos Firestore.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_qorinti/modelos/conductor_vehiculo.dart';

class InvitacionesVehiculoScreen extends StatelessWidget {
  static const route = '/vehiculo/invitaciones';
  const InvitacionesVehiculoScreen({super.key});

  // --------------------------------------------------------------------------
  // Cambia el estado de una relación a un valor básico (APROBADO o RECHAZADO)
  // --------------------------------------------------------------------------
  Future<void> _cambiarEstadoBasico({
    required String idRelacion,
    required String nuevoEstado,
    required BuildContext context,
    required String placa,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'estadoVinculo': nuevoEstado.toUpperCase(),
        'estado': nuevoEstado.toUpperCase(), // compatibilidad con campo antiguo
        'actualizadoEn': FieldValue.serverTimestamp(),
      };

      // Si la invitación fue aceptada, registra la fecha de inicio
      if (nuevoEstado.toUpperCase() == 'APROBADO') {
        updateData['fechaInicio'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('conductor_vehiculo')
          .doc(idRelacion)
          .update(updateData);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nuevoEstado.toUpperCase() == 'APROBADO'
                ? "Has aceptado la invitación del vehículo $placa"
                : "Has rechazado la invitación del vehículo $placa",
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  // --------------------------------------------------------------------------
  // Acepta la invitación de un vehículo y marca el vínculo como APROBADO.
  // Si no existe otro conductor activo para el vehículo, este se marca activo.
  // --------------------------------------------------------------------------
  Future<void> _aceptarInvitacion({
    required String idRelacion,
    required String idVehiculo,
    required BuildContext context,
    required String placa,
  }) async {
    final fs = FirebaseFirestore.instance;

    try {
      // Actualiza la relación principal a estado APROBADO
      await fs.collection('conductor_vehiculo').doc(idRelacion).update({
        'estadoVinculo': 'APROBADO',
        'estado': 'APROBADO',
        'fechaInicio': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // Verifica si ya existe otro conductor activo para el mismo vehículo
      final otros = await fs
          .collection('conductor_vehiculo')
          .where('idVehiculo', isEqualTo: idVehiculo)
          .where('activo', isEqualTo: true)
          .limit(1)
          .get();

      // Si no hay otro conductor activo, activa esta relación
      if (otros.docs.isEmpty) {
        final batch = fs.batch();
        final allVinculos = await fs
            .collection('conductor_vehiculo')
            .where('idVehiculo', isEqualTo: idVehiculo)
            .get();

        for (final d in allVinculos.docs) {
          final isTarget = d.id == idRelacion;
          batch.update(d.reference, {
            'activo': isTarget,
            if (isTarget) 'estadoVinculo': 'APROBADO',
            if (isTarget) 'estado': 'APROBADO',
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Has aceptado la invitación del vehículo $placa")),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al aceptar: $e")),
      );
    }
  }

  // --------------------------------------------------------------------------
  // Rechaza la invitación de un vehículo
  // --------------------------------------------------------------------------
  Future<void> _rechazarInvitacion({
    required String idRelacion,
    required BuildContext context,
    required String placa,
  }) async {
    await _cambiarEstadoBasico(
      idRelacion: idRelacion,
      nuevoEstado: 'RECHAZADO',
      context: context,
      placa: placa,
    );
  }

  // --------------------------------------------------------------------------
  // INTERFAZ PRINCIPAL
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Si el usuario no ha iniciado sesión, se muestra un mensaje informativo
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text("No hay sesión activa")),
      );
    }

    // Referencia a las invitaciones del usuario actual
    final invitacionesRef = FirebaseFirestore.instance
        .collection('conductor_vehiculo')
        .where('idConductor', isEqualTo: uid);

    return Scaffold(
      appBar: AppBar(title: const Text("Invitaciones de Vehículo")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: invitacionesRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snap.hasError) {
            return Center(child: Text("Error: ${snap.error}"));
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(
              child: Text("No tienes invitaciones pendientes"),
            );
          }

          // Filtra solo invitaciones en estado PENDIENTE
          final pendientes = snap.data!.docs.where((d) {
            final data = d.data();
            final e1 = (data['estadoVinculo'] ?? '').toString().toUpperCase();
            final e2 = (data['estado'] ?? '').toString().toUpperCase();
            return e1 == 'PENDIENTE' || (e1.isEmpty && e2 == 'PENDIENTE');
          }).toList();

          if (pendientes.isEmpty) {
            return const Center(
              child: Text("No tienes invitaciones pendientes"),
            );
          }

          // Construye lista de invitaciones
          return ListView.builder(
            itemCount: pendientes.length,
            itemBuilder: (context, i) {
              final doc = pendientes[i];
              final relacion =
                  ConductorVehiculo.fromMap(doc.data(), id: doc.id);

              // Consulta información del vehículo asociado
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('vehiculos')
                    .doc(relacion.idVehiculo)
                    .get(),
                builder: (context, vehSnap) {
                  if (vehSnap.connectionState == ConnectionState.waiting) {
                    return const ListTile(title: Text("Cargando vehículo..."));
                  }

                  final veh = vehSnap.data?.data() ?? {};
                  final placa = (veh['placa'] ?? '---').toString();
                  final marca = (veh['marca'] ?? '---').toString();
                  final tipo = (veh['tipo'] ?? '').toString();
                  final carroceria = (veh['tipoCarroceria'] ?? '').toString();

                  // Tarjeta visual con la información del vehículo invitante
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: const Icon(
                        Icons.directions_car,
                        size: 40,
                        color: Colors.blueGrey,
                      ),
                      title: Text("Placa: $placa"),
                      subtitle: Text(
                        [
                          if (marca.isNotEmpty) "Marca: $marca",
                          if (tipo.isNotEmpty) "Tipo: $tipo",
                          if (carroceria.isNotEmpty)
                            "Carrocería: $carroceria",
                        ].join(" • "),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Botón de aceptación de invitación
                          IconButton(
                            icon: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                            tooltip: "Aceptar",
                            onPressed: () => _aceptarInvitacion(
                              idRelacion: relacion.id!,
                              idVehiculo: relacion.idVehiculo,
                              context: context,
                              placa: placa,
                            ),
                          ),

                          // Botón de rechazo de invitación
                          IconButton(
                            icon: const Icon(
                              Icons.cancel,
                              color: Colors.redAccent,
                            ),
                            tooltip: "Rechazar",
                            onPressed: () => _rechazarInvitacion(
                              idRelacion: relacion.id!,
                              context: context,
                              placa: placa,
                            ),
                          ),
                        ],
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
