// lib/services/websocket_core_interface.dart

/// This file provides a subset of WebSocket functionality needed for the nano player
/// It's a simplified version that avoids exposing the entire WebSocketApiService
library;


/// WebSocketRequest model
class WebSocketRequest {
  /// Request identifier
  final String requestId;
  
  /// Action to perform
  final String action;
  
  /// Parameters for the action
  final Map<String, dynamic> params;

  /// Constructor
  WebSocketRequest({
    required this.requestId,
    required this.action,
    required this.params,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'action': action,
        ...params,
      };
}

/// Extension methods for the WebSocketApiService
extension WebSocketApiServiceExtensions on dynamic {
  /// Send a WebSocket request without waiting for a response
  Future<void> sendRequestWithoutResponse(WebSocketRequest request) async {
    // This method will be provided by the main WebSocketApiService class
    // It's just a stub for compilation purposes
    return Future.value();
  }
}