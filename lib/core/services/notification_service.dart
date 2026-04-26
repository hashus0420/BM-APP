// lib/core/services/notification_service.dart

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Uygulama genelinde kullanılacak gelişmiş bildirim servisi.
class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();

  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _fln =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// SettingsPage ile aynı key'ler.
  static const String prefNotifEnabled = 'notif_enabled';
  static const String prefQuietEnabled = 'quiet_enabled';
  static const String prefQuietFrom = 'quiet_from';
  static const String prefQuietTo = 'quiet_to';
  static const String prefDailySummary = 'daily_summary_enabled';
  static const String prefDailyTime = 'daily_summary_time';

  /// Sabit notification id'leri.
  static const int dailySummaryId = 900001;

  /// Notification kanalları.
  static const String channelDefault = 'msret_default';
  static const String channelScheduled = 'msret_scheduled';
  static const String channelDaily = 'msret_daily';
  static const String channelEvent = 'msret_event';

  /// Servis kurulumu.
  Future<void> init() async {
    if (_initialized) return;

    try {
      tzdata.initializeTimeZones();
    } catch (_) {
      // Timezone zaten initialize edilmiş olabilir.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _fln.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('Notification payload: ${response.payload}');
      },
    );

    await _requestPermissions();

    _initialized = true;
  }

  /// Android/iOS bildirim izinlerini ister.
  Future<void> _requestPermissions() async {
    await _fln
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _fln
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// Kullanıcı bildirimleri kapattı mı?
  Future<bool> _isNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefNotifEnabled) ?? true;
  }

  /// Sessiz saat aktif mi?
  Future<bool> _isQuietTimeNow() async {
    final prefs = await SharedPreferences.getInstance();

    final enabled = prefs.getBool(prefQuietEnabled) ?? false;
    if (!enabled) return false;

    final fromText = prefs.getString(prefQuietFrom) ?? '22:00';
    final toText = prefs.getString(prefQuietTo) ?? '07:00';

    final from = _parseTime(fromText) ?? const TimeOfDay(hour: 22, minute: 0);
    final to = _parseTime(toText) ?? const TimeOfDay(hour: 7, minute: 0);
    final now = TimeOfDay.now();

    final nowMin = now.hour * 60 + now.minute;
    final fromMin = from.hour * 60 + from.minute;
    final toMin = to.hour * 60 + to.minute;

    /// Örnek: 22:00 - 07:00 gibi gece aralığı.
    if (fromMin > toMin) {
      return nowMin >= fromMin || nowMin <= toMin;
    }

    /// Örnek: 13:00 - 15:00 gibi aynı gün aralığı.
    return nowMin >= fromMin && nowMin <= toMin;
  }

  TimeOfDay? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);

    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;

    return TimeOfDay(hour: h, minute: m);
  }

  String _timeToString(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  int _randomId() => Random().nextInt(0x7FFFFFFF);

  NotificationDetails _details({
    required String channelId,
    required String channelName,
    required String channelDescription,
    Importance importance = Importance.high,
    Priority priority = Priority.high,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: importance,
        priority: priority,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  /// Hemen bildirim gösterir.
  Future<void> showNow({
    int? id,
    required String title,
    required String body,
    String? payload,
    bool respectQuietHours = true,
    Importance importance = Importance.high,
    Priority priority = Priority.high,
  }) async {
    await init();

    if (!await _isNotificationEnabled()) return;

    if (respectQuietHours && await _isQuietTimeNow()) {
      debugPrint('Bildirim sessiz saat nedeniyle gösterilmedi.');
      return;
    }

    await _fln.show(
      id ?? _randomId(),
      title,
      body,
      _details(
        channelId: channelDefault,
        channelName: 'Genel',
        channelDescription: 'Genel bildirim kanalı',
        importance: importance,
        priority: priority,
      ),
      payload: payload,
    );
  }

  /// Belirli bir tarihte bildirim planlar.
  Future<void> scheduleAt(
      dynamic whenOrEvent, {
        int? id,
        required String title,
        required String body,
        String? payload,
        bool allowWhileIdle = true,
        bool skipIfPast = true,
      }) async {
    await init();

    if (!await _isNotificationEnabled()) return;

    DateTime? when;

    if (whenOrEvent is DateTime) {
      when = whenOrEvent;
    } else {
      try {
        final dynamic v = whenOrEvent;
        final maybe = v?.eventDate;
        if (maybe is DateTime) when = maybe;
      } catch (_) {}
    }

    if (when == null) return;

    if (skipIfPast && when.isBefore(DateTime.now())) {
      debugPrint('Geçmiş tarihli bildirim planlanmadı: $when');
      return;
    }

    final tzTime = tz.TZDateTime.from(when, tz.local);

    final details = _details(
      channelId: channelScheduled,
      channelName: 'Zamanlı',
      channelDescription: 'Zamanlanmış bildirim kanalı',
    );

    try {
      await _fln.zonedSchedule(
        id ?? _randomId(),
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: allowWhileIdle
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.exact,
        payload: payload,
      );
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        await _fln.zonedSchedule(
          id ?? _randomId(),
          title,
          body,
          tzTime,
          details,
          androidScheduleMode: AndroidScheduleMode.inexact,
          payload: payload,
        );
      } else {
        rethrow;
      }
    }
  }

  /// Etkinlik için otomatik hatırlatma oluşturur.
  Future<void> scheduleEventReminder({
    required int eventId,
    required String eventTitle,
    required DateTime eventDate,
    Duration before = const Duration(minutes: 30),
    String? location,
  }) async {
    final reminderTime = eventDate.subtract(before);

    final minutes = before.inMinutes;

    final body = location == null || location.trim().isEmpty
        ? '$eventTitle etkinliği $minutes dakika sonra başlıyor.'
        : '$eventTitle etkinliği $minutes dakika sonra başlıyor. Yer: $location';

    await scheduleAt(
      reminderTime,
      id: eventId,
      title: 'Etkinlik Hatırlatması',
      body: body,
      payload: 'event:$eventId',
    );
  }

  /// Etkinlik için birden fazla hatırlatma kurar.
  Future<void> scheduleEventReminderPack({
    required int eventId,
    required String eventTitle,
    required DateTime eventDate,
    String? location,
  }) async {
    await scheduleEventReminder(
      eventId: eventId * 10 + 1,
      eventTitle: eventTitle,
      eventDate: eventDate,
      before: const Duration(days: 1),
      location: location,
    );

    await scheduleEventReminder(
      eventId: eventId * 10 + 2,
      eventTitle: eventTitle,
      eventDate: eventDate,
      before: const Duration(hours: 1),
      location: location,
    );

    await scheduleEventReminder(
      eventId: eventId * 10 + 3,
      eventTitle: eventTitle,
      eventDate: eventDate,
      before: const Duration(minutes: 30),
      location: location,
    );
  }

  /// Günlük özet bildirimi kurar.
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    String? payload,
  }) async {
    await init();

    if (!await _isNotificationEnabled()) return;

    final now = DateTime.now();

    final first = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    var tzFirst = tz.TZDateTime.from(first, tz.local);

    if (tzFirst.isBefore(tz.TZDateTime.now(tz.local))) {
      tzFirst = tzFirst.add(const Duration(days: 1));
    }

    await _fln.zonedSchedule(
      id,
      title,
      body,
      tzFirst,
      _details(
        channelId: channelDaily,
        channelName: 'Günlük',
        channelDescription: 'Günlük tekrar eden bildirimler',
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  /// SettingsPage'deki günlük özet ayarına göre günlük bildirim kurar veya iptal eder.
  Future<void> syncDailySummary({
    String title = 'Günlük Etkinlik Özeti',
    String body = 'Bugünkü etkinlikleri kontrol etmeyi unutma.',
  }) async {
    await init();

    final prefs = await SharedPreferences.getInstance();

    final enabled = prefs.getBool(prefDailySummary) ?? false;
    final timeText = prefs.getString(prefDailyTime) ?? '08:00';
    final time = _parseTime(timeText) ?? const TimeOfDay(hour: 8, minute: 0);

    await cancel(dailySummaryId);

    if (!enabled) return;

    await scheduleDaily(
      id: dailySummaryId,
      title: title,
      body: body,
      time: time,
      payload: 'daily_summary',
    );
  }

  /// Bildirim ayarlarını dışarıdan güncellemek için.
  Future<void> setNotificationEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefNotifEnabled, value);

    if (!value) {
      await cancelAll();
    }
  }

  /// Sessiz saat ayarını kaydeder.
  Future<void> setQuietHours({
    required bool enabled,
    required TimeOfDay from,
    required TimeOfDay to,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(prefQuietEnabled, enabled);
    await prefs.setString(prefQuietFrom, _timeToString(from));
    await prefs.setString(prefQuietTo, _timeToString(to));
  }

  /// Günlük özet ayarını kaydeder ve bildirimi senkronize eder.
  Future<void> setDailySummary({
    required bool enabled,
    required TimeOfDay time,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(prefDailySummary, enabled);
    await prefs.setString(prefDailyTime, _timeToString(time));

    await syncDailySummary();
  }

  Future<List<PendingNotificationRequest>> pendingNotifications() async {
    await init();
    return _fln.pendingNotificationRequests();
  }

  Future<void> cancel(int id) async {
    await init();
    await _fln.cancel(id);
  }

  Future<void> cancelEventReminders(int eventId) async {
    await cancel(eventId * 10 + 1);
    await cancel(eventId * 10 + 2);
    await cancel(eventId * 10 + 3);
  }

  Future<void> cancelAll() async {
    await init();
    await _fln.cancelAll();
  }
}