// ============================================================================
// Archivo: servicio.dart
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Propósito
// ---------
// Define la estructura principal del dominio de negocio de Qorinti: **Servicio**,
// junto con todas las entidades y enumeraciones relacionadas al ciclo de vida
// del servicio, ruta, pagos, comprobantes y comisiones.
//
// Este archivo constituye el núcleo del modelo operacional de la aplicación,
// permitiendo representar desde la solicitud de viaje hasta la liquidación
// final con comprobantes y comisiones.
//
// Alcance e integración
// ---------------------
// - Se integra con el módulo de planificación (`PlanRuta`) y con modelos de
//   facturación (`ComprobanteCliente`, `ComisionServicio`).
// - Compatible con Firestore mediante serialización robusta (`toMap` / `fromMap`).
// - Incluye enums de control de flujo, pagos y estados operativos.
// - Utiliza `Equatable` para soporte en patrones BLoC y comparaciones estructurales.
// ============================================================================

import 'utils.dart';
import 'package:equatable/equatable.dart';

/// ----------------------------------------------------------------------------
/// PUNTO DE RUTA
/// ----------------------------------------------------------------------------
/// Representa una ubicación dentro de la ruta de un servicio (origen, parada o destino),
/// incluyendo coordenadas, dirección y marcas temporales estimadas o de registro.
class PuntoRuta {
  final String direccion;
  final double? lat;
  final double? lng;
  final DateTime? eta;     
  final DateTime? checkAt; 

  const PuntoRuta({
    required this.direccion,
    this.lat,
    this.lng,
    this.eta,
    this.checkAt,
  });

  Map<String, dynamic> toMap() => {
        'direccion': direccion,
        'lat': lat,
        'lng': lng,
        'eta': fsts(eta),
        'checkAt': fsts(checkAt),
      }..removeWhere((k, v) => v == null);

  factory PuntoRuta.fromMap(Map<String, dynamic> m) => PuntoRuta(
        direccion: (m['direccion'] ?? '') as String,
        lat: toDoubleF(m['lat']),
        lng: toDoubleF(m['lng']),
        eta: dt(m['eta']),
        checkAt: dt(m['checkAt']),
      );
}

/// ----------------------------------------------------------------------------
/// ENUMERACIONES PRINCIPALES
/// ----------------------------------------------------------------------------

enum TipoServicio { taxi, carga_ligera, carga_pesada, mudanza }
extension TipoServicioX on TipoServicio {
  String get code => toString().split('.').last.toUpperCase();
  static TipoServicio fromString(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'CARGA_LIGERA': return TipoServicio.carga_ligera;
      case 'CARGA_PESADA': return TipoServicio.carga_pesada;
      case 'MUDANZA':      return TipoServicio.mudanza;
      default:             return TipoServicio.taxi;
    }
  }
}

enum MetodoPago { efectivo, yape, plin, transferencia }
extension MetodoPagoX on MetodoPago {
  String get code => toString().split('.').last.toUpperCase();
  static MetodoPago fromString(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'YAPE':          return MetodoPago.yape;
      case 'PLIN':          return MetodoPago.plin;
      case 'TRANSFERENCIA': return MetodoPago.transferencia;
      default:              return MetodoPago.efectivo;
    }
  }
}

enum TipoComprobante { ninguno, boleta, factura }
extension TipoComprobanteX on TipoComprobante {
  String get code => toString().split('.').last.toUpperCase();
  static TipoComprobante fromString(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'BOLETA':  return TipoComprobante.boleta;
      case 'FACTURA': return TipoComprobante.factura;
      default:        return TipoComprobante.ninguno;
    }
  }
}

enum EstadoServicio { pendiente_ofertas, aceptado, en_curso, finalizado, cancelado }
extension EstadoServicioX on EstadoServicio {
  String get code => toString().split('.').last.toUpperCase();
  static EstadoServicio fromString(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'ACEPTADO':         return EstadoServicio.aceptado;
      case 'EN_CURSO':         return EstadoServicio.en_curso;
      case 'FINALIZADO':       return EstadoServicio.finalizado;
      case 'CANCELADO':        return EstadoServicio.cancelado;
      default:                 return EstadoServicio.pendiente_ofertas;
    }
  }
}

enum EstadoComprobante { pendiente, adjuntado, entregado }
extension EstadoComprobanteX on EstadoComprobante {
  String get code => toString().split('.').last.toUpperCase();
  static EstadoComprobante fromString(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'ADJUNTADO': return EstadoComprobante.adjuntado;
      case 'ENTREGADO': return EstadoComprobante.entregado;
      default:          return EstadoComprobante.pendiente;
    }
  }
}

