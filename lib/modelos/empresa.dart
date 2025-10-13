// ============================================================================
// Archivo: empresa.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito del archivo
// ---------------------
// Define la entidad de dominio **Empresa**, que representa a clientes o
// entidades emisoras/receptoras dentro del sistema. Centraliza datos fiscales
// (razón social, RUC, dirección), estado operativo y metadatos útiles para la
// emisión/recepción de comprobantes (series, correo de facturación), así como
// elementos de identidad visual (logo).
//
// Alcance e integración
// ---------------------
// - Persistencia: serializa/deserializa con Firestore mediante `toMap` y
//   `fromMap`, utilizando utilidades de `utils.dart` (`fsts`, `dt`) para
//   manejo consistente de fechas.
// - Operación: `estado` permite controlar habilitación de la empresa en
//   procesos de registro de servicios y facturación.
// - Configuración: campos como `serieBoleta` y `serieFactura` facilitan la
//   parametrización de numeración de documentos.
// ============================================================================

import 'utils.dart';

/// ----------------------------------------------------------------------------
/// Entidad de dominio: Empresa
/// ----------------------------------------------------------------------------
/// Contiene datos fiscales y de contacto, así como parámetros de facturación
/// y trazabilidad temporal para su administración en el sistema.
// ----------------------------------------------------------------------------
class Empresa {
  final String? id;
  final String razonSocial;
  final String ruc;

  final String estado;
  final String? direccionFiscal;
  final String? emailFacturacion;
  final String? telefono;
  final String? logoUrl;
  final String? giroNegocio;
  final String? serieBoleta;
  final String? serieFactura;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Constructor inmutable con valores por defecto para estado operativo.
  const Empresa({
    this.id,
    required this.razonSocial,
    required this.ruc,
    this.estado = 'ACTIVA',
    this.direccionFiscal,
    this.emailFacturacion,
    this.telefono,
    this.logoUrl,
    this.giroNegocio,
    this.serieBoleta,
    this.serieFactura,
    this.creadoEn,
    this.actualizadoEn,
  });

  /// Serialización a Map para persistencia en Firestore.
  /// - Convierte fechas con `fsts`.
  /// - Elimina claves nulas para evitar sobreescrituras indeseadas.
  Map<String, dynamic> toMap() => {
        'razonSocial': razonSocial,
        'ruc': ruc,
        'estado': estado,
        'direccionFiscal': direccionFiscal,
        'emailFacturacion': emailFacturacion,
        'telefono': telefono,
        'logoUrl': logoUrl,
        'giroNegocio': giroNegocio,
        'serieBoleta': serieBoleta,
        'serieFactura': serieFactura,
        'creadoEn': fsts(creadoEn),
        'actualizadoEn': fsts(actualizadoEn),
      }..removeWhere((k, v) => v == null);

  /// Factoría desde Map (lectura Firestore) con valores de respaldo.
  factory Empresa.fromMap(Map<String, dynamic> map, {String? id}) => Empresa(
        id: id,
        razonSocial: (map['razonSocial'] ?? '') as String,
        ruc: (map['ruc'] ?? '') as String,
        estado: (map['estado'] ?? 'ACTIVA') as String,
        direccionFiscal: map['direccionFiscal'] as String?,
        emailFacturacion: map['emailFacturacion'] as String?,
        telefono: map['telefono'] as String?,
        logoUrl: map['logoUrl'] as String?,
        giroNegocio: map['giroNegocio'] as String?,
        serieBoleta: map['serieBoleta'] as String?,
        serieFactura: map['serieFactura'] as String?,
        creadoEn: dt(map['creadoEn']),
        actualizadoEn: dt(map['actualizadoEn']),
      );
}
