// ============================================================================
// Archivo: perfil_extendido.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Modelo de agregación **PerfilExtendido** que concentra la información
// combinada del usuario, su rol de conductor (si aplica), sus vehículos y
// afiliaciones empresariales para facilitar validaciones y consultas en UI/BLoC.
//
// Alcance
// -------
// - Reúne entidades núcleo (`Usuario`, `Conductor`, `Vehiculo`, `UsuarioEmpresa`).
// - Expone propiedades derivadas para flujo operativo: aprobación y operación
//   del conductor, vehículo activo y empresa principal.
// ============================================================================

import 'usuario.dart';
import 'conductor.dart';
import 'vehiculo.dart';
import 'usuario_empresa.dart';

class PerfilExtendido {
  final Usuario usuario;                 
  final Conductor? conductor;           
  final List<Vehiculo> vehiculos;        
  final List<UsuarioEmpresa> empresas;   

  const PerfilExtendido({
    required this.usuario,
    this.conductor,
    this.vehiculos = const [],
    this.empresas = const [],
  });

  /// Alias semántico que refleja si el conductor está operando.
  bool get esConductorActivo => esConductorOperando;

  /// Conductor aprobado por la administración (estado = APROBADO).
  bool get conductorAprobado =>
      conductor != null && conductor!.estado.toUpperCase() == 'APROBADO';

  /// Conductor en operación: aprobado y con vehículo activo asociado.
  bool get esConductorOperando =>
      conductorAprobado &&
      (conductor!.idVehiculoActivo != null);

  /// Vehículo actualmente activo según `idVehiculoActivo` del conductor.
  /// Devuelve null si no hay coincidencia en la lista local.
  Vehiculo? get vehiculoActivo {
    final idAct = conductor?.idVehiculoActivo;
    if (idAct == null) return null;
    try {
      return vehiculos.firstWhere((v) => v.id == idAct);
    } catch (_) {
      return null;
    }
  }

  /// Indica si el usuario tiene al menos una afiliación empresarial.
  bool get tieneEmpresa => empresas.isNotEmpty;

  /// Retorna la afiliación principal; por convención el primer elemento.
  UsuarioEmpresa? get empresaPrincipal {
    if (empresas.isEmpty) return null;
    return empresas.first;
  }

}
