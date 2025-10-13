// lib/pantallas/Admin/admin_conductores_screen.dart
// ============================================================================
// Archivo: admin_conductores_screen.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Pantalla de administración para la gestión de conductores. Permite:
// - Filtrar por estado (Pendiente, Aprobado, Suspendido).
// - Buscar por nombre, DNI, licencia o UID.
// - Realizar acciones de aprobación, suspensión y reactivación.
// - Visualizar detalles del conductor con datos normativos y de contacto.
//
// Alcance e integración
// ---------------------
// - Integra Firestore para lectura en tiempo real de la colección `conductores`
//   y de `usuarios` para denormalizar nombre/foto.
// - Integra Firebase Storage para resolver rutas de imágenes almacenadas.
// - Implementa estrategias de performance: caché de nombres y fotos,
//   precarga en lotes y actualización diferida del estado del widget.
// - Usa `utils.dart` para formateo/parseo de fechas en el detalle.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:app_qorinti/modelos/utils.dart';

class AdminConductoresScreen extends StatefulWidget {
  const AdminConductoresScreen({super.key});

  @override
  State<AdminConductoresScreen> createState() => _AdminConductoresScreenState();
}

// ----------------------------------------------------------------------------
// Estado de la pantalla de administración
// - Mantiene filtros, término de búsqueda y cachés locales.
// - Orquesta la carga en lote de datos relacionados (usuarios/fotos).
// ----------------------------------------------------------------------------
class _AdminConductoresScreenState extends State<AdminConductoresScreen> {
  String? _filtroEstado;
  final _busquedaCtrl = TextEditingController();

  // Caché de nombres de usuario (para evitar lecturas repetidas de `usuarios`)
  final Map<String, String> _cacheNombresUsuarios = {};

  // Caché de URLs ya resueltas (conductor/usuario) para imágenes de perfil
  final Map<String, String> _cacheFotos = {};

  // Flag para evitar ejecuciones concurrentes de precarga
  bool _cargandoBatch = false;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------------------
  // Utilidades de presentación y ayuda
  // ----------------------------------------------------------------------------

