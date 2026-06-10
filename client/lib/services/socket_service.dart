// ignore_for_file: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  IO.Socket? _socket;
  void connect(String serverUrl, String token) {
    _socket = IO.io('http://$serverUrl', IO.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token})
      .enableForceNew()
      .build());

    _socket?.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  IO.Socket? get socket => _socket;

  bool get isConnected => _socket?.connected ?? false;

  void sendMessage({
    required int receiverId,
    String text = '',
    String? filePath,
    String? fileType,
    String? fileName,
    int? fileSize,
  }) {
    _socket?.emit('message:send', {
      'receiverId': receiverId,
      'text': text,
      'file_path': filePath,
      'file_type': fileType,
      'file_name': fileName,
      'file_size': fileSize,
    });
  }

  void sendTyping(int receiverId) {
    _socket?.emit('user:typing', {'receiverId': receiverId});
  }

  void sendStopTyping(int receiverId) {
    _socket?.emit('user:stop_typing', {'receiverId': receiverId});
  }

  void sendRecordingAudio(int receiverId) {
    _socket?.emit('user:recording_audio', {'receiverId': receiverId});
  }

  void sendStopRecordingAudio(int receiverId) {
    _socket?.emit('user:stop_recording_audio', {'receiverId': receiverId});
  }

  void onMessageReceived(void Function(dynamic data) callback) {
    _socket?.on('message:received', callback);
  }

  void onUserTyping(void Function(dynamic data) callback) {
    _socket?.on('user:typing', callback);
  }

  void onUserStopTyping(void Function(dynamic data) callback) {
    _socket?.on('user:stop_typing', callback);
  }

  void onUserRecordingAudio(void Function(dynamic data) callback) {
    _socket?.on('user:recording_audio', callback);
  }

  void onUserStopRecordingAudio(void Function(dynamic data) callback) {
    _socket?.on('user:stop_recording_audio', callback);
  }

  void onUserOnline(void Function(dynamic data) callback) {
    _socket?.on('user:online', callback);
  }

  void onUserOffline(void Function(dynamic data) callback) {
    _socket?.on('user:offline', callback);
  }

  void onDisconnect(void Function() callback) {
    _socket?.on('disconnect', (_) => callback());
  }

  void onConnectError(void Function(dynamic data) callback) {
    _socket?.on('connect_error', callback);
  }

  void removeListener(String event) {
    _socket?.off(event);
  }
}
