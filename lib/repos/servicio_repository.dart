// lib/repos/servicio_repository.dart
//
// Repositorio principal para la gestión de servicios dentro de la aplicación Qorinti.
// Implementa las operaciones CRUD, flujos de negocio y sincronización en tiempo real 
// con Firestore para entidades como Servicio, Oferta, EstadoCuentaConductor y TransaccionConductor.
//
// Este repositorio sirve como capa intermedia entre la lógica de negocio (BLoC) y la base de datos.
// Maneja streams de Firestore, transacciones atómicas y cálculo de métricas auxiliares.
//
// Notas de diseño:
// - Utiliza convenciones upper-case para los códigos de estado de Servicio y Oferta.
// - Emplea streams reactivos para actualizaciones en tiempo real.
// - Incluye funciones para devengar comisiones, procesar pagos, registrar transacciones,
//   y mantener consistencia en los estados del ciclo de vida del servicio.
//
// Dependencias: cloud_firestore, modelos de dominio de Qorinti.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_qorinti/modelos/servicio.dart';
import 'package:app_qorinti/modelos/oferta.dart';
import 'package:app_qorinti/modelos/estado_cuenta_conductor.dart';
import 'package:app_qorinti/modelos/transaccion_conductor.dart';

class ServicioRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Límites de paginación y carga de resultados.
  static const int _SOL_LIMIT = 50;
  static const int _OFERT_LIMIT = 50;
  static const int _HIST_LIMIT = 100;

  // Referencia base a la colección principal de servicios.
  CollectionReference<Map<String, dynamic>> get _serviciosRef =>
      _db.collection('servicios');

  // ============================================================
  // Utilidades internas y funciones de mapeo
  // ============================================================

  /// Convierte un QuerySnapshot de Firestore a una lista de objetos [Servicio].
  List<Servicio> _mapServicios(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map((d) => Servicio.fromMap(d.data(), id: d.id)).toList();

  /// Ordena localmente un historial de servicios por fecha de finalización o solicitud (más recientes primero).
  void _ordenarHistorialLocal(List<Servicio> items) {
    items.sort((a, b) {
      final DateTime da = a.fechaFin ?? a.fechaSolicitud;
      final DateTime db = b.fechaFin ?? b.fechaSolicitud;

      final int na = da.millisecondsSinceEpoch;
      final int nb = db.millisecondsSinceEpoch;

      return nb.compareTo(na);
    });
  }

  /// Redondea valores numéricos a dos decimales.
  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  /// Calcula la diferencia en minutos entre dos Timestamps de Firestore.
  int _minsBetween(Timestamp? a, Timestamp? b) {
    if (a == null || b == null) return 0;
    final start = a.toDate();
    final end = b.toDate();
    final diff = end.difference(start).inMinutes;
    return diff < 0 ? 0 : diff;
  }

  // ============================================================
  // Streams en tiempo real (escucha de cuentas y transacciones)
  // ============================================================

  /// Escucha los cambios en el estado de cuenta de un conductor en tiempo real.
  Stream<EstadoCuentaConductor?> escucharEstadoCuentaConductor(String idConductor) {
    final ref = _db.collection('estado_cuenta_conductor').doc(idConductor);
    return ref.snapshots().map((doc) {
      if (!doc.exists) return null;
      return EstadoCuentaConductor.fromMap(doc.data()!, id: doc.id);
    });
  }

  /// Escucha las transacciones asociadas a un conductor ordenadas por fecha de creación descendente.
  Stream<List<TransaccionConductor>> escucharTransaccionesConductor(
    String idConductor, {
    int limit = 50,
  }) {
    final ref = _db
        .collection('transacciones_conductor')
        .where('idConductor', isEqualTo: idConductor)
        .orderBy('creadoEn', descending: true)
        .limit(limit);

    return ref.snapshots().map(
      (qs) => qs.docs.map((d) => TransaccionConductor.fromMap(d.data(), d.id)).toList(),
    );
  }

  // ============================================================
  // Operaciones de ofertas y validaciones
  // ============================================================

  /// Marca una oferta como rechazada dentro de un servicio específico.
  Future<void> rechazarOferta({
    required String servicioId,
    required String ofertaId,
  }) async {
    final servRef = _serviciosRef.doc(servicioId);
    final ofertaRef = servRef.collection('ofertas').doc(ofertaId);

    await _db.runTransaction((tx) async {
      final servSnap = await tx.get(servRef);
      if (!servSnap.exists) throw Exception('Servicio no existe');

      final estadoSrv = (servSnap.data()?['estado'] ?? '').toString().toUpperCase();
      if (estadoSrv != EstadoServicio.pendiente_ofertas.code) return;

      final ofertaSnap = await tx.get(ofertaRef);
      if (!ofertaSnap.exists) throw Exception('Oferta no existe');

      final estadoActual = (ofertaSnap.data()?['estado'] ?? '').toString().toUpperCase();
      if (estadoActual == EstadoOferta.rechazada.name) return;

      tx.update(ofertaRef, {
        'estado': EstadoOferta.rechazada.name,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });
  }

  // ============================================================
  // Creación y consulta de servicios
  // ============================================================

  /// Crea un nuevo servicio en Firestore y devuelve su ID.
  /// Incluye inicialización de campos de auditoría y asociación con empresa si aplica.
  Future<String> crearServicio(Servicio servicio) async {
    try {
      final data = servicio.toMap()
        ..addAll({
          'estado': EstadoServicio.pendiente_ofertas.code,
          'precioFinal': null,
          'fechaSolicitud': FieldValue.serverTimestamp(),
          'fechaCreacion': FieldValue.serverTimestamp(),
        });

      data['slaMin'] = data['slaMin'] ?? 30;

      if (data['distanciaKm'] is num) {
        data['distanciaKm'] = _round2((data['distanciaKm'] as num).toDouble());
      }

      // Asociación automática con empresa activa si el conductor pertenece a una.
      if (servicio.idConductor != null && servicio.idEmpresa == null) {
        final vinculos = await _db
            .collection('usuario_empresa')
            .where('idUsuario', isEqualTo: servicio.idConductor)
            .where('estadoMembresia', isEqualTo: 'ACTIVO')
            .limit(1)
            .get();
        if (vinculos.docs.isNotEmpty) {
          final vinc = vinculos.docs.first.data();
          if (vinc['usaEmpresaComoEmisor'] == true) {
            data['idEmpresa'] = vinc['idEmpresa'];
          }
        }
      }

      final doc = await _serviciosRef.add(data);
      return doc.id;
    } catch (e) {
      throw Exception("Error al crear servicio: $e");
    }
  }

  /// Escucha servicios pendientes de ofertas (nuevas solicitudes de transporte).
  Stream<List<Servicio>> escucharServiciosSolicitados() {
    return _serviciosRef
        .where('estado', isEqualTo: EstadoServicio.pendiente_ofertas.code)
        .orderBy('fechaSolicitud', descending: true)
        .limit(_SOL_LIMIT)
        .snapshots()
        .map(_mapServicios);
  }

  /// Escucha los cambios en un servicio específico identificado por ID.
  Stream<Servicio?> escucharServicio(String id) {
    return _serviciosRef.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Servicio.fromMap(doc.data()!, id: doc.id);
    });
  }

  /// Escucha servicios activos de un usuario, diferenciando conductor y cliente.
  Stream<List<Servicio>> escucharServiciosActivos(String uid, {required bool esConductor}) {
    final estadosConductor = [
      EstadoServicio.aceptado.code,
      EstadoServicio.en_curso.code,
    ];
    final estadosCliente = [
      EstadoServicio.pendiente_ofertas.code,
      EstadoServicio.aceptado.code,
      EstadoServicio.en_curso.code,
    ];

    final q = esConductor
        ? _serviciosRef.where('idConductor', isEqualTo: uid).where('estado', whereIn: estadosConductor)
        : _serviciosRef.where('idUsuarioSolicitante', isEqualTo: uid).where('estado', whereIn: estadosCliente);

    return q.snapshots().map(_mapServicios);
  }

  Stream<List<Servicio>> escucharServiciosActivosConductor(String idConductor) =>
      escucharServiciosActivos(idConductor, esConductor: true);

  Stream<List<Servicio>> escucharServiciosActivosCliente(String idCliente) =>
      escucharServiciosActivos(idCliente, esConductor: false);

  // ============================================================
  // Historial combinado de servicios (cliente y conductor)
  // ============================================================

  /// Escucha el historial de servicios finalizados o cancelados, fusionando resultados duplicados.
  Stream<List<Servicio>> escucharHistorialServicios(String uid, bool esConductor) {
    final baseA = esConductor
        ? _serviciosRef
            .where('idConductor', isEqualTo: uid)
            .where('estado', whereIn: [
              EstadoServicio.finalizado.code,
              EstadoServicio.cancelado.code,
            ])
            .orderBy('fechaFin', descending: true)
            .limit(_HIST_LIMIT)
        : _serviciosRef
            .where('idUsuarioSolicitante', isEqualTo: uid)
            .where('estado', whereIn: [
              EstadoServicio.finalizado.code,
              EstadoServicio.cancelado.code,
            ])
            .orderBy('fechaFin', descending: true)
            .limit(_HIST_LIMIT);

    // baseB se define igual que baseA, sirve para emitir doble escucha si aplica.
    final baseB = esConductor
        ? _serviciosRef
            .where('idConductor', isEqualTo: uid)
            .where('estado', whereIn: [
              EstadoServicio.finalizado.code,
              EstadoServicio.cancelado.code,
            ])
            .orderBy('fechaFin', descending: true)
            .limit(_HIST_LIMIT)
        : _serviciosRef
            .where('idUsuarioSolicitante', isEqualTo: uid)
            .where('estado', whereIn: [
              EstadoServicio.finalizado.code,
              EstadoServicio.cancelado.code,
            ])
            .orderBy('fechaFin', descending: true)
            .limit(_HIST_LIMIT);

    final controller = StreamController<List<Servicio>>.broadcast();
    controller.add(const []);

    List<Servicio> lastA = const [];
    List<Servicio> lastB = const [];

    void emitMerged() {
      final map = <String, Servicio>{};
      for (final s in [...lastA, ...lastB]) {
        final id = s.id;
        if (id != null) map[id] = s;
      }
      final all = map.values.toList();
      _ordenarHistorialLocal(all);
      controller.add(all);
    }

    StreamSubscription? subA;
    StreamSubscription? subB;

    subA = baseA.snapshots().listen((snap) {
      lastA = _mapServicios(snap);
      emitMerged();
    }, onError: controller.addError);

    subB = baseB.snapshots().listen((snap) {
      lastB = _mapServicios(snap);
      emitMerged();
    }, onError: controller.addError);

    controller.onCancel = () {
      subA?.cancel();
      subB?.cancel();
    };

    return controller.stream;
  }

  // ============================================================
  // Transiciones de estado del servicio (inicio, finalización, cancelación)
  // ============================================================

  /// Actualiza el estado de un servicio a un nuevo estado controlado.
  Future<void> actualizarEstado(String id, EstadoServicio nuevoEstado) async {
    try {
      final ref = _serviciosRef.doc(id);

      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('Servicio no existe');

        final updates = <String, dynamic>{
          'estado': nuevoEstado.code,
          'fechaActualizacion': FieldValue.serverTimestamp(),
        };

        if (nuevoEstado == EstadoServicio.en_curso) {
          updates['fechaInicio'] = FieldValue.serverTimestamp();
          updates['duracionRealMin'] = null; 
        }

        if (nuevoEstado == EstadoServicio.finalizado || nuevoEstado == EstadoServicio.cancelado) {
          final now = Timestamp.now();
          final data = snap.data()!;
          final tsInicio = data['fechaInicio'] as Timestamp?;
          final mins = _minsBetween(tsInicio, now);
          updates['fechaFin'] = FieldValue.serverTimestamp();
          updates['duracionRealMin'] = (mins <= 0 ? 1 : mins); 
        }

        tx.update(ref, updates);
      });
    } catch (e) {
      throw Exception("Error al actualizar estado: $e");
    }
  }

  /// Inicia un servicio si se encuentra en estado ACEPTADO.
  Future<void> iniciarServicio(String idServicio) async {
    final ref = _serviciosRef.doc(idServicio);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('Servicio no existe');

        final estado = (snap.data()?['estado'] ?? '').toString().toUpperCase();
        if (estado != EstadoServicio.aceptado.code) {
          throw Exception('Solo puedes iniciar un servicio ACEPTADO (estado: $estado)');
        }

        tx.update(ref, {
          'estado': EstadoServicio.en_curso.code,
          'fechaInicio': FieldValue.serverTimestamp(),
          'duracionRealMin': null,
          'fechaActualizacion': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      throw Exception('Error al iniciar servicio: $e');
    }
  }
  
  // ============================================================
  // Creación y gestión de ofertas (alta, aceptación, rechazo)
  // ============================================================

  /// Crea una nueva oferta para un servicio, validando que no exista duplicidad
  /// y que el servicio aún se encuentre en estado de recepción de ofertas.
  Future<void> crearOferta(Oferta oferta) async {
    final servRef = _serviciosRef.doc(oferta.idServicio);
    final ofertaRef = servRef.collection('ofertas').doc(oferta.id);

    await _db.runTransaction((tx) async {
      final servSnap = await tx.get(servRef);
      if (!servSnap.exists) throw Exception('Servicio no existe');

      final estadoSrv = (servSnap.data()?['estado'] ?? '').toString().toUpperCase();
      if (estadoSrv != EstadoServicio.pendiente_ofertas.code) {
        throw Exception('El servicio ya no admite ofertas (estado: $estadoSrv)');
      }

      final dup = await servRef
          .collection('ofertas')
          .where('idConductor', isEqualTo: oferta.idConductor)
          .where('estado', whereIn: [
            EstadoOferta.pendiente.name,
            EstadoOferta.aceptada.name,
          ])
          .limit(1)
          .get();
      if (dup.docs.isNotEmpty) {
        throw Exception('Ya tienes una oferta activa para este servicio');
      }

      final yaAceptadas = await servRef
          .collection('ofertas')
          .where('estado', isEqualTo: EstadoOferta.aceptada.name)
          .limit(1)
          .get();
      if (yaAceptadas.docs.isNotEmpty) {
        throw Exception('Ya existe una oferta aceptada');
      }

      tx.set(ofertaRef, oferta.toMap(serverTimestampsIfNull: true), SetOptions(merge: true));
    });
  }

  /// Escucha las ofertas vinculadas a un servicio, ordenadas por estado y fecha de creación.
  Stream<List<Oferta>> escucharOfertas(String idServicio) {
    return _serviciosRef
        .doc(idServicio)
        .collection('ofertas')
        .orderBy('estado')
        .orderBy('creadoEn', descending: true)
        .limit(_OFERT_LIMIT)
        .snapshots()
        .map((qs) => qs.docs.map((d) => Oferta.fromMap(d.data(), d.id)).toList());
  }

  /// Acepta una oferta, rechaza las demás y actualiza el servicio a estado ACEPTADO.
  /// Utiliza transacciones para garantizar consistencia en la base de datos.
  Future<void> aceptarOfertaYRechazarResto({
    required String servicioId,
    required String ofertaId,
    required String conductorId,
    String? vehiculoId,
  }) async {
    final servRef = _serviciosRef.doc(servicioId);
    final ofertasRef = servRef.collection('ofertas');

    try {
      await _db.runTransaction((tx) async {
        final servSnap = await tx.get(servRef);
        if (!servSnap.exists) throw Exception('Servicio no existe');

        final estadoSrv = (servSnap.data()?['estado'] ?? '').toString().toUpperCase();
        if (estadoSrv != EstadoServicio.pendiente_ofertas.code) {
          throw Exception('El servicio ya no admite ofertas (estado: $estadoSrv)');
        }

        final ofertaDoc = ofertasRef.doc(ofertaId);
        final ofertaSnap = await tx.get(ofertaDoc);
        if (!ofertaSnap.exists) throw Exception('Oferta no existe');
        final oferta = Oferta.fromMap(ofertaSnap.data() as Map<String, dynamic>, ofertaSnap.id);

        final otros = await ofertasRef.where(FieldPath.documentId, isNotEqualTo: ofertaId).get();
        for (final d in otros.docs) {
          tx.update(d.reference, {
            'estado': EstadoOferta.rechazada.name,
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
        }

        tx.update(ofertaDoc, {
          'estado': EstadoOferta.aceptada.name,
          'actualizadoEn': FieldValue.serverTimestamp(),
        });

        final updateServicio = {
          'estado': EstadoServicio.aceptado.code,
          'idConductor': conductorId,
          if (vehiculoId != null) 'idVehiculo': vehiculoId,
          'idOfertaSeleccionada': ofertaId,
          'precioFinal': oferta.precioOfrecido,
          'fechaAceptacion': FieldValue.serverTimestamp(),
          'fechaActualizacion': FieldValue.serverTimestamp(),
        };

        final vinc = await _db
            .collection('usuario_empresa')
            .where('idUsuario', isEqualTo: conductorId)
            .where('estadoMembresia', isEqualTo: 'ACTIVO')
            .limit(1)
            .get();
        if (vinc.docs.isNotEmpty && vinc.docs.first['usaEmpresaComoEmisor'] == true) {
          updateServicio['idEmpresa'] = vinc.docs.first['idEmpresa'];
        }

        tx.update(servRef, updateServicio);
      });
    } catch (e) {
      throw Exception("Error al aceptar oferta: $e");
    }
  }

  /// Acepta una oferta, configura los parámetros de pago (método, comprobante, PSP)
  /// y actualiza el estado del servicio en una transacción atómica.
  Future<void> aceptarOfertaYConfigurarPago({
    required String servicioId,
    required String ofertaId,
    required String conductorId,
    required double precioFinal,
    required MetodoPago metodoPago,
    required TipoComprobante tipoComprobante,
    required bool pagoDentroApp,
    String? vehiculoId,
    String? pspAuthId,
  }) async {
    final servRef = _serviciosRef.doc(servicioId);
    final ofertasRef = servRef.collection('ofertas');

    await _db.runTransaction((tx) async {
      final servSnap = await tx.get(servRef);
      if (!servSnap.exists) throw Exception('Servicio no existe');

      final estadoSrv = (servSnap.data()?['estado'] ?? '').toString().toUpperCase();
      if (estadoSrv != EstadoServicio.pendiente_ofertas.code) {
        throw Exception('El servicio ya no admite ofertas (estado: $estadoSrv)');
      }

      final yaAceptadas = await ofertasRef
          .where('estado', isEqualTo: EstadoOferta.aceptada.name)
          .limit(1)
          .get();
      if (yaAceptadas.docs.isNotEmpty) {
        throw Exception('Ya existe una oferta aceptada para este servicio');
      }

      final ofertaDoc = ofertasRef.doc(ofertaId);
      final ofertaSnap = await tx.get(ofertaDoc);
      if (!ofertaSnap.exists) throw Exception('Oferta no existe');

      final otros = await ofertasRef.where(FieldPath.documentId, isNotEqualTo: ofertaId).get();
      for (final d in otros.docs) {
        tx.update(d.reference, {
          'estado': EstadoOferta.rechazada.name,
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
      }

      tx.update(ofertaDoc, {
        'estado': EstadoOferta.aceptada.name,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      final updateServicio = <String, dynamic>{
        'estado': EstadoServicio.aceptado.code,
        'idConductor': conductorId,
        if (vehiculoId != null) 'idVehiculo': vehiculoId,
        'idOfertaSeleccionada': ofertaId,
        'precioFinal': precioFinal,
        'metodoPago': metodoPago.code,
        'tipoComprobante': tipoComprobante.code,
        'pagoDentroApp': pagoDentroApp,
        'fechaAceptacion': FieldValue.serverTimestamp(),
        'fechaActualizacion': FieldValue.serverTimestamp(),
      };

      final vinc = await _db
          .collection('usuario_empresa')
          .where('idUsuario', isEqualTo: conductorId)
          .where('estadoMembresia', isEqualTo: 'ACTIVO')
          .limit(1)
          .get();
      if (vinc.docs.isNotEmpty && vinc.docs.first['usaEmpresaComoEmisor'] == true) {
        updateServicio['idEmpresa'] = vinc.docs.first['idEmpresa'];
      }

      if (pspAuthId != null) updateServicio['referenciaPreAuth'] = pspAuthId;

      tx.update(servRef, updateServicio);
    });
  }

  // ============================================================
  // Finalización del servicio y cálculo de comisiones
  // ============================================================

  /// Marca un servicio como finalizado y registra la transacción del conductor
  /// cuando el pago se realiza fuera de la aplicación ("off-app").
  Future<void> finalizarServicioConPagoOffApp({
    required String servicioId,
    String? referenciaPagoExterno,
    String? observaciones,
    double porcentajeComision = 0.05,
  }) async {
    final servRef = _serviciosRef.doc(servicioId);
    final transColl = _db.collection('transacciones_conductor');
    final cuentasColl = _db.collection('estado_cuenta_conductor');

    await _db.runTransaction((tx) async {
      final servSnap = await tx.get(servRef);
      if (!servSnap.exists) throw Exception('Servicio no existe');

      final servicio = Servicio.fromMap(servSnap.data() as Map<String, dynamic>, id: servSnap.id);
      if (servicio.estado == EstadoServicio.finalizado) return;

      final idConductor = servicio.idConductor;
      if (idConductor == null || idConductor.isEmpty) {
        throw Exception('Servicio sin conductor asignado');
      }

      final precio = servicio.precioFinal ?? servicio.precioEstimado ?? 0;
      if (precio <= 0) throw Exception('Precio del servicio inválido');

      final cuentaRef = cuentasColl.doc(idConductor);
      final cuentaSnap = await tx.get(cuentaRef);

      final montoBruto = _round2(precio);
      final comision = _round2(montoBruto * porcentajeComision);
      final montoNeto = _round2(montoBruto - comision);

      tx.update(servRef, {
        'comision': ComisionServicio(
          baseTipo: BaseComision.porcentaje,
          baseValor: porcentajeComision,
          monto: comision,
          estadoCobro: EstadoCobro.pendiente,
          fechaDevengo: DateTime.now(),
          observaciones: 'Devengada al finalizar servicio (pago off-app)',
        ).toMap(),
      });

      // Registro de transacción del conductor.
      final newTransRef = transColl.doc();
      tx.set(newTransRef, {
        'idServicio': servicioId,
        'idConductor': idConductor,
        'montoBruto': montoBruto,
        'comision': comision,
        'montoNeto': montoNeto,
        'pagoDentroApp': false,
        'referencia': referenciaPagoExterno,
        'estado': 'PENDIENTE',
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // Actualización o creación del estado de cuenta del conductor.
      if (!cuentaSnap.exists) {
        tx.set(cuentaRef, {
          'idConductor': idConductor,
          'saldoDisponible': 0.0,
          'saldoRetenido': 0.0,
          'deudaComision': comision,
          'totalIngresosAcum': montoBruto,
          'totalComisionesAcum': comision,
          'estado': 'ACTIVA',
          'ultimaTransaccionId': newTransRef.id,
          'ultimaTransaccion': FieldValue.serverTimestamp(),
          'creadoEn': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
      } else {
        final c = cuentaSnap.data() as Map<String, dynamic>;
        final deudaComision = (c['deudaComision'] as num?)?.toDouble() ?? 0.0;
        final totalIng = (c['totalIngresosAcum'] as num?)?.toDouble() ?? 0.0;
        final totalCom = (c['totalComisionesAcum'] as num?)?.toDouble() ?? 0.0;

        tx.update(cuentaRef, {
          'deudaComision': _round2(deudaComision + comision),
          'totalIngresosAcum': _round2(totalIng + montoBruto),
          'totalComisionesAcum': _round2(totalCom + comision),
          'ultimaTransaccionId': newTransRef.id,
          'ultimaTransaccion': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
      }

      // Cálculo de duración real y cierre de servicio.
      int? duracionMinCalc;
      if (servicio.fechaInicio != null) {
        final tsInicio = Timestamp.fromDate(servicio.fechaInicio!);
        final nowTs = Timestamp.now();
        final mins = _minsBetween(tsInicio, nowTs);
        duracionMinCalc = (mins <= 0 ? 1 : mins);
      }

      final obs = (observaciones?.trim().isNotEmpty ?? false) ? observaciones!.trim() : null;
      tx.update(servRef, {
        'estado': EstadoServicio.finalizado.code,
        'comisionPendiente': true,
        'fechaFin': FieldValue.serverTimestamp(),
        'fechaActualizacion': FieldValue.serverTimestamp(),
        if (obs != null) 'observaciones': obs,
        if (referenciaPagoExterno != null) 'referenciaPagoExterno': referenciaPagoExterno,
        if (duracionMinCalc != null) 'duracionRealMin': duracionMinCalc, 
      });
    });
  }

  // ============================================================
  // Actualizaciones adicionales: ubicación, pagos y comprobantes
  // ============================================================

  /// Actualiza la ubicación del conductor en un servicio en curso.
  Future<void> actualizarUbicacionConductor({
    required String idServicio,
    required double lat,
    required double lng,
  }) async {
    try {
      await _serviciosRef.doc(idServicio).update({
        'ubicacionConductor': {
          'lat': lat,
          'lng': lng,
          'timestamp': FieldValue.serverTimestamp(),
        },
        'fechaActualizacion': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception("Error al actualizar ubicación: $e");
    }
  }

  /// Marca un servicio como finalizado (flujo estándar desde aplicación).
  /// Permite registrar calificaciones y observaciones.
  Future<void> finalizarServicio({
    required String idServicio,
    int? calificacionConductor,
    int? calificacionUsuario,
    String? observaciones,
  }) async {
    try {
      final ref = _serviciosRef.doc(idServicio);
      await _db.runTransaction((tx) async {
        final doc = await tx.get(ref);
        if (!doc.exists) return;

        final estado = (doc.data()?['estado'] ?? '').toString().toUpperCase();
        if (estado == EstadoServicio.finalizado.code) return;

        final data = doc.data()!;
        final tsInicio = data['fechaInicio'] as Timestamp?;
        int? duracionMin;
        if (tsInicio != null) {
          final nowTs = Timestamp.now();
          final mins = _minsBetween(tsInicio, nowTs);
          duracionMin = (mins <= 0 ? 1 : mins);
        }

        tx.update(ref, {
          'estado': EstadoServicio.finalizado.code,
          'fechaFin': FieldValue.serverTimestamp(),
          'fechaActualizacion': FieldValue.serverTimestamp(),
          if (duracionMin != null) 'duracionRealMin': duracionMin, 
          if (calificacionConductor != null) 'calificacionConductor': calificacionConductor,
          if (calificacionUsuario != null) 'calificacionUsuario': calificacionUsuario,
          if (observaciones != null) 'observaciones': observaciones,
        });
      });
    } catch (e) {
      throw Exception("Error al finalizar servicio: $e");
    }
  }

  /// Cancela un servicio, registrando motivo y usuario que realizó la cancelación.
  Future<void> cancelarServicio(
    String idServicio, {
    String? motivo,
    String? canceladoPor,
  }) async {
    try {
      await _serviciosRef.doc(idServicio).update({
        'estado': EstadoServicio.cancelado.code,
        'fechaCancelacion': FieldValue.serverTimestamp(),
        'fechaFin': FieldValue.serverTimestamp(),
        'fechaActualizacion': FieldValue.serverTimestamp(),
        if (motivo != null) 'motivoCancelacion': motivo,
        if (canceladoPor != null) 'canceladoPor': canceladoPor,
      });
    } catch (e) {
      throw Exception("Error al cancelar servicio: $e");
    }
  }

  /// Marca como confirmado o no el pago realizado dentro de la aplicación.
  Future<void> marcarPagoAppConfirmado(String servicioId, {required bool confirmado}) async {
    await _serviciosRef.doc(servicioId).update({
      'pagoAppConfirmado': confirmado,
      'fechaActualizacion': FieldValue.serverTimestamp(),
    });
  }

  /// Adjunta el comprobante de pago del cliente al documento del servicio.
  Future<void> adjuntarComprobanteCliente({
    required String servicioId,
    required ComprobanteCliente comprobante,
  }) async {
    await _serviciosRef.doc(servicioId).update({
      'comprobanteCliente': comprobante.toMap(),
      'fechaActualizacion': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // Operaciones contables: comisiones y normalización
  // ============================================================

  /// Devenga manualmente una comisión sobre un servicio según porcentaje o base definida.
  Future<void> devengarComision({
    required String servicioId,
    double porcentajeComision = 0.05,
    double? precioBase,
  }) async {
    final ref = _serviciosRef.doc(servicioId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Servicio no existe');

    final srv = Servicio.fromMap(snap.data()!, id: snap.id);
    final base = precioBase ?? srv.precioFinal ?? srv.precioEstimado ?? 0;
    final monto = _round2(base * porcentajeComision);

    await ref.update({
      'comision': ComisionServicio(
        baseTipo: BaseComision.porcentaje,
        baseValor: porcentajeComision,
        monto: monto,
        estadoCobro: EstadoCobro.pendiente,
        fechaDevengo: DateTime.now(),
        observaciones: 'Devengada manualmente',
      ).toMap(),
      'comisionPendiente': true,
      'fechaActualizacion': FieldValue.serverTimestamp(),
    });
  }

  /// Normaliza los documentos de servicios en Firestore corrigiendo inconsistencias
  /// de estado y fechas (uso interno o administrativo).
  Future<void> normalizarServicios() async {
    final snap = await _serviciosRef.get();
    final batch = _db.batch();
    int cambios = 0;

    for (final d in snap.docs) {
      final data = d.data();
      final estado = (data['estado'] ?? '').toString();
      final estadoUp = estado.toUpperCase();
      final updates = <String, dynamic>{};

      if (estado.isNotEmpty && estado != estadoUp) {
        updates['estado'] = estadoUp;
      }

      final tieneFechaFin = data.containsKey('fechaFin') && data['fechaFin'] != null;
      if ((estadoUp == EstadoServicio.finalizado.code || estadoUp == EstadoServicio.cancelado.code) &&
          !tieneFechaFin) {
        updates['fechaFin'] = FieldValue.serverTimestamp();
      }

      if (updates.isNotEmpty) {
        batch.update(d.reference, updates);
        cambios++;
      }
    }

    if (cambios > 0) await batch.commit();
  }
}
