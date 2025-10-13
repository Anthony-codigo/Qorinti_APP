// -----------------------------------------------------------------------------
// Archivo: comprobante_demo_screen.dart
// Descripción general:
//   Interfaz para generar un comprobante PDF de demostración asociado a un
//   servicio completado. Permite elegir entre Boleta o Factura, validar datos
//   de cliente o empresa mediante RUC, y generar el comprobante usando un
//   servicio interno de generación de PDFs (ComprobanteDemoService).
//
// Funcionalidad principal:
//   - Muestra formulario dinámico según tipo de comprobante (boleta/factura).
//   - Consulta y valida RUC mediante RucServicio con control de debounce.
//   - Calcula subtotal e IGV automáticamente a partir del total.
//   - Invoca la generación del comprobante PDF en modo asíncrono.
//   - Muestra retroalimentación de estado (enviando, error, éxito).
// -----------------------------------------------------------------------------

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_qorinti/modelos/comprobante_demo.dart' as cd;
import 'package:app_qorinti/repos/comprobante_demo_service.dart';
import 'package:app_qorinti/servicios/ruc_servicio.dart';

/// Pantalla principal para generación de comprobantes de demostración.
/// Recibe datos del servicio y del cliente, y guía el flujo de emisión.
class ComprobanteDemoScreen extends StatefulWidget {
  final String idServicio;                 // ID del servicio relacionado
  final double total;                      // Total del pago
  final DateTime fecha;                    // Fecha de emisión
  final bool clienteTieneEmpresa;          // Indica si el cliente es empresa
  final Map<String, String>? empresaPreset; // Datos prellenados de la empresa

  const ComprobanteDemoScreen({
    super.key,
    required this.idServicio,
    required this.total,
    required this.fecha,
    required this.clienteTieneEmpresa,
    this.empresaPreset,
  });

  @override
  State<ComprobanteDemoScreen> createState() => _ComprobanteDemoScreenState();
}

class _ComprobanteDemoScreenState extends State<ComprobanteDemoScreen> {
  // Formateador de moneda local
  final _moneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/', decimalDigits: 2);

  // Emisor fijo (predefinido como conductor para la demo)
  final cd.EmisorDemo _emisorFijo = cd.EmisorDemo.conductor;

  // Tipo de comprobante actual (por defecto boleta)
  cd.TipoComprobanteDemo _tipo = cd.TipoComprobanteDemo.boleta;

  // Controladores de texto para campos del formulario
  final _rucCtrl = TextEditingController();
  final _razonCtrl = TextEditingController();
  final _dirCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _dniCtrl = TextEditingController();

  // Estado de proceso de generación
  bool _generando = false;

  // Servicio para validación de RUC
  final _rucSrv = RucServicio();
  bool _rucValidando = false;
  bool _rucValido = false;
  String? _rucMsg;
  Timer? _rucDebounce;

  @override
  void initState() {
    super.initState();

    // Si el cliente tiene empresa, se precargan los datos y se selecciona factura
    if (widget.clienteTieneEmpresa && widget.empresaPreset != null) {
      _tipo = cd.TipoComprobanteDemo.factura;
      _rucCtrl.text = widget.empresaPreset!['ruc'] ?? '';
      _razonCtrl.text = widget.empresaPreset!['razon'] ?? '';
      _dirCtrl.text = widget.empresaPreset!['direccion'] ?? '';
      // Consulta RUC automáticamente si ya tiene longitud válida
      if (_rucCtrl.text.trim().length == 11) {
        _consultarRuc(_rucCtrl.text.trim(), silencioso: true);
      }
    }
    // Escucha cambios en el campo RUC para validar con debounce
    _rucCtrl.addListener(_onRucChanged);
  }

  @override
  void dispose() {
    _rucDebounce?.cancel();
    _rucCtrl.removeListener(_onRucChanged);
    _rucCtrl.dispose();
    _razonCtrl.dispose();
    _dirCtrl.dispose();
    _nombreCtrl.dispose();
    _dniCtrl.dispose();
    super.dispose();
  }

  /// Escucha cambios en el campo RUC y aplica limpieza y validación diferida.
  void _onRucChanged() {
    final ruc = _soloDigitos(_rucCtrl.text);
    // Elimina caracteres no numéricos
    if (_rucCtrl.text != ruc) {
      final sel = _rucCtrl.selection;
      _rucCtrl.value = TextEditingValue(
        text: ruc,
        selection: sel.copyWith(baseOffset: ruc.length, extentOffset: ruc.length),
      );
    }

    _rucDebounce?.cancel();
    _rucValido = false;
    _rucMsg = null;
    setState(() {});

    // Si tiene longitud 11, inicia validación después de un pequeño retraso
    if (ruc.length == 11) {
      _rucDebounce = Timer(const Duration(milliseconds: 600), () {
        _consultarRuc(ruc);
      });
    }
  }

  /// Elimina todos los caracteres que no sean dígitos.
  String _soloDigitos(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// Consulta el servicio RUC para validar y obtener razón social y dirección.
  Future<void> _consultarRuc(String ruc, {bool silencioso = false}) async {
    if (ruc.length != 11) {
      if (!silencioso) _rucMsg = 'RUC debe tener 11 dígitos';
      _rucValido = false;
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      _rucValidando = true;
      _rucMsg = null;
      _rucValido = false;
    });

    final data = await _rucSrv.validarRuc(ruc);
    if (!mounted) return;

    if (data != null) {
      final razon = (data['nombre'] ?? data['razonSocial'] ?? '').toString().trim();
      final direccion = (data['direccion'] ?? '').toString().trim();
      if (razon.isNotEmpty) _razonCtrl.text = razon;
      if (direccion.isNotEmpty) _dirCtrl.text = direccion;
      _rucValido = true;
      _rucMsg = 'RUC válido';
    } else {
      _rucValido = false;
      _rucMsg = 'RUC inválido o no encontrado';
    }

    setState(() => _rucValidando = false);
  }