/// ----------------------------------------------------------------------------
/// COMPROBANTE CLIENTE
/// ----------------------------------------------------------------------------
/// Representa la información fiscal del comprobante emitido al cliente
/// asociado a un servicio (boleta, factura o ninguno).
class ComprobanteCliente {
  final TipoComprobante tipo;            
  final Map<String, String> receptor;      
  final String? urlPdf;
  final String? urlFoto;
  final String? serieNumero;                 
  final EstadoComprobante estado;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  const ComprobanteCliente({
    required this.tipo,
    required this.receptor,
    this.urlPdf,
    this.urlFoto,
    this.serieNumero,
    this.estado = EstadoComprobante.pendiente,
    this.creadoEn,
    this.actualizadoEn,
  });

  Map<String, dynamic> toMap() => {
        'tipo': tipo.code,
        'receptor': receptor,
        'urlPdf': urlPdf,
        'urlFoto': urlFoto,
        'serieNumero': serieNumero,
        'estado': estado.code,
        'creadoEn': fsts(creadoEn),
        'actualizadoEn': fsts(actualizadoEn),
      }..removeWhere((k, v) => v == null);

  factory ComprobanteCliente.fromMap(Map<String, dynamic> m) => ComprobanteCliente(
        tipo: TipoComprobanteX.fromString(m['tipo'] ?? 'NINGUNO'),
        receptor: Map<String, String>.from(m['receptor'] ?? const <String, String>{}),
        urlPdf: m['urlPdf'] as String?,
        urlFoto: m['urlFoto'] as String?,
        serieNumero: m['serieNumero'] as String?,
        estado: EstadoComprobanteX.fromString(m['estado'] ?? 'PENDIENTE'),
        creadoEn: dt(m['creadoEn']),
        actualizadoEn: dt(m['actualizadoEn']),
      );
}

/// ----------------------------------------------------------------------------
/// COMISIÓN DEL SERVICIO
/// ----------------------------------------------------------------------------
/// Representa la configuración y seguimiento de la comisión aplicada al servicio.
/// Permite definir base (porcentaje o monto fijo), monto calculado y estado de cobro.
enum BaseComision { porcentaje, fijo }
extension BaseComisionX on BaseComision {
  String get code => toString().split('.').last.toUpperCase();
  static BaseComision fromString(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'FIJO':  return BaseComision.fijo;
      default:      return BaseComision.porcentaje;
    }
  }
}

enum EstadoCobro { pendiente, reportado, pagado }
extension EstadoCobroX on EstadoCobro {
  String get code => toString().split('.').last.toUpperCase();
  static EstadoCobro fromString(dynamic v) {
    switch ('${v ?? ''}'.toUpperCase()) {
      case 'REPORTADO': return EstadoCobro.reportado;
      case 'PAGADO':    return EstadoCobro.pagado;
      default:          return EstadoCobro.pendiente;
    }
  }
}

class ComisionServicio {
  final BaseComision baseTipo;
  final double baseValor;     
  final double? monto;         
  final EstadoCobro estadoCobro;
  final DateTime? fechaDevengo; 
  final DateTime? fechaPago;   
  final String? voucherUrl;    
  final String? observaciones;

  const ComisionServicio({
    this.baseTipo = BaseComision.porcentaje,
    required this.baseValor,
    this.monto,
    this.estadoCobro = EstadoCobro.pendiente,
    this.fechaDevengo,
    this.fechaPago,
    this.voucherUrl,
    this.observaciones,
  });

  Map<String, dynamic> toMap() => {
        'baseTipo': baseTipo.code,
        'baseValor': baseValor,
        'monto': monto,
        'estadoCobro': estadoCobro.code,
        'fechaDevengo': fsts(fechaDevengo),
        'fechaPago': fsts(fechaPago),
        'voucherUrl': voucherUrl,
        'observaciones': observaciones,
      }..removeWhere((k, v) => v == null);

  factory ComisionServicio.fromMap(Map<String, dynamic> m) => ComisionServicio(
        baseTipo: BaseComisionX.fromString(m['baseTipo'] ?? 'PORCENTAJE'),
        baseValor: toDoubleF(m['baseValor']) ?? 0.0,
        monto: toDoubleF(m['monto']),
        estadoCobro: EstadoCobroX.fromString(m['estadoCobro'] ?? 'PENDIENTE'),
        fechaDevengo: dt(m['fechaDevengo']),
        fechaPago: dt(m['fechaPago']),
        voucherUrl: m['voucherUrl'] as String?,
        observaciones: m['observaciones'] as String?,
      );
}

