import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_router.dart';
import 'repos/servicio_repository.dart';
import 'repos/finanzas_repository.dart'; 
import 'bloc/servicio/servicio_bloc.dart';

/// Punto de inicio de la aplicación Qorinti.
/// Inicializa Firebase, define el manejo global de errores y ejecuta la aplicación dentro de un entorno protegido.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    Zone.current.handleUncaughtError(details.exception, details.stack!);
  };

  try {
    await Firebase.initializeApp();
    await FirebaseAuth.instance.setLanguageCode('es');

    /// Activación de Firebase App Check para reforzar la seguridad de acceso.
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
      appleProvider: AppleProvider.appAttest,
    );
  } catch (e, st) {
    debugPrint("Error inicializando Firebase: $e\n$st");
  }

  /// Ejecución de la aplicación dentro de una zona segura con manejo de errores global.
  runZonedGuarded(
    () => runApp(const QorintiApp()),
    (error, stack) {
      debugPrint("Error no controlado: $error\n$stack");
    },
  );
}

/// Clase principal de la aplicación.
/// Configura los repositorios, la gestión de estados mediante BLoC y las rutas del sistema.
class QorintiApp extends StatelessWidget {
  const QorintiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      /// Registro global de repositorios y BLoCs utilizados en la aplicación.
      providers: [
        RepositoryProvider(create: (_) => ServicioRepository()),
        RepositoryProvider(create: (_) => FinanzasRepository()), 
        BlocProvider(create: (ctx) => ServicioBloc(ctx.read<ServicioRepository>())),
      ],

      /// Configuración base del MaterialApp, incluyendo rutas, temas y soporte multilenguaje.
      child: MaterialApp(
        title: 'Qorinti',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        initialRoute: AppRouter.auth,
        onGenerateRoute: AppRouter.onGenerateRoute,
        onUnknownRoute: AppRouter.onUnknownRoute,
        navigatorKey: AppRouter.navigatorKey,                
        navigatorObservers: [AppRouter.routeObserver],        
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('es', ''),
          Locale('en', ''),
        ],
      ),
    );
  }

  /// Construcción del tema visual principal de la aplicación.
  /// Define colores, tipografías, estilos de botones, campos de texto y componentes visuales comunes.
  ThemeData _buildTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6), 
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7FAFC),

      /// Estilo del AppBar: diseño limpio con título centrado y sin elevación.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),

      /// Configuración global de tipografía.
      textTheme: Typography.blackCupertino.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),

      /// Estilo de tarjetas y componentes contenedores.
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      /// Estilos visuales de botones (Filled, Elevated, Outlined).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      /// Personalización de campos de texto para formularios.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceVariant.withOpacity(0.35),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),

      /// Configuración de divisores, navegación, pestañas, chips, notificaciones y diálogos.
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 24,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: MaterialStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight:
                states.contains(MaterialState.selected) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceVariant.withOpacity(0.4),
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
