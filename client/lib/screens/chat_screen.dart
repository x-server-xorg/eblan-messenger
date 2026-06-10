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
  final int? chatId;
  final String? chatName;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.username,
    this.avatarPath,
    this.chatId,
    this.chatName,
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

  bool get isGroup => widget.chatId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      if (isGroup) {
        chatProvider.setSelectedGroupChat(widget.chatId);
        chatProvider.loadGroupMessages(widget.chatId!);
        chatProvider.socket.joinChat(widget.chatId!);
      } else {
        chatProvider.setSelectedChat(widget.userId);
        chatProvider.loadMessages(widget.userId);
      }
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
    if (isGroup) {
      chatProvider.sendStopTyping(widget.userId, chatId: widget.chatId);
      chatProvider.socket.leaveChat(widget.chatId!);
    } else {
      chatProvider.sendStopTyping(widget.userId);
      chatProvider.sendStopRecordingAudio(widget.userId);
    }
    chatProvider.setSelectedChat(null);
    chatProvider.setSelectedGroupChat(null);
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
      chatProvider.sendTyping(widget.userId, chatId: widget.chatId);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        chatProvider.sendStopTyping(widget.userId, chatId: widget.chatId);
      }
    });
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    context.read<ChatProvider>().sendMessage(
      receiverId: widget.userId,
      chatId: widget.chatId,
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
      chatId: widget.chatId,
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
      if (mounted) setState(() => _elapsedSeconds++);
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

  void _showMessageActions(int messageId, bool isMyMessage) {
    if (!isMyMessage) return;

    showDialog(
      context: context,
      builder: (ctx) {
        bool deleteForAll = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(context.read<LanguageProvider>().t.get('delete_message')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isGroup) ...[
                  CheckboxListTile(
                    title: Text(context.read<LanguageProvider>().t.get('delete_for_all')),
                    value: deleteForAll,
                    onChanged: (v) => setDialogState(() => deleteForAll = v ?? false),
                  ),
                ],
                Text(context.read<LanguageProvider>().t.get('delete_confirm_short')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.read<LanguageProvider>().t.get('cancel')),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.read<ChatProvider>().deleteMessage(messageId, forAll: deleteForAll);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(context.read<LanguageProvider>().t.get('delete')),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showUserMenu() {
    final t = context.read<LanguageProvider>().t;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: Text(t.get('block_user')),
              onTap: () {
                Navigator.pop(ctx);
                _blockUser();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: Text(t.get('delete_chat')),
              onTap: () {
                Navigator.pop(ctx);
                _deleteChat();
              },
            ),
            if (isGroup)
              ListTile(
                leading: const Icon(Icons.person_add),
                title: Text(t.get('invite_user')),
                onTap: () {
                  Navigator.pop(ctx);
                  _showInviteDialog();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _blockUser() async {
    final t = context.read<LanguageProvider>().t;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.get('block_user')),
        content: Text(t.get('block_confirm').replaceFirst('{username}', widget.username)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.get('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.get('block')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await context.read<AuthProvider>().blockUser(widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.get('user_blocked').replaceFirst('{username}', widget.username))),
        );
      }
    }
  }

  Future<void> _deleteChat() async {
    final chatProvider = context.read<ChatProvider>();
    final t = context.read<LanguageProvider>().t;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.get('delete_chat')),
        content: Text(t.get('delete_chat_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.get('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.get('delete')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (isGroup) {
        await chatProvider.deleteChat(widget.chatId!);
      } else {
        await chatProvider.deleteChat(widget.userId);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  void _showInviteDialog() {
    final searchCtrl = TextEditingController();
    final t = context.read<LanguageProvider>().t;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.get('invite_user')),
        content: TextField(
          controller: searchCtrl,
          decoration: InputDecoration(hintText: '@username'),
          autofocus: true,
          onSubmitted: (val) async {
            if (val.trim().isEmpty) return;
            try {
              final api = context.read<AuthProvider>().api;
              final resp = await api.searchUsers(val.trim());
              final users = resp.data['users'] as List;
              if (users.isEmpty) {
                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.get('user_not_found'))));
                return;
              }
              final user = users[0] as Map<String, dynamic>;
              final success = await context.read<ChatProvider>().inviteToChat(widget.chatId!, user['id'] as int);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(success ? t.get('user_invited') : t.get('invite_failed')),
                  backgroundColor: success ? Colors.green : Colors.red,
                ));
              }
            } catch (_) {
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.get('invite_failed')), backgroundColor: Colors.red));
              }
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.get('cancel'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final t = context.watch<LanguageProvider>().t;
    final messages = isGroup
        ? chatProvider.getGroupMessages(widget.chatId!) ?? []
        : chatProvider.getMessages(widget.userId) ?? [];
    final isTyping = chatProvider.isTyping(widget.userId);
    final isRecordingAudio = chatProvider.isRecordingAudio(widget.userId);
    final isOnline = chatProvider.isOnline(widget.userId);
    final auth = context.read<AuthProvider>();
    final currentUserId = auth.user!.id;
    final displayName = isGroup ? (widget.chatName ?? widget.username) : widget.username;

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
                      (widget.username.startsWith('@') ? widget.username[1] : widget.username[0]).toUpperCase(),
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
                Text(displayName, style: const TextStyle(fontSize: 16)),
                if (isRecordingAudio || _showRecordingPanel)
                  Text(t.get('recording_audio'), style: const TextStyle(fontSize: 12, color: Colors.red))
                else if (isTyping)
                  Text(t.get('typing'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary))
                else if (isOnline && !isGroup)
                  Text(t.get('online'), style: const TextStyle(fontSize: 12, color: Colors.green))
                else if (!isGroup)
                  Text(t.get('offline'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'menu':
                  _showUserMenu();
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'menu', child: Text(t.get('actions'))),
            ],
          ),
        ],
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
                      return GestureDetector(
                        onLongPress: isMe ? () => _showMessageActions(message.id, true) : null,
                        child: MessageBubble(
                          message: message,
                          isMe: isMe,
                          serverUrl: auth.api.serverUrl,
                        ),
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
    return _buildNormalInput();
  }

  Widget _buildRecordingTimer() {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    final timerText = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return Center(
      child: Text(
        timerText,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }

  Widget _buildNormalInput() {
    final t = context.read<LanguageProvider>().t;
    final isCancelZone = _recordingDragOffset < _cancelThreshold;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        border: Border(top: BorderSide(color: Colors.grey.withAlpha(30))),
      ),
      child: Row(
        children: [
          if (_showRecordingPanel)
            SizedBox(width: 48, height: 48, child: Icon(Icons.delete_outline, color: isCancelZone ? Colors.red : Colors.grey, size: 28))
          else
            _buildAttachmentButton(),
          const SizedBox(width: 8),
          Expanded(
            child: _showRecordingPanel
                ? _buildRecordingTimer()
                : TextField(
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
          if (!_showRecordingPanel && _textController.text.isNotEmpty)
            IconButton(icon: const Icon(Icons.send, color: Color(0xFF2AABEE)), onPressed: _sendText),
          AudioRecordWidget(
            key: const ValueKey('audio_record'),
            onComplete: _sendVoiceMessage,
            onRecordingStart: _onRecordingStart,
            onRecordingEnd: _onRecordingEnd,
            onDragDelta: _onRecordingDragDelta,
            onCancel: _onRecordingCancel,
            isCancelZone: _showRecordingPanel && _recordingDragOffset < _cancelThreshold,
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
          case 'image': _pickImage(); break;
          case 'video': _pickVideo(); break;
          case 'file': _pickFile(); break;
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
