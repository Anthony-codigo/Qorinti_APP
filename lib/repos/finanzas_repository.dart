// Repositorio de finanzas de conductores.
// Gestiona el estado de cuenta, transacciones, pagos de comisión y emisión de comprobantes.
// 
// Este repositorio centraliza la lógica financiera de Qorinti:
// - Controla el flujo de pagos por comisión (solicitud, aprobación, rechazo, registro).
// - Gestiona los estados de cuenta de conductores (saldo, deuda, movimientos).
// - Genera comprobantes automáticos (boleta o factura) en formato PDF y los almacena en Firebase Storage.
// - Garantiza la consistencia mediante transacciones atómicas en Firestore.
//
// Diseño:
// - Usa colecciones: `estado_cuenta_conductor`, `transacciones_conductor`, `conductores/{id}/pagos_comision`.
// - Incluye validaciones de negocio para evitar pagos duplicados o montos inconsistentes.
// - Integra Firebase Storage para persistir los comprobantes en la nube.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:app_qorinti/modelos/estado_cuenta_conductor.dart';
import 'package:app_qorinti/modelos/transaccion_conductor.dart';
import 'package:app_qorinti/modelos/pago_comision.dart';
import 'package:app_qorinti/modelos/comprobante_qorinti.dart';
import 'package:app_qorinti/pantallas/admin/crear_comprobante_qorinti.dart';

class FinanzasRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Colecciones base de Firestore
  CollectionReference<Map<String, dynamic>> get _estadoCuentaRef =>
      _db.collection('estado_cuenta_conductor');

  CollectionReference<Map<String, dynamic>> get _transaccionesRef =>
      _db.collection('transacciones_conductor');

  CollectionReference<Map<String, dynamic>> _pagosComisionRef(String idConductor) =>
      _db.collection('conductores').doc(idConductor).collection('pagos_comision');

  // Helpers
  FieldValue get _serverNow => FieldValue.serverTimestamp();
  double _r2(num v) => double.parse(v.toDouble().toStringAsFixed(2));

  // ============================================================
  // Métodos internos auxiliares
  // ============================================================

  /// Obtiene el nombre del conductor a partir de los datos de las colecciones
  /// `conductores` o `usuarios`. Se utiliza al generar comprobantes.
  Future<String> _resolverNombreConductor(String idConductor) async {
    String _firstNonEmpty(List<String?> xs) =>
        xs.firstWhere((e) => (e?.trim().isNotEmpty ?? false), orElse: () => '')!.trim();

    final doc = await _db.collection('conductores').doc(idConductor).get();
    final c = doc.data() ?? {};

    final deConductor = _firstNonEmpty([
      c['nombreCompleto']?.toString(),
      c['nombre']?.toString(),
      (('${c['nombres'] ?? ''} ${c['apellidos'] ?? ''}').trim()),
    ]);

    if (deConductor.isNotEmpty) return deConductor;
    final idUsuario = c['idUsuario']?.toString();
    if (idUsuario != null && idUsuario.isNotEmpty) {
      final u = await _db.collection('usuarios').doc(idUsuario).get();
      final m = u.data() ?? {};
      final deUsuario = _firstNonEmpty([
        m['nombre']?.toString(),
        m['displayName']?.toString(),
      ]);
      if (deUsuario.isNotEmpty) return deUsuario;
    }

    return 'Conductor';
  }

  /// Crea el documento de estado de cuenta si no existe.
  Future<void> _ensureEstadoCuenta(String idConductor) async {
    final doc = await _estadoCuentaRef.doc(idConductor).get();
    if (!doc.exists) {
      final nuevo = EstadoCuentaConductor(
        id: idConductor,
        idConductor: idConductor,
        saldoDisponible: 0,
        saldoRetenido: 0,
        deudaComision: 0,
        totalIngresosAcum: 0,
        totalComisionesAcum: 0,
        estado: EstadoCuenta.activa,
        creadoEn: DateTime.now(),
        actualizadoEn: DateTime.now(),
      );
      await _estadoCuentaRef.doc(idConductor).set(nuevo.toMap());
    }
  }

  // ============================================================
  // Streams de lectura en tiempo real
  // ============================================================

  /// Escucha en tiempo real el estado de cuenta de un conductor.
  Stream<EstadoCuentaConductor> streamEstadoCuenta(String idConductor) async* {
    await _ensureEstadoCuenta(idConductor);
    yield* _estadoCuentaRef.doc(idConductor).snapshots().map((d) {
      if (!d.exists) {
        return EstadoCuentaConductor(id: idConductor, idConductor: idConductor);
      }
      return EstadoCuentaConductor.fromMap(d.data()!, id: d.id);
    });
  }

  /// Escucha en tiempo real las transacciones financieras del conductor.
  Stream<List<TransaccionConductor>> streamTransacciones(
    String idConductor, {
    int limit = 50,
  }) {
    return _transaccionesRef
        .where('idConductor', isEqualTo: idConductor)
        .orderBy('creadoEn', descending: true)
        .limit(limit)
        .snapshots()
        .map((qs) => qs.docs.map((d) => TransaccionConductor.fromMap(d.data(), d.id)).toList());
  }

  /// Escucha los pagos de comisión registrados por un conductor.
  Stream<List<PagoComision>> streamPagosComision(
    String idConductor, {
    int limit = 100,
  }) {
    return _pagosComisionRef(idConductor)
        .orderBy('creadoEn', descending: true)
        .limit(limit)
        .snapshots()
        .map((qs) => qs.docs.map((d) => PagoComision.fromMap(d.data(), d.id)).toList());
  }

  /// Recupera un pago de comisión específico.
  Future<PagoComision?> getPagoComision(String idConductor, String idPago) async {
    final doc = await _pagosComisionRef(idConductor).doc(idPago).get();
    if (!doc.exists) return null;
    return PagoComision.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  // ============================================================
  // Flujo: solicitud de pago (conductor)
  // ============================================================

  /// Permite al conductor solicitar el pago de una comisión pendiente.
  Future<void> solicitarPagoComision({
    required String idConductor,
    required double monto,
    String? referencia,
    String? observaciones,
  }) async {
    if (monto <= 0) throw Exception('El monto debe ser mayor a 0.');
    await _ensureEstadoCuenta(idConductor);

    final ref = _pagosComisionRef(idConductor).doc();

    await ref.set({
      'id': ref.id,
      'idConductor': idConductor,
      'monto': _r2(monto),
      'referencia': (referencia?.trim().isNotEmpty ?? false) ? referencia!.trim() : null,
      'observaciones': (observaciones?.trim().isNotEmpty ?? false) ? observaciones!.trim() : null,
      'estado': 'EN_REVISION',
      'creadoEn': _serverNow,
      'actualizadoEn': _serverNow,
    });
  }

  // ============================================================
  // Flujo: aprobación de pago (admin)
  // ============================================================

  /// Proceso de aprobación de pago de comisión por parte del administrador.
  /// Actualiza el estado de cuenta, genera una transacción y emite el comprobante PDF.
  Future<void> aprobarPagoComision({
    required String idConductor,
    required String idPago,
    String? notaAdmin,
  }) async {
    final pagoRef = _pagosComisionRef(idConductor).doc(idPago);
    final estadoRef = _estadoCuentaRef.doc(idConductor);
    final newTxRef = _transaccionesRef.doc();

    double montoAplicado = 0;
    double deudaActual = 0;
    double deudaFinal = 0;
    String? referencia;
    String? obsUser;

    await _db.runTransaction((tx) async {
      final pagoSnap = await tx.get(pagoRef);
      if (!pagoSnap.exists) throw Exception('La solicitud no existe.');
      final data = pagoSnap.data()!;
      final estadoSolicitud = (data['estado'] ?? '').toString().toUpperCase();
      if (estadoSolicitud != 'EN_REVISION') throw Exception('La solicitud no está en revisión.');
      final montoSolicitado = _r2((data['monto'] as num).toDouble());
      referencia = (data['referencia'] as String?)?.trim();
      obsUser = (data['observaciones'] as String?)?.trim();

      final estadoSnap = await tx.get(estadoRef);
      EstadoCuentaConductor cuenta;
      if (!estadoSnap.exists) {
        cuenta = EstadoCuentaConductor(id: idConductor, idConductor: idConductor);
        tx.set(estadoRef, cuenta.toMap());
      } else {
        cuenta = EstadoCuentaConductor.fromMap(estadoSnap.data()!, id: estadoSnap.id);
      }

      deudaActual = _r2(cuenta.deudaComision);
      if (deudaActual <= 0) throw Exception('El conductor no tiene deuda pendiente.');
      montoAplicado = _r2(montoSolicitado > deudaActual ? deudaActual : montoSolicitado);
      deudaFinal = _r2(deudaActual - montoAplicado);

      final txPago = TransaccionConductor(
        id: newTxRef.id,
        idServicio: '__PAGO_COMISION__',
        idConductor: idConductor,
        montoBruto: 0,
        comision: -montoAplicado,
        montoNeto: 0,
        referencia: referencia,
        estado: EstadoTransaccion.liquidado,
        creadoEn: DateTime.now(),
        actualizadoEn: DateTime.now(),
      );
      tx.set(newTxRef, txPago.toMap(serverNowIfNull: true));

      tx.update(estadoRef, {
        'deudaComision': deudaFinal <= 0 ? 0.0 : deudaFinal,
        'actualizadoEn': _serverNow,
        'ultimaTransaccionId': newTxRef.id,
        'ultimaTransaccion': _serverNow,
        if ((obsUser?.trim().isNotEmpty ?? false)) 'observacionesUltima': obsUser!.trim(),
        if ((notaAdmin?.trim().isNotEmpty ?? false)) 'notaAdminUltima': notaAdmin!.trim(),
      });

      tx.update(pagoRef, {
        'estado': 'APROBADO',
        'montoAplicado': montoAplicado,
        'deudaAntes': deudaActual,
        'deudaDespues': deudaFinal <= 0 ? 0.0 : deudaFinal,
        'txAplicadaId': newTxRef.id,
        if (notaAdmin != null && notaAdmin.trim().isNotEmpty) 'notaAdmin': notaAdmin.trim(),
        'actualizadoEn': _serverNow,
      });
    });

    // Intento de generación del comprobante PDF
    try {
      final conductorDoc = await _db.collection('conductores').doc(idConductor).get();
      final c = conductorDoc.data() ?? {};
      final conductorRuc = (c['ruc']?.toString() ?? '');
      final conductorDni = (c['dni']?.toString() ?? '');

      final conductorNombre = await _resolverNombreConductor(idConductor);

      final tipo = conductorRuc.trim().isNotEmpty
          ? TipoComprobanteQorinti.factura
          : TipoComprobanteQorinti.boleta;

      final serie = tipo == TipoComprobanteQorinti.factura ? 'FQOR' : 'BQOR';
      final numero = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      final serieNumero = '$serie-$numero';

      final pdfBytes = await buildComprobanteQorintiPdf(
        rucQorinti: '20612632562',
        razonQorinti: 'TRANSPORTES QORINTI S.A.C.',
        direccionQorinti: 'Mza. 0o2 Lote. 15, Los Olivos, Lima',
        conductorNombre: conductorNombre,
        conductorDoc: conductorRuc.trim().isNotEmpty
            ? conductorRuc
            : (conductorDni.trim().isNotEmpty ? conductorDni : '-'),
        monto: montoAplicado,
        fecha: DateTime.now(),
        tipo: tipo,
      );

      final ref =
          FirebaseStorage.instance.ref('comprobantes_qorinti/$idConductor/$serieNumero.pdf');
      await ref.putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'));
      final url = await ref.getDownloadURL();

      await _db.collection('comprobantes_qorinti').add(
            ComprobanteQorinti(
              id: '',
              idPago: idPago,
              idConductor: idConductor,
              tipo: tipo,
              serie: serie,
              numero: numero,
              serieNumero: serieNumero,
              monto: montoAplicado,
              fecha: DateTime.now(),
              urlPdf: url,
            ).toMap(),
          );
    } catch (e) {
      print(' Error generando comprobante Qorinti: $e');
    }
  }

  // ============================================================
  // Flujo: rechazo de pago
  // ============================================================

  /// Rechaza una solicitud de pago de comisión (solo si está en revisión).
  Future<void> rechazarPagoComision({
    required String idConductor,
    required String idPago,
    String? motivo,
  }) async {
    final pagoRef = _pagosComisionRef(idConductor).doc(idPago);
    final snap = await pagoRef.get();
    if (!snap.exists) throw Exception('La solicitud no existe.');
    final estadoSolicitud = (snap.data()!['estado'] ?? '').toString().toUpperCase();
    if (estadoSolicitud != 'EN_REVISION') {
      throw Exception('La solicitud no está en revisión.');
    }

    await pagoRef.update({
      'estado': 'RECHAZADO',
      'motivoRechazo': (motivo?.trim().isNotEmpty ?? false) ? motivo!.trim() : null,
      'actualizadoEn': _serverNow,
    });
  }

  // ============================================================
  // Flujo: registro manual de pago (conductor)
  // ============================================================

  /// Registra manualmente un pago de comisión realizado por el conductor.
  /// Descuenta la deuda de comisión y crea una transacción asociada.
  Future<void> registrarPagoComision({
    required String idConductor,
    required double monto,
    String? referencia,
    String? observaciones,
  }) async {
    if (monto <= 0) throw Exception('El monto debe ser mayor a 0.');

    final estadoRef = _estadoCuentaRef.doc(idConductor);
    final newTxRef = _transaccionesRef.doc();

    await _db.runTransaction((tx) async {
      final estadoSnap = await tx.get(estadoRef);
      EstadoCuentaConductor estado;
      if (!estadoSnap.exists) {
        estado = EstadoCuentaConductor(id: idConductor, idConductor: idConductor);
        tx.set(estadoRef, estado.toMap());
      } else {
        estado = EstadoCuentaConductor.fromMap(estadoSnap.data()!, id: estadoSnap.id);
      }

      final deudaActual = _r2(estado.deudaComision);
      final nuevo = _r2(deudaActual - monto);

      if (deudaActual <= 0) throw Exception('No tienes deuda pendiente de comisión.');
      if (nuevo < -0.01) throw Exception('El monto excede la deuda pendiente.');

      final txPago = TransaccionConductor(
        id: newTxRef.id,
        idServicio: '__PAGO_COMISION__',
        idConductor: idConductor,
        montoBruto: 0,
        comision: -_r2(monto),
        montoNeto: 0,
        referencia: (referencia?.trim().isNotEmpty ?? false) ? referencia!.trim() : null,
        estado: EstadoTransaccion.liquidado,
        creadoEn: DateTime.now(),
        actualizadoEn: DateTime.now(),
      );
      tx.set(newTxRef, txPago.toMap(serverNowIfNull: true));

      tx.update(estadoRef, {
        'deudaComision': nuevo <= 0 ? 0.0 : nuevo,
        'actualizadoEn': _serverNow,
        'ultimaTransaccionId': newTxRef.id,
        'ultimaTransaccion': _serverNow,
        if (observaciones != null && observaciones.trim().isNotEmpty)
          'observacionesUltima': observaciones.trim(),
      });
    });
  }
}
