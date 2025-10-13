// lib/pantallas/auth/registro_screen.dart
// ============================================================================
// Pantalla: RegistroScreen
// Proyecto: Qorinti App – Registro de nuevos usuarios
// ----------------------------------------------------------------------------
// Descripción general:
// Esta pantalla permite a un usuario crear una cuenta nueva en la aplicación
// mediante su correo electrónico y una contraseña segura.
//
// Flujo de registro:
// 1. El usuario ingresa su nombre, correo y contraseña.
// 2. Acepta los términos y condiciones (obligatorio).
// 3. Firebase Authentication crea la cuenta con el correo y contraseña.
// 4. Se envía un correo de verificación automática al usuario.
// 5. Se guarda un documento en Firestore con los datos del nuevo usuario,
//    incluyendo fecha de creación, estado y metadatos de verificación.
// 6. Al finalizar, redirige al LoginScreen.
//
// Validaciones principales:
// - Todos los campos son obligatorios.
// - El correo debe tener formato válido.
// - La contraseña debe tener al menos 6 caracteres.
// - El usuario debe aceptar los términos antes de continuar.
// ----------------------------------------------------------------------------
// Tecnologías utilizadas:
// - FirebaseAuth: para crear cuentas de correo.
// - Cloud Firestore: para almacenar los datos del perfil.
// - Modelo Usuario: estructura base para persistir el usuario en la BD.
// - Flutter Material: interfaz visual adaptable a escritorio y móvil.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app_qorinti/app_router.dart';
import 'package:app_qorinti/modelos/usuario.dart'; 

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});
  static const route = AppRouter.registro;

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  // Clave del formulario y controladores de campos
  final _formulario = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Estado de los controles y validación
  bool _aceptoTerminos = false;
  bool _cargando = false;
  String? _error;

  // --------------------------------------------------------------------------
  // FUNCIÓN PRINCIPAL: REGISTRO DE USUARIO
  // --------------------------------------------------------------------------
  Future<void> _registrarUsuario() async {
    // Verifica que los campos sean válidos y que acepte los términos
    if (!_formulario.currentState!.validate() || !_aceptoTerminos) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Crea una cuenta en Firebase Authentication
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _correoCtrl.text.trim().toLowerCase(),
        password: _passCtrl.text.trim(),
      );

      // Envía un correo de verificación
      final user = cred.user!;
      await user.sendEmailVerification();

      // Crea el modelo de usuario para Firestore
      final usuario = Usuario.fromFirebase(
        user,
        rol: RolUsuario.USUARIO,
        metodoAuth: MetodoAuth.CORREO,
      ).copyWith(
        nombre: _nombreCtrl.text.trim(),
        correoVerificado: false,
        celularVerificado: user.phoneNumber != null,
      );

      // Guarda los datos en la colección "usuarios"
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario.id)
          .set({
        ...usuario.toMap(),
        'aceptoTerminos': _aceptoTerminos,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // Notifica y redirige a la pantalla de login
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Se envió un enlace de verificación a tu correo'),
        ));
        Navigator.pushReplacementNamed(context, AppRouter.login);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // --------------------------------------------------------------------------
  // INTERFAZ DE USUARIO
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formulario,
                child: ListView(
                  children: [
                    // Campo: nombre completo
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Nombre completo'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Requerido' : null,
                    ),

                    const SizedBox(height: 12),

                    // Campo: correo electrónico
                    TextFormField(
                      controller: _correoCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Correo electrónico'),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                    ),

                    const SizedBox(height: 12),

                    // Campo: contraseña
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Contraseña (mínimo 6 caracteres)'),
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'Muy corta' : null,
                    ),

                    const SizedBox(height: 12),

                    // Checkbox de aceptación de términos
                    CheckboxListTile(
                      value: _aceptoTerminos,
                      onChanged: (v) =>
                          setState(() => _aceptoTerminos = v ?? false),
                      title:
                          const Text('Acepto los términos y condiciones'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                    // Muestra mensaje de error si ocurre
                    if (_error != null)
                      Text(_error!, style: TextStyle(color: colores.error)),

                    const SizedBox(height: 12),

                    // Botón de registro
                    FilledButton(
                      onPressed: _cargando ? null : _registrarUsuario,
                      child: _cargando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Registrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
