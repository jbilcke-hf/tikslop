// lib/widgets/video_player/buffer_manager.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:aitube2/config/config.dart';
import 'package:aitube2/services/clip_queue/video_clip.dart';
import 'package:aitube2/services/clip_queue/clip_queue_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:aitube2/models/video_result.dart';
import 'package:aitube2/models/video_orientation.dart';

/// Manages buffering and clip preloading for video player
class BufferManager {
  /// The queue manager for clips
  final ClipQueueManager queueManager;
  
  /// Whether the manager is disposed
  bool isDisposed = false;
  
  /// Loading progress (0.0 to 1.0)
  double loadingProgress = 0.0;
  
  /// Timer for showing loading progress
  Timer? progressTimer;
  
  /// Timer for debug printing
  Timer? debugTimer;
  
  /// The video result
  final VideoResult video;
  
  /// Callback when queue is updated
  final Function() onQueueUpdated;
  
  /// Constructor
  BufferManager({
    required this.video,
    required this.onQueueUpdated,
    ClipQueueManager? existingQueueManager,
  }) : queueManager = existingQueueManager ?? ClipQueueManager(
         video: video,
         onQueueUpdated: onQueueUpdated,
       );
  
  /// Initialize the buffer with clips
  Future<void> initialize() async {
    if (isDisposed) return;
    
    // Start loading progress animation
    startLoadingProgress();
    
    // Initialize queue manager but don't await it
    await queueManager.initialize();
  }
  
  /// Start loading progress animation
  void startLoadingProgress() {
    progressTimer?.cancel();
    loadingProgress = 0.0;
    
    const totalDuration = Duration(seconds: 12);
    const updateInterval = Duration(milliseconds: 50);
    final steps = totalDuration.inMilliseconds / updateInterval.inMilliseconds;
    final increment = 1.0 / steps;

    progressTimer = Timer.periodic(updateInterval, (timer) {
      if (isDisposed) {
        timer.cancel();
        return;
      }
      
      loadingProgress += increment;
      if (loadingProgress >= 1.0) {
        progressTimer?.cancel();
      }
    });
  }
  
  /// Start debug printing (for development)
  void startDebugPrinting() {
    debugTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!isDisposed) {
        queueManager.printQueueState();
      }
    });
  }
  
  /// Check if buffer is ready to start playback
  bool isBufferReadyToStartPlayback() {
    final readyClips = queueManager.clipBuffer.where((c) => c.isReady).length;
    final totalClips = queueManager.clipBuffer.length;
    final bufferPercentage = (readyClips / totalClips * 100);

    return bufferPercentage >= Configuration.instance.minimumBufferPercentToStartPlayback;
  }
  
  /// Ensure the buffer remains full
  void ensureBufferFull() {
    if (isDisposed) return;
    
    // Add additional safety check to avoid errors if the widget has been disposed
    // but this method is still being called by an ongoing operation
    try {
      queueManager.fillBuffer();
    } catch (e) {
      debugPrint('Error filling buffer: $e');
    }
  }
  
  /// Preload the next clip to ensure smooth playback
  Future<VideoPlayerController?> preloadNextClip() async {
    if (isDisposed) return null;

    VideoPlayerController? nextController;
    try {
      // Always try to preload the next ready clip
      final nextReadyClip = queueManager.nextReadyClip;
      
      if (nextReadyClip?.base64Data != null && 
          nextReadyClip != queueManager.currentClip && 
          !nextReadyClip!.isPlaying) {
        
        nextController = VideoPlayerController.networkUrl(
          Uri.parse(nextReadyClip.base64Data!),
        );

        await nextController.initialize();
        
        if (isDisposed) {
          nextController.dispose();
          return null;
        }

        // we always keep things looping. We never want any video to stop.
        nextController.setLooping(true);
        nextController.setVolume(0.0);
        nextController.setPlaybackSpeed(Configuration.instance.clipPlaybackSpeed);
        
        // Always ensure we're generating new clips after preloading
        // This is wrapped in a try-catch within ensureBufferFull now
        ensureBufferFull();
        
        return nextController;
      }
    } catch (e) {
      // Make sure we dispose any created controller if there was an error
      nextController?.dispose();
      debugPrint('Error preloading next clip: $e');
    }
    
    // Always ensure we're generating new clips after preloading
    // This is wrapped in a try-catch within ensureBufferFull now
    if (!isDisposed) {
      ensureBufferFull();
    }
    return null;
  }
  
  /// Update the orientation when device rotates
  Future<void> updateOrientation(VideoOrientation newOrientation) async {
    if (isDisposed) return;
    if (queueManager.currentOrientation == newOrientation) return;
    
    debugPrint('Updating video orientation to ${newOrientation.name}');
    
    // Start loading progress again as we'll be regenerating clips
    startLoadingProgress();
    
    // Update the orientation in the queue manager
    await queueManager.updateOrientation(newOrientation);
  }
  
  /// Dispose resources
  void dispose() {
    isDisposed = true;
    progressTimer?.cancel();
    debugTimer?.cancel();
  }
}