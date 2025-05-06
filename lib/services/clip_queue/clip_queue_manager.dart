// lib/services/clip_queue/clip_queue_manager.dart

import 'dart:async';
import 'package:aitube2/config/config.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import '../../models/video_result.dart';
import '../websocket_api_service.dart';
import '../../utils/seed.dart';
import 'clip_states.dart';
import 'video_clip.dart';
import 'queue_stats_logger.dart';
import 'clip_generation_handler.dart';

/// Manages a queue of video clips for generation and playback
class ClipQueueManager {
  /// The video for which clips are being generated
  final VideoResult video;
  
  /// WebSocket service for API communication
  final WebSocketApiService _websocketService;
  
  /// Callback for when the queue is updated
  final void Function()? onQueueUpdated;
  
  /// Buffer of clips being managed
  final List<VideoClip> _clipBuffer = [];
  
  /// History of played clips
  final List<VideoClip> _clipHistory = [];
  
  /// Set of active generations (by seed)
  final Set<String> _activeGenerations = {};
  
  /// Timer for checking the buffer state
  Timer? _bufferCheckTimer;
  
  /// Whether the manager is disposed
  bool _isDisposed = false;
  
  /// Stats logger
  final QueueStatsLogger _logger = QueueStatsLogger();
  
  /// Generation handler
  late final ClipGenerationHandler _generationHandler;
  
  /// ID of the video being managed
  final String videoId;

  /// Constructor
  ClipQueueManager({
    required this.video,
    WebSocketApiService? websocketService,
    this.onQueueUpdated,
  }) : videoId = video.id,
       _websocketService = websocketService ?? WebSocketApiService() {
    _generationHandler = ClipGenerationHandler(
      websocketService: _websocketService,
      logger: _logger,
      activeGenerations: _activeGenerations,
      onQueueUpdated: onQueueUpdated,
    );
  }

  /// Whether a new generation can be started
  bool get canStartNewGeneration => 
      _activeGenerations.length < Configuration.instance.renderQueueMaxConcurrentGenerations;
      
  /// Number of pending generations
  int get pendingGenerations => _clipBuffer.where((c) => c.isPending).length;
  
  /// Number of active generations
  int get activeGenerations => _activeGenerations.length;
  
  /// Current clip that is ready or playing
  VideoClip? get currentClip => _clipBuffer.firstWhereOrNull((c) => c.isReady || c.isPlaying);
  
  /// Next clip that is ready to play
  VideoClip? get nextReadyClip => _clipBuffer.where((c) => c.isReady && !c.isPlaying).firstOrNull;
  
  /// Whether there are any ready clips
  bool get hasReadyClips => _clipBuffer.any((c) => c.isReady);
  
  /// Unmodifiable view of the clip buffer
  List<VideoClip> get clipBuffer => List.unmodifiable(_clipBuffer);
  
  /// Unmodifiable view of the clip history
  List<VideoClip> get clipHistory => List.unmodifiable(_clipHistory);

