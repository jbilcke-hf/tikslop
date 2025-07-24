// lib/screens/video_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:tikslop/screens/home_screen.dart';
import 'package:tikslop/widgets/chat_widget.dart';
import 'package:tikslop/widgets/search_box.dart';
import 'package:tikslop/widgets/web_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _settingsService = SettingsService();
  bool _isConnected = false;
  late VideoResult _videoData;
  final _searchController = TextEditingController();
  bool _isSearching = false;

  // Subscription for limit statuses
  StreamSubscription? _anonLimitSubscription;
  StreamSubscription? _deviceLimitSubscription;
  
  // Reference to access video player's buffer manager for simulation updates
  StreamSubscription? _videoUpdateSubscription;

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
                    _initializeConnection();
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

  void _shareVideo() async {

    // For non-web platforms
    final uri = Uri.parse("https://tikslop.com");
    final params = Map<String, String>.from(uri.queryParameters);
    
    // Ensure title and description are in the URL parameters
    params['title'] = _videoData.title;
    params['description'] = _videoData.description;
    
    // Create a new URL with updated parameters
    final shareUri = uri.replace(queryParameters: params);
    final shareUrl = shareUri.toString();


    try {
      // this is a text to share on social media
      // final textToCopy = 'Messing around with #tikslop 👀 $shareUrl';
      
      // but for now let's just use the url
      final textToCopy = shareUrl;
      
      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: textToCopy));
      
      // Show a temporary "Copied!" message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error copying to clipboard: $e')),
        );
      }
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
      // We'll update title and description parameters after we get the search result
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
          // Update title and description parameters
          updateUrlParameter('title', result.title);
          updateUrlParameter('description', result.description);
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
                    ? const Icon(Icons.arrow_back, color: TikSlopColors.onBackground)
                    : const Icon(Icons.home, color: TikSlopColors.onBackground),
                  onPressed: () {
                    // Restore the search parameter in URL when navigating back
                    if (kIsWeb) {
                      // Remove the title and description parameters
                      removeUrlParameter('title');
                      removeUrlParameter('description');
                      
                      // Get the search query from the video description
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
                      if (Configuration.instance.showChatInVideoView && _settingsService.enableSimulation) ...[
                        const SizedBox(width: 16),
                        Padding(
                          padding: const EdgeInsets.only(left: 0, top: 16, right: 16, bottom: 4),
                          child: ChatWidget(videoId: widget.video.id),
                        ),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _buildMainContent(),
                      ),
                      if (Configuration.instance.showChatInVideoView && _settingsService.enableSimulation) ...[
                        const SizedBox(height: 16),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16
                            ),
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
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video Player with unique key to force recreation when needed
            VideoPlayerWidget(
              key: _videoPlayerKey,
              video: _videoData,
              initialThumbnailUrl: _videoData.thumbnailUrl,
              autoPlay: true,
              onVideoUpdated: (updatedVideo) {
                debugPrint('VIDEO_SCREEN: Received updated video data');
                if (updatedVideo.evolvedDescription.isNotEmpty) {
                  debugPrint('VIDEO_SCREEN: Evolved description (${updatedVideo.evolvedDescription.length} chars)');
                  debugPrint('VIDEO_SCREEN: First 100 chars: ${updatedVideo.evolvedDescription.substring(0, math.min(100, updatedVideo.evolvedDescription.length))}...');
                } else {
                  debugPrint('VIDEO_SCREEN: No evolved description received');
                }
                
                setState(() {
                  _videoData = updatedVideo;
                });
              },
            ),
            const SizedBox(height: 16),

            // Collapsible Title and Description Section
            _buildCollapsibleInfoSection(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCollapsibleInfoSection() {
    // Get settings service to check if debug info should be shown
    final settingsService = SettingsService();
    final showDebugInfo = settingsService.showSceneDebugInfo;
    
    return ExpansionTile(
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      title: Row(
        children: [
          Expanded(
            child: Text(
              _videoData.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: TikSlopColors.onBackground,
                fontWeight: FontWeight.bold,
                fontSize: 18
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share, color: TikSlopColors.primary),
            onPressed: _shareVideo,
            tooltip: 'Share this creation',
          ),
        ],
      ),
      iconColor: TikSlopColors.primary,
      collapsedIconColor: TikSlopColors.primary,
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Regular Description Section
            if (!showDebugInfo) ...[
              const SizedBox(height: 8),
              Text(
                _videoData.description,
                style: const TextStyle(
                  color: TikSlopColors.onSurface,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
            ],
            
            // Debug Information (when enabled)
            if (showDebugInfo) ...[
              const SizedBox(height: 16),
              const Text(
                'Initial Description:',
                style: TextStyle(
                  color: TikSlopColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _videoData.description,
                style: const TextStyle(
                  color: TikSlopColors.onSurface,
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              
              // Current Description (Evolved Description) Section
              const Text(
                'Current Description:',
                style: TextStyle(
                  color: TikSlopColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _videoData.evolvedDescription.isNotEmpty
                    ? _videoData.evolvedDescription
                    : _videoData.description, // If evolved description is empty, show initial
                style: const TextStyle(
                  color: TikSlopColors.onSurface,
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              
              // Condensed History (Last Description) Section
              const Text(
                'Last Description:',
                style: TextStyle(
                  color: TikSlopColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _videoData.condensedHistory.isNotEmpty
                    ? _videoData.condensedHistory
                    : "No history available yet", // Show message if no history
                style: const TextStyle(
                  color: TikSlopColors.onSurface,
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
            ],
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