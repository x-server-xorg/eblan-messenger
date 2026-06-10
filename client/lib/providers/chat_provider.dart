import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api;
  final SocketService _socket;

  List<Map<String, dynamic>> _chats = [];
  final Map<int, List<Message>> _messages = {};
  final Map<int, bool> _typing = {};
  final Map<int, bool> _recordingAudio = {};
  final Map<int, bool> _onlineStatus = {};
  int? _userId;
  int? _selectedChatId;
  bool _loading = false;
  String? _error;

  ChatProvider(this._api, this._socket);

  void setCurrentUserId(int id) => _userId = id;

  List<Map<String, dynamic>> get chats => _chats;
  List<Message>? getMessages(int userId) => _messages[userId];
  bool isTyping(int userId) => _typing[userId] ?? false;
  bool isRecordingAudio(int userId) => _recordingAudio[userId] ?? false;
  bool isOnline(int userId) => _onlineStatus[userId] ?? false;
  int? get selectedChatId => _selectedChatId;
  bool get loading => _loading;
  String? get error => _error;

  void setSelectedChat(int? userId) {
    _selectedChatId = userId;
    notifyListeners();
  }

  void initSocketListeners() {
    _socket.onMessageReceived((data) {
      final message = Message.fromJson(data as Map<String, dynamic>);
      final isFromMe = message.senderId == _userId;
      final chatUserId = isFromMe ? message.receiverId : message.senderId;

      _messages.putIfAbsent(chatUserId, () => []);
      _messages[chatUserId]!.add(message);
      _updateChatList(message, chatUserId);

      if (!isFromMe && _selectedChatId != message.senderId) {
        final preview = message.text.isNotEmpty
            ? message.text
            : message.fileName ?? 'Media';
        NotificationService.instance.showMessageNotification(
          id: message.id,
          title: message.senderUsername.isNotEmpty
              ? message.senderUsername
              : 'New message',
          body: preview,
        );
      }

      notifyListeners();
    });

    _socket.onUserTyping((data) {
      final userId = data['userId'] as int;
      _typing[userId] = true;
      _recordingAudio[userId] = false;
      notifyListeners();
    });

    _socket.onUserStopTyping((data) {
      final userId = data['userId'] as int;
      _typing[userId] = false;
      notifyListeners();
    });

    _socket.onUserRecordingAudio((data) {
      final userId = data['userId'] as int;
      _recordingAudio[userId] = true;
      _typing[userId] = false;
      notifyListeners();
    });

    _socket.onUserStopRecordingAudio((data) {
      final userId = data['userId'] as int;
      _recordingAudio[userId] = false;
      notifyListeners();
    });

    _socket.onUserOnline((data) {
      final userId = data['userId'] as int;
      _onlineStatus[userId] = true;
      notifyListeners();
    });

    _socket.onUserOffline((data) {
      final userId = data['userId'] as int;
      _onlineStatus[userId] = false;
      notifyListeners();
    });
  }

  void _updateChatList(Message message, int chatUserId) {
    final previewText = message.text.isNotEmpty
        ? message.text
        : message.fileName ?? (message.isImage ? 'Photo' : message.isVideo ? 'Video' : message.isAudio ? 'Voice message' : 'File');

    final existingIndex = _chats.indexWhere((c) => c['user_id'] == chatUserId);

    if (existingIndex >= 0) {
      final chat = _chats.removeAt(existingIndex);
      chat['last_message_text'] = previewText;
      chat['last_message_at'] = message.createdAt.toIso8601String();
      _chats.insert(0, chat);
    } else {
      _api.getUser(chatUserId).then((resp) {
        final user = resp.data['user'] as Map<String, dynamic>;
        _chats.insert(0, {
          'user_id': chatUserId,
          'username': user['username'] as String,
          'avatar_path': user['avatar_path'] as String?,
          'last_message_text': previewText,
          'last_message_at': message.createdAt.toIso8601String(),
        });
        notifyListeners();
      }).catchError((_) {});
    }
  }

  Future<void> loadChats() async {
    _loading = true;
    notifyListeners();

    try {
      final response = await _api.getChats();
      _chats = (response.data['chats'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> loadMessages(int userId) async {
    try {
      final response = await _api.getMessages(userId);
      final messagesList = (response.data['messages'] as List)
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList();
      _messages[userId] = messagesList;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void sendMessage({
    required int receiverId,
    String text = '',
    String? filePath,
    String? fileType,
    String? fileName,
    int? fileSize,
  }) {
    if (text.isEmpty && filePath == null) return;

    _socket.sendMessage(
      receiverId: receiverId,
      text: text,
      filePath: filePath,
      fileType: fileType,
      fileName: fileName,
      fileSize: fileSize,
    );
  }

  void sendTyping(int receiverId) {
    _socket.sendTyping(receiverId);
  }

  void sendStopTyping(int receiverId) {
    _socket.sendStopTyping(receiverId);
  }

  void sendRecordingAudio(int receiverId) {
    _socket.sendRecordingAudio(receiverId);
  }

  void sendStopRecordingAudio(int receiverId) {
    _socket.sendStopRecordingAudio(receiverId);
  }

  Future<Map<String, dynamic>?> uploadFile(String filePath, String fileName) async {
    try {
      final response = await _api.uploadFile(filePath, fileName);
      return response.data as Map<String, dynamic>;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }


}
