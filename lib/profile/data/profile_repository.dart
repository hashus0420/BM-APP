import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String safeText(dynamic value, {String fallback = '-'}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int? tryParseInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value');
}

DateTime? tryParseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

class ProfileData {
  final int? id;
  final String name;
  final String role;
  final String studentClass;
  final int totalPoint;
  final String? email;
  final String username;
  final String? gender;

  const ProfileData({
    required this.id,
    required this.name,
    required this.role,
    required this.studentClass,
    required this.totalPoint,
    this.email,
    this.username = '-',
    this.gender,
  });

  ProfileData copyWith({
    int? id,
    String? name,
    String? role,
    String? studentClass,
    int? totalPoint,
    String? email,
    String? username,
    String? gender,
  }) {
    return ProfileData(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      studentClass: studentClass ?? this.studentClass,
      totalPoint: totalPoint ?? this.totalPoint,
      email: email ?? this.email,
      username: username ?? this.username,
      gender: gender ?? this.gender,
    );
  }
}

class AttendedEvent {
  final int eventId;
  final String title;
  final int eventPoint;
  final int earnedPoint;
  final DateTime? date;

  const AttendedEvent({
    required this.eventId,
    required this.title,
    required this.eventPoint,
    required this.earnedPoint,
    required this.date,
  });

  factory AttendedEvent.fromMap(Map<String, dynamic> map, {String? title}) {
    final eventId = tryParseInt(map['event_id']) ?? 0;
    final totalPointRaw = map['total_point'];
    final totalPoint = totalPointRaw is num
        ? totalPointRaw.toInt()
        : int.tryParse('${totalPointRaw ?? 0}') ?? 0;

    return AttendedEvent(
      eventId: eventId,
      title: safeText(title ?? map['title'], fallback: 'Etkinlik'),
      eventPoint: totalPoint,
      earnedPoint: totalPoint,
      date: tryParseDate(map['created_at']),
    );
  }
}

class ApplicationItem {
  final int eventId;
  final String title;
  final String status;
  final DateTime? date;

  const ApplicationItem({
    required this.eventId,
    required this.title,
    required this.status,
    required this.date,
  });

  factory ApplicationItem.fromMap(
      Map<String, dynamic> map, {
        required String eventIdCol,
        String? title,
      }) {
    return ApplicationItem(
      eventId: tryParseInt(map[eventIdCol]) ?? 0,
      title: safeText(title ?? map['title'], fallback: 'Etkinlik'),
      status: safeText(map['status'], fallback: 'pending'),
      date: tryParseDate(map['created_at']),
    );
  }
}

class ProfileRepository {
  final SupabaseClient sb;

  ProfileRepository(this.sb);

  static const ProfileData emptyProfile = ProfileData(
    id: null,
    name: 'Ad yok',
    role: 'student',
    studentClass: 'Sınıf yok',
    totalPoint: 0,
    email: null,
    username: '-',
    gender: null,
  );

