import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/theme_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    if (user != null) {
      _usernameController.text = user.username;
      _bioController.text = user.bio;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512);
    if (picked == null) return;

    final auth = context.read<AuthProvider>();
    final t = context.read<LanguageProvider>().t;
    final success = await auth.updateAvatar(picked.path);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? t.get('avatar_updated') : t.get('avatar_failed')),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);

    final auth = context.read<AuthProvider>();
    final t = context.read<LanguageProvider>().t;
    final success = await auth.updateProfile(
      username: _usernameController.text.trim(),
      bio: _bioController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.get('profile_updated')), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? t.get('update_failed')), backgroundColor: Colors.red),
      );
    }

    setState(() => _saving = false);
  }

  Future<void> _deleteAccount() async {
    final t = context.read<LanguageProvider>().t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.get('delete_title')),
        content: Text(t.get('delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.get('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.get('delete_account')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final auth = context.read<AuthProvider>();
      final success = await auth.deleteAccount();
      if (!mounted) return;

      if (success) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Scaffold()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final themeProv = context.watch<ThemeProvider>();
    final langProv = context.watch<LanguageProvider>();
    final t = langProv.t;
    final user = auth.user;
    final theme = Theme.of(context);

    if (user == null) return const Center(child: Text('Not logged in'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickAvatar,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: theme.colorScheme.primary.withAlpha(30),
                  backgroundImage: user.avatarPath != null
                      ? NetworkImage(auth.api.getFileUrl(user.avatarPath!))
                      : null,
                  child: user.avatarPath == null
                      ? Text(
                          user.username[1].toUpperCase(),
                          style: TextStyle(
                            fontSize: 36,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _pickAvatar, child: Text(t.get('change_photo'))),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_editing) ...[
                    _infoRow(t.get('username_label'), user.username),
                    const Divider(),
                    _infoRow(t.get('bio'), user.bio.isEmpty ? t.get('no_bio') : user.bio),
                    const Divider(),
                    _infoRow(t.get('id'), '#${user.id}'),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => setState(() => _editing = true),
                        child: Text(t.get('edit_profile')),
                      ),
                    ),
                  ] else ...[
                    Text(t.get('username_label'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(hintText: '@username'),
                    ),
                    const SizedBox(height: 16),
                    Text(t.get('bio'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _bioController,
                      decoration: InputDecoration(hintText: t.get('bio_hint')),
                      maxLines: 3,
                      maxLength: 150,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _editing = false;
                                _usernameController.text = user.username;
                                _bioController.text = user.bio;
                              });
                            },
                            child: Text(t.get('cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saving ? null : _saveProfile,
                            child: _saving
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(t.get('save')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: SwitchListTile(
              title: Text(t.get('dark_theme')),
              subtitle: Text(themeProv.isDark ? t.get('dark_enabled') : t.get('dark_disabled')),
              value: themeProv.isDark,
              onChanged: (_) => themeProv.toggleTheme(),
              secondary: Icon(themeProv.isDark ? Icons.dark_mode : Icons.light_mode),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.language, color: Colors.grey[600]),
                  const SizedBox(width: 12),
                  Text(t.get('language'), style: const TextStyle(fontSize: 16)),
                  const Spacer(),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: langProv.locale,
                      dropdownColor: theme.cardColor,
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'ru', child: Text('Русский')),
                        DropdownMenuItem(value: 'uk', child: Text('Українська')),
                      ],
                      onChanged: (v) {
                        if (v != null) langProv.setLocale(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _deleteAccount,
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: Text(t.get('delete_account'), style: const TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
