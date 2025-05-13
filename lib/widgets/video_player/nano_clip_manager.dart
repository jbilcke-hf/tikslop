// lib/widgets/video_player/nano_clip_manager.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:tikslop/models/video_result.dart';
import 'package:tikslop/services/clip_queue/video_clip.dart';
import 'package:tikslop/services/clip_queue/clip_states.dart';
import 'package:tikslop/services/websocket_api_service.dart';
import 'package:tikslop/utils/seed.dart';
import 'package:uuid/uuid.dart';

/// Manages a single video clip generation for thumbnail playback
class NanoClipManager {
  /// The video result for which the clip is being generated
  final VideoResult video;
  
  /// WebSocket service for API communication
  final WebSocketApiService _websocketService;
  
  /// Callback for when the clip is updated
  final void Function()? onClipUpdated;
  
  /// The generated video clip
  VideoClip? _videoClip;
  
  /// Whether the manager is disposed
  bool _isDisposed = false;
  
  /// Status text to show during generation
  String _statusText = 'Initializing...';
  
  /// Get the current video clip
  VideoClip? get videoClip => _videoClip;
  
  /// Get the current status text
  String get statusText => _statusText;
  
  /// Constructor
  NanoClipManager({
    required this.video,
    WebSocketApiService? websocketService,
    this.onClipUpdated,
  }) : _websocketService = websocketService ?? WebSocketApiService();
  
  /// Initialize and generate a single clip
  Future<void> initialize({
    int? overrideSeed,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isDisposed) return;
    
    try {
      // Use either provided seed, video's seed, or generate a new one
      final seed = overrideSeed ?? 
                  (video.useFixedSeed && video.seed > 0 ? video.seed : generateSeed());
      
      // Create a video clip
      _videoClip = VideoClip(
        prompt: "${video.title}\n${video.description}",
        seed: seed,
      );
      
      _updateStatus('Connecting...');
      
      // Set up WebSocket API service if needed
      if (_websocketService.status != ConnectionStatus.connected) {
        _updateStatus('Connecting to server...');
        await _websocketService.initialize();
        
        if (_isDisposed) return;
        
        if (_websocketService.status != ConnectionStatus.connected) {
          _updateStatus('Connection failed');
          _videoClip!.state = ClipState.failedToGenerate;
          return;
        }
      }
      
      _updateStatus('Requesting thumbnail...');
      
      // Set up timeout
      final completer = Completer<void>();
      Timer? timeoutTimer;
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          _updateStatus('Generation timed out');
          completer.complete();
        }
      });
      
      // Request the thumbnail generation
      try {
        // Create request for thumbnail generation
        final requestId = const Uuid().v4();
        
        // Mark as generating
        _videoClip!.state = ClipState.generationInProgress;
        
        // Initiate a request to generate a thumbnail
        // Using available methods in WebSocketApiService
        _generateThumbnail(seed, requestId).then((thumbnailData) {
          if (_isDisposed) return;
          
          if (thumbnailData != null && thumbnailData.isNotEmpty) {
            // Successful generation
            _videoClip!.base64Data = thumbnailData;
            _videoClip!.state = ClipState.generatedAndReadyToPlay;
            _updateStatus('Ready');
          } else {
            // Generation failed
            _videoClip!.state = ClipState.failedToGenerate;
            _updateStatus('Failed to generate');
          }
          
          completer.complete();
        }).catchError((error) {
          debugPrint('Error generating thumbnail: $error');
          _videoClip!.state = ClipState.failedToGenerate;
          _updateStatus('Error: $error');
          completer.complete();
        });
        
        // Wait for completion or timeout
        await completer.future;
        timeoutTimer.cancel();
        
      } catch (e) {
        // Handle any errors
        debugPrint('Error in thumbnail generation: $e');
        _videoClip!.state = ClipState.failedToGenerate;
        _updateStatus('Error generating');
        timeoutTimer.cancel();
      }
      
    } catch (e) {
      debugPrint('Error initializing nano clip: $e');
      _updateStatus('Error initializing');
    }
  }
  
  /// Generate a thumbnail using the WebSocketApiService
  Future<String?> _generateThumbnail(int seed, String requestId) async {
    if (_isDisposed) return null;
    
    // Show progress updates
    _simulateProgress();
    
    // If we're in debug mode and on web, we might need to mock the response
    if (kDebugMode && !_websocketService.isConnected) {
      await Future.delayed(const Duration(seconds: 3));
      return 'data:video/mp4;base64,AAAA'; // Mock base64 data
    }
    
    try {
      // Create a request to generate the thumbnail
      // We'll actually implement this using the VideoResult object since that's
      // what the API expects
      final result = await _websocketService.generateVideo(
        video,
        width: 512,       // Small size for thumbnail
        height: 288,      // 16:9 aspect ratio
        seed: seed,       // Use our specific seed
      );
      
      return result;
    } catch (e) {
      debugPrint('Error generating thumbnail through API: $e');
      if (kDebugMode) {
        // In debug mode, return mock data so development can continue
        return 'data:video/mp4;base64,AAAA';
      }
      return null;
    }
  }
  
  /// Simulate generation progress during development or when server is slow
  void _simulateProgress() {
    if (_isDisposed) return;
    
    const progressSteps = [
      {'delay': Duration(milliseconds: 500), 'progress': 20},
      {'delay': Duration(seconds: 1), 'progress': 40},
      {'delay': Duration(seconds: 2), 'progress': 60},
      {'delay': Duration(seconds: 3), 'progress': 80}
    ];
    
    // Show progress updates
    for (final step in progressSteps) {
      Future.delayed(step['delay'] as Duration, () {
        if (_isDisposed) return;
        _updateStatus('Generating (${step['progress']}%)');
      });
    }
  }
  
  /// Update the status text and notify listeners
  void _updateStatus(String status) {
    if (_isDisposed) return;
    _statusText = status;
    onClipUpdated?.call();
  }
  
  /// Dispose resources
  void dispose() {
    _isDisposed = true;
  }
}