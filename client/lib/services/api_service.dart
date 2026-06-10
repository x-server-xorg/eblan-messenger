import 'dart:io';
import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio;
  String? _token;
  String _baseUrl = '';

  void Function(String serverAddress)? onConnectionError;

  ApiService() : _dio = Dio() {
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        if (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.receiveTimeout ||
            error.error is SocketException) {
          onConnectionError?.call(_baseUrl);
        }
        handler.next(error);
      },
    ));
  }

  void configure(String serverUrl, String token) {
    _baseUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    _token = token;
    _dio.options.baseUrl = 'http://$_baseUrl';
    _dio.options.headers['Authorization'] = 'Bearer $token';
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  void clear() {
    _token = null;
    _dio.options.headers.remove('Authorization');
  }

  String get serverUrl => _baseUrl;
  String? get token => _token;

  Future<Response> register(String username, String password) async {
    _dio.options.baseUrl = 'http://$_baseUrl';
    return _dio.post('/api/auth/register', data: {
      'username': username,
      'password': password,
    });
  }

  Future<Response> login(String username, String password) async {
    _dio.options.baseUrl = 'http://$_baseUrl';
    return _dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
  }

  Future<Response> getMe() async {
    return _dio.get('/api/auth/me');
  }

  Future<Response> searchUsers(String query) async {
    return _dio.get('/api/users/search', queryParameters: {'q': query});
  }

  Future<Response> searchAll(String query) async {
    return _dio.get('/api/chats/search', queryParameters: {'q': query});
  }

  Future<Response> getUser(int userId) async {
    return _dio.get('/api/users/$userId');
  }

  Future<Response> updateProfile({String? username, String? bio}) async {
    return _dio.put('/api/users/me', data: {
      if (username != null) 'username': username,
      if (bio != null) 'bio': bio,
    });
  }

  Future<Response> deleteAccount() async {
    return _dio.delete('/api/users/me');
  }

  Future<Response> getMessages(int userId) async {
    return _dio.get('/api/messages/$userId');
  }

  Future<Response> getChatMessages(int chatId) async {
    return _dio.get('/api/chats/$chatId/messages');
  }

  Future<Response> getChats() async {
    return _dio.get('/api/messages/chats/list');
  }

  Future<Response> getAllChats() async {
    return _dio.get('/api/chats');
  }

  Future<Response> createGroup(String name, String username, List<int> memberIds) async {
    return _dio.post('/api/chats', data: {
      'name': name,
      'username': username,
      'members': memberIds,
    });
  }

  Future<Response> getChat(int chatId) async {
    return _dio.get('/api/chats/$chatId');
  }

  Future<Response> deleteChat(int chatId) async {
    return _dio.delete('/api/chats/$chatId');
  }

  Future<Response> inviteToChat(int chatId, int userId) async {
    return _dio.post('/api/chats/$chatId/invite', data: {
      'userId': userId,
    });
  }

  Future<Response> uploadFile(String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    return _dio.post('/api/files/upload', data: formData);
  }

  Future<Response> updateAvatar(String filePath) async {
    final fileName = filePath.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    return _dio.put('/api/users/me/avatar', data: formData);
  }

  Future<Response> deleteMessage(int messageId, {bool forAll = false}) async {
    return _dio.delete('/api/messages/$messageId', queryParameters: {
      if (forAll) 'forAll': 'true',
    });
  }

  Future<Response> blockUser(int userId) async {
    return _dio.post('/api/users/block/$userId');
  }

  Future<Response> unblockUser(int userId) async {
    return _dio.post('/api/users/unblock/$userId');
  }

  Future<Response> getBlockedUsers() async {
    return _dio.get('/api/users/blocks/list');
  }

  Future<Response> getSettings() async {
    return _dio.get('/api/users/settings');
  }

  Future<Response> updateSettings(String groupInvitePrivacy) async {
    return _dio.put('/api/users/settings', data: {
      'group_invite_privacy': groupInvitePrivacy,
    });
  }

  Future<Response> updateChat(int chatId, {String? name, String? description, bool? adminsOnly, String? invitePermission}) async {
    return _dio.put('/api/chats/$chatId', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (adminsOnly != null) 'admins_only': adminsOnly,
      if (invitePermission != null) 'invite_permission': invitePermission,
    });
  }

  Future<Response> removeMember(int chatId, int userId) async {
    return _dio.delete('/api/chats/$chatId/members/$userId');
  }

  Future<Response> promoteMember(int chatId, int userId) async {
    return _dio.post('/api/chats/$chatId/promote/$userId');
  }

  Future<Response> demoteMember(int chatId, int userId) async {
    return _dio.post('/api/chats/$chatId/demote/$userId');
  }

  Future<Response> pinMessage(int chatId, int messageId) async {
    return _dio.post('/api/chats/$chatId/pin/$messageId');
  }

  Future<Response> unpinMessage(int chatId, int messageId) async {
    return _dio.delete('/api/chats/$chatId/pin/$messageId');
  }

  String getFileUrl(String path) {
    return 'http://$_baseUrl/api/files/$path';
  }

  bool get isConfigured => _token != null && _baseUrl.isNotEmpty;
}
