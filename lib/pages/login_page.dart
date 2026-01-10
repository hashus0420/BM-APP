// lib/pages/login_page.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../pages/navigation_page.dart';

/* ---------- PALET ---------- */
const _navy = Color(0xFF113A7D);
const _sky  = Color(0xFF57C3F6);
const _rose = Color(0xFFFF8FA3);
const _radius = 18.0;

LinearGradient get _primaryGrad => const LinearGradient(
  begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_navy, _sky],
);
LinearGradient get _accentGrad => const LinearGradient(
  begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [_rose, _sky],
);

final _supa = Supabase.instance.client;
final _auth = AuthService();

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // -------- Login --------
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // -------- Signup (sheet) --------
  final _suNameController = TextEditingController();
  final _suEmailController = TextEditingController();
  final _suUsernameController = TextEditingController();
  final _suPasswordController = TextEditingController();
  final _suPassword2Controller = TextEditingController();
  final _suClassController = TextEditingController();
  String _suRole = 'student';
  String _suGender = 'female'; // 'male' | 'female'

  // Form keys & focus
  final _formKeyLogin = GlobalKey<FormState>();
  final _formKeySignup = GlobalKey<FormState>();
  final _loginUserFocus = FocusNode();
  final _loginPassFocus = FocusNode();
  final _suNameFocus = FocusNode();
  final _suEmailFocus = FocusNode();
  final _suUserFocus = FocusNode();
  final _suPass1Focus = FocusNode();
  final _suPass2Focus = FocusNode();
  final _suClassFocus = FocusNode();

  bool _isLoading = false;
  bool _obscureLogin = true;
  bool _obscureSignup1 = true;
  bool _obscureSignup2 = true;

  @override
  void initState() {
    super.initState();
    _prefillIdentityFromPrefs();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _suNameController.dispose();
    _suEmailController.dispose();
    _suUsernameController.dispose();
    _suPasswordController.dispose();
    _suPassword2Controller.dispose();
    _suClassController.dispose();

    _loginUserFocus.dispose();
    _loginPassFocus.dispose();
    _suNameFocus.dispose();
    _suEmailFocus.dispose();
    _suUserFocus.dispose();
    _suPass1Focus.dispose();
    _suPass2Focus.dispose();
    _suClassFocus.dispose();
    super.dispose();
  }

  String _pretty(Object e) {
    final raw = e.toString().toUpperCase();
    if (raw.contains('BAD_CREDENTIALS') || raw.contains('GEÇERSİZ') || raw.contains('INVALID_LOGIN_CREDENTIALS')) {
      return 'Geçersiz kullanıcı adı veya şifre.';
    }
    if (raw.contains('USER_NOT_FOUND')) return 'Kullanıcı bulunamadı.';
    if (raw.contains('NETWORK') || raw.contains('SOCKET') || raw.contains('TIMEOUT')) {
      return 'Ağ hatası. Bağlantınızı kontrol edin.';
    }
    if (raw.contains('USERNAME') && raw.contains('EXISTS')) {
      return 'Bu kullanıcı adı zaten kullanılıyor.';
    }
    if (raw.contains('EMAIL') && raw.contains('EXISTS')) {
      return 'Bu e-posta zaten kayıtlı.';
    }
    return 'İşlem başarısız. Lütfen tekrar deneyin.';
  }

  bool _looksLikeEmail(String s) => RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s);

  Future<void> _saveEmailToPrefs({String? identity}) async {
    final prefs = await SharedPreferences.getInstance();
    final authEmail = _supa.auth.currentUser?.email;
    if ((authEmail ?? '').isNotEmpty) {
      await prefs.setString('email', authEmail!);
      return;
    }
    if (identity != null && _looksLikeEmail(identity)) {
      await prefs.setString('email', identity);
    }
  }

  Future<void> _prefillIdentityFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final lastEmail = prefs.getString('email') ?? prefs.getString('identity');
    if ((lastEmail ?? '').isNotEmpty && mounted) {
      _usernameController.text = lastEmail!;
    }
  }

  // Güvenlik: parolayı yerelde saklamıyoruz, yalnız kimliği hatırla (prefill için)
  Future<void> _storeLocalLoginIdentity(String identity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('identity', identity);
  }

  /* ---------------- LOGIN ---------------- */
  Future<void> _handleLogin() async {
    if (!_formKeyLogin.currentState!.validate()) return;

    // normalize identity (email/kullanıcı adı)
    final identity = _usernameController.text.trim(); // sadece trim
    final password = _passwordController.text;        // ŞİFRE ASLA TRIMLENMEZ!

    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();

    setState(() => _isLoading = true);
    try {
      await _auth.signIn(identity: identity, password: password);

      try {
        if (_supa.auth.currentSession == null) {
          await _supa.auth.refreshSession();
        }
      } catch (_) {}

      await _storeLocalLoginIdentity(identity);
      await _saveEmailToPrefs(identity: identity);
      await _cacheFromUsersByIdentity(identity);
      await _cacheRoleAfterAuth(identityHint: identity);

      if (!mounted) return;
      await _showOk('🎉 Giriş Başarılı', 'Hoş geldiniz!');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NavigationPage()),
            (_) => false,
      );
    } on PostgrestException catch (e) {
      debugPrint('🧨 PG code=${e.code} msg=${e.message} details=${e.details} hint=${e.hint}');
      _showError('PG ${e.code} • ${e.message ?? 'Unknown'}');
    } on AuthFailure catch (e) {
      _showError(_pretty(e));
    } on TimeoutException {
      _showError('İstek zaman aşımına uğradı.');
    } catch (e, st) {
      debugPrint('🧨 Unknown error: $e\n$st');
      _showError(_pretty(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /* ---------------- SIGNUP ---------------- */
  Future<void> _handleSignup() async {
    if (!_formKeySignup.currentState!.validate()) return;
    if (_suPasswordController.text != _suPassword2Controller.text) {
      _showError('Şifreler eşleşmiyor.'); return;
    }

    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();

    setState(() => _isLoading = true);
    try {
      // normalize email & username
      final emailNorm    = _suEmailController.text.trim().toLowerCase();
      final usernameNorm = _suUsernameController.text.trim().toLowerCase();

      await _auth.signUp(
        name    : _suNameController.text.trim(),
        email   : emailNorm,
        username: usernameNorm,
        password: _suPasswordController.text, // şifre raw
        role    : _suRole,
        klass   : _suClassController.text.trim(),
        gender  : _suGender, // <-- erkek/kadın
      );

      // Yalnız kimliği hatırla (prefill için)
      await _storeLocalLoginIdentity(usernameNorm);

      await _cacheFromUsersByIdentity(usernameNorm);
      await _cacheRoleAfterAuth(identityHint: usernameNorm);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('email', emailNorm);

      if (!mounted) return;
      Navigator.pop(context);
      await _showOk('🎉 Kayıt Başarılı', 'Hesabınız oluşturuldu.');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NavigationPage()),
            (_) => false,
      );
    } on PostgrestException catch (e) {
      debugPrint('🧨 PG code=${e.code} msg=${e.message} details=${e.details} hint=${e.hint}');
      _showError('PG ${e.code} • ${e.message ?? 'Unknown'}');
    } on TimeoutException {
      _showError('İstek zaman aşımına uğradı.');
    } on AuthFailure catch (e) {
      _showError(_pretty(e));
    } catch (e, st) {
      debugPrint('🧨 Unknown error: $e\n$st');
      _showError(_pretty(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 1) LOCAL LOGIN senaryosu için
  Future<void> _cacheFromUsersByIdentity(String identity) async {
    if (identity.isEmpty) return;
    try {
      final row = await _supa
          .from('users')
          .select('id, username, role, class, name, email, gender')
          .or('username.ilike.$identity,email.ilike.$identity') // case-insensitive
          .maybeSingle();

      if (row == null) return;

      final prefs = await SharedPreferences.getInstance();
      if (row['role'] != null) await prefs.setString('role', row['role'].toString().toLowerCase());
      if (row['class'] != null) await prefs.setString('class', row['class'].toString());
      if (row['username'] != null) await prefs.setString('username', row['username'].toString());
      if (row['name'] != null) await prefs.setString('full_name', row['name'].toString());
      if (row['email'] != null) await prefs.setString('email', row['email'].toString());
      if (row['gender'] != null) await prefs.setString('gender', row['gender'].toString());
      final idRaw = row['id'];
      final asInt = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
      if (asInt != null) await prefs.setInt('user_id', asInt);
    } catch (_) {}
  }

  /// 2) AUTH fallback
  Future<void> _cacheRoleAfterAuth({String? identityHint}) async {
    final uid = _supa.auth.currentUser?.id;
    if (uid == null) return;

    Map<String, dynamic>? urow;
    try {
      urow = await _supa
          .from('users')
          .select('id, username, role, class, name, email, auth_id, gender')
          .eq('auth_id', uid)
          .maybeSingle();
    } catch (_) {}

    final emailHint = _supa.auth.currentUser?.email;
    if (urow == null && (emailHint?.isNotEmpty ?? false)) {
      try {
        urow = await _supa
            .from('users')
            .select('id, username, role, class, name, email, auth_id, gender')
            .eq('email', emailHint!)
            .maybeSingle();
      } catch (_) {}
    }

    if (urow == null && (identityHint?.isNotEmpty ?? false)) {
      try {
        urow = await _supa
            .from('users')
            .select('id, username, role, class, name, email, auth_id, gender')
            .or('username.ilike.$identityHint,email.ilike.$identityHint') // case-insensitive
            .maybeSingle();
      } catch (_) {}
    }

    if (urow != null &&
        (urow['auth_id'] == null || (urow['auth_id'] as String?)?.isEmpty == true)) {
      try {
        await _supa.from('users').update({'auth_id': uid}).eq('id', urow['id'] as int);
        urow['auth_id'] = uid;
      } catch (_) {}
    }

    Map<String, dynamic>? prow;
    if (urow == null) {
      try {
        prow = await _supa
            .from('profiles')
            .select('username, role, class, full_name, email')
            .eq('id', uid)
            .maybeSingle();
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    final role = ((urow?['role'] ?? prow?['role']) as String? ?? 'student').toLowerCase();
    await prefs.setString('role', role);

    if (urow?['class'] != null) {
      await prefs.setString('class', urow!['class'].toString());
    } else if (prow?['class'] != null) {
      await prefs.setString('class', prow!['class'].toString());
    }
    if (urow?['username'] != null) {
      await prefs.setString('username', urow!['username'].toString());
    } else if (prow?['username'] != null) {
      await prefs.setString('username', prow!['username'].toString());
    }
    if (urow?['name'] != null) {
      await prefs.setString('full_name', urow!['name'].toString());
    }
    if (urow?['email'] != null) {
      await prefs.setString('email', urow!['email'].toString());
    } else if (prow?['email'] != null) {
      await prefs.setString('email', prow!['email'].toString());
    }
    if (urow?['gender'] != null) {
      await prefs.setString('gender', urow!['gender'].toString());
    }

    final idRaw = urow?['id'];
    if (idRaw != null) {
      final asInt = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
      if (asInt != null) await prefs.setInt('user_id', asInt);
    }
  }

  Future<void> _showOk(String title, String content) {
    return FancyDialog.success(context, title: title, message: content);
  }

  void _showError(String msg) {
    FancyDialog.error(context, title: '❌ İşlem Başarısız', message: msg);
  }

  InputDecoration _dec(BuildContext context, {required String label, IconData? icon, Widget? suffix}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: cs.surface.withValues(alpha: .08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  // ---------- Kayıt Sheet'i ----------
  Future<void> _openSignupSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16, right: 16, top: 8,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Material(
                    color: theme.colorScheme.surface.withValues(alpha: .96),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKeySignup,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                controller: _suNameController,
                                focusNode: _suNameFocus,
                                textInputAction: TextInputAction.next,
                                decoration: _dec(context, label: 'Ad Soyad', icon: Icons.badge),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                                onFieldSubmitted: (_) => _suEmailFocus.requestFocus(),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _suEmailController,
                                focusNode: _suEmailFocus,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                autocorrect: false,
                                enableSuggestions: false,
                                inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                                decoration: _dec(context, label: 'E-posta', icon: Icons.email),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Zorunlu alan';
                                  final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim());
                                  return ok ? null : 'Geçerli bir e-posta girin';
                                },
                                onFieldSubmitted: (_) => _suUserFocus.requestFocus(),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _suUsernameController,
                                focusNode: _suUserFocus,
                                textInputAction: TextInputAction.next,
                                decoration: _dec(context, label: 'Kullanıcı Adı', icon: Icons.person_add),
                                inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                                onFieldSubmitted: (_) => _suPass1Focus.requestFocus(),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _suPasswordController,
                                focusNode: _suPass1Focus,
                                textInputAction: TextInputAction.next,
                                obscureText: _obscureSignup1,
                                autofillHints: const [AutofillHints.newPassword],
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _dec(
                                  context,
                                  label: 'Şifre (min 6)',
                                  icon: Icons.lock,
                                  suffix: IconButton(
                                    tooltip: _obscureSignup1 ? 'Şifreyi göster' : 'Şifreyi gizle',
                                    onPressed: () => setModalState(() => _obscureSignup1 = !_obscureSignup1),
                                    icon: Icon(_obscureSignup1 ? Icons.visibility : Icons.visibility_off),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Zorunlu alan';
                                  if (v.length < 6) return 'En az 6 karakter olmalı';
                                  return null;
                                },
                                onFieldSubmitted: (_) => _suPass2Focus.requestFocus(),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _suPassword2Controller,
                                focusNode: _suPass2Focus,
                                textInputAction: TextInputAction.next,
                                obscureText: _obscureSignup2,
                                autofillHints: const [AutofillHints.newPassword],
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _dec(
                                  context,
                                  label: 'Şifre (Tekrar)',
                                  icon: Icons.lock_outline,
                                  suffix: IconButton(
                                    tooltip: _obscureSignup2 ? 'Şifreyi göster' : 'Şifreyi gizle',
                                    onPressed: () => setModalState(() => _obscureSignup2 = !_obscureSignup2),
                                    icon: Icon(_obscureSignup2 ? Icons.visibility : Icons.visibility_off),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty) ? 'Zorunlu alan' : null,
                                onFieldSubmitted: (_) => _suClassFocus.requestFocus(),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _suRole,
                                decoration: _dec(context, label: 'Rol', icon: Icons.school),
                                items: const [
                                  DropdownMenuItem(value: 'student', child: Text('Öğrenci')),
                                ],
                                onChanged: (v) => setModalState(() => _suRole = v ?? 'student'),
                              ),
                              const SizedBox(height: 12),

                              // --- Cinsiyet (Erkek/Kadın) ---
                              DropdownButtonFormField<String>(
                                initialValue: _suGender, // 'female' varsayılan
                                decoration: _dec(context, label: 'Cinsiyet', icon: Icons.wc),
                                items: const [
                                  DropdownMenuItem(value: 'male',   child: Text('Erkek')),
                                  DropdownMenuItem(value: 'female', child: Text('Kadın')),
                                ],
                                onChanged: (v) => setModalState(() => _suGender = (v ?? 'female')),
                                validator: (v) => (v == null || v.isEmpty) ? 'Zorunlu alan' : null,
                              ),
                              const SizedBox(height: 12),

                              TextFormField(
                                controller: _suClassController,
                                focusNode: _suClassFocus,
                                textInputAction: TextInputAction.done,
                                decoration: _dec(context, label: 'Sınıf (örn: 10/A)', icon: Icons.class_),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                              ),
                              const SizedBox(height: 16),
                              GradientButton(
                                gradient: _accentGrad,
                                onPressed: _isLoading ? null : _handleSignup,
                                child: _isLoading
                                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('Kayıt Ol', style: TextStyle(fontSize: 16)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themed = Theme.of(context).copyWith(
      scaffoldBackgroundColor: Colors.white,
      cardTheme: Theme.of(context).cardTheme.copyWith(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
    );

    final progress = _isLoading
        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
        : null;

    return Theme(
      data: themed,
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_radius),
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: .55),
                    border: Border.all(width: 1.2, color: Colors.black.withValues(alpha: .06)),
                  ),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/images/logo.png', height: 300, fit: BoxFit.contain),
                          const SizedBox(height: 20),
                          Text('Hoş Geldiniz',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: _navy, fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Form(
                            key: _formKeyLogin,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            child: Column(
                              children: [
                                // USERNAME / EMAIL
                                TextFormField(
                                  controller: _usernameController,
                                  focusNode: _loginUserFocus,
                                  textInputAction: TextInputAction.next,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                                  ],
                                  decoration: _dec(context, label: 'Kullanıcı Adı / E-posta', icon: Icons.person),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                                  onFieldSubmitted: (_) => _loginPassFocus.requestFocus(),
                                ),
                                const SizedBox(height: 12),
                                // PASSWORD
                                TextFormField(
                                  controller: _passwordController,
                                  focusNode: _loginPassFocus,
                                  textInputAction: TextInputAction.done,
                                  obscureText: _obscureLogin,
                                  autofillHints: const [AutofillHints.password],
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: _dec(
                                    context,
                                    label: 'Şifre',
                                    icon: Icons.lock,
                                    suffix: IconButton(
                                      tooltip: _obscureLogin ? 'Şifreyi göster' : 'Şifreyi gizle',
                                      onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
                                      icon: Icon(_obscureLogin ? Icons.visibility : Icons.visibility_off),
                                    ),
                                  ),
                                  validator: (v) => (v == null || v.isEmpty) ? 'Zorunlu alan' : null,
                                  onFieldSubmitted: (_) {
                                    if (!_isLoading) _handleLogin();
                                  },
                                ),
                                const SizedBox(height: 16),
                                GradientButton(
                                  gradient: _primaryGrad,
                                  onPressed: _isLoading ? null : _handleLogin,
                                  child: progress ?? const Text('Giriş Yap', style: TextStyle(fontSize: 16)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _openSignupSheet,
                            child: const Text('Hesabın yok mu? Kayıt Ol'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* -------- Gradient Button -------- */
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    required this.gradient,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material( // güvenlik için Material
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: enabled
              ? gradient
              : LinearGradient(colors: [
            Theme.of(context).disabledColor.withValues(alpha: .25),
            Theme.of(context).disabledColor.withValues(alpha: .15),
          ]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 50,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------- FancyDialog: cam efektli, animasyonlu pop-up ---------- */
class FancyDialog {
  static Future<void> success(
      BuildContext context, {
        required String title,
        required String message,
        String okText = 'Tamam',
        VoidCallback? onOk,
      }) {
    return _show(
      context,
      title: title,
      message: message,
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF1DB954), // yeşil
      okText: okText,
      onOk: onOk,
    );
  }

  static Future<void> error(
      BuildContext context, {
        required String title,
        required String message,
        String okText = 'Kapat',
        VoidCallback? onOk,
      }) {
    return _show(
      context,
      title: title,
      message: message,
      icon: Icons.error_rounded,
      iconColor: const Color(0xFFFF5A7A), // pembe-kırmızı
      okText: okText,
      onOk: onOk,
    );
  }

  static Future<void> warning(
      BuildContext context, {
        required String title,
        required String message,
        String okText = 'Anladım',
        VoidCallback? onOk,
      }) {
    return _show(
      context,
      title: title,
      message: message,
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFF6C945),
      okText: okText,
      onOk: onOk,
    );
  }

  static Future<void> _show(
      BuildContext context, {
        required String title,
        required String message,
        required IconData icon,
        required Color iconColor,
        required String okText,
        VoidCallback? onOk,
      }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dialog',
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return Transform.scale(
          scale: 0.98 + 0.02 * curve.value,
          child: Opacity(
            opacity: anim.value,
            child: Center(
              child: Material( // Ink için Material
                type: MaterialType.transparency,
                child: _GlassCard(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: .15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 40, color: iconColor),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .8),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _DialogButton(
                            text: okText,
                            onPressed: () {
                              Navigator.of(ctx).maybePop();
                              onOk?.call();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: .06), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 24, spreadRadius: 4, offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.text, required this.onPressed});
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [cs.primary, cs.primary.withValues(alpha: .7)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: .2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
