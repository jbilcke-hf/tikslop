import 'dart:async';
import 'dart:io' as io;
// For web platform, conditionally import http instead of HttpClient
import 'package:http/http.dart' as http;
import 'package:tikslop/services/settings_service.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:convert';
// Conditionally import html for web platform with proper handling
import 'html_stub.dart' if (dart.library.html) 'dart:html' as html;
import 'package:tikslop/config/config.dart';
import 'package:tikslop/models/chat_message.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/search_state.dart';
import '../models/video_result.dart';
import '../models/video_orientation.dart';

class WebSocketRequest {
  final String requestId;
  final String action;
  final Map<String, dynamic> params;

  WebSocketRequest({
    String? requestId,
    required this.action,
    required this.params,
  }) : requestId = requestId ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'action': action,
        ...params,
      };
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
  maintenance
}

class WebSocketApiService {
  // Singleton implementation
  static final WebSocketApiService _instance = WebSocketApiService._internal();
  factory WebSocketApiService() => _instance;
  WebSocketApiService._internal();

  // Dynamically build WebSocket URL based on current host in web platform
  // or use environment variable/production URL/localhost for development on other platforms
  static String get _wsUrl {
    if (kIsWeb) {
      // Get the current host and protocol from the browser window
      final location = Uri.base;
      final protocol = location.scheme == 'https' ? 'wss' : 'ws';
      
      // For localhost, explicitly include port 8080
      if (location.host == 'localhost' || location.host.startsWith('localhost:')) {
        final url = '$protocol://localhost:8080/ws';
        debugPrint('WebSocketApiService: Using localhost:8080 WebSocket URL: $url');
        return url;
      }
      
      // For other hosts, include the original port number in the URL
      final url = '$protocol://${location.host}/ws';
      debugPrint('WebSocketApiService: Using dynamic WebSocket URL: $url');
      return url;
    } else {
      // First try to get WebSocket URL from environment variable (highest priority)
      const envWsUrl = String.fromEnvironment('API_WS_URL', defaultValue: '');
      
      if (envWsUrl.isNotEmpty) {
        debugPrint('WebSocketApiService: Using WebSocket URL from environment: $envWsUrl');
        return envWsUrl;
      }
      
      // Second, check if we're in production mode (determined by build flag)
      const isProduction = bool.fromEnvironment('PRODUCTION_MODE', defaultValue: false);
      
      if (isProduction) {
        // Production default is tikslop.com
        const productionUrl = 'wss://tikslop.com/ws';
        debugPrint('WebSocketApiService: Using production WebSocket URL: $productionUrl');
        return productionUrl;
      } else {
        // Fallback to localhost for development
        debugPrint('WebSocketApiService: Using default localhost WebSocket URL');
        return 'ws://localhost:8080/ws';
      }
    }
  }
  WebSocketChannel? _channel;
  final _responseController = StreamController<Map<String, dynamic>>.broadcast();
  final _pendingRequests = <String, Completer<Map<String, dynamic>>>{};
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);
  static bool _initialized = false;

  final _connectionLock = Lock();
  final _disposeLock = Lock();
  final bool _isReconnecting = false;
  
  final _chatController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get chatStream => _chatController.stream;
  
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isInMaintenance => _status == ConnectionStatus.maintenance;

  SearchState? _currentSearchState;
  final _searchController = StreamController<VideoResult>.broadcast();
  final _activeSearches = <String, bool>{};
  static const int maxFailedAttempts = 3;
  static const int maxResults = 4;

  Stream<VideoResult> get searchStream => _searchController.stream;

  static const Duration _minRequestInterval = Duration(milliseconds: 100);
  DateTime _lastRequestTime = DateTime.now();
  final _activeRequests = <String, bool>{};

  final _subscribers = <String, int>{};

  // Track the user role
  String _userRole = 'anon';
  String get userRole => _userRole;
  
  // Stream to notify listeners when user role changes
  final _userRoleController = StreamController<String>.broadcast();
  Stream<String> get userRoleStream => _userRoleController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      debugPrint('WebSocketApiService: Initializing and connecting...');
      await connect();
      
      // Only continue if we're properly connected
      if (_status != ConnectionStatus.connected) {
        debugPrint('WebSocketApiService: Connection not established, status: $_status');
        return;
      }
      
      try {
        // Request user role after connection
        await _requestUserRole();
      } catch (e) {
        // Handle the case where we fail to get user role due to device connection limit
        if (e.toString().contains('Device connection limit exceeded')) {
          // We've already set the appropriate status, just return
          return;
        }
        // Otherwise rethrow
        rethrow;
      }
      
      _initialized = true;
      debugPrint('WebSocketApiService: Successfully initialized, status: $_status');
    } catch (e) {
      debugPrint('Failed to initialize WebSocketApiService: $e');
      rethrow;
    }
  }
  
  Future<void> _requestUserRole() async {
    try {
      final response = await _sendRequest(
        WebSocketRequest(
          action: 'get_user_role',
          params: {},
        ),
        timeout: const Duration(seconds: 5),
      );
      
      if (response['success'] == true && response['user_role'] != null) {
        _userRole = response['user_role'] as String;
        _userRoleController.add(_userRole);
        debugPrint('WebSocketApiService: User role set to $_userRole');
        
        // Now that we know the role, check device connection limit for non-anonymous users
        if (kIsWeb && _userRole != 'anon') {
          final connectionAllowed = _checkAndRegisterDeviceConnection();
          if (!connectionAllowed) {
            _isDeviceLimitExceeded = true;
            _deviceLimitController.add(true);
            _setStatus(ConnectionStatus.error);
            throw Exception('Device connection limit exceeded');
          }
        }
      }
    } catch (e) {
      debugPrint('WebSocketApiService: Failed to get user role: $e');
      rethrow;
    }
  }

  // New status for anonymous users exceeding connection limit
  bool _isAnonLimitExceeded = false;
  bool get isAnonLimitExceeded => _isAnonLimitExceeded;
  
  // Status for VIP users exceeding device connection limit (web only)
  bool _isDeviceLimitExceeded = false;
  bool get isDeviceLimitExceeded => _isDeviceLimitExceeded;
  
  // Message to display when anonymous limit is exceeded
  String _anonLimitMessage = '';
  String get anonLimitMessage => _anonLimitMessage;
  
  // Message to display when device limit is exceeded
  final String _deviceLimitMessage = 'Too many connections from this device. Please close other tabs running TikSlop.';
  String get deviceLimitMessage => _deviceLimitMessage;
  
  // Stream to notify listeners when anonymous limit status changes
  final _anonLimitController = StreamController<bool>.broadcast();
  Stream<bool> get anonLimitStream => _anonLimitController.stream;
  
  // Stream to notify listeners when device limit status changes
  final _deviceLimitController = StreamController<bool>.broadcast();
  Stream<bool> get deviceLimitStream => _deviceLimitController.stream;
  
  // Constants for device connection limits
  static const String _connectionCountKey = 'tikslop_connection_count';
  static const String _connectionIdKey = 'tikslop_connection_id';
  static const int _maxDeviceConnections = 3; // Maximum number of tabs/connections per device
  static const Duration _connectionHeartbeatInterval = Duration(seconds: 10);
  Timer? _connectionHeartbeatTimer;
  String? _connectionId;
  
  // Function to check and register device connection (web only)
  bool _checkAndRegisterDeviceConnection() {
    if (!kIsWeb) return true; // Only apply on web platform
    
    try {
      // Generate a unique ID for this connection instance
      if (_connectionId == null) {
        _connectionId = const Uuid().v4();
        
        // Store connection ID in localStorage
        html.window.localStorage[_connectionIdKey] = _connectionId!;
      }
      
      // Get current connection count from localStorage
      final countJson = html.window.localStorage[_connectionCountKey];
      Map<String, dynamic> connections = {};
      
      if (countJson != null && countJson.isNotEmpty) {
        try {
          connections = json.decode(countJson) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('Error parsing connection count: $e');
          connections = {};
        }
      }
      
      // Clean up stale connections (older than 30 seconds)
      final now = DateTime.now().millisecondsSinceEpoch;
      connections.removeWhere((key, value) {
        if (value is! int) return true;
        return now - value > 30000; // 30 seconds timeout
      });
      
      // Add/update this connection
      connections[_connectionId!] = now;
      
      // Store back to localStorage
      html.window.localStorage[_connectionCountKey] = json.encode(connections);
      
      // Check if we're exceeding the limit, but only for non-anonymous users
      // For anonymous users, we rely on the server-side IP check
      if (_userRole != 'anon' && connections.length > _maxDeviceConnections) {
        debugPrint('Device connection limit exceeded: ${connections.length} connections for $_userRole user');
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('Error checking device connections: $e');
      return true; // Default to allowing connection on error
    }
  }
  
  // Function to update the connection heartbeat
  void _updateConnectionHeartbeat() {
    if (!kIsWeb || _connectionId == null) return;
    
    try {
      // Get current connection count
      final countJson = html.window.localStorage[_connectionCountKey];
      Map<String, dynamic> connections = {};
      
      if (countJson != null && countJson.isNotEmpty) {
        try {
          connections = json.decode(countJson) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('Error parsing connection count: $e');
          connections = {};
        }
      }
      
      // Update timestamp for this connection
      final now = DateTime.now().millisecondsSinceEpoch;
      connections[_connectionId!] = now;
      
      // Store back to localStorage
      html.window.localStorage[_connectionCountKey] = json.encode(connections);
    } catch (e) {
      debugPrint('Error updating connection heartbeat: $e');
    }
  }
  
  // Function to unregister this connection
  void _unregisterDeviceConnection() {
    if (!kIsWeb || _connectionId == null) return;
    
    try {
      // Get current connection count
      final countJson = html.window.localStorage[_connectionCountKey];
      Map<String, dynamic> connections = {};
      
      if (countJson != null && countJson.isNotEmpty) {
        try {
          connections = json.decode(countJson) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('Error parsing connection count: $e');
          connections = {};
        }
      }
      
      // Remove this connection
      connections.remove(_connectionId);
      
      // Store back to localStorage
      html.window.localStorage[_connectionCountKey] = json.encode(connections);
      
      // Stop the heartbeat timer
      _connectionHeartbeatTimer?.cancel();
      _connectionHeartbeatTimer = null;
    } catch (e) {
      debugPrint('Error unregistering device connection: $e');
    }
  }
  
  // Start the connection heartbeat timer
  void _startConnectionHeartbeat() {
    if (!kIsWeb) return;
    
    _connectionHeartbeatTimer?.cancel();
    _connectionHeartbeatTimer = Timer.periodic(_connectionHeartbeatInterval, (timer) {
      _updateConnectionHeartbeat();
    });
  }

  Future<void> connect() async {
    if (_disposed) {
      throw Exception('WebSocketApiService has been disposed');
    }

    // Reset limit exceeded statuses on connection attempt
    _isAnonLimitExceeded = false;
    _isDeviceLimitExceeded = false;
    
    // Check device connection limit (for web only, but only after determining user role)
    // We'll check again after getting the actual role, this is just to prevent excessive connections
    if (kIsWeb) {
      final connectionAllowed = _checkAndRegisterDeviceConnection();
      if (!connectionAllowed) {
        _isDeviceLimitExceeded = true;
        _deviceLimitController.add(true);
        _setStatus(ConnectionStatus.error);
        throw Exception('Device connection limit exceeded');
      }
    }

    // Prevent multiple simultaneous connection attempts
    return _connectionLock.synchronized(() async {
      if (_status == ConnectionStatus.connected) {
        // debugPrint('WebSocketApiService: Already connected, skipping connection attempt');
        return;
      }
      
      if (_status == ConnectionStatus.connecting) {
        // debugPrint('WebSocketApiService: Connection already in progress, waiting...');
        
        // Wait for a short time to see if connection completes
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (_status == ConnectionStatus.connected) {
            // debugPrint('WebSocketApiService: Connection completed while waiting');
            return;
          }
          if (_status == ConnectionStatus.error || _status == ConnectionStatus.maintenance) {
            debugPrint('WebSocketApiService: Connection failed while waiting with status: $_status');
            throw Exception('Connection attempt failed with status: $_status');
          }
        }
        
        // If still connecting after waiting, we'll try again
        debugPrint('WebSocketApiService: Previous connection attempt timed out, trying again');
      }

      try {
        _setStatus(ConnectionStatus.connecting);
        // debugPrint('WebSocketApiService: Setting status to CONNECTING');
        
        // Close existing channel if any
        await _channel?.sink.close();
        _channel = null;
        
        // Get the HF API key if available
        final settings = SettingsService();
        final hfApiKey = settings.huggingfaceApiKey;
        
        // Construct the connection URL with the API key as a query parameter if available
        final baseUrl = Uri.parse(_wsUrl);
        final connectionUrl = hfApiKey.isNotEmpty 
            ? baseUrl.replace(queryParameters: {'hf_token': hfApiKey}) 
            : baseUrl;
        
        debugPrint('WebSocketApiService: Connecting to WebSocket with API key: ${hfApiKey.isNotEmpty ? 'provided' : 'not provided'}');
        
        // First check if server is in maintenance mode by making an HTTP request to the status endpoint
        try {
          // Determine HTTP URL based on WebSocket URL and current location
          String httpUrl;
          if (kIsWeb) {
            // In web, use the current location with api/status appended
            final location = Uri.base;
            final protocol = location.scheme;
            
            // For localhost, explicitly include port 8080
            if (location.host == 'localhost' || location.host.startsWith('localhost:')) {
              httpUrl = '$protocol://localhost:8080/api/status';
            } else {
              httpUrl = '$protocol://${location.host}/api/status';
            }
          } else {
            // For non-web, derive from WebSocket URL
            final wsUri = Uri.parse(_wsUrl);
            final protocol = wsUri.scheme == 'wss' ? 'https' : 'http';
            httpUrl = '$protocol://${wsUri.authority}/api/status';
          }
          
          debugPrint('WebSocketApiService: Checking maintenance status at: $httpUrl');
          
          // Use conditional import to handle platform differences
          if (kIsWeb) {
            // For web platform, use http package instead of HttpClient which is only available in dart:io
            final response = await http.get(Uri.parse(httpUrl));
            
            if (response.statusCode == 200) {
              final statusData = jsonDecode(response.body);
              
              if (statusData['maintenance_mode'] == true) {
                debugPrint('WebSocketApiService: Server is in maintenance mode');
                _setStatus(ConnectionStatus.maintenance);
                return;
              }
            }
          } else {
            // For non-web platforms, use HttpClient from dart:io
            final httpClient = io.HttpClient();
            final request = await httpClient.getUrl(Uri.parse(httpUrl));
            final response = await request.close();
            
            if (response.statusCode == 200) {
              final responseBody = await response.transform(utf8.decoder).join();
              final statusData = jsonDecode(responseBody);
              
              if (statusData['maintenance_mode'] == true) {
                debugPrint('WebSocketApiService: Server is in maintenance mode');
                _setStatus(ConnectionStatus.maintenance);
                return;
              }
            }
          }
        } catch (e) {
          debugPrint('WebSocketApiService: Failed to check maintenance status: $e');
          // Continue with connection attempt even if status check fails
        }
        
        try {
          debugPrint('WebSocketApiService: Creating WebSocket channel...');
          _channel = WebSocketChannel.connect(connectionUrl);
        } catch (e) {
          debugPrint('WebSocketApiService: Failed to create WebSocket channel: $e');
          
          // If connection fails and we were using an API key, try without it
          if (hfApiKey.isNotEmpty) {
            debugPrint('WebSocketApiService: Retrying connection without API key');
            _channel = WebSocketChannel.connect(baseUrl);
          } else {
            _setStatus(ConnectionStatus.error);
            rethrow;
          }
        }
        
        // Wait for connection with proper error handling
        try {
          debugPrint('WebSocketApiService: Waiting for connection ready signal...');
          await _channel!.ready.timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('WebSocketApiService: Connection timeout');
              _setStatus(ConnectionStatus.error);
              throw TimeoutException('Connection timeout');
            },
          );
          debugPrint('WebSocketApiService: Connection ready signal received!');
        } catch (e) {
          debugPrint('WebSocketApiService: Connection failed: $e');
          
          String errorMessage = e.toString();
          
          // Check for anonymous user connection limit exceeded
          if (errorMessage.contains('429') && (errorMessage.contains('anon_limit_exceeded') || 
              errorMessage.contains('Anonymous user limit exceeded'))) {
            debugPrint('WebSocketApiService: Anonymous user connection limit exceeded');
            
            // Try to extract the error message from the response
            String errorMsg = 'Anonymous users can enjoy 1 stream per IP address. If you are on a shared IP please enter your HF token, thank you!';
            
            try {
              // Extract JSON content from the error message if available
              final match = RegExp(r'\{.*\}').firstMatch(errorMessage);
              if (match != null) {
                final jsonStr = match.group(0);
                if (jsonStr != null) {
                  final errorData = json.decode(jsonStr);
                  if (errorData['message'] != null) {
                    errorMsg = errorData['message'];
                  }
                }
              }
            } catch (_) {
              // If parsing fails, use the default message
            }
            
            _setStatus(ConnectionStatus.error);
            _isAnonLimitExceeded = true;
            _anonLimitMessage = errorMsg;
            _anonLimitController.add(true);
            
            // We don't rethrow here - we want to handle this specific error differently
            return;
          }
          
          // If server sent a 503 response with maintenance mode indication
          if (errorMessage.contains('503') && errorMessage.contains('maintenance')) {
            debugPrint('WebSocketApiService: Server is in maintenance mode');
            _setStatus(ConnectionStatus.maintenance);
            return;
          }
          
          // If connection fails and we were using an API key, try without it
          if (hfApiKey.isNotEmpty) {
            debugPrint('WebSocketApiService: Retrying connection without API key after ready timeout');
            
            // Close the failed channel
            await _channel?.sink.close();
            
            // Try connecting without the API key
            _channel = WebSocketChannel.connect(baseUrl);
            
            try {
              await _channel!.ready.timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  _setStatus(ConnectionStatus.error);
                  throw TimeoutException('Connection timeout on fallback attempt');
                },
              );
            } catch (retryError) {
              // Check again for maintenance mode or anonymous limit
              final retryErrorMsg = retryError.toString();
              
              if (retryErrorMsg.contains('429') && (retryErrorMsg.contains('anon_limit_exceeded') || 
                  retryErrorMsg.contains('Anonymous user limit exceeded'))) {
                debugPrint('WebSocketApiService: Anonymous user connection limit exceeded on retry');
                
                // Try to extract the error message from the response
                String errorMsg = 'Anonymous users can enjoy 1 stream per IP address. If you are on a shared IP please enter your HF token, thank you!';
                
                try {
                  // Extract JSON content from the error message if available
                  final match = RegExp(r'\{.*\}').firstMatch(retryErrorMsg);
                  if (match != null) {
                    final jsonStr = match.group(0);
                    if (jsonStr != null) {
                      final errorData = json.decode(jsonStr);
                      if (errorData['message'] != null) {
                        errorMsg = errorData['message'];
                      }
                    }
                  }
                } catch (_) {
                  // If parsing fails, use the default message
                }
                
                _setStatus(ConnectionStatus.error);
                _isAnonLimitExceeded = true;
                _anonLimitMessage = errorMsg;
                _anonLimitController.add(true);
                return;
              }
              
              if (retryErrorMsg.contains('503') && retryErrorMsg.contains('maintenance')) {
                debugPrint('WebSocketApiService: Server is in maintenance mode on retry');
                _setStatus(ConnectionStatus.maintenance);
                return;
              }
              
              debugPrint('WebSocketApiService: Fallback connection also failed: $retryError');
              _setStatus(ConnectionStatus.error);
              rethrow;
            }
          } else {
            _setStatus(ConnectionStatus.error);
            rethrow;
          }
        }
        
        // Setup stream listener with error handling
        // debugPrint('WebSocketApiService: Setting up stream listeners...');
        _channel!.stream.listen(
          _handleMessage,
          onError: _handleError,
          onDone: _handleDisconnect,
          cancelOnError: true,
        );

        _startHeartbeat();
        // Start the device connection heartbeat for web (we'll only apply limits to VIP users)
        if (kIsWeb) {
          _startConnectionHeartbeat();
        }
        
        // debugPrint('WebSocketApiService: Setting status to CONNECTED');
        _setStatus(ConnectionStatus.connected);
        _reconnectAttempts = 0;
        
        // Clear limit flags if we successfully connected
        if (_isAnonLimitExceeded) {
          _isAnonLimitExceeded = false;
          _anonLimitController.add(false);
        }
        
        if (_isDeviceLimitExceeded) {
          _isDeviceLimitExceeded = false;
          _deviceLimitController.add(false);
        }
        
        debugPrint('WebSocketApiService: Connection completed successfully');
      } catch (e) {
        // Check if the error indicates maintenance mode
        if (e.toString().contains('maintenance')) {
          debugPrint('WebSocketApiService: Server is in maintenance mode');
          _setStatus(ConnectionStatus.maintenance);
        } else {
          debugPrint('WebSocketApiService: Connection error: $e');
          _setStatus(ConnectionStatus.error);
          rethrow;
        }
      }
    });
  }

   void addSubscriber(String id) {
    _subscribers[id] = (_subscribers[id] ?? 0) + 1;
    // debugPrint('WebSocket subscriber added: $id (total: ${_subscribers[id]})');
  }

  void removeSubscriber(String id) {
    if (_subscribers.containsKey(id)) {
      _subscribers[id] = _subscribers[id]! - 1;
      if (_subscribers[id]! <= 0) {
        _subscribers.remove(id);
      }
      // debugPrint('WebSocket subscriber removed: $id (remaining: ${_subscribers[id] ?? 0})');
    }
  }

  Future<void> joinChatRoom(String videoId) async {
   // debugPrint('WebSocketApiService: Attempting to join chat room: $videoId');
    
    if (!isConnected) {
      // debugPrint('WebSocketApiService: Not connected, connecting first...');
      await connect();
    }
    
    try {
      final response = await _sendRequest(
        WebSocketRequest(
          action: 'join_chat',
          params: {'videoId': videoId},
        ),
        timeout: const Duration(seconds: 10),
      );

      // debugPrint('WebSocketApiService: Join chat room response received: $response');

      if (!response['success']) {
        final error = response['error'] ?? 'Failed to join chat room';
        debugPrint('WebSocketApiService: Join chat room failed: $error');
        throw Exception(error);
      }

      // Process chat history if provided
      if (response['messages'] != null) {
        _handleChatHistory(response);
      }

      // debugPrint('WebSocketApiService: Successfully joined chat room: $videoId');
    } catch (e) {
      debugPrint('WebSocketApiService: Error joining chat room: $e');
      rethrow;
    }
  }


  Future<void> leaveChatRoom(String videoId) async {
    if (!isConnected) return;

    try {
      await _sendRequest(
        WebSocketRequest(
          action: 'leave_chat',
          params: {'videoId': videoId},
        ),
        timeout: const Duration(seconds: 5),
      );
      // debugPrint('Successfully left chat room: $videoId');
    } catch (e) {
      debugPrint('Failed to leave chat room: $e');
    }
  }

  ////// ---- OLD VERSION OF THE CODE ------
  ///
 

  Future<void> startContinuousSearch(String query) async {
    if (!_initialized) {
      await initialize();
    }

    debugPrint('Starting continuous search for query: $query');
    _activeSearches[query] = true;
    _currentSearchState = SearchState(query: query);
    int failedAttempts = 0;

    while (_activeSearches[query] == true && 
          !_disposed && 
          failedAttempts < maxFailedAttempts && 
          (_currentSearchState?.resultCount ?? 0) < maxResults) {
      try {
        final response = await _sendRequest(
          WebSocketRequest(
            action: 'search',
            params: {
              'query': query,
              'attemptCount': failedAttempts,
            },
          ),
          timeout: const Duration(seconds: 30),
        );

        if (_disposed || _activeSearches[query] != true) break;

        if (response['success'] == true && response['result'] != null) {
          final result = VideoResult.fromJson(response['result'] as Map<String, dynamic>);
          _searchController.add(result);
          _currentSearchState = _currentSearchState?.incrementCount();
          failedAttempts = 0;
        } else {
          failedAttempts++;
          debugPrint('Search attempt $failedAttempts failed for query: $query. Error: ${response['error']}');
        }
      } catch (e) {
        failedAttempts++;
        debugPrint('Search error (attempt $failedAttempts): $e');
        
        if (failedAttempts < maxFailedAttempts) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    _activeSearches[query] = false;
    
    if (_disposed) {
      // debugPrint('Search terminated: Service disposed');
    } else if (failedAttempts >= maxFailedAttempts) {
      // debugPrint('Search terminated: Max failures ($maxFailedAttempts) reached');
    } else if ((_currentSearchState?.resultCount ?? 0) >= maxResults) {
      // debugPrint('Search terminated: Max results ($maxResults) reached');
    } else {
      // debugPrint('Search terminated: Search cancelled');
    }
  }

  void stopContinuousSearch(String query) {
    _activeSearches[query] = false;
  }

  String get statusMessage {
    switch (_status) {
      case ConnectionStatus.disconnected:
        return 'Disconnected';
      case ConnectionStatus.connecting:
        return 'Connected...'; // Make connecting status appear like connected to show green
      case ConnectionStatus.connected:
        return _userRole == 'anon' ? 'Connected as anon' : 'Connected as $_userRole';
      case ConnectionStatus.reconnecting:
        return 'Connection lost. Attempting to reconnect (${_reconnectAttempts + 1}/$_maxReconnectAttempts)...';
      case ConnectionStatus.error:
        return 'Failed to connect';
      case ConnectionStatus.maintenance:
        return 'Server is in maintenance mode';
    }
  }

  void _setStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
      
      // Force an additional status emission for UI updates
      // This ensures Flutter's reactive system picks up the change
      Future.microtask(() {
        if (!_statusController.isClosed && _status == newStatus) {
          _statusController.add(newStatus);
        }
      });
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (isConnected) {
        _channel?.sink.add(json.encode({
          'action': 'heartbeat',
          'requestId': const Uuid().v4(),
        }));
      }
    });
  }

  Future<bool> sendChatMessage(ChatMessage message) async {
    if (_disposed) {
      debugPrint('WebSocketApiService: Cannot send message, service is disposed');
      throw Exception('WebSocketApiService is disposed');
    }
    
    if (!_initialized) {
      debugPrint('WebSocketApiService: Initializing before sending message...');
      await initialize();
    }

    try {
      debugPrint('WebSocketApiService: Sending chat message...');
      
      // Check if the chatController is still open to avoid "Cannot add events after calling close" error
      if (_chatController.isClosed) {
        debugPrint('WebSocketApiService: Chat controller is closed, cannot process messages');
        throw Exception('Chat controller is closed');
      }
      
      final response = await _sendRequest(
        WebSocketRequest(
          action: 'chat_message',
          params: {
            'videoId': message.videoId,
            ...message.toJson(),
          },
        ),
        timeout: const Duration(seconds: 10),
      );

      if (!response['success']) {
        debugPrint('WebSocketApiService: Server returned error: ${response['error']}');
        throw Exception(response['error'] ?? 'Failed to send message');
      }

      debugPrint('WebSocketApiService: Message sent successfully');
      return true;
    } catch (e) {
      debugPrint('WebSocketApiService: Error in sendChatMessage: $e');
      rethrow;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message as String) as Map<String, dynamic>;
      final action = data['action'] as String?;
      final requestId = data['requestId'] as String?;

      debugPrint('WebSocketApiService: Received message for action: $action, requestId: $requestId');
      
      // Update user role if present in response (from heartbeat or get_user_role)
      if (data['user_role'] != null) {
        final newRole = data['user_role'] as String;
        if (_userRole != newRole) {
          _userRole = newRole;
          _userRoleController.add(_userRole);
          debugPrint('WebSocketApiService: User role updated to $_userRole');
        }
      }

      if (requestId != null && _pendingRequests.containsKey(requestId)) {
        if (action == 'chat_message') {
          debugPrint('WebSocketApiService: Processing chat message response');
          // Don't process the message data from our own request since we already added it locally
          // We only need to complete the request to signal success/failure
          _pendingRequests[requestId]!.complete(data);
        } else if (action == 'join_chat') {
          debugPrint('WebSocketApiService: Processing join chat response');
          _pendingRequests[requestId]!.complete(data);
        } else if (action == 'search' && data['success'] == true && data['result'] != null) {
          final result = VideoResult.fromJson(data['result'] as Map<String, dynamic>);
          
          // Complete the pending request but don't add to search results here
          // The search results will be handled by the startContinuousSearch method
          _pendingRequests[requestId]!.complete(data);
          
          // Don't add to search controller here to avoid duplicates
          // _searchController.add(result);
        } else {
          // debugPrint('WebSocketApiService: Processing generic response');
          _pendingRequests[requestId]!.complete(data);
        }
        
        _cleanup(requestId);
      } else if (action == 'chat_message' && data['broadcast'] == true) {
        // For broadcast messages, the message is directly in the data
        debugPrint('WebSocketApiService: Processing chat broadcast');
        _handleChatMessage(data);
      }
      
    } catch (e, stackTrace) {
      debugPrint('WebSocketApiService: Error handling message: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _handleChatMessage(Map<String, dynamic> data) {
    if (_disposed) {
      debugPrint('WebSocketApiService: Skipping message handling, service is disposed');
      return;
    }
    
    try {
      // Log the exact data we're trying to parse
      debugPrint('Parsing chat message data: ${json.encode(data)}');
      
      // Verify required fields are present
      final requiredFields = ['userId', 'username', 'content', 'videoId'];
      final missingFields = requiredFields.where((field) => !data.containsKey(field) || data[field] == null);
      
      if (missingFields.isNotEmpty) {
        throw FormatException(
          'Missing required fields: ${missingFields.join(', ')}'
        );
      }
      
      final message = ChatMessage.fromJson(data);
      debugPrint('Successfully parsed message: ${message.toString()}');
      
      // Only add to stream if it's still open
      if (!_chatController.isClosed) {
        _chatController.add(message);
      } else {
        debugPrint('WebSocketApiService: Chat controller is closed, cannot add message');
      }
    } catch (e, stackTrace) {
      debugPrint('Error handling chat message: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('Raw message data: ${json.encode(data)}');
    }
  }


  void _handleChatHistory(Map<String, dynamic> data) {
    if (_disposed) {
      debugPrint('WebSocketApiService: Skipping chat history handling, service is disposed');
      return;
    }
    
    try {
      if (data['messages'] == null) {
        debugPrint('No messages found in chat history');
        return;
      }
      
      // Check if chat controller is still open
      if (_chatController.isClosed) {
        debugPrint('WebSocketApiService: Chat controller is closed, cannot process chat history');
        return;
      }

      final messages = (data['messages'] as List).map((m) {
        try {
          return ChatMessage.fromJson(m as Map<String, dynamic>);
        } catch (e) {
          debugPrint('Error parsing historical message: $e');
          debugPrint('Raw message data: ${json.encode(m)}');
          return null;
        }
      }).whereType<ChatMessage>().toList();
      
      debugPrint('Processing ${messages.length} historical messages');
      
      // Check again before adding messages in case it was closed during processing
      if (!_chatController.isClosed) {
        for (final message in messages) {
          _chatController.add(message);
        }
      } else {
        debugPrint('WebSocketApiService: Chat controller was closed during processing');
      }
    } catch (e, stackTrace) {
      debugPrint('Error handling chat history: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _handleError(dynamic error) {
    debugPrint('WebSocket error occurred: $error');
    _setStatus(ConnectionStatus.error);
    _scheduleReconnect();
  }

  void _handleDisconnect() {
    debugPrint('WebSocket disconnected');
    _setStatus(ConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || isConnected || _status == ConnectionStatus.reconnecting) {
      return;
    }

    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setStatus(ConnectionStatus.error);
      _cancelPendingRequests('Max reconnection attempts reached');
      return;
    }

    _setStatus(ConnectionStatus.reconnecting);

    final delay = _initialReconnectDelay * (1 << _reconnectAttempts);
    _reconnectTimer = Timer(delay, () async {
      _reconnectAttempts++;
      try {
        await connect();
      } catch (e) {
        debugPrint('Reconnection attempt failed: $e');
      }
    });
  }

  void _cancelPendingRequests([String? error]) {
    final err = error ?? 'WebSocket connection closed';
    _pendingRequests.forEach((_, completer) {
      if (!completer.isCompleted) {
        completer.completeError(err);
      }
    });
    _pendingRequests.clear();
  }

  Future<Map<String, dynamic>> _sendRequest(WebSocketRequest request, {Duration? timeout}) async {
    // Throttle requests
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastRequestTime);
    if (timeSinceLastRequest < _minRequestInterval) {
      await Future.delayed(_minRequestInterval - timeSinceLastRequest);
    }
    _lastRequestTime = DateTime.now();

    // Prevent duplicate requests
    if (_activeRequests[request.requestId] == true) {
      debugPrint('WebSocketApiService: Duplicate request detected ${request.requestId}');
      throw Exception('Duplicate request');
    }
    _activeRequests[request.requestId] = true;

    if (!isConnected) {
      debugPrint('WebSocketApiService: Connecting before sending request...');
      await connect();
    }

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[request.requestId] = completer;

    try {
      final requestData = request.toJson();
      debugPrint('WebSocketApiService: Sending request ${request.requestId} (${request.action}): ${json.encode(requestData)}');
      _channel!.sink.add(json.encode(requestData));
      
      final response = await completer.future.timeout(
        timeout ?? const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('WebSocketApiService: Request ${request.requestId} timed out');
          _cleanup(request.requestId);
          throw TimeoutException('Request timeout');
        },
      );
      
      return response;
    } catch (e) {
      debugPrint('WebSocketApiService: Error in _sendRequest: $e');
      _cleanup(request.requestId);
      rethrow;
    }
  }

  void _cleanup(String requestId) {
    _pendingRequests.remove(requestId);
    _activeRequests.remove(requestId);
  }

  Future<VideoResult> search(String query) async {
    if (query.trim().isEmpty) {
      throw Exception('Search query cannot be empty');
    }

    try {
      final response = await _sendRequest(
        WebSocketRequest(
          action: 'search',
          params: {'query': query},
        ),
        timeout: const Duration(seconds: 30),
      );

      if (!response['success']) {
        throw Exception(response['error'] ?? 'Search failed');
      }

      final result = response['result'];
      if (result == null) {
        throw Exception('No result returned from search');
      }

      return VideoResult.fromJson(result as Map<String, dynamic>);

    } catch (e) {
      throw Exception('Error performing search: $e');
    }
  }

  Future<String> generateVideo(VideoResult video, {
    bool enhancePrompt = false,
    String? negativePrompt,
    int height = 320,
    int width = 512,
    int seed = 0,
    Duration timeout = const Duration(seconds: 12), // we keep things super tight, as normally a video only takes 2~3s to generate
    VideoOrientation orientation = VideoOrientation.LANDSCAPE,
  }) async {
    final settings = SettingsService();

    final response = await _sendRequest(
      WebSocketRequest(
        action: 'generate_video',
        params: {
          'title': video.title,
          'description': video.evolvedDescription.isEmpty ? video.description : video.evolvedDescription,
          'video_prompt_prefix': settings.videoPromptPrefix,
          'options': {
            'enhance_prompt': enhancePrompt,
            'negative_prompt': negativePrompt ?? settings.negativeVideoPrompt,
            'frame_rate': Configuration.instance.originalClipFrameRate,
            'num_inference_steps': Configuration.instance.numInferenceSteps,
            'guidance_scale': Configuration.instance.guidanceScale,
            'height': Configuration.instance.originalClipHeight,
            'width': Configuration.instance.originalClipWidth,
            'num_frames': Configuration.instance.originalClipNumberOfFrames,
            'orientation': orientation.value, // Add orientation parameter
            'seed': seed,
          },
        },
      ),
      timeout: timeout,
    );

    if (!response['success']) {
      throw Exception(response['error'] ?? 'Video generation failed');
    }

    return response['video'] as String;
  }

  Future<String> generateCaption(String title, String description) async {
    final response = await _sendRequest(
      WebSocketRequest(
        action: 'generate_caption',
        params: {
          'title': title,
          'description': description,
        },
      ),
      timeout: const Duration(seconds: 45),
    );

    if (!response['success']) {
      throw Exception(response['error'] ?? 'caption generation failed');
    }

    return response['caption'] as String;
  }

  /// Simulate a video by evolving its description to create a dynamic narrative
  Future<Map<String, String>> simulate({
    required String videoId,
    required String originalTitle,
    required String originalDescription,
    required String currentDescription,
    required String condensedHistory,
    int evolutionCount = 0,
    String chatMessages = '',
  }) async {
    // Skip if the API is not connected
    if (!isConnected) {
      debugPrint('WebSocketApiService: Cannot simulate video, not connected');
      return {
        'evolved_description': currentDescription,
        'condensed_history': condensedHistory
      };
    }

    debugPrint('WebSocketApiService: Sending simulation request for video $videoId (evolution #$evolutionCount)');
    
    try {
      // If chat messages are provided directly, use them; otherwise the default empty string is used
      String formattedChatMessages = chatMessages;
      
      // If no chat messages were provided but we have a chat stream, try to get recent messages
      if (formattedChatMessages.isEmpty) {
        // Check if we have any active chat messages in our stream
        try {
          // Get messages directly from the chatController's history
          final List<ChatMessage> recentChatMessages = [];
          // We'd ideally query for recent messages in a real implementation
          // but to avoid circular dependencies we'll use any messages provided to us
          
          if (recentChatMessages.isNotEmpty) {
            formattedChatMessages = recentChatMessages.map((msg) => 
              "${msg.username}: ${msg.content}"
            ).join("\n");
            debugPrint('WebSocketApiService: Including ${recentChatMessages.length} chat messages in simulation');
          }
        } catch (e) {
          debugPrint('WebSocketApiService: Error getting chat messages: $e');
        }
      }
      
      debugPrint('WebSocketApiService: Chat messages included: ${formattedChatMessages.isNotEmpty ? 'Yes' : 'No'}');
      
      final response = await _sendRequest(
        WebSocketRequest(
          action: 'simulate',
          params: {
            'video_id': videoId,
            'original_title': originalTitle,
            'original_description': originalDescription,
            'current_description': currentDescription,
            'condensed_history': condensedHistory,
            'evolution_count': evolutionCount,
            'chat_messages': formattedChatMessages,
          },
        ),
        timeout: const Duration(seconds: 60),
      );

      if (!response['success']) {
        debugPrint('WebSocketApiService: Simulation API returned error: ${response['error']}');
        throw Exception(response['error'] ?? 'Simulation failed');
      }

      final evolvedDescription = response['evolved_description'] as String? ?? currentDescription;
      final newHistory = response['condensed_history'] as String? ?? condensedHistory;
      
      debugPrint('WebSocketApiService: Simulation successful, received ${evolvedDescription.length} chars for evolved description');
      
      return {
        'evolved_description': evolvedDescription,
        'condensed_history': newHistory
      };
    } catch (e) {
      debugPrint('WebSocketApiService: Error simulating video: $e');
      return {
        'evolved_description': currentDescription,
        'condensed_history': condensedHistory
      };
    }
  }


  // Additional utility methods
  Future<void> waitForConnection() async {
    if (isConnected) return;

    final completer = Completer<void>();
    StreamSubscription<ConnectionStatus>? subscription;

    subscription = statusStream.listen((status) {
      if (status == ConnectionStatus.connected) {
        subscription?.cancel();
        completer.complete();
      } else if (status == ConnectionStatus.error) {
        subscription?.cancel();
        completer.completeError('Failed to connect');
      }
    });

    await connect();
    return completer.future;
  }

  void cancelRequestsForVideo(String videoId) {
    final requestsToCancel = _pendingRequests.entries
        .where((entry) => entry.key.startsWith('video_$videoId'))
        .toList();
        
    for (var entry in requestsToCancel) {
      if (!entry.value.isCompleted) {
        entry.value.completeError('Video closed');
      }
      _cleanup(entry.key);
    }
  }

  Future<void> dispose() async {
    if (_subscribers.isNotEmpty) {
      debugPrint('WebSocketApiService: Skipping disposal - active subscribers remain: ${_subscribers.length}');
      return;
    }
    
    // Use the lock to prevent multiple simultaneous disposal attempts
    return _disposeLock.synchronized(() async {
      if (_disposed) return;
      
      debugPrint('WebSocketApiService: Starting disposal...');
      _disposed = true;
      _initialized = false;
      
      // Unregister device connection (web only)
      _unregisterDeviceConnection();
      
      // Cancel timers
      _heartbeatTimer?.cancel();
      _reconnectTimer?.cancel();
      _connectionHeartbeatTimer?.cancel();
      
      // Clear all pending requests
      _cancelPendingRequests('Service is being disposed');
      
      // Close channel properly
      if (_channel != null) {
        try {
          await _channel!.sink.close();
        } catch (e) {
          debugPrint('WebSocketApiService: Error closing channel: $e');
        }
      }
      
      // Close controllers
      await _responseController.close();
      await _statusController.close();
      await _searchController.close();
      await _chatController.close();
      await _userRoleController.close();
      await _anonLimitController.close();
      await _deviceLimitController.close();
      
      _activeSearches.clear();
      _channel = null;
      
      debugPrint('WebSocketApiService: Disposal complete');
    });
  }

}