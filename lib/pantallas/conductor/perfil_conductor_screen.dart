// lib/conductor/perfil_conductor_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: Perfil del Conductor
// Esta vista permite al conductor gestionar su perfil personal dentro de la
// aplicación Qorinti, incluyendo:
//   • Validación de identidad (DNI y RUC).
//   • Actualización de dirección fiscal y foto de perfil.
//   • Sincronización de calificaciones (ratings) y comentarios de clientes.
//   • Visualización del estado operativo y del vehículo activo.
// Además, integra validación automática del RUC mediante la API SUNAT a través
// del servicio `RucServicio`, con control de temporización y estados de carga.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app_qorinti/modelos/utils.dart';
import 'package:app_qorinti/servicios/ruc_servicio.dart';

class PerfilConductorScreen extends StatefulWidget {
  static const route = '/conductor/perfil';
  const PerfilConductorScreen({super.key});

  @override
  State<PerfilConductorScreen> createState() => _PerfilConductorScreenState();
}

class _PerfilConductorScreenState extends State<PerfilConductorScreen> {
  // --------------------------------------------------------------------------
  // Variables de control de estados visuales y asincrónicos
  // --------------------------------------------------------------------------
  bool _syncingRating = false;   // Estado: sincronizando calificación promedio
  bool _uploadingPhoto = false;  // Estado: subiendo imagen de perfil
  bool _savingExtra = false;     // Estado: guardando datos adicionales

  // Estados internos de validación de RUC y carga inicial
  bool _cargadoInicial = false;
  bool _validandoRuc = false;
  bool _rucValido = false;
  String? _ultimoRucValidado;

  // Mecanismo de debounce y control de concurrencia de validaciones RUC
  Timer? _rucDebounce;
  int _rucRequestSeq = 0;
  int _rucLastCompletedSeq = 0;

  // Control de foco y persistencia al reconstruir la UI
  final _rucFocus = FocusNode();
  bool _holdFocusAfterRebuild = false;

