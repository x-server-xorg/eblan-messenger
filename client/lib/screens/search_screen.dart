import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../models/user.dart';
import 'chat_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<User> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _searching = true);

    try {
      final api = context.read<AuthProvider>().api;
      final response = await api.searchUsers(query.trim());
      final usersList = (response.data['users'] as List)
          .map((u) => User.fromJson(u as Map<String, dynamic>))
          .toList();
      setState(() => _results = usersList);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e'), backgroundColor: Colors.red),
        );
      }
    }

    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LanguageProvider>().t;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: t.get('search_hint'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _results = []);
                      },
                    )
                  : null,
            ),
            onChanged: _search,
            autofocus: true,
          ),
        ),
        Expanded(
          child: _searching
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? t.get('search_empty')
                            : t.get('search_not_found'),
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
                      itemBuilder: (context, index) {
                        final user = _results[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(30),
                            backgroundImage: user.avatarPath != null
                                ? NetworkImage(
                                    context.read<AuthProvider>().api.getFileUrl(user.avatarPath!),
                                  )
                                : null,
                            child: user.avatarPath == null
                                ? Text(
                                    (user.username.startsWith('@') ? user.username[1] : user.username[0]).toUpperCase(),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(user.username),
                          subtitle: user.bio.isNotEmpty ? Text(user.bio, maxLines: 1) : null,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  userId: user.id,
                                  username: user.username,
                                  avatarPath: user.avatarPath,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
