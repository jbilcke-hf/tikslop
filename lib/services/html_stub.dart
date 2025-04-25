/// Stub implementation for dart:html when not on web platform
/// This file is imported when dart.library.html is not available

class Window {
  final Document document = Document();
  final History history = History();
  final Location location = Location();
  final Storage localStorage = Storage();
  
  Stream<dynamic> get onBeforeUnload => 
      Stream.fromIterable([]).asBroadcastStream();
}

class Storage {
  final Map<String, String> _storage = {};
  
  String? operator [](String key) => _storage[key];
  
  void operator []=(String key, String value) {
    _storage[key] = value;
  }
  
  void clear() {
    _storage.clear();
  }
  
  void removeItem(String key) {
    _storage.remove(key);
  }
  
  String? getItem(String key) => _storage[key];
  
  void setItem(String key, String value) {
    _storage[key] = value;
  }
  
  int get length => _storage.length;
  
  String key(int index) {
    if (index < 0 || index >= _storage.length) return '';
    return _storage.keys.elementAt(index);
  }
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
  String get host => '';
  String get hostname => '';
  String get protocol => '';
  String get search => '';
  String get pathname => '';
}

// Exported instances
final Window window = Window();