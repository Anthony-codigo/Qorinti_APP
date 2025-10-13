// ============================================================================
// Archivo: usuario.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Modelo de dominio **Usuario** y enums asociados a estado, rol y método de
// autenticación. Centraliza datos de identificación y verificación para la
// gestión de acceso, perfiles y auditoría.
//
// Alcance
// -------
// - Serialización/deserialización con utilidades de `utils.dart`.
// - Construcción a partir de Firebase Auth (`fromFirebase`).
// - Soporte para comparación estructural vía `Equatable` y utilidades de UI.
// ============================================================================

import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'utils.dart';

/// Estados operativos del usuario en la plataforma.
enum EstadoUsuario { ACTIVO, INACTIVO, BLOQUEADO }
extension EstadoUsuarioX on EstadoUsuario {
  String get code => toString().split('.').last;
  static EstadoUsuario from(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'INACTIVO':  return EstadoUsuario.INACTIVO;
      case 'BLOQUEADO': return EstadoUsuario.BLOQUEADO;
      default:          return EstadoUsuario.ACTIVO;
    }
  }
}

/// Roles disponibles para control de permisos y vistas.
enum RolUsuario { USUARIO, CONDUCTOR, EMPRESA, ADMIN }
extension RolUsuarioX on RolUsuario {
  String get code => toString().split('.').last;
  static RolUsuario from(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'CONDUCTOR': return RolUsuario.CONDUCTOR;
      case 'EMPRESA':   return RolUsuario.EMPRESA;
      case 'ADMIN':     return RolUsuario.ADMIN;
      default:          return RolUsuario.USUARIO;
    }
  }
}

/// Método de autenticación utilizado por la cuenta.
enum MetodoAuth { CORREO, GOOGLE, CELULAR }
extension MetodoAuthX on MetodoAuth {
  String get code => toString().split('.').last.toLowerCase(); 
  static MetodoAuth from(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'GOOGLE':  return MetodoAuth.GOOGLE;
      case 'CELULAR': return MetodoAuth.CELULAR;
      default:        return MetodoAuth.CORREO;
    }
  }
}

/// Entidad principal de usuario de la plataforma.
class Usuario extends Equatable {
  final String? id;
  final String? nombre;
  final String correo;      
  final String? telefono;

  final EstadoUsuario estado;
  final RolUsuario rol;
  final MetodoAuth metodoAuth;

  final bool correoVerificado;
  final bool celularVerificado;

  final String? fotoUrl;
  final String? direccion;

  final DateTime? creadoEn;
  final DateTime? actualizadoEn;
  final DateTime? ultimoLogin;

  /// Constructor inmutable. Normaliza `correo` a minúsculas y sin espacios.
  Usuario({
    this.id,
    this.nombre,
    required String correo,
    this.telefono,
    this.estado = EstadoUsuario.ACTIVO,
    this.rol = RolUsuario.USUARIO,
    this.metodoAuth = MetodoAuth.CORREO,
    this.correoVerificado = false,
    this.celularVerificado = false,
    this.fotoUrl,
    this.direccion,
    this.creadoEn,
    this.actualizadoEn,
    this.ultimoLogin,
  }) : correo = correo.toLowerCase().trim();

  /// Serialización a Map para persistencia.
  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'correo': correo,
        'telefono': telefono,
        'estado': estado.code,
        'rol': rol.code,
        'metodoAuth': metodoAuth.code,
        'correoVerificado': correoVerificado,
        'celularVerificado': celularVerificado,
        'fotoUrl': fotoUrl,
        'direccion': direccion,
        'creadoEn': fsts(creadoEn),
        'actualizadoEn': fsts(actualizadoEn),
        'ultimoLogin': fsts(ultimoLogin),
      }..removeWhere((k, v) => v == null);

  /// Conversión segura a booleano desde dinámico.
  static bool _b(v) => v == true || (v is String && v.toLowerCase().trim() == 'true');

  /// Factoría desde Map (lectura Firestore).
  factory Usuario.fromMap(Map<String, dynamic> map, {String? id}) => Usuario(
        id: id,
        nombre: map['nombre'] as String?,
        correo: ((map['correo'] ?? '') as String).toLowerCase(),
        telefono: map['telefono'] as String?,
        estado: EstadoUsuarioX.from(map['estado'] ?? 'ACTIVO'),
        rol: RolUsuarioX.from(map['rol'] ?? 'USUARIO'),
        metodoAuth: MetodoAuthX.from(map['metodoAuth'] ?? 'correo'),
        correoVerificado: _b(map['correoVerificado']),
        celularVerificado: _b(map['celularVerificado']),
        fotoUrl: map['fotoUrl'] as String?,
        direccion: map['direccion'] as String?,
        creadoEn: dt(map['creadoEn']),
        actualizadoEn: dt(map['actualizadoEn']),
        ultimoLogin: dt(map['ultimoLogin']),
      );

  /// Construcción desde el objeto `User` de Firebase Authentication.
  factory Usuario.fromFirebase(
    User user, {
    RolUsuario rol = RolUsuario.USUARIO,
    MetodoAuth metodoAuth = MetodoAuth.CORREO,
  }) {
    return Usuario(
      id: user.uid,
      nombre: user.displayName,
      correo: (user.email ?? '').toLowerCase(),
      telefono: user.phoneNumber,
      estado: EstadoUsuario.ACTIVO,
      rol: rol,
      metodoAuth: metodoAuth,
      correoVerificado: user.emailVerified,
      celularVerificado: user.phoneNumber != null,
      fotoUrl: user.photoURL,
      creadoEn: DateTime.now(),     
      actualizadoEn: DateTime.now(),
      ultimoLogin: DateTime.now(),
    );
  }

  /// Copia inmutable con cambios selectivos.
  Usuario copyWith({
    String? id,
    String? nombre,
    String? correo,
    String? telefono,
    EstadoUsuario? estado,
    RolUsuario? rol,
    MetodoAuth? metodoAuth,
    bool? correoVerificado,
    bool? celularVerificado,
    String? fotoUrl,
    String? direccion,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
    DateTime? ultimoLogin,
  }) {
    return Usuario(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      correo: (correo ?? this.correo).toLowerCase().trim(),
      telefono: telefono ?? this.telefono,
      estado: estado ?? this.estado,
      rol: rol ?? this.rol,
      metodoAuth: metodoAuth ?? this.metodoAuth,
      correoVerificado: correoVerificado ?? this.correoVerificado,
      celularVerificado: celularVerificado ?? this.celularVerificado,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      direccion: direccion ?? this.direccion,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
      ultimoLogin: ultimoLogin ?? this.ultimoLogin,
    );
  }

  /// Utilidades para UI/validaciones rápidas.
  bool get hasPhone => (telefono ?? '').trim().isNotEmpty;
  bool get hasPhoto => (fotoUrl ?? '').trim().isNotEmpty;

  @override
  List<Object?> get props => [
        id,
        nombre,
        correo,
        telefono,
        estado,
        rol,
        metodoAuth,
        correoVerificado,
        celularVerificado,
        fotoUrl,
        direccion,
        creadoEn,
        actualizadoEn,
        ultimoLogin,
      ];

  @override
  String toString() =>
      'Usuario(id:$id, nombre:$nombre, correo:$correo, tel:$telefono, rol:${rol.code}, estado:${estado.code}, metodo:${metodoAuth.code})';
}
