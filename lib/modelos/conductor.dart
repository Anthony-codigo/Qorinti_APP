// ============================================================================
// Archivo: conductor.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito del archivo
// ---------------------
// Define la entidad de dominio **Conductor**, que representa a los conductores
// registrados en el sistema Qorinti App. Este modelo consolida la información
// personal, fiscal, de licencia, estado de verificación y métricas de
// desempeño (como calificación promedio y cancelaciones).
//
// Alcance e integración
// ---------------------
// - Se vincula con la entidad `Usuario` a través de `idUsuario` y, cuando
//   aplica, con una empresa (`idEmpresa`).
// - Permite persistencia directa en Firestore mediante `toMap` y `fromMap`,
//   empleando las funciones auxiliares `fsts`, `dt`, `toDoubleF` y `toIntF`
//   del módulo `utils.dart`.
// - Facilita la creación de nuevos registros base con `Conductor.nuevo()`
//   y la modificación segura mediante `copyWith()`.
// - Soporta campos de control como `estado`, `verificado`, `creadoEn` y
//   `actualizadoEn` para auditoría y validación de flujo.
// ============================================================================

import 'utils.dart';

/// ----------------------------------------------------------------------------
/// Entidad de dominio: Conductor
/// ----------------------------------------------------------------------------
/// Contiene los datos personales, fiscales y operativos del conductor,
/// incluyendo licencias, configuración de servicio y estadísticas de uso.
/// Se utiliza en los módulos de registro, monitoreo y evaluación de desempeño.
/// ----------------------------------------------------------------------------
class Conductor {
  final String? id;
  final String idUsuario;        
  final String? idEmpresa;

  final String? nombre;
  final String? celular;
  final String? fotoUrl;

  final String? dni;                
  final String? ruc;                
  final String? direccionFiscal;    

  final String? licenciaNumero;
  final String? licenciaCategoria; 
  final DateTime? licenciaVencimiento;

  final bool verificado;
  final String estado;

  final double? radioKm;
  final List<String>? tiposServicioHabilitados;
  final double? ratingPromedio;
  final int? ratingConteo;
  final int? cancelaciones;
  final String? idVehiculoActivo;
  final String? idEstadoCuenta;

  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Constructor inmutable con valores predeterminados de seguridad.
  const Conductor({
    this.id,
    required this.idUsuario,
    this.idEmpresa,
    this.nombre,
    this.celular,
    this.fotoUrl,
    this.dni,
    this.ruc,
    this.direccionFiscal,
    this.licenciaNumero,
    this.licenciaCategoria,
    this.licenciaVencimiento,
    this.verificado = false,
    this.estado = 'PENDIENTE',
    this.radioKm,
    this.tiposServicioHabilitados,
    this.ratingPromedio,
    this.ratingConteo,
    this.cancelaciones,
    this.idVehiculoActivo,
    this.idEstadoCuenta,
    this.creadoEn,
    this.actualizadoEn,
  });

