// lib/widgets/video_player/lifecycle_manager.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// A mixin for managing video player lifecycle and visibility changes
/// Must be used on a State that implements WidgetsBindingObserver
mixin VideoPlayerLifecycleMixin<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  /// Whether video was playing before going to background
  bool _wasPlayingBeforeBackground = false;
  
  /// Whether the player is currently playing
  bool get isPlaying;
  
  /// Set the playing state
  set isPlaying(bool value);

  /// Sets up visibility listeners
  @override
  void initState() {
    super.initState();
    
    // Register as an observer to detect app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    
    // Add web-specific visibility change listener
    if (kIsWeb) {
      setupWebVisibilityListeners();
    }
  }
  
  /// Set up web-specific visibility listeners
  void setupWebVisibilityListeners();
  
  /// Handles visibility state changes
  void handleVisibilityChange();
  
  /// Toggles playback state
  void togglePlayback();
  
  /// Pauses video playback when app goes to background
  void pauseVideo() {
    if (isPlaying) {
      _wasPlayingBeforeBackground = true;
      togglePlayback();
    }
  }
  
  /// Resumes video playback when app comes to foreground
  void resumeVideo() {
    if (!isPlaying && _wasPlayingBeforeBackground) {
      _wasPlayingBeforeBackground = false;
      togglePlayback();
    }
  }
  
  /// Handles app lifecycle state changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes for native platforms
    if (!kIsWeb) {
      if (state == AppLifecycleState.paused || 
          state == AppLifecycleState.inactive || 
          state == AppLifecycleState.detached) {
        pauseVideo();
      } else if (state == AppLifecycleState.resumed && _wasPlayingBeforeBackground) {
        resumeVideo();
      }
    }
  }
  
  /// Clean up resources
  @override
  void dispose() {
    // Unregister the observer
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}