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

  Future<Response> getChats() async {
    return _dio.get('/api/messages/chats/list');
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

  String getFileUrl(String path) {
    return 'http://$_baseUrl/api/files/$path';
  }

  bool get isConfigured => _token != null && _baseUrl.isNotEmpty;
}
