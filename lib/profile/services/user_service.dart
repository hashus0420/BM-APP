// lib/services/user_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants.dart';
import '../models/user_model.dart';

/// Varsayılan şema:
/// profiles: id uuid pk (auth.users.id), email text unique, username text unique,
///           full_name text, role text, class text, updated_at timestamptz
///
/// Not: Admin paneli ile create/update/delete işlemlerinde RLS politikalarını
/// uygun vereceğiz (aşağıda SQL bölümünde).

class UserService {
  final _sb = Supabase.instance.client;

  Map<String, dynamic> _toUserJsonForModel(Map m) {
    // Mevcut UserModel.fromJson hangi alanları bekliyorsa buradan uyarlayabilirsin.
    // Örnek eşleme:
    return {
      'id': m['id'],
      'name': m['full_name'] ?? m['username'],
      'email': m['email'],
      'username': m['username'],
      'role': m['role'],
      'class': m['class'],
      // diğer alanlar...
    };
  }

  /* -------------------- READ -------------------- */

  Future<List<UserModel>> fetchUsers() async {
    final res = await _sb
        .from(kTableProfiles)
        .select('id, email, username, full_name, role, class')
        .order('username');

    if (res is List) {
      return res
          .map((e) => UserModel.fromJson(
        _toUserJsonForModel(Map<String, dynamic>.from(e)),
      ))
          .toList();
    }
    throw Exception('Kullanıcılar alınamadı.');
  }

  Future<UserModel> fetchUser(String id) async {
    final res = await _sb
        .from(kTableProfiles)
        .select('id, email, username, full_name, role, class')
        .eq('id', id)
        .maybeSingle();

    if (res == null) throw Exception('Kullanıcı bulunamadı.');
    return UserModel.fromJson(_toUserJsonForModel(res));
  }

  /* -------------------- CREATE -------------------- */

  /// Admin bir kullanıcı oluştursun: önce auth.signUp, sonra profiles upsert.
  /// Not: Bu işlem için service role gerektirmeden de yapılabilir fakat
  /// RLS politikalarında admin yetkisi verilmiş olmalı (bkz. SQL).
  Future<UserModel> createUser({
    required String email,
    required String password,
    required String username,
    String? fullName,
    String role = 'student',
    String? klass,
  }) async {
    // 1) Auth kayıt
    final sign = await _sb.auth.signUp(email: email, password: password);
    final user = sign.user;
    if (user == null) {
      throw Exception('Auth kaydı tamamlanamadı.');
    }

    // 2) Profil upsert
    final profile = await _sb.from(kTableProfiles).upsert({
      'id': user.id,
      'email': email,
      'username': username,
      'full_name': fullName,
      'role': role,
      'class': klass,
      'updated_at': DateTime.now().toIso8601String(),
    }).select().maybeSingle();

    if (profile == null) {
      throw Exception('Profil oluşturulamadı.');
    }
    return UserModel.fromJson(_toUserJsonForModel(profile));
  }

  /* -------------------- UPDATE -------------------- */

  Future<UserModel> updateUser({
    required String id,
    String? email,
    String? username,
    String? fullName,
    String? role,
    String? klass,
  }) async {
    final payload = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (email != null) payload['email'] = email;
    if (username != null) payload['username'] = username;
    if (fullName != null) payload['full_name'] = fullName;
    if (role != null) payload['role'] = role;
    if (klass != null) payload['class'] = klass;

    final res = await _sb
        .from(kTableProfiles)
        .update(payload)
        .eq('id', id)
        .select()
        .maybeSingle();

    if (res == null) throw Exception('Kullanıcı güncellenemedi.');
    return UserModel.fromJson(_toUserJsonForModel(res));
  }

  /// Parola değiştir (sadece mevcut kullanıcı kendi parolasını değiştirebilir)
  Future<bool> changePassword(String newPassword) async {
    final current = _sb.auth.currentUser;
    if (current == null) throw StateError('Oturum yok.');

    await _sb.auth.updateUser(UserAttributes(password: newPassword));
    return true;
  }

  /* -------------------- DELETE -------------------- */

  /// Kullanıcı silme genellikle service role veya Edge Function ile yapılır.
  /// İstemciden doğrudan silmeyi **önermem**. Yine de RLS ile admin'e izin veriyorsan:
  Future<bool> deleteUser(String id) async {
    // 1) profiles satırını sil
    await _sb.from(kTableProfiles).delete().eq('id', id);

    // 2) auth.users silmek client'tan mümkün değil (güvenlik).
    //    Bunun için Edge Function yazmanı öneririm.
    return true;
  }
}