  // Controladores de campos de texto
  final _dniCtrl = TextEditingController();
  final _rucCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  @override
  void dispose() {
    // Libera recursos al cerrar la pantalla
    _rucDebounce?.cancel();
    _rucFocus.dispose();
    _dniCtrl.dispose();
    _rucCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  // Devuelve un color según el estado operativo del conductor
  Color _estadoColor(String e) {
    switch (e.toUpperCase()) {
      case 'APROBADO':
      case 'ACTIVO':
        return Colors.green;
      case 'RECHAZADO':
      case 'SUSPENDIDO':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  // --------------------------------------------------------------------------
  // Obtiene el nombre visible del conductor
  // Si no tiene nombre registrado en la colección 'conductores', consulta 'usuarios'.
  // --------------------------------------------------------------------------
  Future<String> _getDisplayName({
    required Map<String, dynamic> conductorData,
    required String uid,
  }) async {
    final nombreConductor = (conductorData['nombre'] ?? '').toString().trim();
    if (nombreConductor.isNotEmpty) return nombreConductor;

    try {
      final u = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final nombreUsuario = (u.data()?['nombre'] ?? '').toString().trim();
      if (nombreUsuario.isNotEmpty) return nombreUsuario;
    } catch (_) {}
    return 'Conductor';
  }

  // --------------------------------------------------------------------------
  // Genera un stream en tiempo real con calificaciones del conductor
  // Lee de la colección 'calificaciones' filtrando por `paraUsuarioId`
  // --------------------------------------------------------------------------
  Stream<_RatingBundle> _ratingStreamLive(String uid) {
    final q = FirebaseFirestore.instance
        .collection('calificaciones')
        .where('paraUsuarioId', isEqualTo: uid);

    return q.snapshots().map((snap) {
      int count = 0;
      int sum = 0;
      final comments = <_RatingItem>[];

      for (final d in snap.docs) {
        final m = d.data();
        final estrellas = (m['estrellas'] as num?)?.toInt() ?? 0;
        if (estrellas > 0) {
          sum += estrellas;
          count++;
        }
        final c = (m['comentario'] as String?)?.trim() ?? '';
        DateTime? t;
        final ce = m['creadoEn'];
        if (ce is Timestamp) t = ce.toDate();
        if (c.isNotEmpty) {
          comments.add(_RatingItem(estrellas: estrellas, comentario: c, creadoEn: t));
        }
      }

      comments.sort((a, b) =>
          (b.creadoEn ?? DateTime(0)).compareTo(a.creadoEn ?? DateTime(0)));

      final avg = count == 0 ? 0.0 : (sum / count);
      return _RatingBundle(avg: avg, count: count, comments: comments.take(50).toList());
    });
  }

  // --------------------------------------------------------------------------
  // Sincroniza las calificaciones promedio en la colección 'conductores'
  // Actualiza el rating denormalizado (promedio y conteo) en Firestore
  // --------------------------------------------------------------------------
  Future<void> _syncDenormalizado(String uid, double avg, int count) async {
    if (_syncingRating) return;
    setState(() => _syncingRating = true);
    try {
      await FirebaseFirestore.instance.collection('conductores').doc(uid).update({
        'ratingPromedio': avg,
        'ratingConteo': count,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rating sincronizado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo sincronizar rating: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncingRating = false);
    }
  }

  // --------------------------------------------------------------------------
  // Valida un RUC localmente usando el algoritmo de verificación SUNAT
  // --------------------------------------------------------------------------
  bool _esRucValidoLocal(String ruc) {
    if (ruc.length != 11 || int.tryParse(ruc) == null) return false;
    final pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
    int suma = 0;
    for (int i = 0; i < 10; i++) {
      suma += int.parse(ruc[i]) * pesos[i];
    }
    final resto = suma % 11;
    final digito = (11 - resto) % 10;
    return digito == int.parse(ruc[10]);
  }

  // Sincroniza el texto de un controlador solo si difiere
  void _syncCtrl(TextEditingController c, String nuevo) {
    if (c.text.trim() != nuevo.trim()) c.text = nuevo;
  }

  // --------------------------------------------------------------------------
  // Maneja los cambios del campo RUC con debounce
  // Aplica validaciones locales y dispara la validación remota vía API
  // --------------------------------------------------------------------------
  void _onRucChanged(String uid, String value) {
    final ruc = value.replaceAll(RegExp(r'\s+'), '').trim();

    _rucDebounce?.cancel();

    // Caso: RUC incompleto (<11 dígitos)
    if (ruc.length < 11) {
      if (_validandoRuc || _rucValido || _ultimoRucValidado != null) {
        _holdFocusAfterRebuild = _rucFocus.hasFocus;
        setState(() {
          _validandoRuc = false;
          _rucValido = false;
          _ultimoRucValidado = null;
        });
      }
      return;
    }

    // Caso: formato de RUC incorrecto localmente
    if (!_esRucValidoLocal(ruc)) {
      _holdFocusAfterRebuild = _rucFocus.hasFocus;
      setState(() {
        _validandoRuc = false;
        _rucValido = false;
        _ultimoRucValidado = null;
      });
      return;
    }

    // Si el mismo RUC ya fue validado y confirmado, no repite la llamada
    if (_rucValido && _ultimoRucValidado == ruc) {
      if (_validandoRuc) {
        _holdFocusAfterRebuild = _rucFocus.hasFocus;
        setState(() => _validandoRuc = false);
      }
      return;
    }

    // Ejecuta validación remota con pequeña espera (debounce 300ms)
    _rucDebounce = Timer(const Duration(milliseconds: 300), () {
      _validarRucConApi(uid, ruc);
    });
  }

  // --------------------------------------------------------------------------
  // Llama al servicio RucServicio() para validar datos oficiales SUNAT
  // Actualiza el documento del conductor con razón social, dirección y estado.
  // --------------------------------------------------------------------------
  Future<void> _validarRucConApi(String uid, String ruc) async {
    final int seq = ++_rucRequestSeq;
    _holdFocusAfterRebuild = _rucFocus.hasFocus;
    setState(() => _validandoRuc = true);

    try {
      final servicio = RucServicio();
      final data = await servicio.validarRuc(ruc);

      // Ignora respuestas tardías si hay solicitudes más recientes
      if (seq < _rucLastCompletedSeq) return;
      _rucLastCompletedSeq = seq;

      // Caso: respuesta vacía o sin datos útiles
      if (data == null) {
        _holdFocusAfterRebuild = _rucFocus.hasFocus;
        setState(() {
          _validandoRuc = false;
          _rucValido = false;
          _ultimoRucValidado = null;
        });
        return;
      }

      final razon = (data['razonSocial'] ?? data['nombre'] ?? '').toString().trim();
      final dirApi = (data['direccion'] ?? '').toString().trim();
      final estadoRuc = (data['estado'] ?? '').toString().trim();
      final condicionRuc = (data['condicion'] ?? '').toString().trim();
      final hayDatosUtiles = razon.isNotEmpty || dirApi.isNotEmpty || estadoRuc.isNotEmpty || condicionRuc.isNotEmpty;

      if (!hayDatosUtiles) {
        _holdFocusAfterRebuild = _rucFocus.hasFocus;
        setState(() {
          _validandoRuc = false;
          _rucValido = false;
          _ultimoRucValidado = null;
        });
        return;
      }

      // Si la API devuelve dirección, se actualiza el campo visible
      if (dirApi.isNotEmpty) {
        _direccionCtrl.text = dirApi;
      }

      // Datos a actualizar en Firestore
      final updates = <String, dynamic>{
        'ruc': ruc,
        if (dirApi.isNotEmpty) 'direccionFiscal': dirApi,
        if (razon.isNotEmpty) 'razonSocialRuc': razon,
        if (estadoRuc.isNotEmpty) 'estadoRuc': estadoRuc,
        if (condicionRuc.isNotEmpty) 'condicionRuc': condicionRuc,
        'rucValido': true,
        'rucValidadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      };

      // Completa nombre del conductor si aún no tiene uno
      try {
        final snap = await FirebaseFirestore.instance.collection('conductores').doc(uid).get();
        final nombreActual = (snap.data()?['nombre'] ?? '').toString().trim();
        if (nombreActual.isEmpty && razon.isNotEmpty) {
          updates['nombre'] = razon;
        }
      } catch (_) {}

      // Actualiza el registro del conductor
      await FirebaseFirestore.instance.collection('conductores').doc(uid).update(updates);

      _holdFocusAfterRebuild = _rucFocus.hasFocus;
      setState(() {
        _validandoRuc = false;
        _rucValido = true;
        _ultimoRucValidado = ruc;
      });

      _snack('RUC validado y datos completados');
    } catch (e) {
      if (!mounted) return;
      _holdFocusAfterRebuild = _rucFocus.hasFocus;
      setState(() {
        _validandoRuc = false;
        _rucValido = false;
        _ultimoRucValidado = null;
      });
      _snack('No se pudo validar el RUC: $e');
    }
  }


  // --------------------------------------------------------------------------
  // Guarda datos adicionales del conductor (DNI, RUC y dirección fiscal)
  // Aplica validaciones previas antes de actualizar Firestore.
  // --------------------------------------------------------------------------
  Future<void> _guardarDatosExtras(String uid) async {
    if (_savingExtra) return;

    final dni = _dniCtrl.text.trim();
    final ruc = _rucCtrl.text.replaceAll(RegExp(r'\s+'), '').trim();
    final dir = _direccionCtrl.text.trim();

    // Validaciones mínimas
    if (dni.isEmpty && ruc.isEmpty) {
      _snack('Ingrese al menos DNI o RUC');
      return;
    }

    if (ruc.isNotEmpty) {
      if (!_esRucValidoLocal(ruc)) {
        _snack('RUC inválido. Corrígelo o bórralo para guardar.');
        return;
      }
      if (!_rucValido || _ultimoRucValidado != ruc) {
        _snack('Valida el RUC (11 dígitos) y espera la confirmación antes de guardar.');
        return;
      }
    }

    setState(() => _savingExtra = true);
    try {
      await FirebaseFirestore.instance.collection('conductores').doc(uid).update({
        'dni': dni.isNotEmpty ? dni : FieldValue.delete(),
        'ruc': ruc.isNotEmpty ? ruc : FieldValue.delete(),
        'direccionFiscal': dir.isNotEmpty ? dir : FieldValue.delete(),
        if (ruc.isNotEmpty) 'rucValido': true,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      _snack('Datos actualizados');
    } catch (e) {
      _snack('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _savingExtra = false);
    }
  }

  // --------------------------------------------------------------------------
  // Despliega comentarios de calificaciones en un BottomSheet
  // --------------------------------------------------------------------------
  void _verComentarios(List<_RatingItem> items) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final alto = MediaQuery.of(context).size.height * 0.6;
        return SizedBox(
          height: alto.clamp(320.0, 560.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: items.isEmpty
                ? const Center(child: Text('Aún no tienes comentarios.'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 8),
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Stars(value: it.estrellas, size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (it.creadoEn != null)
                                  Text(
                                    '${it.creadoEn!.day.toString().padLeft(2, '0')}/'
                                    '${it.creadoEn!.month.toString().padLeft(2, '0')}/'
                                    '${it.creadoEn!.year}',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                  ),
                                Text(it.comentario),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // Permite cambiar o subir foto de perfil a Firebase Storage
  // Se actualiza el campo `fotoUrl` del documento en Firestore.
  // --------------------------------------------------------------------------
  Future<void> _changePhoto({
    required String uid,
    required String? currentUrl,
  }) async {
    if (_uploadingPhoto) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _uploadingPhoto = true);

      final ref = FirebaseStorage.instance.ref().child('conductores/$uid/perfil.jpg');
      await ref.putFile(File(picked.path), SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('conductores').doc(uid).update({
        'fotoUrl': url,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      _snack('Foto actualizada');
    } catch (e) {
      _snack('No se pudo actualizar la foto: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // Muestra notificaciones breves tipo SnackBar
  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // --------------------------------------------------------------------------
  // Construcción del widget principal
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text("No hay sesión activa")));
    }

    final docRef = FirebaseFirestore.instance.collection('conductores').doc(uid);

    final vista = Scaffold(
      appBar: AppBar(title: const Text("Mi Perfil de Conductor")),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text("No se encontró tu perfil de conductor"));
          }

          // ------------------------------------------------------------------
          // Extracción de datos del documento del conductor
          // ------------------------------------------------------------------
          final data = snap.data!.data() ?? {};
          final celular = (data['celular'] ?? '').toString();
          final fotoUrl = (data['fotoUrl'] ?? '').toString();
          final dni = (data['dni'] ?? '').toString();
          final ruc = (data['ruc'] ?? '').toString();
          final dir = (data['direccionFiscal'] ?? '').toString();

          // Carga inicial de datos en los controladores
          if (!_cargadoInicial) {
            _dniCtrl.text = dni;
            _rucCtrl.text = ruc;
            _direccionCtrl.text = dir;
            _cargadoInicial = true;

            _rucValido = ruc.isNotEmpty && _esRucValidoLocal(ruc);
            _ultimoRucValidado = _rucValido ? ruc : null;
          } else {
            _syncCtrl(_direccionCtrl, dir);
          }

          final licenciaNumero = (data['licenciaNumero'] ?? '-').toString();
          final licenciaCategoria = (data['licenciaCategoria'] ?? '-').toString();
          final vencimiento = dt(data['licenciaVencimiento']);

          final estadoNew = (data['estado'] ?? '').toString().toUpperCase();
          final estadoCompat = (data['estadoOperativo'] ?? '').toString().toUpperCase();
          final estado = estadoNew.isNotEmpty
              ? estadoNew
              : (estadoCompat.isNotEmpty ? estadoCompat : 'PENDIENTE');

          final verificado = data['verificado'] == true;
          final dAvg = toDoubleF(data['ratingPromedio']) ?? 0.0;
          final dCount = toIntF(data['ratingConteo']) ?? 0;
          final estadoColor = _estadoColor(estado);
          final idVehiculoActivo = (data['idVehiculoActivo'] ?? '').toString();

          // ------------------------------------------------------------------
          // Construcción visual de los bloques del perfil
          // ------------------------------------------------------------------
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Sección encabezado con nombre, foto, estado y verificación
              FutureBuilder<String>(
                future: _getDisplayName(conductorData: data, uid: uid),
                builder: (context, nameSnap) {
                  final nombreFinal = (nameSnap.data ?? '').trim();
                  return _HeaderPerfil(
                    nombre: nombreFinal.isEmpty ? 'Conductor' : nombreFinal,
                    celular: celular,
                    fotoUrl: fotoUrl.isEmpty ? null : fotoUrl,
                    verificado: verificado,
                    estado: estado,
                    estadoColor: estadoColor,
                    uploading: _uploadingPhoto,
                    onChangePhoto: () => _changePhoto(
                      uid: uid,
                      currentUrl: fotoUrl.isEmpty ? null : fotoUrl,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Bloque: Datos de identificación (DNI / RUC / Dirección)
              // Incluye validación de RUC visual y lógica
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Datos de identificación",
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _dniCtrl,
                        decoration: const InputDecoration(
                            labelText: 'DNI', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        focusNode: _rucFocus,
                        controller: _rucCtrl,
                        decoration: InputDecoration(
                          labelText: 'RUC',
                          border: const OutlineInputBorder(),
                          counterText: '',
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _rucCtrl,
                            builder: (_, value, __) {
                              final rucTexto =
                                  value.text.replaceAll(RegExp(r'\s+'), '').trim();
                              if (_validandoRuc) {
                                return const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                );
                              }
                              if (rucTexto.isEmpty || rucTexto.length < 11) {
                                return const Icon(Icons.info_outline);
                              }
                              if (_rucValido &&
                                  _ultimoRucValidado == rucTexto) {
                                return const Icon(Icons.verified,
                                    color: Colors.green);
                              }
                              return const Icon(Icons.error_outline,
                                  color: Colors.red);
                            },
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 11,
                        onChanged: (v) => _onRucChanged(uid, v),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _direccionCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Dirección Fiscal',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _savingExtra
                            ? null
                            : () {
                                final rucTexto = _rucCtrl.text
                                    .replaceAll(RegExp(r'\s+'), '')
                                    .trim();
                                final debeValidar = rucTexto.isNotEmpty &&
                                    (!_rucValido ||
                                        _ultimoRucValidado != rucTexto);
                                if (debeValidar) {
                                  _snack('Escribe los 11 dígitos del RUC y espera la confirmación antes de guardar.');
                                  return;
                                }
                                _guardarDatosExtras(uid);
                              },
                        icon: _savingExtra
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save),
                        label: Text(_savingExtra
                            ? 'Guardando...'
                            : 'Guardar cambios'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Tarjeta informativa: licencia del conductor (categoría y número)
              _card(
                leading: const Icon(Icons.badge, size: 40),
                title: "Licencia $licenciaCategoria",
                subtitle: "Número: $licenciaNumero",
              ),
              const SizedBox(height: 12),

              // Tarjeta informativa: fecha de vencimiento de la licencia
              _card(
                leading: const Icon(Icons.calendar_today, size: 40),
                title: "Vencimiento de licencia",
                subtitle: vencimiento != null
                    ? "${vencimiento.day}/${vencimiento.month}/${vencimiento.year}"
                    : "Sin fecha registrada",
              ),
              const SizedBox(height: 12),

              // Bloque de reputación: consume un stream en vivo de calificaciones
              // para mostrar promedio, conteo y acceso a comentarios
              StreamBuilder<_RatingBundle>(
                stream: _ratingStreamLive(uid),
                builder: (context, rSnap) {
                  final live = rSnap.data;
                  // Si existen valores denormalizados válidos en el documento del conductor,
                  // se priorizan; caso contrario, se usan los calculados en vivo.
                  final useDenorm = (dCount > 0 && dAvg > 0);
                  final avg = (useDenorm ? dAvg : (live?.avg ?? 0.0)).clamp(0.0, 5.0);
                  final cnt = useDenorm ? dCount : (live?.count ?? 0);
                  final comments = live?.comments ?? const <_RatingItem>[];

                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Reputación", style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _Stars(value: avg.isNaN ? 0 : avg.round(), size: 20),
                              Text("${avg.isNaN ? '0.0' : avg.toStringAsFixed(1)} / 5"),
                              Text("($cnt)", style: const TextStyle(color: Colors.black54)),
                              TextButton.icon(
                                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                label: const Text('Ver comentarios'),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: comments.isEmpty ? null : () => _verComentarios(comments),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            // Botón para sincronizar al documento del conductor el promedio y conteo
                            // calculados actualmente (útil para consultas sincrónicas posteriores)
                            child: TextButton.icon(
                              icon: _syncingRating
                                  ? const SizedBox(
                                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.sync),
                              label: const Text('Sincronizar rating'),
                              onPressed: (!_syncingRating)
                                  ? () => _syncDenormalizado(uid, avg.isNaN ? 0.0 : avg, cnt)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Si el conductor tiene un vehículo activo, se muestra una tarjeta resumen
              if (idVehiculoActivo.isNotEmpty)
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance.collection('vehiculos').doc(idVehiculoActivo).get(),
                  builder: (context, vehSnap) {
                    if (vehSnap.connectionState == ConnectionState.waiting) {
                      return const Card(
                        elevation: 2,
                        child: ListTile(
                          leading: Icon(Icons.directions_car),
                          title: Text('Cargando vehículo activo...'),
                        ),
                      );
                    }
                    final veh = vehSnap.data?.data() ?? {};
                    final placa = (veh['placa'] ?? '---').toString();
                    final marca = (veh['marca'] ?? '').toString();
                    final modelo = (veh['modelo'] ?? '').toString();

                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: ListTile(
                        leading: const Icon(Icons.directions_car, size: 40),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Vehículo: $placa",
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            // Indicador visual de vehículo activo
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.green.withOpacity(.3)),
                              ),
                              child: const Text(
                                'Activo',
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          [
                            if (marca.isNotEmpty) "Marca: $marca",
                            if (modelo.isNotEmpty) "Modelo: $modelo",
                          ].join(" • "),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );

    // Restablece el foco del campo RUC después de reconstrucciones,
    // útil cuando se actualiza el estado tras validaciones asíncronas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_holdFocusAfterRebuild) {
        _rucFocus.requestFocus();
        _holdFocusAfterRebuild = false;
        _rucCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _rucCtrl.text.length),
        );
      }
    });

    return vista;
  }

  // ----------------------------------------------------------------------------
  // Helper para crear tarjetas uniformes con ListTile
  // ----------------------------------------------------------------------------
  Widget _card({
    required Widget leading,
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    Widget? trailing,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        leading: leading,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitleWidget ?? (subtitle != null ? Text(subtitle) : null),
        trailing: trailing,
      ),
    );
  }
}

// ============================================================================
// Encabezado del perfil (foto, nombre, verificación y estado)
// ============================================================================
class _HeaderPerfil extends StatelessWidget {
  final String nombre;
  final String celular;
  final String? fotoUrl;
  final bool verificado;
  final String estado;
  final Color estadoColor;
  final bool uploading;
  final VoidCallback onChangePhoto;

  const _HeaderPerfil({
    required this.nombre,
    required this.celular,
    required this.fotoUrl,
    required this.verificado,
    required this.estado,
    required this.estadoColor,
    required this.uploading,
    required this.onChangePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Fondo con gradiente suave para destacar el bloque
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, .6, 1],
          colors: [Color(0xFFEEF5FF), Color(0xFFE6F3FF), Color(0xFFF5F9FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2ECF7)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Avatar con acción de cambiar foto
          Stack(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: (fotoUrl != null && fotoUrl!.isNotEmpty) ? NetworkImage(fotoUrl!) : null,
                child: (fotoUrl == null || fotoUrl!.isEmpty)
                    ? const Icon(Icons.person, size: 36, color: Colors.white)
                    : null,
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: InkWell(
                  onTap: uploading ? null : onChangePhoto,
                  child: Container(
                    decoration: BoxDecoration(
                      color: uploading ? Colors.grey.shade300 : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.06),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: uploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_camera, size: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),

          // Datos principales: nombre, celular, verificación y estado
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      nombre,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (verificado)
                    const Tooltip(
                      message: 'Cuenta verificada',
                      child: Icon(Icons.verified, color: Colors.blue, size: 20),
                    ),
                ]),
                const SizedBox(height: 4),
                if (celular.isNotEmpty)
                  Text(celular, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                const SizedBox(height: 6),
                // Estado del conductor (APROBADO, PENDIENTE, etc.) con etiqueta
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: estadoColor.withOpacity(.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: estadoColor.withOpacity(.3)),
                  ),
                  child: Text(estado, style: TextStyle(color: estadoColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Estructuras para el manejo de reputación (promedio, conteo y comentarios)
// ============================================================================
class _RatingBundle {
  final double avg;                  // Promedio de estrellas (0..5)
  final int count;                   // Total de calificaciones consideradas
  final List<_RatingItem> comments;  // Últimos comentarios
  const _RatingBundle({required this.avg, required this.count, required this.comments});
}

class _RatingItem {
  final int estrellas;        // Cantidad de estrellas de la calificación
  final String comentario;    // Texto del comentario
  final DateTime? creadoEn;   // Timestamp de creación (si existe)
  const _RatingItem({required this.estrellas, required this.comentario, this.creadoEn});
}

// ============================================================================
// Widget de estrellas (visual de 0 a 5) para mostrar calificaciones
// ============================================================================
class _Stars extends StatelessWidget {
  final int value; // Rango esperado 0..5
  final double size;
  const _Stars({required this.value, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = (i + 1) <= v;
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: size,
            color: filled ? Colors.amber : Colors.grey,
          ),
        );
      }),
    );
  }
}
