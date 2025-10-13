Qorinti App – Sistema Móvil de Gestión de Transporte
Descripción General

Qorinti App es una aplicación móvil multiplataforma desarrollada en Flutter con backend en Firebase, diseñada para optimizar el proceso de gestión de transporte de la empresa Transportes Qorinti S.A.C.
Su objetivo es digitalizar los procesos manuales de asignación, seguimiento y control de servicios logísticos, permitiendo una comunicación fluida entre clientes, conductores y administradores, además de mejorar la precisión en la facturación y liquidación de pagos por comisión.

Arquitectura y Tecnologías

Framework principal: Flutter 3.x

Backend y servicios en la nube: Firebase (Firestore, Authentication, Storage)

Gestión de estado: Bloc Pattern (flutter_bloc)

Mapas y ubicación: Google Maps SDK, Geolocator, Google Places API

Internacionalización: intl

Gestión de dependencias: pubspec.yaml

Módulos principales

Autenticación y gestión de usuarios

Registro e inicio de sesión con Google o correo electrónico (Firebase Auth).

Validación de correo y roles dinámicos (cliente, conductor, administrador).

Gestión de empresas

Registro de empresas y solicitudes para unirse a una existente.

Aprobación de solicitudes por el administrador general.

Conductores y vehículos

Registro y aprobación de conductores.

Registro de vehículos vinculados a conductores aprobados.

Asociación conductor–vehículo validada por el administrador.

Servicios y ofertas

Creación de solicitudes de transporte con tipo de servicio, origen, destino y paradas.

Publicación y visualización en tiempo real de ofertas de conductores.

Aceptación de ofertas por parte del cliente e inicio del viaje.

Viaje en curso

Seguimiento GPS en tiempo real.

Cambio de estado automático (aceptado → en curso → finalizado).

Cancelación o finalización de viaje según rol.

Pagos y comisiones

Cálculo automático del 5 % de comisión por cada viaje completado.

Registro y validación de pagos por parte del administrador.

Generación automática de comprobantes Qorinti (boleta/factura).

Comprobantes y facturación

Emisión de comprobantes según tipo de documento (DNI → boleta | RUC → factura).

Opción para usar datos fiscales de empresa como emisor.

Reportes e indicadores

Panel de métricas: eficiencia, puntualidad, tiempo promedio de asignación y precisión de facturación.

Exportación a Excel para análisis externo.

Instalación y Configuración Inicial
1. Clonar el repositorio
git clone https://github.com/usuario/app_qorinti.git
cd app_qorinti

2. Instalar dependencias
flutter pub get

3. Configuración de Firebase

Cada usuario o institución que ejecute el proyecto debe crear su propio proyecto de Firebase en Firebase Console
 y activar los siguientes servicios:

Firestore Database

Authentication (correo electrónico y Google)

Storage

a) Descargar los archivos de configuración

Desde Firebase Console:

Android: google-services.json
→ Guárdalo en:
android/app/google-services.json

iOS: GoogleService-Info.plist
→ Guárdalo en:
ios/Runner/GoogleService-Info.plist

Estos archivos no están incluidos en el repositorio por motivos de seguridad.

b) Configurar Firebase en el proyecto

Asegúrate de que tu build.gradle (nivel app) tenga:

apply plugin: 'com.google.gms.google-services'


y que en android/build.gradle esté incluido:

classpath 'com.google.gms:google-services:4.4.2'

4. Configuración de la API de Google Maps
a) Crear clave de API

Entra en Google Cloud Console
:

Habilita Maps SDK for Android y Places API.

Crea una API Key restringida a tu paquete y SHA-1.

Copia la clave generada.

b) AndroidManifest.xml

Ubicación:

android/app/src/main/AndroidManifest.xml


Coloca tu clave en el campo indicado:

<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="TU_API_KEY_AQUI" />

c) Flutter (Dart)

Archivo:

lib/pantallas/servicios/seleccionar_tipo_ruta_screen.dart