/// ----------------------------------------------------------------------------
/// SERVICIO PRINCIPAL
/// ----------------------------------------------------------------------------
/// Entidad central del sistema que representa una solicitud de transporte.
/// Contiene los datos del usuario solicitante, conductor, vehículo, empresa,
/// estado operativo, pagos, comprobantes y comisiones asociadas.
/// ----------------------------------------------------------------------------
class Servicio extends Equatable {
  final String? id;
  final String idUsuarioSolicitante;
  final String? idConductor;          
  final String? idVehiculo;
  final String? idEmpresa;           
  final String? idOfertaSeleccionada; 
  final List<PuntoRuta> ruta;

  final TipoServicio tipoServicio;
  final double? distanciaKm;
  final int? tiempoEstimadoMin;  
  final int slaMin;              
  final double? precioEstimado;
  final double? precioFinal;     

  final MetodoPago metodoPago;
  final TipoComprobante tipoComprobante;
  final bool comisionPendiente;
  final bool pagoDentroApp;      

  final double? pesoTon;
  final double? volumenM3;
  final bool? requiereAyudantes;
  final int? cantidadAyudantes;
  final bool? requiereMontacargas;
  final String? notasCarga;

  final double? ubicacionConductorLat;
  final double? ubicacionConductorLng;

  final EstadoServicio estado;

  final DateTime? programadoPara; 
  final DateTime fechaSolicitud;  
  final DateTime? fechaAceptacion;
  final DateTime? fechaInicio;    
  final DateTime? fechaFin;    

  final int? calificacionConductor;
  final int? calificacionUsuario;

  final String? observaciones;

  final ComprobanteCliente? comprobanteCliente; 
  final ComisionServicio? comision;

  final int? duracionRealMin;

  /// Constructor principal con valores por defecto en tiempos y estados.
  Servicio({
    this.id,
    required this.idUsuarioSolicitante,
    this.idConductor,
    this.idVehiculo,
    this.idEmpresa,
    this.idOfertaSeleccionada,
    required this.ruta,
    this.tipoServicio = TipoServicio.taxi,
    this.distanciaKm,
    this.tiempoEstimadoMin,
    int? slaMin,
    this.precioEstimado,
    this.precioFinal,
    this.metodoPago = MetodoPago.efectivo,
    this.tipoComprobante = TipoComprobante.ninguno,
    this.comisionPendiente = false,
    this.pagoDentroApp = false,
    this.pesoTon,
    this.volumenM3,
    this.requiereAyudantes,
    this.cantidadAyudantes,
    this.requiereMontacargas,
    this.notasCarga,
    this.ubicacionConductorLat,
    this.ubicacionConductorLng,
    this.estado = EstadoServicio.pendiente_ofertas,
    this.programadoPara,
    DateTime? fechaSolicitud,   
    this.fechaAceptacion,
    this.fechaInicio,
    this.fechaFin,
    this.calificacionConductor,
    this.calificacionUsuario,
    this.observaciones,
    this.comprobanteCliente,
    this.comision,
    this.duracionRealMin,
  })  : slaMin = (slaMin ?? (tiempoEstimadoMin ?? 30)),
        fechaSolicitud = (fechaSolicitud ?? DateTime.now());

  /// Serialización a formato Firestore con limpieza de nulos.
  Map<String, dynamic> toMap() => {
        'idUsuarioSolicitante': idUsuarioSolicitante,
        'idConductor': idConductor,
        'idVehiculo': idVehiculo,
        'idEmpresa': idEmpresa,
        'idOfertaSeleccionada': idOfertaSeleccionada,
        'ruta': ruta.map((e) => e.toMap()).toList(),
        'tipoServicio': tipoServicio.code,
        'distanciaKm': distanciaKm,
        'tiempoEstimadoMin': tiempoEstimadoMin,
        'slaMin': slaMin,
        'precioEstimado': precioEstimado,
        'precioFinal': precioFinal,
        'metodoPago': metodoPago.code,
        'tipoComprobante': tipoComprobante.code,
        'comisionPendiente': comisionPendiente,
        'pagoDentroApp': pagoDentroApp,
        'pesoTon': pesoTon,
        'volumenM3': volumenM3,
        'requiereAyudantes': requiereAyudantes,
        'cantidadAyudantes': cantidadAyudantes,
        'requiereMontacargas': requiereMontacargas,
        'notasCarga': notasCarga,
        'ubicacionConductor': (ubicacionConductorLat != null && ubicacionConductorLng != null)
            ? {'lat': ubicacionConductorLat, 'lng': ubicacionConductorLng}
            : null,
        'estado': estado.code,
        'programadoPara': fsts(programadoPara),
        'fechaSolicitud': fsts(fechaSolicitud),
        'fechaAceptacion': fsts(fechaAceptacion),
        'fechaInicio': fsts(fechaInicio),
        'fechaFin': fsts(fechaFin),
        'calificacionConductor': calificacionConductor,
        'calificacionUsuario': calificacionUsuario,
        'observaciones': observaciones,
        'comprobanteCliente': comprobanteCliente?.toMap(),
        'comision': comision?.toMap(),
        'duracionRealMin': duracionRealMin,
      }..removeWhere((k, v) => v == null);

