// lib/main.dart
import 'package:tikslop/config/config.dart';
import 'package:tikslop/models/video_result.dart';
import 'package:tikslop/screens/video_screen.dart';
import 'package:tikslop/services/settings_service.dart';
import 'package:tikslop/services/websocket_api_service.dart';
import 'package:tikslop/theme/colors.dart';
import 'package:tikslop/widgets/maintenance_screen.dart';
import 'package:tikslop/widgets/web_utils.dart';
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
      // Handle title parameter
      else if (params.containsKey('title')) {
        final titleQuery = params['title'] ?? '';
        
        if (titleQuery.isNotEmpty) {
          // If both title and description are provided, create video directly
          if (params.containsKey('description')) {
            final description = params['description'] ?? '';
            final videoResult = VideoResult(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: titleQuery,
              description: description,
              thumbnailUrl: '',
              tags: [],
            );
            homeWidget = VideoScreen(video: videoResult);
          } else {
            // If only title is provided, use search like before (same as legacy 'view' parameter)
            homeWidget = FutureBuilder<VideoResult>(
              future: wsService.search(titleQuery),
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
    }
    
    // Listen to connection status changes 
    wsService.statusStream.listen((status) {
      if (status == ConnectionStatus.maintenance) {
        // Force update to maintenance screen if server goes into maintenance mode later
        runApp(const TikSlopApp(home: MaintenanceScreen(error: null)));
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

  runApp(TikSlopApp(home: homeWidget));
}

class TikSlopApp extends StatelessWidget {
  final Widget home;
  
  const TikSlopApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Configuration.instance.uiProductName,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          surface: TikSlopColors.surface,
          surfaceContainerHighest: TikSlopColors.surfaceVariant,
          primary: TikSlopColors.primary,
          onSurface: TikSlopColors.onSurface,
          onSurfaceVariant: TikSlopColors.onSurfaceVariant,
        ),
        scaffoldBackgroundColor: TikSlopColors.background,
        cardTheme: CardThemeData(
          color: TikSlopColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: TikSlopColors.background,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: TikSlopColors.onBackground),
          titleMedium: TextStyle(color: TikSlopColors.onBackground),
          bodyLarge: TextStyle(color: TikSlopColors.onSurface),
          bodyMedium: TextStyle(color: TikSlopColors.onSurfaceVariant),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          surface: TikSlopColors.surface,
          surfaceContainerHighest: TikSlopColors.surfaceVariant,
          primary: TikSlopColors.primary,
          onSurface: TikSlopColors.onSurface,
          onSurfaceVariant: TikSlopColors.onSurfaceVariant,
        ),
        scaffoldBackgroundColor: TikSlopColors.background,
        cardTheme: CardThemeData(
          color: TikSlopColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: TikSlopColors.background,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: TikSlopColors.onBackground),
          titleMedium: TextStyle(color: TikSlopColors.onBackground),
          bodyLarge: TextStyle(color: TikSlopColors.onSurface),
          bodyMedium: TextStyle(color: TikSlopColors.onSurfaceVariant),
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