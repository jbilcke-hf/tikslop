import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// ANSI color codes for terminal output
class AnsiColors {
  static const String reset = '\x1B[0m';
  static const String bold = '\x1B[1m';
  static const String dim = '\x1B[2m';
  static const String italic = '\x1B[3m';
  static const String underline = '\x1B[4m';

  // Foreground colors
  static const String black = '\x1B[30m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String magenta = '\x1B[35m';
  static const String cyan = '\x1B[36m';
  static const String white = '\x1B[37m';

  // Bright foreground colors
  static const String brightBlack = '\x1B[90m';
  static const String brightRed = '\x1B[91m';
  static const String brightGreen = '\x1B[92m';
  static const String brightYellow = '\x1B[93m';
  static const String brightBlue = '\x1B[94m';
  static const String brightMagenta = '\x1B[95m';
  static const String brightCyan = '\x1B[96m';
  static const String brightWhite = '\x1B[97m';

  // Background colors
  static const String bgBlack = '\x1B[40m';
  static const String bgRed = '\x1B[41m';
  static const String bgGreen = '\x1B[42m';
  static const String bgYellow = '\x1B[43m';
  static const String bgBlue = '\x1B[44m';
  static const String bgMagenta = '\x1B[45m';
  static const String bgCyan = '\x1B[46m';
  static const String bgWhite = '\x1B[47m';
}

/// Log levels with associated colors and emojis
enum LogLevel {
  debug(AnsiColors.brightBlack, '🔍', 'DEBUG'),
  info(AnsiColors.brightCyan, '💡', 'INFO'),
  warning(AnsiColors.brightYellow, '⚠️', 'WARN'),
  error(AnsiColors.brightRed, '❌', 'ERROR'),
  success(AnsiColors.brightGreen, '✅', 'SUCCESS'),
  network(AnsiColors.brightMagenta, '🌐', 'NET'),
  websocket(AnsiColors.cyan, '🔌', 'WS'),
  video(AnsiColors.brightBlue, '🎬', 'VIDEO'),
  chat(AnsiColors.green, '💬', 'CHAT'),
  search(AnsiColors.yellow, '🔍', 'SEARCH');

  const LogLevel(this.color, this.emoji, this.label);
  
  final String color;
  final String emoji;
  final String label;
}

/// Beautiful colored logger for Flutter applications
class ColoredLogger {
  final String _className;
  
  ColoredLogger(this._className);
  
  /// Create a logger for a specific class
  static ColoredLogger get(String className) {
    return ColoredLogger(className);
  }
  
  /// Debug level logging - for detailed debugging info
  void debug(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.debug, message, data);
  }
  
