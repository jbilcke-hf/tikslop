// lib/services/clip_queue/clip_states.dart

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Represents the different states a video clip can be in during its lifecycle
enum ClipState {
  /// The clip is waiting to be generated
  generationPending,
  
  /// The clip is currently being generated
  generationInProgress,
  
  /// The clip has been generated and is ready to be played
  generatedAndReadyToPlay,
  
  /// The clip has been generated and is currently playing
  generatedAndPlaying,
  
  /// The clip generation failed
  failedToGenerate,
  
  /// The clip has been generated and has been played
  generatedAndPlayed
}

/// Constants for clip queue management
class ClipQueueConstants {
  /// The delay before retrying a failed clip generation
  static const Duration retryDelay = Duration(seconds: 2);
  
  /// The timeout for a clip generation before it is considered stuck
  static const Duration clipTimeout = Duration(seconds: 90);
  
  /// The timeout for the actual generation process
  static const Duration generationTimeout = Duration(seconds: 60);
  
  /// Whether to show logs in debug mode
  static const bool showLogsInDebugMode = false;
  
  /// Maximum number of generation times to store for averaging
  static const int maxStoredGenerationTimes = 10;
  
  /// Helper function to avoid having to type unawaited everywhere
  static void unawaited(Future<void> future) {
    // This function intentionally does nothing.
    // It's used to explicitly mark that we're not waiting for this Future.
  }
  
  /// Logs an event if debug mode is enabled
  static void logEvent(String message) {
    if (showLogsInDebugMode && kDebugMode) {
      debugPrint('ClipQueue: $message');
    }
  }
}