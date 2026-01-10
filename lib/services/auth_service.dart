// lib/services/auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _supa = Supabase.instance.client;

class AuthFailure implements Exception {
  final String code;
  final String? message;
  AuthFailure(this.code, {this.message});
  @override
  String toString() => message == null ? code : '$code: $message';
}

class UsernameTakenFailure extends AuthFailure {
  UsernameTakenFailure() : super('USERNAME_TAKEN');
}

class EmailTakenFailure extends AuthFailure {
  EmailTakenFailure() : super('EMAIL_TAKEN');
}

class AuthService {
  // ---------------------------------------------------------------------------
  // GİRİŞ: local_login RPC (yalnızca username + bcrypt doğrulama)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> signIn({
    required String identity, // username bekliyoruz
    required String password,
  }) async {
    final res = await _supa.rpc('local_login', params: {
      'p_identity': identity,
      'p_password': password,
    });

    if (res == null || (res is List && res.isEmpty)) {
      throw AuthFailure('BAD_CREDENTIALS');
    }

    final row = (res is List ? res.first : res) as Map<String, dynamic>;
    await _cacheFromRow(row);
    return row;
  }

  // ---------------------------------------------------------------------------
  // KAYIT: local_register (void) -> sonra users'tan username ile çek
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> signUp({
    required String name,
    required String email,
    required String username,
    required String password,
    required String role,
    required String klass,
    required String gender,
  }) async {
    try {
      await _supa.rpc('local_register', params: {
        'p_name': name,
        'p_email': email,
        'p_username': username,
        'p_password': password, // backend bcrypt'ler
        'p_role': role,
        'p_class': klass,
        'p_gender': gender,
      });

      final row = await _supa
          .from('users')
          .select('id, username, role, class, name, email, gender')
          .eq('username', username)
          .maybeSingle();

      final data = row ??
          <String, dynamic>{
            'id': null,
            'username': username,
            'role': role,
            'class': klass,
            'name': name,
            'email': email,
            'gender': gender,
          };

      await _cacheFromRow(data);
      return data;
    } on PostgrestException catch (e) {
      final code = e.code; // 23505 duplicate key
      final msgUp = (e.message ?? '').toUpperCase();
      if (code == '23505' && (msgUp.contains('USERNAME') || msgUp.contains('USERS_USERNAME'))) {
        throw UsernameTakenFailure();
      }
      if (code == '23505' && (msgUp.contains('EMAIL') || msgUp.contains('USERS_EMAIL'))) {
        throw EmailTakenFailure();
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // ŞİFRE DEĞİŞTİR: users tablosundaki hash'i günceller (RPC)
  // p_old_password opsiyonel; gönderirsen backend doğrular.
  // ---------------------------------------------------------------------------
  Future<void> changePassword({
    required int userId,
    required String newPassword,
    String? oldPassword,
  }) async {
    await _supa.rpc('local_change_password', params: {
      'p_user_id': userId,
      'p_new_password': newPassword,
      'p_old_password': oldPassword,
    });
  }

  // ---------------------------------------------------------------------------
  // ÇIKIŞ
  // ---------------------------------------------------------------------------
  Future<void> signOut() async {
    // Başka yerde Auth kullanıldıysa sorun çıkmasın diye best-effort signOut
    try {
      await _supa.auth.signOut();
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    await p.remove('is_logged_in');
    await p.remove('user_id');
    await p.remove('role');
    await p.remove('class');
    await p.remove('username');
    await p.remove('full_name');
    await p.remove('email');
    await p.remove('gender');
  }

  // ---------------------------------------------------------------------------
  // Yardımcılar
  // ---------------------------------------------------------------------------
  Future<void> _cacheFromRow(Map<String, dynamic> row) async {
    final p = await SharedPreferences.getInstance();

    final idRaw = row['id'];
    final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
    if (id != null) await p.setInt('user_id', id);

    final role = (row['role'] as String? ?? 'student').toLowerCase();
    await p.setString('role', role);

    if (row['class'] != null) await p.setString('class', row['class'].toString());
    if (row['username'] != null) await p.setString('username', row['username'].toString());
    if (row['name'] != null) await p.setString('full_name', row['name'].toString());
    if (row['email'] != null) await p.setString('email', row['email'].toString());
    if (row['gender'] != null) await p.setString('gender', row['gender'].toString());

    await p.setBool('is_logged_in', true);
  }

  Future<int?> currentUserId() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('user_id');
  }

  Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('is_logged_in') ?? false;
  }
}