  // Mapeo visual de estado → color indicativo
  Color _colorPorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case 'APROBADO':
        return Colors.green;
      case 'SUSPENDIDO':
      case 'BLOQUEADO':
        return Colors.red;
      default:
        return Colors.orange; 
    }
  }

  // Fragmenta una lista en sublistas de tamaño `size` (para consultas whereIn)
  List<List<T>> _chunks<T>(List<T> list, int size) {
    final res = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      res.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return res;
  }

  // Determina si una cadena es una URL http(s) (para fotos ya públicas)
  bool _esUrlHttp(String? v) {
    if (v == null) return false;
    final s = v.trim().toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://');
    }

  // Resuelve un path de Firebase Storage a una URL descargable; si ya es URL, la retorna
  Future<String?> _resolverStoragePath(String? path) async {
    try {
      if (path == null || path.trim().isEmpty) return null;
      if (_esUrlHttp(path)) return path; 
      final ref = FirebaseStorage.instance.ref(path);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------------------
  // Precarga en lote de datos relacionados
  // - Recolecta ids de usuario sin nombre denormalizado y paths de fotos
  // - Realiza consultas paginadas (whereIn en lotes de 10)
  // - Resuelve rutas de Firebase Storage a URLs públicas
  // - Actualiza cachés y refresca UI si el widget sigue montado
  // ----------------------------------------------------------------------------
  Future<void> _precargarBatch(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_cargandoBatch) return;

    final setUsuariosPendientes = <String>{};
    final Map<String, String> fotosConductorPendientes = {}; 
    final Map<String, String> fotosUsuarioPendientes = {}; 

    for (final d in docs) {
      final c = d.data();
      final idConductor = d.id;
      final idUsuario = (c['idUsuario'] ?? '').toString().trim();

      // Detecta necesidad de denormalizar nombre desde `usuarios`
      final nombreCond = (c['nombre'] ?? '').toString().trim();
      if (idUsuario.isNotEmpty &&
          nombreCond.isEmpty &&
          !_cacheNombresUsuarios.containsKey(idUsuario)) {
        setUsuariosPendientes.add(idUsuario);
      }

      // Prepara resolución de foto del conductor (prefiere cache, luego Storage)
      final fotoCond = (c['fotoUrl'] ?? '').toString().trim();
      if (fotoCond.isNotEmpty) {
        final keyC = 'c:$idConductor';
        if (!_cacheFotos.containsKey(keyC)) {
          if (_esUrlHttp(fotoCond)) {
            _cacheFotos[keyC] = fotoCond;
          } else {
            fotosConductorPendientes[idConductor] = fotoCond; 
          }
        }
      }

      // Si no hay foto de conductor en caché, intenta usar la del usuario
      if (!_cacheFotos.containsKey('c:$idConductor') && idUsuario.isNotEmpty) {
        final keyU = 'u:$idUsuario';
        if (!_cacheFotos.containsKey(keyU)) {
          setUsuariosPendientes.add(idUsuario);
        }
      }
    }

    if (setUsuariosPendientes.isEmpty &&
        fotosConductorPendientes.isEmpty &&
        fotosUsuarioPendientes.isEmpty) {
      return;
    }

    _cargandoBatch = true;
    try {
      // Consulta en lotes de hasta 10 ids para `whereIn`
      final lotes = _chunks(setUsuariosPendientes.toList(), 10);
      for (final lote in lotes) {
        final qs = await FirebaseFirestore.instance
            .collection('usuarios')
            .where(FieldPath.documentId, whereIn: lote)
            .get();

        for (final u in qs.docs) {
          final data = u.data();
          final idU = u.id;
          final nombreU = (data['nombre'] ?? '').toString().trim();
          if (nombreU.isNotEmpty) {
            _cacheNombresUsuarios[idU] = nombreU;
          }

          // Prepara ruta de foto del usuario (URL directa o path de Storage)
          final fotoU = (data['fotoUrl'] ?? '').toString().trim();
          if (fotoU.isNotEmpty) {
            if (_esUrlHttp(fotoU)) {
              _cacheFotos['u:$idU'] = fotoU;
            } else {
              fotosUsuarioPendientes[idU] = fotoU;
            }
          }
        }
      }

      // Resuelve fotos de conductor desde Storage
      for (final entry in fotosConductorPendientes.entries) {
        final idC = entry.key;
        final path = entry.value;
        final url = await _resolverStoragePath(path);
        if (url != null) _cacheFotos['c:$idC'] = url;
      }

      // Resuelve fotos de usuario desde Storage
      for (final entry in fotosUsuarioPendientes.entries) {
        final idU = entry.key;
        final path = entry.value;
        final url = await _resolverStoragePath(path);
        if (url != null) _cacheFotos['u:$idU'] = url;
      }

      if (mounted) setState(() {});
    } finally {
      _cargandoBatch = false;
    }
  }

  // ----------------------------------------------------------------------------
  // Confirmación genérica de acciones administrativas
  // ----------------------------------------------------------------------------
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aceptar')),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  // ----------------------------------------------------------------------------
  // Cambio de estado de conductor (aprobar/suspender)
  // - Actualiza campos de control y auditoría, y realiza denormalización
  //   de nombre si existe el usuario relacionado.
  // ----------------------------------------------------------------------------
  Future<void> _cambiarEstadoConductor(
    BuildContext context, {
    required String id,
    required String accion,
    String? motivo,
  }) async {
    final fs = FirebaseFirestore.instance;
    final ahora = FieldValue.serverTimestamp();

    final estadoNuevo = accion == 'APROBAR' ? 'APROBADO' : 'SUSPENDIDO';
    final estadoCompat = accion == 'APROBAR' ? 'ACTIVO' : 'BLOQUEADO';

    try {
      final ref = fs.collection('conductores').doc(id);

      String? nombreDenorm;
      String? idUsuario;
      final snap = await ref.get();
      if (snap.exists) {
        final data = snap.data()!;
        idUsuario = (data['idUsuario'] ?? '').toString();
        if (idUsuario.isNotEmpty) {
          final u = await fs.collection('usuarios').doc(idUsuario).get();
          nombreDenorm = (u.data()?['nombre'] ?? '').toString().trim();
        }
      }

      await ref.update({
        'estado': estadoNuevo,
        'estadoOperativo': estadoCompat,
        if (motivo != null) 'motivoSuspension': motivo,
        if ((nombreDenorm ?? '').isNotEmpty) 'nombre': nombreDenorm,
        'actualizadoEn': ahora,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Conductor $estadoNuevo ✅")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Diálogo de suspensión con captura opcional de motivo
  Future<void> _suspenderConductor(
    BuildContext context,
    String id,
    String nombre,
  ) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Suspender a $nombre'),
        content: TextField(
          controller: motivoCtrl,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
            border: OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Suspender')),
        ],
      ),
    );
    if (ok == true) {
      await _cambiarEstadoConductor(
        context,
        id: id,
        accion: 'SUSPENDER',
        motivo: motivoCtrl.text.trim().isEmpty ? null : motivoCtrl.text.trim(),
      );
    }
  }

  // ----------------------------------------------------------------------------
  // Visualización de detalle de conductor (lectura directa de campos)
  // - Utiliza utilidades de formateo de fecha y conversiones del módulo `utils`.
  // ----------------------------------------------------------------------------
  void _mostrarDetalleDialog(String uid, Map<String, dynamic> c, String nombreMostrar) {
    String s(dynamic v) => (v ?? '').toString().trim();
    final dni       = s(c['dni']);
    final lic       = s(c['licenciaNumero']);
    final cat       = s(c['licenciaCategoria']);
    final vence     = formatDate(dt(c['licenciaVencimiento']));
    final tel       = s(c['telefono']);
    final email     = s(c['email']);
    final estado    = s((c['estado'] ?? '').toString().toUpperCase());
    final operativo = s(c['estadoOperativo']);
    final creado    = formatDate(dt(c['creadoEn']));
    final act       = formatDate(dt(c['actualizadoEn']));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Detalle de conductor'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _row('UID', uid, copyable: true),
              _row('Nombre', nombreMostrar),
              _row('DNI', dni.isEmpty ? '-' : dni),
              _row('Licencia', [lic, if (cat.isNotEmpty) '($cat)'].join(' ').trim() ),
              _row('Vencimiento', vence.isEmpty ? '-' : vence),
              if (tel.isNotEmpty) _row('Teléfono', tel),
              if (email.isNotEmpty) _row('Email', email),
              _row('Estado', estado.isEmpty ? '-' : estado),
              if (operativo.isNotEmpty) _row('Operativo', operativo),
              if (creado.isNotEmpty) _row('Creado', creado),
              if (act.isNotEmpty) _row('Actualizado', act),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  // Renglón clave:valor con opción de copia al portapapeles
  Widget _row(String k, String v, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$k:', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v)),
          if (copyable)
            IconButton(
              tooltip: 'Copiar',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: v));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copiado'), duration: Duration(milliseconds: 900)),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------------
  // Build principal
  // - Suscribe a la colección `conductores` ordenada por fecha de creación.
  // - Aplica filtros por estado y búsqueda textual.
  // - Renderiza tarjetas con datos clave y acciones contextuales.
  // ----------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('conductores')
        .orderBy('creadoEn', descending: true);

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

              // Precarga diferida: evita bloquear el cuadro de render
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _precargarBatch(docs);
              });

              final term = _busquedaCtrl.text.trim().toLowerCase();

              // Filtro compuesto: estado + término de búsqueda en varios campos
              final filtrados = docs.where((d) {
                final c = d.data();
                final uidDoc = d.id.toLowerCase();
                final estado = (c['estado'] ?? '').toString().toUpperCase();

                final idUsuario = (c['idUsuario'] ?? '').toString();
                final nombreEf = (c['nombre'] ?? '').toString().trim().isNotEmpty
                    ? (c['nombre'] ?? '').toString()
                    : (_cacheNombresUsuarios[idUsuario] ?? '');

                final nombre = nombreEf.toLowerCase();
                final dni    = (c['dni'] ?? '').toString().toLowerCase();
                final lic    = (c['licenciaNumero'] ?? '').toString().toLowerCase();

                if (_filtroEstado != null && estado != _filtroEstado) return false;
                if (term.isEmpty) return true;

                return nombre.contains(term) || dni.contains(term) || lic.contains(term) || uidDoc.contains(term);
              }).toList();

              if (filtrados.isEmpty) {
                return const Center(child: Text("No hay conductores que coincidan."));
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: filtrados.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final doc = filtrados[i];
                  final c = doc.data();
                  final uid = doc.id;
                  String s(dynamic v) => (v ?? '').toString().trim();

                  final idUsuario = s(c['idUsuario']);
                  final nombreMostrar = s(c['nombre']).isNotEmpty
                      ? s(c['nombre'])
                      : (_cacheNombresUsuarios[idUsuario] ?? '---');

                  // Resolución de foto: prioridad conductor; fallback usuario
                  String? fotoUrlMostrar = _cacheFotos['c:$uid'];
                  fotoUrlMostrar ??= _cacheFotos['u:$idUsuario'];

                  // Campos normativos/contacto para la tarjeta
                  final dni   = s(c['dni']);
                  final lic   = s(c['licenciaNumero']);
                  final cat   = s(c['licenciaCategoria']);
                  final vence = formatDate(dt(c['licenciaVencimiento']));
                  final tel   = s(c['telefono']);
                  final email = s(c['email']);

                  // Estado visual e interacción contextual
                  final estado = (c['estado'] ?? 'PENDIENTE').toString();
                  final color  = _colorPorEstado(estado);

                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: _avatarConductor(nombreMostrar, fotoUrlMostrar, color),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nombreMostrar, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'UID: $uid',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copiar UID',
                                icon: const Icon(Icons.copy, size: 16),
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: uid));
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('UID copiado'),
                                        duration: Duration(milliseconds: 900),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("DNI: ${dni.isEmpty ? '-' : dni}"),
                          Text("Licencia: ${lic.isEmpty ? '-' : lic} ${cat.isNotEmpty ? '($cat)' : ''}"),
                          Text("Vence: ${vence.isEmpty ? '-' : vence}"),
                          if (tel.isNotEmpty) Text("Teléfono: $tel"),
                          if (email.isNotEmpty) Text("Email: $email"),
                        ],
                      ),
                      trailing: _accionesPorEstado(context, doc.id, nombreMostrar, estado),
                      isThreeLine: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      onTap: () => _mostrarDetalleDialog(uid, c, nombreMostrar),
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

  // ----------------------------------------------------------------------------
  // Avatar de conductor
  // - Usa foto si está disponible; si no, renderiza iniciales con color por estado.
  // ----------------------------------------------------------------------------
  Widget _avatarConductor(String nombre, String? fotoUrl, Color colorEstado) {
    final bg = colorEstado.withOpacity(0.15);

    if (fotoUrl != null && fotoUrl.isNotEmpty) {
      return CircleAvatar(
        backgroundColor: bg,
        backgroundImage: NetworkImage(fotoUrl),
        radius: 22,
      );
    }

    // Iniciales como fallback
    String iniciales = 'C';
    final partes = nombre.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (partes.isNotEmpty) {
      final p1 = partes[0][0];
      final p2 = partes.length > 1 ? partes[1][0] : '';
      iniciales = (p1 + p2).toUpperCase();
    }

    return CircleAvatar(
      backgroundColor: bg,
      radius: 22,
      child: Text(
        iniciales,
        style: TextStyle(
          color: colorEstado,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------------
  // Controles de filtro y búsqueda
  // - Chips de estado y campo de búsqueda con limpieza rápida
  // ----------------------------------------------------------------------------
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
          chip('APROBADO', 'Aprobados'),
          chip('SUSPENDIDO', 'Suspendidos'),
          const SizedBox(width: 12),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _busquedaCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar nombre, DNI, licencia o UID',
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

  // ----------------------------------------------------------------------------
  // Acciones contextuales por estado
  // - Pendiente: aprobar/suspender.
  // - Aprobado: suspender.
  // - Suspendido/otros: reactivar.
  // ----------------------------------------------------------------------------
  Widget _accionesPorEstado(BuildContext context, String id, String nombre, String estado) {
    if (estado == 'PENDIENTE') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Aprobar conductor',
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: () => _confirmarAccion(
              context,
              "¿Aprobar al conductor $nombre?",
              () => _cambiarEstadoConductor(context, id: id, accion: 'APROBAR'),
            ),
          ),
          IconButton(
            tooltip: 'Suspender conductor',
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => _suspenderConductor(context, id, nombre),
          ),
        ],
      );
    } else if (estado == 'APROBADO') {
      return TextButton(
        onPressed: () => _suspenderConductor(context, id, nombre),
        child: const Text('Suspender'),
      );
    } else {
      return TextButton(
        onPressed: () => _confirmarAccion(
          context,
          "¿Reactivar al conductor $nombre?",
          () => _cambiarEstadoConductor(context, id: id, accion: 'APROBAR'),
        ),
        child: const Text('Reactivar'),
      );
    }
  }
}
