import 'dart:async';
import 'package:flutter/foundation.dart';

// Platform-specific imports handling
import 'package:universal_html/html.dart' if (dart.library.io) 'package:tikslop/services/html_stub.dart' as html;

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

// We now use the comprehensive html_stub.dart for non-web platforms
// All mock classes are now consolidated there