  Future<void> saveUserMeta({
    int? id,
    String? email,
    String? gender,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (id != null) await prefs.setInt('user_id', id);
    if ((email ?? '').isNotEmpty) await prefs.setString('email', email!);
    if ((gender ?? '').isNotEmpty) await prefs.setString('gender', gender!);
  }

  Future<Map<String, dynamic>?> _findUserRow({
    int? userId,
    String? username,
    String? email,
    String? authId,
  }) async {
    Map<String, dynamic>? row;

    if (userId != null) {
      try {
        row = await sb
            .from('users')
            .select('id, name, role, class, email, username, auth_id, gender')
            .eq('id', userId)
            .maybeSingle();
        if (row != null) return row;
      } catch (_) {}
    }

    if ((username ?? '').trim().isNotEmpty) {
      try {
        row = await sb
            .from('users')
            .select('id, name, role, class, email, username, auth_id, gender')
            .ilike('username', username!.trim())
            .maybeSingle();
        if (row != null) return row;
      } catch (_) {}
    }

    if ((email ?? '').trim().isNotEmpty) {
      try {
        row = await sb
            .from('users')
            .select('id, name, role, class, email, username, auth_id, gender')
            .eq('email', email!.trim())
            .maybeSingle();
        if (row != null) return row;
      } catch (_) {}
    }

    if ((authId ?? '').trim().isNotEmpty) {
      try {
        row = await sb
            .from('users')
            .select('id, name, role, class, email, username, auth_id, gender')
            .eq('auth_id', authId!)
            .maybeSingle();
        if (row != null) return row;
      } catch (_) {}
    }

    return null;
  }

  Future<
      ({
      ProfileData profile,
      List<AttendedEvent> events,
      List<ApplicationItem> apps
      })> fetchAll({
    String? cachedEmail,
  }) async {
    try {
      final rpcResult = await sb.rpc('get_profile_bundle');

      if (rpcResult is Map<String, dynamic> && rpcResult.isNotEmpty) {
        final profileMap = rpcResult['profile'] as Map<String, dynamic>?;
        final eventMaps =
            (rpcResult['events'] as List?)?.cast<Map<String, dynamic>>() ??
                const [];
        final applicationMaps =
            (rpcResult['applications'] as List?)?.cast<Map<String, dynamic>>() ??
                const [];

        final profile = mapToProfile(profileMap, cachedEmail);
        await saveUserMeta(
          id: profile.id,
          email: profile.email,
          gender: profile.gender,
        );

        final titleById = <int, String>{};
        for (final item in eventMaps) {
          final id = tryParseInt(item['id']);
          if (id != null) {
            titleById[id] = safeText(item['title'], fallback: 'Etkinlik');
          }
        }

        final attended = dedupeAttended(
          eventMaps
              .map(
                (item) => AttendedEvent.fromMap(
              item,
              title: titleById[tryParseInt(item['event_id']) ?? 0],
            ),
          )
              .toList(),
        );

        final apps = dedupeApplications(
          applicationMaps
              .map(
                (item) => ApplicationItem.fromMap(
              item,
              eventIdCol: 'event_id',
              title: titleById[tryParseInt(item['event_id']) ?? 0],
            ),
          )
              .toList(),
        );

        return (profile: profile, events: attended, apps: apps);
      }
    } catch (_) {}

    final profile = await fetchProfile(cachedEmail: cachedEmail);
    final userId = profile.id;

    if (userId == null) {
      return (
      profile: profile,
      events: const <AttendedEvent>[],
      apps: const <ApplicationItem>[],
      );
    }

    final results = await Future.wait([
      fetchAttendedEventsFromPoints(userId, limit: 20, offset: 0),
      fetchActiveApplications(userId, limit: 20, offset: 0),
    ]);

    return (
    profile: profile,
    events: dedupeAttended(results[0] as List<AttendedEvent>),
    apps: dedupeApplications(results[1] as List<ApplicationItem>),
    );
  }

  Future<ProfileData> fetchProfile({String? cachedEmail}) async {
    final prefs = await SharedPreferences.getInstance();

    final prefUserId = prefs.getInt('user_id');
    final prefEmail = prefs.getString('email');
    final prefUsername = prefs.getString('username');
    final prefFullName = prefs.getString('full_name');
    final prefRole = prefs.getString('role');
    final prefClass = prefs.getString('class');
    final prefGender = prefs.getString('gender');

    final authUser = sb.auth.currentUser;
    final authId = authUser?.id;
    final authEmail = authUser?.email;

    final row = await _findUserRow(
      userId: prefUserId,
      username: prefUsername,
      email: prefEmail ?? cachedEmail ?? authEmail,
      authId: authId,
    );

    if (row != null) {
      final profile = mapToProfile(row, prefEmail ?? cachedEmail ?? authEmail);

      int totalPoints = 0;

      try {
        final sum = await sb.rpc(
          'sum_points_for_student',
          params: {'p_student_id': profile.id},
        );
        if (sum is num) totalPoints = sum.toInt();
      } catch (_) {
        try {
          final pointRows = await sb
              .from('points')
              .select('total_point')
              .eq('student_id', profile.id!);

          if (pointRows is List) {
            for (final item in pointRows) {
              final value = item['total_point'];
              if (value is num) {
                totalPoints += value.toInt();
              } else if (value != null) {
                totalPoints += int.tryParse(value.toString()) ?? 0;
              }
            }
          }
        } catch (_) {}
      }

      final finalProfile = profile.copyWith(totalPoint: totalPoints);

      await saveUserMeta(
        id: finalProfile.id,
        email: finalProfile.email,
        gender: finalProfile.gender,
      );

      return finalProfile;
    }

    return ProfileData(
      id: prefUserId,
      name: safeText(prefFullName, fallback: 'Ad yok'),
      role: safeText(prefRole, fallback: 'student'),
      studentClass: safeText(prefClass, fallback: 'Sınıf yok'),
      totalPoint: 0,
      email: prefEmail ?? cachedEmail ?? authEmail,
      username: safeText(prefUsername, fallback: '-'),
      gender: prefGender,
    );
  }

  ProfileData mapToProfile(Map<String, dynamic>? row, String? fallbackEmail) {
    if (row == null) return emptyProfile;

    return ProfileData(
      id: tryParseInt(row['id']),
      name: safeText(row['name'], fallback: 'Ad yok'),
      role: safeText(row['role'], fallback: 'student'),
      studentClass: safeText(row['class'], fallback: 'Sınıf yok'),
      totalPoint: 0,
      email: (row['email'] as String?) ?? fallbackEmail,
      username: safeText(row['username'], fallback: '-'),
      gender: row['gender'] as String?,
    );
  }

  Future<List<AttendedEvent>> fetchAttendedEventsFromPoints(
      int studentId, {
        required int limit,
        required int offset,
      }) async {
    try {
      final pointRowsRaw = await sb
          .from('points')
          .select('event_id, total_point, created_at')
          .eq('student_id', studentId)
          .not('event_id', 'is', null)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      if (pointRowsRaw is! List || pointRowsRaw.isEmpty) return [];

      final pointRows = pointRowsRaw
          .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
          .toList();

      final eventIds = pointRows
          .map<int?>((item) => tryParseInt(item['event_id']))
          .whereType<int>()
          .toSet()
          .toList();

      final titleById = <int, String>{};

      if (eventIds.isNotEmpty) {
        try {
          final events = await sb
              .from('events')
              .select('id, title')
              .inFilter('id', eventIds);

          if (events is List) {
            for (final item in events) {
              final id = tryParseInt(item['id']);
              if (id != null) {
                titleById[id] = safeText(item['title'], fallback: 'Etkinlik');
              }
            }
          }
        } catch (_) {}
      }

      return dedupeAttended(
        pointRows
            .map(
              (item) => AttendedEvent.fromMap(
            item,
            title: titleById[tryParseInt(item['event_id']) ?? 0],
          ),
        )
            .toList(),
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<ApplicationItem>> fetchActiveApplications(
      int studentId, {
        required int limit,
        required int offset,
      }) async {
    Future<List<ApplicationItem>> tryFetch({
      required String table,
      required String eventIdCol,
      String? userIdCol,
      String? statusCol,
      String? createdCol,
      List<String>? activeStatuses,
    }) async {
      try {
        final selectedColumns = [
          eventIdCol,
          if (userIdCol != null) userIdCol,
          if (statusCol != null) statusCol,
          if (createdCol != null) createdCol,
        ].join(', ');

        final query = sb.from(table).select(selectedColumns);

        query.eq(userIdCol ?? 'student_id', studentId);

        if (statusCol != null &&
            activeStatuses != null &&
            activeStatuses.isNotEmpty) {
          query.inFilter(statusCol, activeStatuses);
        }

        if (createdCol != null) {
          query.order(createdCol, ascending: false);
        }

        query.range(offset, offset + limit - 1);

        final rows = await query;
        if (rows is! List || rows.isEmpty) return [];

        final eventIds = rows
            .map<int?>((item) => tryParseInt(item[eventIdCol]))
            .whereType<int>()
            .toSet()
            .toList();

        final titleById = <int, String>{};

        if (eventIds.isNotEmpty) {
          try {
            final events = await sb
                .from('events')
                .select('id, title')
                .inFilter('id', eventIds);

            if (events is List) {
              for (final item in events) {
                final id = tryParseInt(item['id']);
                if (id != null) {
                  titleById[id] = safeText(item['title'], fallback: 'Etkinlik');
                }
              }
            }
          } catch (_) {}
        }

        return dedupeApplications(
          rows
              .map(
                (item) => ApplicationItem.fromMap(
              item,
              eventIdCol: eventIdCol,
              title: titleById[tryParseInt(item[eventIdCol]) ?? 0],
            ),
          )
              .toList(),
        );
      } catch (_) {
        return [];
      }
    }

    final candidates = <Future<List<ApplicationItem>>>[
      tryFetch(
        table: 'event_applications',
        eventIdCol: 'event_id',
        userIdCol: 'student_id',
        statusCol: 'status',
        createdCol: 'created_at',
        activeStatuses: const ['pending', 'approved', 'accepted', 'waiting'],
      ),
      tryFetch(
        table: 'applications',
        eventIdCol: 'event_id',
        userIdCol: 'student_id',
        statusCol: 'status',
        createdCol: 'created_at',
        activeStatuses: const ['pending', 'approved', 'accepted', 'waiting'],
      ),
      tryFetch(
        table: 'registrations',
        eventIdCol: 'event_id',
        userIdCol: 'student_id',
        statusCol: 'status',
        createdCol: 'created_at',
        activeStatuses: const [
          'pending',
          'approved',
          'accepted',
          'waiting',
          'registered',
        ],
      ),
    ];

    for (final future in candidates) {
      final result = await future;
      if (result.isNotEmpty) return result;
    }

    return [];
  }

  List<AttendedEvent> dedupeAttended(List<AttendedEvent> items) {
    final seen = <String>{};
    final result = <AttendedEvent>[];

    for (final item in items) {
      final key = '${item.eventId}_${item.date?.toIso8601String() ?? ''}';
      if (seen.add(key)) {
        result.add(item);
      }
    }

    result.sort((a, b) {
      final aDate = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return result;
  }

  List<ApplicationItem> dedupeApplications(List<ApplicationItem> items) {
    final seen = <String>{};
    final result = <ApplicationItem>[];

    for (final item in items) {
      final key =
          '${item.eventId}_${item.status}_${item.date?.toIso8601String() ?? ''}';
      if (seen.add(key)) {
        result.add(item);
      }
    }

    result.sort((a, b) {
      final aDate = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return result;
  }
}