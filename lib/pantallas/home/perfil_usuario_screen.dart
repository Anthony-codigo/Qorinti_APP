// lib/pantallas/usuario/perfil_usuario_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: PerfilUsuarioScreen
// Descripción general:
//   Permite al usuario visualizar y editar su información personal almacenada en
//   Firestore. Incluye carga, actualización y eliminación de la foto de perfil.
//
//   Esta pantalla integra servicios de:
//     • FirebaseAuth → Obtener UID del usuario actual.
//     • Cloud Firestore → Leer y actualizar datos de perfil (nombre, dirección, etc.).
//     • Firebase Storage → Subir o eliminar foto de perfil.
//     • ImagePicker → Seleccionar imágenes locales desde la galería.
//
//   Funcionalidades principales:
//     - Cargar datos del usuario autenticado desde Firestore.
//     - Editar nombre, teléfono y dirección.
//     - Subir, cambiar o eliminar la foto de perfil.
//     - Mostrar método de autenticación (Google, correo, etc.).
//     - Validar campos y actualizar los cambios en la nube.
// -----------------------------------------------------------------------------

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app_qorinti/modelos/usuario.dart';

class PerfilUsuarioScreen extends StatefulWidget {
  const PerfilUsuarioScreen({super.key});

  @override
  State<PerfilUsuarioScreen> createState() => _PerfilUsuarioScreenState();
}

class _PerfilUsuarioScreenState extends State<PerfilUsuarioScreen> {
  // --------------------------------------------------------------------------
  // Controladores y variables de estado
  // --------------------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  bool _cargando = false;          // Indica si hay una operación en curso
  Usuario? _usuario;               // Modelo del usuario actual
  String? _fotoUrl;                // URL de la foto de perfil almacenada
  File? _imagenSeleccionada;       // Imagen temporal seleccionada localmente

  final ImagePicker _picker = ImagePicker(); // Selector de imágenes

  // --------------------------------------------------------------------------
  // Ciclo de vida: al iniciar, carga el perfil desde Firestore
  // --------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _cargarUsuario();
  }

  // --------------------------------------------------------------------------
  // Obtiene el usuario actual desde Firestore y llena los campos del formulario
  // --------------------------------------------------------------------------
  Future<void> _cargarUsuario() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snap =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final user = Usuario.fromMap(data, id: uid);

    setState(() {
      _usuario = user;
      _nombreCtrl.text = user.nombre ?? '';
      _telefonoCtrl.text = user.telefono ?? '';
      _direccionCtrl.text = user.direccion ?? '';
      _fotoUrl = user.fotoUrl;
    });
  }

  // --------------------------------------------------------------------------
  // Permite seleccionar una imagen desde la galería local
  // --------------------------------------------------------------------------
  Future<void> _seleccionarImagen() async {
    final XFile? picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() => _imagenSeleccionada = File(picked.path));
    }
  }

  // --------------------------------------------------------------------------
  // Sube la imagen seleccionada a Firebase Storage y devuelve la URL pública
  // --------------------------------------------------------------------------
  Future<String?> _subirImagen(File imagen) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;

      final ref = FirebaseStorage.instance
          .ref()
          .child('usuarios/$uid/foto_perfil.jpg');

      final upload = await ref.putFile(imagen);
      final url = await upload.ref.getDownloadURL();
      return url;
    } catch (e) {
      debugPrint("Error subiendo imagen: $e");
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // Elimina la foto de perfil actual tanto en Storage como en Firestore
  // --------------------------------------------------------------------------
  Future<void> _eliminarFoto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _fotoUrl == null || _fotoUrl!.isEmpty) return;

    // Confirmación antes de eliminar
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Eliminar foto de perfil"),
        content:
            const Text("¿Seguro que deseas eliminar tu foto de perfil actual?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      setState(() => _cargando = true);

      // Eliminación en Storage
      final ref =
          FirebaseStorage.instance.ref().child('usuarios/$uid/foto_perfil.jpg');
      await ref.delete();

      // Actualización en Firestore
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .update({
        'fotoUrl': null,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _fotoUrl = null;
          _imagenSeleccionada = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑️ Foto eliminada correctamente')),
        );
      }
    } catch (e) {
      debugPrint('Error al eliminar foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // --------------------------------------------------------------------------
  // Guarda los cambios realizados (texto y/o foto nueva) en Firestore
  // --------------------------------------------------------------------------
  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _cargando = true);

    try {
      String? nuevaUrl = _fotoUrl;

      // Subir imagen nueva si fue seleccionada
      if (_imagenSeleccionada != null) {
        nuevaUrl = await _subirImagen(_imagenSeleccionada!);
        if (nuevaUrl == null) {
          throw Exception("No se pudo subir la imagen");
        }
      }

      // Actualizar campos en Firestore
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'nombre': _nombreCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'direccion': _direccionCtrl.text.trim(),
        'fotoUrl': nuevaUrl,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado correctamente')),
        );
        Navigator.pop(context); // Regresa a la pantalla anterior
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // --------------------------------------------------------------------------
  // Construcción visual del formulario de perfil
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Estado inicial mientras se carga el usuario
    if (_usuario == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final metodo = _usuario!.metodoAuth.code;
    final correo = _usuario!.correo;

    return Scaffold(
      appBar: AppBar(title: const Text('Mi Perfil')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // ----------------------------------------------------------
                // FOTO DE PERFIL (vista + botón cámara + eliminar)
                // ----------------------------------------------------------
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: cs.primaryContainer,
                      backgroundImage: _imagenSeleccionada != null
                          ? FileImage(_imagenSeleccionada!)
                          : (_fotoUrl != null && _fotoUrl!.isNotEmpty)
                              ? NetworkImage(_fotoUrl!) as ImageProvider
                              : null,
                      child: (_fotoUrl == null || _fotoUrl!.isEmpty) &&
                              _imagenSeleccionada == null
                          ? Icon(Icons.person, size: 60, color: cs.primary)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 4,
                      child: InkWell(
                        onTap: _cargando ? null : _seleccionarImagen,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),

                // Opción para eliminar foto si existe una previa
                if (_fotoUrl != null && _fotoUrl!.isNotEmpty)
                  TextButton.icon(
                    onPressed: _cargando ? null : _eliminarFoto,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text("Eliminar foto de perfil"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                  ),

                const SizedBox(height: 24),

                // ----------------------------------------------------------
                // FORMULARIO DE DATOS EDITABLES
                // ----------------------------------------------------------
                TextFormField(
                  controller: _nombreCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Nombre completo'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _telefonoCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Teléfono (opcional)'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _direccionCtrl,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
                const SizedBox(height: 20),

                // ----------------------------------------------------------
                // DATOS NO EDITABLES (correo y método de autenticación)
                // ----------------------------------------------------------
                ListTile(
                  leading: const Icon(Icons.email),
                  title: Text(correo),
                  subtitle: Text('Método: ${metodo.toUpperCase()}'),
                  tileColor: cs.surfaceVariant.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                const SizedBox(height: 24),

                // ----------------------------------------------------------
                // BOTÓN DE GUARDADO
                // ----------------------------------------------------------
                FilledButton.icon(
                  onPressed: _cargando ? null : _guardarCambios,
                  icon: _cargando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Guardar cambios'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
