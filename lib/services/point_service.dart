// lib/services/points_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Puanlar için Supabase tablosu varsayımı:
///   table: points
///   cols : id (uuid), student_id (int?) veya user_id (uuid),
///          point (int), reason (text?), created_at (timestamptz)
///
/// Not: Senin sisteminde öğrenci kimliği int ise (student_id),
/// auth.users ile ilişkili uuid kullanmıyorsan da çalışır.
/// Aşağıdaki metotta iki yolu da destekledim.

class PointsService {
  final _sb = Supabase.instance.client;

  /// Toplam puanı getir.
  /// Eğer `studentId` verilirse student_id=int üzerinden,
  /// verilmezse giriş yapan kullanıcının user_id (uuid) üzerinden toplar.
  Future<int> fetchTotalPoint({int? studentId}) async {
    if (studentId != null) {
      final res = await _sb
          .from('points')
          .select('point')
          .eq('student_id', studentId);

      if (res is List) {
        final total = res.fold<int>(0, (sum, row) => sum + (row['point'] as int? ?? 0));
        return total;
      }
      return 0;
    } else {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        throw StateError('Kullanıcı oturumu yok.');
      }

      final res = await _sb
          .from('points')
          .select('point')
          .eq('user_id', uid);

      if (res is List) {
        final total = res.fold<int>(0, (sum, row) => sum + (row['point'] as int? ?? 0));
        return total;
      }
      return 0;
    }
  }
}
