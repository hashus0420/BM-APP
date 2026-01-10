import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event_model.dart';

class EventService {
  EventService({SupabaseClient? client})
      : _sb = client ?? Supabase.instance.client;

  final SupabaseClient _sb;

  // ---------------------------------------------------------------------------
  // 1) Geriye dönük: Tablodan liste (mevcut UI'nin kullandığı)
  // ---------------------------------------------------------------------------
  Future<List<EventModel>> fetchEvents() async {
    final rows = await _sb
        .from('events')
        .select(
      '''
          id, title, category, description, location,
          event_date, application_deadline, point, quota,
          created_by, created_at,
          series_id, starts_at, ends_at, status, contact_name, contact_email
          ''',
    )
        .order('event_date', ascending: true)
        .limit(1000);

    final list = (rows as List)
        .where((r) => r['event_date'] != null || r['starts_at'] != null)
        .map((r) => EventModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();

    return list;
  }

  // ---------------------------------------------------------------------------
  // 2) Geriye dönük: Doğrudan tabloya insert (mevcut add_event formun için)
  //    Not: DB tarafında point default 0'a çekildi; yine de güvenlik için set ediyoruz.
  // ---------------------------------------------------------------------------
  Future<EventModel?> addEvent(EventModel e) async {
    final payload = e.toInsertMap()
      ..putIfAbsent('point', () => e.point)
      ..putIfAbsent('quota', () => e.quota);

    final row = await _sb
        .from('events')
        .insert(payload)
        .select(
      '''
          id, title, category, description, location,
          event_date, application_deadline, point, quota,
          created_by, created_at,
          series_id, starts_at, ends_at, status, contact_name, contact_email
          ''',
    )
        .single();

    if (row == null) return null;
    return EventModel.fromMap(Map<String, dynamic>.from(row as Map));
  }

  // ---------------------------------------------------------------------------
  // 3) Yeni: Seri & Etkinlik (RPC)  —— tekrarlayan/yayın/tetikler
  // ---------------------------------------------------------------------------

  /// Tekrarlayan seri oluşturur (iCal RRULE: FREQ=WEEKLY;BYDAY=MO ...)
  Future<String> createSeries({
    required int requesterId, // teacher/admin users.id (INT)
    required String title,
    String? description,
    required String rrule,
    String timezone = 'Europe/Istanbul',
    int graceHours = 2,
    int? organizerId, // admin başkası adına açacaksa
    String? organizerContact,
  }) async {
    final res = await _sb.rpc('create_event_series_int', params: {
      'p_requester_id': requesterId,
      'p_title': title,
      'p_description': description,
      'p_rrule': rrule,
      'p_timezone': timezone,
      'p_grace_hours': graceHours,
      'p_organizer_id': organizerId,
      'p_organizer_contact': organizerContact,
    });
    return res as String; // uuid
  }

  /// Seriye bağlı bir etkinlik oluşturur (status: published/draft/...)
  Future<int> createEventAdvanced({
    required int requesterId,
    required String seriesId, // uuid
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String status = 'published',
  }) async {
    final res = await _sb.rpc('create_event_int', params: {
      'p_requester_id': requesterId,
      'p_series_id': seriesId,
      'p_title': title,
      'p_description': description,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
      'p_location': location,
      'p_status': status,
    });

    return (res as num).toInt(); // events.id (int)
  }

  /// Etkinliği sadece sahibi (veya admin) güncelleyebilir
  Future<void> updateEventAdvanced({
    required int requesterId,
    required int eventId,
    String? title,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
    String? location,
    String? status,
  }) async {
    await _sb.rpc('update_event_owner_only_int', params: {
      'p_requester_id': requesterId,
      'p_event': eventId,
      'p_title': title,
      'p_description': description,
      'p_starts_at': startsAt?.toUtc().toIso8601String(),
      'p_ends_at': endsAt?.toUtc().toIso8601String(),
      'p_location': location,
      'p_status': status,
    });
  }

  // ---------------------------------------------------------------------------
  // 4) Listeleme (rol bazlı RPC’ler)
  // ---------------------------------------------------------------------------

  /// Öğretmen: sadece kendi oluşturduklarını/serisini görür
  Future<List<EventModel>> listForTeacher({
    required int teacherId,
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    final res = await _sb.rpc('list_events_for_teacher_int', params: {
      'p_teacher_id': teacherId,
      'p_from': from?.toUtc().toIso8601String(),
      'p_to': to?.toUtc().toIso8601String(),
      'p_status': status,
    }) as List<dynamic>;

    return EventModel.listFrom(res);
  }

  /// Admin: hepsini görür
  Future<List<EventModel>> listForAdmin({
    required int adminId,
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    final res = await _sb.rpc('list_events_for_admin_int', params: {
      'p_admin_id': adminId,
      'p_from': from?.toUtc().toIso8601String(),
      'p_to': to?.toUtc().toIso8601String(),
      'p_status': status,
    }) as List<dynamic>;

    return EventModel.listFrom(res);
  }

  /// Öğrenci: yayımlanmış etkinlikler (opsiyonel tarih aralığı)
  Future<List<EventModel>> listPublished({
    DateTime? from,
    DateTime? to,
  }) async {
    final res = await _sb.rpc('list_published_events', params: {
      'p_from': from?.toUtc().toIso8601String(),
      'p_to': to?.toUtc().toIso8601String(),
    }) as List<dynamic>;

    // RPC kategori/point/quota dönmüyor; bu alanlar null kalır (UI buna hazır olmalı)
    return EventModel.listFrom(res);
  }

  // ---------------------------------------------------------------------------
  // 5) Yoklama (join/leave/canCheckin)
  // ---------------------------------------------------------------------------

  Future<void> joinEvent({
    required int userId,
    required int eventId,
  }) async {
    await _sb.rpc('join_event_int', params: {
      'p_user_id': userId,
      'p_event': eventId,
    });
  }

  Future<void> leaveEvent({
    required int userId,
    required int eventId,
  }) async {
    await _sb.rpc('leave_event_int', params: {
      'p_user_id': userId,
      'p_event': eventId,
    });
  }

  Future<bool> canCheckin(int eventId) async {
    final res = await _sb.rpc('can_checkin_int', params: {
      'p_event': eventId,
    });
    return (res as bool?) ?? false;
  }

  // ---------------------------------------------------------------------------
  // 6) (Varsa) Storage’a görsel yükle – bucket adı: event-images
  // ---------------------------------------------------------------------------
  Future<String> uploadEventImage(File file) async {
    final path = 'events/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _sb.storage.from('event-images').upload(path, file);
    return _sb.storage.from('event-images').getPublicUrl(path);
  }
}
