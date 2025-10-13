// lib/pantallas/auth/verificar_correo_screen.dart
// -----------------------------------------------------------------------------
// Pantalla para guiar al usuario en la verificación de su correo electrónico.
// Permite reenviar el correo de verificación, revisar si ya fue verificado y
// cerrar sesión si lo desea.
// -----------------------------------------------------------------------------

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VerificarCorreoScreen extends StatefulWidget {
  const VerificarCorreoScreen({super.key});

  @override
  State<VerificarCorreoScreen> createState() => _VerificarCorreoScreenState();
}

class _VerificarCorreoScreenState extends State<VerificarCorreoScreen> {
  // Estado de envío del correo de verificación
  bool _enviando = false;

  // Mensajes informativos/errores para el usuario
  String? _mensaje;

  // Reenvía el correo de verificación al usuario actual
  Future<void> _reenviar() async {
    setState(() {
      _enviando = true;
      _mensaje = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.sendEmailVerification();
      setState(() {
        _mensaje = "Correo de verificación enviado. Revisa tu bandeja.";
      });
    } catch (e) {
      setState(() {
        _mensaje = "Error al enviar correo: $e";
      });
    } finally {
      setState(() => _enviando = false);
    }
  }

  // Fuerza la recarga del usuario y comprueba si ya está verificado.
  // Si está verificado, redirige a /home; si no, muestra aviso.
  Future<void> _revisar() async {
    await FirebaseAuth.instance.currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.emailVerified) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, "/home");
      }
    } else {
      setState(() {
        _mensaje = "Aún no has verificado tu correo.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verificar correo")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Instrucciones
            const Text(
              "Debes verificar tu correo para continuar.\n\n"
              "Revisa tu bandeja de entrada y haz clic en el enlace.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Mensaje informativo o de error (si existe)
            if (_mensaje != null)
              Text(
                _mensaje!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),

            const SizedBox(height: 20),

            // Botón para reenviar correo de verificación
            FilledButton(
              onPressed: _enviando ? null : _reenviar,
              child: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Reenviar correo"),
            ),

            const SizedBox(height: 12),

            // Botón para indicar que ya verificó y volver a comprobar estado
            OutlinedButton(
              onPressed: _revisar,
              child: const Text("Ya lo verifiqué"),
            ),

            const SizedBox(height: 12),

            // Opción para cerrar sesión
            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              child: const Text("Cerrar sesión"),
            ),
          ],
        ),
      ),
    );
  }
}
