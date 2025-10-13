// ============================================================================
// Archivo: vehiculo.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Define la entidad **Vehiculo**, utilizada para registrar y administrar los
// datos técnicos, de propiedad y estado operativo de los vehículos que prestan
// servicios en la plataforma (taxis, carga, mudanza).
//
// Alcance e integración
// ---------------------
// - Persistencia: serialización/deserialización compatible con Firestore mediante
//   utilidades de `utils.dart` para fechas (`fsts`, `dt`) y números (`toIntF`, `toDoubleF`).
// - Operación: campos `estado`, `tipo` y `activo` controlan la habilitación y
//   categorización del vehículo en los flujos de asignación y validación.
// - Cumplimiento: incorpora información de SOAT y revisión técnica para auditoría.
// ============================================================================

import 'utils.dart';

class Vehiculo {
  final String? id;
  final String placa;
  final String? marca;
  final String? modelo;
  final int? anio;

  // Dimensiones/capacidades para servicios de carga
  final double? capacidadTon;
  final double? volumenM3;
  final double? altoM;
  final double? anchoM;
  final double? largoM;
  final String? tipoCarroceria;

  // Propiedad del vehículo (usuario o empresa)
  final String? idPropietarioUsuario;
  final String? idPropietarioEmpresa;

  // Documentación y vigencias
  final String? soatNumero;
  final DateTime? soatVencimiento;
  final DateTime? revisionTecnica;

  // Estado operativo y clasificación
  final String estado; 
  final String tipo;   
  final bool activo;

  // Auditoría
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Constructor inmutable con valores predeterminados para estado y tipo.
  const Vehiculo({
    this.id,
    required this.placa,
    this.marca,
    this.modelo,
    this.anio,
    this.capacidadTon,
    this.volumenM3,
    this.altoM,
    this.anchoM,
    this.largoM,
    this.tipoCarroceria,
    this.idPropietarioUsuario,
    this.idPropietarioEmpresa,
    this.soatNumero,
    this.soatVencimiento,
    this.revisionTecnica,
    this.estado = 'PENDIENTE',
    this.tipo = 'AUTO',
    this.activo = false, 
    this.creadoEn,
    this.actualizadoEn,
  });

  /// Serialización a Map para persistencia en Firestore.
  /// - Convierte fechas a `Timestamp` con `fsts`.
  /// - Elimina claves con valor nulo para actualizaciones parciales limpias.
  Map<String, dynamic> toMap() => {
        'placa': placa,
        'marca': marca,
        'modelo': modelo,
        'anio': anio,
        'capacidadTon': capacidadTon,
        'volumenM3': volumenM3,
        'altoM': altoM,
        'anchoM': anchoM,
        'largoM': largoM,
        'tipoCarroceria': tipoCarroceria,
        'idPropietarioUsuario': idPropietarioUsuario,
        'idPropietarioEmpresa': idPropietarioEmpresa,
        'soatNumero': soatNumero,
        'soatVencimiento': fsts(soatVencimiento),
        'revisionTecnica': fsts(revisionTecnica),
        'estado': estado,
        'tipo': tipo,
        'activo': activo,
        'creadoEn': fsts(creadoEn),
        'actualizadoEn': fsts(actualizadoEn),
      }..removeWhere((k, v) => v == null);

  /// Factoría desde Map (lectura Firestore) con conversiones seguras de tipos.
  factory Vehiculo.fromMap(Map<String, dynamic> map, {String? id}) => Vehiculo(
        id: id,
        placa: (map['placa'] ?? '') as String,
        marca: map['marca'] as String?,
        modelo: map['modelo'] as String?,
        anio: toIntF(map['anio']),
        capacidadTon: toDoubleF(map['capacidadTon']),
        volumenM3: toDoubleF(map['volumenM3']),
        altoM: toDoubleF(map['altoM']),
        anchoM: toDoubleF(map['anchoM']),
        largoM: toDoubleF(map['largoM']),
        tipoCarroceria: map['tipoCarroceria'] as String?,
        idPropietarioUsuario: map['idPropietarioUsuario'] as String?,
        idPropietarioEmpresa: map['idPropietarioEmpresa'] as String?,
        soatNumero: map['soatNumero'] as String?,
        soatVencimiento: dt(map['soatVencimiento']),
        revisionTecnica: dt(map['revisionTecnica']),
        estado: (map['estado'] ?? 'PENDIENTE') as String,
        tipo: (map['tipo'] ?? 'AUTO') as String,
        activo: map['activo'] as bool? ?? false, 
        creadoEn: dt(map['creadoEn']),
        actualizadoEn: dt(map['actualizadoEn']),
      );
}
