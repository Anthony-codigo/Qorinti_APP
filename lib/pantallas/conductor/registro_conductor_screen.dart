// lib/pantallas/conductor/registro_conductor_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: RegistroConductorScreen
// Descripción general:
//   Permite a un usuario registrado completar o actualizar su información
//   para habilitarse como conductor dentro de la aplicación Qorinti.
//   Los datos incluyen:
//     • Identificación personal (DNI, RUC, dirección fiscal).
//     • Licencia de conducir (número, categoría y fecha de vencimiento).
//   Una vez registrados, los datos quedan pendientes de validación por parte
//   del administrador o entidad supervisora.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_qorinti/modelos/conductor.dart';
import 'package:app_qorinti/modelos/utils.dart';

class RegistroConductorScreen extends StatefulWidget {
  static const route = '/conductor/registro';
  const RegistroConductorScreen({super.key});

  @override
  State<RegistroConductorScreen> createState() =>
      _RegistroConductorScreenState();
}

class _RegistroConductorScreenState extends State<RegistroConductorScreen> {
  // Llave del formulario para validaciones globales
  final _formKey = GlobalKey<FormState>();

  // Controladores de campos del formulario
  final _licenciaCtrl = TextEditingController();
  final _licenciaCategoriaCtrl = TextEditingController();
  final _dniCtrl = TextEditingController();
  final _rucCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  // Variables auxiliares
  DateTime? _licenciaVencimiento; // Fecha de vencimiento de licencia
  bool _loading = false;           // Estado de carga
  String? _mensaje;                // Mensaje de resultado o error

