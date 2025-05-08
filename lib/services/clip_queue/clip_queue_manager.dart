// lib/services/clip_queue/clip_queue_manager.dart

import 'dart:async';
import 'dart:math';
import 'package:aitube2/config/config.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import '../../models/video_result.dart';
import '../../models/video_orientation.dart';
import '../../models/chat_message.dart';
import '../websocket_api_service.dart';
import '../chat_service.dart';
import '../../utils/seed.dart';
import 'clip_states.dart';
import 'video_clip.dart';
import 'queue_stats_logger.dart';
import 'clip_generation_handler.dart';

/// Manages a queue of video clips for generation and playback
class ClipQueueManager {
  /// The video for which clips are being generated
  VideoResult video;
  
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
  
  /// Timer for evolving the description
  Timer? _descriptionEvolutionTimer;
  
  /// Last time the description was evolved
  DateTime _lastDescriptionEvolutionTime = DateTime.now();
  
  /// Whether the manager is disposed
  bool _isDisposed = false;
  
  /// Whether the simulation is paused (controlled by video playback)
  bool _isSimulationPaused = false;
  
  /// Stats logger
  final QueueStatsLogger _logger = QueueStatsLogger();
  
  /// Generation handler
  late final ClipGenerationHandler _generationHandler;
  
  /// ID of the video being managed
  final String videoId;
  
  /// Evolution counter for tracking how many times we've evolved the description
  int _evolutionCounter = 0;
  
  /// Recent chat messages to include in description evolution
  final List<ChatMessage> _recentChatMessages = [];

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
    
