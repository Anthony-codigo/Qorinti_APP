// lib/pantallas/Admin/admin_pagos_screen.dart
// ============================================================================
// Pantalla: AdminPagosScreen
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Descripción general:
// Pantalla administrativa para la gestión de pagos de comisión de conductores.
// Permite:
// - Ver la lista de pagos enviados por los conductores.
// - Filtrar por estado (En revisión, Aprobados, Rechazados).
// - Aprobar o rechazar pagos.
// - Generar o reemitir comprobantes PDF de pago (boleta o factura).
// - Visualizar detalles completos de cada pago.
//
// Integra Firebase Firestore, Firebase Storage y un repositorio de finanzas
// para el flujo de aprobación y registro de comprobantes Qorinti.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher_string.dart'; 
import 'package:app_qorinti/repos/finanzas_repository.dart';
import 'package:app_qorinti/modelos/utils.dart';
import 'package:app_qorinti/modelos/comprobante_qorinti.dart';
import 'crear_comprobante_qorinti.dart';

class AdminPagosScreen extends StatefulWidget {
  const AdminPagosScreen({super.key});

  @override
  State<AdminPagosScreen> createState() => _AdminPagosScreenState();
}

class _AdminPagosScreenState extends State<AdminPagosScreen> {
  final _finanzasRepo = FinanzasRepository();
  String? _filtroPagos;
  final _busquedaCtrl = TextEditingController();

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  // Determina color visual según el estado del pago.
  Color _colorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case 'APROBADO':
        return Colors.green;
      case 'RECHAZADO':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  // Diálogo genérico de confirmación de acción.
  Future<void> _confirmarAccion(
    String mensaje,
    Future<void> Function() onConfirm,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar acción'),
        content: Text(mensaje),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aceptar')),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  // Aprueba un pago pendiente y genera automáticamente su comprobante.
  Future<void> _aprobarPago(String idConductor, String idPago) async {
    await _confirmarAccion(
      "¿Aprobar este pago y generar su comprobante Qorinti?",
      () async {
        try {
          await _finanzasRepo.aprobarPagoComision(
            idConductor: idConductor,
            idPago: idPago,
            notaAdmin: 'Aprobado por administrador',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pago aprobado')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
            );
          }
        }
      },
    );
  }

