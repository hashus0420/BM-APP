import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _supa = Supabase.instance.client;

/// Genel auth hatası
class AuthFailure implements Exception {
  final String code;
  final String? message;

  AuthFailure(this.code, {this.message});

  @override
  String toString() => message == null ? code : '$code: $message';
}

/// Kullanıcı adı zaten varsa
class UsernameTakenFailure extends AuthFailure {
  UsernameTakenFailure() : super('USERNAME_TAKEN');
}

/// E-posta zaten varsa
class EmailTakenFailure extends AuthFailure {
  EmailTakenFailure() : super('EMAIL_TAKEN');
}

class AuthService {
  /// Kullanıcı girişi
  /// Supabase üzerindeki local_login RPC fonksiyonu çalışır.
  Future<Map<String, dynamic>> signIn({
    required String identity,
    required String password,
  }) async {
    final cleanIdentity = identity.trim();

    if (cleanIdentity.isEmpty || password.isEmpty) {
      throw AuthFailure('EMPTY_FIELDS');
    }

    try {
      final res = await _supa.rpc(
        'local_login',
        params: {
          'p_identity': cleanIdentity,
          'p_password': password,
        },
      );

      if (res == null || (res is List && res.isEmpty)) {
        throw AuthFailure('BAD_CREDENTIALS');
      }

      final row = (res is List ? res.first : res) as Map<String, dynamic>;

      await _cacheFromRow(row);

      return row;
    } on PostgrestException catch (e) {
      throw AuthFailure(e.code ?? 'POSTGREST_ERROR', message: e.message);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure('NETWORK_OR_UNKNOWN_ERROR', message: e.toString());
    }
  }

  /// Kullanıcı kaydı
  /// Supabase üzerindeki local_register RPC fonksiyonu çalışır.
  Future<Map<String, dynamic>> signUp({
    required String name,
    required String email,
    required String username,
    required String password,
    required String role,
    required String klass,
    required String gender,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanUsername = username.trim().toLowerCase();
    final cleanClass = klass.trim();

    if (cleanName.isEmpty ||
        cleanEmail.isEmpty ||
        cleanUsername.isEmpty ||
        password.isEmpty ||
        cleanClass.isEmpty) {
      throw AuthFailure('EMPTY_FIELDS');
    }

    try {
      await _supa.rpc(
        'local_register',
        params: {
          'p_name': cleanName,
          'p_email': cleanEmail,
          'p_username': cleanUsername,
          'p_password': password,
          'p_role': role,
          'p_class': cleanClass,
          'p_gender': gender,
        },
      );

      final row = await _supa
          .from('users')
          .select('id, username, role, class, name, email, gender')
          .eq('username', cleanUsername)
          .maybeSingle();

      final data = row ??
          <String, dynamic>{
            'id': null,
            'username': cleanUsername,
            'role': role,
            'class': cleanClass,
            'name': cleanName,
            'email': cleanEmail,
            'gender': gender,
          };

      await _cacheFromRow(data);

      return data;
    } on PostgrestException catch (e) {
      final code = e.code;
      final msgUp = e.message.toUpperCase();

      if (code == '23505' &&
          (msgUp.contains('USERNAME') || msgUp.contains('USERS_USERNAME'))) {
        throw UsernameTakenFailure();
      }

      if (code == '23505' &&
          (msgUp.contains('EMAIL') || msgUp.contains('USERS_EMAIL'))) {
        throw EmailTakenFailure();
      }

      throw AuthFailure(code ?? 'POSTGREST_ERROR', message: e.message);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure('NETWORK_OR_UNKNOWN_ERROR', message: e.toString());
    }
  }

  /// Şifre değiştirme
  Future<void> changePassword({
    required int userId,
    required String newPassword,
    String? oldPassword,
  }) async {
    if (newPassword.isEmpty) {
      throw AuthFailure('EMPTY_PASSWORD');
    }

    try {
      await _supa.rpc(
        'local_change_password',
        params: {
          'p_user_id': userId,
          'p_new_password': newPassword,
          'p_old_password': oldPassword,
        },
      );
    } on PostgrestException catch (e) {
      throw AuthFailure(e.code ?? 'POSTGREST_ERROR', message: e.message);
    } catch (e) {
      throw AuthFailure('NETWORK_OR_UNKNOWN_ERROR', message: e.toString());
    }
  }

  /// Çıkış işlemi
  Future<void> signOut() async {
    try {
      await _supa.auth.signOut();
    } catch (_) {
      // Supabase Auth kullanılmıyorsa hata önemsenmez.
    }

    final p = await SharedPreferences.getInstance();

    await p.remove('is_logged_in');
    await p.remove('user_id');
    await p.remove('role');
    await p.remove('class');
    await p.remove('username');
    await p.remove('name');
    await p.remove('full_name');
    await p.remove('email');
    await p.remove('gender');
    await p.remove('identity');
  }

  /// Kullanıcı bilgisini local cache'e kaydeder.
  Future<void> _cacheFromRow(Map<String, dynamic> row) async {
    final p = await SharedPreferences.getInstance();

    final idRaw = row['id'];
    final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');

    if (id != null) {
      await p.setInt('user_id', id);
    }

    await p.setString(
      'role',
      (row['role']?.toString() ?? 'student').toLowerCase(),
    );

    if (row['class'] != null) {
      await p.setString('class', row['class'].toString());
    }

    if (row['username'] != null) {
      await p.setString('username', row['username'].toString());
      await p.setString('identity', row['username'].toString());
    }

    if (row['name'] != null) {
      await p.setString('name', row['name'].toString());
      await p.setString('full_name', row['name'].toString());
    }

    if (row['email'] != null) {
      await p.setString('email', row['email'].toString());
    }

    if (row['gender'] != null) {
      await p.setString('gender', row['gender'].toString());
    }

    await p.setBool('is_logged_in', true);
  }

  /// Mevcut kullanıcı ID
  Future<int?> currentUserId() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('user_id');
  }

  /// Kullanıcı giriş yapmış mı?
  Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('is_logged_in') ?? false;
  }
}