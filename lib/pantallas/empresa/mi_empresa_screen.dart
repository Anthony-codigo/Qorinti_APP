// lib/pantallas/empresa/mi_empresa_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: MiEmpresaScreen
// Descripción general:
//   Muestra la información detallada de la empresa a la que el usuario actual
//   pertenece, incluyendo datos fiscales, de contacto, y su rol dentro de ella.
//   Además, permite:
//
//   - Consultar el vínculo activo entre usuario y empresa.
//   - Cambiar la preferencia para usar datos de empresa como emisor de comprobantes.
//   - Visualizar miembros asociados (si el usuario tiene permisos de gestión).
//   - Salir voluntariamente de la empresa (si no es el último administrador).
//
//   Esta pantalla consolida la información de tres colecciones principales:
//     • `empresas` — Datos de la empresa.
//     • `usuario_empresa` — Vínculo usuario ↔ empresa.
//     • `usuarios` — Datos del perfil del usuario.
//
//   También usa el helper `PermisosEmpresa` para determinar si el usuario puede
//   gestionar miembros.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:app_qorinti/modelos/usuario_empresa.dart';
import 'package:app_qorinti/utils/permisos_empresa.dart';
import 'package:app_qorinti/app_router.dart';

class MiEmpresaScreen extends StatelessWidget {
  static const route = '/empresa/mia';
  const MiEmpresaScreen({super.key});