  // Rechaza un pago en revisión, con opción de escribir un motivo.
  Future<void> _rechazarPago(String idConductor, String idPago) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rechazar pago'),
        content: TextField(
          controller: motivoCtrl,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
            border: OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rechazar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _finanzasRepo.rechazarPagoComision(
        idConductor: idConductor,
        idPago: idPago,
        motivo: motivoCtrl.text.trim().isEmpty ? null : motivoCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago rechazado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Genera manualmente un comprobante (boleta o factura) para un pago.
  // Utiliza datos del conductor, crea el PDF y lo sube a Firebase Storage.
  Future<void> _generarComprobanteManual(
    String idConductor,
    String idPago,
    double monto,
  ) async {
    String _firstNonEmpty(List<String?> xs) =>
        xs.firstWhere((e) => (e?.trim().isNotEmpty ?? false), orElse: () => '')!.trim();

    try {
      // Obtiene los datos del conductor y su usuario asociado.
      final conductorDoc = await FirebaseFirestore.instance
          .collection('conductores')
          .doc(idConductor)
          .get();
      final c = conductorDoc.data() ?? {};

      String nombre = _firstNonEmpty([
        c['nombreCompleto']?.toString(),
        c['nombre']?.toString(),
        (('${c['nombres'] ?? ''} ${c['apellidos'] ?? ''}').trim()),
      ]);

      if (nombre.isEmpty) {
        final idUsuario = c['idUsuario']?.toString();
        if (idUsuario != null && idUsuario.isNotEmpty) {
          final u = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(idUsuario)
              .get();
          final m = u.data() ?? {};
          nombre = _firstNonEmpty([
            m['nombre']?.toString(),
            m['displayName']?.toString(),
          ]);
        }
      }
      if (nombre.isEmpty) nombre = 'Conductor';

      final ruc = (c['ruc']?.toString() ?? '').trim();
      final dni = (c['dni']?.toString() ?? '').trim();

      final tipo = ruc.isNotEmpty
          ? TipoComprobanteQorinti.factura
          : TipoComprobanteQorinti.boleta;

      final serie = tipo == TipoComprobanteQorinti.factura ? 'FQOR' : 'BQOR';
      final numero = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      final serieNumero = '$serie-$numero';

      // Genera el PDF del comprobante.
      final pdfBytes = await buildComprobanteQorintiPdf(
        tipo: tipo,
        rucQorinti: '20612632562',
        razonQorinti: 'TRANSPORTES QORINTI S.A.C.',
        direccionQorinti:
            'Mza. 0o2 Lote. 15, Urb. Puerta de Pro Etapa 2, Los Olivos, Lima, Perú',
        conductorNombre: nombre,
        conductorDoc: ruc.isNotEmpty ? ruc : (dni.isNotEmpty ? dni : '-'),
        monto: monto,
        fecha: DateTime.now(),
        logoUrl:
            'https://firebasestorage.googleapis.com/v0/b/dbchavez05.firebasestorage.app/o/imagen_qorinti%2FLogotype-Vertical-3840-x-2160-white.png?alt=media&token=179b343f-e433-4005-8b5f-7892824eaf62',
      );

      // Guarda el PDF en Firebase Storage.
      final ref = FirebaseStorage.instance
          .ref('comprobantes_qorinti/$idConductor/$serieNumero.pdf');
      await ref.putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'));
      final url = await ref.getDownloadURL();

      // Registra el comprobante en Firestore.
      await FirebaseFirestore.instance.collection('comprobantes_qorinti').add(
            ComprobanteQorinti(
              id: '',
              idPago: idPago,
              idConductor: idConductor,
              tipo: tipo,
              serie: serie,
              numero: numero,
              serieNumero: serieNumero,
              monto: monto,
              fecha: DateTime.now(),
              urlPdf: url,
            ).toMap(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comprobante generado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar comprobante: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Abre el PDF del comprobante existente desde su URL.
  Future<void> _verComprobante(String idPago) async {
    final docs = await FirebaseFirestore.instance
        .collection('comprobantes_qorinti')
        .where('idPago', isEqualTo: idPago)
        .limit(1)
        .get();

    if (docs.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay comprobante disponible')),
        );
      }
      return;
    }

    final url = (docs.docs.first.data()['urlPdf'] ?? '').toString();
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El comprobante no tiene PDF disponible')),
        );
      }
      return;
    }

    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  // Muestra los detalles completos de un pago, incluyendo montos,
  // referencias, observaciones y estado actual.
  void _mostrarDetallePago(Map<String, dynamic> p) {
    final idPago = (p['id'] ?? '').toString();
    final idConductor = (p['idConductor'] ?? '').toString();
    final monto = (p['monto'] as num?)?.toDouble() ?? 0.0;
    final estado = (p['estado'] ?? 'EN_REVISION').toString();
    final ref = (p['referencia'] ?? '').toString();
    final obs = (p['observaciones'] ?? '').toString();
    final notaAdmin = (p['notaAdmin'] ?? '').toString();
    final creado = formatDate(dt(p['creadoEn']));
    final actualizado = formatDate(dt(p['actualizadoEn']));
    final montoAplicado = (p['montoAplicado'] as num?)?.toDouble();
    final deudaAntes = (p['deudaAntes'] as num?)?.toDouble();
    final deudaDespues = (p['deudaDespues'] as num?)?.toDouble();
    final txAplicadaId = (p['txAplicadaId'] ?? '').toString();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Detalle del Pago'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rowDetalle('ID Pago', idPago),
              _rowDetalle('Conductor', idConductor),
              _rowDetalle('Monto solicitado', 'S/. ${monto.toStringAsFixed(2)}'),
              _rowDetalle('Estado', estado),
              if (montoAplicado != null)
                _rowDetalle('Monto aplicado', 'S/. ${montoAplicado.toStringAsFixed(2)}'),
              if (deudaAntes != null)
                _rowDetalle('Deuda antes', 'S/. ${deudaAntes.toStringAsFixed(2)}'),
              if (deudaDespues != null)
                _rowDetalle('Deuda después', 'S/. ${deudaDespues.toStringAsFixed(2)}'),
              if (txAplicadaId.isNotEmpty)
                _rowDetalle('Transacción aplicada', txAplicadaId),
              if (ref.isNotEmpty) _rowDetalle('Referencia', ref),
              if (obs.isNotEmpty) _rowDetalle('Observaciones', obs),
              if (notaAdmin.isNotEmpty) _rowDetalle('Nota Admin', notaAdmin),
              _rowDetalle('Creado', creado),
              _rowDetalle('Actualizado', actualizado),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          if (estado == 'APROBADO') ...[
            TextButton(
              onPressed: () => _verComprobante(idPago),
              child: const Text('Ver comprobante'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _generarComprobanteManual(idConductor, idPago, montoAplicado ?? monto);
              },
              child: const Text('Reemitir comprobante'),
            ),
          ],
          if (estado == 'EN_REVISION') ...[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _rechazarPago(idConductor, idPago);
              },
              child: const Text('Rechazar', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _aprobarPago(idConductor, idPago);
              },
              child: const Text('Aprobar'),
            ),
          ]
        ],
      ),
    );
  }

  // Fila genérica para mostrar pares etiqueta-valor en los detalles del pago.
  Widget _rowDetalle(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // Construye la interfaz principal con filtros, búsqueda y lista de pagos.
  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collectionGroup('pagos_comision')
        .orderBy('creadoEn', descending: true);
    if (_filtroPagos != null) q = q.where('estado', isEqualTo: _filtroPagos);

    return Column(
      children: [
        _buildFiltros(context),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];
              final term = _busquedaCtrl.text.trim().toLowerCase();

              // Filtro por término (ID, conductor o referencia).
              final filtrados = term.isEmpty
                  ? docs
                  : docs.where((d) {
                      final p = d.data();
                      final idConductor = (p['idConductor'] ?? '').toString().toLowerCase();
                      final ref = (p['referencia'] ?? '').toString().toLowerCase();
                      final id = (p['id'] ?? d.id).toString().toLowerCase();
                      return id.contains(term) || idConductor.contains(term) || ref.contains(term);
                    }).toList();

              if (filtrados.isEmpty) {
                return const Center(child: Text('No hay pagos que coincidan.'));
              }

              // Renderiza la lista de pagos con detalles básicos y acciones.
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: filtrados.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = filtrados[i];
                  final p = d.data();
                  final idPago = (p['id'] ?? d.id).toString();
                  final idConductor = (p['idConductor'] ?? '').toString();
                  final monto = (p['monto'] as num?)?.toDouble() ?? 0.0;
                  final estado = (p['estado'] ?? 'EN_REVISION').toString();
                  final creado = formatDate(dt(p['creadoEn']));
                  final ref = (p['referencia'] ?? '').toString();

                  final color = _colorEstado(estado);
                  final aplicado = (p['montoAplicado'] as num?)?.toDouble();

                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.15),
                        child: Icon(Icons.receipt_long, color: color),
                      ),
                      title: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('S/. ${monto.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (aplicado != null)
                            Chip(
                              label: Text(
                                'Aplicado: S/. ${aplicado.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              backgroundColor: Colors.blueGrey,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Conductor: $idConductor'),
                          if (ref.isNotEmpty)
                            Text('Ref: $ref', style: const TextStyle(color: Colors.black54)),
                          Text('Creado: $creado',
                              style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                      trailing: _accionesPorEstado(idConductor, idPago, estado),
                      isThreeLine: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      onTap: () => _mostrarDetallePago(p),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

    // Filtros por estado y campo de búsqueda.
  Widget _buildFiltros(BuildContext context) {
    // Componente visual para los chips de selección de estado.
    Widget chip(String? value, String label) {
      final selected = _filtroPagos == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filtroPagos = value),
        selectedColor: Theme.of(context).colorScheme.primary,
        labelStyle: TextStyle(
          color: selected ? Colors.white : null,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Estado:', style: TextStyle(fontWeight: FontWeight.bold)),
          chip(null, 'Todos'),
          chip('EN_REVISION', 'En revisión'),
          chip('APROBADO', 'Aprobados'),
          chip('RECHAZADO', 'Rechazados'),
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _busquedaCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por ID, conductor o referencia',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _busquedaCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _busquedaCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  // Acciones disponibles según el estado del pago.
  Widget _accionesPorEstado(String idConductor, String idPago, String estado) {
    // Si el pago está en revisión, muestra botones para aprobar o rechazar.
    if (estado == 'EN_REVISION') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Aprobar',
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: () => _aprobarPago(idConductor, idPago),
          ),
          IconButton(
            tooltip: 'Rechazar',
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => _rechazarPago(idConductor, idPago),
          ),
        ],
      );
    } else {
      // Si ya fue aprobado o rechazado, muestra un chip con su estado.
      return Chip(
        label: Text(
          estado.toUpperCase(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _colorEstado(estado),
        visualDensity: VisualDensity.compact,
      );
    }
  }
}
