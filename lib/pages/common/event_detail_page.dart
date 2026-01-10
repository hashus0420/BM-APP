// lib/pages/common/event_detail_page.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/event_model.dart';

enum UserRole { admin, teacher, student }

/* ====================== DESIGN TOKENS ====================== */
const kNavy = Color(0xFF113A7D);
const kSky = Color(0xFF57C3F6);
const kTeal = Color(0xFF00796B);
const kWarn = Color(0xFFD32F2F);
const kBg = Color(0xFFF7FAFF);
const kInk = Color(0xFF0F1F33);

const kPrimary = kNavy;
const kAccent = kSky;
const kOk = kTeal;

const r12 = 12.0;
const r16 = 16.0;
const r20 = 20.0;
const r14 = 14.0;

const kSpace1 = 8.0;
const kSpace2 = 12.0;
const kSpace3 = 16.0;
const kSpace4 = 20.0;

// ==== LAYOUT TUNING ====
const double kHeaderHeight = 140;
const double kUiScale = 1.12;

// Tipografi
TextStyle get _titleStyle =>
    TextStyle(fontSize: 20 * kUiScale, fontWeight: FontWeight.w700, color: kInk);
TextStyle get _labelStyle =>
    TextStyle(fontSize: 12 * kUiScale, color: Colors.grey);
TextStyle get _valueStyle =>
    TextStyle(fontSize: 18 * kUiScale, fontWeight: FontWeight.w800, color: kInk);

/* ====================== PAGE ====================== */
class EventDetailPage extends StatefulWidget {
  final EventModel event;
  const EventDetailPage({super.key, required this.event});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabs;

  Timer? _countdownTimer;
  Timer? _checkinPoller;
  Duration _timeLeft = Duration.zero;

  int? _currentUserId;
  String? _currentUserUid;

  UserRole _currentUserRole = UserRole.student;
  bool get _isAdmin => _currentUserRole == UserRole.admin;
  bool get _isTeacher => _currentUserRole == UserRole.teacher;

  // Tüm yönetim yetkileri: admin || etkinlik sahibi || öğretmen
  bool get _canManage => _isAdmin || _isEventOwner || _isTeacher;

  DateTime? _startsAt;
  DateTime? _endsAt;

  int? _ownerId;
  String? _ownerUid;
  String? _ownerName;
  String? _ownerEmail;

  bool get _isEventOwner {
    final idMatch =
    (_ownerId != null && _currentUserId != null && _ownerId == _currentUserId);
    final uidMatch =
    (_ownerUid != null && _currentUserUid != null && _ownerUid == _currentUserUid);
    return idMatch || uidMatch;
  }

  bool _canCheckin = false;
  bool _hasAlreadyApplied = false;
  int _registeredCount = 0;
  List<Map<String, dynamic>> _participants = [];

  bool _loading = true;
  String _search = '';

  // Local overrides
  String? _ovTitle, _ovLocation, _ovImageUrl, _ovDescription;
  int? _ovPoint;
  DateTime? _ovEventDate;

  // Realtime
  RealtimeChannel? _regChannel;

  String get _dispTitle => _ovTitle ?? widget.event.title;
  String get _dispLocation => _ovLocation ?? widget.event.location;
  String? get _dispImage => _ovImageUrl ?? widget.event.imageUrl;
  String get _dispDescription => _ovDescription ?? (widget.event.description ?? '—');
  int get _dispPoint => _ovPoint ?? widget.event.point;
  DateTime get _dispEventDate => _ovEventDate ?? widget.event.eventDate;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _calculateTimeLeft();

