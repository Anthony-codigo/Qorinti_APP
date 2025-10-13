// Permisos y políticas de acceso a nivel de empresa.
// Define reglas de autorización basadas en el rol del usuario y el estado de su membresía.
// Este módulo centraliza la lógica de control de acceso (ACL) para pantallas y operaciones
// relacionadas con entidades de empresa (visualización, edición, miembros, servicios, pagos).

import 'package:app_qorinti/modelos/usuario_empresa.dart';

/// Utilidades estáticas de autorización para una empresa.
/// Se evalúan dos dimensiones:
/// - Rol del usuario dentro de la empresa (p. ej., "ADMIN").
/// - Estado de la membresía (p. ej., "ACTIVO", "SUSPENDIDO", "BAJA", "PENDIENTE").
///
/// Nota: Las constantes de estado/rol se comparan por igualdad exacta con strings.
/// Si en el futuro se tipifican (enums), estas funciones podrán migrarse sin
/// cambiar su contrato público.
class PermisosEmpresa {
  /// Permite acceder a vistas de información general de la empresa.
  /// Requisito: membresía activa.
  static bool puedeVerEmpresa(UsuarioEmpresa u) {
    return u.estadoMembresia == "ACTIVO";
  }

  /// Permite editar datos de la empresa (configuración, perfil, etc.).
  /// Requisitos: rol administrador y membresía activa.
  static bool puedeEditarEmpresa(UsuarioEmpresa u) {
    return u.rol == "ADMIN" && u.estadoMembresia == "ACTIVO";
  }

  /// Permite gestionar el ciclo de vida de miembros (invitar, aprobar, remover).
  /// Requisitos: rol administrador y membresía activa.
  static bool puedeGestionarMiembros(UsuarioEmpresa u) {
    return u.rol == "ADMIN" && u.estadoMembresia == "ACTIVO";
  }

  /// Permite solicitar/crear servicios a nombre de la empresa.
  /// Requisito: membresía activa.
  static bool puedePedirServicios(UsuarioEmpresa u) {
    return u.estadoMembresia == "ACTIVO";
  }

  /// Permite visualizar información de pagos (historial, estados).
  /// Requisito: membresía activa.
  static bool puedeVerPagos(UsuarioEmpresa u) {
    return u.estadoMembresia == "ACTIVO";
  }

  /// Permite realizar operaciones administrativas sobre pagos
  /// (registro manual, conciliación, autorización).
  /// Requisitos: rol administrador y membresía activa.
  static bool puedeAdministrarPagos(UsuarioEmpresa u) {
    return u.rol == "ADMIN" && u.estadoMembresia == "ACTIVO";
  }

  /// Indica si el usuario se encuentra con acceso restringido en el contexto de empresa.
  /// Estados considerados restrictivos: "SUSPENDIDO", "BAJA", "PENDIENTE".
  /// Útil para bloquear acciones transversales o mostrar avisos globales.
  static bool estaRestringido(UsuarioEmpresa u) {
    return u.estadoMembresia == "SUSPENDIDO" ||
           u.estadoMembresia == "BAJA" ||
           u.estadoMembresia == "PENDIENTE";
  }
}
