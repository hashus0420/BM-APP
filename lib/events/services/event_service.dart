import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:msret/events/model/event_model.dart';

class EventService {
  EventService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _eventSelectFields = '''
    id, title, category, description, location,
    event_date, application_deadline, point, quota,
    created_by, created_at,
    series_id, starts_at, ends_at, status, contact_name, contact_email
  ''';

  static const String _eventSelectFieldsWithImage = '''
    id, title, category, description, location,
    event_date, application_deadline, point, quota, created_by, created_at,
    series_id, starts_at, ends_at, status, contact_name, contact_email, image_url
  ''';

  // ---------------------------------------------------------------------------
  // 1) Mevcut UI için klasik etkinlik listesi
  // ---------------------------------------------------------------------------
  Future<List<EventModel>> fetchEvents() async {
    final rows = await _supabase
        .from('events')
        .select(_eventSelectFields)
        .order('event_date', ascending: true)
        .limit(1000);

    return (rows as List)
        .where((row) => row['event_date'] != null || row['starts_at'] != null)
        .map(
          (row) => EventModel.fromMap(
        Map<String, dynamic>.from(row as Map),
      ),
    )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // 2) Mevcut form için doğrudan tabloya insert
  // ---------------------------------------------------------------------------
  Future<EventModel?> addEvent(EventModel event) async {
    final payload = event.toInsertMap()
      ..putIfAbsent('point', () => event.point)
      ..putIfAbsent('quota', () => event.quota);

    final row = await _supabase
        .from('events')
        .insert(payload)
        .select(_eventSelectFields)
        .single();

    if (row == null) return null;

    return EventModel.fromMap(
      Map<String, dynamic>.from(row as Map),
    );
  }

  // ---------------------------------------------------------------------------
  // 3) Seri ve gelişmiş etkinlik işlemleri (RPC)
  // ---------------------------------------------------------------------------

  /// Tekrarlayan seri oluşturur.
  ///
  /// Örnek RRULE:
  /// - FREQ=DAILY
  /// - FREQ=WEEKLY;BYDAY=MO
  Future<String> createSeries({
    required int requesterId,
    required String title,
    String? description,
    required String rrule,
    String timezone = 'Europe/Istanbul',
    int graceHours = 2,
    int? organizerId,
    String? organizerContact,
  }) async {
    final result =
    await _supabase.rpc('create_event_series_int', params: {
      'p_requester_id': requesterId,
      'p_title': title,
      'p_description': description,
      'p_rrule': rrule,
      'p_timezone': timezone,
      'p_grace_hours': graceHours,
      'p_organizer_id': organizerId,
      'p_organizer_contact': organizerContact,
    });

    return result as String;
  }

  /// Seriye bağlı ilk veya yeni bir etkinlik oluşturur.
  Future<int> createEventAdvanced({
    required int requesterId,
    required String seriesId,
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String status = 'published',
  }) async {
    final result = await _supabase.rpc('create_event_int', params: {
      'p_requester_id': requesterId,
      'p_series_id': seriesId,
      'p_title': title,
      'p_description': description,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
      'p_location': location,
      'p_status': status,
    });

    return (result as num).toInt();
  }

  /// Etkinliği sadece sahibi veya admin güncelleyebilir.
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
    await _supabase.rpc('update_event_owner_only_int', params: {
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
  // 4) Rol bazlı listeleme
  // ---------------------------------------------------------------------------

  /// Öğretmen: yalnız kendi oluşturduğu etkinlikleri/serileri görür.
  Future<List<EventModel>> listForTeacher({
    required int teacherId,
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    final result =
    await _supabase.rpc('list_events_for_teacher_int', params: {
      'p_teacher_id': teacherId,
      'p_from': from?.toUtc().toIso8601String(),
      'p_to': to?.toUtc().toIso8601String(),
      'p_status': status,
    }) as List<dynamic>;

    return EventModel.listFrom(result);
  }

  /// Admin: tüm etkinlikleri görür.
  Future<List<EventModel>> listForAdmin({
    required int adminId,
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    final result = await _supabase.rpc('list_events_for_admin_int', params: {
      'p_admin_id': adminId,
      'p_from': from?.toUtc().toIso8601String(),
      'p_to': to?.toUtc().toIso8601String(),
      'p_status': status,
    }) as List<dynamic>;

    return EventModel.listFrom(result);
  }

  /// Öğrenci: yalnız yayımlanmış etkinlikleri görür.
  Future<List<EventModel>> listPublished({
    DateTime? from,
    DateTime? to,
  }) async {
    final result = await _supabase.rpc('list_published_events', params: {
      'p_from': from?.toUtc().toIso8601String(),
      'p_to': to?.toUtc().toIso8601String(),
    }) as List<dynamic>;

    return EventModel.listFrom(result);
  }

  // ---------------------------------------------------------------------------
  // 5) Yoklama / katılım işlemleri
  // ---------------------------------------------------------------------------

  Future<void> joinEvent({
    required int userId,
    required int eventId,
  }) async {
    await _supabase.rpc('join_event_int', params: {
      'p_user_id': userId,
      'p_event': eventId,
    });
  }

  Future<void> leaveEvent({
    required int userId,
    required int eventId,
  }) async {
    await _supabase.rpc('leave_event_int', params: {
      'p_user_id': userId,
      'p_event': eventId,
    });
  }

  Future<bool> canCheckin(int eventId) async {
    final result = await _supabase.rpc('can_checkin_int', params: {
      'p_event': eventId,
    });

    return (result as bool?) ?? false;
  }

  // ---------------------------------------------------------------------------
  // 6) Etkinlik görseli yükleme
  // ---------------------------------------------------------------------------

  Future<String> uploadEventImage(File file) async {
    final path = 'events/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _supabase.storage.from('event-images').upload(path, file);

    return _supabase.storage.from('event-images').getPublicUrl(path);
  }
}