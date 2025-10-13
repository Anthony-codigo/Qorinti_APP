// lib/pantallas/home/home_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: HomeScreen
// Descripción general:
//   Es la pantalla principal de la aplicación Qorinti, adaptativa al tipo de usuario
//   (cliente, conductor, o administrador). Se alimenta en tiempo real de los datos
//   del perfil extendido desde Firestore y construye la interfaz dinámica.
//
//   Muestra accesos directos a:
//     - Empresa (ver, registrar o unirse)
//     - Módulo de conductor (perfil, vehículos, pagos)
//     - Servicios (crear, listar, historial, disponibles)
//   También permite visualizar alertas financieras (deuda de comisión) y
//   cerrar sesión desde el Drawer lateral.
//
//   Dependencias clave:
//     • PerfilService → streamPerfil(uid)
//     • FinanzasRepository → streamEstadoCuenta(uid)
//     • FirebaseAuth → sesión activa
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:app_qorinti/app_router.dart';
import 'package:app_qorinti/repos/perfil_service.dart';
import 'package:app_qorinti/modelos/perfil_extendido.dart';

import 'package:app_qorinti/repos/finanzas_repository.dart';
import 'package:app_qorinti/modelos/estado_cuenta_conductor.dart';

class HomeScreen extends StatelessWidget {
  static const route = '/home';
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // Si no hay sesión activa, se muestra mensaje genérico.
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("No hay sesión activa")),
      );
    }

    // --------------------------------------------------------------------------
    // Inicialización de servicios y formatos
    // --------------------------------------------------------------------------
    final perfilService = PerfilService();
    final finanzas = context.read<FinanzasRepository>();
    final moneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/.', decimalDigits: 2);
    final hoy = DateFormat('EEEE d MMM', 'es_PE').format(DateTime.now());
    final cs = Theme.of(context).colorScheme;

    // --------------------------------------------------------------------------
    // Escucha del perfil extendido del usuario
    // --------------------------------------------------------------------------
    return StreamBuilder<PerfilExtendido>(
      stream: perfilService.streamPerfil(user.uid),
      builder: (context, snapshotPerfil) {
        // Estado: cargando
        if (snapshotPerfil.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        // Estado: error al cargar perfil
        if (snapshotPerfil.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                "Error cargando perfil: ${snapshotPerfil.error}",
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        // Estado: sin datos
        if (!snapshotPerfil.hasData) {
          return const Scaffold(
            body: Center(child: Text("No se pudo cargar el perfil")),
          );
        }

        // ----------------------------------------------------------------------
        // Datos cargados correctamente
        // ----------------------------------------------------------------------
        final perfil = snapshotPerfil.data!;
        final name = (perfil.usuario.nombre ?? perfil.usuario.correo).trim();

        // Variables de contexto de conductor
        final tieneConductor = perfil.conductor != null;
        final conductorAprobado = perfil.conductorAprobado;
        final conductorOperando = perfil.esConductorOperando;

        // ----------------------------------------------------------------------
        // Construcción dinámica del grid de accesos rápidos según estado
        // ----------------------------------------------------------------------
        final items = <_HomeItem>[
          // Bloque Empresa
          _HomeItem(Icons.apartment, "Mi Empresa", AppRouter.miEmpresa),
          _HomeItem(Icons.business, "Registrar Empresa", AppRouter.empresaRegistro),
          _HomeItem(Icons.group_add, "Unirse a Empresa", AppRouter.empresaUnirse),

          // Bloque Conductor
          if (!tieneConductor) ...[
            _HomeItem(Icons.directions_car, "Ser Conductor", AppRouter.registroConductor),
          ] else ...[
            _HomeItem(Icons.person, "Mi Perfil de Conductor", AppRouter.perfilConductor),

            if (!conductorAprobado)
              _HomeItem(Icons.fact_check, "Completar verificación", AppRouter.registroConductor)
            else ...[
              _HomeItem(Icons.add_circle, "Registrar Vehículo", AppRouter.registroVehiculo),
              _HomeItem(Icons.directions_car_filled, "Mis Vehículos", AppRouter.misVehiculos),
              _HomeItem(Icons.account_balance_wallet, "Estado de cuenta", AppRouter.estadoCuentaConductor),
              _HomeItem(Icons.payments, "Registrar pago comisión", AppRouter.registrarPagoComision),
            ],
          ],

          // Bloque Servicios
          _HomeItem(Icons.add_location_alt, "Solicitar Servicio", AppRouter.crearServicio),
          _HomeItem(Icons.list_alt, "Mis Servicios", AppRouter.misServicios),
          _HomeItem(Icons.history, "Historial de Viajes", AppRouter.historialServicios),

          if (conductorAprobado)
            _HomeItem(Icons.local_taxi, "Servicios Disponibles", AppRouter.serviciosDisponibles),

          if (conductorAprobado)
            _HomeItem(Icons.receipt_long, "Pagos de comisión", AppRouter.pagosComisionHistorial),
        ];

        // ----------------------------------------------------------------------
        // Construcción visual principal: AppBar + Drawer + Body con Grid
        // ----------------------------------------------------------------------
        return Scaffold(
          appBar: AppBar(
            title: const Text("Qorinti"),
            centerTitle: true,
          ),

          // ------------------------------------------------------------------
          // Drawer lateral con secciones dinámicas
          // ------------------------------------------------------------------
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Cabecera del Drawer con foto y nombre
                  _DrawerHeader(
                    name: name,
                    email: perfil.usuario.correo,
                    photoUrl: perfil.usuario.fotoUrl,
                  ),

                  const _SectionHeader(title: "Perfil de Usuario"),
                  _drawerItem(context, Icons.person_outline, "Mi Perfil", '/usuario/perfil'),
                  const _SectionDivider(),

                  // --------------------- Bloque Empresa ---------------------
                  const _SectionHeader(title: "Empresa"),
                  _drawerItem(context, Icons.apartment, "Mi Empresa", AppRouter.miEmpresa),
                  _drawerItem(context, Icons.group_add, "Unirse a Empresa", AppRouter.empresaUnirse),
                  _drawerItem(context, Icons.business, "Registrar Empresa", AppRouter.empresaRegistro),

                  const _SectionDivider(),

                  // --------------------- Bloque Conductor ---------------------
                  if (!tieneConductor) ...[
                    const _SectionHeader(title: "Conductor"),
                    _drawerItem(context, Icons.directions_car, "Ser Conductor", AppRouter.registroConductor),
                  ] else ...[
                    const _SectionHeader(title: "Conductor"),
                    _drawerItem(context, Icons.person, "Mi Perfil de Conductor", AppRouter.perfilConductor),
                    if (!conductorAprobado)
                      _drawerItem(context, Icons.fact_check, "Completar verificación", AppRouter.registroConductor)
                    else ...[
                      _drawerItem(context, Icons.add_circle, "Registrar Vehículo", AppRouter.registroVehiculo),
                      _drawerItem(context, Icons.directions_car_filled, "Mis Vehículos", AppRouter.misVehiculos),
                      _drawerItem(context, Icons.account_balance_wallet, "Estado de cuenta", AppRouter.estadoCuentaConductor),
                      _drawerItem(context, Icons.payments, "Registrar pago comisión", AppRouter.registrarPagoComision),
                    ],
                  ],

                  const _SectionDivider(),

                  // --------------------- Bloque Servicios ---------------------
                  const _SectionHeader(title: "Servicios"),
                  _drawerItem(context, Icons.add_location_alt, "Solicitar Servicio", AppRouter.crearServicio),
                  if (conductorAprobado)
                    _drawerItem(context, Icons.local_taxi, "Servicios Disponibles", AppRouter.serviciosDisponibles),
                  _drawerItem(context, Icons.list_alt, "Mis Servicios", AppRouter.misServicios),
                  _drawerItem(context, Icons.history, "Historial de Viajes", AppRouter.historialServicios),

                  const _SectionDivider(),

                  // --------------------- Cerrar sesión ---------------------
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text("Cerrar sesión"),
                    onTap: () async {
                      final nav = Navigator.of(context);
                      nav.pop();
                      try {
                        await FirebaseAuth.instance.signOut();
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error al cerrar sesión: $e')),
                        );
                      }
                      if (!context.mounted) return;
                      nav.pushNamedAndRemoveUntil('/login', (_) => false);
                    },
                  ),
                ],
              ),
            ),
          ),
          // ------------------------------------------------------------------
          // CUERPO PRINCIPAL DEL HOME
          // ------------------------------------------------------------------
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ----------------------------------------------------------
                  // CABECERA superior: saludo, fecha y estado del conductor
                  // ----------------------------------------------------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Hola, ${name.isEmpty ? 'Usuario' : name} 👋",
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today_rounded,
                                    size: 16, color: cs.primary),
                                const SizedBox(width: 6),
                                Text(hoy,
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant)),
                                // Muestra el “pill” de estado si el conductor está operando
                                if (conductorOperando) ...[
                                  const SizedBox(width: 10),
                                  _StatusPill(
                                    icon: Icons.check_circle,
                                    label: "Operando",
                                    bg: cs.primaryContainer,
                                    fg: cs.onPrimaryContainer,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Avatar del usuario o inicial si no tiene foto
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: cs.primaryContainer,
                        backgroundImage: perfil.usuario.fotoUrl != null
                            ? NetworkImage(perfil.usuario.fotoUrl!)
                            : null,
                        child: perfil.usuario.fotoUrl == null
                            ? Text(
                                (name.isNotEmpty ? name[0] : "?")
                                    .toUpperCase(),
                                style: TextStyle(color: cs.onPrimaryContainer))
                            : null,
                      ),
                    ],
                  ),

                  // ----------------------------------------------------------
                  // Banner de deuda de comisión (solo para conductores activos)
                  // ----------------------------------------------------------
                  if (conductorAprobado)
                    StreamBuilder<EstadoCuentaConductor>(
                      stream: finanzas.streamEstadoCuenta(user.uid),
                      builder: (context, snapCuenta) {
                        if (!snapCuenta.hasData) return const SizedBox(height: 12);
                        final deuda = snapCuenta.data!.deudaComision;
                        if (deuda <= 0) return const SizedBox(height: 12);
                        return Padding(
                          padding:
                              const EdgeInsets.only(top: 12.0, bottom: 4.0),
                          child: _SoftBanner(
                            icon: Icons.warning_amber_rounded,
                            iconColor: Colors.orange,
                            message:
                                'Tienes comisión pendiente: ${moneda.format(deuda)}. '
                                'Regístrala para mantener tu cuenta al día.',
                            actionText: 'Registrar pago',
                            onAction: () => Navigator.pushNamed(
                                context, AppRouter.registrarPagoComision),
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 12),

                  // ----------------------------------------------------------
                  // GRID DE ACCESOS RÁPIDOS — Responsivo por tamaño de pantalla
                  // ----------------------------------------------------------
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final isWide = c.maxWidth >= 900;
                        final isTablet =
                            c.maxWidth >= 600 && c.maxWidth < 900;
                        final cross = isWide ? 4 : (isTablet ? 3 : 2);

                        return GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cross,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 1.08,
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final item = items[i];
                            return _gridTile(
                                context, item.icon, item.title, item.route);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // ITEM del Drawer lateral
  // --------------------------------------------------------------------------
  Widget _drawerItem(BuildContext c, IconData icon, String title, String route) {
    final cs = Theme.of(c).colorScheme;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
      ),
      title: Text(title),
      onTap: () {
        Navigator.pop(c);
        Navigator.pushNamed(c, route);
      },
    );
  }

  // --------------------------------------------------------------------------
  // Tarjeta del grid principal (con hover animado)
  // --------------------------------------------------------------------------
  Widget _gridTile(BuildContext c, IconData icon, String title, String route) {
    final cs = Theme.of(c).colorScheme;
    return _HoverScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pushNamed(c, route),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primaryContainer.withOpacity(0.55),
                cs.surfaceVariant.withOpacity(0.35),
              ],
            ),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ícono dentro de un contenedor circular
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 28, color: cs.onPrimary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Modelo auxiliar para representar los ítems del grid principal
// -----------------------------------------------------------------------------
class _HomeItem {
  final IconData icon;
  final String title;
  final String route;
  const _HomeItem(this.icon, this.title, this.route);
}

