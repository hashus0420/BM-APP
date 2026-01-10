// lib/pages/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';

/// ----- Tema -----
const _kPrimary     = Color(0xFF123A8A);
const _kPrimaryDark = Color(0xFF0A2C6A);
const _kPrimaryTint = Color(0xFFE6F3FF);
const _kSurface     = Colors.white;

/// Görünür sürüm (sabit)
const _kAppVersionDisplay = 'v2.1.0';

/// Sosyal medya linkleri
final Uri _instagramUri = Uri.parse('https://www.instagram.com/hashus0420/');
final Uri _linkedinUri  = Uri.parse('https://www.linkedin.com/in/hasanhüseyingenç');

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Çıkışta temizlenecek anahtarlar
  static const _userKeys = <String>[
    'auth_token',
    'user_id',
    'name',
    'role',
    'studentClass',
    'profileImagePath',
    'email',
    'username',
    'class',
    'full_name',
    'is_logged_in',
  ];

  late final Future<({String version, String appName})> _metaFut = _loadMeta();
  late final Future<({String? name, String? email})> _profFut = _loadProfile();

  // ===== Bildirim tercihleri state =====
  static const _kPrefNotifEnabled = 'notif_enabled';
  static const _kPrefQuietEnabled = 'quiet_enabled';
  static const _kPrefQuietFrom    = 'quiet_from';
  static const _kPrefQuietTo      = 'quiet_to';
  static const _kPrefDailySummary = 'daily_summary_enabled';
  static const _kPrefDailyTime    = 'daily_summary_time';

  bool _notifEnabled = true;
  bool _quietEnabled = false;
  TimeOfDay _quietFrom = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietTo   = const TimeOfDay(hour: 7, minute: 0);

  bool _dailySummary = false;
  TimeOfDay _dailyTime = const TimeOfDay(hour: 8, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadNotifPrefs();
  }

  Future<({String version, String appName})> _loadMeta() async {
    final info = await PackageInfo.fromPlatform();
    // final shown = '$_kAppVersionDisplay (${info.version}+${info.buildNumber})';
    return (version: _kAppVersionDisplay, appName: info.appName);
  }

  Future<({String? name, String? email})> _loadProfile() async {
    final p = await SharedPreferences.getInstance();
    return (
    name: p.getString('full_name') ?? p.getString('name'),
    email: p.getString('email') ?? p.getString('username'),
    );
  }

  Future<void> _loadNotifPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _notifEnabled = p.getBool(_kPrefNotifEnabled) ?? true;
      _quietEnabled = p.getBool(_kPrefQuietEnabled) ?? false;
      _dailySummary = p.getBool(_kPrefDailySummary) ?? false;
      _quietFrom = _parseTime(p.getString(_kPrefQuietFrom)) ?? const TimeOfDay(hour: 22, minute: 0);
      _quietTo   = _parseTime(p.getString(_kPrefQuietTo))   ?? const TimeOfDay(hour: 7,  minute: 0);
      _dailyTime = _parseTime(p.getString(_kPrefDailyTime)) ?? const TimeOfDay(hour: 8,  minute: 0);
    });
  }

  TimeOfDay? _parseTime(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmtTime(TimeOfDay t) => t.format(context);

  Future<void> _savePrefs(void Function(SharedPreferences p) write) async {
    final p = await SharedPreferences.getInstance();
    write(p);
  }

  Future<void> _pickQuietRange() async {
    final start = await showTimePicker(context: context, initialTime: _quietFrom);
    if (start == null) return;
    final end = await showTimePicker(context: context, initialTime: _quietTo);
    if (end == null) return;
    setState(() { _quietFrom = start; _quietTo = end; });
    await _savePrefs((p){
      p.setString(_kPrefQuietFrom, '${_quietFrom.hour.toString().padLeft(2,'0')}:${_quietFrom.minute.toString().padLeft(2,'0')}');
      p.setString(_kPrefQuietTo,   '${_quietTo.hour.toString().padLeft(2,'0')}:${_quietTo.minute.toString().padLeft(2,'0')}');
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pickDailyTime() async {
    final t = await showTimePicker(context: context, initialTime: _dailyTime);
    if (t == null) return;
    setState(() => _dailyTime = t);
    await _savePrefs((p){
      p.setString(_kPrefDailyTime, '${_dailyTime.hour.toString().padLeft(2,'0')}:${_dailyTime.minute.toString().padLeft(2,'0')}');
    });
    HapticFeedback.selectionClick();
  }

  // NavigatorState ile çalış: context'i async aralıklardan sonra kullanma
  Future<void> _performLogout(NavigatorState navigator) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    for (final k in _userKeys) {
      await prefs.remove(k);
    }

    HapticFeedback.selectionClick();

    if (!navigator.mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
    );
  }

  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text('Çıkış Yap'),
        content: const Text('Bu hesaptan çıkmak istediğine emin misin?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Çıkış Yap')),
        ],
      ),
    );

    if (ok == true && navigator.mounted) {
      await _performLogout(navigator);
    }
  }

  /// Dış link aç
  Future<void> _openUrl(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı.')));
    }
  }

  /// Geri bildirim – konu dolu, gövde boş
  Future<void> _sendFeedback(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = Uri(
        scheme: 'mailto',
        path: 'hashus0420@gmail.com',
        queryParameters: {'subject': 'Geri Bildirim'},
      );
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('E-posta istemcisi açılamadı.');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Geri bildirim açılamadı: $e')));
    }
  }

  /// PostgREST hatasını okunur hale çevir
  String _prettyPostgrestError(Object error) {
    if (error is PostgrestException) {
      String? s(Object? v) => v?.toString();
      final parts = <String?>[
        s(error.code),
        s(error.message),
        s(error.details),
        s(error.hint)
      ]
          .where((e) => e != null && e!.trim().isNotEmpty)
          .map((e) => e!.trim().toUpperCase())
          .toList();
      final raw = parts.join(' | ');
      if (raw.contains('BAD_CREDENTIALS')) return 'Mevcut şifre yanlış.';
      if (raw.contains('USER_NOT_FOUND'))  return 'Kullanıcı bulunamadı.';
      if (raw.contains('NO_PASSWORD_SET')) return 'Bu kullanıcı için şifre tanımlı değil.';
      if (raw.contains('PASSWORD_CHANGE_FAILED')) return 'Şifre değiştirilemedi.';
      if (raw.contains('PGRST203') || raw.contains('COULD NOT CHOOSE THE BEST CANDIDATE FUNCTION')) {
        return 'Sunucuda aynı isimli birden fazla fonksiyon var.';
      }
      if (raw.contains('PERMISSION') || raw.contains('DENIED') || raw.contains('EXECUTE')) {
        return 'Yetki hatası: EXECUTE izni gerekli.';
      }
      if (raw.contains('INVALID_GRANT')) return 'Oturum geçersiz. Yeniden giriş yapın.';
      if (raw.contains('JWT')) return 'Oturum süresi dolmuş olabilir.';
      return raw.isNotEmpty ? raw : 'İşlem başarısız';
    }
    return error.toString().isNotEmpty ? error.toString() : 'İşlem başarısız';
  }

  /// Kimlik çöz
  Future<String?> _resolveIdentity() async {
    final sb = Supabase.instance.client;
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email');
    if (email != null && email.isNotEmpty) return email;
    final username = prefs.getString('username');
    if (username != null && username.isNotEmpty) return username;
    final authEmail = sb.auth.currentUser?.email;
    if (authEmail != null && authEmail.isNotEmpty) return authEmail;
    return null;
  }

  /// --- POPUP: Şifre Değiştir (RPC ile) ---
  Future<void> _changePasswordSheet(BuildContext context) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final sb = Supabase.instance.client;

    try {
      if (sb.auth.currentSession == null) {
        await sb.auth.refreshSession();
      }
    } catch (_) {}

    final identity = await _resolveIdentity();

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetCtx) {
          bool isLoading = false;
          bool obscure1 = true, obscure2 = true, obscure3 = true;

          String? validateNew(String? v) {
            final val = (v ?? '').trim();
            if (val.isEmpty) return 'Zorunlu';
            if (val.length < 8) return 'En az 8 karakter olmalı';
            final hasLetter = RegExp(r'[A-Za-z]').hasMatch(val);
            final hasDigit  = RegExp(r'\d').hasMatch(val);
            if (!hasLetter || !hasDigit) return 'Harf ve rakam içermeli';
            return null;
          }

          Future<void> submit(StateSetter setState) async {
            if (isLoading) return;

            final sheetNavigator = Navigator.of(sheetCtx);
            final rootMessenger = ScaffoldMessenger.of(context);

            final current = currentCtrl.text.trim();
            final next    = newCtrl.text.trim();
            final confirm = confirmCtrl.text.trim();

            final form = formKey.currentState;
            if (form == null) return;
            if (!form.validate()) return;

            if (identity == null || identity.isEmpty) {
              await showDialog(
                context: sheetCtx,
                builder: (_) => const AlertDialog.adaptive(
                  title: Text('Hata'),
                  content: Text('Kimlik bulunamadı. Lütfen tekrar giriş yapın.'),
                ),
              );
              return;
            }
            if (current == next) {
              await showDialog(
                context: sheetCtx,
                builder: (_) => const AlertDialog.adaptive(
                  title: Text('Hata'),
                  content: Text('Yeni şifre mevcut şifre ile aynı olamaz.'),
                ),
              );
              return;
            }
            if (next != confirm) {
              await showDialog(
                context: sheetCtx,
                builder: (_) => const AlertDialog.adaptive(
                  title: Text('Hata'),
                  content: Text('Şifreler uyuşmuyor.'),
                ),
              );
              return;
            }

            setState(() => isLoading = true);

            try {
              final res = await sb.rpc('local_change_password', params: {
                'p_identity': identity,
                'p_current' : current,
                'p_new'     : next,
              });

              final ok = (res == true) ||
                  (res is Map && (res['local_change_password'] == true));

              if (!ok) {
                throw PostgrestException(
                  message: 'PASSWORD_CHANGE_FAILED',
                  details: 'RPC returned: ${res.toString()}',
                  code: '400',
                  hint: null,
                );
              }

              if (!sheetCtx.mounted) return;
              sheetNavigator.pop();
              HapticFeedback.selectionClick();
              rootMessenger.showSnackBar(
                const SnackBar(content: Text('Şifre başarıyla değiştirildi')),
              );
            } on PostgrestException catch (e) {
              final readable = _prettyPostgrestError(e);
              await showDialog(
                context: sheetCtx,
                builder: (_) => AlertDialog.adaptive(
                  title: const Text('Hata'),
                  content: Text(readable),
                ),
              );
            } catch (e) {
              await showDialog(
                context: sheetCtx,
                builder: (_) => AlertDialog.adaptive(
                  title: const Text('Hata'),
                  content: Text(e.toString()),
                ),
              );
            } finally {
              if (sheetCtx.mounted) {
                setState(() => isLoading = false);
              }
            }
          }

          String strengthLabel(String v) {
            int score = 0;
            if (v.length >= 8) score++;
            if (RegExp(r'[A-Z]').hasMatch(v)) score++;
            if (RegExp(r'[a-z]').hasMatch(v)) score++;
            if (RegExp(r'\d').hasMatch(v)) score++;
            if (RegExp(r'[^\w\s]').hasMatch(v)) score++;
            switch (score) {
              case 0:
              case 1:
                return 'Çok zayıf';
              case 2:
                return 'Zayıf';
              case 3:
                return 'Orta';
              case 4:
                return 'İyi';
              default:
                return 'Güçlü';
            }
          }

          final safeBottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;

          return StatefulBuilder(
            builder: (ctx, setState) {
              final newPwd = newCtrl.text;
              return Padding(
                padding: EdgeInsets.only(bottom: safeBottomInset),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                          decoration: BoxDecoration(
                            color: _kPrimaryTint,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_reset, size: 18, color: _kPrimaryDark),
                              SizedBox(width: 8),
                              Text(
                                'Şifre Değiştir',
                                style: TextStyle(
                                  color: _kPrimaryDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: currentCtrl,
                          decoration: InputDecoration(
                            labelText: 'Mevcut Şifre',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(obscure1 ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => obscure1 = !obscure1),
                            ),
                          ),
                          obscureText: obscure1,
                          validator: (v) => (v == null || v.isEmpty) ? 'Zorunlu' : null,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: newCtrl,
                          decoration: InputDecoration(
                            labelText: 'Yeni Şifre',
                            prefixIcon: const Icon(Icons.lock),
                            helperText: newPwd.isEmpty ? null : 'Güç: ${strengthLabel(newPwd)}',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(obscure2 ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => obscure2 = !obscure2),
                            ),
                          ),
                          obscureText: obscure2,
                          validator: validateNew,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: confirmCtrl,
                          decoration: InputDecoration(
                            labelText: 'Yeni Şifre (Tekrar)',
                            prefixIcon: const Icon(Icons.lock),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(obscure3 ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => obscure3 = !obscure3),
                            ),
                          ),
                          obscureText: obscure3,
                          validator: (v) => (v != newCtrl.text) ? 'Şifreler uyuşmuyor' : null,
                          onFieldSubmitted: (_) => submit(setState),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(sheetCtx).pop(),
                                child: const Text('İptal'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: isLoading ? null : () => submit(setState),
                                child: isLoading
                                    ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                                    : const Text('Kaydet'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      currentCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: FutureBuilder(
          future: Future.wait([_metaFut, _profFut]),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Ayarlar yüklenemedi: ${snap.error}'),
                  ),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final meta = (snap.data![0] as ({String version, String appName}));
            final prof = (snap.data![1] as ({String? name, String? email}));

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 160,
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF102B6B), _kPrimary],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -40,
                            top: -20,
                            child: Opacity(
                              opacity: .14,
                              child: Icon(Icons.settings, size: 180, color: Colors.white),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: Colors.white.withValues(alpha: .2),
                                    child: const Icon(Icons.person, color: Colors.white, size: 28),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prof.name ?? 'Kullanıcı',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (prof.email != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            prof.email!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: Colors.white.withValues(alpha: .9)),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: .18),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.verified, size: 16, color: Colors.white),
                                              const SizedBox(width: 6),
                                              Text(meta.version, style: const TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      children: [
                        // Uygulama
                        _SectionCard(
                          title: 'Uygulama',
                          children: [
                            _SettingTile(icon: Icons.info_outline, title: 'Sürüm', subtitle: meta.version, dense: true),
                            const _SettingTile(icon: Icons.code, title: 'Geliştirici', subtitle: 'Hasan Hüseyin GENÇ', dense: true),
                            _SettingTile(
                              icon: Icons.mail_outline,
                              title: 'Geri Bildirim Gönder',
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () => _sendFeedback(context),
                            ),
                          ],
                        ),

                        // Sosyal Medya
                        _SectionCard(
                          title: 'Sosyal Medya',
                          children: [
                            _SettingTile(
                              icon: Icons.camera_alt_outlined,
                              title: 'Instagram',
                              subtitle: '@hashus0420',
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () => _openUrl(context, _instagramUri),
                            ),
                            _SettingTile(
                              icon: Icons.business_center_outlined,
                              title: 'LinkedIn',
                              subtitle: 'Hasan Hüseyin GENÇ',
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () => _openUrl(context, _linkedinUri),
                            ),
                          ],
                        ),

                        // Bildirimler
                        _SectionCard(
                          title: 'Bildirimler',
                          children: [
                            _SettingTile(
                              icon: Icons.notifications_active_outlined,
                              title: 'Etkinlik Hatırlatmaları',
                              subtitle: _notifEnabled ? 'Açık' : 'Kapalı',
                              trailing: Switch(
                                value: _notifEnabled,
                                onChanged: (v) async {
                                  setState(() => _notifEnabled = v);
                                  await _savePrefs((p) => p.setBool(_kPrefNotifEnabled, v));
                                },
                              ),
                              onTap: () async {
                                final v = !_notifEnabled;
                                setState(() => _notifEnabled = v);
                                await _savePrefs((p) => p.setBool(_kPrefNotifEnabled, v));
                              },
                            ),
                            _SettingTile(
                              icon: Icons.nightlight_round,
                              title: 'Sessiz Saatler',
                              subtitle: _quietEnabled
                                  ? '${_fmtTime(_quietFrom)} - ${_fmtTime(_quietTo)}'
                                  : 'Kapalı',
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.schedule),
                                    onPressed: _quietEnabled ? _pickQuietRange : null,
                                  ),
                                  Switch(
                                    value: _quietEnabled,
                                    onChanged: (v) async {
                                      setState(() => _quietEnabled = v);
                                      await _savePrefs((p) => p.setBool(_kPrefQuietEnabled, v));
                                    },
                                  ),
                                ],
                              ),
                              onTap: _quietEnabled ? _pickQuietRange : null,
                            ),
                            _SettingTile(
                              icon: Icons.today_outlined,
                              title: 'Günlük Özet',
                              subtitle: _dailySummary ? 'Saat ${_fmtTime(_dailyTime)}' : 'Kapalı',
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: _dailySummary ? _pickDailyTime : null,
                                  ),
                                  Switch(
                                    value: _dailySummary,
                                    onChanged: (v) async {
                                      setState(() => _dailySummary = v);
                                      await _savePrefs((p) => p.setBool(_kPrefDailySummary, v));
                                    },
                                  ),
                                ],
                              ),
                              onTap: _dailySummary ? _pickDailyTime : null,
                            ),
                          ],
                        ),

                        // Hesap
                        _SectionCard(
                          title: 'Hesap',
                          children: [
                            _SettingTile(
                              icon: Icons.lock,
                              title: 'Şifre Değiştir',
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _changePasswordSheet(context),
                            ),
                            _SettingTile(
                              icon: Icons.logout,
                              title: 'Çıkış Yap',
                              titleStyle: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                              leadingBg: Colors.red.withValues(alpha: .12),
                              leadingIconColor: Colors.red,
                              onTap: () => _logout(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// ---- Reusable ----
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _kSurface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title,
              style: const TextStyle(
                color: _kPrimaryDark,
                fontWeight: FontWeight.w800,
                letterSpacing: .2,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;
  final Color? leadingBg;
  final Color? leadingIconColor;
  final TextStyle? titleStyle;

  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.leadingBg,
    this.leadingIconColor,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final leadBg = leadingBg ?? _kPrimaryTint;
    final iconColor = leadingIconColor ?? _kPrimaryDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: leadBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle ?? const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13.2)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
