// lib/pantallas/vehiculos/asignar_conductor_screen.dart
// -----------------------------------------------------------------------------
// Pantalla para que el propietario de un vehículo invite/asigne a un conductor.
// Flujo:
// 1) Valida formulario (correo).
// 2) Verifica que el vehículo exista, sea del usuario actual y esté APROBADO.
// 3) Busca al usuario por correo y confirma que sea CONDUCTOR APROBADO.
// 4) Revisa si ya existe relación conductor_vehiculo; si existe, la re-activa
//    como PENDIENTE; si no, crea una nueva invitación.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_qorinti/modelos/conductor_vehiculo.dart';

class AsignarConductorScreen extends StatefulWidget {
  final String idVehiculo; // ID del vehículo a gestionar
  final String placa;      // Placa para mostrar en el título

  const AsignarConductorScreen({
    super.key,
    required this.idVehiculo,
    required this.placa,
  });

  @override
  State<AsignarConductorScreen> createState() =>
      _AsignarConductorScreenState();
}

class _AsignarConductorScreenState extends State<AsignarConductorScreen> {
  final _formKey = GlobalKey<FormState>();   // Clave del formulario
  final _correoCtrl = TextEditingController(); // Entrada de correo
  bool _loading = false;                       // Spinner de envío

  @override
  void dispose() {
    _correoCtrl.dispose();
    super.dispose();
  }

  // Lógica principal de asignación/invitación
  Future<void> _asignarConductor() async {
    if (!_formKey.currentState!.validate()) return;

    final correo = _correoCtrl.text.trim().toLowerCase();
    setState(() => _loading = true);

    try {
      final uidPropietario = FirebaseAuth.instance.currentUser!.uid;
      final fs = FirebaseFirestore.instance;

      // 1) Verificar vehículo y permisos del usuario actual
      final vehDoc = await fs.collection('vehiculos').doc(widget.idVehiculo).get();
      if (!vehDoc.exists) {
        _snack("El vehículo no existe.", isErr: true);
        return;
      }
      final Map<String, dynamic> veh = vehDoc.data()!;
      if ((veh['idPropietarioUsuario'] ?? '') != uidPropietario) {
        _snack("No tienes permisos para gestionar este vehículo.", isErr: true);
        return;
      }
      final estadoVeh = (veh['estado'] ?? 'PENDIENTE').toString().toUpperCase();
      if (estadoVeh != 'APROBADO') {
        _snack("Tu vehículo aún no está aprobado por el administrador.", isErr: true);
        return;
      }

      // 2) Buscar usuario por correo
      final userSnap = await fs
          .collection('usuarios')
          .where('correo', isEqualTo: correo) // índice recomendado
          .limit(1)
          .get();

      if (userSnap.docs.isEmpty) {
        _snack("No se encontró un usuario con ese correo.", isErr: true);
        return;
      }
      final idConductor = userSnap.docs.first.id;

      // Evitar auto-asignación
      if (idConductor == uidPropietario) {
        _snack("No puedes asignarte a ti mismo.", isErr: true);
        return;
      }

      // 3) Validar que el usuario sea CONDUCTOR APROBADO
      final conductorDoc = await fs.collection('conductores').doc(idConductor).get();
      if (!conductorDoc.exists) {
        _snack("Ese usuario no está registrado como conductor.", isErr: true);
        return;
      }
      final conductor = conductorDoc.data() as Map<String, dynamic>;
      final estadoConductor =
          (conductor['estado'] ?? conductor['estadoOperativo'] ?? 'PENDIENTE')
              .toString()
              .toUpperCase();
      if (estadoConductor != 'APROBADO') {
        _snack("Ese conductor aún no está APROBADO. Debe ser validado.", isErr: true);
        return;
      }

      // 4) Revisar si ya existe la relación conductor_vehiculo
      final relSnap = await fs
          .collection('conductor_vehiculo')
          .where('idConductor', isEqualTo: idConductor)
          .where('idVehiculo', isEqualTo: widget.idVehiculo)
          .limit(1)
          .get();

      if (relSnap.docs.isNotEmpty) {
        // Si ya existe, se decide según estado si se reenvía invitación o se informa
        final relDoc = relSnap.docs.first;
        final rel = ConductorVehiculo.fromMap(relDoc.data(), id: relDoc.id);

        // Compatibilidad con campos antiguos: usa estadoVinculo, cae a 'estado' si no está
        final estadoV = rel.estadoVinculo.toUpperCase().isNotEmpty
            ? rel.estadoVinculo.toUpperCase()
            : ((rel.toMap()['estado'] ?? '') as String).toUpperCase();

        if (estadoV == 'APROBADO' || estadoV == 'PENDIENTE') {
          _snack(
            "Ese conductor ya está ${estadoV == 'APROBADO' ? 'asociado' : 'pendiente'} a este vehículo.",
          );
          return;
        }

        // Re-activar invitación existente (regresa a PENDIENTE)
        await relDoc.reference.update({
          'estadoVinculo': 'PENDIENTE',
          'estado': 'PENDIENTE', // compat
          'activo': false,
          'rolAsignacion': 'ASOCIADO',
          'invitadoPor': uidPropietario,
          'fechaInicio': null,
          'actualizadoEn': FieldValue.serverTimestamp(),
        });

        _snack(
          "Invitación reenviada. El conductor debe aceptarla en 'Invitaciones de Vehículo'.",
        );
        if (mounted) Navigator.pop(context);
        return;
      }

      // 5) Crear invitación nueva
      final relacion = ConductorVehiculo(
        idConductor: idConductor,
        idVehiculo: widget.idVehiculo,
        estadoVinculo: 'PENDIENTE',
        activo: false,
        observaciones: null,
      );

      final data = {
        ...relacion.toMap(),
        'estado': 'PENDIENTE',       // compat con campo antiguo
        'rolAsignacion': 'ASOCIADO', // rol de quien se invita
        'invitadoPor': uidPropietario,
        'fechaInicio': null,
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      };

      await fs.collection('conductor_vehiculo').add(data);

      _snack(
        "Invitación enviada. El conductor debe aceptarla en 'Invitaciones de Vehículo'.",
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack("Error: $e", isErr: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Helper para mostrar SnackBars
  void _snack(String msg, {bool isErr = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isErr ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Asignar Conductor • ${widget.placa}")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Instrucciones
              const Text(
                "Ingresa el correo del conductor. Debe estar registrado y APROBADO como conductor.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Campo de correo del conductor
              TextFormField(
                controller: _correoCtrl,
                decoration: const InputDecoration(
                  labelText: "Correo del conductor",
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return "Ingresa un correo";
                  final email = v.trim();
                  if (!email.contains('@') || !email.contains('.')) {
                    return "Correo no válido";
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _loading ? null : _asignarConductor(),
              ),
              const SizedBox(height: 20),

              // Botón de acción
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: _loading
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Invitar Conductor"),
                  onPressed: _loading ? null : _asignarConductor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
