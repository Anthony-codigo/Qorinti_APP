// Servicio de consulta de RUC contra API pública (apis.net.pe).
// Encapsula la llamada HTTP, manejo de tiempo de espera y parseo de respuesta JSON.
// Uso previsto: validación de existencia del RUC y obtención de datos asociados.
//
// Notas de diseño:
// - El token está inyectado como string literal para simplicidad; en producción se recomienda
//   externalizar (variables de entorno/Remote Config/secure storage) y rotación periódica.
// - Los mensajes de error usan print() para trazas rápidas; para apps en producción considerar
//   integrar un logger estructurado (p. ej., package:logging, Sentry) con niveles.
// - El método expone un Future<Map<String,dynamic>?>, retornando `null` en casos de error o RUC inválido.
//   Esto simplifica el consumo aguas arriba, pero si se requiere diagnóstico fino,
//   podría retornarse un tipo resultado (éxito/error) con metadatos.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class RucServicio {
  // Token de autenticación Bearer para la API remota.
  // Recomendación: no versionar tokens reales y utilizar un almacén seguro.
  final String _token = "apis-token-1234"; 

  /// Valida un RUC consultando la API y devuelve el JSON decodificado cuando la
  /// respuesta es 200 (OK). En caso de RUC inválido (422), timeout u otro error,
  /// devuelve `null`.
  ///
  /// Parámetros:
  /// - [ruc]: cadena numérica del RUC a consultar.
  ///
  /// Comportamiento:
  /// - GET a https://api.apis.net.pe/v1/ruc?numero=<ruc>, con Authorization: Bearer <token>.
  /// - Timeout configurado a 8 segundos.
  /// - status 200 → jsonDecode(body)
  /// - status 422 → RUC inválido/no encontrado → null
  /// - Otros status → null
  /// - TimeoutException / Exception → null
  Future<Map<String, dynamic>?> validarRuc(String ruc) async {
    try {
      final url = Uri.parse("https://api.apis.net.pe/v1/ruc?numero=$ruc");

      final response = await http
          .get(url, headers: {
            "Authorization": "Bearer $_token",
          })
          .timeout(const Duration(seconds: 8)); // Límite de espera de la solicitud.
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 422) {
        // RUC inválido o no existe según la API.
        print("RUC inválido o no encontrado");
        return null;
      } else {
        // Otros códigos HTTP no considerados como éxito.
        print("Error en consulta: ${response.statusCode}");
        return null;
      }
    } on TimeoutException {
      // Nota: este print incluye un emoji en el mensaje original del autor.
      print("⏱ Tiempo de espera agotado en consulta de RUC");
      return null;
    } catch (e) {
      // Captura genérica de excepciones (red, parseo, etc.).
      print(" Excepción en validarRuc: $e");
      return null;
    }
  }
}