  /// Initialize the clip queue
  Future<void> initialize() async {
    if (_isDisposed) return;
    
    _logger.logStateChange(
      'initialize:start',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
    _clipBuffer.clear();
    
    try {
      final bufferSize = Configuration.instance.renderQueueBufferSize;
      while (_clipBuffer.length < bufferSize) {
        if (_isDisposed) return;
        
        final newClip = VideoClip(
          prompt: "${video.title}\n${video.description}",
          seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
        );
        _clipBuffer.add(newClip);
        ClipQueueConstants.logEvent('Added initial clip ${newClip.seed} to buffer');
      }

      if (_isDisposed) return;

      _startBufferCheck();
      await _fillBuffer();
      ClipQueueConstants.logEvent('Initialization complete. Buffer size: ${_clipBuffer.length}');
      printQueueState();
    } catch (e) {
      ClipQueueConstants.logEvent('Initialization error: $e');
      rethrow;
    }

    _logger.logStateChange(
      'initialize:complete',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
  }

  /// Start the buffer check timer
  void _startBufferCheck() {
    _bufferCheckTimer?.cancel();
    _bufferCheckTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (timer) {
        if (!_isDisposed) {
          _fillBuffer();
        }
      },
    );
    ClipQueueConstants.logEvent('Started buffer check timer');
  }

  /// Mark a specific clip as played
  void markClipAsPlayed(String clipId) {
    _logger.logStateChange(
      'markAsPlayed:start',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
    final playingClip = _clipBuffer.firstWhereOrNull((c) => c.id == clipId);
    if (playingClip != null) {
      playingClip.finishPlaying();
      
      _reorderBufferByPriority();
      _fillBuffer();
      onQueueUpdated?.call();
    }
    _logger.logStateChange(
      'markAsPlayed:complete',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
  }

  /// Fill the buffer with clips and start generations as needed
  Future<void> _fillBuffer() async {
    if (_isDisposed) return;

    // First ensure we have the correct buffer size
    while (_clipBuffer.length < Configuration.instance.renderQueueBufferSize) {
      final newClip = VideoClip(
        prompt: "${video.title}\n${video.description}",
        seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
      );
      _clipBuffer.add(newClip);
      ClipQueueConstants.logEvent('Added new clip ${newClip.seed} to maintain buffer size');
    }

    // Process played clips first
    final playedClips = _clipBuffer.where((clip) => clip.hasPlayed).toList();
    if (playedClips.isNotEmpty) {
      _processPlayedClips(playedClips);
    }
  
    // Remove failed clips and replace them
    final failedClips = _clipBuffer.where((clip) => clip.hasFailed && !clip.canRetry).toList();
    for (final clip in failedClips) {
      _clipBuffer.remove(clip);
      final newClip = VideoClip(
        prompt: "${video.title}\n${video.description}",
        seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
      );
      _clipBuffer.add(newClip);
    }

    // Clean up stuck generations
    _generationHandler.checkForStuckGenerations(_clipBuffer);

    // Get pending clips that aren't being generated
    final pendingClips = _clipBuffer
        .where((clip) => clip.isPending && !_activeGenerations.contains(clip.seed.toString()))
        .toList();

    // Calculate available generation slots
    final availableSlots = Configuration.instance.renderQueueMaxConcurrentGenerations - _activeGenerations.length;

    if (availableSlots > 0 && pendingClips.isNotEmpty) {
      final clipsToGenerate = pendingClips.take(availableSlots).toList();
      ClipQueueConstants.logEvent('Starting ${clipsToGenerate.length} parallel generations');

      final generationFutures = clipsToGenerate.map((clip) => 
        _generationHandler.generateClip(clip, video).catchError((e) {
          debugPrint('Generation failed for clip ${clip.seed}: $e');
          return null;
        })
      ).toList();

      ClipQueueConstants.unawaited(
        Future.wait(generationFutures, eagerError: false).then((_) {
          if (!_isDisposed) {
            onQueueUpdated?.call();
            // Recursively ensure buffer stays full
            _fillBuffer();
          }
        })
      );
    }

    onQueueUpdated?.call();

    _logger.logStateChange(
      'fillBuffer:complete',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
  }

  /// Reorder the buffer by priority
  void _reorderBufferByPriority() {
    // First, extract all clips that aren't played
    final activeClips = _clipBuffer.where((c) => !c.hasPlayed).toList();
    
    // Sort clips by priority:
    // 1. Currently playing clips stay at their position
    // 2. Ready clips move to the front (right after playing clips)
    // 3. In-progress generations
    // 4. Pending generations
    // 5. Failed generations
    activeClips.sort((a, b) {
      // Helper function to get priority value for a state
      int getPriority(ClipState state) {
        switch (state) {
          case ClipState.generatedAndPlaying:
            return 0;
          case ClipState.generatedAndReadyToPlay:
            return 1;
          case ClipState.generationInProgress:
            return 2;
          case ClipState.generationPending:
            return 3;
          case ClipState.failedToGenerate:
            return 4;
          case ClipState.generatedAndPlayed:
            return 5;
        }
      }

      // Compare priorities
      final priorityA = getPriority(a.state);
      final priorityB = getPriority(b.state);
      
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }
      
      // If same priority, maintain relative order by keeping original indices
      return _clipBuffer.indexOf(a).compareTo(_clipBuffer.indexOf(b));
    });

    // Clear and refill the buffer with the sorted clips
    _clipBuffer.clear();
    _clipBuffer.addAll(activeClips);
  }

  /// Process clips that have been played
  void _processPlayedClips(List<VideoClip> playedClips) {
    for (final clip in playedClips) {
      _clipBuffer.remove(clip);
      _clipHistory.add(clip);
      
      // Add a new pending clip
      final newClip = VideoClip(
        prompt: "${video.title}\n${video.description}",
        seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
      );
      _clipBuffer.add(newClip);
      ClipQueueConstants.logEvent('Replaced played clip ${clip.seed} with new clip ${newClip.seed}');
    }
    
    // Immediately trigger buffer fill to start generating new clips
    _fillBuffer();
  }

  /// Mark the current playing clip as played
  void markCurrentClipAsPlayed() {
    _logger.logStateChange(
      'markAsPlayed:start',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
    final playingClip = _clipBuffer.firstWhereOrNull((c) => c.isPlaying);
    if (playingClip != null) {
      playingClip.finishPlaying();
      
      _reorderBufferByPriority();
      _fillBuffer();
      onQueueUpdated?.call();
    }
    _logger.logStateChange(
      'markAsPlayed:complete',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
  }

  /// Start playing a specific clip
  void startPlayingClip(VideoClip clip) {
    _logger.logStateChange(
      'startPlaying:start',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
    if (clip.isReady) {
      clip.startPlaying();
      onQueueUpdated?.call();
    }
    _logger.logStateChange(
      'startPlaying:complete',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
  }

  /// Manually fill the buffer
  void fillBuffer() {
    ClipQueueConstants.logEvent('Manual buffer fill requested');
    _fillBuffer();
  }

  /// Print the current state of the queue
  void printQueueState() {
    _logger.printQueueState(
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
    );
  }

  /// Get statistics for the buffer
  Map<String, dynamic> getBufferStats() {
    return _logger.getBufferStats(
      clipBuffer: _clipBuffer,
      clipHistory: _clipHistory,
      activeGenerations: _activeGenerations,
    );
  }

  /// Dispose the manager and clean up resources
  Future<void> dispose() async {
    debugPrint('ClipQueueManager: Starting disposal for video $videoId');
    _isDisposed = true;
    _generationHandler.isDisposed = true;

    // Cancel all timers first
    _bufferCheckTimer?.cancel();
    
    // Complete any pending generation completers
    for (var clip in _clipBuffer) {
      clip.retryTimer?.cancel();
      
      if (clip.isGenerating && 
          clip.generationCompleter != null && 
          !clip.generationCompleter!.isCompleted) {
        // Don't throw an error, just complete normally
        clip.generationCompleter!.complete();
      }
    }

    // Cancel any pending requests for this video
    if (videoId.isNotEmpty) {
      _websocketService.cancelRequestsForVideo(videoId);
    }

    // Clear all collections
    _clipBuffer.clear();
    _clipHistory.clear();
    _activeGenerations.clear();

    debugPrint('ClipQueueManager: Completed disposal for video $videoId');
  }
}