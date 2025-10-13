// lib/pantallas/Admin/admin_home_screen.dart
// ============================================================================
// Archivo: admin_home_screen.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Pantalla principal del panel administrativo de Qorinti.
// Sirve como contenedor y punto de navegación para las diferentes secciones
// del sistema de administración: Empresas, Conductores, Vehículos, Pagos y Reportes.
//
// Funcionalidades:
// - Muestra un panel lateral o menú tipo drawer (según el ancho de pantalla).
// - Controla la navegación interna entre secciones mediante `_selectedIndex`.
// - Incluye encabezado con logotipo e información del administrador.
// - Permite cerrar sesión del administrador (FirebaseAuth.signOut()).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'admin_empresas_screen.dart';
import 'admin_conductores_screen.dart';
import 'admin_vehiculos_screen.dart';
import 'admin_pagos_screen.dart';
import 'admin_reportes_screen.dart'; 

class AdminHomeScreen extends StatefulWidget {
  static const route = '/admin';
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0;

  // Lista de secciones visibles en el panel.
  final _sections = const [
    "Solicitudes de Empresas",
    "Conductores",
    "Vehículos",
    "Pagos de Comisión",
    "Reportes", 
  ];

  // Iconos asociados a cada sección.
  final _sectionIcons = const [
    Icons.business,
    Icons.people_alt,
    Icons.local_taxi,
    Icons.payments,
    Icons.summarize, 
  ];

  // Logotipo oficial de Qorinti almacenado en Firebase Storage.
  final String _logoUrl =
      "https://firebasestorage.googleapis.com/v0/b/dbchavez05.firebasestorage.app/o/imagen_qorinti%2FLogotype-Vertical-3840-x-2160-white.png?alt=media&token=179b343f-e433-4005-8b5f-7892824eaf62";

  // Devuelve la pantalla correspondiente a la opción seleccionada.
  Widget _buildCurrentPage() {
    switch (_selectedIndex) {
      case 0:
        return const AdminEmpresasScreen();
      case 1:
        return const AdminConductoresScreen();
      case 2:
        return const AdminVehiculosScreen();
      case 3:
        return const AdminPagosScreen();
      case 4:
      default:
        return const AdminReportesScreen();
    }
  }

  // Construye el encabezado del panel lateral o drawer.
  // Incluye logotipo, título y descripción corta del panel.
  Widget _drawerHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C2C2C), Color(0xFF3A3A3A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(
              imageUrl: _logoUrl,
              height: 95,
              fit: BoxFit.contain,
              memCacheWidth: 300,
              placeholder: (_, __) => const SizedBox(
                height: 95,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported,
                  color: Colors.white, size: 70),
            ),
            const SizedBox(height: 15),
            const Text(
              "Admin Qorinti",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Gestión completa del sistema",
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // Construye el listado de opciones del menú lateral.
  // Cada elemento cambia de estilo al estar seleccionado.
  Widget _menuList(BuildContext context) {
    return ListView.builder(
      itemCount: _sections.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (_, i) {
        final selected = _selectedIndex == i;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? Colors.grey.shade300 : Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: ListTile(
            leading: Icon(
              _sectionIcons[i],
              color: selected ? Colors.black87 : Colors.grey[800],
            ),
            title: Text(
              _sections[i],
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.black87 : Colors.grey[900],
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = i);
            },
          ),
        );
      },
    );
  }

  // Estructura principal de la pantalla.
  // Muestra el panel lateral fijo en pantallas anchas o como drawer en móviles.
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          "Panel Administrador Qorinti",
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
      ),
      body: Row(
        children: [
          if (isWide)
            // Panel lateral permanente (solo en escritorio o pantallas grandes).
            Container(
              width: 280,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  right: BorderSide(color: Colors.black12, width: 0.5),
                ),
              ),
              child: Column(
                children: [
                  _drawerHeader(context),
                  Expanded(child: _menuList(context)),
                  const Divider(height: 0),
                  _drawerFooter(context),
                ],
              ),
            ),
          // Contenido principal dinámico.
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildCurrentPage(),
            ),
          ),
        ],
      ),
      // Drawer lateral (solo visible en pantallas pequeñas).
      drawer: isWide
          ? null
          : Drawer(
              backgroundColor: Colors.white,
              child: Column(
                children: [
                  _drawerHeader(context),
                  Expanded(child: _menuList(context)),
                  const Divider(height: 0),
                  _drawerFooter(context),
                ],
              ),
            ),
    );
  }

  // Pie del menú lateral. Contiene la opción para cerrar sesión.
  Widget _drawerFooter(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text(
            "Cerrar sesión",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
          ),
          onTap: () async {
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              Navigator.pushReplacementNamed(context, '/login');
            }
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
