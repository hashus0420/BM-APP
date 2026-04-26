import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:msret/features/auth/services/auth_service.dart';
import 'package:msret/navigation/pages/navigation_page.dart';

/* ---------- RENK PALETİ ---------- */

const _iosBg = Color(0xFFF5F6FA);
const _navy = Color(0xFF113A7D);
const _sky = Color(0xFF57C3F6);
const _rose = Color(0xFFFF8FA3);

const _radius = 20.0;

/// Ana giriş butonu gradient'i
const _primaryGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_navy, _sky],
);

/// Kayıt ol butonu gradient'i
const _accentGrad = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [_rose, _sky],
);

/// Supabase client tek sefer global alınır.
final _supa = Supabase.instance.client;

/// AuthService tek sefer oluşturulur.
final _auth = AuthService();

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  /* ---------- CONTROLLER'LAR ---------- */

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  final _suNameController = TextEditingController();
  final _suEmailController = TextEditingController();
  final _suUsernameController = TextEditingController();
  final _suPasswordController = TextEditingController();
  final _suPassword2Controller = TextEditingController();
  final _suClassController = TextEditingController();

  /* ---------- FORM KEY'LER ---------- */

  final _formKeyLogin = GlobalKey<FormState>();
  final _formKeySignup = GlobalKey<FormState>();

  /* ---------- FOCUS NODE'LAR ---------- */

  final _loginUserFocus = FocusNode();
  final _loginPassFocus = FocusNode();

  final _suNameFocus = FocusNode();
  final _suEmailFocus = FocusNode();
  final _suUserFocus = FocusNode();
  final _suPass1Focus = FocusNode();
  final _suPass2Focus = FocusNode();
  final _suClassFocus = FocusNode();

  /* ---------- STATE DEĞİŞKENLERİ ---------- */

  String _suRole = 'student';
  String _suGender = 'female';

  bool _isLoading = false;
  bool _obscureLogin = true;
  bool _obscureSignup1 = true;
  bool _obscureSignup2 = true;

  /// UI hazır olana kadar skeleton gösterilir.
  bool _uiReady = false;

  @override
  void initState() {
    super.initState();

    /// İlk frame çizildikten sonra hafif async işlemler yapılır.
    /// Bu sayede uygulama açılışındaki frame drop azalır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareInitialUi();
    });
  }

  /// Login ekranı için ilk hazırlık işlemleri.
  Future<void> _prepareInitialUi() async {
    try {
      await _prefillIdentityFromPrefs();

      if (!mounted) return;

      /// Logo ön belleğe alınır.
      /// cacheHeight çok yüksek tutulursa RAM ve decode maliyeti artar.
      await precacheImage(
        const AssetImage('assets/images/logo.png'),
        context,
      );
    } catch (_) {
      // Açılışta hata olsa bile ekran çalışmaya devam etsin.
    } finally {
      if (mounted) {
        setState(() => _uiReady = true);
      }
    }
  }

  @override
  void dispose() {
    /// Memory leak olmaması için tüm controller'lar temizlenir.
    _usernameController.dispose();
    _passwordController.dispose();

    _suNameController.dispose();
    _suEmailController.dispose();
    _suUsernameController.dispose();
    _suPasswordController.dispose();
    _suPassword2Controller.dispose();
    _suClassController.dispose();

    /// Focus node'lar temizlenir.
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

  /* ---------- YARDIMCI FONKSİYONLAR ---------- */

  /// Hataları kullanıcı dostu mesaja çevirir.
  String _pretty(Object e) {
    final raw = e.toString().toUpperCase();

    if (raw.contains('BAD_CREDENTIALS') ||
        raw.contains('GEÇERSİZ') ||
        raw.contains('INVALID_LOGIN_CREDENTIALS')) {
      return 'Geçersiz kullanıcı adı veya şifre.';
    }

    if (raw.contains('USER_NOT_FOUND')) {
      return 'Kullanıcı bulunamadı.';
    }

    if (raw.contains('NETWORK') ||
        raw.contains('SOCKET') ||
        raw.contains('TIMEOUT')) {
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

  /// Basit e-posta format kontrolü.
  bool _looksLikeEmail(String s) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }

  /// Daha önce girilen kullanıcı adı/e-posta input'a otomatik yazılır.
  Future<void> _prefillIdentityFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString('email') ?? prefs.getString('identity');

    if ((last ?? '').isNotEmpty && mounted) {
      _usernameController.text = last!;
    }
  }

  /// Kullanıcının son kullandığı identity bilgisi localde tutulur.
  Future<void> _storeLocalLoginIdentity(String identity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('identity', identity);
  }

  /// Supabase Auth içindeki e-posta veya girilen identity localde tutulur.
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

  /// Kullanıcıyı users tablosundan tek sorgu ile çeker.
  /// Önceki kodda birden fazla Supabase sorgusu vardı.
  /// Bu yapı performans açısından daha temizdir.
  Future<Map<String, dynamic>?> _getUserByIdentity(String identity) async {
    if (identity.trim().isEmpty) return null;

    final normalized = identity.trim();

    return await _supa
        .from('users')
        .select('id, name, username, email, role, class, gender, auth_id')
        .or('username.eq.$normalized,email.eq.$normalized')
        .maybeSingle();
  }

  /// Kullanıcı bilgilerini SharedPreferences içine tek noktadan kaydeder.
  Future<void> _cacheUserToPrefs(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();

    final idRaw = user['id'];
    final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');

    if (id != null) {
      await prefs.setInt('user_id', id);
    }

    await prefs.setString('name', user['name']?.toString() ?? '');
    await prefs.setString('full_name', user['name']?.toString() ?? '');
    await prefs.setString('username', user['username']?.toString() ?? '');
    await prefs.setString('email', user['email']?.toString() ?? '');
    await prefs.setString(
      'role',
      (user['role']?.toString() ?? 'student').toLowerCase(),
    );
    await prefs.setString('class', user['class']?.toString() ?? '');
    await prefs.setString('gender', user['gender']?.toString() ?? '');

    /// AuthGate içinde kontrol edilen değer.
    await prefs.setBool('is_logged_in', true);
  }

  /// Kullanıcının auth_id alanı boşsa Supabase Auth ID ile güncellenir.
  Future<void> _syncAuthIdIfNeeded(Map<String, dynamic> user) async {
    final uid = _supa.auth.currentUser?.id;

    if (uid == null) return;

    final authId = user['auth_id']?.toString();
    final idRaw = user['id'];
    final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');

    if (id == null) return;

    if (authId == null || authId.isEmpty) {
      try {
        await _supa.from('users').update({'auth_id': uid}).eq('id', id);
      } catch (_) {
        /// Bu kritik değil; giriş başarılı çalışmaya devam edebilir.
      }
    }
  }

  /* ---------- LOGIN ---------- */

  Future<void> _handleLogin() async {
    if (!_formKeyLogin.currentState!.validate()) return;

    final identity = _usernameController.text.trim();
    final password = _passwordController.text;

    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();

    setState(() => _isLoading = true);

    try {
      /// 1. AuthService üzerinden giriş yapılır.
      await _auth.signIn(identity: identity, password: password);

      /// 2. Session yoksa yenileme denenir.
      try {
        if (_supa.auth.currentSession == null) {
          await _supa.auth.refreshSession();
        }
      } catch (_) {}

      /// 3. Kullanıcı bilgileri tek sorgu ile çekilir.
      final user = await _getUserByIdentity(identity);

      /// 4. Local identity/email kaydı yapılır.
      await _storeLocalLoginIdentity(identity);
      await _saveEmailToPrefs(identity: identity);

      /// 5. User bulunduysa local cache'e yazılır.
      if (user != null) {
        await _cacheUserToPrefs(user);
        await _syncAuthIdIfNeeded(user);
      }

      if (!mounted) return;

      await _showOk('🎉 Giriş Başarılı', 'Hoş geldiniz!');

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        _cupertinoRoute(const NavigationPage()),
            (_) => false,
      );
    } on PostgrestException catch (e) {
      debugPrint(
        'PG code=${e.code} msg=${e.message} details=${e.details} hint=${e.hint}',
      );
      _showError('PG ${e.code} • ${e.message}');
    } on AuthFailure catch (e) {
      _showError(_pretty(e));
    } on TimeoutException {
      _showError('İstek zaman aşımına uğradı.');
    } catch (e, st) {
      debugPrint('Unknown login error: $e\n$st');
      _showError(_pretty(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /* ---------- SIGNUP ---------- */

  Future<void> _handleSignup() async {
    if (!_formKeySignup.currentState!.validate()) return;

    if (_suPasswordController.text != _suPassword2Controller.text) {
      _showError('Şifreler eşleşmiyor.');
      return;
    }

    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();

    setState(() => _isLoading = true);

    try {
      final emailNorm = _suEmailController.text.trim().toLowerCase();
      final usernameNorm = _suUsernameController.text.trim().toLowerCase();

      /// Kullanıcı AuthService üzerinden oluşturulur.
      await _auth.signUp(
        name: _suNameController.text.trim(),
        email: emailNorm,
        username: usernameNorm,
        password: _suPasswordController.text,
        role: _suRole,
        klass: _suClassController.text.trim(),
        gender: _suGender,
      );

      /// Kayıt sonrası kullanıcı bilgileri tek sorgu ile çekilir.
      final user = await _getUserByIdentity(usernameNorm);

      await _storeLocalLoginIdentity(usernameNorm);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('email', emailNorm);
      await prefs.setBool('is_logged_in', true);

      if (user != null) {
        await _cacheUserToPrefs(user);
        await _syncAuthIdIfNeeded(user);
      }

      if (!mounted) return;

      Navigator.pop(context);

      await _showOk('🎉 Kayıt Başarılı', 'Hesabınız oluşturuldu.');

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        _cupertinoRoute(const NavigationPage()),
            (_) => false,
      );
    } on PostgrestException catch (e) {
      debugPrint(
        'PG code=${e.code} msg=${e.message} details=${e.details} hint=${e.hint}',
      );
      _showError('PG ${e.code} • ${e.message}');
    } on TimeoutException {
      _showError('İstek zaman aşımına uğradı.');
    } on AuthFailure catch (e) {
      _showError(_pretty(e));
    } catch (e, st) {
      debugPrint('Unknown signup error: $e\n$st');
      _showError(_pretty(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /* ---------- DIALOG ---------- */

  Future<void> _showOk(String title, String content) {
    return FancyDialog.success(context, title: title, message: content);
  }

  void _showError(String msg) {
    FancyDialog.error(context, title: '❌ İşlem Başarısız', message: msg);
  }

  /* ---------- INPUT DECORATION ---------- */

  InputDecoration _dec(
      BuildContext context, {
        required String label,
        IconData? icon,
        Widget? suffix,
      }) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF6F7FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Colors.black.withOpacity(0.06),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: cs.primary.withOpacity(0.45),
          width: 1.2,
        ),
      ),
    );
  }

  /* ---------- SAYFA GEÇİŞİ ---------- */

  PageRoute _cupertinoRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /* ---------- KAYIT BOTTOM SHEET ---------- */

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
            final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

            /// Blur azaltıldı.
            /// Keyboard açıkken blur kapalı.
            final sigma = keyboardOpen ? 0.0 : 5.0;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 8,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: Material(
                    color: theme.colorScheme.surface.withOpacity(0.97),
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
                                decoration: _dec(
                                  context,
                                  label: 'Ad Soyad',
                                  icon: Icons.badge,
                                ),
                                validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Zorunlu alan'
                                    : null,
                                onFieldSubmitted: (_) {
                                  _suEmailFocus.requestFocus();
                                },
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
                                inputFormatters: [
                                  FilteringTextInputFormatter.deny(
                                    RegExp(r'\s'),
                                  ),
                                ],
                                decoration: _dec(
                                  context,
                                  label: 'E-posta',
                                  icon: Icons.email,
                                ),
                                validator: (v) {
                                  final s = (v ?? '').trim();

                                  if (s.isEmpty) return 'Zorunlu alan';

                                  final ok = RegExp(
                                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                  ).hasMatch(s);

                                  return ok ? null : 'Geçerli bir e-posta girin';
                                },
                                onFieldSubmitted: (_) {
                                  _suUserFocus.requestFocus();
                                },
                              ),
                              const SizedBox(height: 12),

                              TextFormField(
                                controller: _suUsernameController,
                                focusNode: _suUserFocus,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _dec(
                                  context,
                                  label: 'Kullanıcı Adı',
                                  icon: Icons.person_add,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.deny(
                                    RegExp(r'\s'),
                                  ),
                                ],
                                validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Zorunlu alan'
                                    : null,
                                onFieldSubmitted: (_) {
                                  _suPass1Focus.requestFocus();
                                },
                              ),
                              const SizedBox(height: 12),

                              TextFormField(
                                controller: _suPasswordController,
                                focusNode: _suPass1Focus,
                                textInputAction: TextInputAction.next,
                                obscureText: _obscureSignup1,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _dec(
                                  context,
                                  label: 'Şifre (min 6)',
                                  icon: Icons.lock,
                                  suffix: IconButton(
                                    tooltip: _obscureSignup1
                                        ? 'Şifreyi göster'
                                        : 'Şifreyi gizle',
                                    onPressed: () {
                                      setModalState(() {
                                        _obscureSignup1 = !_obscureSignup1;
                                      });
                                    },
                                    icon: Icon(
                                      _obscureSignup1
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Zorunlu alan';
                                  }

                                  if (v.length < 6) {
                                    return 'En az 6 karakter olmalı';
                                  }

                                  return null;
                                },
                                onFieldSubmitted: (_) {
                                  _suPass2Focus.requestFocus();
                                },
                              ),
                              const SizedBox(height: 12),

                              TextFormField(
                                controller: _suPassword2Controller,
                                focusNode: _suPass2Focus,
                                textInputAction: TextInputAction.next,
                                obscureText: _obscureSignup2,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _dec(
                                  context,
                                  label: 'Şifre (Tekrar)',
                                  icon: Icons.lock_outline,
                                  suffix: IconButton(
                                    tooltip: _obscureSignup2
                                        ? 'Şifreyi göster'
                                        : 'Şifreyi gizle',
                                    onPressed: () {
                                      setModalState(() {
                                        _obscureSignup2 = !_obscureSignup2;
                                      });
                                    },
                                    icon: Icon(
                                      _obscureSignup2
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                  ),
                                ),
                                validator: (v) =>
                                (v == null || v.isEmpty)
                                    ? 'Zorunlu alan'
                                    : null,
                                onFieldSubmitted: (_) {
                                  _suClassFocus.requestFocus();
                                },
                              ),
                              const SizedBox(height: 12),

                              DropdownButtonFormField<String>(
                                value: _suRole,
                                decoration: _dec(
                                  context,
                                  label: 'Rol',
                                  icon: Icons.school,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'student',
                                    child: Text('Öğrenci'),
                                  ),
                                ],
                                onChanged: (v) {
                                  setModalState(() {
                                    _suRole = v ?? 'student';
                                  });
                                },
                              ),
                              const SizedBox(height: 12),

                              DropdownButtonFormField<String>(
                                value: _suGender,
                                decoration: _dec(
                                  context,
                                  label: 'Cinsiyet',
                                  icon: Icons.wc,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'male',
                                    child: Text('Erkek'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'female',
                                    child: Text('Kadın'),
                                  ),
                                ],
                                onChanged: (v) {
                                  setModalState(() {
                                    _suGender = v ?? 'female';
                                  });
                                },
                                validator: (v) =>
                                (v == null || v.isEmpty)
                                    ? 'Zorunlu alan'
                                    : null,
                              ),
                              const SizedBox(height: 12),

                              TextFormField(
                                controller: _suClassController,
                                focusNode: _suClassFocus,
                                textInputAction: TextInputAction.done,
                                decoration: _dec(
                                  context,
                                  label: 'Sınıf (örn: 10/A)',
                                  icon: Icons.class_,
                                ),
                                validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Zorunlu alan'
                                    : null,
                                onFieldSubmitted: (_) {
                                  if (!_isLoading) {
                                    _handleSignup();
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              PressableScale(
                                onTap: _isLoading ? null : _handleSignup,
                                child: GradientButton(
                                  gradient: _accentGrad,
                                  onPressed: _isLoading ? null : _handleSignup,
                                  child: _isLoading
                                      ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : const Text(
                                    'Kayıt Ol',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
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

  /* ---------- SKELETON LOADING ---------- */

  Widget _skeletonCard(BuildContext context) {
    Widget bar({double h = 14, double w = double.infinity}) {
      return Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.06),
          borderRadius: BorderRadius.circular(10),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 190,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.05),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 20),
          bar(h: 22, w: 220),
          const SizedBox(height: 16),
          bar(h: 52),
          const SizedBox(height: 12),
          bar(h: 52),
          const SizedBox(height: 16),
          bar(h: 50),
          const SizedBox(height: 12),
          bar(h: 18, w: 180),
        ],
      ),
    );
  }

  /* ---------- BUILD ---------- */

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    /// Blur değeri 14'ten 6'ya düşürüldü.
    /// Bu frame drop'u azaltır.
    final cardBlur = keyboardOpen ? 0.0 : 6.0;

    final themed = Theme.of(context).copyWith(
      scaffoldBackgroundColor: _iosBg,
      cardTheme: Theme.of(context).cardTheme.copyWith(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
    );

    return Theme(
      data: themed,
      child: Scaffold(
        body: PremiumBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),

                  /// Login kartı ayrı repaint edilir.
                  /// Arka plan animasyonu kartı sürekli yeniden çizmesin diye kullanılır.
                  child: RepaintBoundary(
                    child: _uiReady
                        ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PremiumEntrance(
                          child: Column(
                            children: [
                              Hero(
                                tag: 'app_logo',
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  height: 112,
                                  fit: BoxFit.contain,

                                  /// Daha düşük cacheHeight daha az decode maliyeti demektir.
                                  cacheHeight: 256,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Hoş Geldiniz',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Devam etmek için giriş yapın',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),

                        PremiumEntrance(
                          delay: const Duration(milliseconds: 100),
                          child: PremiumGlassCard(
                            blurSigma: cardBlur,
                            child: Form(
                              key: _formKeyLogin,
                              autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _usernameController,
                                    focusNode: _loginUserFocus,
                                    textInputAction:
                                    TextInputAction.next,
                                    keyboardType:
                                    TextInputType.emailAddress,
                                    autofillHints: const [
                                      AutofillHints.username,
                                      AutofillHints.email,
                                    ],
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.deny(
                                        RegExp(r'\s'),
                                      ),
                                    ],
                                    decoration: _dec(
                                      context,
                                      label: 'Kullanıcı Adı / E-posta',
                                      icon: Icons.person,
                                    ),
                                    validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Zorunlu alan'
                                        : null,
                                    onFieldSubmitted: (_) {
                                      _loginPassFocus.requestFocus();
                                    },
                                  ),
                                  const SizedBox(height: 14),

                                  TextFormField(
                                    controller: _passwordController,
                                    focusNode: _loginPassFocus,
                                    textInputAction:
                                    TextInputAction.done,
                                    obscureText: _obscureLogin,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: _dec(
                                      context,
                                      label: 'Şifre',
                                      icon: Icons.lock,
                                      suffix: IconButton(
                                        tooltip: _obscureLogin
                                            ? 'Şifreyi göster'
                                            : 'Şifreyi gizle',
                                        onPressed: () {
                                          setState(() {
                                            _obscureLogin =
                                            !_obscureLogin;
                                          });
                                        },
                                        icon: Icon(
                                          _obscureLogin
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                      ),
                                    ),
                                    validator: (v) =>
                                    (v == null || v.isEmpty)
                                        ? 'Zorunlu alan'
                                        : null,
                                    onFieldSubmitted: (_) {
                                      if (!_isLoading) {
                                        _handleLogin();
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 18),

                                  PressableScale(
                                    onTap:
                                    _isLoading ? null : _handleLogin,
                                    child: GradientButton(
                                      gradient: _primaryGrad,
                                      onPressed: _isLoading
                                          ? null
                                          : _handleLogin,
                                      child: _isLoading
                                          ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child:
                                        CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                          : const Text(
                                        'Giriş Yap',
                                        style:
                                        TextStyle(fontSize: 16),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _openSignupSheet,
                                    child: const Text(
                                      'Hesabın yok mu? Kayıt Ol',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                        : _skeletonCard(context),
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

/* -------------------------------------------------------------------------- */
/*                                  WIDGETLAR                                 */
/* -------------------------------------------------------------------------- */

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

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: enabled
              ? gradient
              : LinearGradient(
            colors: [
              Theme.of(context).disabledColor.withOpacity(.25),
              Theme.of(context).disabledColor.withOpacity(.15),
            ],
          ),
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

/* ---------- DIALOG ---------- */

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
      iconColor: const Color(0xFF1DB954),
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
      iconColor: const Color(0xFFFF5A7A),
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

      /// Dialog geçiş süresi kısaltıldı.
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);

        return Transform.scale(
          scale: 0.98 + 0.02 * curve.value,
          child: Opacity(
            opacity: anim.value,
            child: Center(
              child: Material(
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
                              color: iconColor.withOpacity(.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 40, color: iconColor),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(.8),
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
        /// Dialog blur değeri 10'dan 5'e düşürüldü.
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.black.withOpacity(.06),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.08),
                blurRadius: 24,
                spreadRadius: 4,
                offset: const Offset(0, 10),
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
  const _DialogButton({
    required this.text,
    required this.onPressed,
  });

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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, cs.primary.withOpacity(.7)],
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
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------- BACKGROUND ---------- */

class PremiumBackground extends StatelessWidget {
  const PremiumBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final routeActive = ModalRoute.of(context)?.isCurrent ?? true;

    return Stack(
      children: [
        /// Sayfa aktif değilken arka plan animasyonu çalışmaz.
        TickerMode(
          enabled: routeActive,
          child: const Positioned.fill(child: _MeshGlow()),
        ),

        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 1.2,
                  colors: [
                    Colors.black.withOpacity(0.00),
                    Colors.black.withOpacity(0.05),
                  ],
                ),
              ),
            ),
          ),
        ),

        child,
      ],
    );
  }
}

class _MeshGlow extends StatefulWidget {
  const _MeshGlow();

  @override
  State<_MeshGlow> createState() => _MeshGlowState();
}

class _MeshGlowState extends State<_MeshGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();

    /// Sürekli animasyon var ama düşük maliyetli tutuldu.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);

        return DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            gradient: RadialGradient(
              center: Alignment(-0.7 + 0.3 * t, -0.8 + 0.2 * t),
              radius: 1.25,
              colors: [
                _sky.withOpacity(0.16),
                _navy.withOpacity(0.08),
                bg,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment(0.85 - 0.25 * t, 0.65 - 0.15 * t),
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _rose.withOpacity(0.14),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/* ---------- GLASS CARD ---------- */

class PremiumGlassCard extends StatelessWidget {
  const PremiumGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.blurSigma = 6,
  });

  final Widget child;
  final EdgeInsets padding;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: BackdropFilter(
        /// Blur düşük tutuldu.
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(0.82),
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(
              color: Colors.white.withOpacity(0.32),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 8,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/* ---------- ENTRANCE ANIMATION ---------- */

class PremiumEntrance extends StatefulWidget {
  const PremiumEntrance({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 0),
  });

  final Widget child;
  final Duration delay;

  @override
  State<PremiumEntrance> createState() => _PremiumEntranceState();
}

class _PremiumEntranceState extends State<PremiumEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,

      /// Süre biraz kısaltıldı.
      duration: const Duration(milliseconds: 480),
    );

    Future.delayed(widget.delay, () {
      if (mounted) {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/* ---------- PRESS ANIMATION ---------- */

class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,

      /// Buton pasifse animasyon çalışmasın.
      onTapDown: widget.onTap == null
          ? null
          : (_) {
        setState(() => _down = true);
      },
      onTapCancel: widget.onTap == null
          ? null
          : () {
        setState(() => _down = false);
      },
      onTapUp: widget.onTap == null
          ? null
          : (_) {
        setState(() => _down = false);
      },
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        scale: _down ? 0.985 : 1.0,
        child: widget.child,
      ),
    );
  }
}