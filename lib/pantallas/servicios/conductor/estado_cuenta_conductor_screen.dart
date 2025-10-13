// lib/pantallas/finanzas/estado_cuenta_conductor_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: EstadoCuentaConductorScreen
// Descripción general:
//   Esta pantalla permite al conductor visualizar el resumen financiero de su
//   cuenta dentro del sistema Qorinti App, incluyendo:
//
//     • Su deuda pendiente por comisiones.
//     • Totales acumulados de ingresos y comisiones.
//     • Historial detallado de transacciones (servicios, pagos de comisión, etc.).
//
//   Funcionalidades principales:
//     - Se conecta al repositorio de finanzas para obtener en tiempo real
//       (vía Stream) los datos de la cuenta y sus transacciones.
//     - Ofrece acceso directo al registro de pago de comisión.
//     - Presenta alertas y banners cuando existe deuda pendiente.
//     - Permite ver el detalle individual de cada movimiento.
//
//   Integra:
//     - FirebaseAuth: para identificar al conductor actual (uid).
//     - FinanzasRepository: para obtener `EstadoCuentaConductor` y `TransaccionConductor`.
//     - Firestore Streams: para reflejar actualizaciones en vivo.
//     - Formato de moneda y fecha con intl.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_qorinti/modelos/estado_cuenta_conductor.dart';
import 'package:app_qorinti/modelos/transaccion_conductor.dart';
import 'package:app_qorinti/repos/finanzas_repository.dart';
import 'package:app_qorinti/app_router.dart';

