import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:msret/profile/data/profile_repository.dart';

const _kPrimary = Color(0xFF123A8A);
const _kAccent = Color(0xFF57C3F6);
const _kSurface = Color(0xFFF6F8FC);
const _kInk = Color(0xFF0E1B2C);

const _kAppbarLogoPng = 'assets/brand/logo@3x.png';
const _kEventIconPng = 'assets/icons/event@3x.png';

TextStyle get _titleStrong => const TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.w800,
  letterSpacing: .2,
);

TextStyle get _label => const TextStyle(
  color: Colors.black54,
  fontWeight: FontWeight.w500,
);

extension ColorCompat on Color {
  Color withValues({double? alpha, int? red, int? green, int? blue}) {
    final aInt =
    alpha != null ? (alpha.clamp(0.0, 1.0) * 255).round() : this.alpha;
    final rInt = red ?? this.red;
    final gInt = green ?? this.green;
    final bInt = blue ?? this.blue;
    return Color.fromARGB(aInt & 0xff, rInt & 0xff, gInt & 0xff, bInt & 0xff);
  }
}

enum _Section { attended, applications }

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final SupabaseClient sb = Supabase.instance.client;
  late final ProfileRepository repo = ProfileRepository(sb);

  int? userId;
  String name = 'Ad yok';
  String role = 'student';
  String studentClass = 'Sınıf yok';
  int totalPoint = 0;
  String? email;
  String username = '-';
  String? gender;

  File? profileImageLocal;
  bool _imageBusy = false;
  String? _lastRemovedImagePath;

  final List<AttendedEvent> _attended = [];
  final List<ApplicationItem> _apps = [];

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  static const _pageSize = 20;

  int _attendedOffset = 0;
  bool _attendedHasMore = true;
  bool _attendedLoadingMore = false;

  int _appsOffset = 0;
  bool _appsHasMore = true;
  bool _appsLoadingMore = false;

  bool _loading = true;
  StreamSubscription<AuthState>? _authSub;
  _Section _section = _Section.attended;

  int _loadToken = 0;

  @override
  void initState() {
    super.initState();

    _authSub = sb.auth.onAuthStateChange.listen((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (mounted) {
        _loadAll(resetPaging: true);
      }
    });

    _loadAll(resetPaging: true);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _trGender(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'female':
        return 'Kız';
      case 'male':
        return 'Erkek';
      default:
        return '-';
    }
  }

  IconData _genderIcon(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'female':
        return Icons.female;
      case 'male':
        return Icons.male;
      default:
        return Icons.person_outline;
    }
  }

  Future<void> _ensureSession() async {
    try {
      if (sb.auth.currentSession != null) {
        await sb.auth.refreshSession();
      }
    } catch (_) {}
  }

  Future<void> _loadAll({bool resetPaging = false}) async {
    if (!mounted) return;

    final requestToken = ++_loadToken;

    setState(() => _loading = true);

    if (resetPaging) {
      _attended.clear();
      _apps.clear();
      _attendedOffset = 0;
      _appsOffset = 0;
      _attendedHasMore = true;
      _appsHasMore = true;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      if (mounted) {
        setState(() {
          userId = prefs.getInt('user_id') ?? userId;
          name = prefs.getString('full_name') ?? name;
          role = prefs.getString('role') ?? role;
          studentClass = prefs.getString('class') ?? studentClass;
          email = prefs.getString('email') ?? email;
          username = prefs.getString('username') ?? username;
          gender = prefs.getString('gender') ?? gender;
        });
      }

      await _ensureSession();

      final bundle = await repo.fetchAll(cachedEmail: email);
      if (!mounted || requestToken != _loadToken) return;

      final profile = bundle.profile;

      setState(() {
        userId = profile.id;
        name = profile.name;
        role = profile.role;
        studentClass = profile.studentClass;
        totalPoint = profile.totalPoint;
        email = profile.email ?? email;
        username = profile.username;
        gender = profile.gender;
      });

      if (userId != null) {
        setState(() {
          _attended
            ..clear()
            ..addAll(bundle.events);
          _apps
            ..clear()
            ..addAll(bundle.apps);

          _attendedOffset = _attended.length;
          _appsOffset = _apps.length;
          _attendedHasMore = bundle.events.length >= _pageSize;
          _appsHasMore = bundle.apps.length >= _pageSize;
        });
      }

      final path = prefs.getString('profileImagePath');
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          if (!mounted || requestToken != _loadToken) return;
          setState(() => profileImageLocal = file);
        } else {
          await prefs.remove('profileImagePath');
        }
      } else {
        if (!mounted || requestToken != _loadToken) return;
        setState(() => profileImageLocal = null);
      }
    } finally {
      if (mounted && requestToken == _loadToken) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    if (_imageBusy) return;

    setState(() => _imageBusy = true);

    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.split('.').last;
      final file = File(
        '${dir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );

      await File(picked.path).copy(file.path);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profileImagePath', file.path);

      if (!mounted) return;

      setState(() {
        profileImageLocal = file;
        _lastRemovedImagePath = null;
      });
    } finally {
      if (mounted) setState(() => _imageBusy = false);
    }
  }

  Future<void> _removeImage({bool permanent = false}) async {
    if (_imageBusy) return;

    setState(() => _imageBusy = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('profileImagePath');
      if (path == null || path.isEmpty) return;

      _lastRemovedImagePath = path;
      await prefs.remove('profileImagePath');

      if (mounted) {
        setState(() => profileImageLocal = null);
      }

      if (!mounted) return;

      if (!permanent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Fotoğraf kaldırıldı'),
            action: SnackBarAction(
              label: 'Geri Al',
              onPressed: () async {
                if (_lastRemovedImagePath != null) {
                  final file = File(_lastRemovedImagePath!);
                  await prefs.setString(
                    'profileImagePath',
                    _lastRemovedImagePath!,
                  );
                  if (mounted) {
                    setState(() => profileImageLocal = file);
                  }
                }
              },
            ),
          ),
        );
      } else {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}

        _lastRemovedImagePath = null;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fotoğraf kalıcı olarak silindi')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _imageBusy = false);
    }
  }

  Future<void> _showAvatarActions() async {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Fotoğrafı değiştir'),
              subtitle: const Text('Galeriden yeni bir görsel seç'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.hide_image_outlined),
              title: const Text('Fotoğrafı kaldır'),
              onTap: () async {
                Navigator.pop(context);

                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Kaldırılsın mı?'),
                    content: const Text(
                      'Profil fotoğrafı kaldırılacak. İstersen geri alabilirsin.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Vazgeç'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Kaldır'),
                      ),
                    ],
                  ),
                );

                if (ok == true) {
                  await _removeImage();
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_forever_outlined,
                color: Colors.redAccent,
              ),
              title: const Text('Kalıcı sil'),
              subtitle: const Text('Cihazdan da silinir'),
              onTap: () async {
                Navigator.pop(context);

                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Kalıcı silme'),
                    content: const Text(
                      'Görsel dosyası cihazdan da silinecek. Emin misin?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Vazgeç'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sil'),
                      ),
                    ],
                  ),
                );

                if (ok == true) {
                  await _removeImage(permanent: true);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _glass({
    required Widget child,
    EdgeInsetsGeometry? padding,
    double blur = 12,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding ?? const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.66),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(.4)),
            boxShadow: [
              BoxShadow(
                color: _kInk.withValues(alpha: .08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _avatar() {
    return Semantics(
      label: 'Profil fotoğrafı',
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_kAccent, Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _kAccent.withValues(alpha: .35),
                  blurRadius: 22,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 58,
              backgroundColor: Colors.white,
              backgroundImage:
              profileImageLocal != null ? FileImage(profileImageLocal!) : null,
              child: profileImageLocal == null
                  ? const Icon(Icons.person, size: 56, color: Colors.black26)
                  : null,
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Material(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(999),
              elevation: 2,
              child: InkWell(
                onTap: _imageBusy ? null : _showAvatarActions,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _imageBusy
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(
                    Icons.camera_alt_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
      IconData icon,
      String label,
      String value, {
        bool showDivider = true,
      }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: _kAccent.withValues(alpha: .18),
                child: Icon(icon, size: 16, color: _kPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: _label)),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 0, color: Colors.grey.withValues(alpha: .25)),
      ],
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('dd.MM.yyyy', 'tr_TR').format(date);
  }

  Widget _pointsBanner() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: totalPoint.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final shown = value.round();

        return _glass(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _kPrimary.withValues(alpha: .95),
                  _kAccent.withValues(alpha: .95),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              child: Row(
                children: [
                  const Icon(Icons.stars_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Toplam Puan',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$shown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _kPrimary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _eventLeadingIcon() {
    return CircleAvatar(
      backgroundColor: Colors.white,
      child: ClipOval(
        child: Image.asset(
          _kEventIconPng,
          width: 22,
          height: 22,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
          const Icon(Icons.event, color: _kPrimary),
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String text) {
    return _glass(
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonTile() {
    return _glass(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: double.infinity,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 120,
                  color: Colors.grey.shade200,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<AttendedEvent> get _filteredAttended {
    if (_query.isEmpty) return _attended;
    final q = _query.toLowerCase();
    return _attended.where((item) {
      return item.title.toLowerCase().contains(q);
    }).toList();
  }

  List<ApplicationItem> get _filteredApps {
    if (_query.isEmpty) return _apps;
    final q = _query.toLowerCase();
    return _apps.where((item) {
      return item.title.toLowerCase().contains(q) ||
          item.status.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _loadMoreAttended() async {
    if (!_attendedHasMore || _attendedLoadingMore || userId == null) return;

    setState(() => _attendedLoadingMore = true);

    try {
      final items = await repo.fetchAttendedEventsFromPoints(
        userId!,
        limit: _pageSize,
        offset: _attendedOffset,
      );

      setState(() {
        _attended.addAll(items);
        _attendedOffset += items.length;
        _attendedHasMore = items.length >= _pageSize;
      });
    } finally {
      if (mounted) {
        setState(() => _attendedLoadingMore = false);
      }
    }
  }

  Future<void> _loadMoreApps() async {
    if (!_appsHasMore || _appsLoadingMore || userId == null) return;

    setState(() => _appsLoadingMore = true);

    try {
      final items = await repo.fetchActiveApplications(
        userId!,
        limit: _pageSize,
        offset: _appsOffset,
      );

      setState(() {
        _apps.addAll(items);
        _appsOffset += items.length;
        _appsHasMore = items.length >= _pageSize;
      });
    } finally {
      if (mounted) {
        setState(() => _appsLoadingMore = false);
      }
    }
  }

  Widget _attendedList() {
    final list = _filteredAttended;

    if (_loading) {
      return Column(
        children: List.generate(
          5,
              (_) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _skeletonTile(),
          ),
        ),
      );
    }

    if (list.isEmpty) {
      return _emptyState(
        Icons.event_busy,
        'Henüz katıldığınız etkinlik bulunmuyor.',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 120) {
          _loadMoreAttended();
        }
        return false;
      },
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: list.length + (_attendedHasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, index) {
          if (index >= list.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: _kPrimary),
              ),
            );
          }

          final item = list[index];

          return _glass(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              leading: _eventLeadingIcon(),
              title: Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Wrap(
                  spacing: 8,
                  runSpacing: -4,
                  children: [
                    _pill(
                      Icons.local_fire_department,
                      'Etkinlik: +${item.eventPoint}',
                    ),
                    _pill(
                      Icons.check_circle,
                      'Kazanılan: +${item.earnedPoint}',
                    ),
                    if (item.date != null)
                      _pill(Icons.calendar_month, _formatDate(item.date)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _applicationsList() {
    String trStatus(String value) {
      switch (value.toLowerCase()) {
        case 'pending':
          return 'Beklemede';
        case 'approved':
        case 'accepted':
          return 'Kabul';
        case 'waiting':
          return 'Sırada';
        case 'registered':
          return 'Kayıtlı';
        case 'rejected':
          return 'Reddedildi';
        default:
          return value;
      }
    }

    IconData statusIcon(String value) {
      switch (value.toLowerCase()) {
        case 'approved':
        case 'accepted':
        case 'registered':
          return Icons.verified_rounded;
        case 'rejected':
          return Icons.block;
        case 'waiting':
          return Icons.schedule;
        default:
          return Icons.hourglass_empty;
      }
    }

    final list = _filteredApps;

    if (_loading) {
      return Column(
        children: List.generate(
          5,
              (_) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _skeletonTile(),
          ),
        ),
      );
    }

    if (list.isEmpty) {
      return _emptyState(
        Icons.hourglass_empty,
        'Aktif başvurunuz bulunmuyor.',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 120) {
          _loadMoreApps();
        }
        return false;
      },
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: list.length + (_appsHasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, index) {
          if (index >= list.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: _kPrimary),
              ),
            );
          }

          final item = list[index];

          return _glass(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              leading: _eventLeadingIcon(),
              title: Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Wrap(
                  spacing: 8,
                  runSpacing: -4,
                  children: [
                    _pill(
                      statusIcon(item.status),
                      'Durum: ${trStatus(item.status)}',
                    ),
                    if (item.date != null)
                      _pill(Icons.calendar_month, _formatDate(item.date)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _segment() {
    final isAttended = _section == _Section.attended;
    final isApplications = _section == _Section.applications;

    Widget segmentButton({
      required String text,
      required IconData icon,
      required bool active,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          onTap: active ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: active
                  ? _kPrimary.withValues(alpha: .92)
                  : Colors.white.withOpacity(.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? _kPrimary.withValues(alpha: .95)
                    : Colors.white.withOpacity(.6),
                width: 1,
              ),
              boxShadow: active
                  ? [
                BoxShadow(
                  color: _kPrimary.withValues(alpha: .18),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
                  : [],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: active ? Colors.white : _kPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : _kPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'İçerik seçimi',
      child: _glass(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            segmentButton(
              text: 'Katıldıklarım',
              icon: Icons.emoji_events_outlined,
              active: isAttended,
              onTap: () => setState(() => _section = _Section.attended),
            ),
            const SizedBox(width: 8),
            segmentButton(
              text: 'Aktif Başvurularım',
              icon: Icons.pending_actions_outlined,
              active: isApplications,
              onTap: () => setState(() => _section = _Section.applications),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileInfoCard() {
    return _glass(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _infoRow(Icons.badge_outlined, 'Adı Soyadı', name),
          _infoRow(Icons.email_outlined, 'E-posta', email ?? '-'),
          _infoRow(Icons.alternate_email, 'Kullanıcı Adı', username),
          _infoRow(Icons.school_outlined, 'Sınıf', studentClass),
          _infoRow(_genderIcon(gender), 'Cinsiyet', _trGender(gender)),
          _infoRow(Icons.person_outline, 'Rol', role, showDivider: false),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Semantics(
      label: 'Arama alanı',
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value.trim()),
        decoration: InputDecoration(
          hintText: 'Ara: etkinlik veya başlık…',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectionTitle = _section == _Section.attended
        ? 'Katıldığı Etkinlikler'
        : 'Aktif Başvurularım';

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              _kAppbarLogoPng,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
              const Icon(Icons.school, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text(
              'Profil',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: () => _loadAll(resetPaging: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: () => _loadAll(resetPaging: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _avatar(),
              const SizedBox(height: 14),
              Text(name, style: _titleStrong, textAlign: TextAlign.center),
              if ((email ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(email!, style: const TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 12),
              _profileInfoCard(),
              const SizedBox(height: 12),
              _pointsBanner(),
              const SizedBox(height: 12),
              _searchBar(),
              const SizedBox(height: 12),
              _segment(),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  sectionTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              if (_section == _Section.attended)
                _attendedList()
              else
                _applicationsList(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}