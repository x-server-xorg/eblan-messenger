import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api;
  final SocketService _socket;

  User? _user;
  bool _loading = false;
  String? _error;
  bool _initialized = false;
  bool _serverUnreachable = false;
  String? _unreachableServerAddress;
  Timer? _healthCheckTimer;

  AuthProvider(this._api, this._socket) {
    _api.onConnectionError = (address) {
      if (_user != null) {
        _setServerUnreachable(address);
      }
    };

    _socket.onDisconnect(() {
      if (_user != null) {
        _setServerUnreachable(_api.serverUrl);
      }
    });

    _socket.onConnectError((_) {
      if (_user != null) {
        _setServerUnreachable(_api.serverUrl);
      }
    });
  }

  void _setServerUnreachable(String address) {
    _serverUnreachable = true;
    _unreachableServerAddress = address;
    _stopHealthCheck();
    notifyListeners();
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_user == null) return;
      try {
        await _api.getMe();
        // Server is back — clear the error
        if (_serverUnreachable) {
          _serverUnreachable = false;
          _unreachableServerAddress = null;
          notifyListeners();
        }
      } catch (_) {
        // Server is still down — keep the error
      }
    });
  }

  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  User? get user => _user;
  bool get loading => _loading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  bool get initialized => _initialized;
  bool get serverUnreachable => _serverUnreachable;
  String? get unreachableServerAddress => _unreachableServerAddress;
  ApiService get api => _api;
  SocketService get socket => _socket;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('server_url');
    final token = prefs.getString('token');

    if (serverUrl != null && token != null) {
      _api.configure(serverUrl, token);
      _socket.connect(serverUrl, token);

      try {
        final response = await _api.getMe();
        _user = User.fromJson(response.data['user']);
        _initialized = true;
        notifyListeners();
        return;
      } catch (e) {
        // Don't clear saved data — keep server_url for login screen pre-fill
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<bool> register(String server, String username, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _api.configure(server, '');
      final response = await _api.register(username, password);
      final token = response.data['token'] as String;
      final userData = response.data['user'] as Map<String, dynamic>;

      _api.configure(server, token);
      _socket.connect(server, token);

      _user = User.fromJson(userData);
      _startHealthCheck();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', server);
      await prefs.setString('token', token);

      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _extractError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String server, String username, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _api.configure(server, '');
      final response = await _api.login(username, password);
      final token = response.data['token'] as String;
      final userData = response.data['user'] as Map<String, dynamic>;

      _api.configure(server, token);
      _socket.connect(server, token);

      _user = User.fromJson(userData);
      _startHealthCheck();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', server);
      await prefs.setString('token', token);

      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _extractError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _stopHealthCheck();
    _socket.disconnect();
    _api.clear();
    _user = null;
    _serverUnreachable = false;
    _unreachableServerAddress = null;

    final prefs = await SharedPreferences.getInstance();
    await _clearSavedData(prefs);

    notifyListeners();
  }

  void logoutFromServerError() {
    _stopHealthCheck();
    _socket.disconnect();
    _api.clear();
    _user = null;
    _serverUnreachable = false;
    _unreachableServerAddress = null;
    notifyListeners();
  }

  Future<bool> updateProfile({String? username, String? bio}) async {
    try {
      final response = await _api.updateProfile(username: username, bio: bio);
      _user = User.fromJson(response.data['user']);
      notifyListeners();
      return true;
    } catch (e) {
      _error = _extractError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateAvatar(String filePath) async {
    try {
      final response = await _api.updateAvatar(filePath);
      _user = User.fromJson(response.data['user'] as Map<String, dynamic>);
      notifyListeners();
      return true;
    } catch (e) {
      _error = _extractError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteAccount() async {
    try {
      await _api.deleteAccount();
      await logout();
      return true;
    } catch (e) {
      _error = _extractError(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> _clearSavedData(SharedPreferences prefs) async {
    await prefs.remove('server_url');
    await prefs.remove('token');
  }

  String _extractError(dynamic e) {
    if (e is Exception) {
      final errStr = e.toString();
      if (errStr.contains('error')) {
        try {
          final dioError = e as dynamic;
          if (dioError.response?.data != null) {
            return dioError.response.data['error'] ?? 'Unknown error';
          }
        } catch (_) {}
      }
      if (errStr.contains('SocketException') || errStr.contains('Connection refused')) {
        return 'Cannot connect to server';
      }
      return errStr.replaceAll('Exception: ', '');
    }
    return 'Unknown error';
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
