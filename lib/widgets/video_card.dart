import 'package:flutter/material.dart';
import 'dart:convert';
import '../theme/colors.dart';
import '../models/video_result.dart';
import './video_player/index.dart';

class VideoCard extends StatelessWidget {
  final VideoResult video;

  const VideoCard({
    super.key,
    required this.video,
  });

  Widget _buildThumbnail() {
    if (video.thumbnailUrl.isEmpty) {
      return Container(
        color: AiTubeColors.surfaceVariant,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.movie_creation,
                color: AiTubeColors.onSurfaceVariant,
                size: 32,
              ),
              SizedBox(height: 8),
              Text(
                'Generating preview...',
                style: TextStyle(
                  color: AiTubeColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    try {
      // Handle image thumbnails
      if (video.thumbnailUrl.startsWith('data:image')) {
        final uri = Uri.parse(video.thumbnailUrl);
        final base64Data = uri.data?.contentAsBytes();
        
        if (base64Data == null) {
          debugPrint('Invalid image data in thumbnailUrl');
          throw Exception('Invalid image data');
        }

        return Image.memory(
          base64Data,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Error loading image thumbnail: $error');
            return _buildErrorThumbnail();
          },
        );
      }
      // Handle video thumbnails
      else if (video.thumbnailUrl.startsWith('data:video')) {
        return NanoVideoPlayer(
          video: video,
          autoPlay: true,
          muted: true,
          loop: true,
          borderRadius: 0,
          showLoadingIndicator: true,
          playbackSpeed: 0.7,
        );
      }
      // Regular URL thumbnail
      else if (video.thumbnailUrl.isNotEmpty) {
        return Image.network(
          video.thumbnailUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Error loading network thumbnail: $error');
            return _buildErrorThumbnail();
          },
        );
      } else {
        return _buildErrorThumbnail();
      }
    } catch (e) {
      debugPrint('Unexpected error in thumbnail rendering: $e');
      return _buildErrorThumbnail();
    }
  }

  Widget _buildErrorThumbnail() {
    return Container(
      color: AiTubeColors.surfaceVariant,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image,
              color: AiTubeColors.onSurfaceVariant,
              size: 32,
            ),
            SizedBox(height: 8),
            Text(
              'Preview unavailable',
              style: TextStyle(
                color: AiTubeColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildThumbnail(),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'LTX Video',
                          style: TextStyle(
                            color: AiTubeColors.onBackground,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: AiTubeColors.surface,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: AiTubeColors.surfaceVariant,
                  child: Icon(
                    Icons.play_arrow,
                    color: AiTubeColors.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        video.title,
                        style: const TextStyle(
                          color: AiTubeColors.onBackground,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Generated using LTX Video',
                        style: TextStyle(
                          color: AiTubeColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}