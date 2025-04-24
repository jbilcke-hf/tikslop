// lib/main.dart
import 'package:aitube2/config/config.dart';
import 'package:aitube2/services/settings_service.dart';
import 'package:aitube2/services/websocket_api_service.dart';
import 'package:aitube2/theme/colors.dart';
import 'package:aitube2/widgets/maintenance_screen.dart';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Configuration.instance.initialize();

  Widget homeWidget = const HomeScreen();
  Exception? connectionError;

  try {
    // Initialize services in sequence to ensure proper dependencies
    await SettingsService().initialize();
    await CacheService().initialize();
    
    // Initialize the WebSocket service
    final wsService = WebSocketApiService();
    await wsService.initialize();
    
    // Check the current status
    if (wsService.status == ConnectionStatus.maintenance || wsService.isInMaintenance) {
      homeWidget = const MaintenanceScreen(error: null);
    }
    
    // Listen to connection status changes 
    wsService.statusStream.listen((status) {
      if (status == ConnectionStatus.maintenance) {
        // Force update to maintenance screen if server goes into maintenance mode later
        runApp(AiTubeApp(home: const MaintenanceScreen(error: null)));
      }
    });
    
  } catch (e) {
    debugPrint('Error initializing services: $e');
    connectionError = e is Exception ? e : Exception('$e');
    
    // If the error message contains maintenance, show the maintenance screen
    if (e.toString().toLowerCase().contains('maintenance')) {
      homeWidget = const MaintenanceScreen(error: null);
    } else {
      homeWidget = MaintenanceScreen(error: connectionError);
    }
  }

  runApp(AiTubeApp(home: homeWidget));
}

class AiTubeApp extends StatelessWidget {
  final Widget home;
  
  const AiTubeApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Configuration.instance.uiProductName,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          surface: AiTubeColors.surface,
          surfaceContainerHighest: AiTubeColors.surfaceVariant,
          primary: AiTubeColors.primary,
          onSurface: AiTubeColors.onSurface,
          onSurfaceVariant: AiTubeColors.onSurfaceVariant,
        ),
        scaffoldBackgroundColor: AiTubeColors.background,
        cardTheme: CardThemeData(
          color: AiTubeColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AiTubeColors.background,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: AiTubeColors.onBackground),
          titleMedium: TextStyle(color: AiTubeColors.onBackground),
          bodyLarge: TextStyle(color: AiTubeColors.onSurface),
          bodyMedium: TextStyle(color: AiTubeColors.onSurfaceVariant),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          surface: AiTubeColors.surface,
          surfaceContainerHighest: AiTubeColors.surfaceVariant,
          primary: AiTubeColors.primary,
          onSurface: AiTubeColors.onSurface,
          onSurfaceVariant: AiTubeColors.onSurfaceVariant,
        ),
        scaffoldBackgroundColor: AiTubeColors.background,
        cardTheme: CardThemeData(
          color: AiTubeColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AiTubeColors.background,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: AiTubeColors.onBackground),
          titleMedium: TextStyle(color: AiTubeColors.onBackground),
          bodyLarge: TextStyle(color: AiTubeColors.onSurface),
          bodyMedium: TextStyle(color: AiTubeColors.onSurfaceVariant),
        ),
      ),
      home: home,
    );
  }
}