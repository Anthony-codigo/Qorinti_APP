// lib/pantallas/admin/admin_reportes_screen.dart
// ============================================================================
// Pantalla: AdminReportesScreen
// Proyecto: Qorinti App – Gestión de Transporte
// ----------------------------------------------------------------------------
// Descripción general:
// Esta pantalla permite al administrador generar reportes globales del sistema
// Qorinti. Consolida indicadores clave (KPIs) sobre los servicios realizados
// durante un rango de fechas determinado.
//
// Funcionalidades principales:
// - Selección de rango de fechas (por campo fechaSolicitud).
// - Cálculo de KPIs operativos y financieros:
//     ▪ % de viajes completados exitosamente (PVE)
//     ▪ Cumplimiento del tiempo de servicio (CTS)
//     ▪ Tiempo promedio de asignación (TPA)
//     ▪ Precisión en la facturación cliente (PFL Cliente)
//     ▪ Precisión en la liquidación Qorinti→Conductor (PFL Liquidación)
//     ▪ Devengado vs Liquidado
// - Exportación de resultados detallados a archivo Excel (.xlsx).
// - Visualización de servicios en lista con métricas clave.
// ----------------------------------------------------------------------------
// Tecnologías utilizadas:
// - Firebase Firestore para la fuente de datos.
// - Paquetes excel, path_provider y share_plus para generar y compartir reportes.
// - Widgets dinámicos (Slivers) para una experiencia fluida en scroll.
// ============================================================================

import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as xls; 
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AdminReportesScreen extends StatefulWidget {
  const AdminReportesScreen({super.key});

  @override
  State<AdminReportesScreen> createState() => _AdminReportesScreenState();
}

class _AdminReportesScreenState extends State<AdminReportesScreen> {
  final _df = DateFormat('dd/MM/yyyy');

  // Rango de fechas seleccionado por el usuario (últimos 7 días por defecto)
  DateTimeRange _rango = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  bool _loading = false;

  // === KPIs principales ===
  int _total = 0;              // Total de servicios encontrados
  int _finalizados = 0;        // Servicios finalizados
  double _pve = 0;             // % de viajes completados exitosamente

  // CTS (Cumplimiento del Tiempo de Servicio)
  int _eligiblesCts = 0;
  int _nvs = 0;
  double _cts = 0;

  // TPA (Tiempo Promedio de Asignación)
  int _eligiblesTpa = 0;
  double _tpaProm = 0;

  // PFL Cliente (Precisión Facturación Cliente)
  int _eligiblesPflCli = 0;
  int _correctasPflCli = 0;
  double _pflCli = 0;

  // PFL Liquidación (Precisión Liquidación Qorinti→Conductor)
  double _devengado = 0.0;
  int _serviciosConComision = 0;
  int _liqDocs = 0;
  double _liqTotal = 0.0;
  double _pflLiq = 0;

  // Datos detallados de servicios para exportar a Excel
  final List<Map<String, dynamic>> _rows = [];

  // --------------------------------------------------------------------------
  // UTILIDADES DE INTERFAZ
  // --------------------------------------------------------------------------

