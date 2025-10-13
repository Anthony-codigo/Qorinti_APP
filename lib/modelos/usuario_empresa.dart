// ============================================================================
// Archivo: usuario_empresa.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Modelo **UsuarioEmpresa** que representa la afiliación de un usuario a una
// empresa dentro del sistema. Gestiona estado de membresía, rol asignado,
// preferencias de emisión de comprobantes y organización por centro de costo.
//
// Alcance e integración
// ---------------------
// - Se relaciona con las entidades `Usuario` y `Empresa` mediante sus ids.
// - Parametriza el comportamiento de facturación con `usaEmpresaComoEmisor`.
// - Incluye metadatos de auditoría (`creadoEn`, `actualizadoEn`) para control
//   de cambios y trazabilidad.
// - Serialización/deserialización compatible con Firestore usando utilidades
//   de `utils.dart` (`fsts`, `dt`).
// ============================================================================

import 'utils.dart';

/// ----------------------------------------------------------------------------
/// Entidad de dominio: UsuarioEmpresa
/// ----------------------------------------------------------------------------
/// Representa la relación (membresía) entre un usuario y una empresa,
/// incluyendo rol, estado y parámetros de emisión de comprobantes.
class UsuarioEmpresa {
  final String? id;
  final String idUsuario;
  final String idEmpresa;

  final String estadoMembresia;

  final String rol;

  final bool usaEmpresaComoEmisor;

  final String? centroCostoId;

  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Constructor inmutable con valores por defecto seguros:
  /// - `estadoMembresia = 'ACTIVO'`
  /// - `rol = 'MIEMBRO'`
  /// - `usaEmpresaComoEmisor = false`
  const UsuarioEmpresa({
    this.id,
    required this.idUsuario,
    required this.idEmpresa,
    this.estadoMembresia = 'ACTIVO',
    this.rol = 'MIEMBRO',
    this.usaEmpresaComoEmisor = false,
    this.centroCostoId,
    this.creadoEn,
    this.actualizadoEn,
  });

  /// Serialización a Map para persistencia en Firestore.
  /// - Normaliza `estadoMembresia` y `rol` a mayúsculas.
  /// - Convierte fechas con `fsts`.
  /// - Elimina claves nulas para actualizaciones parciales limpias.
  Map<String, dynamic> toMap() => {
        'idUsuario': idUsuario,
        'idEmpresa': idEmpresa,
        'estadoMembresia': estadoMembresia.toUpperCase(),
        'rol': rol.toUpperCase(),
        'usaEmpresaComoEmisor': usaEmpresaComoEmisor,
        'centroCostoId': centroCostoId,
        'creadoEn': fsts(creadoEn),
        'actualizadoEn': fsts(actualizadoEn),
      }..removeWhere((k, v) => v == null);

  /// Factoría desde Map (lectura Firestore).
  /// - `up()` asegura valores por defecto y normaliza a mayúsculas.
  factory UsuarioEmpresa.fromMap(Map<String, dynamic> map, {String? id}) {
    String up(dynamic x, String def) =>
        (x?.toString().trim().toUpperCase().isNotEmpty ?? false)
            ? x.toString().trim().toUpperCase()
            : def;

    return UsuarioEmpresa(
      id: id,
      idUsuario: (map['idUsuario'] ?? '') as String,
      idEmpresa: (map['idEmpresa'] ?? '') as String,
      estadoMembresia: up(map['estadoMembresia'], 'ACTIVO'),
      rol: up(map['rol'], 'MIEMBRO'),
      usaEmpresaComoEmisor: map['usaEmpresaComoEmisor'] == true,
      centroCostoId: map['centroCostoId'] as String?,
      creadoEn: dt(map['creadoEn']),
      actualizadoEn: dt(map['actualizadoEn']),
    );
  }

  /// Propiedades derivadas para autorización/visibilidad en UI.
  bool get esAdmin => rol == 'ADMIN';
  bool get esMiembro => rol == 'MIEMBRO';
  bool get estaActivo => estadoMembresia == 'ACTIVO';
}