class EstadoCuentaConductorScreen extends StatelessWidget {
  const EstadoCuentaConductorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Repositorio de finanzas y uid del usuario autenticado
    final repo = context.read<FinanzasRepository>();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final moneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/ ', decimalDigits: 2);

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Debes iniciar sesión')),
      );
    }

    // ------------------------------------------------------------------------
    // Estructura general del Scaffold
    // ------------------------------------------------------------------------
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estado de cuenta'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AppRouter.push(
          AppRouter.registrarPagoComision,
          args: uid,
        ),
        icon: const Icon(Icons.payments),
        label: const Text('Registrar pago'),
      ),

      // Stream principal: escucha el estado de cuenta del conductor
      body: StreamBuilder<EstadoCuentaConductor>(
        stream: repo.streamEstadoCuenta(uid),
        builder: (context, snapCuenta) {
          if (snapCuenta.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapCuenta.hasError) {
            return Center(child: Text('Error: ${snapCuenta.error}'));
          }

          final cuenta = snapCuenta.data;

          // ------------------------------------------------------------------
          // Cuerpo principal: resumen, banners y listado de transacciones
          // ------------------------------------------------------------------
          return Column(
            children: [
              const SizedBox(height: 8),

              // Tarjeta resumen del estado de cuenta
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _ResumenCuentaCard(
                  deudaComision: cuenta?.deudaComision ?? 0,
                  totalIngresosAcum: cuenta?.totalIngresosAcum ?? 0,
                  totalComisionesAcum: cuenta?.totalComisionesAcum ?? 0,
                  estado: (cuenta?.estado ?? EstadoCuenta.activa).name,
                  moneda: moneda,
                ),
              ),

              // Banner de alerta si hay deuda pendiente
              if ((cuenta?.deudaComision ?? 0) > 0) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MaterialBanner(
                    backgroundColor: Colors.orange.shade50,
                    leading: const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange),
                    content: Text(
                      'Tienes comisión pendiente por pagar: '
                      '${moneda.format(cuenta!.deudaComision)}.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => _mostrarInstruccionesPago(context),
                        child: const Text('Cómo pagar'),
                      ),
                      TextButton.icon(
                        onPressed: () => AppRouter.push(
                          AppRouter.registrarPagoComision,
                          args: uid,
                        ),
                        icon: const Icon(Icons.payments),
                        label: const Text('Registrar ahora'),
                      ),
                    ],
                  ),
                ),
              ],

              // Encabezado de lista de movimientos
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Movimientos',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Stream secundario: transacciones del conductor
              Expanded(
                child: StreamBuilder<List<TransaccionConductor>>(
                  stream: repo.streamTransacciones(uid, limit: 100),
                  builder: (context, snapTrans) {
                    if (snapTrans.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapTrans.hasError) {
                      final msg = snapTrans.error.toString();
                      final friendly = msg.contains('requires an index')
                          ? 'Estamos preparando tus datos. Intenta de nuevo en unos minutos.'
                          : 'No pudimos cargar tus movimientos.';
                      return Center(child: Text('❌ $friendly'));
                    }

                    final items = snapTrans.data ?? const <TransaccionConductor>[];
                    if (items.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Aún no hay movimientos en tu cuenta.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    // ----------------------------------------------------------
                    // Listado de movimientos
                    // ----------------------------------------------------------
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final t = items[i];
                        final esPagoComision =
                            t.idServicio == '__PAGO_COMISION__';

                        final estadoColor = _estadoTxColor(t.estado);

                        // Bloque inferior de texto dentro del ListTile
                        final subtitleWidgets = <Widget>[
                          const SizedBox(height: 4),
                          if (esPagoComision) ...[
                            Text('Monto pagado: ${moneda.format(t.comision.abs())}'),
                          ] else ...[
                            Text(
                              'Bruto: ${moneda.format(t.montoBruto)}  •  '
                              'Comisión: ${moneda.format(t.comision)}  •  '
                              'Neto: ${moneda.format(t.montoNeto)}',
                            ),
                          ],
                          if (t.referencia != null && t.referencia!.isNotEmpty)
                            Text('Ref: ${t.referencia}',
                                style: const TextStyle(color: Colors.black54)),
                          const SizedBox(height: 2),
                          Text(
                            'Creado: ${_fmtFecha(t.creadoEn)}'
                            '${t.actualizadoEn != null ? '  •  Act: ${_fmtFecha(t.actualizadoEn)}' : ''}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        ];

                        final leadingColor =
                            esPagoComision ? Colors.green : Colors.deepPurple;
                        final leadingIcon =
                            esPagoComision ? Icons.inbox : Icons.payments;

                        return Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: leadingColor.withOpacity(0.15),
                              child: Icon(leadingIcon, color: leadingColor),
                            ),
                            title: Text(
                              esPagoComision
                                  ? 'Pago de comisión'
                                  : 'Servicio: ${t.idServicio}',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: subtitleWidgets,
                            ),
                            trailing: Chip(
                              label: Text(
                                t.estado.name.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                              backgroundColor: estadoColor,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            onTap: () => _mostrarDetalleTx(context, t, moneda),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // UTILIDADES DE FORMATO Y COLOR SEGÚN ESTADO DE TRANSACCIÓN
  // --------------------------------------------------------------------------
  static Color _estadoTxColor(EstadoTransaccion estado) {
    switch (estado) {
      case EstadoTransaccion.liquidado:
        return Colors.green;
      case EstadoTransaccion.anulado:
        return Colors.red;
      case EstadoTransaccion.pendiente:
        return Colors.orange;
    }
  }

  static String _fmtFecha(DateTime? d) {
    if (d == null) return '—';
    final f = DateFormat('dd/MM/yyyy HH:mm');
    return f.format(d.toLocal());
  }

  // --------------------------------------------------------------------------
  // Diálogo con instrucciones para realizar el pago de comisión
  // --------------------------------------------------------------------------
  void _mostrarInstruccionesPago(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cómo pagar comisión'),
        content: const Text(
          'Paga el 5% de comisión por tus viajes cobrados directo al cliente.\n\n'
          '• Yape/Plin/Transferencia a Qorinti\n'
          '• Indica la referencia en tu pago\n'
          '• Cuando el admin apruebe tu solicitud, tu deuda disminuirá.\n',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Muestra detalle completo de una transacción en un diálogo modal
  // --------------------------------------------------------------------------
  void _mostrarDetalleTx(
    BuildContext context,
    TransaccionConductor t,
    NumberFormat moneda,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Detalle de movimiento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Tipo', t.idServicio == '__PAGO_COMISION__'
                ? 'Pago de comisión'
                : 'Cargo por comisión'),
            if (t.idServicio != '__PAGO_COMISION__')
              _row('Servicio', t.idServicio),
            _row('Bruto', moneda.format(t.montoBruto)),
            _row('Comisión', moneda.format(t.comision)),
            _row('Neto', moneda.format(t.montoNeto)),
            if (t.referencia != null && t.referencia!.isNotEmpty)
              _row('Referencia', t.referencia!),
            _row('Estado', t.estado.name.toUpperCase()),
            _row('Creado', _fmtFecha(t.creadoEn)),
            _row('Actualizado', _fmtFecha(t.actualizadoEn)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // Utilidad para mostrar una fila de datos clave-valor dentro del diálogo
  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$k:',
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              v,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Widget: _ResumenCuentaCard
// Muestra resumen de indicadores financieros principales del conductor
// -----------------------------------------------------------------------------
class _ResumenCuentaCard extends StatelessWidget {
  final double deudaComision;
  final double totalIngresosAcum;
  final double totalComisionesAcum;
  final String estado;
  final NumberFormat moneda;

  const _ResumenCuentaCard({
    required this.deudaComision,
    required this.totalIngresosAcum,
    required this.totalComisionesAcum,
    required this.estado,
    required this.moneda,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = estado == 'BLOQUEADA'
        ? Colors.red
        : (estado == 'CERRADA' ? Colors.grey : Colors.green);

    return Card(
      elevation: 2.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: [
            // Encabezado del resumen
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.indigo),
                const SizedBox(width: 8),
                const Text('Resumen',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Chip(
                  label: Text(estado,
                      style: const TextStyle(color: Colors.white)),
                  backgroundColor: badgeColor,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // KPIs principales: deuda e ingresos
            Row(
              children: [
                _kpi('Deuda comisión', moneda.format(deudaComision),
                    color: Colors.orange),
                const SizedBox(width: 12),
                _kpi('Ingresos acum.', moneda.format(totalIngresosAcum),
                    color: Colors.indigo),
              ],
            ),
            const SizedBox(height: 10),

            // KPIs secundarios: comisiones acumuladas y estado
            Row(
              children: [
                _kpiMini('Comisiones acum.',
                    moneda.format(totalComisionesAcum)),
                const SizedBox(width: 12),
                _kpiMini('Estado de cuenta', estado),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Tarjeta pequeña con valor principal (color destacado)
  Widget _kpi(String title, String value, {Color color = Colors.indigo}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tarjeta pequeña gris con texto resumido
  Widget _kpiMini(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.035),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
