// lib/services/clip_queue/video_clip.dart

import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'clip_states.dart';
import '../../models/video_orientation.dart';

/// Represents a video clip in the queue
class VideoClip {
  /// Unique identifier for the clip
  final String id;
  
  /// The prompt used to generate the clip
  final String prompt;
  
  /// The seed used for generation
  final int seed;
  
  /// Current state of the clip
  ClipState state;
  
  /// Device orientation for the clip
  final VideoOrientation orientation;
  
  /// Base64 encoded video data
  String? base64Data;
  
  /// Timer for retrying generation
  Timer? retryTimer;
  
  /// Completer for tracking generation completion
  Completer<void>? generationCompleter;
  
  /// When generation started
  DateTime? generationStartTime;
  
  /// When generation ended
  DateTime? generationEndTime;
  
  /// When playback started
  DateTime? playStartTime;
  
  /// Number of retry attempts
  int retryCount = 0;
  
  /// Maximum number of retries allowed
  static const maxRetries = 3;

  /// Constructor
  VideoClip({
    String? id,
    required this.prompt,
    required this.seed,
    this.orientation = VideoOrientation.LANDSCAPE,
    this.state = ClipState.generationPending,
    this.base64Data,
  }): id = id ?? const Uuid().v4(); 

  /// Whether the clip is ready to play
  bool get isReady => state == ClipState.generatedAndReadyToPlay;
  
  /// Whether the clip is waiting to be generated
  bool get isPending => state == ClipState.generationPending;
  
  /// Whether the clip is currently being generated
  bool get isGenerating => state == ClipState.generationInProgress;
  
  /// Whether the clip is currently playing
  bool get isPlaying => state == ClipState.generatedAndPlaying;
  
  /// Whether the clip failed to generate
  bool get hasFailed => state == ClipState.failedToGenerate;
  
  /// Whether the clip has been played
  bool get hasPlayed => state == ClipState.generatedAndPlayed;
  
  /// Whether the clip can be retried
  bool get canRetry => retryCount < maxRetries;

  /// Duration of the generation process
  Duration? get generationDuration {
    if (generationStartTime == null) return null;
    if (isGenerating) {
      return DateTime.now().difference(generationStartTime!);
    }
    if (isReady || isPlaying || hasPlayed) {
      return generationEndTime?.difference(generationStartTime!);
    }
    return null;
  }

  /// Duration of playback
  Duration? get playbackDuration {
    if (playStartTime == null) return null;
    return DateTime.now().difference(playStartTime!);
  }

  /// Mark the clip as playing
  void startPlaying() {
    if (state == ClipState.generatedAndReadyToPlay) {
      state = ClipState.generatedAndPlaying;
      playStartTime = DateTime.now();
    }
  }

  /// Mark the clip as played
  void finishPlaying() {
    if (state == ClipState.generatedAndPlaying) {
      state = ClipState.generatedAndPlayed;
    }
  }

  /// Mark the clip as generated
  void completeGeneration() {
    if (state == ClipState.generationInProgress) {
      generationEndTime = DateTime.now();
      state = ClipState.generatedAndReadyToPlay;
    }
  }

  @override
  String toString() => 'VideoClip(seed: $seed, state: $state, retryCount: $retryCount)';
}