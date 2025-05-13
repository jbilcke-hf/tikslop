// lib/widgets/video_player/playback_controller.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:tikslop/config/config.dart';
import 'package:tikslop/services/clip_queue/video_clip.dart';

/// Manages video playback logic for the video player
class PlaybackController {
  /// The current video player controller
  VideoPlayerController? currentController;
  
  /// The next video player controller (preloaded)
  VideoPlayerController? nextController;
  
  /// The current clip being played
  VideoClip? currentClip;
  
  /// Whether the video is playing
  bool isPlaying = false;
  
  /// Whether the video is loading
  bool isLoading = false;
  
  /// Whether this is the initial load
  bool isInitialLoad = true;
  
  /// Current playback position
  Duration currentPlaybackPosition = Duration.zero;
  
  /// Whether initial playback has started
  bool startedInitialPlayback = false;
  
  /// Timer for checking if buffer is ready
  Timer? nextClipCheckTimer;
  
  /// Timer for playback duration
  Timer? playbackTimer;
  
  /// Timer for tracking position
  Timer? positionTrackingTimer;
  
  /// Whether the controller is disposed
  bool isDisposed = false;
  
  /// Callback for when video is completed
  Function()? onVideoCompleted;
  
  /// Callback for when the queue needs updating
  Function()? onQueueUpdate;
  
  /// Toggle playback between play and pause
  void togglePlayback() {
    if (isLoading) return;
    
    final controller = currentController;
    if (controller == null) return;

    isPlaying = !isPlaying;
    
    if (isPlaying) {
      // Restore previous position before playing
      controller.seekTo(currentPlaybackPosition);
      controller.play();
      startPlaybackTimer();
    } else {
      controller.pause();
      playbackTimer?.cancel();
      positionTrackingTimer?.cancel();
    }
  }
  
  /// Start the playback timer to manage clip duration
  void startPlaybackTimer() {
    playbackTimer?.cancel();
    nextClipCheckTimer?.cancel();

    playbackTimer = Timer(Configuration.instance.actualClipPlaybackDuration, () {
      if (isDisposed || !isPlaying) return;
      
      onVideoCompleted?.call();
    });

    startPositionTracking();
  }
  
  /// Start tracking the video position
  void startPositionTracking() {
    positionTrackingTimer?.cancel();
    positionTrackingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (isDisposed || !isPlaying) return;
      
      final controller = currentController;
      if (controller != null && controller.value.isInitialized) {
        currentPlaybackPosition = controller.value.position;
      }
    });
  }

  /// Start checking for the next clip
  void startNextClipCheck() {
    nextClipCheckTimer?.cancel();
    nextClipCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (isDisposed || !isPlaying) {
        timer.cancel();
        return;
      }

      onQueueUpdate?.call();
    });
  }
  
  /// Log the current playback status (debug only)
  void logPlaybackStatus() {
    if (kDebugMode) {
      final controller = currentController;
      if (controller != null && controller.value.isInitialized) {
        final position = controller.value.position;
        final duration = controller.value.duration;
        debugPrint('Playback status: ${position.inSeconds}s / ${duration.inSeconds}s'
            ' (${isPlaying ? "playing" : "paused"})');
        debugPrint('Current clip: ${currentClip?.seed}, Next controller ready: ${nextController != null}');
      }
    }
  }
  
  /// Initialize a controller for a video clip
  Future<VideoPlayerController> initializeController(String videoUrl) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(videoUrl),
    );
    
    await controller.initialize();
    
    // Configure the controller
    controller.setLooping(true);
    controller.setVolume(0.0);
    controller.setPlaybackSpeed(Configuration.instance.clipPlaybackSpeed);
    
    return controller;
  }
  
  /// Prepare the controller to be disposed
  Future<void> dispose() async {
    isDisposed = true;
    
    playbackTimer?.cancel();
    nextClipCheckTimer?.cancel();
    positionTrackingTimer?.cancel();
    
    await currentController?.dispose();
    await nextController?.dispose();
    
    currentController = null;
    nextController = null;
  }
}