class User {
  final String id;
  final String name;
  final bool isSpeaking;
  final String ipAddress;
  final String? photoUrl;

  User({
    required this.id,
    required this.name,
    this.isSpeaking = false,
    this.ipAddress = '',
    this.photoUrl,
  });

  User copyWith({
    String? id,
    String? name,
    bool? isSpeaking,
    String? ipAddress,
    String? photoUrl,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      ipAddress: ipAddress ?? this.ipAddress,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isSpeaking': isSpeaking,
      'ipAddress': ipAddress,
      'photoUrl': photoUrl,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unknown User',
      isSpeaking: json['isSpeaking'] as bool? ?? false,
      ipAddress: json['ipAddress'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
    );
  }
}
