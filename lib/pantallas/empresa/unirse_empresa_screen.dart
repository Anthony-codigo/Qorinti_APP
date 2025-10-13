// lib/pantallas/empresa/unirse_empresa_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: UnirseEmpresaScreen
// Descripción general:
//   Permite a un usuario buscar empresas registradas activas en el sistema Qorinti
//   y solicitar unirse a una de ellas. Gestiona automáticamente las solicitudes
//   pendientes, previene duplicados, y reactiva vínculos previos en estado inactivo.
//
//   Este módulo trabaja directamente con las siguientes colecciones de Firestore:
//     • `empresas` – Datos generales de la empresa (RUC, razón social, estado, logo).
//     • `usuario_empresa` – Vínculos entre usuarios y empresas.
//     • `empresa_solicitudes` – Registros de solicitudes de unión pendientes o aprobadas.
//
//   Funcionalidades principales:
//     - Búsqueda dinámica por RUC o razón social con debounce.
//     - Validación de empresa activa antes de permitir solicitud.
//     - Prevención de duplicados o solicitudes repetidas.
//     - Reactivación de solicitudes rechazadas o vínculos previos.
//     - Envío atómico de solicitud y vínculo mediante batch Firestore.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_qorinti/modelos/usuario_empresa.dart';

class UnirseEmpresaScreen extends StatefulWidget {
  static const route = '/empresa/unirse';
  const UnirseEmpresaScreen({super.key});

  @override
  State<UnirseEmpresaScreen> createState() => _UnirseEmpresaScreenState();
}

