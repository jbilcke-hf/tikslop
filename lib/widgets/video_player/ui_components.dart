// lib/widgets/video_player/ui_components.dart

import 'package:flutter/material.dart';
import 'package:aitube2/theme/colors.dart';
import 'package:aitube2/widgets/ai_content_disclaimer.dart';
import 'package:aitube2/config/config.dart';

/// Builds a placeholder widget for when video is not loaded
Widget buildPlaceholder(String? initialThumbnailUrl) {
  // Use our new AI Content Disclaimer widget as the placeholder
  if (initialThumbnailUrl?.isEmpty ?? true) {
    // Set isInteractive to true as we generate content on-the-fly
    return const AiContentDisclaimer(isInteractive: true);
  }

  try {
    if (initialThumbnailUrl!.startsWith('data:image')) {
      final uri = Uri.parse(initialThumbnailUrl);
      final base64Data = uri.data?.contentAsBytes();
      
      if (base64Data == null) {
        throw Exception('Invalid image data');
      }

      return Image.memory(
        base64Data,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => buildErrorPlaceholder(),
      );
    }

    return Image.network(
      initialThumbnailUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => buildErrorPlaceholder(),
    );
  } catch (e) {
    return buildErrorPlaceholder();
  }
}

/// Builds an error placeholder for when image loading fails
Widget buildErrorPlaceholder() {
  return const Center(
    child: Icon(
      Icons.broken_image,
      size: 64,
      color: AiTubeColors.onSurfaceVariant,
    ),
  );
}

/// Builds a buffer status indicator widget
Widget buildBufferStatus({
  required bool showDuringLoading,
  required bool isLoading,
  required List<dynamic> clipBuffer,
}) {
  final readyOrPlayingClips = clipBuffer.where((c) => c.isReady || c.isPlaying).length;
  final totalClips = clipBuffer.length;
  final bufferPercentage = (readyOrPlayingClips / totalClips * 100).round();

  // since we are playing clips at a reduced speed, they each last "longer"
  // eg a video playing back at 0.5 speed will see its duration multiplied by 2
  final actualDurationPerClip = Configuration.instance.actualClipPlaybackDuration;

  final remainingSeconds = readyOrPlayingClips * actualDurationPerClip.inSeconds;

  // Don't show 0% during initial loading
  if (!showDuringLoading && bufferPercentage == 0) {
    return const SizedBox.shrink();
  }

  return Positioned(
    right: 16,
    bottom: 16,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getBufferIcon(bufferPercentage),
            color: _getBufferStatusColor(bufferPercentage),
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            isLoading 
              ? 'Buffering $bufferPercentage%'
              : '$bufferPercentage% (${remainingSeconds}s)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Get icon for buffer status based on percentage
IconData _getBufferIcon(int percentage) {
  if (percentage >= 40) return Icons.network_wifi;
  if (percentage >= 30) return Icons.network_wifi_3_bar;
  if (percentage >= 20) return Icons.network_wifi_2_bar;
  return Icons.network_wifi_1_bar;
}

/// Get color for buffer status based on percentage
Color _getBufferStatusColor(int percentage) {
  if (percentage >= 30) return Colors.green;
  if (percentage >= 20) return Colors.orange;
  return Colors.red;
}

/// Formats queue statistics for display
String formatQueueStats(dynamic queueManager) {
  final stats = queueManager.getBufferStats();
  final currentClipInfo = queueManager.currentClip != null 
      ? '\nPlaying: ${queueManager.currentClip!.seed}'
      : '';
  final nextClipInfo = stats['nextControllerReady'] == true
      ? '\nNext clip preloaded'
      : '';
  
  return 'Queue: ${stats['readyClips']}/${stats['bufferSize']} ready\n'
         'Gen: ${stats['activeGenerations']} active'
         '$currentClipInfo$nextClipInfo';
}

/// Builds a play/pause button overlay
Widget buildPlayPauseButton({
  required bool isPlaying,
  required VoidCallback onTap,
}) {
  return Positioned(
    left: 16,
    bottom: 16,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
          size: 24,
        ),
      ),
    ),
  );
}