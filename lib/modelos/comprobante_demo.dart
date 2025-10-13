// ============================================================================
// Archivo: comprobante_demo.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito del archivo
// ---------------------
// Define el modelo de datos temporal **ComprobanteDemo**, utilizado en entornos
// de prueba o demostración para simular comprobantes electrónicos (boletas o
// facturas) asociados a los servicios de transporte. Este modelo replica la
// estructura de un comprobante real, pero con fines de validación, pruebas
// visuales o demostraciones sin conexión con sistemas SUNAT.
//
// Alcance e integración
// ---------------------
// - Se integra con el modelo `ComprobanteCliente` (servicio.dart) para generar
//   o convertir comprobantes simulados.
// - Contiene conversiones a/desde Firestore, adaptando tipos (`Timestamp`,
//   `DateTime`, `String`, `num`).
// - Define enumeraciones `EmisorDemo` y `TipoComprobanteDemo` para representar
//   de manera controlada el origen y tipo de comprobante.
// - Implementa `Equatable` para asegurar comparaciones estructurales y
//   compatibilidad con patrones BLoC y estados inmutables.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'servicio.dart';

/// Enumeración que representa al emisor del comprobante en modo demostración.
/// Puede ser la empresa Qorinti o el conductor.
enum EmisorDemo { qorinti, conductor }

/// Extensión para agregar métodos utilitarios de conversión y etiquetas
/// legibles de la enumeración `EmisorDemo`.
extension EmisorDemoX on EmisorDemo {
  String get label => this == EmisorDemo.qorinti ? 'Qorinti (DEMO)' : 'Conductor (DEMO)';
  String get toFirestore => this == EmisorDemo.qorinti ? 'QORINTI' : 'CONDUCTOR';

  static EmisorDemo fromString(dynamic v) {
    final s = ('${v ?? ''}').toUpperCase().trim();
    return s == 'QORINTI' ? EmisorDemo.qorinti : EmisorDemo.conductor;
  }
}

/// Enumeración que define el tipo de comprobante: Boleta o Factura.
enum TipoComprobanteDemo { boleta, factura }

/// Extensión con conversiones y utilidades asociadas al tipo de comprobante.
extension TipoComprobanteDemoX on TipoComprobanteDemo {
  String get label => this == TipoComprobanteDemo.factura ? 'Factura' : 'Boleta';
  String get toFirestore => this == TipoComprobanteDemo.factura ? 'FACTURA' : 'BOLETA';

  static TipoComprobanteDemo fromString(dynamic v) {
    final s = ('${v ?? ''}').toUpperCase().trim();
    return s == 'FACTURA' ? TipoComprobanteDemo.factura : TipoComprobanteDemo.boleta;
  }

  /// Conversión hacia el enum usado en el dominio principal del servicio.
  TipoComprobante toServicioEnum() =>
      this == TipoComprobanteDemo.factura ? TipoComprobante.factura : TipoComprobante.boleta;

  /// Conversión desde el enum de dominio hacia el modelo de demostración.
  static TipoComprobanteDemo fromServicioEnum(TipoComprobante t) =>
      t == TipoComprobante.factura ? TipoComprobanteDemo.factura : TipoComprobanteDemo.boleta;
}

/// Modelo de comprobante en modo demostración. Incluye datos del emisor,
/// receptor, totales, tipo de documento y enlaces asociados.
class ComprobanteDemo extends Equatable {
  final EmisorDemo emisor;              
  final TipoComprobanteDemo tipo;

  final String serie;                   
  final String numero;             
  final String serieNumero;              

  final double total;
  final DateTime fecha;
  final String urlPdf;

  final String? urlFoto;

  final String? ruc;
  final String? razonSocial;
  final String? direccionFiscal;

  final String? nombreCliente;
  final String? dniCliente;

  final String? emisorNombre;    
  final String? emisorDocTipo;    
  final String? emisorDoc;         
  final String? emisorDireccion;  

