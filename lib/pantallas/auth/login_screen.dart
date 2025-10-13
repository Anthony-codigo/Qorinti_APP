// lib/pantallas/auth/login_screen.dart
// ============================================================================
// Pantalla: LoginScreen
// Proyecto: Qorinti App – Autenticación principal
// ----------------------------------------------------------------------------
// Descripción general:
// Esta pantalla permite al usuario autenticarse mediante tres métodos:
//
// 1. Correo electrónico y contraseña.
// 2. Cuenta de Google (Firebase + GoogleSignIn).
// 3. Número de celular (redirige a LoginPhoneScreen).
//
// Además, crea o actualiza automáticamente el documento del usuario en
// Firestore con su información básica, estado y rol.  
//
// Si la autenticación es exitosa, redirige al enrutador principal (AppRouter.auth),
// que a su vez gestiona la navegación según el rol del usuario (usuario normal o admin).
// ----------------------------------------------------------------------------
// Tecnologías utilizadas:
// - Firebase Authentication: email/password y Google Sign-In.
// - Cloud Firestore: almacenamiento del perfil de usuario.
// - GoogleSignIn Plugin: para móviles (Android/iOS).
// - Flutter Material: para diseño de UI.
// ============================================================================

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:app_qorinti/app_router.dart';
import 'package:app_qorinti/modelos/usuario.dart';
import 'login_phone_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  static const route = AppRouter.login;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controladores del formulario
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  // Estado de carga y error
  bool _loading = false;
  String? _error;

  // Identificador del cliente OAuth de Google (modo web)
  static const _webClientId =
      "372155608327-s042trdpc4f01qkbskoj99qttlbqo4b0.apps.googleusercontent.com";

  // Paleta de colores usada en la interfaz
  static const _brandBlue = Color(0xFF2A6DF4);
  static const _ink = Color(0xFF0F172A);
  static const _inkSoft = Color(0xFF475569);

  // URLs de recursos visuales
  static const _logoUrl =
      'https://firebasestorage.googleapis.com/v0/b/dbchavez05.firebasestorage.app/o/imagen_qorinti%2FImagen%20de%20WhatsApp%202025-10-04%20a%20las%2022.25.35_ac943c72.jpg?alt=media&token=553a2052-b211-4b25-86be-9ad780cc3373';
  static const _googlePng =
      'https://developers.google.com/identity/images/g-logo.png';

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // FUNCIONES DE PERSISTENCIA DE USUARIO EN FIRESTORE
  // --------------------------------------------------------------------------

  /// Guarda o actualiza el usuario en Firestore con los datos proporcionados.
  Future<void> _guardarUsuario(Usuario usuario) async {
    final ref = FirebaseFirestore.instance.collection('usuarios').doc(usuario.id);
    final doc = await ref.get();

    // Si el documento no existe, crea uno nuevo
    if (!doc.exists) {
      await ref.set({
        ...usuario.toMap()
          ..remove('creadoEn')
          ..remove('actualizadoEn')
          ..remove('ultimoLogin'),
        'rol': RolUsuario.USUARIO.code,
        'estado': EstadoUsuario.ACTIVO.code,
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'ultimoLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      // Si ya existe, actualiza los campos modificados
      final data = usuario.toMap()
        ..remove('rol')
        ..remove('creadoEn');
      await ref.set({
        ...data,
        'ultimoLogin': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Registra la sesión iniciada con Google en Firestore.
  Future<void> _postGoogleSignIn(User user) async {
    await _guardarUsuario(
      Usuario.fromFirebase(
        user,
        metodoAuth: MetodoAuth.GOOGLE,
        rol: RolUsuario.USUARIO,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // AUTENTICACIÓN CON CORREO Y CONTRASEÑA
  // --------------------------------------------------------------------------

  Future<void> _loginEmail() async {
    final scope = FocusScope.of(context);
    if (scope.hasFocus) scope.unfocus();
    if (!_form.currentState!.validate()) return;

    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );

      await _guardarUsuario(Usuario.fromFirebase(
        cred.user!, metodoAuth: MetodoAuth.CORREO, rol: RolUsuario.USUARIO));

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRouter.auth);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Error de autenticación');
    } catch (e) {
      if (mounted) setState(() => _error = 'Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------------------------------------------------------------------------
  // AUTENTICACIÓN CON GOOGLE (FIREBASE AUTH)
  // --------------------------------------------------------------------------

  Future<void> _loginGoogle() async {
    final scope = FocusScope.of(context);
    if (scope.hasFocus) scope.unfocus();

    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      if (kIsWeb) {
        // Flujo de autenticación para navegadores web
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        final userCred = await FirebaseAuth.instance.signInWithProvider(provider);
        await _postGoogleSignIn(userCred.user!);
      } else if (Platform.isAndroid || Platform.isIOS) {
        // Flujo nativo para Android/iOS usando el plugin GoogleSignIn
        await _loginGoogle_conPlugin();
      } else {
        // Flujo alternativo para otros entornos (desktop, etc.)
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        final userCred = await FirebaseAuth.instance.signInWithProvider(provider);
        await _postGoogleSignIn(userCred.user!);
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRouter.auth);

    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Error de autenticación con Google');
    } catch (e) {
      final m = e.toString().toLowerCase();
      if (!(m.contains('canceled') || m.contains('cancelled'))) {
        if (mounted) setState(() => _error = 'Error inesperado: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------------------------------------------------------------------------
  // MÉTODO INTERNO: LOGIN GOOGLE EN DISPOSITIVOS MÓVILES
  // --------------------------------------------------------------------------

  Future<void> _loginGoogle_conPlugin() async {
    try {
      final signIn = GoogleSignIn.instance;
      await signIn.initialize(serverClientId: _webClientId);
      await signIn.attemptLightweightAuthentication();

      final account = await signIn.authenticate();
      final gauth = await account.authentication;
      final idToken = gauth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError(
          'No se obtuvo idToken de Google. Revisa Web Client ID/SHA y google-services.json.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      await _postGoogleSignIn(userCred.user!);

    } on FirebaseAuthException catch (_) {
      rethrow; 
    } catch (e) {
      final m = e.toString().toLowerCase();
      if (m.contains('canceled') || m.contains('cancelled')) return; 
      rethrow;
    }
  }

  // --------------------------------------------------------------------------
  // INTERFAZ DE USUARIO
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tecladoAbierto = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEFF2F6), Color(0xFFE3E9F2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Form(
                  key: _form,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: tecladoAbierto ? 48 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        // Imagen o logo principal
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(color: Colors.white.withOpacity(.10)),
                                Image.network(
                                  _logoUrl,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (c, w, p) {
                                    if (p == null) return w;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: p.expectedTotalBytes != null
                                            ? p.cumulativeBytesLoaded /
                                                (p.expectedTotalBytes ?? 1)
                                            : null,
                                        strokeWidth: 2,
                                      ),
                                    );
                                  },
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Text(
                                      'QORINTI',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            color: _ink,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Formulario principal
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.98),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 18,
                                offset: Offset(0, 12),
                              ),
                            ],
                            border: Border.all(color: Color(0xFFE8EDF5), width: 1),
                          ),
                          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                          child: Column(
                            children: [
                              Text(
                                'Bienvenido',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      color: _ink,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Inicia sesión para continuar',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: _inkSoft,
                                    ),
                              ),
                              const SizedBox(height: 18),

                              // Campo: Correo electrónico
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Correo',
                                  prefixIcon: const Icon(Icons.email_outlined),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                              ),

                              const SizedBox(height: 12),

                              // Campo: Contraseña
                              TextFormField(
                                controller: _pass,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _loading ? null : _loginEmail(),
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                              ),

                              const SizedBox(height: 12),

                              // Mensaje de error (si existe)
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(color: cs.error),
                                    textAlign: TextAlign.center,
                                  ),
                                ),

                              // Botón principal de inicio de sesión
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _loading ? null : _loginEmail,
                                  icon: const Icon(Icons.login),
                                  label: _loading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Entrar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _brandBlue,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Separador visual
                              Row(
                                children: [
                                  Expanded(child: Divider(color: Colors.grey.shade300)),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('o'),
                                  ),
                                  Expanded(child: Divider(color: Colors.grey.shade300)),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Botón: Google Sign-In
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _loading ? null : _loginGoogle,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    side: BorderSide(color: Colors.grey.shade300),
                                    foregroundColor: _ink,
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Image.network(
                                        _googlePng,
                                        width: 18,
                                        height: 18,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.account_circle_outlined, size: 18),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text('Entrar con Google'),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Botón: Iniciar sesión con teléfono
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _loading
                                      ? null
                                      : () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const LoginPhoneScreen(),
                                            ),
                                          ),
                                  icon: const Icon(Icons.phone_iphone),
                                  label: const Text('Entrar con Celular'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    side: BorderSide(color: Colors.grey.shade300),
                                    foregroundColor: _ink,
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Enlace: Crear nueva cuenta
                              TextButton(
                                onPressed: () => Navigator.pushNamed(context, AppRouter.registro),
                                child: const Text('Crear cuenta'),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Pie de la pantalla
                        Text(
                          'Transportes Qorinti',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: _inkSoft,
                                letterSpacing: .6,
                              ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
