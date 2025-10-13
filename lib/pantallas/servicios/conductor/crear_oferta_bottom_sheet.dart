// lib/pantallas/servicios/crear_oferta_bottom_sheet.dart
// -----------------------------------------------------------------------------
// Componente: CrearOfertaBottomSheet
// Descripción general:
//   Hoja modal inferior (BottomSheet) utilizada por conductores para crear y enviar
//   una oferta sobre un servicio disponible dentro del sistema Qorinti App.
//
//   Permite ingresar el precio ofrecido, tiempo estimado de servicio y notas
//   opcionales. Valida las condiciones de negocio antes de registrar la oferta:
//
//     • Verifica que el servicio aún admita ofertas (estado y disponibilidad).
//     • Evita que un conductor oferte a su propio servicio.
//     • Impide enviar múltiples ofertas del mismo conductor para un mismo servicio.
//     • Normaliza montos decimales y restringe formatos de entrada.
//
//   La creación de ofertas se gestiona mediante:
//     - FirebaseAuth → identificación del conductor autenticado.
//     - Cloud Firestore → persistencia de datos de oferta.
//     - ServicioRepository → capa de abstracción para crear la oferta.
//
//   Interfaz:
//     - Formulario reactivo con validaciones inmediatas.
//     - Botón de envío con indicador de carga.
//     - Campos con formateadores personalizados (precio y tiempo).
// -----------------------------------------------------------------------------

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_qorinti/modelos/oferta.dart';
import 'package:app_qorinti/repos/servicio_repository.dart';

class CrearOfertaBottomSheet extends StatefulWidget {
  final String idServicio;
  const CrearOfertaBottomSheet({super.key, required this.idServicio});

  @override
  State<CrearOfertaBottomSheet> createState() => _CrearOfertaBottomSheetState();
}

class _CrearOfertaBottomSheetState extends State<CrearOfertaBottomSheet> {
  // --------------------------------------------------------------------------
  // Controladores, estados y referencias de formulario
  // --------------------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();

  final _precioCtrl = TextEditingController();
  final _tiempoCtrl = TextEditingController();
  final _notasCtrl  = TextEditingController();

  final _precioFocus = FocusNode();
  final _tiempoFocus = FocusNode();
  final _notasFocus  = FocusNode();

  bool _enviando = false;     // indica si hay envío en proceso
  int? _hintMin;              // valor sugerido de tiempo estimado (desde SLA)

