class User {
  final int id;
  final String username;
  final String bio;
  final String? avatarPath;

  User({
    required this.id,
    required this.username,
    this.bio = '',
    this.avatarPath,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      bio: (json['bio'] as String?) ?? '',
      avatarPath: json['avatar_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'bio': bio,
      'avatar_path': avatarPath,
    };
  }

  String get displayName => username.startsWith('@') ? username : '@$username';
}
