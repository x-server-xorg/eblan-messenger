class Message {
  final int id;
  final int senderId;
  final int receiverId;
  final String senderUsername;
  final String text;
  final String? filePath;
  final String? fileType;
  final String? fileName;
  final int? fileSize;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.senderUsername = '',
    this.text = '',
    this.filePath,
    this.fileType,
    this.fileName,
    this.fileSize,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as int,
      senderId: json['sender_id'] as int,
      receiverId: json['receiver_id'] as int,
      senderUsername: (json['sender_username'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
      filePath: json['file_path'] as String?,
      fileType: json['file_type'] as String?,
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] as int?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  bool get isImage => fileType?.startsWith('image/') ?? false;
  bool get isVideo => fileType?.startsWith('video/') ?? false;
  bool get isAudio => fileType?.startsWith('audio/') ?? false;
  bool get isFile => filePath != null && !isImage && !isVideo && !isAudio;

  String get fileExtension {
    if (fileName == null) return '';
    return fileName!.split('.').last.toUpperCase();
  }
}
