// lib/pantallas/empresa/empresa_registro_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: EmpresaRegistroScreen
// Descripción general:
//   Permite al usuario registrar una nueva empresa en la plataforma Qorinti.
//   Valida el RUC ingresado a través del servicio SUNAT, genera una solicitud
//   pendiente de aprobación y crea los vínculos correspondientes entre:
//       - Empresa (colección `empresas`)
//       - Usuario-Empresa (colección `usuario_empresa`)
//       - Solicitud de Empresa (colección `empresa_solicitudes`)
//
//   Adicionalmente, permite subir un logo al almacenamiento Firebase Storage
//   y gestiona el control de empresas predeterminadas por usuario.
//
//   El flujo principal:
//     1. Validar RUC → Consultar API SUNAT → Obtener razón social y datos.
//     2. Registrar o actualizar datos en Firestore.
//     3. Asociar usuario actual como ADMIN o MIEMBRO.
//     4. Crear una solicitud de aprobación pendiente.
//
//   También previene duplicados y reactivaciones indebidas.
// -----------------------------------------------------------------------------

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app_qorinti/modelos/empresa.dart';
import 'package:app_qorinti/modelos/usuario_empresa.dart';
import 'package:app_qorinti/servicios/ruc_servicio.dart';

class EmpresaRegistroScreen extends StatefulWidget {
  static const route = '/empresa/registro';
  const EmpresaRegistroScreen({super.key});

  @override
  State<EmpresaRegistroScreen> createState() => _EmpresaRegistroScreenState();
}

class _EmpresaRegistroScreenState extends State<EmpresaRegistroScreen> {
  // --------------------------------------------------------------------------
  // Controladores de formulario
  // --------------------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();

  final _ruc = TextEditingController();
  final _razon = TextEditingController();
  final _direccion = TextEditingController();
  final _email = TextEditingController();
  final _telefono = TextEditingController();
  final _giro = TextEditingController();
  final _serieBoleta = TextEditingController();
  final _serieFactura = TextEditingController();

  bool _loading = false;      // Indica proceso activo (bloquea interfaz)
  bool _submitting = false;   // Previene envíos repetidos
  String? _msg;               // Mensaje de estado o error mostrado al usuario

  File? _logoFile;            // Imagen temporal del logo cargado
  String? _giroSugeridoApi;   // Giro obtenido desde API SUNAT

