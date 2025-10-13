// ============================================================================
// Archivo: utils.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Conjunto de utilidades comunes para conversión de tipos y formateo de fechas,
// orientadas a interoperar de forma segura con Firestore (`Timestamp`) y capas
// de presentación (formateo con `intl`).
//
// Alcance
// -------
// - Conversión robusta entre `dynamic` y tipos primitivos (bool, double, int).
// - Normalización de fechas: `dt` (dynamic → DateTime?), `fsts` (DateTime? → Timestamp?).
// - Formateo estándar de fechas/horas para UI.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// ----------------------------------------------------------------------------
/// Fechas y Timestamps
/// ----------------------------------------------------------------------------
/// `dt` convierte valores dinámicos (`Timestamp`, `DateTime`, `String`) a
/// `DateTime?`. Devuelve `null` cuando la conversión no es posible.
DateTime? dt(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return DateTime.tryParse('$v');
}

/// Convierte `DateTime?` a `Timestamp?` para compatibilidad con Firestore.
Object? fsts(DateTime? d) => d == null ? null : Timestamp.fromDate(d);

/// ----------------------------------------------------------------------------
/// Conversión genérica de tipos primitivos
/// ----------------------------------------------------------------------------
/// `toBool`: coerción segura desde `dynamic` a `bool?` con convenciones
/// comunes (num ≠ 0 → true; 'true'/'1' → true).
bool? toBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.toLowerCase() == 'true' || v == '1';
  return null;
}

/// `toDoubleF`: parsea valores numéricos/strings a `double?`.
double? toDoubleF(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

/// `toIntF`: parsea valores numéricos/strings a `int?`.
int? toIntF(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

/// ----------------------------------------------------------------------------
/// Formateo para UI
/// ----------------------------------------------------------------------------
/// `formatDate`: devuelve la fecha en el patrón indicado (por defecto dd/MM/yyyy).
String formatDate(DateTime? fecha, {String pattern = 'dd/MM/yyyy'}) {
  if (fecha == null) return '-';
  return DateFormat(pattern).format(fecha);
}

/// `formatDateTime`: fecha y hora en el patrón indicado (por defecto dd/MM/yyyy HH:mm).
String formatDateTime(DateTime? fecha, {String pattern = 'dd/MM/yyyy HH:mm'}) {
  if (fecha == null) return '-';
  return DateFormat(pattern).format(fecha);
}
