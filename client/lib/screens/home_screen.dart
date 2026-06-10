import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/language_provider.dart';
import '../widgets/chat_tile.dart';
import 'chat_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'create_group_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final chatProvider = context.read<ChatProvider>();
      if (auth.user != null) chatProvider.setCurrentUserId(auth.user!.id);
      chatProvider.loadChats();
      chatProvider.initSocketListeners();
    });
  }

  void _openChat(Map<String, dynamic> chat) {
    if (chat['type'] == 'group') {
      final chatId = chat['id'] as int;
      final name = chat['name'] as String;
      final username = chat['username'] as String? ?? '';
      final avatarPath = chat['avatar_path'] as String?;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            userId: 0,
            username: username,
            avatarPath: avatarPath,
            chatId: chatId,
            chatName: name,
          ),
        ),
      );
    } else {
      final userId = chat['user_id'] as int;
      final username = chat['username'] as String;
      final avatarPath = chat['avatar_path'] as String?;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            userId: userId,
            username: username,
            avatarPath: avatarPath,
          ),
        ),
      );
    }
  }

  void _createGroup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
  }

  Future<void> _logout() async {
    final t = context.read<LanguageProvider>().t;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.get('logout_title')),
        content: Text(t.get('logout_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.get('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.get('logout'))),
        ],
      ),
    );

    if (confirm == true) {
      await context.read<AuthProvider>().logout();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final t = context.watch<LanguageProvider>().t;
    final chats = chatProvider.chats;

    if (auth.serverUnreachable) {
      return _buildServerError(auth.unreachableServerAddress ?? '');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0 ? 'Eblan-Messenger' : _currentIndex == 1 ? t.get('search') : t.get('profile'),
        ),
        actions: [
          if (_currentIndex == 0) ...[
            IconButton(
              icon: const Icon(Icons.group_add),
              onPressed: _createGroup,
              tooltip: t.get('create_group'),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _currentIndex = 1),
            ),
          ],
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _currentIndex == 0
          ? _buildChatsList(chats)
          : _currentIndex == 1
              ? const SearchScreen()
              : const ProfileScreen(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.chat), label: t.get('chats')),
          BottomNavigationBarItem(icon: const Icon(Icons.search), label: t.get('search')),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: t.get('profile')),
        ],
      ),
    );
  }

  Widget _buildServerError(String address) {
    final t = context.read<LanguageProvider>().t;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              Text('Server "$address" is not responding', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text('Please check your connection or try again later', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500])),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  context.read<AuthProvider>().logoutFromServerError();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                child: Text(t.get('logout')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatsList(List<Map<String, dynamic>> chats) {
    final chatProvider = context.read<ChatProvider>();
    final t = context.read<LanguageProvider>().t;
    if (chatProvider.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(t.get('no_chats'), style: TextStyle(fontSize: 18, color: Colors.grey[500])),
            const SizedBox(height: 8),
            Text(t.get('no_chats_hint'), style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => chatProvider.loadChats(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: chats.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
        itemBuilder: (context, index) {
          final chat = chats[index];
          final type = chat['type'] as String? ?? 'dialog';

          if (type == 'group') {
            final chatId = chat['id'] as int;
            final name = chat['name'] as String;
            final username = chat['username'] as String?;
            final avatarPath = chat['avatar_path'] as String?;
            final lastMsg = chat['last_message_text'] as String?;

            return ChatTile(
              username: name,
              lastMessage: lastMsg,
              avatarPath: avatarPath,
              onTap: () => _openChat(chat),
              isGroup: true,
            );
          } else {
            final userId = chat['user_id'] as int? ?? (chat['peer_id'] as int);
            final username = chat['username'] as String? ?? 'Unknown';
            final avatarPath = chat['avatar_path'] as String?;
            final lastMsg = chat['last_message_text'] as String?;

            return ChatTile(
              username: username,
              lastMessage: lastMsg,
              avatarPath: avatarPath,
              isOnline: chatProvider.isOnline(userId),
              onTap: () => _openChat(chat),
            );
          }
        },
      ),
    );
  }
}
