// lib/pantallas/empresa/empresa_miembros_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: EmpresaMiembrosScreen
// Descripción general:
//   Permite al administrador o responsable de una empresa gestionar los
//   miembros asociados a ella, incluyendo:
//     - Ver el listado de miembros con filtros por estado y búsqueda.
//     - Cambiar roles (ADMIN ↔ MIEMBRO).
//     - Cambiar estados de membresía (PENDIENTE, ACTIVO, SUSPENDIDO, BAJA).
//     - Aprobar o rechazar solicitudes pendientes.
//     - Eliminar definitivamente un vínculo usuario-empresa.
//   Esta pantalla consulta y modifica las colecciones Firestore:
//     • usuario_empresa
//     • usuarios
//     • empresa_solicitudes
//
//   Incluye controles de seguridad para evitar dejar a la empresa sin
//   administradores activos, así como validaciones visuales y modales
//   de confirmación.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:app_qorinti/modelos/usuario_empresa.dart';

class EmpresaMiembrosScreen extends StatefulWidget {
  final String idEmpresa; // Identificador único de la empresa
  const EmpresaMiembrosScreen({super.key, required this.idEmpresa});

  @override
  State<EmpresaMiembrosScreen> createState() => _EmpresaMiembrosScreenState();
}

class _EmpresaMiembrosScreenState extends State<EmpresaMiembrosScreen> {
  // Estado seleccionado en filtro ("TODOS", "PENDIENTE", etc.)
  String _filtroEstado = "TODOS";

  // Controlador para el cuadro de búsqueda
  final _busquedaCtrl = TextEditingController();

