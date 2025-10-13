// lib/pantallas/admin/admin_vehiculos_screen.dart
// ============================================================================
// Pantalla: AdminVehiculosScreen
// Proyecto: Qorinti App – Módulo Administrador
// ----------------------------------------------------------------------------
// Descripción general:
// Esta pantalla permite al administrador visualizar, filtrar y gestionar los
// registros de vehículos registrados por los conductores dentro del sistema.
//
// Funcionalidades principales:
//  - Listar vehículos almacenados en Firestore (colección 'vehiculos').
//  - Filtrar por estado (Pendiente, Aprobado, Rechazado).
//  - Buscar por placa, marca, modelo o propietario.
//  - Aprobar, rechazar o revertir estado de vehículos.
//  - Al aprobar un vehículo, crea o activa la relación con el conductor
//    (colección 'conductor_vehiculo') si aún no existe.
// ----------------------------------------------------------------------------
// Tecnologías utilizadas:
//  - Flutter Material (UI).
//  - Cloud Firestore (Firebase) para los datos.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminVehiculosScreen extends StatefulWidget {
  const AdminVehiculosScreen({super.key});

  @override
  State<AdminVehiculosScreen> createState() => _AdminVehiculosScreenState();
}

class _AdminVehiculosScreenState extends State<AdminVehiculosScreen> {
  // Estado seleccionado en los filtros (Pendiente, Aprobado, Rechazado)
  String? _filtroEstado;

  // Controlador de texto para la barra de búsqueda
  final _busquedaCtrl = TextEditingController();

  // Cache local para evitar múltiples lecturas de nombres de usuarios
  final Map<String, String> _nombreCache = {};

  // --------------------------------------------------------------------------
  // FUNCIONES AUXILIARES
  // --------------------------------------------------------------------------

  // Retorna un color representativo según el estado del vehículo
  Color _colorPorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case 'APROBADO':
        return Colors.green;
      case 'RECHAZADO':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  // Muestra un cuadro de diálogo de confirmación antes de ejecutar una acción
  Future<void> _confirmarAccion(
    BuildContext context,
    String mensaje,
    Future<void> Function() onConfirm,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar acción'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  // --------------------------------------------------------------------------
  // CAMBIO DE ESTADO DE VEHÍCULO EN FIRESTORE
  // --------------------------------------------------------------------------

  Future<void> _cambiarEstadoVehiculo(
    BuildContext context, {
    required String idVehiculo,
    required String nuevoEstado,
  }) async {
    final fs = FirebaseFirestore.instance;
    final vehiculoRef = fs.collection('vehiculos').doc(idVehiculo);
    final relRef = fs.collection('conductor_vehiculo');

    try {
      final snap = await vehiculoRef.get();
      if (!snap.exists) {
        throw 'Vehículo no encontrado';
      }

      final v = snap.data() as Map<String, dynamic>;
      final idPropietario = (v['idPropietarioUsuario'] ?? '').toString();
      final estadoActual = (v['estado'] ?? '').toString();

      // Actualiza el estado principal del vehículo
      await vehiculoRef.update({
        'estado': nuevoEstado,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // Si se aprueba un vehículo nuevo, crea el vínculo con su conductor
      if (nuevoEstado == 'APROBADO' &&
          estadoActual != 'APROBADO' &&
          idPropietario.isNotEmpty) {
        final existe = await relRef
            .where('idConductor', isEqualTo: idPropietario)
            .where('idVehiculo', isEqualTo: idVehiculo)
            .where('activo', isEqualTo: true)
            .limit(1)
            .get();

        // Si no existe el vínculo, se registra uno nuevo
        if (existe.docs.isEmpty) {
          final ahora = FieldValue.serverTimestamp();
          await relRef.add({
            'idConductor': idPropietario,
            'idVehiculo': idVehiculo,
            'rolAsignacion': 'PROPIETARIO',
            'estadoVinculo': 'APROBADO',
            'estado': 'APROBADO',
            'activo': true,
            'fechaInicio': ahora,
            'creadoEn': ahora,
            'actualizadoEn': ahora,
          });
        }
      }

      // Muestra confirmación visual
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Vehículo $nuevoEstado")),
        );
      }
    } catch (e) {
      // Muestra error en caso de fallo
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Obtiene el nombre del usuario desde su UID, usando cache para rendimiento
  Future<String> _getNombreUsuario(String uid) async {
    if (uid.isEmpty) return '-';
    if (_nombreCache.containsKey(uid)) return _nombreCache[uid]!;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        final nombre = (data['nombre'] ?? '').toString().trim();
        final correo = (data['correo'] ?? '').toString().trim();
        final res = nombre.isNotEmpty ? nombre : (correo.isNotEmpty ? correo : uid);
        _nombreCache[uid] = res;
        return res;
      }
    } catch (_) {}
    _nombreCache[uid] = uid;
    return uid;
  }

  // --------------------------------------------------------------------------
  // INTERFAZ PRINCIPAL
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Consulta base a la colección de vehículos
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('vehiculos')
        .orderBy('creadoEn', descending: true);

    // Filtro por estado
    if (_filtroEstado != null) {
      q = q.where('estado', isEqualTo: _filtroEstado);
    }

    return Column(
      children: [
        _buildFiltros(context), // Sección de filtros superiores
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];
              final term = _busquedaCtrl.text.trim().toLowerCase();

              // Filtro local por texto (placa, marca, modelo o propietario)
              final filtrados = term.isEmpty
                  ? docs
                  : docs.where((d) {
                      final v = d.data();
                      final placa = (v['placa'] ?? '').toString().toLowerCase();
                      final marca = (v['marca'] ?? '').toString().toLowerCase();
                      final modelo = (v['modelo'] ?? '').toString().toLowerCase();
                      final prop = (v['idPropietarioUsuario'] ?? '').toString().toLowerCase();
                      return placa.contains(term) ||
                          marca.contains(term) ||
                          modelo.contains(term) ||
                          prop.contains(term);
                    }).toList();

              if (filtrados.isEmpty) {
                return const Center(child: Text("No hay vehículos para mostrar."));
              }

              // Lista principal de vehículos
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: filtrados.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = filtrados[i];
                  final v = d.data();
                  final placa = (v['placa'] ?? '-').toString();
                  final marca = (v['marca'] ?? '-').toString();
                  final modelo = (v['modelo'] ?? '-').toString();
                  final propietarioUid = (v['idPropietarioUsuario'] ?? '').toString();
                  final estado = (v['estado'] ?? 'PENDIENTE').toString();

                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _colorPorEstado(estado).withOpacity(0.15),
                        child: Icon(Icons.directions_car, color: _colorPorEstado(estado)),
                      ),
                      title: Text("Placa: $placa",
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Marca: $marca • Modelo: $modelo"),
                          const SizedBox(height: 2),
                          // Muestra el propietario con su nombre obtenido desde Firestore
                          FutureBuilder<String>(
                            future: _getNombreUsuario(propietarioUid),
                            builder: (context, snapNombre) {
                              final nombre = snapNombre.data ??
                                  (propietarioUid.isNotEmpty ? propietarioUid : '-');
                              return Text(
                                "Propietario: $nombre",
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                              );
                            },
                          ),
                        ],
                      ),
                      trailing: _accionesPorEstado(context, d.id, estado, placa),
                      isThreeLine: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // FILTROS Y BÚSQUEDA
  // --------------------------------------------------------------------------