  /// Crea una copia modificada manteniendo inmutabilidad.
  Conductor copyWith({
    String? id,
    String? idUsuario,
    String? idEmpresa,
    String? nombre,
    String? celular,
    String? fotoUrl,
    String? dni,
    String? ruc,
    String? direccionFiscal,
    String? licenciaNumero,
    String? licenciaCategoria,
    DateTime? licenciaVencimiento,
    bool? verificado,
    String? estado,
    double? radioKm,
    List<String>? tiposServicioHabilitados,
    double? ratingPromedio,
    int? ratingConteo,
    int? cancelaciones,
    String? idVehiculoActivo,
    String? idEstadoCuenta,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
  }) {
    return Conductor(
      id: id ?? this.id,
      idUsuario: idUsuario ?? this.idUsuario,
      idEmpresa: idEmpresa ?? this.idEmpresa,
      nombre: nombre ?? this.nombre,
      celular: celular ?? this.celular,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      dni: dni ?? this.dni,
      ruc: ruc ?? this.ruc,
      direccionFiscal: direccionFiscal ?? this.direccionFiscal,
      licenciaNumero: licenciaNumero ?? this.licenciaNumero,
      licenciaCategoria: licenciaCategoria ?? this.licenciaCategoria,
      licenciaVencimiento: licenciaVencimiento ?? this.licenciaVencimiento,
      verificado: verificado ?? this.verificado,
      estado: estado ?? this.estado,
      radioKm: radioKm ?? this.radioKm,
      tiposServicioHabilitados: tiposServicioHabilitados ?? this.tiposServicioHabilitados,
      ratingPromedio: ratingPromedio ?? this.ratingPromedio,
      ratingConteo: ratingConteo ?? this.ratingConteo,
      cancelaciones: cancelaciones ?? this.cancelaciones,
      idVehiculoActivo: idVehiculoActivo ?? this.idVehiculoActivo,
      idEstadoCuenta: idEstadoCuenta ?? this.idEstadoCuenta,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }

  /// Serialización a Map para persistencia en Firestore.
  Map<String, dynamic> toMap() => {
        'idUsuario': idUsuario,
        'idEmpresa': idEmpresa,
        'nombre': nombre,
        'celular': celular,
        'fotoUrl': fotoUrl,
        'dni': dni,
        'ruc': ruc,
        'direccionFiscal': direccionFiscal,
        'licenciaNumero': licenciaNumero,
        'licenciaCategoria': licenciaCategoria?.toUpperCase(),
        'licenciaVencimiento': fsts(licenciaVencimiento),
        'verificado': verificado,
        'estado': estado.toUpperCase(),
        'radioKm': radioKm,
        'tiposServicioHabilitados': tiposServicioHabilitados,
        'ratingPromedio': ratingPromedio,
        'ratingConteo': ratingConteo,
        'cancelaciones': cancelaciones,
        'idVehiculoActivo': idVehiculoActivo,
        'idEstadoCuenta': idEstadoCuenta,
        'creadoEn': fsts(creadoEn),
        'actualizadoEn': fsts(actualizadoEn),
      }..removeWhere((k, v) => v == null);

  /// Factoría para reconstruir la entidad a partir de un mapa (lectura Firestore).
  factory Conductor.fromMap(Map<String, dynamic> map, {String? id}) => Conductor(
        id: id,
        idUsuario: (map['idUsuario'] ?? '') as String,
        idEmpresa: map['idEmpresa'] as String?,
        nombre: map['nombre'] as String?,
        celular: map['celular'] as String?,
        fotoUrl: map['fotoUrl'] as String?,
        dni: map['dni'] as String?,
        ruc: map['ruc'] as String?,
        direccionFiscal: map['direccionFiscal'] as String?,
        licenciaNumero: map['licenciaNumero'] as String?,
        licenciaCategoria: (map['licenciaCategoria'] as String?)?.toUpperCase(),
        licenciaVencimiento: dt(map['licenciaVencimiento']),
        verificado: map['verificado'] == true,
        estado: (map['estado'] ?? 'PENDIENTE').toString().toUpperCase(),
        radioKm: toDoubleF(map['radioKm']),
        tiposServicioHabilitados: (map['tiposServicioHabilitados'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        ratingPromedio: toDoubleF(map['ratingPromedio']),
        ratingConteo: toIntF(map['ratingConteo']),
        cancelaciones: toIntF(map['cancelaciones']),
        idVehiculoActivo: map['idVehiculoActivo'] as String?,
        idEstadoCuenta: map['idEstadoCuenta'] as String?,
        creadoEn: dt(map['creadoEn']),
        actualizadoEn: dt(map['actualizadoEn']),
      );

  /// Indica si el conductor se encuentra aprobado por la administración.
  bool get estaAprobado => estado == 'APROBADO';

  /// Devuelve el promedio de calificación con valor por defecto de 0.0.
  double get rating => (ratingPromedio ?? 0.0);

  /// Constructor auxiliar para inicializar un nuevo conductor con valores base.
  factory Conductor.nuevo({
    required String uidUsuario,
    String? dni,
    String? ruc,
    String? direccionFiscal,
    String? licenciaNumero,
    String? licenciaCategoria,
    DateTime? licenciaVencimiento,
  }) {
    return Conductor(
      idUsuario: uidUsuario,
      dni: dni,
      ruc: ruc,
      direccionFiscal: direccionFiscal,
      licenciaNumero: licenciaNumero,
      licenciaCategoria: licenciaCategoria?.toUpperCase(),
      licenciaVencimiento: licenciaVencimiento,
      verificado: false,
      estado: 'PENDIENTE',
      radioKm: 10.0,
      tiposServicioHabilitados: const ['TAXI', 'CARGA'],
      ratingPromedio: 0.0,
      ratingConteo: 0,
      cancelaciones: 0,
    );
  }
}
