// lib/screens/video_screen.dart
import 'dart:async';

import 'package:aitube2/screens/home_screen.dart';
import 'package:aitube2/widgets/chat_widget.dart';
import 'package:aitube2/widgets/search_box.dart';
import 'package:aitube2/widgets/web_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/config.dart';
import '../models/video_result.dart';
import '../services/websocket_api_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../widgets/video_player_widget.dart';

class VideoScreen extends StatefulWidget {
  final VideoResult video;

  const VideoScreen({
    super.key,
    required this.video,
  });

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  Future<String>? _captionFuture;
  final _websocketService = WebSocketApiService();
  bool _isConnected = false;
  late VideoResult _videoData;
  final _searchController = TextEditingController();
  bool _isSearching = false;

  // Subscription for limit statuses
  StreamSubscription? _anonLimitSubscription;
  StreamSubscription? _deviceLimitSubscription;

  @override
  void initState() {
    super.initState();
    _videoData = widget.video;
    _searchController.text = _videoData.title;
    _websocketService.addSubscriber(widget.video.id);
    
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
    
    _initializeConnection();
  }

  Future<void> _initializeConnection() async {
    try {
      await _websocketService.connect();
      
      // Check if anonymous limit is exceeded
      if (_websocketService.isAnonLimitExceeded) {
        if (mounted) {
          _showAnonLimitExceededDialog();
        }
        return;
      }
      
      if (mounted) {
        setState(() {
          _isConnected = true;
          _captionFuture = _generateCaption();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnected = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to server: $e'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _initializeConnection,
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
                  color: AiTubeColors.onBackground,
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
                    style: const TextStyle(color: AiTubeColors.onSurface),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Enter your HuggingFace API token to continue:',
                    style: TextStyle(color: AiTubeColors.onSurface),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    obscureText: obscureText,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      labelStyle: const TextStyle(color: AiTubeColors.onSurfaceVariant),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureText ? Icons.visibility : Icons.visibility_off,
                          color: AiTubeColors.onSurfaceVariant,
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
              backgroundColor: AiTubeColors.surface,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AiTubeColors.onSurfaceVariant),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, controller.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: AiTubeColors.primary,
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
        _initializeConnection();
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
              color: AiTubeColors.onBackground,
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
                style: const TextStyle(color: AiTubeColors.onSurface),
              ),
              const SizedBox(height: 16),
              const Text(
                'Please close some of your other browser tabs running AiTube to continue.',
                style: TextStyle(color: AiTubeColors.onSurface),
              ),
            ],
          ),
          backgroundColor: AiTubeColors.surface,
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                
                // Try to reconnect after dialog is closed
                if (mounted) {
                  Future.delayed(const Duration(seconds: 1), () {
                    _initializeConnection();
                  });
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: AiTubeColors.primary,
              ),
              child: const Text('Try Again'),
            ),
          ],
        );
      },
    );
  }

  Future<String> _generateCaption() async {
    if (!_isConnected) {
      return 'Error: Not connected to server';
    }
    
    try {
      return await _websocketService.generateCaption(
        _videoData.title,
        _videoData.description,
      );
    } catch (e) {
      return 'Error generating caption: $e';
    }
  }

  // Reference to the current VideoPlayerWidget to force reset when needed
  Key _videoPlayerKey = UniqueKey();

  Future<void> _onVideoSearch(String query) async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to server')),
      );
      return;
    }

    setState(() => _isSearching = true);
    
    // Update URL parameter on web platform
    if (kIsWeb) {
      // Update view parameter with the description instead of the query
      // We'll get the actual description from the search result
      // removeUrlParameter('search') will happen after we get the result
    }

    try {
      // First, cancel any requests for the current video
      _websocketService.cancelRequestsForVideo(_videoData.id);
      
      // Get the search result
      final result = await _websocketService.search(query);
      
      if (mounted) {
        setState(() {
          // Generate a new key to force recreation of the VideoPlayerWidget
          _videoPlayerKey = UniqueKey();
          _videoData = result;
          _isSearching = false;
        });
        
        // Now that we have the result, update the URL parameter on web platform
        if (kIsWeb) {
          // Update view parameter with the description
          updateUrlParameter('view', result.description);
          removeUrlParameter('search');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 900;
        
        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight + 16),
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AppBar(
                leading: IconButton(
                  icon: Navigator.canPop(context) 
                    ? const Icon(Icons.arrow_back, color: AiTubeColors.onBackground)
                    : const Icon(Icons.home, color: AiTubeColors.onBackground),
                  onPressed: () {
                    // Restore the search parameter in URL when navigating back
                    if (kIsWeb) {
                      // Remove the view parameter
                      removeUrlParameter('view');
                      
                      // Get the search query from the video description
                      // This matches what we stored in the view parameter when
                      // navigating to this screen
                      final searchQuery = _videoData.description.trim();
                      if (searchQuery.isNotEmpty) {
                        // Update URL to show search parameter again
                        updateUrlParameter('search', searchQuery);
                      }
                    }
                    
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      // Navigate to home screen if we can't go back
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const HomeScreen()),
                      );
                    }
                  },
                ),
                titleSpacing: 0,
            title: Padding(
              padding: const EdgeInsets.all(8),
              child: SearchBox(
                controller: _searchController,
                isSearching: _isSearching,
                enabled: _isConnected,
                onSearch: _onVideoSearch,
                onCancel: () {
                  setState(() => _isSearching = false);
                },
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                onPressed: _isConnected ? null : _initializeConnection,
              ),
            ],
              ),
            ),
          ),
          body: SafeArea(
            child: isWideScreen
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildMainContent(),
                      ),
                      if (Configuration.instance.showChatInVideoView) ...[
                        const SizedBox(width: 16),
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: ChatWidget(videoId: widget.video.id),
                        ),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      _buildMainContent(),
                      if (Configuration.instance.showChatInVideoView) ...[
                        const SizedBox(height: 16),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ChatWidget(
                              videoId: widget.video.id,
                              isCompact: true,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video Player with unique key to force recreation when needed
          VideoPlayerWidget(
            key: _videoPlayerKey,
            video: _videoData,
            initialThumbnailUrl: _videoData.thumbnailUrl,
            autoPlay: true,
          ),
          const SizedBox(height: 16),

          // Collapsible Title and Description Section
          _buildCollapsibleInfoSection(),
        ],
      ),
    );
  }
  
  Widget _buildCollapsibleInfoSection() {
    return ExpansionTile(
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      title: Text(
        _videoData.title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: AiTubeColors.onBackground,
          fontWeight: FontWeight.bold,
        ),
      ),
      iconColor: AiTubeColors.primary,
      collapsedIconColor: AiTubeColors.primary,
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tags
            if (_videoData.tags.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _videoData.tags.map((tag) => Chip(
                  label: Text(tag),
                  backgroundColor: AiTubeColors.surface,
                  labelStyle: const TextStyle(color: AiTubeColors.onSurface),
                )).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Description Section
            const Text(
              'Description',
              style: TextStyle(
                color: AiTubeColors.onBackground,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _videoData.description,
              style: const TextStyle(
                color: AiTubeColors.onSurface,
                height: 1.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    // Cancel any pending video-related requests
    _websocketService.cancelRequestsForVideo(widget.video.id);
    _websocketService.removeSubscriber(widget.video.id);
    
    // Cleanup other resources
    _searchController.dispose();
    _anonLimitSubscription?.cancel();
    _deviceLimitSubscription?.cancel();
    super.dispose();
  }

}