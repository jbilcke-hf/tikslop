import 'dart:async';
import 'package:flutter/foundation.dart';

// Platform-specific imports handling
import 'package:universal_html/html.dart' if (dart.library.io) 'package:aitube2/widgets/null_html.dart' as html;

/// Get URL parameters from the current URL (web only)
Map<String, String> getUrlParameters() {
  if (!kIsWeb) return {};
  
  final uri = Uri.parse(html.window.location.href);
  return uri.queryParameters;
}

/// Update URL parameters without page reload (web only)
void updateUrlParameter(String key, String value) {
  if (!kIsWeb) return;
  
  final uri = Uri.parse(html.window.location.href);
  final params = Map<String, String>.from(uri.queryParameters);
  
  // Update the parameter
  params[key] = value;
  
  // Create a new URL with updated parameters
  final newUri = uri.replace(queryParameters: params);
  
  // Update browser history without reloading the page
  html.window.history.pushState(null, '', newUri.toString());
}

/// Remove a URL parameter without page reload (web only)
void removeUrlParameter(String key) {
  if (!kIsWeb) return;
  
  final uri = Uri.parse(html.window.location.href);
  final params = Map<String, String>.from(uri.queryParameters);
  
  // Remove the parameter
  params.remove(key);
  
  // Create a new URL with updated parameters
  final newUri = uri.replace(queryParameters: params);
  
  // Update browser history without reloading the page
  html.window.history.pushState(null, '', newUri.toString());
}

/// Fallback implementation for non-web platforms
class NullHtml {
  // Mock objects to prevent build errors
  final window = Window();
  final document = Document();
}

// Mock implementation for html.window
class Window {
  final document = Document();
  final History history = History();
  
  Stream<dynamic> get onBeforeUnload => 
      Stream.fromIterable([]).asBroadcastStream();
  
  String get location => '';
}

// Mock implementation for html.History
class History {
  void pushState(dynamic data, String title, String url) {
    // No-op for non-web platforms
  }
}

// Mock implementation for html.document
class Document {
  String get visibilityState => 'visible';
  
  Stream<dynamic> get onVisibilityChange => 
      Stream.fromIterable([]).asBroadcastStream();
}