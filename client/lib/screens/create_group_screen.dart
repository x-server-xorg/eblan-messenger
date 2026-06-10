import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/language_provider.dart';
import '../models/user.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final Set<int> _selectedIds = {};
  List<User> _searchResults = [];
  bool _searching = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final api = context.read<AuthProvider>().api;
      final resp = await api.searchUsers(q.trim());
      final users = (resp.data['users'] as List)
          .map((u) => User.fromJson(u as Map<String, dynamic>))
          .toList();
      setState(() => _searchResults = users);
    } catch (_) {}
    setState(() => _searching = false);
  }

  Future<void> _create() async {
    final t = context.read<LanguageProvider>().t;
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();

    if (name.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fill all fields')));
      return;
    }

    if (!username.startsWith('@')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.get('username_at'))));
      return;
    }

    final chatProvider = context.read<ChatProvider>();
    final success = await chatProvider.createGroup(name, username, _selectedIds.toList());

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Group created')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(chatProvider.error ?? 'Failed to create group'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LanguageProvider>().t;
    final auth = context.read<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(t.get('create_group'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: t.get('group_name')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameCtrl,
              decoration: InputDecoration(labelText: t.get('group_username')),
            ),
            const SizedBox(height: 24),
            Text(t.get('select_members'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            if (_selectedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  children: _selectedIds.map((id) {
                    final user = _searchResults.where((u) => u.id == id).firstOrNull;
                    if (user == null) return const SizedBox.shrink();
                    return Chip(
                      label: Text(user.username),
                      onDeleted: () => setState(() => _selectedIds.remove(id)),
                    );
                  }).toList(),
                ),
              ),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: t.get('search_hint'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            if (_searching) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
            if (_searchResults.isNotEmpty)
              SizedBox(
                height: 200,
                child: ListView(
                  children: _searchResults.map((user) {
                    final selected = _selectedIds.contains(user.id);
                    return CheckboxListTile(
                      title: Text(user.username),
                      subtitle: user.bio.isNotEmpty ? Text(user.bio, maxLines: 1) : null,
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedIds.add(user.id);
                          } else {
                            _selectedIds.remove(user.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _create,
              child: Text(t.get('create')),
            ),
          ],
        ),
      ),
    );
  }
}
