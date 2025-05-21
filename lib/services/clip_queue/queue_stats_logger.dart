// lib/services/clip_queue/queue_stats_logger.dart

import 'package:collection/collection.dart';
import 'video_clip.dart';
import 'clip_states.dart';

/// Handles logging and statistics for the ClipQueueManager
class QueueStatsLogger {
  /// Last time the state was logged
  DateTime? _lastStateLogTime;
  
  /// Last state that was logged
  Map<String, dynamic>? _lastLoggedState;
  
  /// The most recent successful generation time
  DateTime? _lastSuccessfulGeneration;
  
  /// List of recent generation times for calculating averages
  final List<Duration> _generationTimes = [];

  /// Log a clip queue state change
  void logStateChange(
    String trigger, {
    required List<VideoClip> clipBuffer,
    required Set<String> activeGenerations,
    required List<VideoClip> clipHistory,
    required bool isDisposed,
  }) {
    if (isDisposed) return;

    final currentState = {
      'readyClips': clipBuffer.where((c) => c.isReady).length,
      'playingClips': clipBuffer.where((c) => c.isPlaying).length,
      'generatingClips': activeGenerations.length,
      'pendingClips': clipBuffer.where((c) => c.isPending).length,
      'failedClips': clipBuffer.where((c) => c.hasFailed).length,
      'clipStates': clipBuffer.map((c) => {
        'seed': c.seed,
        'state': c.state.toString(),
        'retryCount': c.retryCount,
        'genDuration': c.generationDuration?.inSeconds,
        'playDuration': c.playbackDuration?.inSeconds,
      }).toList(),
      'activeGenerations': List<String>.from(activeGenerations),
      'historySize': clipHistory.length,
    };

    // Only log if state has changed
    if (_lastLoggedState == null || 
        !_areStatesEqual(_lastLoggedState!, currentState) ||
        _shouldLogDueToTimeout()) {
      
      // debugPrint('Queue State Change [$trigger] => Ready: ${currentState['readyClips']}, Playing: ${currentState['playingClips']}, Generating: ${currentState['generatingClips']}');
      
      /*
      debugPrint('Pending: ${currentState['pendingClips']}');
      debugPrint('Failed: ${currentState['failedClips']}');
      debugPrint('History: ${currentState['historySize']}');
      
      debugPrint('\nClip Details:');
      final clipStates = currentState['clipStates'] as List<Map<String, dynamic>>;
      for (var clipState in clipStates) {
        debugPrint('Clip ${clipState['seed']}: ${clipState['state']} '
            '(retries: ${clipState['retryCount']}, '
            'gen: ${clipState['genDuration']}s, '
            'play: ${clipState['playDuration']}s)');
      }

      final activeGenerations = currentState['activeGenerations'] as List<String>;
      if (activeGenerations.isNotEmpty) {
        debugPrint('\nActive Generations: ${activeGenerations.join(', ')}');
      }

      debugPrint('=====================================\n');
      */
      
      _lastLoggedState = currentState;
      _lastStateLogTime = DateTime.now();
    }
  }

  /// Update generation statistics
  void updateGenerationStats(VideoClip clip) {
    if (clip.generationStartTime != null) {
      final duration = DateTime.now().difference(clip.generationStartTime!);
      _generationTimes.add(duration);
      if (_generationTimes.length > ClipQueueConstants.maxStoredGenerationTimes) {
        _generationTimes.removeAt(0);
      }
      _lastSuccessfulGeneration = DateTime.now();
    }
  }

  /// Calculate the average generation time
  Duration? getAverageGenerationTime() {
    if (_generationTimes.isEmpty) return null;
    final totalMs = _generationTimes.fold<int>(
      0, 
      (sum, duration) => sum + duration.inMilliseconds
    );
    return Duration(milliseconds: totalMs ~/ _generationTimes.length);
  }

  /// Print current state of the clip queue
  void printQueueState({
    required List<VideoClip> clipBuffer,
    required Set<String> activeGenerations,
    required List<VideoClip> clipHistory,
  }) {
    final ready = clipBuffer.where((c) => c.isReady).length;
    final playing = clipBuffer.where((c) => c.isPlaying).length;
    final generating = activeGenerations.length;
    final pending = clipBuffer.where((c) => c.isPending).length;
    final failed = clipBuffer.where((c) => c.hasFailed).length;
    
    ClipQueueConstants.logEvent('\nQueue State:');
    ClipQueueConstants.logEvent('Buffer size: ${clipBuffer.length}');
    ClipQueueConstants.logEvent('Ready: $ready, Playing: $playing, Generating: $generating, Pending: $pending, Failed: $failed');
    ClipQueueConstants.logEvent('History size: ${clipHistory.length}');
    
    for (var i = 0; i < clipBuffer.length; i++) {
      final clip = clipBuffer[i];
      final genDuration = clip.generationDuration;
      final playDuration = clip.playbackDuration;
      ClipQueueConstants.logEvent('Clip $i: seed=${clip.seed}, state=${clip.state}, '
          'retries=${clip.retryCount}, generation time=${genDuration?.inSeconds}s'
          '${playDuration != null ? ", playing for ${playDuration.inSeconds}s" : ""}');
    }
  }

  /// Get statistics for the buffer
  Map<String, dynamic> getBufferStats({
    required List<VideoClip> clipBuffer,
    required List<VideoClip> clipHistory,
    required Set<String> activeGenerations,
  }) {
    final averageGeneration = getAverageGenerationTime();
    return {
      'bufferSize': clipBuffer.length,
      'historySize': clipHistory.length,
      'activeGenerations': activeGenerations.length,
      'pendingClips': clipBuffer.where((c) => c.isPending).length,
      'readyClips': clipBuffer.where((c) => c.isReady).length,
      'failedClips': clipBuffer.where((c) => c.hasFailed).length,
      'lastSuccessfulGeneration': _lastSuccessfulGeneration?.toString(),
      'averageGenerationTime': averageGeneration?.toString(),
      'clipStates': clipBuffer.map((c) => c.state.toString()).toList(),
    };
  }

  /// Log generation status
  void logGenerationStatus({
    required List<VideoClip> clipBuffer,
    required Set<String> activeGenerations,
  }) {
    final pending = clipBuffer.where((c) => c.isPending).length;
    final generating = activeGenerations.length;
    final ready = clipBuffer.where((c) => c.isReady).length;
    final playing = clipBuffer.where((c) => c.isPlaying).length;
    
    ClipQueueConstants.logEvent('''
      Buffer Status:
      - Pending: $pending
      - Generating: $generating
      - Ready: $ready
      - Playing: $playing
      - Active generations: ${activeGenerations.join(', ')}
    ''');
  }

  /// Check if two states are equal
  bool _areStatesEqual(Map<String, dynamic> state1, Map<String, dynamic> state2) {
    return state1['readyClips'] == state2['readyClips'] &&
           state1['playingClips'] == state2['playingClips'] &&
           state1['generatingClips'] == state2['generatingClips'] &&
           state1['pendingClips'] == state2['pendingClips'] &&
           state1['failedClips'] == state2['failedClips'] &&
           state1['historySize'] == state2['historySize'] &&
           const ListEquality().equals(
             state1['activeGenerations'] as List,
             state2['activeGenerations'] as List
           );
  }

  /// Check if we should log due to timeout
  bool _shouldLogDueToTimeout() {
    if (_lastStateLogTime == null) return true;
    // Force log every 30 seconds even if state hasn't changed
    return DateTime.now().difference(_lastStateLogTime!) > const Duration(seconds: 30);
  }
}