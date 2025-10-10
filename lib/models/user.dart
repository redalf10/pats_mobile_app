enum Role { tower1, tower2, pilot, inspector }

class User {
  final String id;
  final String name;
  final bool isSpeaking;
  final String ipAddress;
  final String? photoUrl;
  final Role role;

  User({
    required this.id,
    required this.name,
    this.isSpeaking = false,
    this.ipAddress = '',
    this.photoUrl,
    this.role = Role.pilot, // Changed default role to pilot
  });

  User copyWith({
    String? id,
    String? name,
    bool? isSpeaking,
    String? ipAddress,
    String? photoUrl,
    Role? role,
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
      'role': role.toString().split('.').last, // Convert role to string format
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      isSpeaking: json['isSpeaking'] as bool? ?? false,
      ipAddress: json['ipAddress'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      role: json['role'] != null
          ? Role.values.firstWhere(
              (e) => e.toString().split('.').last == json['role'],
              orElse: () => Role.pilot,
            )
          : Role.pilot, // Changed default role to pilot
    );
  }
}
