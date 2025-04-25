/// Null implementation for html when not on web platform
/// This file is imported conditionally when not running on web

class Window {
  final Document document = Document();
  final History history = History();
  final Location location = Location();
  
  Stream<dynamic> get onBeforeUnload => 
      Stream.fromIterable([]).asBroadcastStream();
}

class Document {
  String get visibilityState => 'visible';
  
  Stream<dynamic> get onVisibilityChange => 
      Stream.fromIterable([]).asBroadcastStream();
}

class History {
  void pushState(dynamic data, String title, String url) {
    // No-op for non-web platforms
  }
}

class Location {
  String get href => '';
}

// Exported instances
final Window window = Window();
final Document document = Document();