// -----------------------------------------------------------------------------
// Cabecera del Drawer con nombre, correo y foto de usuario
// -----------------------------------------------------------------------------
class _DrawerHeader extends StatelessWidget {
  final String name;
  final String email;
  final String? photoUrl;
  const _DrawerHeader({required this.name, required this.email, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: cs.primary,
            backgroundImage:
                photoUrl != null ? NetworkImage(photoUrl!) : null,
            child: photoUrl == null
                ? Text(
                    (name.isNotEmpty ? name[0] : "?").toUpperCase(),
                    style: TextStyle(
                        color: cs.onPrimary, fontWeight: FontWeight.w700))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Usuario' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer)),
                const SizedBox(height: 2),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: cs.onPrimaryContainer.withOpacity(0.8))),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Encabezado y divisor visual para las secciones del Drawer
// -----------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 24),
    );
  }
}

// -----------------------------------------------------------------------------
// Widget “pill” que indica estado (ej. Operando)
// -----------------------------------------------------------------------------
class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  const _StatusPill({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Banner informativo suave (alerta de deuda, avisos, etc.)
// -----------------------------------------------------------------------------
class _SoftBanner extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String message;
  final String actionText;
  final VoidCallback onAction;

  const _SoftBanner({
    required this.icon,
    required this.iconColor,
    required this.message,
    required this.actionText,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: cs.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: Text(actionText),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Efecto visual de escala al pasar el mouse (hover) en desktop/web
// -----------------------------------------------------------------------------
class _HoverScale extends StatefulWidget {
  final Widget child;
  const _HoverScale({required this.child});

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