  // Bandera para evitar múltiples operaciones simultáneas
  bool _operando = false;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Colores representativos según el estado de membresía
  // --------------------------------------------------------------------------
  Color _colorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case "ACTIVO":
        return Colors.green;
      case "PENDIENTE":
        return Colors.orange;
      case "SUSPENDIDO":
        return Colors.red;
      case "BAJA":
      case "INACTIVA":
        return Colors.grey;
      default:
        return Colors.black54;
    }
  }

  // --------------------------------------------------------------------------
  // Ventana de confirmación genérica (AlertDialog)
  // --------------------------------------------------------------------------
  Future<bool> _confirmar(
    String titulo,
    String mensaje, {
    String ok = 'Aceptar',
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(titulo),
            content: Text(mensaje),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancelar"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ok),
              ),
            ],
          ),
        ) ??
        false;
  }

  // --------------------------------------------------------------------------
  // Solicita un texto opcional (motivo) para acciones como rechazos
  // --------------------------------------------------------------------------
  Future<String?> _pedirMotivo({String title = 'Motivo (opcional)'}) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Escribe un motivo si deseas',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (ok == true) return ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
    return null;
  }

  // --------------------------------------------------------------------------
  // Verifica si un usuario es el último administrador de una empresa
  // --------------------------------------------------------------------------
  Future<bool> _esUltimoAdmin(String idEmpresa, {String? excluirDocId}) async {
    final admins = await FirebaseFirestore.instance
        .collection('usuario_empresa')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('rol', isEqualTo: 'ADMIN')
        .get();

    if (excluirDocId != null) {
      final restantes = admins.docs.where((d) => d.id != excluirDocId).length;
      return restantes == 0;
    }
    return admins.docs.length <= 1;
  }

  // --------------------------------------------------------------------------
  // Cierra solicitudes pendientes asociadas a un usuario-empresa específico
  // --------------------------------------------------------------------------
  Future<void> _cerrarSolicitudesPendientes(
    String usuarioEmpresaId,
    String nuevoEstado, {
    String? motivo,
  }) async {
    final col = FirebaseFirestore.instance.collection('empresa_solicitudes');
    final qs = await col
        .where('usuarioEmpresaId', isEqualTo: usuarioEmpresaId)
        .where('estado', isEqualTo: 'PENDIENTE')
        .get();

    if (qs.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final d in qs.docs) {
      batch.update(d.reference, {
        'estado': nuevoEstado,
        if (motivo != null) 'motivo': motivo,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // --------------------------------------------------------------------------
  // Cambiar el estado de membresía (ej. ACTIVO, SUSPENDIDO, BAJA)
  // Incluye validación para no suspender al único ADMIN.
  // --------------------------------------------------------------------------
  Future<void> _cambiarEstado({
    required String docId,
    required String nuevoEstado,
    required String idEmpresa,
    required String rolActual,
  }) async {
    if (_operando) return;
    final nuevo = nuevoEstado.toUpperCase();

    // Bloquea suspensión o baja si es el último administrador
    if (rolActual.toUpperCase() == 'ADMIN' && (nuevo == 'SUSPENDIDO' || nuevo == 'BAJA')) {
      final esUltimo = await _esUltimoAdmin(idEmpresa, excluirDocId: docId);
      if (esUltimo) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No puedes suspender o dar de baja al único ADMIN. Asigna otro ADMIN primero.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final ok = await _confirmar("Cambiar estado", "¿Cambiar estado a $nuevo?");
    if (!ok) return;

    setState(() => _operando = true);
    try {
      await FirebaseFirestore.instance.collection('usuario_empresa').doc(docId).update({
        'estadoMembresia': nuevo,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estado actualizado a $nuevo')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar estado: $e')),
      );
    } finally {
      setState(() => _operando = false);
    }
  }

  // --------------------------------------------------------------------------
  // Aprobar una solicitud pendiente (activa el vínculo usuario-empresa)
  // --------------------------------------------------------------------------
  Future<void> _aprobarSolicitud(UsuarioEmpresa m) async {
    if (_operando) return;
    final ok = await _confirmar('Aprobar solicitud', '¿Aprobar a este miembro?');
    if (!ok) return;

    setState(() => _operando = true);
    try {
      await FirebaseFirestore.instance.collection('usuario_empresa').doc(m.id!).update({
        'estadoMembresia': 'ACTIVO',
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      await _cerrarSolicitudesPendientes(m.id!, 'APROBADA');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud aprobada ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _operando = false);
    }
  }

  // --------------------------------------------------------------------------
  // Rechazar una solicitud pendiente con motivo opcional
  // --------------------------------------------------------------------------
  Future<void> _rechazarSolicitud(UsuarioEmpresa m) async {
    if (_operando) return;

    final ok = await _confirmar('Rechazar solicitud', '¿Rechazar esta solicitud?');
    if (!ok) return;

    final motivo = await _pedirMotivo(title: 'Motivo de rechazo (opcional)');
    setState(() => _operando = true);

    try {
      final docRef = FirebaseFirestore.instance.collection('usuario_empresa').doc(m.id!);
      await docRef.update({
        'estadoMembresia': 'BAJA',
        if (motivo != null) 'motivoRechazo': motivo,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      await _cerrarSolicitudesPendientes(m.id!, 'RECHAZADA', motivo: motivo);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud rechazada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _operando = false);
    }
  }

  // --------------------------------------------------------------------------
  // Cambio de rol (ADMIN ↔ MIEMBRO)
  // Incluye validación para no dejar la empresa sin administrador.
  // --------------------------------------------------------------------------
  Future<void> _cambiarRol({
    required String docId,
    required String nuevoRol,
    required String idEmpresa,
  }) async {
    if (_operando) return;
    final rolUp = nuevoRol.toUpperCase();

    // Si se va a quitar el rol ADMIN, validar que no sea el último
    final doc = await FirebaseFirestore.instance.collection('usuario_empresa').doc(docId).get();
    final actualRol = (doc.data()?['rol'] ?? '').toString().toUpperCase();
    if (actualRol == 'ADMIN' && rolUp != 'ADMIN') {
      final esUltimo = await _esUltimoAdmin(idEmpresa, excluirDocId: docId);
      if (esUltimo) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No puedes quitar el último ADMIN. Asigna otro ADMIN primero.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final ok = await _confirmar("Cambiar rol", "¿Cambiar rol a $rolUp?");
    if (!ok) return;

    setState(() => _operando = true);
    try {
      await FirebaseFirestore.instance.collection('usuario_empresa').doc(docId).update({
        'rol': rolUp,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rol actualizado a $rolUp')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar rol: $e')),
      );
    } finally {
      setState(() => _operando = false);
    }
  }
  // --------------------------------------------------------------------------
  // Eliminar DEFINITIVAMENTE el vínculo usuario-empresa
  // Se ejecuta solo con confirmación explícita.
  // --------------------------------------------------------------------------
  Future<void> _eliminarDefinitivo({
    required String docId,
    required String idEmpresa,
    required String rol,
  }) async {
    if (_operando) return;

    // Previene eliminar al único administrador activo
    if (rol.toUpperCase() == 'ADMIN') {
      final esUltimo = await _esUltimoAdmin(idEmpresa, excluirDocId: docId);
      if (esUltimo) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No puedes eliminar al único ADMIN. Asigna otro ADMIN primero.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final ok = await _confirmar(
      "Eliminar definitivamente",
      "Esta acción quitará por completo el acceso. ¿Deseas continuar?",
      ok: 'Eliminar',
    );
    if (!ok) return;

    setState(() => _operando = true);
    try {
      await FirebaseFirestore.instance.collection('usuario_empresa').doc(docId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Miembro eliminado definitivamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: $e')),
      );
    } finally {
      setState(() => _operando = false);
    }
  }

  // --------------------------------------------------------------------------
  // Construcción visual principal de la pantalla
  // Contiene: filtros, campo de búsqueda y lista dinámica de miembros.
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final idEmpresa = widget.idEmpresa.trim();

    return Scaffold(
      appBar: AppBar(title: const Text("Gestionar miembros")),
      body: Column(
        children: [
          // --------------------------------------------------------------
          // Encabezado con filtros por estado y búsqueda por texto
          // --------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Estado: "),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _filtroEstado,
                      items: const [
                        DropdownMenuItem(value: "TODOS", child: Text("Todos")),
                        DropdownMenuItem(value: "PENDIENTE", child: Text("Pendientes")),
                        DropdownMenuItem(value: "ACTIVO", child: Text("Activos")),
                        DropdownMenuItem(value: "SUSPENDIDO", child: Text("Suspendidos")),
                        DropdownMenuItem(value: "BAJA", child: Text("Dados de baja")),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _filtroEstado = value);
                      },
                    ),
                  ],
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _busquedaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre, correo o UID',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: (_busquedaCtrl.text.isNotEmpty)
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
          ),

          // --------------------------------------------------------------
          // Contenedor principal con listado de miembros
          // Se alimenta mediante StreamBuilder de Firestore
          // --------------------------------------------------------------
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuario_empresa')
                  .where('idEmpresa', isEqualTo: idEmpresa)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text("No hay miembros registrados."));
                }

                // Conversión a modelo de datos UsuarioEmpresa
                var miembros = snap.data!.docs
                    .map((doc) => UsuarioEmpresa.fromMap(doc.data(), id: doc.id))
                    .toList();

                // Filtro según estado seleccionado
                if (_filtroEstado != "TODOS") {
                  miembros = miembros
                      .where((m) => m.estadoMembresia.toUpperCase() == _filtroEstado.toUpperCase())
                      .toList();
                }

                // Orden de visualización: PENDIENTE → ACTIVO → SUSPENDIDO → BAJA
                // Dentro de un mismo estado, los ADMIN aparecen primero.
                miembros.sort((a, b) {
                  const orden = {"PENDIENTE": 0, "ACTIVO": 1, "SUSPENDIDO": 2, "BAJA": 3};
                  final ai = orden[a.estadoMembresia.toUpperCase()] ?? 99;
                  final bi = orden[b.estadoMembresia.toUpperCase()] ?? 99;
                  if (ai != bi) return ai.compareTo(bi);
                  if (a.rol == 'ADMIN' && b.rol != 'ADMIN') return -1;
                  if (a.rol != 'ADMIN' && b.rol == 'ADMIN') return 1;
                  return (a.creadoEn ?? DateTime(2000)).compareTo(b.creadoEn ?? DateTime(2000));
                });

                if (miembros.isEmpty) {
                  return Center(child: Text("No hay miembros con estado $_filtroEstado"));
                }

                // Término de búsqueda actual
                final term = _busquedaCtrl.text.trim().toLowerCase();

                // ----------------------------------------------------------
                // Renderizado de cada miembro en la lista
                // ----------------------------------------------------------
                return ListView.builder(
                  itemCount: miembros.length,
                  itemBuilder: (context, i) {
                    final m = miembros[i];

                    // Subconsulta del usuario (datos básicos)
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('usuarios')
                          .doc(m.idUsuario)
                          .snapshots(),
                      builder: (context, userSnap) {
                        final userData = userSnap.data?.data() ?? {};
                        final nombre = (userData['nombre'] ?? '').toString();
                        final correo = (userData['correo'] ?? '').toString();
                        final fotoUrl = (userData['fotoUrl'] ?? '').toString();

                        // Filtro de texto aplicado localmente
                        if (term.isNotEmpty) {
                          final base = '$nombre $correo ${m.idUsuario}'.toLowerCase();
                          if (!base.contains(term)) return const SizedBox.shrink();
                        }

                        // Formateo de fecha de registro
                        String fechaRegistro = "";
                        if (m.creadoEn != null) {
                          fechaRegistro = DateFormat('dd/MM/yyyy HH:mm').format(m.creadoEn!);
                        }

                        final estadoColor = _colorEstado(m.estadoMembresia.toUpperCase());
                        final esPendiente = m.estadoMembresia.toUpperCase() == 'PENDIENTE';

                        // --------------------------------------------------
                        // Tarjeta visual de cada miembro con menú contextual
                        // --------------------------------------------------
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage: (fotoUrl.isNotEmpty) ? NetworkImage(fotoUrl) : null,
                              child: (fotoUrl.isEmpty)
                                  ? Text(
                                      (nombre.isNotEmpty
                                              ? nombre[0]
                                              : (correo.isNotEmpty ? correo[0] : '?'))
                                          .toUpperCase(),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Expanded(child: Text(nombre.isNotEmpty ? nombre : 'Sin nombre')),
                                if (m.rol == 'ADMIN')
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(Icons.star, color: Colors.amber, size: 18),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (correo.isNotEmpty) Text(correo),
                                const SizedBox(height: 4),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  children: [
                                    Text("Rol: ${m.rol}"),
                                    Chip(
                                      label: Text(m.estadoMembresia),
                                      backgroundColor: estadoColor.withOpacity(0.2),
                                      labelStyle: TextStyle(color: estadoColor),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                if (fechaRegistro.isNotEmpty) Text("Registrado: $fechaRegistro"),
                              ],
                            ),
                            isThreeLine: true,

                            // ------------------------------------------------
                            // Menú de acciones por miembro
                            // ------------------------------------------------
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Acciones',
                              onSelected: (accion) async {
                                if (_operando) return;
                                switch (accion) {
                                  case "APROBAR":
                                    await _aprobarSolicitud(m);
                                    break;
                                  case "RECHAZAR":
                                    await _rechazarSolicitud(m);
                                    break;
                                  case "ADMIN":
                                  case "MIEMBRO":
                                    await _cambiarRol(
                                      docId: m.id!,
                                      nuevoRol: accion,
                                      idEmpresa: idEmpresa,
                                    );
                                    break;
                                  case "ACTIVO":
                                  case "SUSPENDIDO":
                                  case "BAJA":
                                    await _cambiarEstado(
                                      docId: m.id!,
                                      nuevoEstado: accion,
                                      idEmpresa: idEmpresa,
                                      rolActual: m.rol,
                                    );
                                    break;
                                  case "ELIMINAR":
                                    await _eliminarDefinitivo(
                                      docId: m.id!,
                                      idEmpresa: idEmpresa,
                                      rol: m.rol,
                                    );
                                    break;
                                }
                              },

                              // Generación dinámica del contenido del menú contextual
                              itemBuilder: (context) {
                                final items = <PopupMenuEntry<String>>[];

                                // Si el miembro está pendiente → solo aprobar o rechazar
                                if (esPendiente) {
                                  items.addAll(const [
                                    PopupMenuItem(value: "APROBAR", child: Text("Aprobar")),
                                    PopupMenuItem(value: "RECHAZAR", child: Text("Rechazar solicitud")),
                                  ]);
                                  return items;
                                }

                                // Opciones de cambio de rol
                                if (m.rol.toUpperCase() == "ADMIN") {
                                  items.add(const PopupMenuItem(value: "MIEMBRO", child: Text("Hacer MIEMBRO")));
                                } else {
                                  items.add(const PopupMenuItem(value: "ADMIN", child: Text("Hacer ADMIN")));
                                }
                                items.add(const PopupMenuDivider());

                                // Cambios de estado de membresía
                                if (m.estadoMembresia.toUpperCase() != "ACTIVO") {
                                  items.add(const PopupMenuItem(value: "ACTIVO", child: Text("Activar")));
                                }
                                if (m.estadoMembresia.toUpperCase() != "SUSPENDIDO") {
                                  items.add(const PopupMenuItem(value: "SUSPENDIDO", child: Text("Suspender")));
                                }
                                if (m.estadoMembresia.toUpperCase() != "BAJA") {
                                  items.add(const PopupMenuItem(value: "BAJA", child: Text("Dar de baja")));
                                }

                                items.add(const PopupMenuDivider());

                                // Opción de eliminación definitiva
                                items.add(const PopupMenuItem(
                                  value: "ELIMINAR",
                                  child: Text("Eliminar definitivamente", style: TextStyle(color: Colors.red)),
                                ));

                                return items;
                              },
                              child: const Icon(Icons.more_vert),
                            ),
                          ),
                        );
                      },
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
}
