// lib/pantallas/servicios/conductor/pagos_comision_historial_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: PagosComisionHistorialScreen
//
// Descripción general:
//   Muestra el historial completo de los pagos de comisión realizados por un
//   conductor dentro de Qorinti App. Permite filtrar, buscar y revisar el
//   estado de cada pago, además de visualizar el comprobante (PDF) asociado.
//
//   Incluye:
//     - Filtros por estado (En revisión, Aprobado, Rechazado).
//     - Búsqueda por texto en referencia u observaciones.
//     - Cálculo dinámico del total y cantidad de movimientos visibles.
//     - Enlace directo a comprobante PDF (si fue emitido).
//
//   Integra los siguientes servicios:
//     • FirebaseAuth → Identifica al conductor autenticado.
//     • FinanzasRepository → Provee stream de pagos registrados en Firestore.
//     • Firestore → Consulta en tiempo real los comprobantes asociados.
//     • url_launcher → Abre comprobantes PDF en navegador o visor in-app.
//     • intl → Formato de moneda (S/) y fechas locales.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:app_qorinti/modelos/pago_comision.dart';
import 'package:app_qorinti/repos/finanzas_repository.dart';


// -----------------------------------------------------------------------------
// FUNCIÓN GLOBAL: _abrirPdfRobusto
//
// Permite abrir un comprobante PDF de manera robusta. Intenta tres métodos:
//   1. Abrir con aplicación externa (preferido).
//   2. Abrir en navegador interno (WebView).
//   3. Copiar enlace al portapapeles si ambas fallan.
//
// Incluye validación de URL y mensajes de error visuales.
// -----------------------------------------------------------------------------
Future<void> _abrirPdfRobusto(BuildContext context, String url) async {
  Uri? uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL inválida del comprobante')),
    );
    return;
  }

  // 1️⃣ Intentar abrir con aplicación externa
  final puedeExterno = await canLaunchUrl(uri);
  if (puedeExterno) {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) return;
  }

  // 2️⃣ Intentar abrir dentro de la app (WebView)
  final okInApp = await launchUrl(
    uri,
    mode: LaunchMode.inAppBrowserView,
    webViewConfiguration: const WebViewConfiguration(
      enableJavaScript: true,
      enableDomStorage: true,
    ),
  );
  if (okInApp) return;

  // 3️⃣ Si todo falla, notificar y copiar enlace
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el comprobante. Enlace copiado.')),
    );
  }
  await Clipboard.setData(ClipboardData(text: url));
}

// -----------------------------------------------------------------------------
// Clase principal: PagosComisionHistorialScreen
//
// Pantalla principal con filtros, búsqueda y listado de pagos.
// -----------------------------------------------------------------------------
class PagosComisionHistorialScreen extends StatefulWidget {
  const PagosComisionHistorialScreen({super.key});

  @override
  State<PagosComisionHistorialScreen> createState() =>
      _PagosComisionHistorialScreenState();
}

