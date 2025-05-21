// lib/services/clip_queue/clip_generation_handler.dart

import 'dart:async';
import 'package:tikslop/config/config.dart';
import '../websocket_api_service.dart';
import '../../models/video_result.dart';
import 'clip_states.dart';
import 'video_clip.dart';
import 'queue_stats_logger.dart';

/// Handles the generation of video clips
class ClipGenerationHandler {
  /// WebSocket service for API communication
  final WebSocketApiService _websocketService;
  
  /// Logger for tracking stats
  final QueueStatsLogger _logger;
  
  /// Set of active generations (by seed)
  final Set<String> _activeGenerations;
  
  /// Whether the handler is disposed
  bool _isDisposed = false;
  
  /// Callback for when the queue is updated
  final void Function()? onQueueUpdated;

  /// Constructor
  ClipGenerationHandler({
    required WebSocketApiService websocketService,
    required QueueStatsLogger logger,
    required Set<String> activeGenerations,
    required this.onQueueUpdated,
  }) : _websocketService = websocketService,
       _logger = logger,
       _activeGenerations = activeGenerations;
  
  /// Setter for the disposed state
  set isDisposed(bool value) {
    _isDisposed = value;
  }
  
  /// Whether a new generation can be started
  bool canStartNewGeneration(int maxConcurrentGenerations) => 
      _activeGenerations.length < maxConcurrentGenerations;
      
  /// Handle a stuck generation
  void handleStuckGeneration(VideoClip clip) {
    ClipQueueConstants.logEvent('Found stuck generation for clip ${clip.seed}');
    
    if (_activeGenerations.contains(clip.seed.toString())) {
      _activeGenerations.remove(clip.seed.toString());
    }
    
    clip.state = ClipState.failedToGenerate;
    
    if (clip.canRetry) {
      scheduleRetry(clip);
    }
  }
  
  /// Schedule a retry for a failed generation
  void scheduleRetry(VideoClip clip) {
    clip.retryTimer?.cancel();
    clip.retryTimer = Timer(ClipQueueConstants.retryDelay, () {
      if (!_isDisposed && clip.hasFailed) {
        ClipQueueConstants.logEvent('Retrying clip ${clip.seed} (attempt ${clip.retryCount + 1}/${VideoClip.maxRetries})');
        clip.state = ClipState.generationPending;
        clip.generationCompleter = null;
        clip.generationStartTime = null;
        onQueueUpdated?.call();
      }
    });
  }
  
  /// Generate a video clip
  Future<void> generateClip(VideoClip clip, VideoResult video) async {
    if (clip.isGenerating || clip.isReady || _isDisposed || 
        !canStartNewGeneration(Configuration.instance.renderQueueMaxConcurrentGenerations)) {
      return;
    }

    final clipSeed = clip.seed.toString();
    if (_activeGenerations.contains(clipSeed)) {
      ClipQueueConstants.logEvent('Clip $clipSeed already generating');
      return;
    }

    _activeGenerations.add(clipSeed);
    clip.state = ClipState.generationInProgress;
    clip.generationCompleter = Completer<void>();
    clip.generationStartTime = DateTime.now();

    try {
      // Check if we're disposed before proceeding
      if (_isDisposed) {
        ClipQueueConstants.logEvent('Cancelled generation of clip $clipSeed - handler disposed');
        return;
      }

      // Generate new video with timeout, passing the orientation
      String videoData = await _websocketService.generateVideo(
        video,
        seed: clip.seed,
        orientation: clip.orientation,
      ).timeout(ClipQueueConstants.generationTimeout);

      if (!_isDisposed) {
        await handleSuccessfulGeneration(clip, videoData);
      }

    } catch (e) {
      if (!_isDisposed) {
        handleFailedGeneration(clip, e);
      }
    } finally {
      cleanupGeneration(clip);
    }
  }
  
  /// Handle a successful generation
  Future<void> handleSuccessfulGeneration(
    VideoClip clip,
    String videoData,
  ) async {
    if (_isDisposed) return;
    
    clip.base64Data = videoData;
    clip.completeGeneration();
    
    // Only complete the completer if it exists and isn't already completed
    if (clip.generationCompleter != null && !clip.generationCompleter!.isCompleted) {
      clip.generationCompleter!.complete();
    }
    
    _logger.updateGenerationStats(clip);
    onQueueUpdated?.call();
  }
  
  /// Handle a failed generation
  void handleFailedGeneration(VideoClip clip, dynamic error) {
    if (_isDisposed) return;
    clip.state = ClipState.failedToGenerate;
    clip.retryCount++;
    
    // Only complete with error if the completer exists and isn't completed
    if (clip.generationCompleter != null && !clip.generationCompleter!.isCompleted) {
      clip.generationCompleter!.completeError(error);
    }
    
    if (clip.canRetry) {
      scheduleRetry(clip);
    }
  }
  
  /// Clean up after a generation attempt
  void cleanupGeneration(VideoClip clip) {
    if (!_isDisposed) {
      _activeGenerations.remove(clip.seed.toString());
      onQueueUpdated?.call();
    }
  }
  
  /// Check for stuck generations
  void checkForStuckGenerations(List<VideoClip> clipBuffer) {
    final now = DateTime.now();
    var hadStuckGenerations = false;

    for (final clip in clipBuffer) {
      if (clip.isGenerating && 
          clip.generationStartTime != null &&
          now.difference(clip.generationStartTime!) > ClipQueueConstants.clipTimeout) {
        hadStuckGenerations = true;
        handleStuckGeneration(clip);
      }
    }

    if (hadStuckGenerations) {
      ClipQueueConstants.logEvent('Cleaned up stuck generations. Active: ${_activeGenerations.length}');
    }
  }
}