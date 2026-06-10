import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class ChatTile extends StatelessWidget {
  final String username;
  final String? lastMessage;
  final String? avatarPath;
  final bool isOnline;
  final bool isGroup;
  final VoidCallback onTap;

  const ChatTile({
    super.key,
    required this.username,
    this.lastMessage,
    this.avatarPath,
    this.isOnline = false,
    this.isGroup = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final avatarUrl = avatarPath != null ? auth.api.getFileUrl(avatarPath!) : null;

    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(30),
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Icon(
                    isGroup ? Icons.group : Icons.person,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  )
                : null,
          ),
          if (isOnline && !isGroup)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
      title: Text(username, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: lastMessage != null && lastMessage!.isNotEmpty
          ? Text(lastMessage!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[500]))
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    );
  }
}