  @override
  void dispose() {
    // Liberar recursos de controladores al destruir la vista
    _ruc.dispose();
    _razon.dispose();
    _direccion.dispose();
    _email.dispose();
    _telefono.dispose();
    _giro.dispose();
    _serieBoleta.dispose();
    _serieFactura.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Permite seleccionar una imagen desde la galería (logo)
  // --------------------------------------------------------------------------
  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() => _logoFile = File(picked.path));
    }
  }

  // --------------------------------------------------------------------------
  // Sube el logo de empresa al Storage y devuelve su URL pública
  // --------------------------------------------------------------------------
  Future<String?> _uploadLogo(String ruc) async {
    if (_logoFile == null) return null;
    try {
      final ref = FirebaseStorage.instance.ref('logos_empresas/$ruc.png');
      await ref.putFile(_logoFile!);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error subiendo logo: $e');
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // Verifica si el usuario ya tiene una solicitud pendiente para el mismo RUC
  // --------------------------------------------------------------------------
  Future<bool> _tieneSolicitudPendiente(String ruc, String uid) async {
    final q = await FirebaseFirestore.instance
        .collection('empresa_solicitudes')
        .where('idEmpresa', isEqualTo: ruc)
        .where('creadoPor', isEqualTo: uid)
        .where('estado', isEqualTo: 'PENDIENTE')
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  // --------------------------------------------------------------------------
  // Desactiva otros registros predeterminados del mismo usuario
  // para garantizar unicidad del campo "predeterminado".
  // --------------------------------------------------------------------------
  Future<void> _marcarUnicoPredeterminado({
    required String idUsuario,
    required WriteBatch batch,
    required CollectionReference<Map<String, dynamic>> ueRef,
  }) async {
    final otrosPred = await ueRef
        .where('idUsuario', isEqualTo: idUsuario)
        .where('predeterminado', isEqualTo: true)
        .get();
    for (final d in otrosPred.docs) {
      batch.update(d.reference, {
        'predeterminado': false,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    }
  }

  // --------------------------------------------------------------------------
  // Lógica central del registro de empresa y creación de solicitud
  // --------------------------------------------------------------------------
  Future<void> _validarYGuardar() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final rucTrim = _ruc.text.trim();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    setState(() {
      _loading = true;
      _submitting = true;
      _msg = null;
    });

    try {
      // Paso 1: Validar si ya existe solicitud pendiente
      if (await _tieneSolicitudPendiente(rucTrim, uid)) {
        setState(() {
          _msg = 'Ya tienes una solicitud pendiente para este RUC.';
        });
        return;
      }

      // Paso 2: Validar RUC mediante API externa (SUNAT)
      final api = RucServicio();
      final data = await api.validarRuc(rucTrim);

      if (data == null) {
        setState(() => _msg = 'RUC no válido o no encontrado en la SUNAT.');
        return;
      }

      // Procesar información obtenida de la API
      final razonApi = (data['razonSocial'] ?? data['nombre']) as String?;
      final razonFinal = (razonApi?.trim().isNotEmpty ?? false)
          ? razonApi!.trim()
          : (_razon.text.trim().isNotEmpty ? _razon.text.trim() : 'SIN RAZON SOCIAL');

      _razon.text = razonFinal;
      _direccion.text = (data['direccion'] ?? '').toString();
      _giroSugeridoApi = (data['actividad'] ?? '').toString().trim();

      if (_giro.text.trim().isEmpty && _giroSugeridoApi!.isNotEmpty) {
        _giro.text = _giroSugeridoApi!;
      }

      // Paso 3: Configurar referencias a colecciones Firestore
      final fs = FirebaseFirestore.instance;
      final empresasRef = fs.collection('empresas');
      final ueRef = fs.collection('usuario_empresa');
      final solicitudesRef = fs.collection('empresa_solicitudes');
      final empresaDocRef = empresasRef.doc(rucTrim);

      final existing = await empresaDocRef.get();
      final batch = fs.batch();
      final logoUrl = await _uploadLogo(rucTrim);

      // ----------------------------------------------------------------------
      // Caso A: Empresa no existe → crear nueva
      // ----------------------------------------------------------------------
      if (!existing.exists) {
        final empresa = Empresa(
          razonSocial: razonFinal,
          ruc: rucTrim,
          estado: "PENDIENTE",
          direccionFiscal: _direccion.text.trim().isEmpty ? null : _direccion.text.trim(),
          emailFacturacion: _email.text.trim().isEmpty ? null : _email.text.trim(),
          telefono: _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
          giroNegocio: _giro.text.trim().isNotEmpty
              ? _giro.text.trim()
              : (_giroSugeridoApi?.isNotEmpty ?? false ? _giroSugeridoApi : 'Sin especificar') as String,
          logoUrl: logoUrl,
          serieBoleta: _serieBoleta.text.trim().isEmpty ? null : _serieBoleta.text.trim(),
          serieFactura: _serieFactura.text.trim().isEmpty ? null : _serieFactura.text.trim(),
          creadoEn: DateTime.now(),
          actualizadoEn: DateTime.now(),
        );

        batch.set(empresaDocRef, {
          ...empresa.toMap(),
          'creadoEn': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });

        // Asegura unicidad de empresa predeterminada
        await _marcarUnicoPredeterminado(idUsuario: uid, batch: batch, ueRef: ueRef);

        // Vincular usuario actual como ADMIN pendiente
        final nuevoUeRef = ueRef.doc();
        final usuarioEmpresa = UsuarioEmpresa(
          id: nuevoUeRef.id,
          idUsuario: uid,
          idEmpresa: rucTrim,
          rol: "ADMIN",
          estadoMembresia: "PENDIENTE",
        );
        batch.set(nuevoUeRef, {
          ...usuarioEmpresa.toMap(),
          'creadoEn': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });

        // Crear solicitud pendiente
        final solicitudRef = solicitudesRef.doc('${rucTrim}_${uid}_${DateTime.now().millisecondsSinceEpoch}');
        batch.set(solicitudRef, {
          'idEmpresa': rucTrim,
          'razonSocial': razonFinal,
          'creadoPor': uid,
          'estado': 'PENDIENTE',
          'usuarioEmpresaId': nuevoUeRef.id,
          'creadoEn': FieldValue.serverTimestamp(),
        });

        await batch.commit();
        setState(() => _msg = 'Empresa registrada. Quedará en revisión por Qorinti.');
        return;
      }

      // ----------------------------------------------------------------------
      // Caso B: Empresa existente
      // ----------------------------------------------------------------------
      final estadoEmpresa = (existing.data()?['estado'] ?? 'PENDIENTE')
          .toString()
          .toUpperCase();

      final vinculoQuery = await ueRef
          .where('idEmpresa', isEqualTo: rucTrim)
          .where('idUsuario', isEqualTo: uid)
          .limit(1)
          .get();

      // Si la empresa fue RECHAZADA, se reactiva y genera nueva solicitud
      if (estadoEmpresa == 'RECHAZADA') {
        if (await _tieneSolicitudPendiente(rucTrim, uid)) {
          setState(() => _msg = 'Ya tienes una solicitud pendiente para este RUC.');
          return;
        }

        // Actualiza empresa a estado PENDIENTE nuevamente
        batch.update(empresaDocRef, {
          'estado': 'PENDIENTE',
          'razonSocial': razonFinal,
          if (_direccion.text.trim().isNotEmpty) 'direccionFiscal': _direccion.text.trim(),
          if (_email.text.trim().isNotEmpty) 'emailFacturacion': _email.text.trim(),
          if (_telefono.text.trim().isNotEmpty) 'telefono': _telefono.text.trim(),
          if (_giro.text.trim().isNotEmpty) 'giroNegocio': _giro.text.trim(),
          if (_serieBoleta.text.trim().isNotEmpty) 'serieBoleta': _serieBoleta.text.trim(),
          if (_serieFactura.text.trim().isNotEmpty) 'serieFactura': _serieFactura.text.trim(),
          if (logoUrl != null) 'logoUrl': logoUrl,
          'actualizadoEn': FieldValue.serverTimestamp(),
        });

        // Si el usuario ya tenía vínculo previo
        if (vinculoQuery.docs.isNotEmpty) {
          await _marcarUnicoPredeterminado(idUsuario: uid, batch: batch, ueRef: ueRef);
          batch.update(vinculoQuery.docs.first.reference, {
            'rol': 'ADMIN',
            'estadoMembresia': 'PENDIENTE',
            'predeterminado': true,
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
        } else {
          // Crea nuevo vínculo si no existía
          await _marcarUnicoPredeterminado(idUsuario: uid, batch: batch, ueRef: ueRef);
          final nuevoUeRef = ueRef.doc();
          batch.set(nuevoUeRef, {
            'idUsuario': uid,
            'idEmpresa': rucTrim,
            'rol': 'ADMIN',
            'estadoMembresia': 'PENDIENTE',
            'comprobantePreferido': 'FACTURA',
            'requiereAprobacion': false,
            'predeterminado': true,
            'creadoEn': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
        }

        // Nueva solicitud
        final solicitudRef = solicitudesRef.doc('${rucTrim}_${uid}_${DateTime.now().millisecondsSinceEpoch}');
        batch.set(solicitudRef, {
          'idEmpresa': rucTrim,
          'razonSocial': razonFinal,
          'creadoPor': uid,
          'estado': 'PENDIENTE',
          'usuarioEmpresaId': vinculoQuery.docs.isNotEmpty ? vinculoQuery.docs.first.id : null,
          'creadoEn': FieldValue.serverTimestamp(),
        });

        await batch.commit();
        setState(() => _msg = 'La empresa estaba RECHAZADA. Se reactivó y se envió nueva solicitud.');
        return;
      }

      // ----------------------------------------------------------------------
      // Caso C: Empresa ya existe y usuario ya vinculado
      // ----------------------------------------------------------------------
      if (vinculoQuery.docs.isNotEmpty) {
        final vData = vinculoQuery.docs.first.data();
        final estadoV = (vData['estadoMembresia'] ?? 'PENDIENTE').toString();
        setState(() => _msg = 'Ya existe relación con esta empresa (estado: $estadoV).');
        return;
      }

      // ----------------------------------------------------------------------
      // Caso D: Empresa existente sin vínculo del usuario actual
      // ----------------------------------------------------------------------
      await _marcarUnicoPredeterminado(idUsuario: uid, batch: batch, ueRef: ueRef);

      final nuevoUeRef = ueRef.doc();
      batch.set(nuevoUeRef, {
        'idUsuario': uid,
        'idEmpresa': rucTrim,
        'rol': 'MIEMBRO',
        'estadoMembresia': 'PENDIENTE',
        'comprobantePreferido': 'FACTURA',
        'requiereAprobacion': false,
        'predeterminado': true,
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      final solicitudRef = solicitudesRef.doc('${rucTrim}_${uid}_${DateTime.now().millisecondsSinceEpoch}');
      batch.set(solicitudRef, {
        'idEmpresa': rucTrim,
        'razonSocial': razonFinal,
        'creadoPor': uid,
        'estado': 'PENDIENTE',
        'usuarioEmpresaId': nuevoUeRef.id,
        'creadoEn': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      setState(() => _msg = 'Tu solicitud para unirte a la empresa fue enviada.');
    } catch (e) {
      setState(() => _msg = 'Error al registrar: $e');
    } finally {
      setState(() {
        _loading = false;
        _submitting = false;
      });
    }
  }

  // --------------------------------------------------------------------------
  // Interfaz visual del formulario de registro de empresa
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Empresa')),
      body: AbsorbPointer(
        absorbing: _loading,
        child: Stack(
          children: [
            // Formulario principal
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Text(
                      'Completa la información de tu empresa para solicitar su registro en Qorinti.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),

                    // Campos de texto
                    TextFormField(
                      controller: _ruc,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'RUC',
                        prefixIcon: Icon(Icons.business),
                        hintText: '11 dígitos',
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Ingrese RUC';
                        if (!RegExp(r'^\d{11}$').hasMatch(v)) return 'Debe tener 11 dígitos';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _razon,
                      decoration: const InputDecoration(
                        labelText: 'Razón Social',
                        prefixIcon: Icon(Icons.badge),
                      ),
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _direccion,
                      decoration: const InputDecoration(
                        labelText: 'Dirección Fiscal',
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email Facturación',
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _telefono,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Campo con sugerencia de giro desde la API
                    TextFormField(
                      controller: _giro,
                      decoration: InputDecoration(
                        labelText: 'Giro de negocio',
                        prefixIcon: const Icon(Icons.store),
                        suffixIcon: (_giroSugeridoApi != null &&
                                _giroSugeridoApi!.isNotEmpty &&
                                _giro.text.trim() != _giroSugeridoApi)
                            ? IconButton(
                                tooltip: 'Usar sugerido de SUNAT',
                                icon: const Icon(Icons.auto_awesome),
                                onPressed: () => setState(() => _giro.text = _giroSugeridoApi!),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Series opcionales
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _serieBoleta,
                            decoration: const InputDecoration(
                              labelText: 'Serie Boleta (opcional)',
                              prefixIcon: Icon(Icons.confirmation_number),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _serieFactura,
                            decoration: const InputDecoration(
                              labelText: 'Serie Factura (opcional)',
                              prefixIcon: Icon(Icons.receipt_long),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Selector de logo (imagen opcional)
                    InkWell(
                      onTap: _pickLogo,
                      child: Container(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _logoFile == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.upload, size: 40, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text("Subir logo (opcional)"),
                                ],
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(_logoFile!, fit: BoxFit.cover, width: double.infinity),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Mensaje informativo
                    if (_msg != null)
                      Text(
                        _msg!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _msg!.startsWith('Error') ? Colors.red : Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Botón principal
                    FilledButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      onPressed: _validarYGuardar,
                      label: const Text('Enviar solicitud'),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Indicador de carga
            if (_loading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.05),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
