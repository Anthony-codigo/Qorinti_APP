// Repositorio de gestión de calificaciones entre usuarios dentro de la aplicación Qorinti.
// 
// Este módulo centraliza las operaciones CRUD relacionadas con las calificaciones
// que se otorgan entre conductores y usuarios tras finalizar un servicio.
// Permite crear registros de calificación, actualizar el resumen de puntuación
// dentro del documento de servicio correspondiente y consultar las calificaciones
// recibidas por un usuario.
// 
// Consideraciones técnicas:
// - Utiliza la colección `calificaciones` para almacenar los registros individuales.
// - Actualiza la colección `servicios` para mantener un campo resumen de calificación.
// - Emplea streams para ofrecer actualizaciones en tiempo real de las calificaciones recibidas.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_qorinti/modelos/calificacion.dart';

class CalificacionRepository {
  final FirebaseFirestore _db;
  CalificacionRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  // Referencias a las colecciones principales
  CollectionReference<Map<String, dynamic>> get _calificaciones =>
      _db.collection('calificaciones');
  CollectionReference<Map<String, dynamic>> get _servicios =>
      _db.collection('servicios');

  /// Crea una nueva calificación en la colección `calificaciones`.
  /// Retorna el ID del documento generado.
  Future<String> crearCalificacion(Calificacion calificacion) async {
    try {
      final ref = await _calificaciones.add(
        calificacion.toMap(serverNowIfNull: true),
      );
      return ref.id;
    } catch (e) {
      throw Exception('Error al crear calificación: $e');
    }
  }

  /// Actualiza el documento del servicio con un resumen de la calificación recibida.
  /// El campo actualizado depende del origen de la calificación:
  /// - Si `esCalificacionDeConductor` es true, se actualiza `calificacionUsuario`.
  /// - Caso contrario, se actualiza `calificacionConductor`.
  Future<void> setResumenEnServicio({
    required String idServicio,
    required bool esCalificacionDeConductor,
    required int estrellas,
  }) async {
    final campo = esCalificacionDeConductor ? 'calificacionUsuario' : 'calificacionConductor';
    try {
      await _servicios.doc(idServicio).update({
        campo: estrellas,
        'fechaActualizacion': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error al actualizar resumen en servicio: $e');
    }
  }

  /// Devuelve un stream con la lista de calificaciones recibidas por un usuario específico.
  /// Los resultados se ordenan por fecha de creación (más recientes primero).
  Stream<List<Calificacion>> calificacionesDeUsuario(String paraUsuarioId) {
    return _calificaciones
        .where('paraUsuarioId', isEqualTo: paraUsuarioId)
        .orderBy('creadoEn', descending: true)
        .snapshots()
        .map((qs) => qs.docs
            .map((d) => Calificacion.fromMap(d.data(), d.id))
            .toList());
  }
}
