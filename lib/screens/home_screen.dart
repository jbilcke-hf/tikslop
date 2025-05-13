// lib/screens/home_screen.dart
import 'dart:async';
import 'package:tikslop/config/config.dart';
import 'package:tikslop/widgets/web_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:tikslop/screens/video_screen.dart';
import 'package:tikslop/screens/settings_screen.dart';
import 'package:tikslop/models/video_result.dart';
import 'package:tikslop/services/websocket_api_service.dart';
import 'package:tikslop/services/settings_service.dart';
import 'package:tikslop/widgets/video_card.dart';
import 'package:tikslop/widgets/search_box.dart';
import 'package:tikslop/theme/colors.dart';

class HomeScreen extends StatefulWidget {
  final String? initialSearchQuery;
  
  const HomeScreen({
    super.key,
    this.initialSearchQuery,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _websocketService = WebSocketApiService();
  List<VideoResult> _results = [];
  bool _isSearching = false;
  String? _currentSearchQuery;
  StreamSubscription? _searchSubscription;
  static const int maxResults = 4;

  // Subscription for limit status
  StreamSubscription? _anonLimitSubscription;
  StreamSubscription? _deviceLimitSubscription;

  @override
  void initState() {
    super.initState();
    
    // Listen for changes to anonymous limit status
    _anonLimitSubscription = _websocketService.anonLimitStream.listen((exceeded) {
      if (exceeded && mounted) {
        _showAnonLimitExceededDialog();
      }
    });
    
    // Listen for changes to device limit status (for VIP users on web)
    _deviceLimitSubscription = _websocketService.deviceLimitStream.listen((exceeded) {
      if (exceeded && mounted) {
        _showDeviceLimitExceededDialog();
      }
    });
    
    _initializeWebSocket();
    _setupSearchListener();
    
    // Force a UI refresh to ensure connection status is displayed correctly
    Future.microtask(() {
      if (mounted) {
        setState(() {});  // Trigger a rebuild to refresh the connection status
      }
    });
    
    // Check if we have an initial search query from URL parameters
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!;
      // Need to use Future.delayed to ensure WebSocket is initialized
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _search(widget.initialSearchQuery!);
        }
      });
    }
  }

  void _setupSearchListener() {
    _searchSubscription = _websocketService.searchStream.listen((result) {
      if (mounted) {
        setState(() {
          if (_results.length < maxResults) {
            _results.add(result);
            // Stop search if we've reached max results
            if (_results.length >= maxResults) {
              _stopSearch();
            }
          }
        });
      }
    });
  }

  void _stopSearch() {
    if (_currentSearchQuery != null) {
      _websocketService.stopContinuousSearch(_currentSearchQuery!);
      setState(() {
        _isSearching = false;
        _currentSearchQuery = null;
      });
    }
  }

  Future<void> _initializeWebSocket() async {
    try {
      await _websocketService.connect();
      
      // Check if anonymous limit is exceeded
      if (_websocketService.isAnonLimitExceeded) {
        if (mounted) {
          _showAnonLimitExceededDialog();
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to server: $e'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _initializeWebSocket,
            ),
          ),
        );
      }
    }
  }
  
  void _showAnonLimitExceededDialog() async {
    // Create a controller outside the dialog for easier access
    final TextEditingController controller = TextEditingController();
    
    final settings = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        bool obscureText = true;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Connection Limit Reached',
                style: TextStyle(
                  color: TikSlopColors.onBackground,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _websocketService.anonLimitMessage.isNotEmpty
                      ? _websocketService.anonLimitMessage
                      : 'Anonymous users can enjoy 1 stream per IP address. If you are on a shared IP please enter your HF token, thank you!',
                    style: const TextStyle(color: TikSlopColors.onSurface),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Enter your HuggingFace API token to continue:',
                    style: TextStyle(color: TikSlopColors.onSurface),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    obscureText: obscureText,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      labelStyle: const TextStyle(color: TikSlopColors.onSurfaceVariant),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureText ? Icons.visibility : Icons.visibility_off,
                          color: TikSlopColors.onSurfaceVariant,
                        ),
                        onPressed: () => setState(() => obscureText = !obscureText),
                      ),
                    ),
                    onSubmitted: (value) {
                      Navigator.pop(dialogContext, value);
                    },
                  ),
                ],
              ),
              backgroundColor: TikSlopColors.surface,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: TikSlopColors.onSurfaceVariant),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, controller.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: TikSlopColors.primary,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          }
        );
      },
    );
    
    // Clean up the controller
    controller.dispose();
    
    // If user provided an API key, save it and retry connection
    if (settings != null && settings.isNotEmpty) {
      // Save the API key
      final settingsService = SettingsService();
      await settingsService.setHuggingfaceApiKey(settings);
      
      // Retry connection
      if (mounted) {
        _initializeWebSocket();
      }
    }
  }
  
  void _showDeviceLimitExceededDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(
            'Too Many Connections',
            style: TextStyle(
              color: TikSlopColors.onBackground,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _websocketService.deviceLimitMessage,
                style: const TextStyle(color: TikSlopColors.onSurface),
              ),
              const SizedBox(height: 16),
              const Text(
                'Please close some of your other browser tabs running TikSlop to continue.',
                style: TextStyle(color: TikSlopColors.onSurface),
              ),
            ],
          ),
          backgroundColor: TikSlopColors.surface,
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                
                // Try to reconnect after dialog is closed
                if (mounted) {
                  Future.delayed(const Duration(seconds: 1), () {
                    _initializeWebSocket();
                  });
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: TikSlopColors.primary,
              ),
              child: const Text('Try Again'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConnectionStatus() {
    
    return StreamBuilder<ConnectionStatus>(
      stream: _websocketService.statusStream,
      initialData: _websocketService.status, // Add initial data to avoid null status
      builder: (context, connectionSnapshot) {
        // Immediately extract and use the connection status
        final status = connectionSnapshot.data ?? ConnectionStatus.disconnected;
        
        return StreamBuilder<String>(
          stream: _websocketService.userRoleStream,
          initialData: _websocketService.userRole, // Add initial data
          builder: (context, roleSnapshot) {
            final userRole = roleSnapshot.data ?? 'anon';
            
            final backgroundColor = status == ConnectionStatus.connected || status == ConnectionStatus.connecting
                ? Colors.green.withOpacity(0.1)
                : status == ConnectionStatus.error
                    ? Colors.red.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1);
            
            final textAndIconColor = status == ConnectionStatus.connected || status == ConnectionStatus.connecting
                ? Colors.green
                : status == ConnectionStatus.error
                    ? Colors.red
                    : Colors.orange;

            final icon = status == ConnectionStatus.connected || status == ConnectionStatus.connecting
                ? Icons.cloud_done
                : status == ConnectionStatus.error
                    ? Icons.cloud_off
                    : Icons.cloud_sync;

            // Get the status message (with user role info for connected state)
            String statusMessage = _websocketService.statusMessage;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: textAndIconColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    statusMessage,
                    style: TextStyle(
                      color: textAndIconColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a search query')),
      );
      return;
    }

    // Clear previous results if query is different
    if (_currentSearchQuery != trimmedQuery) {
      setState(() {
        _results.clear();
        _isSearching = true;
      });
    }

    // Stop any existing search
    if (_currentSearchQuery != null) {
      _websocketService.stopContinuousSearch(_currentSearchQuery!);
    }

    // Update URL parameter for web builds
    if (kIsWeb) {
      updateUrlParameter('search', trimmedQuery);
    }

    try {
      // Check connection
      if (!_websocketService.isConnected) {
        await _websocketService.connect();
      }

      _currentSearchQuery = trimmedQuery;

      // Start continuous search
      _websocketService.startContinuousSearch(trimmedQuery);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error performing search: $e')),
        );
        setState(() => _isSearching = false);
      }
    }
  }

  int _getColumnCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1536) { // 2XL
      return 6;
    } else if (width >= 1280) { // XL
      return 5;
    } else if (width >= 1024) { // LG
      return 4;
    } else if (width >= 768) { // MD
      return 3;
    } else {
      return 2; // Default for small screens
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Configuration.instance.uiProductName),
        backgroundColor: TikSlopColors.background,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildConnectionStatus(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _stopSearch(); // Stop search but keep results
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBox(
              controller: _searchController,
              isSearching: _isSearching,
              enabled: _websocketService.isConnected,
              onSearch: _search,
              onCancel: _stopSearch,
            ),
          ),

          // Results Grid
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _isSearching
                          ? 'Hallucinating search results using AI...'
                          : 'Results are generated on demand, videos rendered on the fly.',
                      style: const TextStyle(
                        color: TikSlopColors.onSurfaceVariant,
                        fontSize: 20
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                  : MasonryGridView.count(
                  padding: const EdgeInsets.all(16),
                  crossAxisCount: _getColumnCount(context),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        _stopSearch(); // Stop search but keep results
                        
                        // Update URL parameter on web platform
                        if (kIsWeb) {
                          // Update title and description parameters and remove search parameter
                          updateUrlParameter('title', _results[index].title);
                          updateUrlParameter('description', _results[index].description);
                          removeUrlParameter('search');
                        }
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VideoScreen(
                              video: _results[index],
                            ),
                          ),
                        );
                      },
                      child: VideoCard(video: _results[index]),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchSubscription?.cancel();
    _anonLimitSubscription?.cancel();
    _deviceLimitSubscription?.cancel();
    _searchController.dispose();
    _websocketService.dispose();
    super.dispose();
  }
}