// Mock implementations for non-web platforms

class Window {
  final document = Document();
  final history = History();
  final location = Location();
  
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
final window = Window();
final document = Document();