// lib/main.dart
import 'package:aitube2/config/config.dart';
import 'package:aitube2/models/video_result.dart';
import 'package:aitube2/screens/video_screen.dart';
import 'package:aitube2/services/settings_service.dart';
import 'package:aitube2/services/websocket_api_service.dart';
import 'package:aitube2/theme/colors.dart';
import 'package:aitube2/widgets/maintenance_screen.dart';
import 'package:aitube2/widgets/web_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Configuration.instance.initialize();

  Widget homeWidget = const HomeScreen();
  Exception? connectionError;
  final WebSocketApiService wsService = WebSocketApiService();

  try {
    // Initialize services in sequence to ensure proper dependencies
    await SettingsService().initialize();
    
    // Initialize the WebSocket service
    await wsService.initialize();
    
    // Check the current status
    if (wsService.status == ConnectionStatus.maintenance || wsService.isInMaintenance) {
      homeWidget = const MaintenanceScreen(error: null);
    } else if (kIsWeb) {
      // Handle URL query parameters (web only)
      final params = getUrlParameters();
      
      // Handle search parameter
      if (params.containsKey('search')) {
        final searchQuery = params['search'] ?? '';
        if (searchQuery.isNotEmpty) {
          // Pass search query to HomeScreen - it will trigger search on load
          homeWidget = HomeScreen(initialSearchQuery: searchQuery);
        }
      } 
      // Handle view parameter (higher priority than search if both are present)
      else if (params.containsKey('view')) {
        final viewQuery = params['view'] ?? '';
        if (viewQuery.isNotEmpty) {
          // Create a loading widget that will transition to VideoScreen once search completes
          homeWidget = FutureBuilder<VideoResult>(
            future: wsService.search(viewQuery),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                // Navigate to VideoScreen once we have the result
                return VideoScreen(video: snapshot.data!);
              } else if (snapshot.hasError) {
                return Scaffold(
                  body: Center(
                    child: Text('Error loading video: ${snapshot.error}'),
                  ),
                );
              } else {
                // Show loading indicator while waiting
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
            },
          );
        }
      }
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
      // Use custom route handling to support deep linking with URL parameters on web
      onGenerateRoute: (settings) {
        // The home screen is the default fallback
        return MaterialPageRoute(builder: (_) => home);
      },
      home: home,
    );
  }
}