  // --------------------------------------------------------------------------
  // Determina el color del chip según el estado de membresía
  // --------------------------------------------------------------------------
  Color _colorEstadoChip(String estadoUpper) {
    switch (estadoUpper) {
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
  // Obtiene el nombre legible del usuario desde la colección `usuarios`
  // Si no hay nombre, devuelve el correo o el UID como fallback.
  // --------------------------------------------------------------------------
  Future<String> _getNombreUsuario(String uid) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        final nombre = (data['nombre'] ?? '').toString().trim();
        final correo = (data['correo'] ?? '').toString().trim();
        if (nombre.isNotEmpty) return nombre;
        if (correo.isNotEmpty) return correo;
      }
      return uid;
    } catch (_) {
      return uid;
    }
  }

  // --------------------------------------------------------------------------
  // Devuelve un stream del vínculo principal (usuario_empresa) del usuario.
  // Filtra solo estados activos o pendientes y prioriza el más actualizado.
  // --------------------------------------------------------------------------
  Stream<UsuarioEmpresa?> _streamVinculoPrincipal(String uid) {
    return FirebaseFirestore.instance
        .collection('usuario_empresa')
        .where('idUsuario', isEqualTo: uid)
        .snapshots()
        .map((qs) {
      if (qs.docs.isEmpty) return null;

      final todos =
          qs.docs.map((d) => UsuarioEmpresa.fromMap(d.data(), id: d.id)).toList();

      // Se consideran solo vínculos activos o pendientes
      final visibles = todos.where((v) {
        final st = v.estadoMembresia.toUpperCase();
        return st == 'ACTIVO' || st == 'PENDIENTE';
      }).toList();

      if (visibles.isEmpty) return null;

      // Orden descendente por fecha de actualización
      visibles.sort((a, b) {
        final aUpd = a.actualizadoEn ??
            a.creadoEn ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bUpd = b.actualizadoEn ??
            b.creadoEn ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bUpd.compareTo(aUpd);
      });

      return visibles.first;
    });
  }

  // --------------------------------------------------------------------------
  // Alterna la opción para usar los datos de la empresa como emisor en comprobantes
  // --------------------------------------------------------------------------
  Future<void> _toggleUsarEmpresaComoEmisor(
    BuildContext context,
    String vinculoId,
    bool nuevo,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('usuario_empresa')
          .doc(vinculoId)
          .update({
        'usaEmpresaComoEmisor': nuevo,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nuevo
                  ? 'Ahora tus comprobantes saldrán a nombre de la empresa.'
                  : 'Tus comprobantes volverán a salir con tus datos personales.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // Permite que el usuario elimine su vínculo con una empresa
  // Valida que no sea el último ADMIN antes de permitir la salida.
  // --------------------------------------------------------------------------
  Future<void> _eliminarVinculo(
    BuildContext context, {
    required String vinculoId,
    required String idEmpresa,
    required String rolUsuario,
  }) async {
    // Confirmación del usuario
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Salir de la empresa'),
        content: const Text(
            '¿Deseas salir de esta empresa? Tu vínculo será eliminado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salir')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final fs = FirebaseFirestore.instance;
      final ueRef = fs.collection('usuario_empresa');

      // Validación: no permitir eliminar al único administrador
      if (rolUsuario.toUpperCase() == 'ADMIN') {
        final admins = await ueRef
            .where('idEmpresa', isEqualTo: idEmpresa)
            .where('rol', isEqualTo: 'ADMIN')
            .get();

        if (admins.docs.length <= 1) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'No puedes salir: eres el único ADMIN. Asigna otro ADMIN primero.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      // Eliminar vínculo
      await ueRef.doc(vinculoId).delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Vínculo eliminado. Has salido de la empresa.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // Construcción principal del widget
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    // Caso: usuario no autenticado
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Mi Empresa")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Debes iniciar sesión para ver tu empresa."),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: const Text("Iniciar sesión"),
              ),
            ],
          ),
        ),
      );
    }

    // Usuario autenticado: escuchar cambios en su vínculo principal
    return Scaffold(
      appBar: AppBar(title: const Text("Mi Empresa")),
      body: StreamBuilder<UsuarioEmpresa?>(
        stream: _streamVinculoPrincipal(uid),
        builder: (context, ueSnap) {
          if (ueSnap.hasError) {
            return Center(child: Text('Error: ${ueSnap.error}'));
          }
          if (ueSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final ue = ueSnap.data;

          // Caso: sin vínculos activos o pendientes
          if (ue == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("No perteneces a ninguna empresa."),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/empresa/unirse'),
                    child: const Text("Unirse a una empresa"),
                  ),
                ],
              ),
            );
          }

          // Si hay vínculo, se consulta la información de la empresa vinculada
          final idEmpresa = ue.idEmpresa.trim();

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('empresas')
                .doc(idEmpresa)
                .snapshots(),
            builder: (context, empresaSnap) {
              if (empresaSnap.hasError) {
                return Center(child: Text('Error: ${empresaSnap.error}'));
              }
              if (empresaSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!empresaSnap.hasData || !empresaSnap.data!.exists) {
                return const Center(child: Text("La empresa ya no existe."));
              }

              // Datos principales de la empresa
              final empresa = empresaSnap.data!.data() ?? {};
              final razon = (empresa['razonSocial'] ?? 'Sin nombre').toString();
              final ruc = (empresa['ruc'] ?? idEmpresa).toString();
              final estadoEmpresa = (empresa['estado'] ?? '---').toString();
              final emailFact = (empresa['emailFacturacion'] ?? '').toString();
              final telefono = (empresa['telefono'] ?? '').toString();
              final direccion = (empresa['direccionFiscal'] ?? '').toString();
              final giro = (empresa['giroNegocio'] ?? '').toString();
              final logoUrl = (empresa['logoUrl'] ?? '').toString();
              final serieBoleta = (empresa['serieBoleta'] ?? '').toString();
              final serieFactura = (empresa['serieFactura'] ?? '').toString();

              final estadoChipColor =
                  _colorEstadoChip(ue.estadoMembresia.toUpperCase());
              final puedeGestionar =
                  PermisosEmpresa.puedeGestionarMiembros(ue);

              // ------------------------------------------------------------------
              // INTERFAZ: información general, contacto, membresía y miembros
              // ------------------------------------------------------------------
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Tarjeta con logo y datos principales
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (logoUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                logoUrl,
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            // Avatar genérico con inicial
                            CircleAvatar(
                              radius: 34,
                              child: Text(
                                (razon.isNotEmpty ? razon[0] : 'E')
                                    .toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(razon,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: -6,
                                  children: [
                                    Chip(label: Text('RUC: $ruc')),
                                    Chip(
                                      label: Text(estadoEmpresa),
                                      backgroundColor: Colors.blueGrey
                                          .withOpacity(0.08),
                                    ),
                                  ],
                                ),
                                if (giro.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text('Giro: $giro'),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Datos de contacto y facturación
                  const SizedBox(height: 12),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text('Información fiscal y contacto',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium),
                          const SizedBox(height: 10),
                          if (direccion.isNotEmpty)
                            _kv('Dirección fiscal', direccion),
                          if (emailFact.isNotEmpty)
                            _kv('Email facturación', emailFact),
                          if (telefono.isNotEmpty)
                            _kv('Teléfono', telefono),
                          if (serieBoleta.isNotEmpty ||
                              serieFactura.isNotEmpty) ...[
                            const Divider(height: 24),
                            if (serieBoleta.isNotEmpty)
                              _kv('Serie boleta', serieBoleta),
                            if (serieFactura.isNotEmpty)
                              _kv('Serie factura', serieFactura),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Bloque: membresía y opciones personales
                  const SizedBox(height: 12),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text('Mi membresía',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium),
                          const SizedBox(height: 10),
                          _kv('Rol', ue.rol),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Text('Estado: '),
                              Chip(
                                label: Text(ue.estadoMembresia),
                                backgroundColor: estadoChipColor
                                    .withOpacity(0.15),
                                labelStyle:
                                    TextStyle(color: estadoChipColor),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          FilterChip(
                            label: const Text(
                                'Usar datos de la empresa en comprobantes'),
                            selected: ue.usaEmpresaComoEmisor,
                            onSelected: (sel) =>
                                _toggleUsarEmpresaComoEmisor(
                                    context, ue.id!, sel),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.logout,
                                  color: Colors.red),
                              label: const Text('Salir de la empresa',
                                  style: TextStyle(color: Colors.red)),
                              onPressed: () => _eliminarVinculo(
                                context,
                                vinculoId: ue.id!,
                                idEmpresa: ue.idEmpresa,
                                rolUsuario: ue.rol,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ------------------------------------------------------------------
                  // Sección visible solo si el usuario tiene permisos de gestión
                  // ------------------------------------------------------------------
                  if (puedeGestionar) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Miembros de la empresa',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium),
                        TextButton.icon(
                          icon: const Icon(Icons.manage_accounts),
                          label: const Text('Gestionar'),
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              AppRouter.empresaMiembros,
                              arguments: idEmpresa,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Sublista rápida de miembros (máx. 5)
                    StreamBuilder<
                        QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('usuario_empresa')
                          .where('idEmpresa',
                              isEqualTo: idEmpresa)
                          .limit(5)
                          .snapshots(),
                      builder: (context, miembrosSnap) {
                        if (miembrosSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (!miembrosSnap.hasData ||
                            miembrosSnap.data!.docs.isEmpty) {
                          return const Text("Aún no hay miembros.");
                        }
                        final miembros = miembrosSnap.data!.docs;

                        // Lista de miembros renderizada con FutureBuilder para nombre
                        return Column(
                          children: miembros.map((mDoc) {
                            final m = UsuarioEmpresa.fromMap(
                                mDoc.data(),
                                id: mDoc.id);
                            return FutureBuilder<String>(
                              future:
                                  _getNombreUsuario(m.idUsuario),
                              builder: (context, nombreSnap) {
                                final nombreMostrar =
                                    nombreSnap.data ?? m.idUsuario;
                                final color = _colorEstadoChip(
                                    m.estadoMembresia
                                        .toUpperCase());
                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      m.rol == 'ADMIN'
                                          ? Icons.star
                                          : Icons.person,
                                      color: m.rol == 'ADMIN'
                                          ? Colors.amber
                                          : Colors.blueGrey,
                                    ),
                                    title: Text(nombreMostrar),
                                    subtitle:
                                        Text("Rol: ${m.rol}"),
                                    trailing: Chip(
                                      label: Text(
                                          m.estadoMembresia),
                                      backgroundColor: color
                                          .withOpacity(0.15),
                                      labelStyle:
                                          TextStyle(color: color),
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Widget auxiliar: imprime clave-valor con formato de texto uniforme
  // --------------------------------------------------------------------------
  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 170,
              child: Text('$k:',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}
