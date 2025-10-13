// Importaciones principales de Flutter y librerías utilizadas
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_storage/firebase_storage.dart';

// Repositorio de finanzas y modelo de estado de cuenta del conductor
import 'package:app_qorinti/repos/finanzas_repository.dart';
import 'package:app_qorinti/modelos/estado_cuenta_conductor.dart';

// Constantes para configuración de métodos de pago locales
// Aquí se definen los números y rutas de QR para Yape y Plin
const String _YAPE_NUMERO = '929051797';
const String _PLIN_NUMERO = '929051797';

const String _YAPE_QR_STORAGE = 'Pago_QR/MIQR.jpg';
const String _PLIN_QR_STORAGE = '';

// Enumeración para representar los distintos métodos de pago disponibles
enum _MetodoLocal { yape, plin, transferencia, efectivo }

// Extensión sobre el enum _MetodoLocal que agrega propiedades
// útiles para la interfaz (label, icono y color asociado)
extension on _MetodoLocal {

  // Devuelve el texto representativo de cada método
  String get label {
    switch (this) {
      case _MetodoLocal.yape: return 'Yape';
      case _MetodoLocal.plin: return 'Plin';
      case _MetodoLocal.transferencia: return 'Transferencia';
      case _MetodoLocal.efectivo: return 'Efectivo';
    }
  }

  // Devuelve el ícono correspondiente a cada método
  IconData get icon {
    switch (this) {
      case _MetodoLocal.yape: return Icons.qr_code_2_rounded;
      case _MetodoLocal.plin: return Icons.qr_code_2_rounded;
      case _MetodoLocal.transferencia: return Icons.account_balance;
      case _MetodoLocal.efectivo: return Icons.payments;
    }
  }

  // Devuelve un color característico por método
  Color get color {
    switch (this) {
      case _MetodoLocal.yape: return Colors.deepPurple;
      case _MetodoLocal.plin: return Colors.indigo;
      case _MetodoLocal.transferencia: return Colors.teal;
      case _MetodoLocal.efectivo: return Colors.green;
    }
  }
}
/// Pantalla para registrar el pago de comisión de un conductor.
/// - Valida que el usuario autenticado coincida con el id del conductor.
/// - Muestra la deuda actual vía stream y propone autollenar el monto.
/// - Permite elegir método de pago y registrar la solicitud.
class RegistrarPagoComisionScreen extends StatefulWidget {
  final String idConductor;
  const RegistrarPagoComisionScreen({super.key, required this.idConductor});

  @override
  State<RegistrarPagoComisionScreen> createState() => _RegistrarPagoComisionScreenState();
}

class _RegistrarPagoComisionScreenState extends State<RegistrarPagoComisionScreen> {
  // Clave de formulario para validaciones
  final _formKey = GlobalKey<FormState>();
  // Controladores de campos del formulario
  final _montoCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  // Bandera de envío para deshabilitar UI mientras se procesa
  bool _enviando = false;
  // Método de pago seleccionado (por defecto Yape)
  _MetodoLocal _metodo = _MetodoLocal.yape;

