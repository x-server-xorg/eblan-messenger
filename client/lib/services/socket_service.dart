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
    int? chatId,
    String text = '',
    String? filePath,
    String? fileType,
    String? fileName,
    int? fileSize,
  }) {
    _socket?.emit('message:send', {
      'receiverId': receiverId,
      'chatId': chatId,
      'text': text,
      'file_path': filePath,
      'file_type': fileType,
      'file_name': fileName,
      'file_size': fileSize,
    });
  }

  void deleteMessage(int messageId, {bool forAll = false}) {
    _socket?.emit('message:delete', {
      'messageId': messageId,
      'forAll': forAll,
    });
  }

  void sendTyping(int receiverId, {int? chatId}) {
    _socket?.emit('user:typing', {'receiverId': receiverId, 'chatId': chatId});
  }

  void sendStopTyping(int receiverId, {int? chatId}) {
    _socket?.emit('user:stop_typing', {'receiverId': receiverId, 'chatId': chatId});
  }

  void sendRecordingAudio(int receiverId) {
    _socket?.emit('user:recording_audio', {'receiverId': receiverId});
  }

  void sendStopRecordingAudio(int receiverId) {
    _socket?.emit('user:stop_recording_audio', {'receiverId': receiverId});
  }

  void joinChat(int chatId) {
    _socket?.emit('chat:join', {'chatId': chatId});
  }

  void leaveChat(int chatId) {
    _socket?.emit('chat:leave', {'chatId': chatId});
  }

  void onMessageReceived(void Function(dynamic data) callback) {
    _socket?.on('message:received', callback);
  }

  void onMessageDeleted(void Function(dynamic data) callback) {
    _socket?.on('message:deleted', callback);
  }

  void onMessageError(void Function(dynamic data) callback) {
    _socket?.on('message:error', callback);
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