  // Selector de rango de fechas
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 2, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);

    final r = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: _rango,
      helpText: 'Selecciona rango de fechas (por fechaSolicitud)',
      confirmText: 'Listo',
    );
    if (r != null) {
      setState(() => _rango = r);
    }
  }

  // Conversión segura a DateTime
  DateTime? _asDate(dynamic x) {
    if (x is Timestamp) return x.toDate();
    if (x is DateTime) return x;
    return null;
  }

  // Diferencia en minutos entre dos fechas (evita negativos)
  int _minsBetween(DateTime? a, DateTime? b) {
    if (a == null || b == null) return 0;
    final m = b.difference(a).inMinutes;
    return m < 0 ? 0 : m;
  }

  // --------------------------------------------------------------------------
  // CARGA Y CÁLCULO DE INDICADORES
  // --------------------------------------------------------------------------

  Future<void> _cargarYCalcular() async {
    setState(() {
      _loading = true;
      _rows.clear();

      // Reinicia los KPIs
      _total = _finalizados = 0;
      _pve = 0;
      _eligiblesCts = _nvs = 0;
      _cts = 0;
      _eligiblesTpa = 0;
      _tpaProm = 0;
      _eligiblesPflCli = _correctasPflCli = 0;
      _pflCli = 0;
      _devengado = 0;
      _serviciosConComision = 0;
      _liqDocs = 0;
      _liqTotal = 0;
      _pflLiq = 0;
    });

    try {
      // Rango de búsqueda en Firestore
      final start = DateTime(_rango.start.year, _rango.start.month, _rango.start.day, 0, 0, 0);
      final end = DateTime(_rango.end.year, _rango.end.month, _rango.end.day, 23, 59, 59);

      // Consulta de servicios por fecha de solicitud
      final qs = await FirebaseFirestore.instance
          .collection('servicios')
          .where('fechaSolicitud', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('fechaSolicitud', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      // Recorre cada servicio para calcular KPIs
      for (final d in qs.docs) {
        final m = d.data();
        final id = d.id;

        // Campos relevantes
        final estado = (m['estado'] ?? '').toString().toUpperCase();
        final precioEstimado = (m['precioEstimado'] as num?)?.toDouble();
        final precioFinal = (m['precioFinal'] as num?)?.toDouble();
        final metodoPago = (m['metodoPago'] ?? '').toString().toUpperCase();
        final tipoComprobante = (m['tipoComprobante'] ?? '').toString().toUpperCase();

        final fechaSolicitud = _asDate(m['fechaSolicitud']);
        final fechaAceptacion = _asDate(m['fechaAceptacion']);
        final fechaInicio = _asDate(m['fechaInicio']);
        final fechaFin = _asDate(m['fechaFin']);

        // SLA y duración real
        final slaMin = (m['slaMin'] as num?)?.toInt();
        int? duracionRealMin = (m['duracionRealMin'] as num?)?.toInt();

        // Si no existe duración real, se calcula con fechas
        if (duracionRealMin == null && fechaInicio != null && fechaFin != null) {
          final mins = _minsBetween(fechaInicio, fechaFin);
          duracionRealMin = mins <= 0 ? 1 : mins;
        }

        final distanciaKm = (m['distanciaKm'] as num?)?.toDouble();
        final idConductor = (m['idConductor'] ?? '').toString();
        final idUsuario = (m['idUsuarioSolicitante'] ?? '').toString();
        final idEmpresa = (m['idEmpresa'] ?? '').toString();

        // ---------------- KPIs ----------------

        // Total y finalizados
        _total += 1;
        if (estado == 'FINALIZADO') _finalizados += 1;

        // Cumplimiento del tiempo de servicio (CTS)
        if (estado == 'FINALIZADO' && slaMin != null && duracionRealMin != null) {
          _eligiblesCts += 1;
          if (duracionRealMin <= slaMin) _nvs += 1;
        }

        // Tiempo promedio de asignación (TPA)
        if (fechaSolicitud != null && fechaAceptacion != null) {
          _eligiblesTpa += 1;
          _tpaProm += _minsBetween(fechaSolicitud, fechaAceptacion).toDouble();
        }

        // Precisión en la facturación Cliente
        final requiereComp = tipoComprobante.isNotEmpty && tipoComprobante != 'NINGUNO';
        if (estado == 'FINALIZADO' && requiereComp) {
          _eligiblesPflCli += 1;
          bool ok = false;

          final compCliente = m['comprobanteCliente'];
          final compDemo = m['comprobanteDemo'];

          if (compCliente is Map) {
            final urlPdf = (compCliente['urlPdf'] ?? '').toString();
            final serieNumero = (compCliente['serieNumero'] ?? '').toString();
            if (urlPdf.isNotEmpty || serieNumero.isNotEmpty) ok = true;
          }
          if (!ok && compDemo is Map) {
            final urlPdf = (compDemo['urlPdf'] ?? '').toString();
            if (urlPdf.isNotEmpty) ok = true;
          }
          if (ok) _correctasPflCli += 1;
        }

        // Devengado (monto de comisión Qorinti)
        final comp = m['comision'];
        if (estado == 'FINALIZADO' && comp is Map && (comp['monto'] is num)) {
          final monto = (comp['monto'] as num).toDouble();
          if (monto > 0) {
            _serviciosConComision += 1;
            _devengado += monto;
          }
        }

        // Registro del servicio para exportar
        _rows.add({
          'id': id,
          'estado': estado,
          'fechaSolicitud': fechaSolicitud,
          'fechaAceptacion': fechaAceptacion,
          'fechaInicio': fechaInicio,
          'fechaFin': fechaFin,
          'slaMin': slaMin,
          'duracionRealMin': duracionRealMin,
          'distanciaKm': distanciaKm,
          'metodoPago': metodoPago,
          'tipoComprobante': tipoComprobante,
          'precioEstimado': precioEstimado,
          'precioFinal': precioFinal,
          'idConductor': idConductor,
          'idUsuario': idUsuario,
          'idEmpresa': idEmpresa,
        });
      }

      // Datos de comprobantes de liquidación emitidos
      final liqQs = await FirebaseFirestore.instance
          .collection('comprobantes_qorinti')
          .where(
              'fecha',
              isGreaterThanOrEqualTo: Timestamp.fromDate(
                  DateTime(_rango.start.year, _rango.start.month, _rango.start.day, 0, 0, 0)))
          .where(
              'fecha',
              isLessThanOrEqualTo: Timestamp.fromDate(
                  DateTime(_rango.end.year, _rango.end.month, _rango.end.day, 23, 59, 59)))
          .get();

      _liqDocs = liqQs.docs.length;
      _liqTotal = liqQs.docs.fold<double>(0.0, (acc, e) {
        final m = e.data();
        final monto = (m['monto'] as num?)?.toDouble() ?? 0.0;
        return acc + monto;
      });

      // Cierre de cálculos
      _pve = _total == 0 ? 0 : (_finalizados / _total) * 100.0;
      _cts = _eligiblesCts == 0 ? 0 : (_nvs / _eligiblesCts) * 100.0;
      _tpaProm = _eligiblesTpa == 0 ? 0 : _tpaProm / _eligiblesTpa;
      _pflCli = _eligiblesPflCli == 0 ? 0 : (_correctasPflCli / _eligiblesPflCli) * 100.0;
      _pflLiq = _serviciosConComision == 0 ? 0 : (_liqDocs / _serviciosConComision) * 100.0;

      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando datos: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------------------------------------------------------------------------
  // EXPORTAR A EXCEL
  // --------------------------------------------------------------------------

  Future<void> _exportarExcel() async {
    if (_rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar.')),
      );
      return;
    }

    // Alias de celdas de texto y numéricas
    xls.CellValue T(String s) => xls.TextCellValue(s);
    xls.CellValue I(int v) => xls.IntCellValue(v);
    xls.CellValue E() => xls.TextCellValue('');

    final excel = xls.Excel.createExcel();

    // ---------- Hoja Resumen ----------
    final resumen = excel['Resumen'];
    resumen.appendRow([
      T('TÍTULO'),
      T('APLICACIÓN MÓVIL PARA OPTIMIZAR EL PROCESO DE GESTIÓN DE TRANSPORTE EN TRANSPORTES QORINTI S.A.C.')
    ]);
    resumen.appendRow([T('Rango'), T('${_df.format(_rango.start)} - ${_df.format(_rango.end)}')]);
    resumen.appendRow([E(), E()]);

    // Indicadores principales
    resumen.appendRow([T('INDICADOR'), T('% de viajes completados exitosamente')]);
    resumen.appendRow([T('Completados (NVC)'), I(_finalizados)]);
    resumen.appendRow([T('Totales (NTV)'), I(_total)]);
    resumen.appendRow([T('Resultado'), T('${_pve.toStringAsFixed(2)} %')]);
    resumen.appendRow([E(), E()]);

    resumen.appendRow([T('INDICADOR'), T('Cumplimiento del tiempo de servicio (%)')]);
    resumen.appendRow([T('En tiempo (NVS)'), I(_nvs)]);
    resumen.appendRow([T('Elegibles (NTV_e)'), I(_eligiblesCts)]);
    resumen.appendRow([T('Resultado'), T('${_cts.toStringAsFixed(2)} %')]);
    resumen.appendRow([E(), E()]);

    resumen.appendRow([T('INDICADOR'), T('Tiempo promedio de asignación de viajes')]);
    resumen.appendRow([T('Observaciones (elegibles)'), I(_eligiblesTpa)]);
    resumen.appendRow([T('Resultado (min)'), T(_tpaProm.toStringAsFixed(2))]);
    resumen.appendRow([E(), E()]);

    resumen.appendRow([T('INDICADOR'), T('Precisión en la facturación (Cliente)')]);
    resumen.appendRow([T('Correctas'), I(_correctasPflCli)]);
    resumen.appendRow([T('Elegibles'), I(_eligiblesPflCli)]);
    resumen.appendRow([T('Resultado'), T('${_pflCli.toStringAsFixed(2)} %')]);
    resumen.appendRow([E(), E()]);

    resumen.appendRow([T('INDICADOR'), T('Precisión en la liquidación (Qorinti → Conductor)')]);
    resumen.appendRow([T('Servicios con comisión (devengados)'), I(_serviciosConComision)]);
    resumen.appendRow([T('Comprobantes emitidos (#)'), I(_liqDocs)]);
    resumen.appendRow([T('Resultado'), T('${_pflLiq.toStringAsFixed(2)} %')]);
    resumen.appendRow([T('Devengado S/'), T(_devengado.toStringAsFixed(2))]);
    resumen.appendRow([T('Liquidado S/'), T(_liqTotal.toStringAsFixed(2))]);
    resumen.appendRow([T('Brecha S/ (Dev − Liq)'), T((_devengado - _liqTotal).toStringAsFixed(2))]);

    // ---------- Hoja Servicios ----------
    final hoja = excel['Servicios'];
    hoja.appendRow([
      T('ID'),
      T('ESTADO'),
      T('FECHA_SOLICITUD'),
      T('FECHA_ACEPTACION'),
      T('FECHA_INICIO'),
      T('FECHA_FIN'),
      T('SLA_MIN'),
      T('DURACION_REAL_MIN'),
      T('DISTANCIA_KM'),
      T('METODO_PAGO'),
      T('TIPO_COMPROBANTE'),
      T('PRECIO_ESTIMADO'),
      T('PRECIO_FINAL'),
      T('ID_CONDUCTOR'),
      T('ID_USUARIO'),
      T('ID_EMPRESA'),
    ]);

    // Formato de fecha estándar
    String fmtDate(DateTime? d) => d == null ? '' : DateFormat('yyyy-MM-dd HH:mm:ss').format(d);

    for (final r in _rows) {
      final sla = r['slaMin'] as int?;
      final dur = r['duracionRealMin'] as int?;
      final dist = r['distanciaKm'] as double?;
      final pe = r['precioEstimado'] as double?;
      final pf = r['precioFinal'] as double?;

      hoja.appendRow([
        T((r['id'] ?? '').toString()),
        T((r['estado'] ?? '').toString()),
        T(fmtDate(r['fechaSolicitud'] as DateTime?)),
        T(fmtDate(r['fechaAceptacion'] as DateTime?)),
        T(fmtDate(r['fechaInicio'] as DateTime?)),
        T(fmtDate(r['fechaFin'] as DateTime?)),
        sla == null ? E() : I(sla),
        dur == null ? E() : I(dur),
        dist == null ? E() : xls.DoubleCellValue(double.parse(dist.toStringAsFixed(2))),
        T((r['metodoPago'] ?? '').toString()),
        T((r['tipoComprobante'] ?? '').toString()),
        pe == null ? E() : xls.DoubleCellValue(double.parse(pe.toStringAsFixed(2))),
        pf == null ? E() : xls.DoubleCellValue(double.parse(pf.toStringAsFixed(2))),
        T((r['idConductor'] ?? '').toString()),
        T((r['idUsuario'] ?? '').toString()),
        T((r['idEmpresa'] ?? '').toString()),
      ]);
    }

    // Guarda y comparte el archivo generado
    final bytes = excel.encode();
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo generar el archivo Excel.')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/reporte_qorinti_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    await file.writeAsBytes(bytes, flush: true);

    if (!mounted) return;
    await Share.shareXFiles([XFile(file.path)], text: 'Reporte Qorinti');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reporte generado: ${file.path}')),
    );
  }

  // --------------------------------------------------------------------------
  // INTERFAZ DE USUARIO (Scroll adaptativo)
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = scheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text('Reportes · Qorinti')),
      body: CustomScrollView(
        slivers: [
          // Sección superior con filtros y KPIs
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Controles de rango y acciones
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickRange,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Rango de fechas (fechaSolicitud)',
                              border: OutlineInputBorder(),
                            ),
                            child: Text('${_df.format(_rango.start)}  —  ${_df.format(_rango.end)}'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _cargarYCalcular,
                        icon: _loading
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh),
                        label: const Text('Calcular'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _rows.isEmpty ? null : _exportarExcel,
                        icon: const Icon(Icons.file_download),
                        label: const Text('Exportar Excel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Tarjetas con KPIs principales
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _kpiCard('% de viajes completados exitosamente',
                          '${_pve.toStringAsFixed(2)} %', 'Completados: $_finalizados / Total: $_total', cardColor, onSurface),
                      _kpiCard('Cumplimiento del tiempo de servicio (%)',
                          '${_cts.toStringAsFixed(2)} %', 'En tiempo: $_nvs / Elegibles: $_eligiblesCts', cardColor, onSurface),
                      _kpiCard('Tiempo promedio de asignación de viajes',
                          '${_tpaProm.toStringAsFixed(2)} min', 'Observaciones (elegibles): $_eligiblesTpa', cardColor, onSurface),
                      _kpiCard('Precisión en la facturación (Cliente)',
                          '${_pflCli.toStringAsFixed(2)} %', 'Correctas: $_correctasPflCli / Elegibles: $_eligiblesPflCli', cardColor, onSurface),
                      _kpiCard('Precisión en la liquidación (Qorinti → Conductor)',
                          '${_pflLiq.toStringAsFixed(2)} %', 'Comprobantes: $_liqDocs / Devengados: $_serviciosConComision', cardColor, onSurface),
                      _kpiCard('Devengado vs Liquidado',
                          'S/ ${_liqTotal.toStringAsFixed(2)}',
                          'Dev: S/ ${_devengado.toStringAsFixed(2)} • Brecha: S/ ${(_devengado - _liqTotal).toStringAsFixed(2)}',
                          cardColor, onSurface),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Servicios encontrados: ${_rows.length}'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // Lista de servicios en formato sliver
          if (_rows.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Sin datos. Pulsa “Calcular”.')),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  // Alterna divisor entre filas
                  if (i.isOdd) return const Divider(height: 1);
                  final idx = i ~/ 2;
                  final r = _rows[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListTile(
                      dense: true,
                      title: Text('${r['id']} • ${r['estado']}'),
                      subtitle: Text(
                        'Sol: ${_fmt(r['fechaSolicitud'] as DateTime?)}  |  '
                        'Ace: ${_fmt(r['fechaAceptacion'] as DateTime?)}  |  '
                        'Fin: ${_fmt(r['fechaFin'] as DateTime?)}',
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (r['precioFinal'] != null)
                            Text('S/ ${(r['precioFinal'] as double).toStringAsFixed(2)}'),
                          if (r['duracionRealMin'] != null && r['slaMin'] != null)
                            Text('Dur: ${r['duracionRealMin']} / SLA: ${r['slaMin']}'),
                        ],
                      ),
                    ),
                  );
                },
                childCount: _rows.isEmpty ? 0 : (_rows.length * 2 - 1),
              ),
            ),
        ],
      ),
    );
  }

  // Formatea una fecha en formato corto
  String _fmt(DateTime? d) => d == null ? '—' : DateFormat('dd/MM HH:mm').format(d);

  // Tarjeta visual para mostrar un KPI
  Widget _kpiCard(String title, String value, String note, Color bg, Color fg) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 12, letterSpacing: .3, color: fg.withOpacity(.7))),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
            const SizedBox(height: 4),
            Text(note, style: TextStyle(fontSize: 12, color: fg.withOpacity(.7))),
          ],
        ),
      ),
    );
  }
}