class _PagosComisionHistorialScreenState
    extends State<PagosComisionHistorialScreen> {
  EstadoPagoComision? _filtro; // Estado seleccionado (filtro activo)
  final _searchCtrl = TextEditingController(); // Controlador para búsqueda

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<FinanzasRepository>();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final moneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/ ', decimalDigits: 2);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    // Si no hay sesión activa, mostrar aviso
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Debes iniciar sesión')));
    }

    // ------------------------------------------------------------------------
    // ESTRUCTURA GENERAL DE LA PANTALLA
    // ------------------------------------------------------------------------
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos de comisión'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ------------------------------------------------------------------
          // FILTROS VISUALES (Chips)
          // ------------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipFiltro('Todos', null),
                _chipFiltro('En revisión', EstadoPagoComision.en_revision,
                    color: Colors.orange),
                _chipFiltro('Aprobado', EstadoPagoComision.aprobado,
                    color: Colors.green),
                _chipFiltro('Rechazado', EstadoPagoComision.rechazado,
                    color: Colors.red),
              ],
            ),
          ),

          // ------------------------------------------------------------------
          // CAMPO DE BÚSQUEDA
          // ------------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por referencia u observaciones…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (_searchCtrl.text.isEmpty)
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // ------------------------------------------------------------------
          // CONTENIDO PRINCIPAL (StreamBuilder)
          // ------------------------------------------------------------------
          Expanded(
            child: StreamBuilder<List<PagoComision>>(
              stream: repo.streamPagosComision(uid, limit: 200),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }

                var items = snap.data ?? const <PagoComision>[];

                // Aplicar filtro por estado
                if (_filtro != null) {
                  items = items.where((p) => p.estado == _filtro).toList();
                }

                // Aplicar búsqueda textual
                final q = _searchCtrl.text.trim().toLowerCase();
                if (q.isNotEmpty) {
                  items = items.where((p) {
                    final ref = (p.referencia ?? '').toLowerCase();
                    final obs = (p.observaciones ?? '').toLowerCase();
                    return ref.contains(q) || obs.contains(q);
                  }).toList();
                }

                // Ordenar por fecha descendente
                items.sort((a, b) {
                  final ta =
                      (a.actualizadoEn ?? a.creadoEn)?.millisecondsSinceEpoch ?? 0;
                  final tb =
                      (b.actualizadoEn ?? b.creadoEn)?.millisecondsSinceEpoch ?? 0;
                  return tb.compareTo(ta);
                });

                // Construir resumen dinámico
                final double total =
                    items.fold(0.0, (acc, it) => acc + (it.monto));
                final String sub =
                    _buildResumenSub(items.length, total, moneda);

                // Si no hay resultados
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        (_filtro == null && q.isEmpty)
                            ? 'Aún no registraste pagos.'
                            : 'Sin resultados para los filtros actuales.\n$sub',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                // --------------------------------------------------------------
                // LISTA DE PAGOS (con RefreshIndicator)
                // --------------------------------------------------------------
                return RefreshIndicator(
                  onRefresh: () async =>
                      Future<void>.delayed(const Duration(milliseconds: 350)),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    children: [
                      // Card resumen superior
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading:
                              const Icon(Icons.summarize, color: Colors.indigo),
                          title: const Text('Resumen del filtro'),
                          subtitle: Text(sub),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Renderizado de cada pago
                      ...List.generate(items.length, (i) {
                        final p = items[i];
                        final estadoColor = _estadoTxColor(p.estado);

                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _detalle(context, p, moneda, fmt),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Ícono lateral (recibo)
                                  CircleAvatar(
                                    backgroundColor:
                                        estadoColor.withOpacity(0.15),
                                    child: Icon(Icons.receipt_long,
                                        color: estadoColor),
                                  ),
                                  const SizedBox(width: 12),

                                  // Columna central con información del pago
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          moneda.format(p.monto),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 4),
                                        if (p.referencia != null &&
                                            p.referencia!.isNotEmpty)
                                          Text('Ref: ${p.referencia}',
                                              style: const TextStyle(
                                                  color: Colors.black87)),
                                        if (p.observaciones != null &&
                                            p.observaciones!.isNotEmpty)
                                          Text(p.observaciones!,
                                              style: const TextStyle(
                                                  color: Colors.black54)),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Creado: ${p.creadoEn != null ? fmt.format(p.creadoEn!.toLocal()) : '—'}'
                                          '${p.actualizadoEn != null ? '  •  Act: ${fmt.format(p.actualizadoEn!.toLocal())}' : ''}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  // Columna lateral derecha (estado + comprobante)
                                  _EstadoYComprobanteColumn(
                                    estado: p.estado,
                                    pagoId: p.id,
                                    conductorId: uid,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Genera un Chip de filtro visual
  // --------------------------------------------------------------------------
  Widget _chipFiltro(String label, EstadoPagoComision? v, {Color? color}) {
    final sel = _filtro == v;
    final bg = sel ? (color ?? Colors.blueGrey) : Colors.black.withOpacity(0.06);
    final fg = sel ? Colors.white : Colors.black87;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      selectedColor: bg,
      backgroundColor: bg,
      labelStyle: TextStyle(
          color: fg, fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
      onSelected: (_) => setState(() => _filtro = v),
    );
  }

  // --------------------------------------------------------------------------
  // Diálogo con detalles de un pago seleccionado
  // --------------------------------------------------------------------------
  void _detalle(BuildContext c, PagoComision p, NumberFormat moneda, DateFormat fmt) {
    showDialog(
      context: c,
      builder: (_) => AlertDialog(
        title: const Text('Detalle de pago'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Monto', moneda.format(p.monto)),
              _row('Estado', p.estado.name),
              if (p.referencia != null && p.referencia!.isNotEmpty)
                _row('Referencia', p.referencia!),
              if (p.observaciones != null && p.observaciones!.isNotEmpty)
                _row('Observaciones', p.observaciones!),
              _row('Creado', p.creadoEn != null ? fmt.format(p.creadoEn!.toLocal()) : '—'),
              _row('Actualizado', p.actualizadoEn != null ? fmt.format(p.actualizadoEn!.toLocal()) : '—'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  // Fila genérica clave:valor usada en el diálogo
  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text('$k:', style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  // Colorea según el estado del pago
  Color _estadoTxColor(EstadoPagoComision e) {
    switch (e) {
      case EstadoPagoComision.aprobado:
        return Colors.green;
      case EstadoPagoComision.rechazado:
        return Colors.red;
      case EstadoPagoComision.en_revision:
        return Colors.orange;
    }
  }

  // Construye el resumen dinámico de cantidad y monto total
  String _buildResumenSub(int count, double total, NumberFormat moneda) {
    final s1 = count == 1 ? '1 movimiento' : '$count movimientos';
    final s2 = moneda.format(total);
    return '$s1 • Total: $s2';
  }
}

// -----------------------------------------------------------------------------
// WIDGET AUXILIAR: _EstadoYComprobanteColumn
//
// Muestra el estado del pago y, si fue aprobado, busca en tiempo real el
// comprobante asociado en la colección `comprobantes_qorinti`.
//
// Si el comprobante existe y tiene un `urlPdf`, ofrece un botón para abrirlo.
// -----------------------------------------------------------------------------
class _EstadoYComprobanteColumn extends StatelessWidget {
  final EstadoPagoComision estado;
  final String pagoId;
  final String conductorId;

  const _EstadoYComprobanteColumn({
    required this.estado,
    required this.pagoId,
    required this.conductorId,
  });

  @override
  Widget build(BuildContext context) {
    final color = () {
      switch (estado) {
        case EstadoPagoComision.aprobado:
          return Colors.green;
        case EstadoPagoComision.rechazado:
          return Colors.red;
        case EstadoPagoComision.en_revision:
          return Colors.orange;
      }
    }();

    // Chip de estado (coloreado)
    final chip = Chip(
      label: Text(estado.name, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    // Si no está aprobado, solo muestra el chip
    if (estado != EstadoPagoComision.aprobado) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [chip],
      );
    }

    // Si fue aprobado, buscar comprobante PDF en Firestore
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        chip,
        const SizedBox(height: 6),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('comprobantes_qorinti')
              .where('idPago', isEqualTo: pagoId)
              .where('idConductor', isEqualTo: conductorId)
              .limit(1)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return const Text(
                'Comprobante no disponible',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              );
            }

            // Extraer datos del comprobante
            final m = snap.data!.docs.first.data();
            final String tipo =
                (m['tipo'] ?? '').toString().toUpperCase(); // BOLETA o FACTURA
            final String urlPdf = (m['urlPdf'] ?? '').toString();

            if (urlPdf.isEmpty) {
              return const Text(
                'Comprobante no disponible',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              );
            }

            // Botón para abrir el comprobante PDF
            return TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _abrirPdfRobusto(context, urlPdf),
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: Text(
                'Ver ${tipo.isEmpty ? 'comprobante' : tipo}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ],
    );
  }
}
