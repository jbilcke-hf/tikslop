// lib/screens/video_screen.dart
import 'package:aitube2/widgets/chat_widget.dart';
import 'package:aitube2/widgets/search_box.dart';
import 'package:flutter/material.dart';
import '../config/config.dart';
import '../models/video_result.dart';
import '../services/websocket_api_service.dart';
import '../services/cache_service.dart';
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
  final _cacheService = CacheService();
  bool _isConnected = false;
  late VideoResult _videoData;
  final _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _videoData = widget.video;
    _searchController.text = _videoData.title;
    _websocketService.addSubscriber(widget.video.id);
    _initializeConnection();
    _loadCachedThumbnail();
  }

  Future<void> _loadCachedThumbnail() async {
    final cachedThumbnail = await _cacheService.getThumbnail(_videoData.id);
    if (cachedThumbnail != null && mounted) {
      setState(() {
        _videoData = _videoData.copyWith(thumbnailUrl: cachedThumbnail);
      });
    }
  }

  Future<void> _initializeConnection() async {
    try {
      await _websocketService.connect();
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
          appBar: AppBar(
            titleSpacing: 0,
            title: Padding(
              padding: const EdgeInsets.only(right: 8),
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
    super.dispose();
  }

}