La constante _PLACES_API_KEY está definida para recibir la key en tiempo de compilación:

static const String _PLACES_API_KEY =
  String.fromEnvironment('PLACES_API_KEY', defaultValue: '');


Puedes inyectarla con:

flutter run --dart-define=PLACES_API_KEY=TU_API_KEY_AQUI

5. Estructura de Firestore

El proyecto utiliza una base de datos NoSQL estructurada en colecciones principales:

Colección	Descripción
usuarios	Datos de autenticación y roles
empresas	Información fiscal de empresas registradas
usuario_empresa	Vínculos entre usuarios y empresas
conductores	Información de conductores
vehiculos	Datos de vehículos asociados
servicios	Solicitudes de transporte
ofertas	Ofertas de conductores por servicio
pagos_comision	Registro y validación del 5 % de comisión
comprobantes_qorinti	Comprobantes emitidos por comisión
calificaciones	Valoraciones entre clientes y conductores

NOTA: Para usar un usuario administrador lo que se debe hacer es ingresar primero con cualquier usuario ya sea google o correo electronico y dentro de la colección manualmente cambiarle el rol a "SUPERADMIN" y luego cuando intente ingresar de nuevo con ese usuario le llevara al home de administrador para realizar todas las funciones de gestión de permisos o autorizaciones como pagos o empresas, etc. 

6. Índices requeridos

Para evitar errores de consultas compuestas en Firestore, crea los siguientes índices desde la pestaña Firestore → Índices:

Colección	Campos indexados	Estado
servicios	estado, idUsuarioSolicitante	Habilitado
servicios	estado, fechaSolicitud	Habilitado
servicios	idConductor, estado, fechaFin	Habilitado
conductores	estadoOperativo, creadoEn	Habilitado
transacciones_conductor	idConductor, creadoEn, fechaFin	Habilitado
empresas	estado, razonSocial	Habilitado
empresa_solicitudes	estado, creadoEn	Habilitado
pagos_comision	estado, idConductor, creadoEn	Habilitado
ofertas	estado, creadoEn	Habilitado
usuario_empresa	idUsuario, creadoEn	Habilitado

Si alguna consulta genera error indicando un índice faltante, Firebase proporcionará un enlace directo para crearlo asi que revisar la consola del visual Studio Code o cualquier entorno de desarrollo que usen.

7. Configuración de Reglas de Seguridad

Ejemplo de reglas recomendadas:

service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}

service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}


Ajusta las reglas según tus requerimientos de acceso (por roles o colecciones específicas).

8. Estructura del Proyecto
lib/
 ├── bloc/                   # Gestión de estado (Bloc/Cubit)
 ├── modelos/                # Modelos de datos
 ├── pantallas/              # Interfaz y lógica de presentación
 │    ├── auth/              # Login y registro
 │    ├── empresa/           # Gestión de empresas
 │    ├── conductor/         # Registro y pagos
 │    ├── servicios/         # Módulos de servicios, viajes y comprobantes
 │    └── home/              # Panel principal
 ├── repos/                  # Repositorios de datos (Firebase)
 └── main.dart               # Punto de entrada de la app

9. Ejecución del Proyecto
Android
flutter run

Web (modo desarrollo)
flutter run -d chrome


Para entornos de producción, se recomienda compilar con variables --dart-define para la clave de Google y Firebase configurados por entorno.

10. Créditos del Proyecto
Rol	Integrante
Scrum Manager	Marko Alexander Naveda Samamé
Desarrollador Principal	Anthony Martin Chavez Zegarra
Institución	Universidad Privada San Juan Bautista
Proyecto académico	Aplicación móvil para optimizar el proceso de gestión de transporte en la empresa Transportes Qorinti S.A.C.
11. Licencia

Este proyecto fue desarrollado con fines académicos y empresariales para Transportes Qorinti S.A.C.
Queda prohibida la distribución con fines comerciales sin autorización previa del autor.