  const ComprobanteDemo({
    required this.emisor,
    required this.tipo,
    required this.serie,
    required this.numero,
    required this.serieNumero,
    required this.total,
    required this.fecha,
    required this.urlPdf,
    this.urlFoto,
    this.ruc,
    this.razonSocial,
    this.direccionFiscal,
    this.nombreCliente,
    this.dniCliente,
    this.emisorNombre,
    this.emisorDocTipo,
    this.emisorDoc,
    this.emisorDireccion,
  });

  /// Conversión robusta de diferentes tipos a `DateTime`.
  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      final p = DateTime.tryParse(v);
      if (p != null) return p;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Conversión segura a `double` para el campo total.
  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0.0;
  }

  /// Serialización a formato Map para persistencia en Firestore.
  Map<String, dynamic> toMap() => {
        'emisor': emisor.toFirestore,
        'tipo': tipo.toFirestore,
        'serie': serie,
        'numero': numero,
        'serieNumero': serieNumero,
        'total': total,
        'fecha': Timestamp.fromDate(fecha),
        'urlPdf': urlPdf,
        if (urlFoto != null) 'urlFoto': urlFoto,

        if (ruc != null) 'ruc': ruc,
        if (razonSocial != null) 'razonSocial': razonSocial,
        if (direccionFiscal != null) 'direccionFiscal': direccionFiscal,
        if (nombreCliente != null) 'nombreCliente': nombreCliente,
        if (dniCliente != null) 'dniCliente': dniCliente,

        if (emisorNombre != null) 'emisorNombre': emisorNombre,
        if (emisorDocTipo != null) 'emisorDocTipo': emisorDocTipo,
        if (emisorDoc != null) 'emisorDoc': emisorDoc,
        if (emisorDireccion != null) 'emisorDireccion': emisorDireccion,
      };

  /// Factoría para crear una instancia desde un Map (lectura desde Firestore).
  factory ComprobanteDemo.fromMap(Map<String, dynamic> m) => ComprobanteDemo(
        emisor: EmisorDemoX.fromString(m['emisor']),
        tipo: TipoComprobanteDemoX.fromString(m['tipo']),
        serie: (m['serie'] ?? '').toString(),
        numero: (m['numero'] ?? '').toString(),
        serieNumero: (m['serieNumero'] ?? '').toString(),
        total: _toDouble(m['total']),
        fecha: _toDate(m['fecha']),
        urlPdf: (m['urlPdf'] ?? '').toString(),
        urlFoto: m['urlFoto'] as String?,
        ruc: m['ruc'] as String?,
        razonSocial: m['razonSocial'] as String?,
        direccionFiscal: m['direccionFiscal'] as String?,
        nombreCliente: m['nombreCliente'] as String?,
        dniCliente: m['dniCliente'] as String?,
        emisorNombre: m['emisorNombre'] as String?,
        emisorDocTipo: m['emisorDocTipo'] as String?,
        emisorDoc: m['emisorDoc'] as String?,
        emisorDireccion: m['emisorDireccion'] as String?,
      );

  /// Conversión del comprobante de demostración a `ComprobanteCliente`
  /// (modelo de dominio real) para interoperabilidad con el sistema principal.
  ComprobanteCliente toComprobanteCliente() {
    final Map<String, String> receptor = <String, String>{};
    if (tipo == TipoComprobanteDemo.factura) {
      receptor['ruc'] = (ruc ?? '');
      receptor['razon'] = (razonSocial ?? '');
      receptor['direccion'] = (direccionFiscal ?? '');
    } else {
      receptor['nombre'] = (nombreCliente ?? '');
      final dni = (dniCliente ?? '').trim();
      if (dni.isNotEmpty) receptor['dni'] = dni;
    }

    return ComprobanteCliente(
      tipo: tipo.toServicioEnum(),
      receptor: receptor,
      urlPdf: urlPdf.trim().isNotEmpty ? urlPdf : null,
      urlFoto: urlFoto,
      serieNumero: serieNumero.trim().isNotEmpty ? serieNumero : null,
      estado: EstadoComprobante.adjuntado,
      creadoEn: fecha,
      actualizadoEn: DateTime.now(),
    );
  }

  /// Crea un comprobante de demostración a partir de un comprobante cliente.
  static ComprobanteDemo fromComprobanteCliente({
    required ComprobanteCliente c,
    required EmisorDemo emisor, 
    required double total,
    required String serie,      
    required String numero,
  }) {
    final tipoDemo = TipoComprobanteDemoX.fromServicioEnum(c.tipo);
    final serieNum = c.serieNumero ?? [serie, numero].where((e) => e.isNotEmpty).join('-');

    return ComprobanteDemo(
      emisor: emisor,
      tipo: tipoDemo,
      serie: serie,
      numero: numero,
      serieNumero: serieNum,
      total: total,
      fecha: c.creadoEn ?? DateTime.now(),
      urlPdf: c.urlPdf ?? '',
      urlFoto: c.urlFoto,
      ruc: c.receptor['ruc'],
      razonSocial: c.receptor['razon'],
      direccionFiscal: c.receptor['direccion'],
      nombreCliente: c.receptor['nombre'],
      dniCliente: c.receptor['dni'],
    );
  }

  /// Devuelve una representación legible de la serie y número.
  String get serieNumeroPretty {
    if (serieNumero.trim().isNotEmpty) return serieNumero;
    final s = serie.trim(), n = numero.trim();
    return [s, n].where((e) => e.isNotEmpty).join('-');
  }

  /// Indica si el comprobante cuenta con un enlace PDF válido.
  bool get tienePdf => urlPdf.trim().isNotEmpty;

  /// Permite generar una copia modificada manteniendo la inmutabilidad del modelo.
  ComprobanteDemo copyWith({
    EmisorDemo? emisor,
    TipoComprobanteDemo? tipo,
    String? serie,
    String? numero,
    String? serieNumero,
    double? total,
    DateTime? fecha,
    String? urlPdf,
    String? urlFoto,
    String? ruc,
    String? razonSocial,
    String? direccionFiscal,
    String? nombreCliente,
    String? dniCliente,
    String? emisorNombre,
    String? emisorDocTipo,
    String? emisorDoc,
    String? emisorDireccion,
  }) {
    return ComprobanteDemo(
      emisor: emisor ?? this.emisor,
      tipo: tipo ?? this.tipo,
      serie: serie ?? this.serie,
      numero: numero ?? this.numero,
      serieNumero: serieNumero ?? this.serieNumero,
      total: total ?? this.total,
      fecha: fecha ?? this.fecha,
      urlPdf: urlPdf ?? this.urlPdf,
      urlFoto: urlFoto ?? this.urlFoto,
      ruc: ruc ?? this.ruc,
      razonSocial: razonSocial ?? this.razonSocial,
      direccionFiscal: direccionFiscal ?? this.direccionFiscal,
      nombreCliente: nombreCliente ?? this.nombreCliente,
      dniCliente: dniCliente ?? this.dniCliente,
      emisorNombre: emisorNombre ?? this.emisorNombre,
      emisorDocTipo: emisorDocTipo ?? this.emisorDocTipo,
      emisorDoc: emisorDoc ?? this.emisorDoc,
      emisorDireccion: emisorDireccion ?? this.emisorDireccion,
    );
  }

  @override
  List<Object?> get props => [
        emisor,
        tipo,
        serie,
        numero,
        serieNumero,
        total,
        fecha,
        urlPdf,
        urlFoto,
        ruc,
        razonSocial,
        direccionFiscal,
        nombreCliente,
        dniCliente,
        emisorNombre,
        emisorDocTipo,
        emisorDoc,
        emisorDireccion,
      ];
}
