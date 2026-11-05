class AuthUser {
  final String id;
  final String email;
  final String name;
  final bool isActive;

  const AuthUser({
    required this.id,
    required this.email,
    this.name = '',
    this.isActive = true,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'is_active': isActive,
    };
  }

  AuthUser copyWith({
    String? id,
    String? email,
    String? name,
    bool? isActive,
  }) {
    return AuthUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }
}
