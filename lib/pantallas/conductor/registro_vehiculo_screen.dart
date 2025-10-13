// lib/pantallas/conductor/registro_vehiculo_screen.dart
// -----------------------------------------------------------------------------
// Pantalla: RegistroVehiculoScreen
// Descripción general:
//   Permite al usuario registrar un nuevo vehículo en el sistema Qorinti.
//   Los datos ingresados se guardan en la colección 'vehiculos' de Firestore.
//   El registro queda en estado "PENDIENTE" hasta su revisión y aprobación
//   por parte del administrador del sistema.
//
//   Se ingresan los siguientes datos:
//     • Identificación básica (placa, marca, modelo, año, tipo).
//     • Dimensiones y capacidad de carga (opcional).
//     • Documentos (SOAT, revisión técnica).
//
//   Esta pantalla implementa validaciones para formato de placa, año, y
//   tipos de datos numéricos, además de control de estado visual (enviado,
//   cargando, o error).
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_qorinti/modelos/utils.dart';

class RegistroVehiculoScreen extends StatefulWidget {
  static const route = '/vehiculo/registro';
  const RegistroVehiculoScreen({super.key});

  @override
  State<RegistroVehiculoScreen> createState() => _RegistroVehiculoScreenState();
}

class _RegistroVehiculoScreenState extends State<RegistroVehiculoScreen> {
  // Llave del formulario para validaciones globales
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto para campos del formulario
  final _placaCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  final _anioCtrl = TextEditingController();

  final _soatNumeroCtrl = TextEditingController();
  DateTime? _soatVencimiento;       // Fecha de vencimiento del SOAT
  DateTime? _revisionTecnica;       // Fecha de revisión técnica

  // Campos para capacidades y dimensiones del vehículo
  final _capacidadTonCtrl = TextEditingController();
  final _volumenM3Ctrl = TextEditingController();
  final _altoMCtrl = TextEditingController();
  final _anchoMCtrl = TextEditingController();
  final _largoMCtrl = TextEditingController();

  // Selectores de tipo y carrocería
  String _tipoVehiculo = 'CAMIONETA';  // Valor por defecto
  String? _tipoCarroceria;             // Valor opcional

  // Estados visuales
  bool _loading = false;       // Indica si se está guardando
  bool _submitted = false;     // Indica si ya fue enviado
  String? _mensaje;            // Mensaje informativo o de error
  Color _mensajeColor = Colors.black; // Color del mensaje

  @override
  void dispose() {
    // Libera memoria de controladores cuando se destruye la pantalla
    _placaCtrl.dispose();
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _anioCtrl.dispose();
    _soatNumeroCtrl.dispose();
    _capacidadTonCtrl.dispose();
    _volumenM3Ctrl.dispose();
    _altoMCtrl.dispose();
    _anchoMCtrl.dispose();
    _largoMCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Función principal: Registrar vehículo en Firestore
  // --------------------------------------------------------------------------
  Future<void> _registrarVehiculo() async {
    // Si ya se está procesando o el formulario fue enviado, no hacer nada
    if (_loading || _submitted) return;

    // Validación general de formulario
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _mensaje = null;
    });