    // frame-sonsrası setState — stretch hatasını tetiklememesi için
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(_calculateTimeLeft);
      });
    });

    _bootstrap();
    _setupRealtime();
  }

  Future<void> _bootstrap() async {
    await _loadUserInfo();
    await Future.wait([
      _fetchParticipants(),
      _refreshCanCheckin(),
      _loadEventMeta(),
    ]);
    await _checkIfAlreadyApplied();
    _checkinPoller =
        Timer.periodic(const Duration(seconds: 20), (_) => _refreshCanCheckin());
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _setupRealtime() {
    final id = widget.event.id;
    if (id == null) return;
    _regChannel = supabase
        .channel('event_regs_$id')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'event_registrations',
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, column: 'event_id', value: '$id'),
      callback: (_) => _fetchParticipants(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'event_registrations',
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, column: 'event_id', value: '$id'),
      callback: (_) => _fetchParticipants(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'event_registrations',
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, column: 'event_id', value: '$id'),
      callback: (_) => _fetchParticipants(),
    )
        .subscribe();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _checkinPoller?.cancel();
    _tabs.dispose();
    // Kanalı düzgün kapat
    _regChannel?.unsubscribe();
    if (_regChannel != null) {
      supabase.removeChannel(_regChannel!);
    }
    super.dispose();
  }

  /* ====================== HELPERS ====================== */
  double sx(BuildContext c) {
    final scaled = MediaQuery.textScalerOf(c).scale(1.0);
    return scaled.clamp(1.0, 1.3);
  }

  void _calculateTimeLeft() {
    final d = _dispEventDate.difference(DateTime.now());
    _timeLeft = d.isNegative ? Duration.zero : d;
  }

  String _formatTime(DateTime? dt) => dt == null ? '-' : DateFormat('HH:mm').format(dt);

  String _formatCountdown(Duration d) {
    if (d == Duration.zero) return 'Etkinlik başladı / bitti';
    final days = d.inDays, h = d.inHours % 24, m = d.inMinutes % 60, s = d.inSeconds % 60;
    if (days > 0) return '$days g $h s $m d';
    if (h > 0) return '$h s $m d $s sn';
    if (m > 0) return '$m d $s sn';
    return '$s sn';
  }

  Future<void> _toast(String msg, {bool error = false}) async {
    if (error) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? kWarn : Colors.black87,
      ),
    );
  }

  Future<void> _notify(String title, String message,
      {bool error = false, IconData? icon}) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20)),
        title: Row(
          children: [
            Icon(icon ?? (error ? Icons.error_outline : Icons.info_outline),
                color: error ? kWarn : kPrimary),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
        ],
      ),
    );
  }

  bool _isYoklamaClosedError(Object e) {
    if (e is PostgrestException) {
      if ((e.code ?? '').toUpperCase() == 'P0001') return true;
      final msg = (e.message ?? '').toLowerCase();
      if (msg.contains('yoklama penceresi kapalı')) return true;
    }
    final s = e.toString().toLowerCase();
    return s.contains('yoklama penceresi kapalı') || s.contains('p0001');
  }

  /* ====================== DATA ====================== */
  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final roleStr = (prefs.getString('role') ?? 'student').trim();
    _currentUserId = prefs.getInt('user_id');
    _currentUserUid = prefs.getString('user_uid');
    _currentUserRole = UserRole.values.firstWhere(
          (e) => e.name == roleStr,
      orElse: () => UserRole.student,
    );
  }

  Future<void> _loadEventMeta() async {
    if (widget.event.id == null) return;
    try {
      final row = await supabase
          .from('events')
          .select('starts_at, ends_at, created_by')
          .eq('id', widget.event.id!)
          .maybeSingle();

      int? ownerId;
      String? ownerUid;

      if (row != null) {
        final cb = row['created_by'];
        if (cb is int) {
          ownerId = cb;
        } else if (cb is String) {
          ownerUid = cb.trim();
        }
      }

      String? ownerName, ownerEmail;
      try {
        if (ownerId != null) {
          final u = await supabase
              .from('users')
              .select('id, name, email')
              .eq('id', ownerId)
              .maybeSingle();
          ownerName = (u?['name'] as String?)?.trim();
          ownerEmail = (u?['email'] as String?)?.trim();
        } else if (ownerUid != null) {
          final u = await supabase
              .from('users')
              .select('id, name, email, auth_uid')
              .eq('auth_uid', ownerUid)
              .maybeSingle();
          ownerName = (u?['name'] as String?)?.trim();
          ownerEmail = (u?['email'] as String?)?.trim();
        }
      } catch (_) {}

      setState(() {
        _startsAt = row?['starts_at'] != null
            ? DateTime.tryParse('${row!['starts_at']}')?.toLocal()
            : null;
        _endsAt = row?['ends_at'] != null
            ? DateTime.tryParse('${row!['ends_at']}')?.toLocal()
            : null;
        _ownerId = ownerId;
        _ownerUid = ownerUid;
        _ownerName = ownerName;
        _ownerEmail = ownerEmail;
      });
    } catch (_) {}
  }

  Future<void> _refreshCanCheckin() async {
    if (widget.event.id == null) return;
    try {
      final res =
      await supabase.rpc('can_checkin_int', params: {'p_event': widget.event.id});
      setState(() => _canCheckin = (res as bool?) ?? false);
    } catch (_) {
      setState(() => _canCheckin = false);
    }
  }

  Future<void> _fetchParticipants() async {
    final id = widget.event.id;
    if (id == null) return;
    try {
      final data = await supabase
          .from('event_registrations')
          .select('id, is_participated, student_id(id, name)')
          .eq('event_id', id);

      final list = (data as List).map<Map<String, dynamic>>((e) {
        final s = e['student_id'];
        final sid = s is Map ? (s['id'] ?? s['user_id'] ?? s['student_id']) : s;
        final name = s is Map ? (s['name'] ?? 'İsimsiz') : 'İsimsiz';
        return {
          'id': e['id'],
          'studentId': sid is int ? sid : int.tryParse('$sid') ?? -1,
          'name': '$name',
          'attendance': e['is_participated'] ?? false,
        };
      }).toList();

      list.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));

      setState(() {
        _participants = list;
        _registeredCount = list.length;
      });
    } catch (e) {
      _notify('Hata', 'Katılımcılar alınamadı: $e', error: true);
    }
  }

  Future<void> _checkIfAlreadyApplied() async {
    final uid = _currentUserId;
    if (uid == null || widget.event.id == null) return;
    try {
      final data = await supabase
          .from('event_registrations')
          .select('id')
          .eq('event_id', widget.event.id!)
          .eq('student_id', uid);
      setState(() => _hasAlreadyApplied = (data as List).isNotEmpty);
    } catch (_) {}
  }

  /* ====================== ACTIONS ====================== */

  Future<void> _applyToEvent() async {
    final uid = _currentUserId;
    if (uid == null) {
      return _notify('Giriş Gerekli', 'Önce giriş yapmalısınız.', error: true);
    }
    if (widget.event.id == null) {
      return _notify('Eksik Bilgi', 'Etkinlik bilgisi eksik.', error: true);
    }

    try {
      final resp = await supabase
          .from('event_registrations')
          .upsert(
        {
          'event_id': widget.event.id,
          'student_id': uid,
          'is_participated': false
        },
        onConflict: 'event_id,student_id',
        ignoreDuplicates: true,
      )
          .select()
          .maybeSingle();
      setState(() => _hasAlreadyApplied = true);
      if (resp != null) await _fetchParticipants();
      await _toast('Başvurunuz alındı 🎉');
    } catch (e) {
      if (e.toString().contains('23505')) {
        setState(() => _hasAlreadyApplied = true);
        return _toast('Bu etkinliğe zaten başvurdunuz.');
      }
      _toast('İşlem sırasında bir sorun oluştu', error: true);
    }
  }

  // ÖĞRENCİ: Başvurusunu iptal et
  Future<void> _cancelApplication() async {
    final uid = _currentUserId;
    if (uid == null || widget.event.id == null) {
      return _notify('Giriş Gerekli', 'Önce giriş yapmalısınız.', error: true);
    }
    try {
      await supabase
          .from('event_registrations')
          .delete()
          .eq('event_id', widget.event.id!)
          .eq('student_id', uid);

      // varsa puan kaydını da temizleyelim (opsiyonel)
      await supabase
          .from('points')
          .delete()
          .eq('event_id', widget.event.id!)
          .eq('student_id', uid);

      setState(() => _hasAlreadyApplied = false);
      await _fetchParticipants();
      await _toast('Başvurunuz iptal edildi');
    } catch (e) {
      _toast('Başvuru iptal edilemedi', error: true);
    }
  }

  // force=true ise kapalı pencereye rağmen yöneticinin/öğretmenin onay verebilmesi sağlanır
  Future<void> _joinLeave(bool join, {int? userId, int? regId, bool force = false}) async {
    final uid = userId ?? _currentUserId;
    if (uid == null || widget.event.id == null) {
      return _notify('Giriş Gerekli', 'Önce giriş yapmalısınız.', error: true);
    }

    // Öğrenciler force kullanamaz; yönetici/sahip/öğretmen kullanabilir
    final mayForce = force && _canManage;

    // Normalde pencere kapalıysa uyar; fakat mayForce ise devam et
    if (!mayForce) {
      await _refreshCanCheckin();
      if (!_canCheckin) {
        return _notify(
          'Yoklama Kapalı',
          'Yoklama penceresi kapalı. Yönetici/öğretmen bu ekran üzerinden onay verebilir.',
          error: true,
        );
      }
    }

    Future<void> directUpdate() async {
      // Kayıt yoksa oluştur
      final existing = await supabase
          .from('event_registrations')
          .select('id')
          .eq('event_id', widget.event.id!)
          .eq('student_id', uid)
          .maybeSingle();

      final int useRegId;
      if (existing == null) {
        final inserted = await supabase.from('event_registrations').insert({
          'event_id': widget.event.id!,
          'student_id': uid,
          'is_participated': join,
          'recorded_by': _currentUserId,
        }).select('id').single();
        useRegId = inserted['id'] as int;
      } else {
        useRegId = (existing['id'] as int);
        await supabase
            .from('event_registrations')
            .update({'is_participated': join, 'recorded_by': _currentUserId})
            .eq('id', useRegId);
      }
    }

    try {
      if (mayForce) {
        // Önce force RPC var mı dene
        final rpcName = join ? 'join_event_force_int' : 'leave_event_force_int';
        try {
          await supabase.rpc(rpcName, params: {'p_user_id': uid, 'p_event': widget.event.id});
        } catch (_) {
          // Yoksa doğrudan tablo güncelle
          await directUpdate();
        }
      } else {
        // Normal RPC
        if (join) {
          await supabase
              .rpc('join_event_int', params: {'p_user_id': uid, 'p_event': widget.event.id});
        } else {
          await supabase
              .rpc('leave_event_int', params: {'p_user_id': uid, 'p_event': widget.event.id});
        }

        // UI tutarlılığı için yine de registration satırını güncelle
        if (regId != null) {
          await supabase
              .from('event_registrations')
              .update({'is_participated': join, 'recorded_by': _currentUserId})
              .eq('id', regId);
        } else {
          await supabase
              .from('event_registrations')
              .update({'is_participated': join, 'recorded_by': uid})
              .eq('event_id', widget.event.id!)
              .eq('student_id', uid);
        }
      }

      await _fetchParticipants();
      await _refreshCanCheckin();
      await _toast(join ? 'Yoklama verildi' : 'Yoklama geri alındı');
    } catch (e) {
      // Eğer kapalı pencere hatası geldiyse ve yetkili ise fallback
      if (_isYoklamaClosedError(e) && _canManage) {
        try {
          await directUpdate();
          await _fetchParticipants();
          return _toast(join ? 'Yoklama verildi (force)' : 'Yoklama geri alındı (force)');
        } catch (ee) {
          return _notify('Hata', 'Yoklama güncellenemedi: $ee', error: true);
        }
      }
      _notify('Hata', 'Yoklama güncellenemedi: $e', error: true);
    }
  }

  Future<void> _kickParticipant(int regId, int studentId) async {
    if (!_canManage) {
      return _notify('Yetki Yok', 'Katılımcı çıkarmak için yetkiniz yok.', error: true);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20)),
        title: const Text('Katılımcıyı Çıkar'),
        content: const Text('Bu katılımcı etkinlikten çıkarılacak. Devam edilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Çıkar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('event_registrations').delete().eq('id', regId);
      await supabase
          .from('points')
          .delete()
          .eq('event_id', widget.event.id!)
          .eq('student_id', studentId);
      await _fetchParticipants();
      await _toast('Katılımcı çıkarıldı');
    } catch (e) {
      _toast('Katılımcı çıkarılamadı', error: true);
    }
  }

  Future<void> _markAll(bool present) async {
    if (!_canManage) {
      return _notify('Yetki Yok', 'Bu işlem için yetkiniz yok.', error: true);
    }
    // Kapalıysa da force ile devam
    try {
      for (final p in _participants) {
        final cur = p['attendance'] ?? false;
        if (cur == present) continue;
        await _joinLeave(present,
            userId: p['studentId'] as int, regId: p['id'] as int, force: true);
      }
      await supabase
          .from('event_registrations')
          .update({'is_participated': present, 'recorded_by': _currentUserId})
          .eq('event_id', widget.event.id!);
      await _fetchParticipants();
      await _toast(
          present ? 'Tümü katıldı olarak işaretlendi' : 'Tümü katılmadı olarak işaretlendi');
    } catch (e) {
      _notify('Hata', 'Toplu işlem başarısız: $e', error: true);
    }
  }

  Future<void> _deleteEvent() async {
    if (!_canManage) {
      return _notify('Yetki Yok', 'Sadece admin/öğretmen/sahip silebilir.', error: true);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20)),
        title: const Text('Etkinliği Sil'),
        content: const Text('Etkinlik ve tüm ilişkili kayıtlar silinecek. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('points').delete().eq('event_id', widget.event.id!);
      await supabase.from('event_registrations').delete().eq('event_id', widget.event.id!);
      await supabase.from('events').delete().eq('id', widget.event.id!);
      if (!mounted) return;
      await _toast('Etkinlik silindi');
      Navigator.pop(context);
    } catch (e) {
      _toast('Etkinlik silinemedi', error: true);
    }
  }

  Future<void> _toggleCheckin() async {
    if (!_canManage) {
      return _notify(
          'Yetki Yok', 'Yalnızca öğretmen/sahip veya admin değiştirebilir.', error: true);
    }
    final newState = !_canCheckin;

    try {
      final res =
      await supabase.rpc('toggle_checkin_int', params: {'p_event': widget.event.id});
      if (res is bool) {
        setState(() => _canCheckin = res);
        return _toast(res ? 'Yoklama açıldı' : 'Yoklama kapatıldı');
      }
    } catch (_) {}

    try {
      await supabase
          .rpc('set_checkin_open', params: {'p_event': widget.event.id, 'p_open': newState});
      setState(() => _canCheckin = newState);
      return _toast(newState ? 'Yoklama açıldı' : 'Yoklama kapatıldı');
    } catch (e) {
      return _notify('Hata', 'Yoklama durumu değiştirilemedi: $e', error: true);
    }
  }

  // Takvime eklemek için ICS
  Future<void> _exportIcs() async {
    final s = _startsAt ??
        DateTime(_dispEventDate.year, _dispEventDate.month, _dispEventDate.day, 9);
    final e = _endsAt ?? s.add(const Duration(hours: 1));
    final ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART:${DateFormat("yyyyMMdd'T'HHmmss'Z'").format(s.toUtc())}
DTEND:${DateFormat("yyyyMMdd'T'HHmmss'Z'").format(e.toUtc())}
SUMMARY:$_dispTitle
LOCATION:$_dispLocation
DESCRIPTION:$_dispDescription
END:VEVENT
END:VCALENDAR
''';
    await Clipboard.setData(ClipboardData(text: ics));
    await _toast('ICS panoya kopyalandı. Takvime yapıştırarak ekleyebilirsin.');
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // Rapor: sadece katılanlar
  Future<void> _copyPresentList() async {
    final list = _participants.where((p) => (p['attendance'] ?? false) == true);
    final buf = StringBuffer()..writeln('name');
    for (final p in list) {
      final name = (p['name'] ?? '').toString().replaceAll(',', ' ');
      buf.writeln(name);
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    _notify('Katılanlar Kopyalandı', 'Sadece katılanların listesi panoya kopyalandı.',
        icon: Icons.playlist_add_check);
  }

  /* ====================== BUILD ====================== */
  @override
  Widget build(BuildContext context) {
    final canManage = _canManage;

    return Scaffold(
      backgroundColor: kBg,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: StudentActionsFab(
        isStudent: _currentUserRole == UserRole.student,
        timeLeft: _timeLeft,
        hasApplied: _hasAlreadyApplied,
        canCheckin: _canCheckin,
        isEventPassed: DateTime.now().isAfter(_dispEventDate),
        onApply: _applyToEvent,
        onCancel: _cancelApplication,
        onJoin: () => _joinLeave(true),
        onLeave: () => _joinLeave(false),
      ),
      body: _loading
          ? const _SkeletonDetail()
          : RefreshIndicator(
        onRefresh: () async {
          await _fetchParticipants();
          await _refreshCanCheckin();
          await _loadEventMeta();
          await _checkIfAlreadyApplied();
        },
        child: NestedScrollView(
          physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          headerSliverBuilder: (ctx, scrolled) => [
            SliverAppBar(
              pinned: true,
              stretch: false, // stretch kapalı
              expandedHeight: kHeaderHeight,
              title: Text(_dispTitle,
                  style:
                  TextStyle(color: Colors.white, fontSize: 18 * sx(context))),
              backgroundColor: kPrimary,
              actionsIconTheme: const IconThemeData(color: Colors.white),
              actions: [
                if (canManage)
                  IconButton(
                    tooltip: _canCheckin ? 'Yoklamayı Kapat' : 'Yoklamayı Aç',
                    icon:
                    Icon(_canCheckin ? Icons.lock_open : Icons.lock_clock),
                    onPressed: _toggleCheckin,
                  ),
                if (canManage)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'calendar') _exportIcs();
                      if (v == 'manage') _openManageSheet();
                    },
                    itemBuilder: (c) => const [
                      PopupMenuItem(
                        value: 'calendar',
                        child: Row(
                          children: [
                            Icon(Icons.event_available_outlined),
                            SizedBox(width: 8),
                            Text('Takvime ekle (ICS)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'manage',
                        child: Row(
                          children: [
                            Icon(Icons.tune),
                            SizedBox(width: 8),
                            Text('Yönet'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: const [
                  StretchMode.blurBackground,
                  StretchMode.zoomBackground
                ],
                background: _HeroHeader(imageUrl: _dispImage),
              ),
              bottom: TabBar(
                controller: _tabs,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard_outlined), text: 'Detay'),
                  Tab(icon: Icon(Icons.groups_2_outlined), text: 'Katılımcılar'),
                ],
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabs,
            children: [
              SummarySectionPro(
                date: _dispEventDate,
                timeText:
                '${_formatTime(_startsAt)} – ${_formatTime(_endsAt)}',
                location: _dispLocation,
                point: _dispPoint,
                canCheckin: _canCheckin,
                ownerName: _ownerName,
                registered: _registeredCount,
                countdownText: _formatCountdown(_timeLeft),
                description: _dispDescription,
                isPast: DateTime.now().isAfter(_dispEventDate),
              ),
              ParticipantsSection(
                participants: _participants,
                canCheckin: _canCheckin,
                canManage: canManage,
                onSearch: (q) => setState(() => _search = q),
                searchQuery: _search,
                // Kapalı olsa bile canManage ise force:true gönderiyoruz
                onJoin: (regId, studentId, {bool force = false}) => _joinLeave(true,
                    userId: studentId,
                    regId: regId,
                    force: force || (canManage && !_canCheckin)),
                onLeave: (regId, studentId, {bool force = false}) =>
                    _joinLeave(false,
                        userId: studentId,
                        regId: regId,
                        force: force || (canManage && !_canCheckin)),
                onKick: (regId, studentId) => _kickParticipant(regId, studentId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openManageSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(r20)),
      ),
      builder: (_) => ManageSheet(
        isAdmin: _isAdmin,
        canCheckin: _canCheckin,
        onCsv: _copyCsv,
        onCopyPresent: _copyPresentList,
        onAllJoin: () => _markAll(true), // force
        onAllLeave: () => _markAll(false), // force
        onEdit: _openEditEventSheet,
        onDelete: _deleteEvent,
      ),
    );
  }

  Future<void> _copyCsv() async {
    final buf = StringBuffer()..writeln('name,attendance');
    for (final p in _participants) {
      final name = (p['name'] ?? '').toString().replaceAll(',', ' ');
      final att = (p['attendance'] ?? false) ? 'joined' : 'left';
      buf.writeln('$name,$att');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    _notify('CSV Kopyalandı', 'Katılımcı listesi panoya kopyalandı.',
        icon: Icons.table_chart_outlined);
  }

  // -------- Admin/Teacher/Owner: Etkinliği Düzenle --------
  Future<void> _openEditEventSheet() async {
    if (!_canManage) {
      _notify('Yetki Yok', 'Yalnızca öğretmen/sahip veya admin düzenleyebilir.',
          error: true);
      // ignore: invariant_booleans
      return;
    }

    final titleCtrl = TextEditingController(text: _dispTitle);
    final descCtrl =
    TextEditingController(text: _dispDescription == '—' ? '' : _dispDescription);
    final locCtrl = TextEditingController(text: _dispLocation);
    final imgCtrl = TextEditingController(text: _dispImage ?? '');
    final pointCtrl = TextEditingController(text: _dispPoint.toString());

    DateTime date = _dispEventDate;
    TimeOfDay? startTod = _startsAt != null
        ? TimeOfDay(hour: _startsAt!.hour, minute: _startsAt!.minute)
        : null;
    TimeOfDay? endTod = _endsAt != null
        ? TimeOfDay(hour: _endsAt!.hour, minute: _endsAt!.minute)
        : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Etkinliği Düzenle',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Başlık, açıklama, tarih/saat, konum, puan, görsel'),
                  ),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Başlık'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Açıklama'),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: locCtrl,
                        decoration: const InputDecoration(labelText: 'Konum'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: imgCtrl,
                        decoration: const InputDecoration(labelText: 'Görsel URL'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  // Puan alanı (kontenjan kaldırıldı)
                  TextField(
                    controller: pointCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Puan'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event),
                          label: Text(DateFormat('d MMM y', 'tr').format(date)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              locale: const Locale('tr', 'TR'),
                            );
                            if (picked != null) setSheet(() => date = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label:
                          Text(startTod == null ? 'Başlangıç' : startTod!.format(ctx)),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime:
                              startTod ?? const TimeOfDay(hour: 9, minute: 0),
                              builder: (context, child) => MediaQuery(
                                data: MediaQuery.of(context)
                                    .copyWith(alwaysUse24HourFormat: true),
                                child: child!,
                              ),
                            );
                            if (picked != null) setSheet(() => startTod = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(endTod == null ? 'Bitiş' : endTod!.format(ctx)),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime:
                              endTod ?? const TimeOfDay(hour: 10, minute: 0),
                              builder: (context, child) => MediaQuery(
                                data: MediaQuery.of(context)
                                    .copyWith(alwaysUse24HourFormat: true),
                                child: child!,
                              ),
                            );
                            if (picked != null) setSheet(() => endTod = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('İptal'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Kaydet'),
                        onPressed: () async {
                          try {
                            final updates = <String, dynamic>{};

                            if (titleCtrl.text.trim().isNotEmpty &&
                                titleCtrl.text.trim() != _dispTitle) {
                              updates['title'] = titleCtrl.text.trim();
                            }
                            if (descCtrl.text.trim() !=
                                (_dispDescription == '—' ? '' : _dispDescription)) {
                              updates['description'] = descCtrl.text.trim();
                            }
                            if (locCtrl.text.trim().isNotEmpty &&
                                locCtrl.text.trim() != _dispLocation) {
                              updates['location'] = locCtrl.text.trim();
                            }
                            if ((imgCtrl.text.trim()) != (_dispImage ?? '')) {
                              updates['image_url'] = imgCtrl.text.trim();
                            }
                            final newPoint = int.tryParse(pointCtrl.text.trim());
                            if (newPoint != null && newPoint != _dispPoint) {
                              updates['point'] = newPoint;
                            }

                            final eventDate =
                            DateTime(date.year, date.month, date.day);
                            if (!_isSameDay(eventDate, _dispEventDate)) {
                              updates['event_date'] =
                                  eventDate.toUtc().toIso8601String();
                            }
                            if (startTod != null) {
                              final dt = DateTime(eventDate.year, eventDate.month,
                                  eventDate.day, startTod!.hour, startTod!.minute);
                              updates['starts_at'] = dt.toUtc().toIso8601String();
                            }
                            if (endTod != null) {
                              final dt = DateTime(eventDate.year, eventDate.month,
                                  eventDate.day, endTod!.hour, endTod!.minute);
                              updates['ends_at'] = dt.toUtc().toIso8601String();
                            }

                            if (updates.isEmpty) {
                              await _notify('Bilgi', 'Değişiklik yok.');
                              return;
                            }

                            await supabase
                                .from('events')
                                .update(updates)
                                .eq('id', widget.event.id!);

                            setState(() {
                              if (updates.containsKey('title')) {
                                _ovTitle = updates['title'] as String;
                              }
                              if (updates.containsKey('description')) {
                                _ovDescription = updates['description'] as String;
                              }
                              if (updates.containsKey('location')) {
                                _ovLocation = updates['location'] as String;
                              }
                              if (updates.containsKey('image_url')) {
                                _ovImageUrl = updates['image_url'] as String;
                              }
                              if (updates.containsKey('point')) {
                                _ovPoint = updates['point'] as int;
                              }
                              if (updates.containsKey('event_date')) {
                                _ovEventDate =
                                    DateTime.parse(updates['event_date']).toLocal();
                              }
                              if (updates.containsKey('starts_at')) {
                                _startsAt =
                                    DateTime.parse(updates['starts_at']).toLocal();
                              }
                              if (updates.containsKey('ends_at')) {
                                _endsAt = DateTime.parse(updates['ends_at']).toLocal();
                              }
                            });

                            _calculateTimeLeft();
                            if (mounted) Navigator.pop(ctx);
                            _toast('Etkinlik bilgileri kaydedildi');
                          } catch (e) {
                            _toast('Kaydedilemedi', error: true);
                          }
                        },
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ========================= SUBWIDGETS ========================= */

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.imageUrl});
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = imageUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (url == null || url.isEmpty)
          Container(color: isDark ? const Color(0xFF0B1A33) : kPrimary)
        else
          Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: 1200,
            errorBuilder: (_, __, ___) =>
                Container(color: isDark ? const Color(0xFF0B1A33) : kPrimary),
            loadingBuilder: (c, child, p) =>
            p == null ? child : const Center(child: CircularProgressIndicator()),
          ),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 450),
          builder: (_, v, __) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2 + v * 3, sigmaY: 2 + v * 3),
            child: const SizedBox.expand(),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0x64000000), Color(0x00000000)],
            ),
          ),
        ),
      ],
    );
  }
}

enum PillVariant { normal, muted, success, warn }

/* ====================== NEW DETAIL LAYOUT ====================== */

class SummarySectionPro extends StatelessWidget {
  const SummarySectionPro({
    super.key,
    required this.date,
    required this.timeText,
    required this.location,
    required this.point,
    required this.canCheckin,
    required this.ownerName,
    required this.registered,
    required this.countdownText,
    required this.description,
    this.isPast = false,
  });

  final DateTime date;
  final String timeText, location, countdownText, description;
  final int point, registered;
  final bool canCheckin;
  final String? ownerName;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(kSpace3, kSpace2, kSpace3, 96),
      children: [
        Row(
          children: [
            DateBadgeWide(date: date),
            const SizedBox(height: kSpace3),
            Expanded(child: TimePill(text: timeText)),
          ],
        ),
        const SizedBox(height: kSpace3),

        if (isPast)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 18, color: kPrimary),
                SizedBox(width: 8),
                Flexible(child: Text('Etkinlik tarihi geçti')),
              ],
            ),
          ),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            InfoPill(icon: Icons.location_on, text: location),
            const SizedBox(width: 8),
            if ((ownerName ?? '').isNotEmpty)
              InfoPill(icon: Icons.person, text: ownerName!),
            if ((ownerName ?? '').isNotEmpty) const SizedBox(width: 8),
            InfoPill(icon: Icons.star_border, text: '$point puan'),
            const SizedBox(width: 8),
            InfoPill(
              icon: canCheckin ? Icons.how_to_reg : Icons.lock_clock,
              text: canCheckin ? 'Yoklama Açık' : 'Yoklama Kapalı',
              variant: canCheckin ? PillVariant.success : PillVariant.muted,
            ),
          ]),
        ),
        const SizedBox(height: kSpace3),

        // Basit istatistik kartı: Kayıtlı kişi sayısı + geri sayım
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r16)),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(kSpace3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(r12),
                      ),
                      child: const Icon(Icons.groups_2, color: kPrimary),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Kayıtlı', style: _labelStyle),
                        const SizedBox(height: 4),
                        Text('$registered',
                            style: _valueStyle.copyWith(color: kPrimary, fontSize: 20)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: kSpace2),
                Row(
                  children: [
                    const Icon(Icons.hourglass_bottom, size: 18, color: kPrimary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Kalan: $countdownText',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: kSpace3),

        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r16)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kSpace3, kSpace3, kSpace3, kSpace4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.notes_outlined, color: kPrimary),
                  const SizedBox(width: kSpace2),
                  Text('Açıklama', style: _titleStyle),
                ]),
                const SizedBox(height: kSpace2),
                Text(
                  description.trim().isEmpty ? '—' : description,
                  style: const TextStyle(height: 1.4, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class TimePill extends StatelessWidget {
  const TimePill({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r16),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
              color: Colors.black12.withValues(alpha: .05),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: kPrimary),
          const SizedBox(width: 10),
          Text(text,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}

/* ====================== COMMON UI PARTS ====================== */

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(r16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(r16),
          border: Border.all(color: Colors.white.withValues(alpha: .30)),
        ),
        padding: const EdgeInsets.all(kSpace3),
        child: child,
      ),
    );
  }
}

class DateBadgeWide extends StatelessWidget {
  const DateBadgeWide({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final day = DateFormat('d', 'tr').format(date);
    final mon = DateFormat('MMM', 'tr').format(date).toUpperCase();
    final year = DateFormat('y', 'tr').format(date);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * kUiScale, vertical: 10 * kUiScale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r16),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: .10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(day,
            style: TextStyle(
                fontSize: 30 * kUiScale, fontWeight: FontWeight.w900, color: kPrimary, height: 1)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mon,
              style: TextStyle(
                  letterSpacing: 1.2, fontWeight: FontWeight.w700, fontSize: 13 * kUiScale)),
          Text(year, style: TextStyle(color: Colors.grey.shade700, fontSize: 12 * kUiScale)),
        ]),
      ]),
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill(
      {super.key, required this.icon, required this.text, this.variant = PillVariant.normal});

  final IconData icon;
  final String text;
  final PillVariant variant;

  @override
  Widget build(BuildContext context) {
    Color fg = kPrimary;
    switch (variant) {
      case PillVariant.success:
        fg = kOk;
        break;
      case PillVariant.warn:
        fg = kWarn;
        break;
      case PillVariant.muted:
        fg = Colors.grey.shade700;
        break;
      case PillVariant.normal:
      default:
        fg = kPrimary;
        break;
    }
    return Container(
      decoration: BoxDecoration(
        color: fg.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: .20)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 12 * kUiScale,
        vertical: 7 * kUiScale,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18 * kUiScale, color: fg),
        SizedBox(width: 6 * kUiScale),
        Text(text, style: TextStyle(fontSize: 14 * kUiScale)),
      ]),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.softBg = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final bool softBg;

  @override
  Widget build(BuildContext context) {
    final c = valueColor ?? kInk;
    return SizedBox(
      height: 108,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r16)),
        color: softBg ? c.withValues(alpha: .06) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              padding: EdgeInsets.all(9 * kUiScale),
              decoration:
              BoxDecoration(color: c.withValues(alpha: .10), borderRadius: BorderRadius.circular(r12)),
              child: Icon(icon, color: c, size: 20 * kUiScale),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: _labelStyle),
                  const SizedBox(height: 6),
                  Text(value,
                      style: _valueStyle.copyWith(color: c, fontSize: 22 * kUiScale)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class ManageSheet extends StatelessWidget {
  const ManageSheet({
    super.key,
    required this.isAdmin,
    required this.canCheckin,
    required this.onCsv,
    required this.onAllJoin,
    required this.onAllLeave,
    required this.onEdit,
    required this.onDelete,
    this.onCopyPresent,
  });

  final bool isAdmin, canCheckin;
  final VoidCallback onCsv;
  final VoidCallback? onAllJoin, onAllLeave, onCopyPresent;
  final Future<void> Function()? onDelete;
  final Future<void> Function() onEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kSpace3, kSpace2, kSpace3, kSpace3),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            leading: Icon(Icons.tune, color: kPrimary),
            title: Text('Yönetim'),
            subtitle: Text('CSV, yoklama ve düzenleme'),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                  onPressed: onCsv,
                  icon: const Icon(Icons.table_chart),
                  label: const Text('CSV Kopyala')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                  onPressed: onCopyPresent,
                  icon: const Icon(Icons.checklist_rtl),
                  label: const Text('Katılanlar')),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: FilledButton.tonalIcon(
                    onPressed: onAllJoin,
                    icon: const Icon(Icons.task_alt),
                    label: const Text('Hepsi Katıldı'))),
            const SizedBox(width: 8),
            Expanded(
                child: FilledButton.tonalIcon(
                    onPressed: onAllLeave,
                    icon: const Icon(Icons.block),
                    label: const Text('Hepsi Katılmadı'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit),
                    label: const Text('Etkinliği Düzenle'))),
          ]),
          const SizedBox(height: 12),
          if (isAdmin)
            Row(children: [
              Expanded(
                  child: FilledButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Etkinliği Sil'),
                    style: FilledButton.styleFrom(
                        backgroundColor: kWarn.withValues(alpha: .12),
                        foregroundColor: kWarn),
                  )),
            ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              canCheckin
                  ? 'Yoklama açık'
                  : 'Not: Yoklama kapalı (yetkililer yine onay verebilir).',
              style: TextStyle(color: canCheckin ? kOk : Colors.grey),
            ),
          ),
        ]),
      ),
    );
  }
}

class ParticipantsSection extends StatefulWidget {
  const ParticipantsSection({
    super.key,
    required this.participants,
    required this.canCheckin,
    required this.canManage,
    required this.onSearch,
    required this.searchQuery,
    required this.onJoin,
    required this.onLeave,
    required this.onKick,
  });

  final List<Map<String, dynamic>> participants;
  final bool canCheckin, canManage;
  final ValueChanged<String> onSearch;
  final String searchQuery;

  // force param’ını destekleyen callback imzaları
  final Future<void> Function(int regId, int studentId, {bool force}) onJoin;
  final Future<void> Function(int regId, int studentId, {bool force}) onLeave;

  final Future<void> Function(int regId, int studentId) onKick;

  @override
  State<ParticipantsSection> createState() => _ParticipantsSectionState();
}

enum _AttFilter { all, joined, notJoined }

class _ParticipantsSectionState extends State<ParticipantsSection> {
  Timer? _debounce;
  _AttFilter _filter = _AttFilter.all;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = _visible(widget.participants, widget.searchQuery);
    final filtered = base.where((p) {
      if (_filter == _AttFilter.joined) return (p['attendance'] ?? false) == true;
      if (_filter == _AttFilter.notJoined) return (p['attendance'] ?? false) == false;
      return true;
    }).toList();

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kSpace3, 8, kSpace3, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'İsme göre ara…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(r12)),
              ),
              onChanged: (q) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () => widget.onSearch(q));
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Wrap(spacing: 8, children: [
            ChoiceChip(
              label: const Text('Hepsi'),
              selected: _filter == _AttFilter.all,
              onSelected: (_) => setState(() => _filter = _AttFilter.all),
            ),
            ChoiceChip(
              label: const Text('Katılan'),
              selected: _filter == _AttFilter.joined,
              onSelected: (_) => setState(() => _filter = _AttFilter.joined),
            ),
            ChoiceChip(
              label: const Text('Katılmayan'),
              selected: _filter == _AttFilter.notJoined,
              onSelected: (_) => setState(() => _filter = _AttFilter.notJoined),
            ),
          ]),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
              child: Text('Kriterlere uyan katılımcı yok.',
                  style: TextStyle(color: Colors.grey.shade600)))
              : ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final p = filtered[i];
              final name = (p['name'] ?? 'İsimsiz').toString();
              final attended = p['attendance'] ?? false;
              final regId = p['id'] as int;
              final sid = p['studentId'] as int;

              final showManageButtons = widget.canManage;
              final enableButtons = widget.canManage; // kapalı olsa da yetkiliyse aktif

              return Card(
                elevation: .5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r14)),
                child: ListTile(
                  dense: true,
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: kPrimary.withValues(alpha: .10),
                    child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(color: kPrimary)),
                  ),
                  title:
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: SizedBox(
                    width: showManageButtons ? 200 : 130,
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (showManageButtons)
                        IconButton.filledTonal(
                          tooltip: 'Katıldı',
                          icon: const Icon(Icons.check),
                          onPressed: enableButtons && !attended
                              ? () => widget.onJoin(
                            regId,
                            sid,
                            force: !widget.canCheckin && widget.canManage,
                          )
                              : null,
                          style: IconButton.styleFrom(foregroundColor: kOk),
                        )
                      else
                        Icon(attended ? Icons.check_circle : Icons.cancel,
                            color: attended ? kOk : kWarn),
                      const SizedBox(width: 6),
                      if (showManageButtons)
                        IconButton.filledTonal(
                          tooltip: 'Katılmadı',
                          icon: const Icon(Icons.close),
                          onPressed: enableButtons && attended
                              ? () => widget.onLeave(
                            regId,
                            sid,
                            force: !widget.canCheckin && widget.canManage,
                          )
                              : null,
                          style: IconButton.styleFrom(foregroundColor: kWarn),
                        ),
                      if (showManageButtons) ...[
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: 'Katılımcıyı çıkar',
                          icon: const Icon(Icons.person_remove_alt_1),
                          onPressed: () => widget.onKick(regId, sid),
                        ),
                      ]
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle,
                size: 18,
                color: widget.canManage ? kOk : (widget.canCheckin ? kOk : Colors.grey)),
            const SizedBox(width: 6),
            Text('Katıldı',
                style: TextStyle(
                    fontSize: 12,
                    color: widget.canManage
                        ? null
                        : (widget.canCheckin ? null : Colors.grey))),
            const SizedBox(width: 12),
            Icon(Icons.cancel,
                size: 18,
                color:
                widget.canManage ? kWarn : (widget.canCheckin ? kWarn : Colors.grey)),
            const SizedBox(width: 6),
            Text('Katılmadı',
                style: TextStyle(
                    fontSize: 12,
                    color: widget.canManage
                        ? null
                        : (widget.canCheckin ? null : Colors.grey))),
            if (!widget.canCheckin && !widget.canManage)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('(Yoklama kapalı)',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ]),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> list, String q) {
    var l = List<Map<String, dynamic>>.from(list);
    if (q.isNotEmpty) {
      final qq = q.toLowerCase();
      l = l.where((p) => (p['name'] ?? '').toString().toLowerCase().contains(qq)).toList();
    }
    l.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return l;
  }
}

class StudentActionsFab extends StatelessWidget {
  const StudentActionsFab({
    super.key,
    required this.isStudent,
    required this.timeLeft,
    required this.hasApplied,
    required this.canCheckin,
    required this.isEventPassed,
    required this.onApply,
    required this.onCancel,
    required this.onJoin,
    required this.onLeave,
  });

  final bool isStudent, hasApplied, canCheckin, isEventPassed;
  final Duration timeLeft;
  final VoidCallback onApply, onCancel, onJoin, onLeave;

  @override
  Widget build(BuildContext context) {
    if (!isStudent) return const SizedBox.shrink();

    if (timeLeft > Duration.zero && !hasApplied && !isEventPassed) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
                color: kAccent.withValues(alpha: .45),
                blurRadius: 22,
                offset: const Offset(0, 10))
          ],
        ),
        child: FloatingActionButton.extended(
          elevation: 4,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Etkinliğe Başvur'),
          backgroundColor: kAccent,
          foregroundColor: Colors.white,
          onPressed: onApply,
        ),
      );
    }

    if (hasApplied && !isEventPassed && !canCheckin) {
      return FloatingActionButton.extended(
        icon: const Icon(Icons.cancel_schedule_send),
        label: const Text('Başvuruyu İptal Et'),
        backgroundColor: kWarn,
        foregroundColor: Colors.white,
        onPressed: onCancel,
      );
    }

    if (hasApplied && canCheckin) {
      return Wrap(
        spacing: 8,
        children: [
          FloatingActionButton.extended(
            heroTag: 'join',
            icon: const Icon(Icons.how_to_reg),
            label: const Text('Katıl'),
            backgroundColor: kOk,
            foregroundColor: Colors.white,
            onPressed: onJoin,
          ),
          FloatingActionButton.extended(
            heroTag: 'leave',
            icon: const Icon(Icons.logout),
            label: const Text('Ayrıl'),
            backgroundColor: Colors.grey.shade800,
            foregroundColor: Colors.white,
            onPressed: onLeave,
          ),
        ],
      );
    }

    if (hasApplied) {
      return FloatingActionButton.extended(
        icon: const Icon(Icons.info_outline),
        label: const Text('Başvurunuz alındı'),
        onPressed: () {},
      );
    }

    return const SizedBox.shrink();
  }
}

/* ====================== SKELETON ====================== */

class _SkeletonDetail extends StatelessWidget {
  const _SkeletonDetail();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _SkelBox(h: 84, w: 180, r: 16),
        _SkelBox(h: 64, w: 260, r: 16),
        SizedBox(height: 12),
        _SkelBox(h: 110, r: 16),
        SizedBox(height: 12),
        _SkelBox(h: 140, r: 16),
      ],
    );
  }
}

class _SkelBox extends StatelessWidget {
  const _SkelBox({this.h = 16, this.w = double.infinity, this.r = 12});
  final double h, w, r;
  @override
  Widget build(BuildContext c) => Container(
    height: h,
    width: w,
    margin: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black12.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(r),
    ),
  );
}
