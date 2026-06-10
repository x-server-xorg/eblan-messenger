import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/language_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/audio_record_widget.dart';

class ChatScreen extends StatefulWidget {
  final int userId;
  final String username;
  final String? avatarPath;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.username,
    this.avatarPath,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  Timer? _typingTimer;
  bool _isTyping = false;

  bool _showRecordingPanel = false;
  double _recordingDragOffset = 0;
  int _elapsedSeconds = 0;
  Timer? _recordingTimer;

  static const double _cancelThreshold = -80;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      chatProvider.setSelectedChat(widget.userId);
      chatProvider.loadMessages(widget.userId);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    final chatProvider = context.read<ChatProvider>();
    chatProvider.sendStopTyping(widget.userId);
    chatProvider.sendStopRecordingAudio(widget.userId);
    chatProvider.setSelectedChat(null);
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text) {
    final chatProvider = context.read<ChatProvider>();
    if (text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      chatProvider.sendTyping(widget.userId);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        chatProvider.sendStopTyping(widget.userId);
      }
    });
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    context.read<ChatProvider>().sendMessage(
      receiverId: widget.userId,
      text: text,
    );

    _textController.clear();
    _isTyping = false;
    _typingTimer?.cancel();
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _sendFile(picked.path, picked.name);
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _sendFile(picked.path, picked.name);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    await _sendFile(file.path!, file.name);
  }

  Future<void> _sendFile(String filePath, String fileName) async {
    final chatProvider = context.read<ChatProvider>();
    final t = context.read<LanguageProvider>().t;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.get('uploading')), duration: const Duration(seconds: 1)),
    );

    final uploadResult = await chatProvider.uploadFile(filePath, fileName);
    if (uploadResult == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.get('upload_failed')), backgroundColor: Colors.red),
      );
      return;
    }

    chatProvider.sendMessage(
      receiverId: widget.userId,
      filePath: uploadResult['file_path'] as String,
      fileType: uploadResult['file_type'] as String,
      fileName: uploadResult['file_name'] as String,
      fileSize: uploadResult['file_size'] as int?,
    );

    _scrollToBottom();
  }

  void _onRecordingStart() {
    setState(() {
      _showRecordingPanel = true;
      _recordingDragOffset = 0;
      _elapsedSeconds = 0;
    });
    context.read<ChatProvider>().sendRecordingAudio(widget.userId);
    _isTyping = false;
    _typingTimer?.cancel();

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  void _onRecordingEnd() {
    _recordingTimer?.cancel();
    context.read<ChatProvider>().sendStopRecordingAudio(widget.userId);
  }

  void _onRecordingDragDelta(double delta) {
    setState(() => _recordingDragOffset = delta);
  }

  void _onRecordingCancel() {
    setState(() => _showRecordingPanel = false);
  }

  Future<void> _sendVoiceMessage(String audioPath) async {
    setState(() => _showRecordingPanel = false);
    await _sendFile(audioPath, 'voice_message.ogg');
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final t = context.watch<LanguageProvider>().t;
    final messages = chatProvider.getMessages(widget.userId) ?? [];
    final isTyping = chatProvider.isTyping(widget.userId);
    final isRecordingAudio = chatProvider.isRecordingAudio(widget.userId);
    final isOnline = chatProvider.isOnline(widget.userId);
    final auth = context.read<AuthProvider>();
    final currentUserId = auth.user!.id;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(30),
              backgroundImage: widget.avatarPath != null
                  ? NetworkImage(auth.api.getFileUrl(widget.avatarPath!))
                  : null,
              child: widget.avatarPath == null
                  ? Text(
                      widget.username[1].toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.username, style: const TextStyle(fontSize: 16)),
                if (isRecordingAudio || _showRecordingPanel)
                  Text(t.get('recording_audio'), style: const TextStyle(fontSize: 12, color: Colors.red))
                else if (isTyping)
                  Text(t.get('typing'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary))
                else if (isOnline)
                  Text(t.get('online'), style: TextStyle(fontSize: 12, color: Colors.green))
                else
                  Text(t.get('offline'), style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      t.get('no_messages'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == currentUserId;
                      return MessageBubble(
                        message: message,
                        isMe: isMe,
                        serverUrl: auth.api.serverUrl,
                      );
                    },
                  ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    if (_showRecordingPanel) {
      return _buildRecordingPanel();
    }
    return _buildNormalInput();
  }

  Widget _buildRecordingPanel() {
    final isCancelZone = _recordingDragOffset < _cancelThreshold;
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    final timerText = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        border: Border(
          top: BorderSide(color: Colors.grey.withAlpha(30)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              Icons.delete_outline,
              color: isCancelZone ? Colors.red : Colors.grey,
              size: 28,
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                timerText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              Icons.mic,
              color: Colors.red,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalInput() {
    final t = context.read<LanguageProvider>().t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        border: Border(
          top: BorderSide(color: Colors.grey.withAlpha(30)),
        ),
      ),
      child: Row(
        children: [
          _buildAttachmentButton(),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              onChanged: _onTextChanged,
              decoration: InputDecoration(
                hintText: t.get('message_hint'),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendText(),
            ),
          ),
          const SizedBox(width: 8),
          _textController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF2AABEE)),
                  onPressed: _sendText,
                )
              : AudioRecordWidget(
                  onComplete: _sendVoiceMessage,
                  onRecordingStart: _onRecordingStart,
                  onRecordingEnd: _onRecordingEnd,
                  onDragDelta: _onRecordingDragDelta,
                  onCancel: _onRecordingCancel,
                ),
        ],
      ),
    );
  }

  Widget _buildAttachmentButton() {
    final t = context.read<LanguageProvider>().t;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.attach_file),
      onSelected: (value) {
        switch (value) {
          case 'image':
            _pickImage();
            break;
          case 'video':
            _pickVideo();
            break;
          case 'file':
            _pickFile();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'image', child: ListTile(leading: const Icon(Icons.image), title: Text(t.get('photo')))),
        PopupMenuItem(value: 'video', child: ListTile(leading: const Icon(Icons.videocam), title: Text(t.get('video')))),
        PopupMenuItem(value: 'file', child: ListTile(leading: const Icon(Icons.file_present), title: Text(t.get('file')))),
      ],
    );
  }
}
