// lib/pantallas/auth/login_phone_screen.dart
// ============================================================================
// Pantalla: LoginPhoneScreen
// Proyecto: Qorinti App – Autenticación por número de celular
// ----------------------------------------------------------------------------
// Descripción general:
// Esta pantalla permite a los usuarios autenticarse mediante su número
// telefónico utilizando Firebase Authentication con verificación por SMS.
// Incluye soporte para varios países, manejo de códigos de prueba, y
// creación automática del perfil del usuario en Firestore.
//
// Flujo general:
// 1. El usuario ingresa su número de celular y selecciona el país.
// 2. Firebase envía un código SMS al número proporcionado.
// 3. El usuario ingresa el código recibido (o se usa uno predefinido de prueba).
// 4. Firebase autentica al usuario.
// 5. Si el usuario es nuevo, se crea su documento en la colección `usuarios`.
// 6. Según su rol en Firestore (USUARIO o ADMIN), se redirige a la pantalla adecuada.
// ----------------------------------------------------------------------------
// Tecnologías utilizadas:
// - Firebase Authentication (verifyPhoneNumber, SMS).
// - Cloud Firestore (persistencia del perfil del usuario).
// - Flutter Material (interfaz).
// - app_qorinti/modelos/usuario.dart (modelo estándar de usuario).
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_qorinti/app_router.dart';
import 'package:app_qorinti/modelos/usuario.dart';

class LoginPhoneScreen extends StatefulWidget {
  const LoginPhoneScreen({super.key});

  @override
  State<LoginPhoneScreen> createState() => _LoginPhoneScreenState();
}

class _LoginPhoneScreenState extends State<LoginPhoneScreen> {
  // Controladores y estado de UI
  final _phoneController = TextEditingController();
  String _countryCode = '+51';
  bool _loading = false;
  String? _error;

  // Lista de prefijos internacionales disponibles
  final _paises = {
    '🇵🇪 Perú': '+51',
    '🇲🇽 México': '+52',
    '🇨🇴 Colombia': '+57',
    '🇨🇱 Chile': '+56',
    '🇦🇷 Argentina': '+54',
  };

  // Números de prueba con códigos predefinidos (para entornos de desarrollo)
  final Map<String, String> numerosPrueba = const {
    "+51999999999": "123456",
    "+16505551234": "123456",
  };

  // Limpia el número ingresado y lo normaliza con el código del país
  String _normalizarNumero(String numero) {
    final limpio = numero.replaceAll(RegExp(r"\s+|-"), "");
    return limpio.startsWith("+") ? limpio : _countryCode + limpio;
  }

  // --------------------------------------------------------------------------
  // FUNCIÓN PRINCIPAL: Autenticación por teléfono
  // --------------------------------------------------------------------------

  Future<void> _loginPhone() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final fullPhone = _normalizarNumero(_phoneController.text.trim());

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhone,
        timeout: const Duration(seconds: 60),

        // Autenticación automática en algunos dispositivos (Android)
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
            await _savePhoneUser(userCred);
          } catch (e) {
            if (mounted) setState(() => _error = e.toString());
          }
        },

        // Error durante el envío o verificación
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) setState(() => _error = e.message ?? 'Error desconocido');
        },

        // Se envió el código SMS correctamente
        codeSent: (String verificationId, int? resendToken) async {
          // Usa un código predefinido si el número está en la lista de prueba
          final preset = numerosPrueba[_normalizarNumero(_phoneController.text.trim())];
          final smsCode = preset ?? await _askSmsCode(context);

          if (smsCode == null) {
            if (mounted) setState(() => _error = "Operación cancelada");
            return;
          }

          try {
            final cred = PhoneAuthProvider.credential(
              verificationId: verificationId,
              smsCode: smsCode.trim(),
            );
            final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
            await _savePhoneUser(userCred);
          } on FirebaseAuthException catch (e) {
            if (mounted) setState(() => _error = e.message ?? 'Código inválido');
          } catch (e) {
            if (mounted) setState(() => _error = e.toString());
          }
        },

        // Se agotó el tiempo de espera para la verificación automática
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------------------------------------------------------------------------
  // REDIRECCIÓN SEGÚN ROL
  // --------------------------------------------------------------------------

  Future<void> _goAccordingToRole(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      final String rol = (data['rol'] as String?)?.toUpperCase() ?? '';
      final bool isAdmin = rol == 'SUPERADMIN' || rol == 'ADMIN';

      if (!mounted) return;

      // Redirección según rol: panel admin o pantalla principal
      Navigator.pushReplacementNamed(
        context,
        isAdmin ? AppRouter.adminPanel : AppRouter.home,
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRouter.home);
    }
  }

  // --------------------------------------------------------------------------
  // GUARDA O ACTUALIZA EL USUARIO EN FIRESTORE
  // --------------------------------------------------------------------------

  Future<void> _savePhoneUser(UserCredential userCred) async {
    final user = userCred.user;
    if (user == null) {
      if (mounted) setState(() => _error = "No se pudo iniciar sesión");
      return;
    }

    final String uid = user.uid; 

    // Crea el objeto Usuario con datos básicos y método de autenticación CELULAR
    final usuario = Usuario.fromFirebase(
      user,
      rol: RolUsuario.USUARIO,
      metodoAuth: MetodoAuth.CELULAR,
    );

    final doc = FirebaseFirestore.instance.collection('usuarios').doc(uid);
    final snap = await doc.get();

    // Si es un usuario nuevo, se crea el documento completo
    if (!snap.exists) {
      await doc.set({
        ...usuario.toMap()
          ..remove('creadoEn')
          ..remove('actualizadoEn')
          ..remove('ultimoLogin'),
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'ultimoLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } 
    // Si ya existe, solo se actualizan los campos relacionados al celular
    else {
      await doc.set({
        'telefono': usuario.telefono ?? user.phoneNumber,
        'celularVerificado': true,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'ultimoLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (!mounted) return;
    await _goAccordingToRole(uid);
  }

  // --------------------------------------------------------------------------
  // DIÁLOGO PARA INGRESAR EL CÓDIGO SMS
  // --------------------------------------------------------------------------

  Future<String?> _askSmsCode(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Código SMS"),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(
            hintText: "123456",
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // INTERFAZ DE USUARIO
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Entrar con Celular")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Selector de país y código telefónico
            DropdownButtonFormField<String>(
              value: _countryCode,
              items: _paises.entries
                  .map((e) => DropdownMenuItem(
                        value: e.value,
                        child: Text("${e.key} (${e.value})"),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _countryCode = v ?? '+51'),
              decoration: const InputDecoration(labelText: "País"),
            ),
            const SizedBox(height: 12),

            // Campo de texto para ingresar el número de celular
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\s-]+')),
                LengthLimitingTextInputFormatter(15),
              ],
              decoration: const InputDecoration(
                labelText: "Número de celular",
                hintText: "999 999 999",
              ),
            ),
            const SizedBox(height: 20),

            // Mensaje de error si ocurre algún problema
            if (_error != null)
              Text(_error!, style: TextStyle(color: cs.error)),

            const SizedBox(height: 20),

            // Botón para iniciar la verificación
            FilledButton.icon(
              onPressed: _loading ? null : _loginPhone,
              icon: const Icon(Icons.sms),
              label: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Enviar código"),
            ),
          ],
        ),
      ),
    );
  }
}
