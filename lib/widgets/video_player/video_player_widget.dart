// lib/widgets/video_player/video_player_widget.dart

import 'dart:async';
import 'dart:math' as math;
import 'dart:math' show min;
import 'dart:io' show Platform;
import 'package:tikslop/config/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:tikslop/models/video_result.dart';
import 'package:tikslop/models/video_orientation.dart';
import 'package:tikslop/theme/colors.dart';

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
  
  /// Callback when video data is updated (for simulation updates)
  final Function(VideoResult updatedVideo)? onVideoUpdated;

  /// Constructor
  const VideoPlayerWidget({
    super.key,
    required this.video,
    this.initialThumbnailUrl,
    this.autoPlay = true,
    this.borderRadius = 12,
    this.onVideoLoaded,
    this.onVideoUpdated,
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
  
  /// Subscription to video update stream
  StreamSubscription? _videoUpdateSubscription;
  
  /// Current orientation
  VideoOrientation _currentOrientation = VideoOrientation.LANDSCAPE;
  
  /// Last time orientation was changed
  DateTime _lastOrientationChange = DateTime.now();
  
  /// Timer for debouncing orientation changes
  Timer? _orientationDebounceTimer;

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
      
      // Manually pause playback and simulation together
      _playbackController.togglePlayback();
      _bufferManager.queueManager.setSimulationPaused(true);
      
      if (!_isDisposed && mounted) {
        setState(() {});
      }
    }
  }
  
  void _resumeVideo() {
    if (!_playbackController.isPlaying && _wasPlayingBeforeBackground) {
      _wasPlayingBeforeBackground = false;
      
      // Manually resume playback and simulation together
      _playbackController.togglePlayback();
      _bufferManager.queueManager.setSimulationPaused(false);
      
      if (!_isDisposed && mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _initializePlayer() async {
    if (_isDisposed) return;
    
    // Determine initial orientation based on platform
    final mediaQuery = MediaQuery.of(context);
    if (kIsWeb) {
      // For web, use screen dimensions to determine initial orientation
      final screenWidth = mediaQuery.size.width;
      final screenHeight = mediaQuery.size.height;
      final aspectRatio = screenWidth / screenHeight;
      
      // debugPrint('Initial screen size: ${screenWidth.toInt()}x${screenHeight.toInt()}, aspect ratio: ${aspectRatio.toStringAsFixed(2)}');
      
      // Set initial orientation based on aspect ratio
      if (aspectRatio > 1.2) {
        _currentOrientation = VideoOrientation.LANDSCAPE;
      } else if (aspectRatio < 0.8) {
        _currentOrientation = VideoOrientation.PORTRAIT;
      } else {
        // Default to landscape for square-ish windows
        _currentOrientation = VideoOrientation.LANDSCAPE;
      }
      
      // debugPrint('Initial orientation set to: ${_currentOrientation.name}');
    } else {
      // For mobile, use device orientation
      _currentOrientation = mediaQuery.orientation == Orientation.landscape
          ? VideoOrientation.LANDSCAPE
          : VideoOrientation.PORTRAIT;
    }
    
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
      
      // Update orientation after initialization
      await _bufferManager.updateOrientation(_currentOrientation);
      
      // Subscribe to video updates
      _videoUpdateSubscription = _bufferManager.queueManager.videoUpdateStream.listen((updatedVideo) {
        if (!_isDisposed && mounted) {
          // Calling setState to refresh UI with updated video data
          setState(() {
            // Since VideoResult is immutable, we need to use the updated copy
            // that comes from the stream, not create a new one
            // The parent widget should receive this via the onVideoUpdated callback
            if (widget.onVideoUpdated != null) {
              debugPrint('PLAYER: Received video update, evolvedDescription length: ${updatedVideo.evolvedDescription.length}');
              
              if (updatedVideo.evolvedDescription.isNotEmpty) {
                debugPrint('PLAYER: First 100 chars: ${updatedVideo.evolvedDescription.substring(0, min(100, updatedVideo.evolvedDescription.length))}...');
              }
              
              widget.onVideoUpdated!(updatedVideo);
            } else {
              debugPrint('PLAYER: No video update callback registered');
            }
          });
        }
      });
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
      // Initialize simulation pause state based on initial autoPlay setting
      _bufferManager.queueManager.setSimulationPaused(!widget.autoPlay);
      
      setState(() {
        _playbackController.isLoading = false;
        _playbackController.isInitialLoad = false;
      });
    }
  }

  void _togglePlayback() {
    _playbackController.togglePlayback();
    
    // Control the simulation based on playback state
    _bufferManager.queueManager.setSimulationPaused(!_playbackController.isPlaying);
    
    if (!_isDisposed && mounted) {
      setState(() {});
    }
  }

  Future<void> _playClip(dynamic clip) async {
    if (_isDisposed || clip.base64Data == null) return;

    try {
      VideoPlayerController? newController;
      
      if (_playbackController.nextController != null) {
        // debugPrint('Using preloaded controller for clip ${clip.seed}');
        newController = _playbackController.nextController;
        _playbackController.nextController = null;
      } else {
        // debugPrint('Creating new controller for clip ${clip.seed}');
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
        // debugPrint('Started playback of clip ${clip.seed}');
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
    
    // Ensure simulation is paused when widget is disposed
    _bufferManager.queueManager.setSimulationPaused(true);
      
    // Unregister the observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Cancel the video update subscription
    _videoUpdateSubscription?.cancel();
    
    // Dispose controllers and timers
    _playbackController.dispose();
    _bufferManager.dispose();
    _orientationDebounceTimer?.cancel();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get the actual screen/window dimensions from MediaQuery
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine orientation based on the screen dimensions rather than the constraints
        // This avoids issues with infinite heights in ScrollViews
        VideoOrientation newOrientation;
        
        if (kIsWeb) {
          // Use the screen dimensions to determine orientation
          // This is more reliable than constraints in scrollable containers
          double aspectRatio = screenWidth / screenHeight;
          // debugPrint('Screen size: ${screenWidth.toInt()}x${screenHeight.toInt()}, aspect ratio: ${aspectRatio.toStringAsFixed(2)}');
          
          if (aspectRatio > 1.2) {
            newOrientation = VideoOrientation.LANDSCAPE;
          } else if (aspectRatio < 0.8) {
            newOrientation = VideoOrientation.PORTRAIT;
          } else {
            // In middle zone (near square), maintain current orientation for stability
            newOrientation = _currentOrientation;
          }
        } else {
          // For mobile platforms, still use the device orientation
          final orientation = mediaQuery.orientation;
          newOrientation = orientation == Orientation.landscape
              ? VideoOrientation.LANDSCAPE
              : VideoOrientation.PORTRAIT;
        }
        
        // Check if orientation changed
        if (newOrientation != _currentOrientation) {
          // Ensure we don't change orientation too frequently
          final now = DateTime.now();
          final timeSinceLastChange = now.difference(_lastOrientationChange);
          
          // Debug log the orientation change request with more details
          // debugPrint('Orientation change request: ${_currentOrientation.name} -> ${newOrientation.name}');
          // debugPrint('  • Current orientation: ${_currentOrientation.name}');
          // debugPrint('  • New orientation: ${newOrientation.name}');
          // debugPrint('  • Screen size: ${screenWidth.toInt()}x${screenHeight.toInt()}');
          // debugPrint('  • Aspect ratio: ${(screenWidth / screenHeight).toStringAsFixed(2)}');
          // debugPrint('  • Time since last change: ${timeSinceLastChange.inMilliseconds}ms');
     
          // Cancel any pending orientation change
          _orientationDebounceTimer?.cancel();
          
          if (timeSinceLastChange.inMilliseconds >= 500) {
            // debugPrint('Applying immediate orientation change to ${newOrientation.name}');
            
            // Force immediate orientation change
            setState(() {
              _currentOrientation = newOrientation;
              _lastOrientationChange = now;
            });
            
            // Update buffer manager orientation
            _bufferManager.updateOrientation(newOrientation);
          } else {
            // For recent changes, set a short timer to check if the orientation remains stable
            _orientationDebounceTimer = Timer(const Duration(milliseconds: 800), () {
              if (!_isDisposed && mounted) {
                // Get the latest screen dimensions
                final latestMediaQuery = MediaQuery.of(context);
                final latestWidth = latestMediaQuery.size.width;
                final latestHeight = latestMediaQuery.size.height;
                final latestAspectRatio = latestWidth / latestHeight;
                
                // debugPrint('Delayed check - screen size: ${latestWidth.toInt()}x${latestHeight.toInt()}, ratio: ${latestAspectRatio.toStringAsFixed(2)}');
                
                // Determine if the orientation is still requesting the same change
                VideoOrientation latestOrientation;
                if (latestAspectRatio > 1.2) {
                  latestOrientation = VideoOrientation.LANDSCAPE;
                } else if (latestAspectRatio < 0.8) {
                  latestOrientation = VideoOrientation.PORTRAIT;
                } else {
                  latestOrientation = _currentOrientation;
                }
                
                // Only apply the change if the orientation is still the same as requested
                if (latestOrientation == newOrientation && _currentOrientation != newOrientation) {
                  // debugPrint('Applying delayed orientation change to ${newOrientation.name}');
                  
                  if (!_isDisposed && mounted) {
                    setState(() {
                      _currentOrientation = newOrientation;
                      _lastOrientationChange = DateTime.now();
                    });
                    
                    // Update buffer manager orientation
                    _bufferManager.updateOrientation(newOrientation);
                  }
                }
              }
            });
          }
        }
        
        // Video player layout
        final controller = _playbackController.currentController;
        final aspectRatio = controller?.value.aspectRatio ?? 16/9;
        
        // Calculate player height based on the available width from constraints
        // (which will be finite in the row/column layout)
        double playerHeight = constraints.maxWidth / aspectRatio;
        
        // Safety check - if width was somehow infinite or the result is invalid
        if (!constraints.maxWidth.isFinite || !playerHeight.isFinite) {
          // Use a percentage of screen height as fallback
          playerHeight = screenHeight * 0.4;
          debugPrint('Using fallback height: $playerHeight (percentage of screen height)');
        }

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
                  color: TikSlopColors.surfaceVariant,
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