  /// Ejecuta la generación del comprobante según el tipo (boleta o factura).
  Future<void> _generar() async {
    // Validaciones de campos requeridos
    if (_tipo == cd.TipoComprobanteDemo.factura) {
      final ruc = _soloDigitos(_rucCtrl.text);
      if (ruc.length != 11 || _razonCtrl.text.trim().isEmpty || _dirCtrl.text.trim().isEmpty) {
        _snack('Completa RUC, razón social y dirección.');
        return;
      }
    } else {
      if (_nombreCtrl.text.trim().isEmpty) {
        _snack('Completa el nombre del cliente.');
        return;
      }
    }

    // Validación de permisos para emitir factura
    if (_tipo == cd.TipoComprobanteDemo.factura) {
      final cRuc = _soloDigitos(_rucCtrl.text);
      if (cRuc.isEmpty) {
        _snack('Solo puedes emitir FACTURA si tienes RUC registrado en tu perfil.');
        return;
      }
    }

    setState(() => _generando = true);

    try {
      // Genera y adjunta el comprobante PDF mediante el servicio interno
      await ComprobanteDemoService.generateAndAttach(
        idServicio: widget.idServicio,
        emisor: _emisorFijo,
        tipo: _tipo,
        total: widget.total,
        fecha: widget.fecha,
        receptor: _tipo == cd.TipoComprobanteDemo.factura
            ? {
                'ruc': _soloDigitos(_rucCtrl.text),
                'razon': _razonCtrl.text.trim(),
                'direccion': _dirCtrl.text.trim(),
              }
            : {
                'nombre': _nombreCtrl.text.trim(),
                if (_soloDigitos(_dniCtrl.text).isNotEmpty) 'dni': _soloDigitos(_dniCtrl.text),
              },
      ).timeout(const Duration(seconds: 60));

      if (!mounted) return;
      _snack('Comprobante generado correctamente');
      Navigator.pop(context, true);
    } on TimeoutException catch (e) {
      _snack('Timeout: ${e.message ?? "Demoró demasiado. Verifica conexión o permisos."}');
    } catch (e) {
      _snack('Error al generar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Cálculo automático de subtotal e IGV
    final subtotal = widget.total / 1.18;
    final igv = widget.total - subtotal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generar comprobante'),
        centerTitle: true,
      ),
      // Contenido principal
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sección: tipo de comprobante
          _cardWrap(
            icon: Icons.receipt_long,
            title: 'Tipo de comprobante',
            child: DropdownButtonFormField<cd.TipoComprobanteDemo>(
              value: _tipo,
              onChanged: widget.clienteTieneEmpresa
                  ? null
                  : (v) => setState(() => _tipo = v ?? cd.TipoComprobanteDemo.boleta),
              items: const [
                DropdownMenuItem(value: cd.TipoComprobanteDemo.boleta, child: Text('Boleta')),
                DropdownMenuItem(value: cd.TipoComprobanteDemo.factura, child: Text('Factura')),
              ],
              decoration: _inputDeco(),
            ),
          ),
          const SizedBox(height: 8),

          // Formulario condicional según tipo (factura o boleta)
          if (_tipo == cd.TipoComprobanteDemo.factura)
            _cardWrap(
              icon: Icons.apartment_rounded,
              title: 'Datos de la empresa',
              child: Column(
                children: [
                  // Campo RUC con indicador de validación
                  TextFormField(
                    controller: _rucCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 11,
                    decoration: _inputDeco(label: 'RUC').copyWith(
                      counterText: '',
                      suffixIcon: _rucValidando
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _rucValido
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : (_rucMsg != null
                                  ? const Icon(Icons.error_outline, color: Colors.red)
                                  : null),
                    ),
                  ),
                  if (_rucMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _rucMsg!,
                        style: TextStyle(fontSize: 12, color: _rucValido ? Colors.green : cs.error),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextFormField(controller: _razonCtrl, decoration: _inputDeco(label: 'Razón social')),
                  const SizedBox(height: 8),
                  TextFormField(controller: _dirCtrl, decoration: _inputDeco(label: 'Dirección fiscal')),
                ],
              ),
            )
          else
            _cardWrap(
              icon: Icons.person_rounded,
              title: 'Datos del cliente',
              child: Column(
                children: [
                  TextFormField(controller: _nombreCtrl, decoration: _inputDeco(label: 'Nombre')),
                  const SizedBox(height: 8),
                  TextFormField(controller: _dniCtrl, decoration: _inputDeco(label: 'DNI (opcional)')),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Resumen de pago
          _cardWrap(
            icon: Icons.calculate_rounded,
            title: 'Resumen del pago',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('Subtotal', _moneda.format(subtotal)),
                _kv('IGV (18%)', _moneda.format(igv)),
                const Divider(),
                _kv('TOTAL', _moneda.format(widget.total), bold: true, big: true),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Botón de generación
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_generando || _rucValidando) ? null : _generar,
              icon: _generando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: Text(_generando ? 'Generando…' : 'Generar comprobante'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Envoltura visual estándar para secciones del formulario.
  Widget _cardWrap({required Widget child, required IconData icon, required String title}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  /// Estilo común de los campos de entrada.
  InputDecoration _inputDeco({String? label}) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  /// Muestra una fila de resumen clave-valor (Subtotal, IGV, Total).
  Widget _kv(String k, String v, {bool bold = false, bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            Text(
              v,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                fontSize: big ? 15 : 13.5,
              ),
            ),
          ],
        ),
      );

  /// Muestra un SnackBar informativo en la parte inferior de la pantalla.
  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
      );
}
