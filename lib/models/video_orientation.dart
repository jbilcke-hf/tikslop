// lib/models/video_orientation.dart

/// Enum representing the orientation of a video clip.
enum VideoOrientation {
  /// Landscape orientation (horizontal, typically 16:9)
  LANDSCAPE,
  
  /// Portrait orientation (vertical, typically 9:16)
  PORTRAIT
}

/// Extension methods for VideoOrientation enum
extension VideoOrientationExtension on VideoOrientation {
  /// Get the string representation of the orientation
  String get name {
    switch (this) {
      case VideoOrientation.LANDSCAPE:
        return 'LANDSCAPE';
      case VideoOrientation.PORTRAIT:
        return 'PORTRAIT';
    }
  }
  
  /// Value for API communication
  String get value {
    return name;
  }
  
  /// Get the orientation from a string
  static VideoOrientation fromString(String? str) {
    if (str?.toUpperCase() == 'PORTRAIT') {
      return VideoOrientation.PORTRAIT;
    }
    return VideoOrientation.LANDSCAPE; // Default to landscape
  }
  
  /// Whether this orientation is portrait
  bool get isPortrait => this == VideoOrientation.PORTRAIT;
  
  /// Whether this orientation is landscape
  bool get isLandscape => this == VideoOrientation.LANDSCAPE;
}

/// Helper function to determine orientation from width and height
VideoOrientation getOrientationFromDimensions(int width, int height) {
  return width >= height ? VideoOrientation.LANDSCAPE : VideoOrientation.PORTRAIT;
}