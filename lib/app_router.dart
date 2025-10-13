// lib/app_router.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// =========================
// Importaciones de pantallas organizadas por módulo
// =========================

// Auth
import 'pantallas/auth/login_screen.dart';
import 'pantallas/auth/registro_screen.dart';
import 'pantallas/auth/auth_gate.dart';
import 'pantallas/auth/verificar_correo_screen.dart';

// Home
import 'pantallas/home/home_screen.dart';
import 'pantallas/home/perfil_usuario_screen.dart';

// Empresa
import 'pantallas/empresa/empresa_registro_screen.dart';
import 'pantallas/empresa/unirse_empresa_screen.dart';
import 'pantallas/empresa/mi_empresa_screen.dart';
import 'pantallas/empresa/empresa_miembros_screen.dart';

// Admin
import 'pantallas/admin/admin_home_screen.dart';

// Conductor y vehículos
import 'pantallas/conductor/registro_conductor_screen.dart';
import 'pantallas/conductor/perfil_conductor_screen.dart';
import 'pantallas/conductor/registro_vehiculo_screen.dart';
import 'pantallas/conductor/mis_vehiculos_screen.dart';
import 'pantallas/servicios/conductor/estado_cuenta_conductor_screen.dart';
import 'pantallas/servicios/conductor/registrar_pago_comision_screen.dart';
import 'pantallas/servicios/conductor/pagos_comision_historial_screen.dart';

// Servicios
import 'pantallas/servicios/conductor/servicios_disponibles_screen.dart';
import 'pantallas/servicios/historial_servicios_screen.dart';
import 'pantallas/servicios/crear_servicio_screen.dart';
import 'pantallas/servicios/mis_servicios_screen.dart';
import 'pantallas/servicios/ofertas_servicio_screen.dart';
import 'pantallas/servicios/viaje_en_curso_screen.dart';

// =========================
// Clases auxiliares para argumentos tipados en rutas
// =========================

/// Argumentos utilizados para la navegación hacia la pantalla de miembros de empresa.
class EmpresaMiembrosArgs {
  final String idEmpresa;
  const EmpresaMiembrosArgs(this.idEmpresa);
}

/// Argumentos utilizados para la navegación hacia la pantalla de viaje en curso.
class ViajeEnCursoArgs {
  final String idServicio;
  final bool esConductor;
  const ViajeEnCursoArgs({required this.idServicio, required this.esConductor});
}

/// ========================================================
/// AppRouter: gestor central de rutas de navegación de Qorinti.
/// Define rutas nombradas, validaciones de sesión y generación de páginas.
/// ========================================================
class AppRouter {
  AppRouter._();

  /// Claves globales para el control de navegación y observación de rutas.
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final routeObserver = RouteObserver<PageRoute<dynamic>>();

  // ========================================================
  // Definición de rutas nombradas para cada módulo funcional
  // ========================================================

  // Admin
  static const adminPanel = '/admin';

  // Auth
  static const login = '/login';
  static const registro = '/registro';
  static const home = '/home';
  static const auth = '/auth';
  static const verificarCorreo = '/verificar-correo';

  // Empresa
  static const empresaRegistro = '/empresa/registro';
  static const empresaUnirse = '/empresa/unirse';
  static const miEmpresa = '/empresa/mia';
  static const empresaMiembros = '/empresa/miembros';

  // Conductor
  static const registroConductor = '/conductor/registro';
  static const perfilConductor = '/conductor/perfil';
  static const estadoCuentaConductor = '/conductor/estado-cuenta';
  static const registrarPagoComision = '/conductor/pago-comision';
  static const pagosComisionHistorial = '/conductor/pagos-comision-historial';
  static const solicitarRetiro = '/conductor/solicitar-retiro';
  static const retirosHistorial = '/conductor/retiros';

  // Vehículos
  static const registroVehiculo = '/vehiculo/registro';
  static const misVehiculos = '/vehiculo/mis';

  // Servicios
  static const crearServicio = '/servicios/crear';
  static const serviciosDisponibles = '/servicios/disponibles';
  static const historialServicios = '/servicios/historial';
  static const misServicios = '/servicios/mis';
  static const ofertasServicio = '/servicios/ofertas';
  static const viajeEnCurso = '/servicios/viaje';

  // ========================================================
  // Métodos utilitarios de navegación
  // ========================================================

