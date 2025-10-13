// lib/pantallas/vehiculos/mis_vehiculos_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: Mis Vehículos
// Esta vista permite a los conductores y propietarios visualizar los vehículos
// asociados a su cuenta. Integra la información de las colecciones
// `vehiculos` y `conductor_vehiculo` para determinar los vínculos activos,
// su rol dentro del vehículo (propietario o asociado), el estado de
// aprobación y las acciones permitidas.
// Incluye además funciones para asignar conductores, gestionar relaciones,
// reactivar vínculos de propietario y desasociarse de un vehículo.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:app_qorinti/modelos/utils.dart';
import 'package:app_qorinti/modelos/conductor_vehiculo.dart';
import 'package:app_qorinti/pantallas/conductor/asignar_conductor_screen.dart';
import 'package:app_qorinti/pantallas/conductor/gestion_conductores_screen.dart';
import 'package:app_qorinti/pantallas/conductor/invitaciones_vehiculo_screen.dart';

class MisVehiculosScreen extends StatelessWidget {
  static const route = '/vehiculo/mis';
  const MisVehiculosScreen({super.key});

  // --------------------------------------------------------------------------
  // Divide una lista de IDs en grupos más pequeños (paginación manual)
  // Esto se utiliza para evitar limitaciones de Firestore en consultas `whereIn`.
  // --------------------------------------------------------------------------
  List<List<String>> _chunkIds(List<String> ids, {int size = 10}) {
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += size) {
      chunks.add(ids.sublist(i, i + size > ids.length ? ids.length : i + size));
    }
    return chunks;
  }

  // --------------------------------------------------------------------------
  // Crea un chip visual reutilizable para mostrar estados o roles
  // --------------------------------------------------------------------------
  Chip _chip(String text, Color color) => Chip(
        label: Text(text),
        backgroundColor: color.withOpacity(.12),
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  // --------------------------------------------------------------------------
  // Obtiene los vehículos asociados al usuario (como conductor o propietario)
  // Incluye vínculos activos o aprobados, y también los vehículos propios.
  // --------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> _fetchVehiculos(String uid) async {
    final fs = FirebaseFirestore.instance;

    // Relaciones donde el usuario figura como conductor
    final relSnap = await fs
        .collection('conductor_vehiculo')
        .where('idConductor', isEqualTo: uid)
        .get();

    // Se filtran relaciones activas o aprobadas
    final relaciones = relSnap.docs
        .map((d) => ConductorVehiculo.fromMap(d.data(), id: d.id))
        .where((r) {
          final e = r.estadoVinculo.toUpperCase();
          return r.activo == true || e == 'APROBADO' || e == 'ACTIVO';
        })
        .toList();

    final results = <Map<String, dynamic>>[];

    // Recupera datos de vehículos vinculados
    if (relaciones.isNotEmpty) {
      final vehiculoIds = relaciones.map((r) => r.idVehiculo).toList();
      for (final batch in _chunkIds(vehiculoIds)) {
        final vehiculosSnap = await fs
            .collection('vehiculos')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final d in vehiculosSnap.docs) {
          final data = d.data();
          data['id'] = d.id;

          // Vinculación correspondiente
          final relacion = relaciones.firstWhere(
            (r) => r.idVehiculo == d.id,
            orElse: () => ConductorVehiculo(
              id: null,
              idConductor: uid,
              idVehiculo: d.id,
              estadoVinculo: 'APROBADO',
              activo: false,
            ),
          );

          // Determina el rol del usuario en el vehículo
          final rolAsignacion = (relacion.toMap()['rolAsignacion'] ??
                  data['rolAsignacion'] ??
                  ((data['idPropietarioUsuario'] == uid)
                      ? 'PROPIETARIO'
                      : 'ASOCIADO'))
              .toString();

          results.add({
            ...data,
            'relacionId': relacion.id,
            'rolAsignacion': rolAsignacion,
            'activoVinculo': relacion.activo == true,
            'estadoVinculo': relacion.estadoVinculo.toUpperCase(),
          });
        }
      }
    }

    // Incluye vehículos propios aprobados que no están ya listados
    final yaIncluidos = results.map((e) => e['id'] as String).toSet();
    final propiosSnap = await fs
        .collection('vehiculos')
        .where('idPropietarioUsuario', isEqualTo: uid)
        .where('estado', isEqualTo: 'APROBADO')
        .get();

    for (final d in propiosSnap.docs) {
      if (yaIncluidos.contains(d.id)) continue;
      final data = d.data();
      results.add({
        ...data,
        'id': d.id,
        'rolAsignacion': 'PROPIETARIO',
        'idPropietarioUsuario': uid,
        'activoVinculo': false,
        'estadoVinculo': 'FINALIZADO',
        'needsReactivation': true,
      });
    }

    // Ordena la lista priorizando vínculos activos y más recientes
    results.sort((a, b) {
      final aAct = a['activoVinculo'] == true ? 0 : 1;
      final bAct = b['activoVinculo'] == true ? 0 : 1;
      if (aAct != bAct) return aAct.compareTo(bAct);

      DateTime ta = DateTime(0), tb = DateTime(0);
      final va = a['actualizadoEn'] ?? a['creadoEn'];
      final vb = b['actualizadoEn'] ?? b['creadoEn'];
      if (va is Timestamp) ta = va.toDate();
      if (vb is Timestamp) tb = vb.toDate();
      return tb.compareTo(ta);
    });

    return results;
  }

  // --------------------------------------------------------------------------
  // Permite al propietario reactivar su vínculo en caso de haber finalizado
  // --------------------------------------------------------------------------
  Future<void> _reactivarmeComoPropietario({
    required BuildContext context,
    required String idVehiculo,
    required String uid,
  }) async {
    final fs = FirebaseFirestore.instance;
    try {
      final vDoc = await fs.collection('vehiculos').doc(idVehiculo).get();
      if (!vDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehículo no existe'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final v = vDoc.data()!;
      if ((v['idPropietarioUsuario'] ?? '') != uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No eres el propietario'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if ((v['estado'] ?? 'PENDIENTE').toString().toUpperCase() != 'APROBADO') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehículo no está aprobado'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final ahora = FieldValue.serverTimestamp();

      // Desactiva todos los vínculos existentes del vehículo
      final allVinc = await fs
          .collection('conductor_vehiculo')
          .where('idVehiculo', isEqualTo: idVehiculo)
          .get();
      final batch = fs.batch();
      for (final d in allVinc.docs) {
        batch.update(d.reference, {'activo': false, 'actualizadoEn': ahora});
      }

      // Si el propietario no tenía vínculo, se crea uno nuevo
      final relSnap = await fs
          .collection('conductor_vehiculo')
          .where('idConductor', isEqualTo: uid)
          .where('idVehiculo', isEqualTo: idVehiculo)
          .limit(1)
          .get();

      if (relSnap.docs.isEmpty) {
        final data = {
          'idConductor': uid,
          'idVehiculo': idVehiculo,
          'rolAsignacion': 'PROPIETARIO',
          'estadoVinculo': 'APROBADO',
          'estado': 'APROBADO',
          'activo': true,
          'fechaInicio': ahora,
          'creadoEn': ahora,
          'actualizadoEn': ahora,
        };
        batch.set(fs.collection('conductor_vehiculo').doc(), data);
      } else {
        batch.update(relSnap.docs.first.reference, {
          'rolAsignacion': 'PROPIETARIO',
          'estadoVinculo': 'APROBADO',
          'estado': 'APROBADO',
          'activo': true,
          'fechaInicio': ahora,
          'actualizadoEn': ahora,
        });
      }

      await batch.commit();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vínculo reactivado como PROPIETARIO')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // --------------------------------------------------------------------------
  // Permite a un conductor desasociarse voluntariamente de un vehículo
  // --------------------------------------------------------------------------
  Future<void> _desasociar(String relacionId, BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desasociarte del vehículo'),
        content: const Text(
            '¿Seguro que deseas finalizar tu vínculo con este vehículo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Finalizar')),
        ],
      ),
    );
    if (ok != true) return;

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

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Te has desasociado del vehículo")),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  // --------------------------------------------------------------------------
  // INTERFAZ PRINCIPAL
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Validación de sesión activa
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text("No hay sesión activa")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Vehículos"),
        actions: [
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: "Invitaciones de Vehículo",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InvitacionesVehiculoScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchVehiculos(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snap.hasError) {
            return Center(child: Text("Error: ${snap.error}"));
          }
          if (!snap.hasData || snap.data!.isEmpty) {
            return const Center(
                child: Text("No tienes vehículos asociados"));
          }

          final vehiculos = snap.data!;

          // Renderiza cada vehículo con sus acciones disponibles
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: vehiculos.length,
            itemBuilder: (context, i) {
              final v = vehiculos[i];
              final placa = (v['placa'] ?? '---').toString();
              final marca = (v['marca'] ?? '---').toString();
              final modelo = (v['modelo'] ?? '---').toString();
              final estado =
                  (v['estado'] ?? 'PENDIENTE').toString().toUpperCase();
              final soatVencimiento = dt(v['soatVencimiento']);
              final revision = dt(v['revisionTecnica']);
              final idPropietario = v['idPropietarioUsuario'];
              final rol = (v['rolAsignacion'] ?? 'ASOCIADO').toString();
              final activoVinculo = v['activoVinculo'] == true;
              final estadoVinculo =
                  (v['estadoVinculo'] ?? 'APROBADO').toString();
              final needsReactivation = v['needsReactivation'] == true;

              // Define color según estado del vehículo
              Color estadoColor;
              switch (estado) {
                case 'APROBADO':
                case 'ACTIVO':
                  estadoColor = Colors.green;
                  break;
                case 'RECHAZADO':
                case 'FINALIZADO':
                  estadoColor = Colors.red;
                  break;
                default:
                  estadoColor = Colors.orange;
              }

              final esPropietario = idPropietario == uid;
              final vehiculoAprobado = estado == 'APROBADO';

              // Tarjeta visual con la información del vehículo
              return Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: estadoColor.withOpacity(.12),
                        child:
                            Icon(Icons.directions_car, color: estadoColor, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    "Placa: $placa",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _chip(rol,
                                    esPropietario ? Colors.indigo : Colors.blueGrey),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text("Marca: $marca • Modelo: $modelo"),
                            const SizedBox(height: 6),

                            // Chips de estado y vínculos
                            Wrap(
                              spacing: 6,
                              runSpacing: -4,
                              children: [
                                _chip(estado, estadoColor),
                                if (activoVinculo)
                                  _chip('Vínculo activo', Colors.green),
                                if (!vehiculoAprobado)
                                  _chip('En revisión', Colors.orange),
                                if (estadoVinculo == 'PENDIENTE')
                                  _chip('Invitación pendiente', Colors.orange),
                                if (needsReactivation)
                                  _chip('Vínculo finalizado', Colors.red),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Información complementaria del vehículo
                            Text(
                              "SOAT: ${soatVencimiento != null ? formatDate(soatVencimiento) : "No registrado"} • "
                              "Revisión: ${revision != null ? formatDate(revision) : "No registrada"}",
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                            const SizedBox(height: 8),

                            // Acciones contextuales según el rol
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _acciones(
                                context,
                                v,
                                esPropietario,
                                vehiculoAprobado,
                                uid,
                                needsReactivation: needsReactivation,
                              ),
                            ),
                          ],
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

  // --------------------------------------------------------------------------
  // Determina qué acciones mostrar al usuario según su rol y estado del vehículo
  // --------------------------------------------------------------------------
  Widget _acciones(
    BuildContext context,
    Map<String, dynamic> v,
    bool esPropietario,
    bool vehiculoAprobado,
    String uid, {
    required bool needsReactivation,
  }) {
    final placa = (v['placa'] ?? '---').toString();

    // Acciones disponibles para el propietario del vehículo
    if (esPropietario && vehiculoAprobado) {
      if (needsReactivation) {
        return TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Reactivarme'),
          onPressed: () => _reactivarmeComoPropietario(
            context: context,
            idVehiculo: v['id'],
            uid: uid,
          ),
        );
      }

      return Wrap(
        spacing: 6,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text("Asignar"),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AsignarConductorScreen(
                    idVehiculo: v['id'],
                    placa: placa,
                  ),
                ),
              );
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.group),
            label: const Text("Gestionar"),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GestionConductoresScreen(
                    idVehiculo: v['id'],
                    placa: placa,
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

     // Opción para desasociarse (si el usuario es conductor asociado)
    if (!esPropietario && v['relacionId'] != null) {
      return TextButton.icon(
        icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
        label: const Text('Desasociarme'),
        onPressed: () => _desasociar(v['relacionId'], context),
      );
    }

    // En caso de que no existan acciones aplicables
    return const SizedBox.shrink();
  }
}

