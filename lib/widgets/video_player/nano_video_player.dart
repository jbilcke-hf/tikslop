// lib/widgets/video_player/nano_video_player.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import 'package:tikslop/models/video_result.dart';
import 'package:tikslop/theme/colors.dart';
import 'package:tikslop/widgets/video_player/nano_clip_manager.dart';
import 'package:tikslop/widgets/video_player/lifecycle_manager.dart';
import 'package:tikslop/widgets/ai_content_disclaimer.dart';

// Conditionally import dart:html for web platform
import '../web_utils.dart' if (dart.library.html) 'dart:html' as html;

/// A lightweight video player for thumbnails with autoplay functionality
class NanoVideoPlayer extends StatefulWidget {
  /// The video to display
  final VideoResult video;
  
  /// Initial thumbnail URL to show while loading
  final String? initialThumbnailUrl;
  
  /// Whether to autoplay the video
  final bool autoPlay;
  
  /// Whether to mute the video
  final bool muted;
  
  /// Border radius of the player
  final double borderRadius;
  
  /// Playback speed
  final double playbackSpeed;
  
  /// Callback when video is tapped
  final VoidCallback? onTap;
  
  /// Callback when video is loaded
  final VoidCallback? onLoaded;
  
  /// Whether to show loading indicator
  final bool showLoadingIndicator;
  
  /// Whether to loop the video
  final bool loop;
  
  /// Constructor with sensible defaults for thumbnail usage
  const NanoVideoPlayer({
    super.key,
    required this.video,
    this.initialThumbnailUrl,
    this.autoPlay = true,
    this.muted = true,
    this.borderRadius = 8.0,
    this.playbackSpeed = 0.7,
    this.onTap,
    this.onLoaded,
    this.showLoadingIndicator = true,
    this.loop = true,
  });

  @override
  State<NanoVideoPlayer> createState() => _NanoVideoPlayerState();
}

class _NanoVideoPlayerState extends State<NanoVideoPlayer> with WidgetsBindingObserver, VideoPlayerLifecycleMixin {
  /// Clip manager for the nano video
  late final NanoClipManager _clipManager;
  
  /// Video player controller
  VideoPlayerController? _controller;
  
  /// Whether the video is playing
  bool _isPlaying = false;
  
  /// Whether the video is loading
  bool _isLoading = true;
  
  /// Whether the component is disposed
  bool _isDisposed = false;
  
  /// Implements the isPlaying getter required by the mixin
  @override
  bool get isPlaying => _isPlaying;
  
  /// Implements the isPlaying setter required by the mixin
  @override
  set isPlaying(bool value) {
    if (_isDisposed) return;
    setState(() {
      _isPlaying = value;
    });
  }
  
  @override
  void initState() {
    // Initialize the manager
    _clipManager = NanoClipManager(
      video: widget.video,
      onClipUpdated: _onClipUpdated,
    );
    
    _initialize();
    
    // Call super after setting up variables that the mixin needs
    super.initState();
  }
  
  /// Initialize the player and start clip generation
  Future<void> _initialize() async {
    if (_isDisposed) return;
    
    setState(() {
      _isLoading = true;
    });
    
    // Start generating the clip
    await _clipManager.initialize();
    
    // Set up the video controller if clip is ready
    if (_clipManager.videoClip?.isReady == true && _clipManager.videoClip?.base64Data != null) {
      await _setupController();
    }
  }
  
  /// Set up the video controller with the clip
  Future<void> _setupController() async {
    if (_isDisposed || _clipManager.videoClip?.base64Data == null) return;
    
    try {
      final clip = _clipManager.videoClip!;
      
      // Dispose previous controller if exists
      await _controller?.dispose();
      
      // Create new controller
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(clip.base64Data!),
      );
      
      await _controller!.initialize();
      
      if (_isDisposed) {
        await _controller?.dispose();
        return;
      }
      
      // Configure the controller
      _controller!.setLooping(widget.loop);
      _controller!.setVolume(widget.muted ? 0.0 : 1.0);
      _controller!.setPlaybackSpeed(widget.playbackSpeed);
      
      setState(() {
        _isLoading = false;
        _isPlaying = widget.autoPlay;
      });
      
      if (widget.autoPlay) {
        await _controller!.play();
      }
      
      widget.onLoaded?.call();
      
    } catch (e) {
      debugPrint('Error setting up nano video controller: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// Callback when clip is updated
  void _onClipUpdated() {
    if (_isDisposed) return;
    
    setState(() {});
    
    if (_clipManager.videoClip?.isReady == true && _controller == null) {
      _setupController();
    }
  }
  
  /// Toggle playback
  @override
  void togglePlayback() {
    if (_isLoading || _controller == null) return;
    
    setState(() {
      _isPlaying = !_isPlaying;
    });
    
    if (_isPlaying) {
      _controller!.play();
    } else {
      _controller!.pause();
    }
  }
  
  /// Set up web visibility listeners
  @override
  void setupWebVisibilityListeners() {
    if (kIsWeb) {
      try {
        html.document.onVisibilityChange.listen((_) {
          handleVisibilityChange();
        });
      } catch (e) {
        debugPrint('Error setting up web visibility listeners: $e');
      }
    }
  }
  
  /// Handle visibility changes
  @override
  void handleVisibilityChange() {
    if (!kIsWeb) return;
    
    try {
      final visibilityState = html.window.document.visibilityState;
      if (visibilityState == 'hidden') {
        pauseVideo();
      } else if (visibilityState == 'visible') {
        resumeVideo();
      }
    } catch (e) {
      debugPrint('Error handling visibility change: $e');
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    _controller?.dispose();
    _clipManager.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // Base layer: Video or placeholder
            Container(
              color: TikSlopColors.surfaceVariant,
              child: _controller?.value.isInitialized == true
                ? AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  )
                : _buildPlaceholder(),
            ),
            
            // Loading indicator
            if (_isLoading && widget.showLoadingIndicator)
              const Center(
                child: CircularProgressIndicator(),
              ),
              
            // Status text overlay for debugging
            if (_clipManager.statusText.isNotEmpty && _controller?.value.isInitialized != true)
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _clipManager.statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  /// Build placeholder widget
  Widget _buildPlaceholder() {
    if (widget.initialThumbnailUrl?.isNotEmpty == true) {
      try {
        if (widget.initialThumbnailUrl!.startsWith('data:image')) {
          final uri = Uri.parse(widget.initialThumbnailUrl!);
          final base64Data = uri.data?.contentAsBytes();
          
          if (base64Data == null) {
            throw Exception('Invalid image data');
          }
          
          return Image.memory(
            base64Data,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackPlaceholder(),
          );
        }
        
        return Image.network(
          widget.initialThumbnailUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackPlaceholder(),
        );
      } catch (e) {
        return _buildFallbackPlaceholder();
      }
    } else {
      return _buildFallbackPlaceholder();
    }
  }
  
  /// Build fallback placeholder when image fails to load
  Widget _buildFallbackPlaceholder() {
    return const Center(
      child: AiContentDisclaimer(
        isInteractive: true,
        compact: true,
      ),
    );
  }
}