  Widget _buildFiltros(BuildContext context) {
    // Crea un chip de filtro (selector)
    Widget chip(String? value, String label) {
      final selected = _filtroEstado == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filtroEstado = value),
        selectedColor: Theme.of(context).colorScheme.primary,
        labelStyle: TextStyle(
          color: selected ? Colors.white : null,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Estado:', style: TextStyle(fontWeight: FontWeight.bold)),
          chip(null, 'Todos'),
          chip('PENDIENTE', 'Pendientes'),
          chip('APROBADO', 'Aprobados'),
          chip('RECHAZADO', 'Rechazados'),
          const SizedBox(width: 12),
          // Campo de búsqueda
          SizedBox(
            width: 250,
            child: TextField(
              controller: _busquedaCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar placa, marca, modelo o propietario',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _busquedaCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _busquedaCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // BOTONES DE ACCIÓN POR ESTADO
  // --------------------------------------------------------------------------

  Widget _accionesPorEstado(
    BuildContext context,
    String docId,
    String estado,
    String placa,
  ) {
    // Si el vehículo está pendiente, permite aprobar o rechazar
    if (estado == 'PENDIENTE') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Aprobar',
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: () => _confirmarAccion(
              context,
              "¿Aprobar el vehículo $placa?",
              () => _cambiarEstadoVehiculo(context, idVehiculo: docId, nuevoEstado: 'APROBADO'),
            ),
          ),
          IconButton(
            tooltip: 'Rechazar',
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => _confirmarAccion(
              context,
              "¿Rechazar el vehículo $placa?",
              () => _cambiarEstadoVehiculo(context, idVehiculo: docId, nuevoEstado: 'RECHAZADO'),
            ),
          ),
        ],
      );
    } else {
      // Si ya está aprobado o rechazado, muestra opción para revertir
      return TextButton(
        onPressed: () => _confirmarAccion(
          context,
          "¿Marcar el vehículo $placa como PENDIENTE?",
          () => _cambiarEstadoVehiculo(context, idVehiculo: docId, nuevoEstado: 'PENDIENTE'),
        ),
        child: const Text('Revertir'),
      );
    }
  }
}
