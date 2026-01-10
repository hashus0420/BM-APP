// lib/services/notification_service.dart
import 'dart:math';
import 'package:flutter/material.dart';            // TimeOfDay için
import 'package:flutter/services.dart';            // PlatformException için
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Uygulama genelinde kullanılacak bildirim servisi.
/// Plugin: flutter_local_notifications ^19.x
class NotificationService {
  NotificationService._();
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;

  final FlutterLocalNotificationsPlugin _fln =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Kurulum – main() içinde çağırın (ama defalarca çağrılsa da sorun yok).
  Future<void> init() async {
    if (_initialized) return;

    // TZ setup
    try {
      tzdata.initializeTimeZones();
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _fln.initialize(initSettings);

    // Android 13+ bildirim izni
    await _fln
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Basit hemen göster
  Future<void> showNow({
    int? id,
    required String title,
    required String body,
    String? payload,
    Importance importance = Importance.high,
    Priority priority = Priority.high,
  }) async {
    await init();

    final nid = id ?? _randomId();

    final androidDetails = AndroidNotificationDetails(
      'msret_default',
      'Genel',
      channelDescription: 'Genel bildirim kanalı',
      importance: importance,
      priority: priority,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _fln.show(nid, title, body, details, payload: payload);
  }

  /// 1. YÖNTEM: Tek **positional** argümanla tarih ver (çağıran dosyada `scheduleAt(someDate)` şeklinde).
  /// activities_page.dart’taki çağrıyla birebir uyumlu olsun diye bu imza kullanılıyor.
  Future<void> scheduleAt(
      dynamic whenOrEvent, {
        int? id,
        required String title,
        required String body,
        String? payload,
        bool allowWhileIdle = true,
      }) async {
    await init();

    // Girilen değer DateTime değilse, event benzeri bir objeden alan adıyla çekmeye çalış.
    DateTime? when;
    if (whenOrEvent is DateTime) {
      when = whenOrEvent;
    } else {
      try {
        // EventModel gibi bir obje ise "eventDate" alanını kullanmayı dene
        final dynamic v = whenOrEvent;
        final maybe = v?.eventDate;
        if (maybe is DateTime) when = maybe;
      } catch (_) {}
    }
    when ??= DateTime.now().add(const Duration(seconds: 5));

    final tzTime = tz.TZDateTime.from(when, tz.local);

    final nid = id ?? _randomId();

    final androidDetails = AndroidNotificationDetails(
      'msret_scheduled',
      'Zamanlı',
      channelDescription: 'Zamanlanmış bildirim kanalı',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Android 13+ EXact Alarm izni yoksa "exact" mod hata fırlatır.
    // Önce exact dene; PlatformException gelirse inexact’e düş.
    try {
      await _fln.zonedSchedule(
        nid,
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
      // exact_alarms_not_permitted -> inexact’e düş
      if (e.code == 'exact_alarms_not_permitted') {
        await _fln.zonedSchedule(
          nid,
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

  /// Her gün belirli saatte (ör. 08:30) – TimeOfDay kullanır
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    String? payload,
  }) async {
    await init();

    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    var tzFirst = tz.TZDateTime.from(first, tz.local);
    if (tzFirst.isBefore(tz.TZDateTime.now(tz.local))) {
      tzFirst = tzFirst.add(const Duration(days: 1));
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'msret_daily',
        'Günlük',
        channelDescription: 'Günlük tekrarlar',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await _fln.zonedSchedule(
      id,
      title,
      body,
      tzFirst,
      details,
      androidScheduleMode: AndroidScheduleMode.inexact,
      matchDateTimeComponents: DateTimeComponents.time, // her gün aynı saat
      payload: payload,
    );
  }

  Future<void> cancel(int id) async {
    await _fln.cancel(id);
  }

  Future<void> cancelAll() async {
    await _fln.cancelAll();
  }

  int _randomId() => Random().nextInt(0x7FFFFFFF);
}