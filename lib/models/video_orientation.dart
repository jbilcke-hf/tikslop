// lib/models/video_orientation.dart

/// Enum representing the orientation of a video clip.
enum VideoOrientation {
  /// Landscape orientation (horizontal, typically 16:9)
  landscape,
  
  /// Portrait orientation (vertical, typically 9:16)
  portrait
}

/// Extension methods for VideoOrientation enum
extension VideoOrientationExtension on VideoOrientation {
  /// Get the string representation of the orientation
  String get name {
    switch (this) {
      case VideoOrientation.landscape:
        return 'landscape';
      case VideoOrientation.portrait:
        return 'portrait';
    }
  }
  
  /// Get the orientation from a string
  static VideoOrientation fromString(String? str) {
    if (str?.toLowerCase() == 'portrait') {
      return VideoOrientation.portrait;
    }
    return VideoOrientation.landscape; // Default to landscape
  }
  
  /// Whether this orientation is portrait
  bool get isPortrait => this == VideoOrientation.portrait;
  
  /// Whether this orientation is landscape
  bool get isLandscape => this == VideoOrientation.landscape;
}