  static bool _b(dynamic v) => v == true || (v is String && v.toLowerCase() == 'true');

  /// Factoría para reconstrucción desde Firestore.
  factory Servicio.fromMap(Map<String, dynamic> map, {String? id}) => Servicio(
        id: id,
        idUsuarioSolicitante: (map['idUsuarioSolicitante'] ?? '') as String,
        idConductor: map['idConductor'] as String?,
        idVehiculo: map['idVehiculo'] as String?,
        idEmpresa: map['idEmpresa'] as String?,
        idOfertaSeleccionada: map['idOfertaSeleccionada'] as String?,
        ruta: (map['ruta'] as List<dynamic>? ?? [])
            .map((e) => PuntoRuta.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        tipoServicio: TipoServicioX.fromString(map['tipoServicio'] ?? 'TAXI'),
        distanciaKm: toDoubleF(map['distanciaKm']),
        tiempoEstimadoMin: toIntF(map['tiempoEstimadoMin']),
        slaMin: toIntF(map['slaMin']) ?? (toIntF(map['tiempoEstimadoMin']) ?? 30),
        precioEstimado: toDoubleF(map['precioEstimado']),
        precioFinal: toDoubleF(map['precioFinal']),
        metodoPago: MetodoPagoX.fromString(map['metodoPago'] ?? 'EFECTIVO'),
        tipoComprobante: TipoComprobanteX.fromString(map['tipoComprobante'] ?? 'NINGUNO'),
        comisionPendiente: _b(map['comisionPendiente']),
        pagoDentroApp: _b(map['pagoDentroApp']),
        pesoTon: toDoubleF(map['pesoTon']),
        volumenM3: toDoubleF(map['volumenM3']),
        requiereAyudantes: _b(map['requiereAyudantes']),
        cantidadAyudantes: toIntF(map['cantidadAyudantes']),
        requiereMontacargas: _b(map['requiereMontacargas']),
        notasCarga: map['notasCarga'] as String?,
        ubicacionConductorLat: toDoubleF(map['ubicacionConductor']?['lat']),
        ubicacionConductorLng: toDoubleF(map['ubicacionConductor']?['lng']),
        estado: EstadoServicioX.fromString(map['estado'] ?? 'PENDIENTE_OFERTAS'),
        programadoPara: dt(map['programadoPara']),
        fechaSolicitud: dt(map['fechaSolicitud']) ?? DateTime.now(),
        fechaAceptacion: dt(map['fechaAceptacion']),
        fechaInicio: dt(map['fechaInicio']),
        fechaFin: dt(map['fechaFin']),
        calificacionConductor: toIntF(map['calificacionConductor']),
        calificacionUsuario: toIntF(map['calificacionUsuario']),
        observaciones: map['observaciones'] as String?,
        comprobanteCliente: (map['comprobanteCliente'] is Map)
            ? ComprobanteCliente.fromMap(Map<String, dynamic>.from(map['comprobanteCliente'] as Map))
            : null,
        comision: (map['comision'] is Map)
            ? ComisionServicio.fromMap(Map<String, dynamic>.from(map['comision'] as Map))
            : null,
        duracionRealMin: toIntF(map['duracionRealMin']),
      );

  /// Tiempo desde la solicitud hasta la aceptación del servicio.
  int? get tpaMin => (fechaAceptacion != null)
      ? fechaAceptacion!.difference(fechaSolicitud).inMinutes
      : null;

  /// Calcula la duración real del servicio, usando marca de inicio/fin o valor fijo.
  int? get duracionMinCalculada {
    if (duracionRealMin != null) return duracionRealMin;
    if (fechaInicio != null && fechaFin != null) {
      return fechaFin!.difference(fechaInicio!).inMinutes;
    }
    return null;
  }

  /// Verifica cumplimiento de SLA (tiempo dentro del límite).
  bool? get cumpleSLA {
    final d = duracionMinCalculada;
    if (d == null) return null;
    return d <= slaMin;
  }

  /// Crea una copia modificada del servicio sin alterar la instancia original.
  Servicio copyWith({
    String? id,
    String? idUsuarioSolicitante,
    String? idConductor,
    String? idVehiculo,
    String? idEmpresa,
    String? idOfertaSeleccionada,
    List<PuntoRuta>? ruta,
    TipoServicio? tipoServicio,
    double? distanciaKm,
    int? tiempoEstimadoMin,
    int? slaMin,
    double? precioEstimado,
    double? precioFinal,
    MetodoPago? metodoPago,
    TipoComprobante? tipoComprobante,
    bool? comisionPendiente,
    bool? pagoDentroApp,
    double? pesoTon,
    double? volumenM3,
    bool? requiereAyudantes,
    int? cantidadAyudantes,
    bool? requiereMontacargas,
    String? notasCarga,
    double? ubicacionConductorLat,
    double? ubicacionConductorLng,
    EstadoServicio? estado,
    DateTime? programadoPara,
    DateTime? fechaSolicitud,
    DateTime? fechaAceptacion,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int? calificacionConductor,
    int? calificacionUsuario,
    String? observaciones,
    ComprobanteCliente? comprobanteCliente,
    ComisionServicio? comision,
    int? duracionRealMin,
  }) {
    return Servicio(
      id: id ?? this.id,
      idUsuarioSolicitante: idUsuarioSolicitante ?? this.idUsuarioSolicitante,
      idConductor: idConductor ?? this.idConductor,
      idVehiculo: idVehiculo ?? this.idVehiculo,
      idEmpresa: idEmpresa ?? this.idEmpresa,
      idOfertaSeleccionada: idOfertaSeleccionada ?? this.idOfertaSeleccionada,
      ruta: ruta ?? this.ruta,
      tipoServicio: tipoServicio ?? this.tipoServicio,
      distanciaKm: distanciaKm ?? this.distanciaKm,
      tiempoEstimadoMin: tiempoEstimadoMin ?? this.tiempoEstimadoMin,
      slaMin: slaMin ?? this.slaMin,
      precioEstimado: precioEstimado ?? this.precioEstimado,
      precioFinal: precioFinal ?? this.precioFinal,
      metodoPago: metodoPago ?? this.metodoPago,
      tipoComprobante: tipoComprobante ?? this.tipoComprobante,
      comisionPendiente: comisionPendiente ?? this.comisionPendiente,
      pagoDentroApp: pagoDentroApp ?? this.pagoDentroApp,
      pesoTon: pesoTon ?? this.pesoTon,
      volumenM3: volumenM3 ?? this.volumenM3,
      requiereAyudantes: requiereAyudantes ?? this.requiereAyudantes,
      cantidadAyudantes: cantidadAyudantes ?? this.cantidadAyudantes,
      requiereMontacargas: requiereMontacargas ?? this.requiereMontacargas,
      notasCarga: notasCarga ?? this.notasCarga,
      ubicacionConductorLat: ubicacionConductorLat ?? this.ubicacionConductorLat,
      ubicacionConductorLng: ubicacionConductorLng ?? this.ubicacionConductorLng,
      estado: estado ?? this.estado,
      programadoPara: programadoPara ?? this.programadoPara,
      fechaSolicitud: fechaSolicitud ?? this.fechaSolicitud,
      fechaAceptacion: fechaAceptacion ?? this.fechaAceptacion,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      calificacionConductor: calificacionConductor ?? this.calificacionConductor,
      calificacionUsuario: calificacionUsuario ?? this.calificacionUsuario,
      observaciones: observaciones ?? this.observaciones,
      comprobanteCliente: comprobanteCliente ?? this.comprobanteCliente,
      comision: comision ?? this.comision,
      duracionRealMin: duracionRealMin ?? this.duracionRealMin,
    );
  }

  @override
  List<Object?> get props => [
        id,
        idUsuarioSolicitante,
        idConductor,
        idVehiculo,
        idEmpresa,
        idOfertaSeleccionada,
        ruta,
        tipoServicio,
        distanciaKm,
        tiempoEstimadoMin,
        slaMin,
        precioEstimado,
        precioFinal,
        metodoPago,
        tipoComprobante,
        comisionPendiente,
        pagoDentroApp,
        pesoTon,
        volumenM3,
        requiereAyudantes,
        cantidadAyudantes,
        requiereMontacargas,
        notasCarga,
        ubicacionConductorLat,
        ubicacionConductorLng,
        estado,
        programadoPara,
        fechaSolicitud,
        fechaAceptacion,
        fechaInicio,
        fechaFin,
        calificacionConductor,
        calificacionUsuario,
        observaciones,
        comprobanteCliente,
        comision,
        duracionRealMin,
      ];
}
