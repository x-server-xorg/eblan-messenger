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
  int? _selectedGroupChatId;
  bool _loading = false;
  String? _error;

  ChatProvider(this._api, this._socket);

  void setCurrentUserId(int id) => _userId = id;

  List<Map<String, dynamic>> get chats => _chats;
  List<Message>? getMessages(int userId) => _messages[userId];
  List<Message>? getGroupMessages(int chatId) => _messages[chatId];
  bool isTyping(int userId) => _typing[userId] ?? false;
  bool isRecordingAudio(int userId) => _recordingAudio[userId] ?? false;
  bool isOnline(int userId) => _onlineStatus[userId] ?? false;
  int? get selectedChatId => _selectedChatId;
  int? get selectedGroupChatId => _selectedGroupChatId;
  bool get loading => _loading;
  String? get error => _error;
  SocketService get socket => _socket;

  void setSelectedChat(int? userId) {
    _selectedChatId = userId;
    _selectedGroupChatId = null;
    notifyListeners();
  }

  void setSelectedGroupChat(int? chatId) {
    _selectedGroupChatId = chatId;
    _selectedChatId = null;
    notifyListeners();
  }

  void initSocketListeners() {
    _socket.onMessageReceived((data) {
      final message = Message.fromJson(data as Map<String, dynamic>);
      final isFromMe = message.senderId == _userId;
      final chatUserId = isFromMe ? message.receiverId : message.senderId;

      if (message.chatId != null) {
        _messages.putIfAbsent(message.chatId!, () => []);
        _messages[message.chatId!]!.add(message);
      } else {
        _messages.putIfAbsent(chatUserId, () => []);
        _messages[chatUserId]!.add(message);
        _updateChatList(message, chatUserId);
      }

      if (!isFromMe && _selectedChatId != message.senderId) {
        final preview = message.text.isNotEmpty
            ? message.text
            : message.fileName ?? 'Media';
        NotificationService.instance.showMessageNotification(
          id: message.id,
          title: message.senderUsername.isNotEmpty ? message.senderUsername : 'New message',
          body: preview,
        );
      }

      notifyListeners();
    });

    _socket.onMessageDeleted((data) {
      final messageId = data['messageId'] as int;
      final chatId = data['chatId'] as int?;

      for (final entry in _messages.entries) {
        entry.value.removeWhere((m) => m.id == messageId);
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

    final existingIndex = _chats.indexWhere((c) => c['user_id'] == chatUserId && c['type'] != 'group');

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
          'peer_id': chatUserId,
          'username': user['username'] as String,
          'avatar_path': user['avatar_path'] as String?,
          'type': 'dialog',
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
      final response = await _api.getAllChats();
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

  Future<void> loadGroupMessages(int chatId) async {
    try {
      final response = await _api.getChatMessages(chatId);
      final messagesList = (response.data['messages'] as List)
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList();
      _messages[chatId] = messagesList;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void sendMessage({
    required int receiverId,
    int? chatId,
    String text = '',
    String? filePath,
    String? fileType,
    String? fileName,
    int? fileSize,
  }) {
    if (text.isEmpty && filePath == null) return;
    _socket.sendMessage(
      receiverId: receiverId,
      chatId: chatId,
      text: text,
      filePath: filePath,
      fileType: fileType,
      fileName: fileName,
      fileSize: fileSize,
    );
  }

  Future<void> deleteMessage(int messageId, {bool forAll = false}) async {
    try {
      await _api.deleteMessage(messageId, forAll: forAll);
      if (!forAll) {
        for (final entry in _messages.entries) {
          entry.value.removeWhere((m) => m.id == messageId);
        }
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<bool> createGroup(String name, String username, List<int> memberIds) async {
    try {
      final response = await _api.createGroup(name, username, memberIds);
      final chat = response.data['chat'] as Map<String, dynamic>;
      _chats.insert(0, {
        'id': chat['id'],
        'name': chat['name'],
        'username': chat['username'],
        'type': 'group',
        'last_message_text': null,
        'last_message_at': chat['created_at'],
      });
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteChat(int chatId) async {
    try {
      await _api.deleteChat(chatId);
      _chats.removeWhere((c) => c['id'] == chatId || c['peer_id'] == chatId);
      _messages.remove(chatId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> inviteToChat(int chatId, int userId) async {
    try {
      await _api.inviteToChat(chatId, userId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void sendTyping(int receiverId, {int? chatId}) {
    _socket.sendTyping(receiverId, chatId: chatId);
  }

  void sendStopTyping(int receiverId, {int? chatId}) {
    _socket.sendStopTyping(receiverId, chatId: chatId);
  }

  void sendRecordingAudio(int receiverId) {
    _socket.sendRecordingAudio(receiverId);
  }

  void sendStopRecordingAudio(int receiverId) {
    _socket.sendStopRecordingAudio(receiverId);
  }

  Future<bool> updateGroup(int chatId, {String? name, String? description, bool? adminsOnly, String? invitePermission}) async {
    try {
      await _api.updateChat(chatId, name: name, description: description, adminsOnly: adminsOnly, invitePermission: invitePermission);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeMember(int chatId, int userId) async {
    try {
      await _api.removeMember(chatId, userId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> promoteMember(int chatId, int userId) async {
    try {
      await _api.promoteMember(chatId, userId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> demoteMember(int chatId, int userId) async {
    try {
      await _api.demoteMember(chatId, userId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> pinMessage(int chatId, int messageId) async {
    try {
      await _api.pinMessage(chatId, messageId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> unpinMessage(int chatId, int messageId) async {
    try {
      await _api.unpinMessage(chatId, messageId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
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