  /// Navega a una ruta específica agregándola al stack de navegación.
  static Future<T?> push<T extends Object?>(String route, {Object? args}) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.pushNamed<T>(route, arguments: args);
  }

  /// Reemplaza la ruta actual por una nueva.
  static Future<T?> replace<T extends Object?>(String route, {Object? args}) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.pushReplacementNamed<T, T>(route, arguments: args);
  }

  /// Limpia el historial de navegación y redirige a una ruta específica.
  static Future<T?> clearAndGo<T extends Object?>(String route, {Object? args}) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.pushNamedAndRemoveUntil<T>(route, (_) => false, arguments: args);
  }

  /// Cierra la ruta actual y regresa a la anterior.
  static void pop<T extends Object?>([T? result]) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (nav.canPop()) nav.pop<T>(result);
  }

  // ========================================================
  // Validaciones de sesión y métodos internos de control
  // ========================================================

  static User? get _user => FirebaseAuth.instance.currentUser;
  static bool get _isLoggedIn => _user != null;
  static bool get _isEmailVerified => _user?.emailVerified ?? false;

  /// Genera una pantalla de error genérica para rutas inválidas o argumentos incorrectos.
  static Route<dynamic> _error(String msg) => MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Navegación')),
          body: Center(child: Text('⚠️ $msg')),
        ),
      );

  /// Crea una ruta MaterialPageRoute genérica con la pantalla indicada.
  static Route<T> _page<T extends Object?>(Widget page, RouteSettings s,
      {bool fullscreenDialog = false}) {
    return MaterialPageRoute<T>(
      settings: s,
      builder: (_) => page,
      fullscreenDialog: fullscreenDialog,
    );
  }

  /// Verifica que el usuario esté autenticado antes de acceder a ciertas rutas.
  /// Si requiere verificación de correo, valida que el usuario haya confirmado su email.
  static Route<dynamic> _requireAuth(
    RouteSettings s,
    Widget child, {
    bool requireVerifiedEmail = false,
  }) {
    if (!_isLoggedIn) {
      return _page(const LoginScreen(), s);
    }
    if (requireVerifiedEmail && !_isEmailVerified) {
      return _page(const VerificarCorreoScreen(), s);
    }
    return _page(child, s);
  }

  // ========================================================
  // Generador principal de rutas de la aplicación
  // ========================================================
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      // ---------- Autenticación ----------
      case login:
        return _page(const LoginScreen(), settings);
      case registro:
        return _page(const RegistroScreen(), settings);
      case home:
        return _page(const HomeScreen(), settings);
      case auth:
        return _page(const AuthGate(), settings);
      case verificarCorreo:
        return _isLoggedIn
            ? _page(const VerificarCorreoScreen(), settings)
            : _page(const LoginScreen(), settings);
      case '/usuario/perfil':
        return _requireAuth(settings, const PerfilUsuarioScreen());

      // ---------- Empresa (requiere autenticación) ----------
      case empresaRegistro:
        return _requireAuth(settings, const EmpresaRegistroScreen());
      case empresaUnirse:
        return _requireAuth(settings, const UnirseEmpresaScreen());
      case miEmpresa:
        return _requireAuth(settings, const MiEmpresaScreen());
      case empresaMiembros: {
        String? idEmpresa;

        final args = settings.arguments;
        if (args is String) {
          idEmpresa = args.trim();
        } else if (args is Map) {
          final dynamic v = args['idEmpresa'];
          if (v is String) idEmpresa = v.trim();
        } else if (args is EmpresaMiembrosArgs) {
          idEmpresa = args.idEmpresa.trim();
        }

        if (idEmpresa == null || idEmpresa.isEmpty) {
          return _error('ID de empresa no válido');
        }

        return _requireAuth(
          settings,
          EmpresaMiembrosScreen(idEmpresa: idEmpresa),
        );
      }

      // ---------- Administración ----------
      case '/admin':
        return _requireAuth(settings, const AdminHomeScreen());

      // ---------- Conductor ----------
      case registroConductor:
        return _requireAuth(settings, const RegistroConductorScreen());
      case perfilConductor:
        return _requireAuth(settings, const PerfilConductorScreen());
      case estadoCuentaConductor:
        return _requireAuth(settings, const EstadoCuentaConductorScreen());
      case registrarPagoComision: {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || uid.isEmpty) {
          return _error('No hay sesión activa');
        }
        return _requireAuth(
          settings,
          RegistrarPagoComisionScreen(idConductor: uid),
        );
      }
      case pagosComisionHistorial:
        return _requireAuth(settings, const PagosComisionHistorialScreen());

      // ---------- Vehículos ----------
      case registroVehiculo:
        return _requireAuth(settings, const RegistroVehiculoScreen());
      case misVehiculos:
        return _requireAuth(settings, const MisVehiculosScreen());

      // ---------- Servicios ----------
      case crearServicio:
        return _requireAuth(settings, const CrearServicioScreen());
      case serviciosDisponibles:
        return _requireAuth(settings, const ServiciosDisponiblesScreen());
      case historialServicios:
        return _requireAuth(settings, const HistorialServiciosScreen());
      case misServicios:
        return _requireAuth(settings, const MisServiciosScreen());
      case ofertasServicio: {
        final idServicio = settings.arguments as String?;
        if (idServicio == null || idServicio.isEmpty) {
          return _error('ID de servicio no válido');
        }
        return _requireAuth(settings, OfertasServicioScreen(idServicio: idServicio));
      }
      case viajeEnCurso: {
        final args = settings.arguments;
        if (args is! ViajeEnCursoArgs) {
          return _error('Argumentos inválidos para el viaje');
        }
        return _requireAuth(
          settings,
          ViajeEnCursoScreen(
            idServicio: args.idServicio,
            esConductor: args.esConductor,
          ),
        );
      }

      // ---------- Ruta por defecto ----------
      default:
        return _page(const LoginScreen(), settings);
    }
  }

  // ========================================================
  // Manejador de rutas desconocidas
  // ========================================================
  static Route<dynamic> onUnknownRoute(RouteSettings settings) {
    return _error('Ruta desconocida: ${settings.name ?? '-'}');
  }
}