    // Start listening to chat messages
    final chatService = ChatService();
    chatService.initialize().then((_) {
      chatService.joinRoom(videoId).then((_) {
        chatService.chatStream.listen(_addChatMessage);
      }).catchError((e) {
        debugPrint('ClipQueueManager: Error joining chat room: $e');
      });
    }).catchError((e) {
      debugPrint('ClipQueueManager: Error initializing chat service: $e');
    });
  }
  
  /// Add a chat message to the recent messages list
  void _addChatMessage(ChatMessage message) {
    if (message.videoId == videoId) {
      _recentChatMessages.add(message);
      // Keep only the 10 most recent messages
      if (_recentChatMessages.length > 10) {
        _recentChatMessages.removeAt(0);
      }
      ClipQueueConstants.logEvent('Added chat message: ${message.content.substring(0, min(20, message.content.length))}...');
    }
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

  /// Current orientation of clips being generated
  VideoOrientation _currentOrientation = VideoOrientation.LANDSCAPE;
  
  /// Get the current orientation
  VideoOrientation get currentOrientation => _currentOrientation;

  /// Initialize the clip queue
  Future<void> initialize({VideoOrientation? orientation}) async {
    if (_isDisposed) return;
    
    _logger.logStateChange(
      'initialize:start',
      clipBuffer: _clipBuffer,
      activeGenerations: _activeGenerations,
      clipHistory: _clipHistory,
      isDisposed: _isDisposed,
    );
    _clipBuffer.clear();
    
    // Reset evolution counter and last evolution time
    _evolutionCounter = 0;
    _lastDescriptionEvolutionTime = DateTime.now();
    
    // Set initial orientation
    _currentOrientation = orientation ?? getOrientationFromDimensions(
      Configuration.instance.originalClipWidth, 
      Configuration.instance.originalClipHeight
    );
    
    try {
      final bufferSize = Configuration.instance.renderQueueBufferSize;
      while (_clipBuffer.length < bufferSize) {
        if (_isDisposed) return;
        
        final newClip = VideoClip(
          prompt: "${video.title}\n${video.description}",
          seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
          orientation: _currentOrientation,
        );
        _clipBuffer.add(newClip);
        ClipQueueConstants.logEvent('Added initial clip ${newClip.seed} to buffer with orientation: ${_currentOrientation.name}');
      }

      if (_isDisposed) return;

      _startBufferCheck();
      _startDescriptionEvolution();
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
  
  /// Start the simulation timer
  void _startDescriptionEvolution() {
    // Cancel any existing timer
    _descriptionEvolutionTimer?.cancel();
    
    // Only start if simulation frequency is greater than 0
    if (Configuration.instance.simLoopFrequencyInSec <= 0) {
      ClipQueueConstants.logEvent('Simulation disabled (frequency is 0)');
      return;
    }
    
    // Adaptive check interval - less frequent checks to reduce overhead
    final checkInterval = max(3, Configuration.instance.simLoopFrequencyInSec ~/ 3);
    
    ClipQueueConstants.logEvent('Starting simulation with check interval of $checkInterval seconds');
    
    // Check periodically if it's time to simulate the video
    _descriptionEvolutionTimer = Timer.periodic(
      Duration(seconds: checkInterval),
      (timer) async {
        if (_isDisposed) return;
        
        // Skip if simulation is paused (due to video playback being paused)
        if (_isSimulationPaused) {
          ClipQueueConstants.logEvent('Skipping simulation because it is paused');
          return;
        }
        
        // Check if we're currently generating a video - if so, delay simulation
        final isGenerating = _activeGenerations.isNotEmpty;
        if (isGenerating) {
          ClipQueueConstants.logEvent('Delaying simulation due to active generations');
          return;
        }
        
        // Calculate time since last simulation
        final now = DateTime.now();
        final duration = now.difference(_lastDescriptionEvolutionTime);
        
        // If we've waited long enough, simulate the video
        if (duration.inSeconds >= Configuration.instance.simLoopFrequencyInSec) {
          ClipQueueConstants.logEvent('Triggering simulation after ${duration.inSeconds} seconds');
          await _evolveDescription();
          _lastDescriptionEvolutionTime = now;
        }
      },
    );
    ClipQueueConstants.logEvent('Started simulation timer');
  }
  
  /// Simulate the video by evolving the description using the LLM
  Future<void> _evolveDescription() async {
    if (!_websocketService.isConnected) {
      ClipQueueConstants.logEvent('Cannot simulate video: websocket not connected');
      return;
    }
    
    int retryCount = 0;
    const maxRetries = 2;
    
    // Function to get chat message string
    String getChatMessagesString() {
      if (_recentChatMessages.isEmpty) return '';
      
      return _recentChatMessages.map((msg) => 
        "${msg.username}: ${msg.content}"
      ).join("\n");
    }
    
    while (retryCount <= maxRetries) {
      try {
        // Format recent chat messages as a string for the simulation prompt
        String chatMessagesString = getChatMessagesString();
        if (chatMessagesString.isNotEmpty) {
          ClipQueueConstants.logEvent('Including ${_recentChatMessages.length} chat messages in simulation');
        }
        
        // Use the WebSocketService to simulate the video
        final result = await _websocketService.simulate(
          videoId: video.id,
          originalTitle: video.title,
          originalDescription: video.description,
          currentDescription: video.evolvedDescription.isEmpty ? video.description : video.evolvedDescription,
          condensedHistory: video.condensedHistory,
          evolutionCount: _evolutionCounter,
          chatMessages: chatMessagesString,
        );
        
        // Update the video with the evolved description
        video = video.copyWith(
          evolvedDescription: result['evolved_description'],
          condensedHistory: result['condensed_history'],
        );
        
        _evolutionCounter++;
        ClipQueueConstants.logEvent('Video simulated (iteration $_evolutionCounter)');
        onQueueUpdated?.call();
        
        // Success, exit retry loop
        break;
      } catch (e) {
        retryCount++;
        ClipQueueConstants.logEvent('Error simulating video attempt $retryCount/$maxRetries: $e');
        
        if (retryCount <= maxRetries) {
          // Wait before retrying with exponential backoff
          final delay = Duration(seconds: 1 << retryCount);
          ClipQueueConstants.logEvent('Retrying simulation in ${delay.inSeconds} seconds...');
          await Future.delayed(delay);
        } else {
          ClipQueueConstants.logEvent('Failed to simulate video after $maxRetries attempts');
          
          // If we've been successful before but failed now, we can continue using the last evolved description
          if (_evolutionCounter > 0) {
            ClipQueueConstants.logEvent('Continuing with previous description');
          }
        }
      }
    }
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
      // Determine which description to use for the prompt
      String descriptionToUse = video.description;
      
      // If we have an evolved description, use that instead
      if (video.evolvedDescription.isNotEmpty) {
        descriptionToUse = video.evolvedDescription;
      }
      
      final newClip = VideoClip(
        prompt: "${video.title}\n${descriptionToUse}",
        seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
        orientation: _currentOrientation,
      );
      _clipBuffer.add(newClip);
      ClipQueueConstants.logEvent('Added new clip ${newClip.seed} with orientation ${_currentOrientation.name} to maintain buffer size');
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
      
      // Determine which description to use for the prompt
      String descriptionToUse = video.description;
      
      // If we have an evolved description, use that instead
      if (video.evolvedDescription.isNotEmpty) {
        descriptionToUse = video.evolvedDescription;
        ClipQueueConstants.logEvent('Using evolved description for new clip (evolution #$_evolutionCounter)');
      }
      
      // Add a new pending clip with current orientation
      final newClip = VideoClip(
        prompt: "${video.title}\n${descriptionToUse}",
        seed: video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed(),
        orientation: _currentOrientation,
      );
      _clipBuffer.add(newClip);
      ClipQueueConstants.logEvent('Replaced played clip ${clip.seed} with new clip ${newClip.seed} using orientation ${_currentOrientation.name}');
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
  
  /// Handle orientation change
  Future<void> updateOrientation(VideoOrientation newOrientation) async {
    if (_currentOrientation == newOrientation) {
      ClipQueueConstants.logEvent('Orientation unchanged: ${newOrientation.name}');
      return;
    }
    
    ClipQueueConstants.logEvent('Orientation changed from ${_currentOrientation.name} to ${newOrientation.name}');
    _currentOrientation = newOrientation;
    
    // Cancel any active generations
    for (var clipSeed in _activeGenerations.toList()) {
      _activeGenerations.remove(clipSeed);
    }
    
    // Clear buffer and history
    _clipBuffer.clear();
    _clipHistory.clear();
    
    // Re-initialize the queue with the new orientation
    await initialize(orientation: newOrientation);
    
    // Notify listeners
    onQueueUpdated?.call();
  }
  
  /// Set the simulation pause state based on video playback
  void setSimulationPaused(bool isPaused) {
    if (_isSimulationPaused == isPaused) return;
    
    _isSimulationPaused = isPaused;
    ClipQueueConstants.logEvent(
      isPaused 
        ? 'Simulation paused (video playback paused)' 
        : 'Simulation resumed (video playback resumed)'
    );
    
    // If we're resuming after a pause, update the last evolution time
    // to avoid immediate evolution after resuming
    if (!isPaused) {
      _lastDescriptionEvolutionTime = DateTime.now();
    }
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
    _descriptionEvolutionTimer?.cancel();
    
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