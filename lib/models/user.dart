enum UserRole {
  pilot1,
  pilot2,
  tower,
  inspector,
}

class User {
  final String id;
  final String name;
  final bool isSpeaking;
  final String ipAddress;
  final String? photoUrl;
  final UserRole role;

  User({
    required this.id,
    required this.name,
    this.isSpeaking = false,
    this.ipAddress = '',
    this.photoUrl,
    this.role = UserRole.inspector,
  });

  User copyWith({
    String? id,
    String? name,
    bool? isSpeaking,
    String? ipAddress,
    String? photoUrl,
    UserRole? role,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      ipAddress: ipAddress ?? this.ipAddress,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isSpeaking': isSpeaking,
      'ipAddress': ipAddress,
      'photoUrl': photoUrl,
      'role': role.name,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unknown User',
      isSpeaking: json['isSpeaking'] as bool? ?? false,
      ipAddress: json['ipAddress'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      role: UserRole.values.firstWhere(
        (role) => role.name == json['role'],
        orElse: () => UserRole.inspector,
      ),
    );
  }
}
