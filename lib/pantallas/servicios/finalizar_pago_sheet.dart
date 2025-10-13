// -----------------------------------------------------------------------------
// Archivo: finalizar_pago_sheet.dart
// Descripción general:
//   Hoja modal inferior (BottomSheet) que permite confirmar el pago recibido
//   al finalizar un servicio. El conductor indica si recibió el pago, puede
//   ingresar una referencia o nota, y confirmar la finalización.
//
// Funcionalidad:
//   - Captura si el pago fue recibido (SwitchListTile).
//   - Permite agregar referencia y observaciones opcionales.
//   - Devuelve un objeto [FinalizarPagoResult] con la información registrada.
//   - Controla el estado de envío (_enviando) para evitar múltiples acciones.
//   - Muestra chips informativos sobre el método de pago y monto.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Resultado devuelto por la hoja de finalización.
/// Contiene el estado de pago y detalles opcionales.
class FinalizarPagoResult {
  final bool pagoRecibido;     // Indica si el conductor confirma haber recibido el pago.
  final String? referencia;    // Referencia del pago (número de operación, etc.)
  final String? observaciones; // Observaciones adicionales.

  const FinalizarPagoResult({
    required this.pagoRecibido,
    this.referencia,
    this.observaciones,
  });
}

/// Hoja modal inferior para registrar el pago y finalizar el viaje.
///
/// Parámetros opcionales:
/// - [metodoTexto]: texto que describe el método de pago.
/// - [monto]: monto asociado al pago.
/// - [pagoDentroApp]: si el pago se realizó dentro de la app.
/// - [titulo]: encabezado de la hoja.
/// - [mensaje]: texto explicativo debajo del título.
class FinalizarPagoSheet extends StatefulWidget {
  final String? metodoTexto;
  final double? monto;
  final bool? pagoDentroApp;
  final String titulo;
  final String mensaje;

  const FinalizarPagoSheet({
    super.key,
    this.metodoTexto,
    this.monto,
    this.pagoDentroApp,
    this.titulo = 'Finalizar viaje',
    this.mensaje = 'Confirma que ya recibiste el pago del cliente y agrega una referencia si aplica.',
  });

  @override
  State<FinalizarPagoSheet> createState() => _FinalizarPagoSheetState();
}

class _FinalizarPagoSheetState extends State<FinalizarPagoSheet> {
  final _formKey = GlobalKey<FormState>();
  final _refCtrl = TextEditingController();  // Controlador del campo de referencia
  final _obsCtrl = TextEditingController();  // Controlador del campo de observaciones
  final _refFocus = FocusNode();             // Foco para campo de referencia

  bool _pagoRecibido = false; // Estado del switch de pago
  bool _enviando = false;     // Control para evitar envío duplicado

  /// Determina si el pago se realizó dentro de la app.
  /// Esto sirve para decidir si se pide referencia o no.
  bool get _isInApp {
    if (widget.pagoDentroApp != null) return widget.pagoDentroApp!;
    final t = widget.metodoTexto?.toLowerCase() ?? '';
    return t.contains('app');
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _obsCtrl.dispose();
    _refFocus.dispose();
    super.dispose();
  }

  /// Cambia el estado del switch "Pago recibido".
  /// Si el pago es externo (fuera de app), enfoca el campo referencia.
  void _togglePagoRecibido(bool v) {
    setState(() => _pagoRecibido = v);
    if (v && !_isInApp) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _refFocus.requestFocus();
      });
    }
  }

  /// Quita el foco de todos los campos (usado al hacer tap fuera).
  void _unfocus() => FocusScope.of(context).unfocus();

  /// Valida y envía la información del formulario.
  /// Si es válida, devuelve un [FinalizarPagoResult] al cerrar la hoja.
  Future<void> _enviar() async {
    if (_enviando) return;

    // Asegura que el conductor confirme haber recibido el pago
    if (!_pagoRecibido) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirma que el pago fue recibido para finalizar.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Valida el formulario completo
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _enviando = true);
    HapticFeedback.mediumImpact(); // Retroalimentación háptica
    _unfocus();

    final ref = _refCtrl.text.trim();
    final obs = _obsCtrl.text.trim();

    // Construye el resultado con los valores ingresados
    final result = FinalizarPagoResult(
      pagoRecibido: _pagoRecibido,
      referencia: _isInApp ? null : (ref.isEmpty ? null : ref),
      observaciones: obs.isEmpty ? null : obs,
    );

    if (!mounted) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final montoStr = (widget.monto != null) ? 'S/ ${widget.monto!.toStringAsFixed(2)}' : null;

    // Texto auxiliar del switch, dependiendo del tipo de pago
    final switchSubtitle = _isInApp
        ? 'Pago en app'
        : 'Pago directo: efectivo / Yape / Plin / transferencia';

    return WillPopScope(
      // Evita cerrar mientras se está enviando
      onWillPop: () async => !_enviando,
      child: SafeArea(
        top: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _unfocus,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Indicador visual superior (handle)
                      Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),

                      // Título y mensaje descriptivo
                      Text(
                        widget.titulo,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        semanticsLabel: 'Título: ${widget.titulo}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.mensaje,
                        textAlign: TextAlign.center,
                      ),

                      // Chips informativos (método y monto)
                      if (widget.metodoTexto != null || montoStr != null) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            if (widget.metodoTexto != null)
                              Chip(
                                avatar: const Icon(Icons.payments, color: Colors.white, size: 18),
                                label: Text(
                                  widget.metodoTexto!,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                backgroundColor: _isInApp ? Colors.indigo : Colors.teal,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            if (montoStr != null)
                              Chip(
                                avatar: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 18),
                                label: Text(
                                  montoStr,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                backgroundColor: Colors.grey.shade700,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Switch de confirmación de pago recibido
                      SwitchListTile.adaptive(
                        title: const Text('Pago recibido'),
                        subtitle: Text(switchSubtitle),
                        value: _pagoRecibido,
                        onChanged: _enviando ? null : _togglePagoRecibido,
                      ),

                      // Campo de referencia (solo si el pago fue fuera de la app)
                      if (!_isInApp) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _refCtrl,
                          focusNode: _refFocus,
                          decoration: const InputDecoration(
                            labelText: 'Referencia (opcional)',
                            hintText: 'Ej: ID de operación, últimas 4 cifras, etc.',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.receipt_long),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\n')),
                          ],
                          textInputAction: TextInputAction.next,
                          maxLength: 80,
                          enabled: !_enviando,
                          onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Campo de observaciones adicionales
                      TextFormField(
                        controller: _obsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Observaciones (opcional)',
                          hintText: 'Alguna nota adicional…',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.notes),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 200,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        enabled: !_enviando,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\n{3,}')),
                        ],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _enviar(),
                      ),

                      const SizedBox(height: 16),

                      // Botón principal de acción
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (!_pagoRecibido || _enviando) ? null : _enviar,
                          icon: _enviando
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.flag),
                          label: Text(_enviando ? 'Registrando…' : 'Finalizar y registrar'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
