// lib/widgets/chat_widget.dart
import 'dart:async';

import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../theme/colors.dart';

class ChatWidget extends StatefulWidget {
  final String videoId;
  final bool isCompact;

  const ChatWidget({
    super.key,
    required this.videoId,
    this.isCompact = false,
  });

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final _chatService = ChatService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];
  // Track message IDs to prevent duplicates
  final _messageIds = <String>{};
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  Timer? _reconnectTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_disposed) return;
    
    debugPrint('ChatWidget: Starting initialization for video ${widget.videoId}...');
    try {
      await _chatService.initialize();
      
      int retryCount = 0;
      const maxRetries = 3;
      
      while (retryCount < maxRetries && !_disposed) {
        try {
          debugPrint('ChatWidget: Attempting to join room ${widget.videoId} (attempt ${retryCount + 1})');
          await _chatService.joinRoom(widget.videoId).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('ChatWidget: Join room timeout on attempt ${retryCount + 1}');
              throw TimeoutException('Failed to join chat room');
            },
          );
          
          if (_disposed) return;
          
          debugPrint('ChatWidget: Successfully joined room ${widget.videoId}');
          break;
        } catch (e) {
          retryCount++;
          debugPrint('ChatWidget: Attempt $retryCount failed: $e');
          
          if (retryCount >= maxRetries || _disposed) {
            debugPrint('ChatWidget: Max retries reached or widget disposed, throwing error');
            throw Exception('Failed to join chat room after $maxRetries attempts');
          }
          
          final delay = Duration(seconds: 1 << retryCount);
          debugPrint('ChatWidget: Waiting ${delay.inSeconds}s before retry...');
          await Future.delayed(delay);
        }
      }

      if (!_disposed) {
        _chatService.chatStream.listen(
          _onNewMessage,
          onError: (error) {
            debugPrint('ChatWidget: Chat stream error: $error');
            _handleError(error);
          },
        );
        
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = null;
          });
        }
      }
    } catch (e) {
      debugPrint('ChatWidget: Initialization error: $e');
      if (mounted && !_disposed) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to connect to chat. Tap to retry.';
        });
      }
    }
  }

  void _handleError(dynamic error) {
    if (_disposed || !mounted) return;
    
    setState(() {
      _error = 'Connection error. Tap to retry.';
      _isLoading = false;
    });
    
    // Schedule reconnection
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _initialize);
  }

  void _onNewMessage(ChatMessage message) {
    if (!mounted) return;
    
    // Check if we already have this message (prevent duplicates)
    if (_messageIds.contains(message.id)) {
      debugPrint('ChatWidget: Skipping duplicate message with ID: ${message.id}');
      return;
    }
    
    setState(() {
      _messages.add(message);
      _messageIds.add(message.id);
      // Keep only last 100 messages
      if (_messages.length > 100) {
        final removedMessage = _messages.removeAt(0);
        _messageIds.remove(removedMessage.id);
      }
    });

    // Auto-scroll to bottom with a slight delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet',
          style: TextStyle(
            color: TikSlopColors.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageTile(message);
      },
    );
  }

  Widget _buildMessageTile(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Color(
              int.parse(message.color?.substring(1) ?? 'FF4444',
              radix: 16) | 0xFF000000,
            ),
            child: Text(
              message.username.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      message.username,
                      style: const TextStyle(
                        color: TikSlopColors.onBackground,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(message.timestamp),
                      style: const TextStyle(
                        color: TikSlopColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message.content,
                  style: const TextStyle(color: TikSlopColors.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: TikSlopColors.transparent,
        border: Border(
          top: BorderSide(
            color: TikSlopColors.surfaceVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: TikSlopColors.onSurface),
              maxLength: 255,
              maxLines: 1,
              onChanged: (value) {
                // Enforce the character limit by trimming excess characters
                if (value.length > 255) {
                  _messageController.text = value.substring(0, 255);
                  _messageController.selection = TextSelection.fromPosition(
                    const TextPosition(offset: 255),
                  );
                }
              },
              decoration: InputDecoration(
                hintText: 'Chat with this tikslopr..',
                hintStyle: const TextStyle(color: TikSlopColors.onSurfaceVariant, fontSize: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0x20FFFFFF),
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0x20FFFFFF),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: TikSlopColors.primary,
                    width: 1,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                counterText: '',
                filled: true,
                fillColor: const Color(0x10000000),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: _isSending 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.reply),
            color: TikSlopColors.primary,
            onPressed: _isSending ? null : _sendMessage,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSending = true);
    
    try {
      final success = await _chatService.sendMessage(content, widget.videoId);
      
      if (success) {
        _messageController.clear();
        FocusScope.of(context).unfocus();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send message. Please try again.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: TikSlopColors.onBackground)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _initialize();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Container(
      width: widget.isCompact ? double.infinity : 320,
      decoration: BoxDecoration(
        color: TikSlopColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: TikSlopColors.surfaceVariant,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.chat, color: TikSlopColors.onBackground),
                SizedBox(width: 8),
                Text(
                  'Simulation log',
                  style: TextStyle(
                    color: TikSlopColors.onBackground,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildMessageList()),
          _buildMessageInput(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('ChatWidget: Disposing chat widget for video ${widget.videoId}');
    _disposed = true;
    _reconnectTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    
    // Just leave the chat room, but don't dispose the ChatService
    // since it's a singleton that may be used by other widgets
    _chatService.leaveRoom(widget.videoId).catchError((error) {
      debugPrint('ChatWidget: Error leaving chat room during disposal: $error');
    });
    
    super.dispose();
  }
}