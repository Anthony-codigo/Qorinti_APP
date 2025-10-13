// lib/pantallas/Admin/admin_empresas_screen.dart
// ============================================================================
// Archivo: admin_empresas_screen.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Pantalla administrativa para la gestión de empresas registradas en el sistema.
// Permite al administrador revisar, aprobar o rechazar solicitudes de empresas,
// así como visualizar los detalles completos de la empresa, su información legal,
// de contacto y sus miembros asociados.
//
// Integración
// -----------
// - Conecta con Firestore para leer las colecciones `empresa_solicitudes`,
//   `empresas`, y `usuario_empresa`.
// - Actualiza múltiples documentos de manera transaccional utilizando `WriteBatch`.
// - Usa `utils.dart` para el formateo de fechas.
// - Implementa confirmaciones modales, control de estado y filtros visuales.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_qorinti/modelos/utils.dart';

class AdminEmpresasScreen extends StatefulWidget {
  const AdminEmpresasScreen({super.key});

  @override
  State<AdminEmpresasScreen> createState() => _AdminEmpresasScreenState();
}

class _AdminEmpresasScreenState extends State<AdminEmpresasScreen> {
  String? _filtroEstado;
  final _busquedaCtrl = TextEditingController();
  bool _procesando = false;

  // Determina el color de estado visual según el estado de la empresa.
  Color _colorPorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case 'APROBADA':
      case 'ACTIVA':
        return Colors.green;
      case 'RECHAZADA':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  // Diálogo de confirmación genérico para cualquier acción administrativa.
  Future<void> _confirmarAccion(
    BuildContext context,
    String titulo,
    String mensaje,
    Future<void> Function() onConfirm,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aceptar')),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  // Actualiza el estado de una empresa y sus documentos relacionados.
  // Incluye:
  // - Actualización de `empresas`, `usuario_empresa` y `empresa_solicitudes`.
  // - Promoción del usuario creador a rol ADMIN si la empresa es aprobada.
  // - Manejo de estados 'PENDIENTE', 'APROBADA' y 'RECHAZADA'.
  Future<void> _cambiarEstadoEmpresa(
    BuildContext context, {
    required String idEmpresa,
    required String razon,
    required String usuarioEmpresaId,
    required String solicitudId,
    required String nuevoEstadoSolicitud,
  }) async {
    if (_procesando) return;
    setState(() => _procesando = true);

    final fs = FirebaseFirestore.instance;
    final batch = fs.batch();

    final empresaRef = fs.collection('empresas').doc(idEmpresa);
    final usuarioEmpresaRef = fs.collection('usuario_empresa').doc(usuarioEmpresaId);
    final solicitudRef = fs.collection('empresa_solicitudes').doc(solicitudId);
    final relRef = fs.collection('usuario_empresa');
    final ahora = FieldValue.serverTimestamp();

    final nuevoEstadoEmpresa =
        (nuevoEstadoSolicitud == 'APROBADA') ? 'ACTIVA' : 'RECHAZADA';
    final nuevoEstadoMembresia =
        (nuevoEstadoSolicitud == 'APROBADA') ? 'ACTIVO' : 'SUSPENDIDO';

    try {
      final empresaSnap = await empresaRef.get();
      final empresaActual = empresaSnap.data();
      final estadoAnterior = (empresaActual?['estado'] ?? '').toString();

      batch.update(empresaRef, {'estado': nuevoEstadoEmpresa, 'actualizadoEn': ahora});
      batch.update(usuarioEmpresaRef, {'estadoMembresia': nuevoEstadoMembresia, 'actualizadoEn': ahora});
      batch.update(solicitudRef, {'estado': nuevoEstadoSolicitud, 'actualizadoEn': ahora});

      await batch.commit();

      // Si la empresa se aprueba, asigna rol ADMIN al usuario asociado.
      if (nuevoEstadoSolicitud == 'APROBADA' && estadoAnterior != 'ACTIVA') {
        await relRef.doc(usuarioEmpresaId).update({
          'rol': 'ADMIN',
          'asignadoPor': 'SYSTEM',
          'actualizadoEn': ahora,
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Empresa $razon → $nuevoEstadoSolicitud")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _procesando = false);
    }
  }

  // Construcción de la interfaz principal con lista de solicitudes.
  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('empresa_solicitudes')
        .orderBy('creadoEn', descending: true);

    if (_filtroEstado != null) q = q.where('estado', isEqualTo: _filtroEstado);

    return Column(
      children: [
        _buildFiltros(context),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];
              final term = _busquedaCtrl.text.trim().toLowerCase();

              // Filtro por término de búsqueda (razón social o RUC).
              final filtrados = term.isEmpty
                  ? docs
                  : docs.where((d) {
                      final data = d.data();
                      final razon = (data['razonSocial'] ?? '').toString().toLowerCase();
                      final ruc = (data['idEmpresa'] ?? '').toString().toLowerCase();
                      return razon.contains(term) || ruc.contains(term);
                    }).toList();

              if (filtrados.isEmpty) return const Center(child: Text("No hay empresas."));

              // Renderizado de cada solicitud como tarjeta.
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: filtrados.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final doc = filtrados[i];
                  final data = doc.data();
                  final razon = (data['razonSocial'] ?? '---').toString();
                  final estado = (data['estado'] ?? 'PENDIENTE').toString();
                  final idEmpresa = (data['idEmpresa'] ?? '').toString();
                  final usuarioEmpresaId = (data['usuarioEmpresaId'] ?? '').toString();
                  final creadoEn = formatDate(dt(data['creadoEn']));
                  final logoUrl = (data['logoUrl'] ?? '').toString();

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _mostrarDetalleEmpresa(context, idEmpresa, razon),
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: logoUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  logoUrl,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Icon(Icons.business, color: _colorPorEstado(estado)),
                                ),
                              )
                            : CircleAvatar(
                                backgroundColor: _colorPorEstado(estado).withOpacity(0.15),
                                child: Icon(Icons.business, color: _colorPorEstado(estado)),
                              ),
                        title: Text(razon, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text("RUC: $idEmpresa\nFecha: $creadoEn"),
                        trailing: _accionesPorEstado(
                          context,
                          idEmpresa,
                          razon,
                          usuarioEmpresaId,
                          doc.id,
                          estado,
                        ),
                      ),
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

  // Construye los filtros superiores de estado y campo de búsqueda.
  Widget _buildFiltros(BuildContext context) {
    Widget chip(String? value, String label) {
      final selected = _filtroEstado == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filtroEstado = value),
        selectedColor: Theme.of(context).colorScheme.primary,
        labelStyle: TextStyle(color: selected ? Colors.white : null, fontWeight: FontWeight.w600),
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
          chip('APROBADA', 'Aprobadas'),
          chip('RECHAZADA', 'Rechazadas'),
          const SizedBox(width: 12),
          SizedBox(
            width: 250,
            child: TextField(
              controller: _busquedaCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar empresa o RUC',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _busquedaCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _busquedaCtrl.clear();
                          FocusScope.of(context).unfocus();
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

  // Muestra el detalle completo de la empresa seleccionada en un modal inferior.
  // Incluye información legal, de contacto y la lista de miembros vinculados.
  Future<void> _mostrarDetalleEmpresa(
      BuildContext context, String idEmpresa, String razon) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('empresas')
              .doc(idEmpresa)
              .get(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snap.hasError) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Error al cargar empresa')),
              );
            }

            final doc = snap.data;
            final data = doc?.data();
            if (doc == null || !doc.exists || data == null) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Empresa no encontrada')),
              );
            }

            final estado = (data['estado'] ?? 'PENDIENTE').toString();
            final colorEstado = _colorPorEstado(estado);
            final logoUrl = (data['logoUrl'] ?? '').toString();

            // Presentación visual de los datos principales de la empresa.
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (logoUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                logoUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: colorEstado.withOpacity(0.15),
                              child: Icon(Icons.business,
                                  color: colorEstado, size: 36),
                            ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              razon,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(estado),
                        backgroundColor: colorEstado.withOpacity(0.1),
                        labelStyle: TextStyle(
                            color: colorEstado, fontWeight: FontWeight.bold),
                      ),
                      const Divider(height: 24),
                      Text("📑 RUC: ${data['ruc'] ?? idEmpresa}",
                          style: const TextStyle(fontSize: 15)),
                      if (data['direccionFiscal'] != null)
                        Text("🏢 Dirección: ${data['direccionFiscal']}",
                            style: const TextStyle(fontSize: 15)),
                      if (data['emailFacturacion'] != null)
                        Text("✉️ Email: ${data['emailFacturacion']}",
                            style: const TextStyle(fontSize: 15)),
                      if (data['telefono'] != null)
                        Text("📞 Teléfono: ${data['telefono']}",
                            style: const TextStyle(fontSize: 15)),
                      if (data['giroNegocio'] != null)
                        Text("💼 Giro: ${data['giroNegocio']}",
                            style: const TextStyle(fontSize: 15)),
                      const Divider(height: 28),
                      const Text(
                        "Miembros de la Empresa",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      // Consulta en tiempo real de los usuarios vinculados a la empresa.
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('usuario_empresa')
                            .where('idEmpresa', isEqualTo: idEmpresa)
                            .snapshots(),
                        builder: (context, snapUe) {
                          if (snapUe.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (snapUe.hasError) {
                            return const Text(
                                "Error al cargar miembros de la empresa.");
                          }

                          final miembros = snapUe.data?.docs ?? [];
                          if (miembros.isEmpty) {
                            return const Text("No hay usuarios vinculados.");
                          }

                          return Column(
                            children: miembros.map((m) {
                              final u = m.data();
                              final idUsuario = (u['idUsuario'] ?? '').toString();

                              // Carga asincrónica del perfil de usuario vinculado.
                              return FutureBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>>(
                                future: FirebaseFirestore.instance
                                    .collection('usuarios')
                                    .doc(idUsuario)
                                    .get(),
                                builder: (context, userSnap) {
                                  if (userSnap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const ListTile(
                                      leading: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                      title: Text('Cargando usuario...'),
                                    );
                                  }
                                  if (userSnap.hasError) {
                                    return ListTile(
                                      leading: const Icon(Icons.error,
                                          color: Colors.red),
                                      title: const Text(
                                          'Error al cargar usuario'),
                                      subtitle: Text(idUsuario),
                                    );
                                  }

                                  final userDoc = userSnap.data;
                                  String nombre = 'Sin nombre';
                                  String correo = '';

                                  if (userDoc != null && userDoc.exists) {
                                    final ud = userDoc.data();
                                    if (ud != null) {
                                      nombre =
                                          (ud['nombre'] ?? 'Sin nombre').toString();
                                      correo = (ud['correo'] ?? '').toString();
                                    }
                                  }

                                  return ListTile(
                                    leading: Icon(
                                      u['rol'] == 'ADMIN'
                                          ? Icons.star
                                          : Icons.person,
                                      color: u['rol'] == 'ADMIN'
                                          ? Colors.amber
                                          : Colors.blueGrey,
                                    ),
                                    title: Text(nombre),
                                    subtitle: Text([
                                      if (correo.isNotEmpty) correo,
                                      'Rol: ${u['rol']}',
                                      'Estado: ${u['estadoMembresia']}',
                                    ].join(' | ')),
                                    isThreeLine: false,
                                  );
                                },
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Renderiza los botones de acción según el estado actual de la empresa.
  // PENDIENTE → Aprobar o Rechazar.
  // APROBADA/RECHAZADA → Revertir a estado pendiente.
  Widget _accionesPorEstado(
    BuildContext context,
    String idEmpresa,
    String razon,
    String usuarioEmpresaId,
    String solicitudId,
    String estado,
  ) {
    if (estado.toUpperCase() == 'PENDIENTE') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Aprobar empresa',
            icon: const Icon(Icons.check_circle, color: Colors.green),
            onPressed: _procesando
                ? null
                : () => _confirmarAccion(
                      context,
                      "Aprobar empresa",
                      "¿Deseas aprobar la empresa \"$razon\"?",
                      () => _cambiarEstadoEmpresa(
                        context,
                        idEmpresa: idEmpresa,
                        razon: razon,
                        usuarioEmpresaId: usuarioEmpresaId,
                        solicitudId: solicitudId,
                        nuevoEstadoSolicitud: 'APROBADA',
                      ),
                    ),
          ),
          IconButton(
            tooltip: 'Rechazar empresa',
            icon: const Icon(Icons.cancel, color: Colors.red),
            onPressed: _procesando
                ? null
                : () => _confirmarAccion(
                      context,
                      "Rechazar empresa",
                      "¿Rechazar la empresa \"$razon\"?",
                      () => _cambiarEstadoEmpresa(
                        context,
                        idEmpresa: idEmpresa,
                        razon: razon,
                        usuarioEmpresaId: usuarioEmpresaId,
                        solicitudId: solicitudId,
                        nuevoEstadoSolicitud: 'RECHAZADA',
                      ),
                    ),
          ),
        ],
      );
    } else {
      return TextButton.icon(
        icon: const Icon(Icons.refresh, color: Colors.orange),
        label: const Text('Revertir'),
        onPressed: _procesando
            ? null
            : () => _confirmarAccion(
                  context,
                  "Revertir empresa",
                  "¿Marcar la empresa \"$razon\" como pendiente nuevamente?",
                  () => _cambiarEstadoEmpresa(
                    context,
                    idEmpresa: idEmpresa,
                    razon: razon,
                    usuarioEmpresaId: usuarioEmpresaId,
                    solicitudId: solicitudId,
                    nuevoEstadoSolicitud: 'PENDIENTE',
                  ),
                ),
      );
    }
  }
}
