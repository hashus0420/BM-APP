// lib/services/points_client.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class PointsClient {
  final SupabaseClient _sb = Supabase.instance.client;

  /// History'ye delta (+/-) kayıt at
  Future<void> addDelta({
    required int studentId,
    required int eventId,
    required int delta,
  }) async {
    await _sb.from('points_history').insert({
      'student_id': studentId,
      'event_id': eventId,
      'total_point': delta,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Öğrencinin toplam puanı (client tarafında toplayarak)
  Future<int> fetchTotalPoint(int studentId) async {
    final data = await _sb
        .from('points_history')
        .select('total_point')
        .eq('student_id', studentId);

    int sum = 0;
    for (final row in (data as List)) {
      sum += (row['total_point'] ?? 0) as int;
    }
    return sum;
  }
}
