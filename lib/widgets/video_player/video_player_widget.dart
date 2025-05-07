// lib/widgets/video_player/video_player_widget.dart

import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:aitube2/config/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:aitube2/models/video_result.dart';
import 'package:aitube2/models/video_orientation.dart';
import 'package:aitube2/theme/colors.dart';

// Import components
import 'playback_controller.dart';
import 'buffer_manager.dart';
import 'ui_components.dart' as ui;

// Conditionally import dart:html for web platform
import '../web_utils.dart' if (dart.library.html) 'dart:html' as html;

// Extension to check if target platform is mobile
extension TargetPlatformExtension on TargetPlatform {
  bool get isMobile => 
      this == TargetPlatform.iOS || 
      this == TargetPlatform.android;
}

/// A widget that plays video clips with buffering and automatic playback
class VideoPlayerWidget extends StatefulWidget {
  /// The video to play
  final VideoResult video;
  
  /// Initial thumbnail URL to show while loading
  final String? initialThumbnailUrl;
  
  /// Whether to autoplay the video
  final bool autoPlay;
  
  /// Border radius of the video player
  final double borderRadius;
  
  /// Callback when video is loaded
  final VoidCallback? onVideoLoaded;

  /// Constructor
  const VideoPlayerWidget({
    super.key,
    required this.video,
    this.initialThumbnailUrl,
    this.autoPlay = true,
    this.borderRadius = 12,
    this.onVideoLoaded,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> with WidgetsBindingObserver {
  /// Playback controller for video playback
  late final PlaybackController _playbackController;
  
  /// Buffer manager for clip buffering
  late final BufferManager _bufferManager;
  
  /// Whether the widget is disposed
  bool _isDisposed = false;
  
  /// Whether playback was happening before going to background
  bool _wasPlayingBeforeBackground = false;
  
  /// Current orientation
  VideoOrientation _currentOrientation = VideoOrientation.LANDSCAPE;

  @override
  void initState() {
    super.initState();
    
    // Register as an observer to detect app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    
    // Add web-specific visibility change listener
    if (kIsWeb) {
      try {
        // Add document visibility change listener
        html.document.onVisibilityChange.listen((_) {
          _handleVisibilityChange();
        });
        
        // Add before unload listener
        html.window.onBeforeUnload.listen((_) {
          // Pause video when navigating away from the page
          _pauseVideo();
        });
      } catch (e) {
        debugPrint('Error setting up web visibility listeners: $e');
      }
    }
    
    _initializePlayer();
  }
  
  void _handleVisibilityChange() {
    if (!kIsWeb) return;
    
    try {
      final visibilityState = html.window.document.visibilityState;
      if (visibilityState == 'hidden') {
        _pauseVideo();
      } else if (visibilityState == 'visible' && _wasPlayingBeforeBackground) {
        _resumeVideo();
      }
    } catch (e) {
      debugPrint('Error handling visibility change: $e');
    }
  }
  
  void _pauseVideo() {
    if (_playbackController.isPlaying) {
      _wasPlayingBeforeBackground = true;
      _togglePlayback();
    }
  }
  
  void _resumeVideo() {
    if (!_playbackController.isPlaying && _wasPlayingBeforeBackground) {
      _wasPlayingBeforeBackground = false;
      _togglePlayback();
    }
  }

  Future<void> _initializePlayer() async {
    if (_isDisposed) return;
    
    // Get initial orientation
    final mediaQuery = MediaQuery.of(context);
    _currentOrientation = mediaQuery.orientation == Orientation.landscape
        ? VideoOrientation.LANDSCAPE
        : VideoOrientation.PORTRAIT;
    
    _playbackController = PlaybackController();
    _playbackController.isLoading = true;
    _playbackController.isInitialLoad = true;
    _playbackController.onVideoCompleted = _onVideoCompleted;
    
    if (_playbackController.isInitialLoad) {
      _bufferManager = BufferManager(
        video: widget.video,
        onQueueUpdated: () {
          // Prevent setState after disposal
          if (!_isDisposed && mounted) {
            setState(() {});
            // Check buffer status whenever queue updates
            _checkBufferAndStartPlayback();
          }
        },
      );
      
      // Initialize buffer manager with current orientation
      await _bufferManager.initialize();
    }
    
    if (!_isDisposed && mounted) {
      setState(() {
        _playbackController.isLoading = true;
      });
    }
  }

  void _checkBufferAndStartPlayback() {
    if (_isDisposed || _playbackController.startedInitialPlayback) return;

    try {
      if (_bufferManager.isBufferReadyToStartPlayback()) {
        _playbackController.startedInitialPlayback = true;
        _startInitialPlayback();
      } else {
        // Schedule another check
        if (!_isDisposed) {
          Future.delayed(const Duration(milliseconds: 50), _checkBufferAndStartPlayback);
        }
      }
    } catch (e) {
      debugPrint('Error checking buffer status: $e');
      // Don't reschedule if there was an error to prevent infinite error loops
    }
  }

  Future<void> _startInitialPlayback() async {
    if (_isDisposed) return;
    
    final nextClip = _bufferManager.queueManager.currentClip;
    if (nextClip?.isReady == true && !nextClip!.isPlaying) {
      _bufferManager.queueManager.startPlayingClip(nextClip);
      await _playClip(nextClip);
    }
    
    if (!_isDisposed && mounted) {
      setState(() {
        _playbackController.isLoading = false;
        _playbackController.isInitialLoad = false;
      });
    }
  }

  void _togglePlayback() {
    _playbackController.togglePlayback();
    if (!_isDisposed && mounted) {
      setState(() {});
    }
  }

  Future<void> _playClip(dynamic clip) async {
    if (_isDisposed || clip.base64Data == null) return;

    try {
      VideoPlayerController? newController;
      
      if (_playbackController.nextController != null) {
        debugPrint('Using preloaded controller for clip ${clip.seed}');
        newController = _playbackController.nextController;
        _playbackController.nextController = null;
      } else {
        debugPrint('Creating new controller for clip ${clip.seed}');
        newController = VideoPlayerController.networkUrl(
          Uri.parse(clip.base64Data!),
        );
        await newController.initialize();
      }

      if (_isDisposed || newController == null) {
        newController?.dispose();
        return;
      }

      newController.setLooping(true);
      newController.setVolume(0.0);
      newController.setPlaybackSpeed(Configuration.instance.clipPlaybackSpeed);

      final oldController = _playbackController.currentController;
      final oldClip = _playbackController.currentClip;

      _bufferManager.queueManager.startPlayingClip(clip);
      _playbackController.currentPlaybackPosition = Duration.zero; // Reset for new clip

      if (!_isDisposed && mounted) {
        setState(() {
          _playbackController.currentController = newController;
          _playbackController.currentClip = clip;
          _playbackController.isPlaying = widget.autoPlay;
        });
      }

      if (widget.autoPlay) {
        await newController.play();
        debugPrint('Started playback of clip ${clip.seed}');
        _playbackController.startPlaybackTimer();
      }

      await oldController?.dispose();
      if (oldClip != null && oldClip != clip) {
        _bufferManager.queueManager.markCurrentClipAsPlayed();
      }

      widget.onVideoLoaded?.call();
      await _preloadNextClip();
      _bufferManager.ensureBufferFull();

    } catch (e) {
      debugPrint('Error playing clip: $e');
      if (!_isDisposed) {
        if (!_isDisposed && mounted) {
        setState(() => _playbackController.isLoading = true);
      }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  Future<void> _onVideoCompleted() async {
    if (_isDisposed) return;

    // debugPrint('\nHandling video completion');
    _playbackController.playbackTimer?.cancel();  // Cancel current playback timer
    
    // Get next clip before cleaning up current
    final nextClip = _bufferManager.queueManager.nextReadyClip;
    if (nextClip == null) {
      // Reset current clip
      _playbackController.currentController?.seekTo(Duration.zero);
      _playbackController.startPlaybackTimer();  // Restart playback timer
      return;
    }

    // Mark current as played and move to history
    if (_playbackController.currentClip != null) {
      _bufferManager.queueManager.markCurrentClipAsPlayed();
      _playbackController.currentClip = null;
    }

    // Important: Mark the next clip as playing BEFORE transitioning the video
    _bufferManager.queueManager.startPlayingClip(nextClip);

    // Transition to next clip
    if (_playbackController.nextController != null) {
      final oldController = _playbackController.currentController;
      if (!_isDisposed && mounted) {
        setState(() {
          _playbackController.currentController = _playbackController.nextController;
          _playbackController.nextController = null;
          _playbackController.currentClip = nextClip;
          _playbackController.isPlaying = true;
        });
      }

      await _playbackController.currentController?.play();
      _playbackController.startPlaybackTimer();  // Start timer for new clip
      await oldController?.dispose();
      
      // Start preloading next
      await _preloadNextClip();
      
    } else {
      await _playClip(nextClip);
    }
  }

  Future<void> _preloadNextClip() async {
    try {
      final nextController = await _bufferManager.preloadNextClip();
      if (!_isDisposed && nextController != null) {
        // Dispose any existing preloaded controller first
        await _playbackController.nextController?.dispose();
        _playbackController.nextController = nextController;
      }
    } catch (e) {
      debugPrint('Error in preloadNextClip: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Handle app lifecycle changes for native platforms
    if (!kIsWeb) {
      if (state == AppLifecycleState.paused || 
          state == AppLifecycleState.inactive || 
          state == AppLifecycleState.detached) {
        _pauseVideo();
      } else if (state == AppLifecycleState.resumed && _wasPlayingBeforeBackground) {
        _resumeVideo();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    
    // Unregister the observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Dispose controllers and timers
    _playbackController.dispose();
    _bufferManager.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine orientation based on form factor rather than device orientation
        // This ensures proper behavior on desktop platforms
        VideoOrientation newOrientation;
        
        if (kIsWeb || !defaultTargetPlatform.isMobile) {
          // For web and desktop platforms, use form factor (width vs height) to determine orientation
          newOrientation = constraints.maxWidth > constraints.maxHeight 
              ? VideoOrientation.LANDSCAPE 
              : VideoOrientation.PORTRAIT;
          
          // Add a small buffer so we don't change orientation too frequently on borderline cases
          if (newOrientation == VideoOrientation.LANDSCAPE && 
              constraints.maxWidth / constraints.maxHeight < 1.05) {
            newOrientation = _currentOrientation;
          } else if (newOrientation == VideoOrientation.PORTRAIT &&
              constraints.maxHeight / constraints.maxWidth < 1.05) {
            newOrientation = _currentOrientation;
          }
        } else {
          // For mobile platforms, use the device orientation
          final orientation = MediaQuery.of(context).orientation;
          newOrientation = orientation == Orientation.landscape
              ? VideoOrientation.LANDSCAPE
              : VideoOrientation.PORTRAIT;
        }
        
        // Check if orientation changed
        if (newOrientation != _currentOrientation) {
          debugPrint('Orientation changed to ${newOrientation.name} (form factor: ${constraints.maxWidth}x${constraints.maxHeight})');
          _currentOrientation = newOrientation;
          
          // Update buffer manager orientation (without awaiting to avoid blocking UI)
          Future.microtask(() async {
            if (!_isDisposed && mounted) {
              await _bufferManager.updateOrientation(newOrientation);
            }
          });
        }
        
        // Video player layout
        final controller = _playbackController.currentController;
        final aspectRatio = controller?.value.aspectRatio ?? 16/9;
        final playerHeight = constraints.maxWidth / aspectRatio;

        return SizedBox(
          width: constraints.maxWidth,
          height: playerHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Base layer: Placeholder or Video
              ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: Container(
                  color: AiTubeColors.surfaceVariant,
                  child: controller?.value.isInitialized ?? false
                      ? VideoPlayer(controller!)
                      : ui.buildPlaceholder(widget.initialThumbnailUrl),
                ),
              ),

              // Play/Pause button overlay
              if (controller?.value.isInitialized ?? false)
                ui.buildPlayPauseButton(
                  isPlaying: _playbackController.isPlaying,
                  onTap: _togglePlayback,
                ),

              // Buffer status
              ui.buildBufferStatus(
                showDuringLoading: true,
                isLoading: _playbackController.isLoading,
                clipBuffer: _bufferManager.queueManager.clipBuffer,
              ),
            ],
          ),
        );
      },
    );
  }
}