class _UnirseEmpresaScreenState extends State<UnirseEmpresaScreen> {
  // --------------------------------------------------------------------------
  // Controladores y variables de estado
  // --------------------------------------------------------------------------
  final TextEditingController _busqueda = TextEditingController();
  String _criterio = "";       // Texto actual de búsqueda
  Timer? _debounce;            // Temporizador para control de escritura
  bool _enviando = false;      // Bloquea interacciones mientras se envía solicitud

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busqueda.removeListener(_onSearchChanged);
    _busqueda.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Control del campo de búsqueda con debounce (350 ms)
  // --------------------------------------------------------------------------
  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _criterio = _busqueda.text.trim());
    });
  }

  // --------------------------------------------------------------------------
  // Lógica principal para enviar una solicitud de unión a una empresa
  // --------------------------------------------------------------------------
  Future<void> _solicitarUnion(String idEmpresa) async {
    if (_enviando) return;
    setState(() => _enviando = true);

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Debes iniciar sesión para continuar.")),
      );
      setState(() => _enviando = false);
      return;
    }

    try {
      final fs = FirebaseFirestore.instance;
      final empresasRef = fs.collection('empresas');
      final ueRef = fs.collection('usuario_empresa');
      final solicitudesRef = fs.collection('empresa_solicitudes');

      // Verificar existencia y estado de la empresa
      final empresaDoc = await empresasRef.doc(idEmpresa).get(const GetOptions(source: Source.serverAndCache));
      if (!empresaDoc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La empresa no existe.")));
        setState(() => _enviando = false);
        return;
      }

      final empresaData = empresaDoc.data() ?? {};
      final estadoEmpresa = (empresaData['estado'] ?? 'ACTIVA').toString().toUpperCase();
      if (estadoEmpresa != 'ACTIVA') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("La empresa no está activa (estado: $estadoEmpresa).")),
        );
        setState(() => _enviando = false);
        return;
      }

      // ----------------------------------------------------------------------
      // Paso 1: Verificar si existe una solicitud pendiente duplicada
      // ----------------------------------------------------------------------
      final dup = await solicitudesRef
          .where('idEmpresa', isEqualTo: idEmpresa)
          .where('creadoPor', isEqualTo: uid)
          .where('estado', isEqualTo: 'PENDIENTE')
          .limit(1)
          .get();

      if (dup.docs.isNotEmpty) {
        final d = dup.docs.first;
        final ueId = (d.data()['usuarioEmpresaId'] ?? '').toString();

        if (ueId.isNotEmpty) {
          final ueSnap = await ueRef.doc(ueId).get();
          final estadoV = (ueSnap.data()?['estadoMembresia'] ?? '').toString().toUpperCase();

          // Si el vínculo ya no existe o no está pendiente, se marca como rechazada
          if (!ueSnap.exists || estadoV != 'PENDIENTE') {
            await d.reference.update({
              'estado': 'RECHAZADA',
              'actualizadoEn': FieldValue.serverTimestamp(),
            });
          } else {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Ya tienes una solicitud pendiente para esta empresa.")),
            );
            setState(() => _enviando = false);
            return;
          }
        } else {
          // Limpieza de registros huérfanos
          await d.reference.update({
            'estado': 'RECHAZADA',
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
        }
      }

      // ----------------------------------------------------------------------
      // Paso 2: Verificar si el usuario ya tiene vínculo previo con la empresa
      // ----------------------------------------------------------------------
      final vinculoQuery = await ueRef
          .where('idUsuario', isEqualTo: uid)
          .where('idEmpresa', isEqualTo: idEmpresa)
          .limit(1)
          .get();

      if (vinculoQuery.docs.isNotEmpty) {
        final doc = vinculoQuery.docs.first;
        final data = doc.data();
        final estado = (data['estadoMembresia'] ?? 'PENDIENTE').toString().toUpperCase();

        // Manejo de casos según estado actual del vínculo
        if (estado == 'ACTIVO') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Ya eres miembro de esta empresa.")),
          );
          setState(() => _enviando = false);
          return;
        }

        if (estado == 'PENDIENTE') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Ya tienes una solicitud registrada.")),
          );
          setState(() => _enviando = false);
          return;
        }

        // Reactivación del vínculo (por ejemplo, si estaba dado de baja)
        final batch = fs.batch();
        batch.update(doc.reference, {
          'estadoMembresia': 'PENDIENTE',
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
        final solicitudRef = solicitudesRef.doc();
        batch.set(solicitudRef, {
          'idEmpresa': idEmpresa,
          'razonSocial': (empresaData['razonSocial'] ?? '').toString(),
          'creadoPor': uid,
          'estado': 'PENDIENTE',
          'creadoEn': FieldValue.serverTimestamp(),
          'usuarioEmpresaId': doc.id,
        });
        await batch.commit();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Solicitud reabierta y enviada ")),
        );
        setState(() => _enviando = false);
        return;
      }

      // ----------------------------------------------------------------------
      // Paso 3: Crear nueva solicitud y vínculo usuario-empresa
      // ----------------------------------------------------------------------
      final nuevoUeRef = ueRef.doc();
      final usuarioEmpresa = UsuarioEmpresa(
        id: nuevoUeRef.id,
        idUsuario: uid,
        idEmpresa: idEmpresa,
        estadoMembresia: "PENDIENTE",
        rol: "MIEMBRO",
      );

      final batch = fs.batch();

      // Crear vínculo
      batch.set(nuevoUeRef, {
        ...usuarioEmpresa.toMap(),
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // Crear solicitud asociada
      final solicitudRef = solicitudesRef.doc();
      batch.set(solicitudRef, {
        'idEmpresa': idEmpresa,
        'razonSocial': (empresaData['razonSocial'] ?? '').toString(),
        'creadoPor': uid,
        'estado': 'PENDIENTE',
        'creadoEn': FieldValue.serverTimestamp(),
        'usuarioEmpresaId': nuevoUeRef.id,
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Solicitud enviada con éxito ")),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // --------------------------------------------------------------------------
  // Construye el stream de empresas activas según el criterio de búsqueda
  // - Si vacío → primeras 25 empresas ordenadas alfabéticamente
  // - Si es RUC (11 dígitos) → búsqueda exacta
  // - Si texto → búsqueda por prefijo de razón social
  // --------------------------------------------------------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> _empresasStream() {
    final baseQuery = FirebaseFirestore.instance
        .collection('empresas')
        .where('estado', isEqualTo: "ACTIVA");

    if (_criterio.isEmpty) {
      return baseQuery.orderBy('razonSocial').limit(25).snapshots();
    }

    final c = _criterio;
    if (c.length == 11 && RegExp(r'^\d{11}$').hasMatch(c)) {
      return baseQuery.where('ruc', isEqualTo: c).limit(1).snapshots();
    }

    return baseQuery.orderBy('razonSocial').startAt([c]).endAt(['$c\uf8ff']).limit(30).snapshots();
  }

  // --------------------------------------------------------------------------
  // Construcción visual principal de la pantalla
  // Incluye el buscador, la lista de resultados y los botones de acción
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Unirse a una Empresa")),
      body: Column(
        children: [
          // --------------------------------------------------------------
          // Campo de búsqueda
          // --------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _busqueda,
              decoration: InputDecoration(
                labelText: "Buscar por RUC o Razón Social",
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _criterio.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _busqueda.clear();
                          setState(() => _criterio = "");
                        },
                      )
                    : null,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => setState(() => _criterio = _busqueda.text.trim()),
            ),
          ),
          const SizedBox(height: 8),

          // --------------------------------------------------------------
          // Listado de empresas en tiempo real
          // --------------------------------------------------------------
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _empresasStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text("No se encontraron empresas."));
                }

                final empresas = snap.data!.docs;
                final uid = FirebaseAuth.instance.currentUser?.uid;

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: empresas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final doc = empresas[i];
                    final e = doc.data();
                    final idEmpresa = doc.id;
                    final razon = (e['razonSocial'] ?? '').toString();
                    final ruc = (e['ruc'] ?? '').toString();
                    final estado = (e['estado'] ?? '').toString();
                    final logoUrl = (e['logoUrl'] ?? '').toString();

                    // ------------------------------------------------------
                    // Tarjeta individual de empresa con acción condicional
                    // ------------------------------------------------------
                    return Card(
                      elevation: 2,
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
                                      CircleAvatar(backgroundColor: cs.primary.withOpacity(.12), child: const Icon(Icons.business)),
                                ),
                              )
                            : CircleAvatar(
                                backgroundColor: cs.primary.withOpacity(.12),
                                child: const Icon(Icons.business),
                              ),
                        title: Text(razon.isNotEmpty ? razon : 'Sin razón social',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text("RUC: $ruc | Estado: $estado"),
                        trailing: (uid == null)
                            ? const SizedBox()
                            : _EstadoUnionBoton(
                                idEmpresa: idEmpresa,
                                uid: uid,
                                onUnirme: () => _solicitarUnion(idEmpresa),
                                enviando: _enviando,
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
}

// -----------------------------------------------------------------------------
// Widget auxiliar: _EstadoUnionBoton
// Muestra el estado actual de la relación usuario-empresa (chip o botón).
//   - Si el usuario no está vinculado → botón "Unirme"
//   - Si el estado es PENDIENTE → chip "Pendiente"
//   - Si el estado es ACTIVO → chip "Miembro"
//   - Si está suspendido o dado de baja → botón "Reabrir"
// -----------------------------------------------------------------------------
class _EstadoUnionBoton extends StatelessWidget {
  final String idEmpresa;
  final String uid;
  final VoidCallback onUnirme;
  final bool enviando;
  const _EstadoUnionBoton({
    required this.idEmpresa,
    required this.uid,
    required this.onUnirme,
    required this.enviando,
  });

  @override
  Widget build(BuildContext context) {
    final ueQuery = FirebaseFirestore.instance
        .collection('usuario_empresa')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('idUsuario', isEqualTo: uid)
        .limit(1);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ueQuery.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 120,
            height: 38,
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return FilledButton(
            onPressed: enviando ? null : onUnirme,
            child: const Text("Unirme"),
          );
        }

        final u = docs.first.data();
        final estado = (u['estadoMembresia'] ?? 'PENDIENTE').toString().toUpperCase();

        if (estado == 'ACTIVO') {
          return const Chip(
            label: Text('Miembro'),
            avatar: Icon(Icons.verified, size: 18),
          );
        }
        if (estado == 'PENDIENTE') {
          return const Chip(
            label: Text('Pendiente'),
            avatar: Icon(Icons.schedule, size: 18),
          );
        }
        if (estado == 'SUSPENDIDO' || estado == 'BAJA') {
          return OutlinedButton.icon(
            onPressed: enviando ? null : onUnirme,
            icon: const Icon(Icons.refresh),
            label: const Text('Reabrir'),
          );
        }

        return OutlinedButton(
          onPressed: enviando ? null : onUnirme,
          child: const Text("Solicitar"),
        );
      },
    );
  }
}