    try {
      // Obtiene el UID del usuario autenticado
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final vehiculosRef = FirebaseFirestore.instance.collection('vehiculos');

      // Normaliza la placa (elimina espacios, guiones largos, pasa a mayúscula)
      final placaNorm = _placaCtrl.text
          .toUpperCase()
          .trim()
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll('—', '-');

      final docRef = vehiculosRef.doc(placaNorm);
      final yaExiste = await docRef.get();

      // Si la placa ya existe, mostrar error y no continuar
      if (yaExiste.exists) {
        setState(() {
          _mensaje = "Esta placa ya está registrada.";
          _mensajeColor = Colors.red;
        });
        return;
      }

      // Conversión de datos numéricos y fechas
      final int? anio = int.tryParse(_anioCtrl.text.trim());
      final double? capacidadTon = double.tryParse(_capacidadTonCtrl.text.trim());
      final double? volumenM3 = double.tryParse(_volumenM3Ctrl.text.trim());
      final double? altoM = double.tryParse(_altoMCtrl.text.trim());
      final double? anchoM = double.tryParse(_anchoMCtrl.text.trim());
      final double? largoM = double.tryParse(_largoMCtrl.text.trim());

      // Construcción del mapa de datos para Firestore
      final data = <String, dynamic>{
        'placa': placaNorm,
        'marca': _marcaCtrl.text.trim(),
        'modelo': _modeloCtrl.text.trim(),
        'anio': anio,
        'capacidadTon': capacidadTon,
        'volumenM3': volumenM3,
        'altoM': altoM,
        'anchoM': anchoM,
        'largoM': largoM,
        'tipoCarroceria': _tipoCarroceria?.toUpperCase(),
        'idPropietarioUsuario': uid,
        'idPropietarioEmpresa': null,
        'soatNumero': _soatNumeroCtrl.text.trim(),
        'soatVencimiento': _soatVencimiento != null
            ? Timestamp.fromDate(_soatVencimiento!)
            : null,
        'revisionTecnica': _revisionTecnica != null
            ? Timestamp.fromDate(_revisionTecnica!)
            : null,
        'estado': 'PENDIENTE',              // Estado inicial
        'tipo': _tipoVehiculo.toUpperCase(),
        'activo': false,                    // No se activa hasta aprobación
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }..removeWhere((k, v) => v == null || (v is String && v.isEmpty));

      // Inserta documento en Firestore
      await docRef.set(data);

      // Mensaje de confirmación al usuario
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _mensaje =
            "Vehículo registrado correctamente.\nQuedó pendiente de aprobación por administración.";
        _mensajeColor = Colors.green;
      });

    } catch (e) {
      // Manejo de errores en registro
      if (!mounted) return;
      setState(() {
        _mensaje = "Error al registrar vehículo: $e";
        _mensajeColor = Colors.red;
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // --------------------------------------------------------------------------
  // Selector genérico de fechas para SOAT o revisión técnica
  // --------------------------------------------------------------------------
  Future<void> _seleccionarFecha(BuildContext context, String tipoCampo) async {
    final ahora = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: ahora,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('es', ''),
    );
    if (picked != null) {
      setState(() {
        if (tipoCampo == 'soat') {
          _soatVencimiento = picked;
        } else {
          _revisionTecnica = picked;
        }
      });
    }
  }

  // --------------------------------------------------------------------------
  // Validadores de campos de entrada
  // --------------------------------------------------------------------------

  // Valida formato de placa según tipo de vehículo
  String? _validarPlaca(String? v) {
    final raw = (v ?? '').toUpperCase().trim();
    if (raw.isEmpty) return 'Campo requerido';

    final value = raw.replaceAll(RegExp(r'\s+'), '').replaceAll('—', '-');
    final esMoto = _tipoVehiculo.toUpperCase() == 'MOTO';

    // Expresiones regulares para distintos tipos de placa
    final expAuto = RegExp(r'^(?:[A-Z]{3}-?\d{3}|[A-Z]{3}-?[A-Z0-9]{3})$');
    final expMoto = RegExp(r'^(?:\d{3}-?[A-Z]{3})$');
    final expRelajado = RegExp(r'^[A-Z0-9-]{6,7}$');

    final ok = esMoto
        ? (expMoto.hasMatch(value) || expAuto.hasMatch(value) || expRelajado.hasMatch(value))
        : (expAuto.hasMatch(value) || expMoto.hasMatch(value) || expRelajado.hasMatch(value));

    if (!ok) {
      return 'Placa no parece válida. Ej.: ABC-123, ABC-1A2${esMoto ? ", 123-ABC" : ""}';
    }
    return null;
  }

  // Valida año del vehículo dentro de un rango aceptable
  String? _validarAnio(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null) return 'Año no válido';
    final now = DateTime.now().year;
    if (n < 1980 || n > now + 1) return 'Año fuera de rango';
    return null;
  }

  // Decoración estándar para campos de texto
  InputDecoration _dec(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());

  // --------------------------------------------------------------------------
  // Construcción visual de la pantalla
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Listas para desplegables
    final carrocerias = <String>[
      'FURGON', 'PLATAFORMA', 'BARANDA', 'VOLQUETE',
      'CISTERNA', 'CONTAINER', 'OTRO',
    ];

    final tipos = <String>[
      'AUTO', 'MOTO', 'CAMIONETA', 'CAMION',
      'MINIVAN', 'TRACTO', 'OTRO',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Registro de Vehículo")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // --------------------------------------------------------------
              // BLOQUE 1: Identificación del vehículo
              // --------------------------------------------------------------
              TextFormField(
                controller: _placaCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _dec("Placa"),
                validator: _validarPlaca,
                enabled: !_submitted,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _marcaCtrl,
                      decoration: _dec("Marca"),
                      enabled: !_submitted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _modeloCtrl,
                      decoration: _dec("Modelo"),
                      enabled: !_submitted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _anioCtrl,
                      decoration: _dec("Año"),
                      keyboardType: TextInputType.number,
                      validator: _validarAnio,
                      enabled: !_submitted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _tipoVehiculo,
                      decoration: _dec("Tipo"),
                      items: tipos
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: _submitted
                          ? null
                          : (v) => setState(() => _tipoVehiculo = v ?? 'CAMIONETA'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              // --------------------------------------------------------------
              // BLOQUE 2: Especificaciones de carga (opcional)
              // --------------------------------------------------------------
              Text(
                "Especificaciones de carga (opcional)",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _capacidadTonCtrl,
                      decoration: _dec("Capacidad (ton)"),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_submitted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _volumenM3Ctrl,
                      decoration: _dec("Volumen (m³)"),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_submitted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _altoMCtrl,
                      decoration: _dec("Alto (m)"),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_submitted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _anchoMCtrl,
                      decoration: _dec("Ancho (m)"),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_submitted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _largoMCtrl,
                      decoration: _dec("Largo (m)"),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_submitted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _tipoCarroceria,
                decoration: _dec("Carrocería (opcional)"),
                items: carrocerias
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: _submitted ? null : (v) => setState(() => _tipoCarroceria = v),
              ),

              const SizedBox(height: 16),
              // --------------------------------------------------------------
              // BLOQUE 3: Documentación (SOAT y Revisión Técnica)
              // --------------------------------------------------------------
              Text(
                "Documentación",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _soatNumeroCtrl,
                decoration: _dec("Número SOAT"),
                enabled: !_submitted,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(_soatVencimiento == null
                        ? "Selecciona vencimiento SOAT"
                        : "SOAT vence: ${formatDate(_soatVencimiento)}"),
                  ),
                  ElevatedButton(
                    onPressed: _submitted ? null : () => _seleccionarFecha(context, 'soat'),
                    child: const Text("Elegir"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(_revisionTecnica == null
                        ? "Selecciona revisión técnica"
                        : "Revisión: ${formatDate(_revisionTecnica)}"),
                  ),
                  ElevatedButton(
                    onPressed: _submitted ? null : () => _seleccionarFecha(context, 'revision'),
                    child: const Text("Elegir"),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              // --------------------------------------------------------------
              // BOTÓN PRINCIPAL: Registrar vehículo
              // --------------------------------------------------------------
              ElevatedButton.icon(
                icon: const Icon(Icons.directions_car),
                onPressed: (_loading || _submitted) ? null : _registrarVehiculo,
                label: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : (_submitted
                        ? const Text("Enviado")
                        : const Text("Registrar Vehículo")),
              ),

              // Mensaje de confirmación o error al final
              if (_mensaje != null) ...[
                const SizedBox(height: 20),
                Text(
                  _mensaje!,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _mensajeColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
