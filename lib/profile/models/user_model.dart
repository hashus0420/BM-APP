class UserModel {
  final int id;
  final String name;
  final String role;          // student | teacher | admin
  final String? email;
  final String? username;
  final String? klass;        // DB'deki "class" kolonunu temsil eder
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.username,
    this.klass,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      name: (json['name'] ?? '') as String,
      role: (json['role'] ?? 'student') as String,
      email: json['email'] as String?,
      username: json['username'] as String?,
      klass: json['class'] as String?, // <- "class" JSON anahtarını al
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  /// Listelerde/tabloda geri göndermen gerekirse (parola içermez)
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    if (email != null) 'email': email,
    if (username != null) 'username': username,
    if (klass != null) 'class': klass,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

/// Kayıt / oluşturma için ayrı request modeli (parola burada)
class UserCreateRequest {
  final String name;
  final String password;
  final String role;            // student | teacher | admin
  final String? email;
  final String? username;
  final String? klass;          // "class" kolonu

  UserCreateRequest({
    required this.name,
    required this.password,
    required this.role,
    this.email,
    this.username,
    this.klass,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'password': password,
    'role': role,
    if (email != null && email!.isNotEmpty) 'email': email,
    if (username != null && username!.isNotEmpty) 'username': username,
    if (klass != null && klass!.isNotEmpty) 'class': klass,
  };
}

/// Güncelleme için (parolasız patch)
class UserUpdateRequest {
  final String? name;
  final String? role;
  final String? email;
  final String? username;
  final String? klass;

  UserUpdateRequest({
    this.name,
    this.role,
    this.email,
    this.username,
    this.klass,
  });

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (role != null) 'role': role,
    if (email != null) 'email': email,
    if (username != null) 'username': username,
    if (klass != null) 'class': klass,
  };
}
