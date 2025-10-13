// Servicio de agregación de perfil de usuario.
// Expone un stream que combina en tiempo real múltiples colecciones de Firestore
// para construir un PerfilExtendido (datos del usuario, conductor, vehículos y vínculos empresa).
//
// Diseño y consideraciones:
// - Se usa Rx.combineLatest4 para sincronizar cuatro flujos: usuario, conductor,
//   vehículos (lista) y relaciones usuario-empresa (lista).
// - Si el documento de usuario no existe, se lanza una excepción para indicar
//   un estado inconsistente (el resto de entidades dependen del usuario).
// - El perfil de conductor es opcional; vehículos y empresas se mapearán a listas vacías si no hay registros.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'package:app_qorinti/modelos/usuario.dart';
import 'package:app_qorinti/modelos/conductor.dart';
import 'package:app_qorinti/modelos/vehiculo.dart';
import 'package:app_qorinti/modelos/usuario_empresa.dart';
import 'package:app_qorinti/modelos/perfil_extendido.dart';

class PerfilService {
  final _db = FirebaseFirestore.instance;

  /// Devuelve un stream reactivo de [PerfilExtendido] para el usuario [uid].
  /// Combina:
  /// - Doc de `usuarios/{uid}`
  /// - Doc de `conductores/{uid}` (opcional)
  /// - Query `vehiculos` filtrando por `idPropietarioUsuario == uid`
  /// - Query `usuario_empresa` filtrando por `idUsuario == uid`
  ///
  /// Emite una nueva instancia de perfil cada vez que cualquiera de las fuentes cambia.
  Stream<PerfilExtendido> streamPerfil(String uid) {
    final usuario$ = _db.collection('usuarios').doc(uid).snapshots();
    final conductor$ = _db.collection('conductores').doc(uid).snapshots();
    final vehiculos$ = _db
        .collection('vehiculos')
        .where('idPropietarioUsuario', isEqualTo: uid)
        .snapshots();
    final empresas$ = _db
        .collection('usuario_empresa')
        .where('idUsuario', isEqualTo: uid)
        .snapshots();

    return Rx.combineLatest4<
        DocumentSnapshot<Map<String, dynamic>>,
        DocumentSnapshot<Map<String, dynamic>>,
        QuerySnapshot<Map<String, dynamic>>,
        QuerySnapshot<Map<String, dynamic>>,
        PerfilExtendido>(
      usuario$,
      conductor$,
      vehiculos$,
      empresas$,
      (uSnap, cSnap, vSnap, eSnap) {
        // Validación estricta: el documento de usuario debe existir.
        if (!uSnap.exists || uSnap.data() == null) {
          throw Exception("Usuario no encontrado");
        }
        final usuario = Usuario.fromMap(uSnap.data()!, id: uSnap.id);

        // El rol de conductor es opcional.
        Conductor? conductor;
        if (cSnap.exists && cSnap.data() != null) {
          conductor = Conductor.fromMap(cSnap.data()!, id: cSnap.id);
        }

        // Mapeo de vehículos propiedad del usuario.
        final vehiculos = vSnap.docs
            .map((d) => Vehiculo.fromMap(d.data(), id: d.id))
            .toList();

        // Mapeo de asociaciones empresa-usuario.
        final empresas = eSnap.docs
            .map((d) => UsuarioEmpresa.fromMap(d.data(), id: d.id))
            .toList();

        // Ensamblaje del perfil extendido con todas las fuentes.
        return PerfilExtendido(
          usuario: usuario,
          conductor: conductor,
          vehiculos: vehiculos,
          empresas: empresas,
        );
      },
    );
  }
}