  /// Info level logging - for general information
  void info(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.info, message, data);
  }
  
  /// Warning level logging - for potential issues
  void warning(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.warning, message, data);
  }
  
  /// Error level logging - for errors and exceptions
  void error(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.error, message, data);
  }
  
  /// Success level logging - for successful operations
  void success(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.success, message, data);
  }
  
  /// Network level logging - for network operations
  void network(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.network, message, data);
  }
  
  /// WebSocket level logging - for WebSocket operations
  void websocket(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.websocket, message, data);
  }
  
  /// Video level logging - for video generation operations
  void video(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.video, message, data);
  }
  
  /// Chat level logging - for chat operations
  void chat(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.chat, message, data);
  }
  
  /// Search level logging - for search operations
  void search(String message, [Map<String, dynamic>? data]) {
    _log(LogLevel.search, message, data);
  }
  
  void _log(LogLevel level, String message, Map<String, dynamic>? data) {
    if (!kDebugMode) return; // Only log in debug mode
    
    final timestamp = DateTime.now();
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
                   '${timestamp.minute.toString().padLeft(2, '0')}:'
                   '${timestamp.second.toString().padLeft(2, '0')}.'
                   '${timestamp.millisecond.toString().padLeft(3, '0')}';
    
    // Format the main log message with colors
    final coloredMessage = _colorizeMessage(message);
    
    // Build the log line
    final logLine = StringBuffer();
    
    // Timestamp (dim)
    logLine.write('${AnsiColors.dim}$timeStr${AnsiColors.reset} ');
    
    // Level with color and emoji
    logLine.write('${level.color}${level.emoji} ${level.label.padRight(7)}${AnsiColors.reset} ');
    
    // Class name (bright black)
    logLine.write('${AnsiColors.brightBlack}[$_className]${AnsiColors.reset} ');
    
    // Message
    logLine.write(coloredMessage);
    
    // Add data if provided
    if (data != null && data.isNotEmpty) {
      logLine.write(' ${AnsiColors.dim}${_formatData(data)}${AnsiColors.reset}');
    }
    
    // Use developer.log for better IDE integration
    developer.log(
      logLine.toString(),
      name: _className,
      level: _getLevelValue(level),
    );
  }
  
  String _colorizeMessage(String message) {
    String result = message;
    
    // Highlight request IDs in brackets
    result = result.replaceAllMapped(
      RegExp(r'\[([a-zA-Z0-9-]+)\]'),
      (match) => '${AnsiColors.brightGreen}[${match.group(1)}]${AnsiColors.reset}',
    );
    
    // Highlight user IDs
    result = result.replaceAllMapped(
      RegExp(r'\buser ([a-zA-Z0-9-]+)'),
      (match) => 'user ${AnsiColors.brightBlue}${match.group(1)}${AnsiColors.reset}',
    );
    
    // Highlight actions
    result = result.replaceAllMapped(
      RegExp(r'\b(generate_video|search|simulate|join_chat|leave_chat|chat_message|connect|disconnect)\b'),
      (match) => '${AnsiColors.brightYellow}${match.group(1)}${AnsiColors.reset}',
    );
    
    // Highlight status keywords
    result = result.replaceAllMapped(
      RegExp(r'\b(success|successful|completed|connected|ready|ok)\b', caseSensitive: false),
      (match) => '${AnsiColors.brightGreen}${match.group(1)}${AnsiColors.reset}',
    );
    
    result = result.replaceAllMapped(
      RegExp(r'\b(error|failed|timeout|exception|crash)\b', caseSensitive: false),
      (match) => '${AnsiColors.brightRed}${match.group(1)}${AnsiColors.reset}',
    );
    
    result = result.replaceAllMapped(
      RegExp(r'\b(warning|retry|reconnect|fallback)\b', caseSensitive: false),
      (match) => '${AnsiColors.brightYellow}${match.group(1)}${AnsiColors.reset}',
    );
    
    // Highlight numbers with units
    result = result.replaceAllMapped(
      RegExp(r'\b(\d+\.?\d*)(ms|s|MB|KB|bytes|chars|fps)?\b'),
      (match) => '${AnsiColors.brightMagenta}${match.group(1)}${AnsiColors.cyan}${match.group(2) ?? ''}${AnsiColors.reset}',
    );
    
    // Highlight URLs
    result = result.replaceAllMapped(
      RegExp(r'https?://[^\s]+'),
      (match) => '${AnsiColors.underline}${AnsiColors.brightCyan}${match.group(0)}${AnsiColors.reset}',
    );
    
    // Highlight JSON-like structures
    result = result.replaceAllMapped(
      RegExp(r'\{[^}]*\}'),
      (match) => '${AnsiColors.dim}${match.group(0)}${AnsiColors.reset}',
    );
    
    // Highlight strings in quotes
    result = result.replaceAllMapped(
      RegExp(r'"([^"]*)"'),
      (match) => '"${AnsiColors.green}${match.group(1)}${AnsiColors.reset}"',
    );
    
    return result;
  }
  
  String _formatData(Map<String, dynamic> data) {
    final entries = data.entries.map((e) {
      final key = e.key;
      final value = e.value.toString();
      return '${AnsiColors.cyan}$key${AnsiColors.reset}=${AnsiColors.brightWhite}$value${AnsiColors.reset}';
    }).join(' ');
    
    return '{$entries}';
  }
  
  int _getLevelValue(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
      case LogLevel.success:
        return 800;
      case LogLevel.network:
        return 700;
      case LogLevel.websocket:
        return 700;
      case LogLevel.video:
        return 700;
      case LogLevel.chat:
        return 700;
      case LogLevel.search:
        return 700;
    }
  }
}

/// Extension methods for easy logging
extension ColoredLogging on Object {
  ColoredLogger get log => ColoredLogger.get(runtimeType.toString());
}

/// Global logger instance for quick access
final appLog = ColoredLogger.get('App');