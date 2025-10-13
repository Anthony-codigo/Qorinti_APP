/// ============================================================================
/// Archivo: calificacion.dart
/// Proyecto: Qorinti App – Gestión de Transporte
/// ----------------------------------------------------------------------------
/// Propósito del archivo
/// ---------------------
/// Define el modelo de dominio **Calificacion**, que representa la evaluación
/// (puntuación en estrellas y comentario opcional) realizada por un usuario a
/// otro dentro de un **Servicio**. Este modelo se persiste en **Cloud Firestore**
/// y se utiliza tanto para registrar nuevas calificaciones como para leerlas y
/// mostrarlas en interfaces de reporte y reputación (p. ej., conductor ↔ cliente).
///
/// Alcance e integración
/// ---------------------
/// - Persistencia: serializa/deserializa con Firestore mediante `toMap` y
///   `fromMap`, empleando `Timestamp`/`FieldValue.serverTimestamp`.
/// - Integridad: campos obligatorios garantizan trazabilidad (ids de servicio y
///   usuarios, y cantidad de estrellas).
/// - Utilidades: usa `dt()` de `utils.dart` para convertir a `DateTime` valores
///   provenientes de Firestore (Timestamp/dynamic).


import 'package:cloud_firestore/cloud_firestore.dart';
import 'utils.dart';

/// ----------------------------------------------------------------------------
/// Entidad de dominio: Calificacion
/// ----------------------------------------------------------------------------
/// Representa una calificación de `deUsuarioId` para `paraUsuarioId` asociada a
/// un `idServicio`. Incluye:
/// - `estrellas` (entero): métrica principal de reputación.
/// - `comentario` (opcional): contexto cualitativo.
/// - `creadoEn` (opcional): fecha de creación; si se omite al persistir, puede
///   completarse con `serverTimestamp` para consistencia temporal en Firestore.
/// ----------------------------------------------------------------------------
class Calificacion {
  final String id;
  final String idServicio;
  final String deUsuarioId;     
  final String paraUsuarioId;  
  final int estrellas;          
  final String? comentario;
  final DateTime? creadoEn;

  /// --------------------------------------------------------------------------
  /// Constructor inmutable
  /// - Requiere identificadores y la puntuación en estrellas.
  /// - `comentario` y `creadoEn` son opcionales para permitir creación mínima y
  ///   delegar el tiempo al servidor cuando sea necesario.
  /// --------------------------------------------------------------------------
  const Calificacion({
    required this.id,
    required this.idServicio,
    required this.deUsuarioId,
    required this.paraUsuarioId,
    required this.estrellas,
    this.comentario,
    this.creadoEn,
  });

  /// --------------------------------------------------------------------------
  /// Serialización a Map para Firestore
  /// - Convierte `creadoEn` a `Timestamp` cuando viene definido.
  /// - Si `creadoEn` es nulo y `serverNowIfNull` es `true`, usa
  ///   `FieldValue.serverTimestamp()` para registrar la hora del servidor.
  /// - `removeWhere` limpia claves con valores nulos para evitar sobrescrituras
  ///   indeseadas en actualizaciones parciales (merge/update).
  /// --------------------------------------------------------------------------
  Map<String, dynamic> toMap({bool serverNowIfNull = false}) => {
        'idServicio': idServicio,
        'deUsuarioId': deUsuarioId,
        'paraUsuarioId': paraUsuarioId,
        'estrellas': estrellas,
        'comentario': comentario,
        'creadoEn': creadoEn != null
            ? Timestamp.fromDate(creadoEn!)
            : (serverNowIfNull ? FieldValue.serverTimestamp() : null),
      }..removeWhere((k, v) => v == null);

  /// --------------------------------------------------------------------------
  /// Factoría desde Map (lectura Firestore)
  /// - `id` proviene del documento (no del payload).
  /// - Realiza casting seguro y fallback por defecto para evitar nullability
  ///   issues en campos críticos.
  /// - `estrellas` se normaliza a `int` desde `num?`.
  /// - `creadoEn` se convierte con `dt()` para aceptar `Timestamp`/dynamic.
  /// --------------------------------------------------------------------------
  factory Calificacion.fromMap(Map<String, dynamic> m, String id) => Calificacion(
        id: id,
        idServicio: (m['idServicio'] ?? '') as String,
        deUsuarioId: (m['deUsuarioId'] ?? '') as String,
        paraUsuarioId: (m['paraUsuarioId'] ?? '') as String,
        estrellas: (m['estrellas'] as num?)?.toInt() ?? 0,
        comentario: m['comentario'] as String?,
        creadoEn: dt(m['creadoEn']),
      );
}