  @override
  void dispose() {
    // Liberar controladores al cerrar pantalla
    _licenciaCtrl.dispose();
    _licenciaCategoriaCtrl.dispose();
    _dniCtrl.dispose();
    _rucCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Validadores de campos
  // --------------------------------------------------------------------------

  String? _validarNoVacio(String? v) {
    if (v == null || v.trim().isEmpty) return "Campo requerido";
    return null;
  }

  String? _validarDni(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return "Campo requerido";
    if (t.length != 8 || int.tryParse(t) == null) {
      return "DNI debe tener 8 dígitos numéricos";
    }
    return null;
  }

  String? _validarRucOpcional(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    if (t.length != 11 || int.tryParse(t) == null) {
      return "RUC debe tener 11 dígitos numéricos";
    }
    return null;
  }

  String? _validarCategoria(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    if (t.isEmpty) return "Campo requerido";
    // Verifica formato tipo "A1", "B2", etc.
    final reg = RegExp(r'^[A-C][1-3]$');
    if (!reg.hasMatch(t)) {
      return "Categoría inválida (ej. A1, A2, B2...)";
    }
    return null;
  }

  // Valida que la fecha de vencimiento sea futura
  String? _validarVencimiento(DateTime? d) {
    if (d == null) return "Debes seleccionar fecha de vencimiento.";
    final hoy = DateTime.now();
    final soloHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final soloFecha = DateTime(d.year, d.month, d.day);
    if (!soloFecha.isAfter(soloHoy)) {
      return "La fecha debe ser futura.";
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // Función principal: Registrar o actualizar conductor en Firestore
  // --------------------------------------------------------------------------
  Future<void> _registrarConductor() async {
    if (!_formKey.currentState!.validate()) return;

    final errorFecha = _validarVencimiento(_licenciaVencimiento);
    if (errorFecha != null) {
      setState(() => _mensaje = errorFecha);
      return;
    }

    setState(() {
      _loading = true;
      _mensaje = null;
    });

    try {
      // Verifica sesión activa
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _mensaje = "No hay sesión iniciada.");
        return;
      }
      final uid = user.uid;

      // Referencia al documento del conductor
      final docRef = FirebaseFirestore.instance.collection('conductores').doc(uid);
      final snap = await docRef.get();

      // Construcción del objeto conductor
      final c = Conductor(
        id: uid,
        idUsuario: uid,
        dni: _dniCtrl.text.trim(),
        ruc: _rucCtrl.text.trim().isEmpty ? null : _rucCtrl.text.trim(),
        direccionFiscal: _direccionCtrl.text.trim().isEmpty ? null : _direccionCtrl.text.trim(),
        licenciaNumero: _licenciaCtrl.text.trim(),
        licenciaCategoria: _licenciaCategoriaCtrl.text.trim().toUpperCase(),
        licenciaVencimiento: _licenciaVencimiento,
      );

      final baseMap = c.toMap();

      // ------------------------------------------------------------------
      // Si no existe, crea un nuevo registro de conductor
      // ------------------------------------------------------------------
      if (!snap.exists) {
        await docRef.set({
          ...baseMap,
          'verificado': false,
          'estado': 'PENDIENTE',
          'ratingPromedio': 0.0,
          'ratingConteo': 0,
          'cancelaciones': 0,
          'radioKm': 10.0,
          'tiposServicioHabilitados': ['TAXI', 'CARGA'],
          'creadoEn': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });

        setState(() => _mensaje = "Registro enviado. Tus documentos están en revisión.");
      } 
      // ------------------------------------------------------------------
      // Si ya existe, actualiza los datos relevantes
      // ------------------------------------------------------------------
      else {
        final updateData = {
          'dni': c.dni,
          if (c.ruc != null && c.ruc!.isNotEmpty)
            'ruc': c.ruc
          else
            'ruc': FieldValue.delete(),
          if (c.direccionFiscal != null && c.direccionFiscal!.isNotEmpty)
            'direccionFiscal': c.direccionFiscal
          else
            'direccionFiscal': FieldValue.delete(),
          'licenciaNumero': c.licenciaNumero,
          'licenciaCategoria': c.licenciaCategoria?.toUpperCase(),
          'licenciaVencimiento': Timestamp.fromDate(c.licenciaVencimiento!),
          'actualizadoEn': FieldValue.serverTimestamp(),
        };

        await docRef.update(updateData);
        setState(() => _mensaje = "Datos de conductor actualizados correctamente.");
      }
    } catch (e) {
      setState(() => _mensaje = "Error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  // --------------------------------------------------------------------------
  // Selector de fecha de vencimiento de licencia
  // --------------------------------------------------------------------------
  Future<void> _seleccionarFecha(BuildContext context) async {
    final ahora = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: ahora,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('es', ''),
    );
    if (picked != null) {
      setState(() => _licenciaVencimiento = picked);
    }
  }

  // --------------------------------------------------------------------------
  // Construcción visual de la interfaz del formulario
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final venceTxt = _licenciaVencimiento == null
        ? "Selecciona fecha de vencimiento"
        : "Vence: ${formatDate(_licenciaVencimiento)}";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Registro de Conductor"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // --------------------------------------------------------------
              // Sección: Datos personales
              // --------------------------------------------------------------
              _tituloSeccion("Datos personales"),
              _tarjeta([
                TextFormField(
                  controller: _dniCtrl,
                  decoration: const InputDecoration(labelText: "DNI"),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  validator: _validarDni,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _rucCtrl,
                  decoration: const InputDecoration(labelText: "RUC (opcional)"),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  validator: _validarRucOpcional,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _direccionCtrl,
                  decoration: const InputDecoration(
                    labelText: "Dirección fiscal (opcional)",
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
              ]),
              const SizedBox(height: 24),

              // --------------------------------------------------------------
              // Sección: Licencia de conducir
              // --------------------------------------------------------------
              _tituloSeccion("Licencia de conducir"),
              _tarjeta([
                TextFormField(
                  controller: _licenciaCtrl,
                  decoration: const InputDecoration(labelText: "Número de licencia"),
                  validator: _validarNoVacio,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _licenciaCategoriaCtrl,
                  decoration: const InputDecoration(
                    labelText: "Categoría de licencia (ej. A1, A2)",
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    LengthLimitingTextInputFormatter(3),
                  ],
                  validator: _validarCategoria,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        venceTxt,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _seleccionarFecha(context),
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: const Text("Elegir fecha"),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 30),

              // --------------------------------------------------------------
              // Botón principal: Registrar o actualizar datos
              // --------------------------------------------------------------
              ElevatedButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline),
                label: Text(_loading ? "Guardando..." : "Registrar"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: _loading ? null : _registrarConductor,
              ),

              // --------------------------------------------------------------
              // Mensaje final de confirmación o error
              // --------------------------------------------------------------
              if (_mensaje != null) ...[
                const SizedBox(height: 20),
                Text(
                  _mensaje!,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _mensaje!.startsWith("Error") ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Widgets auxiliares para estructura visual
  // --------------------------------------------------------------------------
  Widget _tituloSeccion(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2E3A59),
          ),
        ),
      );

  Widget _tarjeta(List<Widget> children) => Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: children),
        ),
      );
}

// -----------------------------------------------------------------------------
// Clase auxiliar para forzar texto en mayúsculas
// Útil en el campo de categoría de licencia (A1, B2, etc.)
// -----------------------------------------------------------------------------
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue, 
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
