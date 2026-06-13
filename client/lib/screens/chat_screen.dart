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
  final _inputKey = GlobalKey();
  Timer? _typingTimer;
  bool _isTyping = false;

  bool _showRecordingPanel = false;
  double _recordingDragOffset = 0;
  int _elapsedSeconds = 0;
  Timer? _recordingTimer;

  List<Map<String, dynamic>> _members = [];
  String _mentionQuery = '';
  int? _mentionStart;
  final LayerLink _mentionLayer = LayerLink();
  OverlayEntry? _mentionOverlay;

  static const double _cancelThreshold = -80;

  bool get isGroup => widget.chatId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      
      // Ensure socket is connected before using it
      if (chatProvider.socket?.isConnected != true) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _initChat();
        });
      } else {
        _initChat();
      }
    });
    _textController.addListener(_onMentionChanged);
  }

  void _initChat() {
    final chatProvider = context.read<ChatProvider>();
    if (isGroup) {
      chatProvider.setSelectedGroupChat(widget.chatId);
      chatProvider.loadGroupMessages(widget.chatId!);
      if (chatProvider.socket?.isConnected == true) {
        chatProvider.socket.joinChat(widget.chatId!);
      }
      _loadMembersWithRetry();
    } else {
      chatProvider.setSelectedChat(widget.userId);
      chatProvider.loadMessages(widget.userId);
    }
  }

  Future<void> _loadMembersWithRetry({int retryCount = 0}) async {
    const maxRetries = 3;
    try {
      final api = context.read<AuthProvider>().api;
      final resp = await api.getChat(widget.chatId!);
      final chat = resp.data['chat'] as Map<String, dynamic>;
      if (mounted) {
        setState(() => _members = (chat['members'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (retryCount < maxRetries && mounted) {
        Future.delayed(Duration(seconds: retryCount + 1), () {
          if (mounted) _loadMembersWithRetry(retryCount: retryCount + 1);
        });
      }
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onMentionChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _removeMentionOverlay();
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

  void _onMentionChanged() {
    if (!isGroup) return;
    final text = _textController.text;
    final sel = _textController.selection.baseOffset;
    if (sel <= 0) { _removeMentionOverlay(); return; }

    final before = text.substring(0, sel);
    final atIdx = before.lastIndexOf('@');
    if (atIdx >= 0 && (atIdx == 0 || before[atIdx - 1] == ' ')) {
      final query = before.substring(atIdx + 1);
      final isOnlyAlpha = RegExp(r'^[a-zA-Z0-9_]*$').hasMatch(query);
      if (!isOnlyAlpha) { _removeMentionOverlay(); return; }
      _mentionStart = atIdx;
      _mentionQuery = query;
      _showMentionOverlay();
    } else {
      _removeMentionOverlay();
    }
  }

  void _showMentionOverlay() {
    _removeMentionOverlay();
    final filtered = _members.where((m) {
      final username = (m['username'] as String?)?.toLowerCase() ?? '';
      return username.contains(_mentionQuery.toLowerCase()) && m['id'] != context.read<AuthProvider>().user!.id;
    }).toList();
    if (filtered.isEmpty) return;

    final overlay = Overlay.of(context);
    final renderBox = _inputKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _mentionOverlay = OverlayEntry(
      builder: (ctx) {
        final chatProvider = context.read<ChatProvider>();
        final authProvider = context.read<AuthProvider>();
        final myId = authProvider.user!.id;
        return Positioned(
          width: 250,
          child: CompositedTransformFollower(
            link: _mentionLayer,
            offset: Offset(0, renderBox.size.height + 4),
            targetAnchor: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final m = filtered[i];
                    final uname = (m['username'] as String?) ?? '';
                    final name = uname.startsWith('@') ? uname : '@$uname';
                    final role = (m['role'] as String?) ?? 'member';
                    final isAdmin = role == 'admin' || role == 'creator';
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.blue.withAlpha(30),
                        child: Text(
                          name.length > 1 ? name[1].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontSize: 14)),
                      trailing: isAdmin ? const Icon(Icons.shield, size: 16, color: Colors.amber) : null,
                      onTap: () {
                        _insertMention(name);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_mentionOverlay!);
  }

  void _removeMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
  }

  void _insertMention(String name) {
    if (_mentionStart == null) return;
    final text = _textController.text;
    final sel = _textController.selection.baseOffset;
    final newText = '${text.substring(0, _mentionStart!)}$name ${text.substring(sel)}';
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: _mentionStart! + name.length + 1),
    );
    _removeMentionOverlay();
    _focusNode.requestFocus();
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

  bool _isAdmin() {
    final myId = context.read<AuthProvider>().user!.id;
    final me = _members.where((m) => m['id'] == myId).firstOrNull;
    if (me == null) return false;
    final role = (me['role'] as String?) ?? 'member';
    return role == 'admin' || role == 'creator';
  }

  void _showMessageActions(int messageId, bool isMyMessage) {
    final t = context.read<LanguageProvider>().t;
    final isAdmin = _isAdmin();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMyMessage)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(t.get('delete_message')),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteConfirm(messageId);
                },
              ),
            if (isGroup && isAdmin)
              ListTile(
                leading: const Icon(Icons.push_pin, color: Colors.blue),
                title: Text(t.get('pin_message')),
                onTap: () {
                  Navigator.pop(ctx);
                  _pinMessage(messageId);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(int messageId) {
    final t = context.read<LanguageProvider>().t;
    showDialog(
      context: context,
      builder: (ctx) {
        bool deleteForAll = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(t.get('delete_message')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isGroup) CheckboxListTile(
                  title: Text(t.get('delete_for_all')),
                  value: deleteForAll,
                  onChanged: (v) => setDialogState(() => deleteForAll = v ?? false),
                ),
                Text(t.get('delete_confirm_short')),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.get('cancel'))),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.read<ChatProvider>().deleteMessage(messageId, forAll: deleteForAll);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(t.get('delete')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pinMessage(int messageId) async {
    final chatProvider = context.read<ChatProvider>();
    final success = await chatProvider.pinMessage(widget.chatId!, messageId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? 'Message pinned' : 'Failed to pin message'),
        backgroundColor: success ? Colors.green : Colors.red,
      ));
    }
  }

  void _showUserMenu() {
    final t = context.read<LanguageProvider>().t;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isGroup)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(t.get('group_info')),
                onTap: () {
                  Navigator.pop(ctx);
                  _openGroupInfo();
                },
              ),
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

  void _openGroupInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<ChatProvider>(),
          child: _GroupInfoScreen(
            chatId: widget.chatId!,
            chatName: widget.chatName ?? widget.username,
            myId: context.read<AuthProvider>().user!.id,
          ),
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
                if (success) _loadMembers();
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
        title: GestureDetector(
          onTap: isGroup ? () => _openGroupInfo() : null,
          child: Row(
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
                        onLongPress: () => _showMessageActions(message.id, isMe),
                        child: MessageBubble(
                          message: message,
                          isMe: isMe,
                          serverUrl: auth.api.serverUrl,
                          currentUserId: currentUserId,
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
    final hasText = _textController.text.trim().isNotEmpty;

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
                : CompositedTransformTarget(
                    link: _mentionLayer,
                    child: TextField(
                      key: _inputKey,
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
          ),
          const SizedBox(width: 8),
          if (!_showRecordingPanel)
            IconButton(
              icon: Icon(
                hasText ? Icons.send : Icons.mic,
                color: hasText ? const Color(0xFF2AABEE) : Colors.grey,
              ),
              onPressed: hasText ? _sendText : null,
            ),
          if (!_showRecordingPanel && !hasText)
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

class _GroupInfoScreen extends StatefulWidget {
  final int chatId;
  final String chatName;
  final int myId;

  const _GroupInfoScreen({required this.chatId, required this.chatName, required this.myId});

  @override
  State<_GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<_GroupInfoScreen> {
  Map<String, dynamic>? _chat;
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AuthProvider>().api;
      final resp = await api.getChat(widget.chatId);
      final chat = resp.data['chat'] as Map<String, dynamic>;
      setState(() {
        _chat = chat;
        _members = (chat['members'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  bool _isAdmin(int userId) {
    final m = _members.where((m) => m['id'] == userId).firstOrNull;
    if (m == null) return false;
    final role = (m['role'] as String?) ?? 'member';
    return role == 'admin' || role == 'creator';
  }

  bool _isCreator(int userId) {
    final m = _members.where((m) => m['id'] == userId).firstOrNull;
    return (m?['role'] as String?) == 'creator';
  }

  bool get _iCanAdmin {
    return _isCreator(widget.myId);
  }

  Future<void> _removeMember(int userId, String username) async {
    final t = context.read<LanguageProvider>().t;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.get('remove_member')),
        content: Text('Remove $username from group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.get('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.get('remove')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final success = await context.read<ChatProvider>().removeMember(widget.chatId, userId);
      if (success) _load();
    }
  }

  Future<void> _promoteMember(int userId) async {
    await context.read<ChatProvider>().promoteMember(widget.chatId, userId);
    _load();
  }

  Future<void> _demoteMember(int userId) async {
    await context.read<ChatProvider>().demoteMember(widget.chatId, userId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LanguageProvider>().t;
    final auth = context.read<AuthProvider>();
    final theme = Theme.of(context);

    if (_loading) return Scaffold(appBar: AppBar(title: Text(widget.chatName)), body: const Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: Text(t.get('group_info'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.primary.withAlpha(30),
              backgroundImage: _chat?['avatar_path'] != null
                  ? NetworkImage(auth.api.getFileUrl(_chat!['avatar_path'] as String))
                  : null,
              child: _chat?['avatar_path'] == null
                  ? Text(
                      (widget.chatName.startsWith('@') ? widget.chatName[1] : widget.chatName[0]).toUpperCase(),
                      style: TextStyle(fontSize: 28, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(widget.chatName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          if (_chat?['description'] != null && (_chat!['description'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(child: Text(_chat!['description'] as String, style: TextStyle(color: Colors.grey[600]))),
            ),
          if (_chat?['username'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Center(child: Text(_chat!['username'] as String, style: TextStyle(color: Colors.grey[500], fontSize: 13))),
            ),
          const SizedBox(height: 16),
          if (_iCanAdmin) ...[
            Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.settings, size: 18),
                        const SizedBox(width: 8),
                        Text(t.get('group_settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: Text(t.get('admins_only_mode')),
                    subtitle: Text(t.get('admins_only_hint')),
                    value: _chat?['admins_only'] == 1,
                    onChanged: (v) async {
                      await context.read<ChatProvider>().updateGroup(widget.chatId, adminsOnly: v);
                      _load();
                    },
                  ),
                  ListTile(
                    title: Text(t.get('invite_permission')),
                    subtitle: Text(_chat?['invite_permission'] == 'admins' ? t.get('only_admins') : t.get('everyone')),
                    trailing: DropdownButton<String>(
                      value: (_chat?['invite_permission'] as String?) ?? 'everyone',
                      items: [
                        DropdownMenuItem(value: 'everyone', child: Text(t.get('everyone'))),
                        DropdownMenuItem(value: 'admins', child: Text(t.get('only_admins'))),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await context.read<ChatProvider>().updateGroup(widget.chatId, invitePermission: v);
                        _load();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('${t.get('members')} (${_members.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...List.generate(_members.length, (i) {
            final m = _members[i];
            final uid = m['id'] as int;
            final uname = (m['username'] as String?) ?? '';
            final avatar = m['avatar_path'] as String?;
            final role = (m['role'] as String?) ?? 'member';
            final isMe = uid == widget.myId;
            final isAdmin = role == 'admin' || role == 'creator';
            return ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.primary.withAlpha(30),
                backgroundImage: avatar != null ? NetworkImage(auth.api.getFileUrl(avatar)) : null,
                child: avatar == null
                    ? Text(uname.length > 1 ? uname[1].toUpperCase() : '?',
                        style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14))
                    : null,
              ),
              title: Text(uname),
              subtitle: isAdmin ? Text(_isCreator(uid) ? t.get('creator') : t.get('admin'), style: const TextStyle(color: Colors.amber, fontSize: 12)) : null,
              trailing: isMe
                  ? null
                  : PopupMenuButton(
                      itemBuilder: (_) {
                        final items = <PopupMenuEntry<String>>[];
                        if (_iCanAdmin || role == 'member') {
                          if (role == 'member') {
                            items.add(PopupMenuItem(value: 'promote', child: Text(t.get('promote_admin'))));
                          }
                          items.add(PopupMenuItem(value: 'remove', child: Text(t.get('remove_member'), style: const TextStyle(color: Colors.red))));
                          if (role == 'admin' && _iCanAdmin) {
                            items.add(PopupMenuItem(value: 'demote', child: Text(t.get('demote_admin'))));
                          }
                        }
                        return items;
                      },
                      onSelected: (v) async {
                        switch (v) {
                          case 'promote':
                            await _promoteMember(uid);
                            break;
                          case 'demote':
                            await _demoteMember(uid);
                            break;
                          case 'remove':
                            await _removeMember(uid, uname);
                            break;
                        }
                      },
                    ),
            );
          }),
        ],
      ),
    );
  }
}