  // --------------------------------------------------------------------------
  // Inicialización: obtiene sugerencia de tiempo desde Firestore
  // --------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance
        .collection('servicios')
        .doc(widget.idServicio)
        .get()
        .then((d) {
      final m = d.data();
      if (!mounted || m == null) return;
      final sla = (m['slaMin'] is int) ? m['slaMin'] as int : null;
      final eta = (m['tiempoEstimadoMin'] is int) ? m['tiempoEstimadoMin'] as int : null;
      setState(() => _hintMin = sla ?? eta);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _precioCtrl.dispose();
    _tiempoCtrl.dispose();
    _notasCtrl.dispose();
    _precioFocus.dispose();
    _tiempoFocus.dispose();
    _notasFocus.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Genera un ID único de oferta (uid + timestamp)
  // --------------------------------------------------------------------------
  String _genOfertaId(String uid) => '$uid-${DateTime.now().millisecondsSinceEpoch}';

  // --------------------------------------------------------------------------
  // Verifica si el conductor ya envió una oferta para este servicio
  // --------------------------------------------------------------------------
  Future<bool> _yaExisteOfertaDeEsteConductor(String uid) async {
    final qs = await FirebaseFirestore.instance
        .collection('servicios').doc(widget.idServicio)
        .collection('ofertas')
        .where('idConductor', isEqualTo: uid)
        .limit(1)
        .get();
    return qs.docs.isNotEmpty;
  }

  // --------------------------------------------------------------------------
  // Valida si el servicio aún admite ofertas:
  //   - Estado del servicio ("PENDIENTE_OFERTAS")
  //   - No sea del mismo usuario solicitante
  //   - No exista ya una oferta aceptada
  // --------------------------------------------------------------------------
  Future<bool> _servicioAdmiteOfertas(String uidConductor) async {
    final servRef = FirebaseFirestore.instance.collection('servicios').doc(widget.idServicio);
    final s = await servRef.get();
    if (!s.exists) {
      _showSnack('El servicio ya no está disponible.');
      return false;
    }

    final data = s.data()!;
    final estado = (data['estado'] ?? '').toString().toUpperCase();
    final idSolicitante = (data['idUsuarioSolicitante'] ?? '').toString();

    if (idSolicitante == uidConductor) {
      _showSnack('No puedes ofertar a tu propio servicio.');
      return false;
    }
    if (estado != 'PENDIENTE_OFERTAS') {
      _showSnack('Este servicio ya no admite ofertas.');
      return false;
    }

    final aceptadas = await servRef
        .collection('ofertas')
        .where('estado', isEqualTo: 'aceptada')
        .limit(1)
        .get();
    if (aceptadas.docs.isNotEmpty) {
      _showSnack('Ya existe una oferta aceptada.');
      return false;
    }
    return true;
  }

  // --------------------------------------------------------------------------
  // Utilidad: normaliza entradas decimales con punto (.) en lugar de coma (,)
  // --------------------------------------------------------------------------
  String _normalizeDecimal(String input) {
    final t = input.trim().replaceAll(',', '.');
    if (t.startsWith('.')) return '0$t';
    return t;
  }

  // --------------------------------------------------------------------------
  // Validación de campo: precio ofrecido
  // --------------------------------------------------------------------------
  String? _validaPrecio(String? v) {
    final s = _normalizeDecimal(v ?? '');
    final n = double.tryParse(s);
    if (n == null || n <= 0) return 'Ingresa un monto válido';
    if (n > 9999.99) return 'Monto demasiado alto';
    if (n.toStringAsFixed(2) == '0.00') return 'Ingresa un monto válido';
    return null;
  }

  // --------------------------------------------------------------------------
  // Validación de campo: tiempo estimado en minutos
  // --------------------------------------------------------------------------
  String? _validaTiempo(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n <= 0) return 'Ingresa un tiempo válido';
    if (n > 480) return 'Máx. 480 min';
    return null;
  }

  // Comprueba si ambos campos son válidos
  bool get _formValido =>
      _validaPrecio(_precioCtrl.text) == null &&
      _validaTiempo(_tiempoCtrl.text) == null;

  // --------------------------------------------------------------------------
  // Acción principal: enviar oferta al sistema
  // --------------------------------------------------------------------------
  Future<void> _enviar() async {
    if (_enviando) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnack('Debes iniciar sesión como conductor.');
      return;
    }
    if (!_formKey.currentState!.validate()) {
      _precioFocus.requestFocus();
      return;
    }

    setState(() => _enviando = true);

    try {
      // Validaciones previas al envío
      if (!await _servicioAdmiteOfertas(uid)) {
        setState(() => _enviando = false);
        return;
      }

      if (await _yaExisteOfertaDeEsteConductor(uid)) {
        _showSnack('Ya enviaste una oferta a este servicio.');
        setState(() => _enviando = false);
        return;
      }

      // Construcción de la oferta
      final precioNormalizado = _normalizeDecimal(_precioCtrl.text);
      final precio = double.parse(precioNormalizado);
      final tiempo = int.parse(_tiempoCtrl.text.trim());

      final oferta = Oferta(
        id: _genOfertaId(uid),
        idServicio: widget.idServicio,
        idConductor: uid,
        precioOfrecido: precio,
        tiempoEstimadoMin: tiempo,
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
        estado: EstadoOferta.pendiente,
        creadoEn: null,
        actualizadoEn: null,
      );

      // Envío de oferta a través del repositorio de servicios
      final repo = context.read<ServicioRepository>();
      await repo.crearOferta(oferta);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showSnack('❌ Error al enviar oferta: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // --------------------------------------------------------------------------
  // Utilidad: muestra mensajes tipo snackbar
  // --------------------------------------------------------------------------
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // --------------------------------------------------------------------------
  // Construcción del formulario visual (BottomSheet)
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Indicador visual superior del BottomSheet
                  Center(
                    child: Container(
                      width: 42, height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  // Encabezado
                  Row(
                    children: [
                      Icon(Icons.local_offer, color: cs.primary),
                      const SizedBox(width: 8),
                      const Text('Crear oferta',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Campo: Precio ofrecido
                  TextFormField(
                    controller: _precioCtrl,
                    focusNode: _precioFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Precio ofrecido (S/.)',
                      hintText: 'Ej: 25.50',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      _SingleDecimalFormatter(),
                      LengthLimitingTextInputFormatter(8),
                    ],
                    validator: _validaPrecio,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) {
                      _precioCtrl.text = _normalizeDecimal(_precioCtrl.text);
                      _tiempoFocus.requestFocus();
                    },
                  ),
                  const SizedBox(height: 12),

                  // Campo: Tiempo estimado en minutos
                  TextFormField(
                    controller: _tiempoCtrl,
                    focusNode: _tiempoFocus,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Tiempo estimado (min)',
                      hintText: _hintMin != null ? 'Ej: $_hintMin' : 'Ej: 30',
                      prefixIcon: const Icon(Icons.timer),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    validator: _validaTiempo,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _notasFocus.requestFocus(),
                  ),
                  const SizedBox(height: 12),

                  // Campo: Notas opcionales
                  TextFormField(
                    controller: _notasCtrl,
                    focusNode: _notasFocus,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      hintText: 'Mensaje breve para el cliente…',
                      prefixIcon: Icon(Icons.notes),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    maxLines: 2,
                    maxLength: 160,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _enviar(),
                  ),
                  const SizedBox(height: 16),

                  // Botón principal de envío
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _enviando || !_formValido ? null : _enviar,
                      icon: _enviando
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(_enviando ? 'Enviando…' : 'Enviar oferta'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Formateador personalizado: permite solo un separador decimal y 2 decimales
// -----------------------------------------------------------------------------
class _SingleDecimalFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;

    final dots = '.'.allMatches(text).length;
    final commas = ','.allMatches(text).length;
    if (dots + commas > 1) return oldValue;

    final idx = text.indexOf(RegExp(r'[.,]'));
    if (idx >= 0) {
      final dec = text.substring(idx + 1);
      if (dec.length > 2) return oldValue;
    }
    return newValue;
  }
}
