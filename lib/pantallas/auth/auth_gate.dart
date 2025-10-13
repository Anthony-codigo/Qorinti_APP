// lib/pantallas/auth/auth_gate.dart
// ============================================================================
// Widget: AuthGate
// Proyecto: Qorinti App – Control de acceso y navegación inicial
// ----------------------------------------------------------------------------
// Descripción general:
// Este widget actúa como una “puerta de autenticación” que determina qué
// pantalla debe mostrar la aplicación según el estado actual del usuario
// autenticado en Firebase.
//
// Lógica principal:
// 1. Si no hay usuario autenticado → muestra la pantalla de Login.
// 2. Si el usuario se registró con email y contraseña pero aún no verificó
//    su correo electrónico → redirige a VerificarCorreoScreen.
// 3. Si el usuario está autenticado y su correo está verificado, consulta
//    su documento en Firestore para determinar su rol:
//      ▪ SUPERADMIN → abre el panel administrador (AdminHomeScreen).
//      ▪ Cualquier otro rol → abre la pantalla de inicio normal (HomeScreen).
// ----------------------------------------------------------------------------
// Tecnologías utilizadas:
// - FirebaseAuth: para gestionar el estado de sesión del usuario.
// - Cloud Firestore: para leer los datos y roles del usuario.
// - Flutter StreamBuilder: para reaccionar dinámicamente a cambios en tiempo real.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app_qorinti/pantallas/auth/login_screen.dart';
import 'package:app_qorinti/pantallas/auth/verificar_correo_screen.dart';
import 'package:app_qorinti/pantallas/home/home_screen.dart';
import 'package:app_qorinti/pantallas/Admin/admin_home_screen.dart'; 

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // Escucha los cambios en el estado de autenticación (login, logout, etc.)
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, snap) {
        // Mientras se conecta a Firebase muestra un indicador de carga.
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Si no hay sesión iniciada, se muestra la pantalla de login.
        final user = snap.data;
        if (user == null) {
          return const LoginScreen();
        }

        // Si el usuario usa autenticación por contraseña y su correo no está verificado,
        // se lo dirige a la pantalla de verificación de correo electrónico.
        if (user.providerData.any((p) => p.providerId == 'password') &&
            !user.emailVerified) {
          return const VerificarCorreoScreen();
        }

        // Si el usuario está autenticado, se consulta su documento en Firestore
        // para obtener su rol (por ejemplo, USUARIO o SUPERADMIN).
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnap) {
            // Si la consulta aún no responde, muestra un indicador de carga.
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // Si no existe el documento del usuario en Firestore,
            // se considera un usuario normal y se redirige a HomeScreen.
            if (!userSnap.hasData || !userSnap.data!.exists) {
              return const HomeScreen();
            }

            // Extrae el rol del documento y lo convierte a mayúsculas.
            final data =
                userSnap.data!.data() as Map<String, dynamic>? ?? {};
            final rol = (data['rol'] ?? 'USUARIO').toString().toUpperCase();

            // Si el rol es SUPERADMIN → abre el panel administrador.
            if (rol == 'SUPERADMIN') {
              return const AdminHomeScreen(); 
            } 
            // En cualquier otro caso → abre la pantalla principal estándar.
            else {
              return const HomeScreen();
            }
          },
        );
      },
    );
  }
}