  @override
  void dispose() {
    // Liberación de recursos de los controladores
    _montoCtrl.dispose();
    _refCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Inyección del repositorio de finanzas desde el contexto (Bloc/Provider)
    final repo = context.read<FinanzasRepository>();
    // Formateador de moneda para Perú
    final currency = NumberFormat.currency(locale: 'es_PE', symbol: 'S/ ', decimalDigits: 2);
    // Usuario autenticado
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Validación de sesión: el uid debe coincidir con el conductor objetivo
    if (uid == null || uid != widget.idConductor) {
      return const Scaffold(
        body: Center(child: Text('Sesión inválida')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar pago de comisión')),
      // Suscripción al estado de cuenta del conductor para obtener deuda actual
      body: StreamBuilder<EstadoCuentaConductor>(
        stream: repo.streamEstadoCuenta(widget.idConductor),
        builder: (context, snap) {
          final deuda = (snap.data?.deudaComision ?? 0);

          // Autollenar el campo de monto 1 sola vez si está vacío y hay deuda
          if ((deuda > 0) && _montoCtrl.text.trim().isEmpty) {
            _montoCtrl.text = deuda.toStringAsFixed(2);
          }

          // Habilitar envío solo si no está enviando y existe deuda
          final puedeEnviar = !_enviando && deuda > 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Resumen de deuda del conductor
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1.5,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.report, color: deuda > 0 ? Colors.red : Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            deuda > 0
                                ? 'Deuda pendiente: ${currency.format(deuda)}'
                                : '¡No tienes deuda pendiente!',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Selector de método de pago (chips) y ayudas contextuales
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Método de pago', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        // Chips de selección de método
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: _MetodoLocal.values.map((m) {
                            final selected = _metodo == m;
                            return ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Icono contextual del método
                                  Icon(m.icon, size: 16, color: selected ? Colors.white : m.color),
                                  const SizedBox(width: 6),
                                  Text(m.label),
                                ],
                              ),
                              selected: selected,
                              selectedColor: m.color,
                              labelStyle: TextStyle(
                                color: selected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                              onSelected: (_) => setState(() => _metodo = m),
                            );
                          }).toList(),
                        ),
                        // Ayuda para QR (Yape/Plin)
                        if (_metodo == _MetodoLocal.yape || _metodo == _MetodoLocal.plin) ...[
                          const SizedBox(height: 12),
                          _MetodoPagoAyuda(
                            titulo: _metodo == _MetodoLocal.yape ? 'Paga por Yape' : 'Paga por Plin',
                            numero: _metodo == _MetodoLocal.yape ? _YAPE_NUMERO : _PLIN_NUMERO,
                            storageRef: _metodo == _MetodoLocal.yape
                                ? _YAPE_QR_STORAGE
                                : _PLIN_QR_STORAGE,
                            color: _metodo.color,
                          ),
                        ],
                        // Texto de guía para transferencia bancaria
                        if (_metodo == _MetodoLocal.transferencia) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Transferencia bancaria a Qorinti. Incluye la referencia en el mensaje del pago.',
                            style: TextStyle(color: Colors.teal.shade700),
                          ),
                        ],
                        // Texto de guía para efectivo
                        if (_metodo == _MetodoLocal.efectivo) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Entrega en efectivo. Agrega una referencia/nota para identificar el pago.',
                            style: TextStyle(color: Colors.green.shade700),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Formulario principal de registro
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Campo: Monto a pagar
                      TextFormField(
                        controller: _montoCtrl,
                        enabled: deuda > 0,
                        decoration: const InputDecoration(
                          labelText: 'Monto a pagar',
                          prefixIcon: Icon(Icons.payments),
                          border: OutlineInputBorder(),
                          hintText: 'Ej: 10.00',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        // Validador: formato decimal, > 0, no exceder deuda
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+([.,]\d{0,2})?$')),
                        ],
                        validator: (v) {
                          if (deuda <= 0) return null;
                          if (v == null || v.trim().isEmpty) {
                            return 'Ingresa un monto';
                          }
                          final m = double.tryParse(v.replaceAll(',', '.'));
                          if (m == null || m <= 0) {
                            return 'Monto inválido';
                          }
                          if (m > deuda + 0.01) {
                            return 'No puedes pagar más que la deuda';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Campo: Referencia (opcional)
                      TextFormField(
                        controller: _refCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Referencia (opcional)',
                          prefixIcon: Icon(Icons.receipt_long),
                          border: OutlineInputBorder(),
                          hintText: 'ID operación / últimas 4 / voucher, etc.',
                        ),
                        maxLength: 80,
                        enabled: deuda > 0,
                      ),
                      const SizedBox(height: 12),
                      // Campo: Observaciones (opcional)
                      TextFormField(
                        controller: _obsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Observaciones (opcional)',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 200,
                        enabled: deuda > 0,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Aviso si no hay deuda
                if (deuda <= 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: const [
                        Icon(Icons.info_outline, size: 18),
                        SizedBox(width: 6),
                        Expanded(child: Text('No tienes deuda pendiente.')),
                      ],
                    ),
                  ),

                // Botón de acción principal: enviar solicitud
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: !puedeEnviar
                        ? null
                        : () async {
                            // Validación del formulario previa al envío
                            if (_formKey.currentState?.validate() != true) return;
                            final monto = double.parse(_montoCtrl.text.replaceAll(',', '.'));
                            final ref = _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim();
                            final obsUser = _obsCtrl.text.trim();
                            // Observaciones combinadas con método de pago
                            final obs = [
                              '[Método: ${_metodo.label}]',
                              if (obsUser.isNotEmpty) obsUser,
                            ].join(' ');

                            setState(() => _enviando = true);
                            try {
                              // Llamada al repositorio para registrar la solicitud
                              await repo.solicitarPagoComision(
                                idConductor: widget.idConductor,
                                monto: monto,
                                referencia: ref,
                                observaciones: obs.isEmpty ? null : obs,
                              );

                              if (!mounted) return;
                              // Aviso al usuario de éxito
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Solicitud enviada para revisión')),
                              );

                              // Cerrar la pantalla luego del envío
                              Navigator.pop(context);
                            } catch (e) {
                              if (!mounted) return;
                              // Manejo de error genérico mostrando el mensaje
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            } finally {
                              // Rehabilitar UI si la pantalla sigue montada
                              if (mounted) setState(() => _enviando = false);
                            }
                          },
                    // Indicador de progreso en el botón mientras se envía
                    icon: _enviando
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle),
                    label: Text(_enviando ? 'Procesando…' : 'Registrar pago'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Widget de ayuda visual para mostrar datos del método de pago por QR/transferencia.
/// - Resuelve la URL de descarga desde Firebase Storage o URL directa.
/// - Muestra número a copiar y una imagen QR si existe.
class _MetodoPagoAyuda extends StatelessWidget {
  final String titulo;
  final String numero;
  final String? storageRef;
  final Color color;

  const _MetodoPagoAyuda({
    required this.titulo,
    required this.numero,
    required this.storageRef,
    required this.color,
  });

  // Obtiene la URL de descarga del recurso (QR) según el tipo de referencia:
  // - gs:// -> refFromURL
  // - http/https -> se usa tal cual
  // - cadena simple -> se resuelve con ref(path)
  Future<String?> _resolveDownloadUrl(String? ref) async {
    if (ref == null || ref.trim().isEmpty) return null;
    final v = ref.trim();
    try {
      if (v.startsWith('gs://')) {
        return await FirebaseStorage.instance.refFromURL(v).getDownloadURL();
      } else if (v.startsWith('http://') || v.startsWith('https://')) {
        return v;
      } else {
        return await FirebaseStorage.instance.ref(v).getDownloadURL();
      }
    } catch (_) {
      // En caso de error al resolver/descargar, retorna null para mostrar placeholder
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Contenedor con color tenue y borde según el color del método
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sección del QR: muestra skeleton mientras carga,
          // placeholder si no hay URL, y la imagen si existe.
          FutureBuilder<String?>(
            future: _resolveDownloadUrl(storageRef),
            builder: (context, snap) {
              final url = snap.data;
              if (snap.connectionState == ConnectionState.waiting) {
                return _qrSkeleton();
              }
              if (url == null || url.isEmpty) {
                return _qrPlaceholder();
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 86,
                  height: 86,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _qrPlaceholder(),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          // Información textual: título, número y acción de copiar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.phone_iphone, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        numero,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Botón para copiar el número al portapapeles
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: numero));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Número copiado'),
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(milliseconds: 1200),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copiar'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Coloca la referencia/nota en tu operación para identificar el pago.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Placeholder a mostrar si no hay QR disponible o hubo error al cargar
  Widget _qrPlaceholder() => Container(
        width: 86,
        height: 86,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12),
        ),
        child: const Icon(Icons.qr_code_2, size: 36, color: Colors.black45),
      );

  // Skeleton de carga mientras se resuelve la URL del QR
  Widget _qrSkeleton() => Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}
