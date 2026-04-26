import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentPointsPage extends StatefulWidget {
  const StudentPointsPage({super.key});

  @override
  State<StudentPointsPage> createState() => _StudentPointsPageState();
}

class _StudentPointsPageState extends State<StudentPointsPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  int? _studentId;
  int _totalPoints = 0;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final sid = prefs.getInt('user_id');
    if (sid == null) {
      setState(() {
        _loading = false;
        _studentId = null;
      });
      return;
    }

    try {
      final total = await supabase
          .from('v_student_total_points')
          .select('total_points')
          .eq('student_id', sid)
          .maybeSingle();

      final list = await supabase
          .from('v_student_points')
          .select('event_title,event_date,is_participated,base_point,extra_point,earned_point')
          .eq('student_id', sid)
          .order('event_date', ascending: false);

      setState(() {
        _studentId = sid;
        _totalPoints = (total?['total_points'] ?? 0) as int;
        _items = List<Map<String, dynamic>>.from(list as List);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Puanlar alınamadı: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM y', 'tr');

    return Scaffold(
      appBar: AppBar(title: const Text('Puanlarım')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.star, color: Colors.teal),
                title: const Text('Toplam Puan'),
                subtitle: Text('$_totalPoints', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Etkinlikler', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              const Text('Henüz etkinlik kaydı bulunmuyor.')
            else
              ..._items.map((r) {
                final date = DateTime.parse(r['event_date'] as String);
                final participated = r['is_participated'] == true;
                final earned = r['earned_point'] as int;
                final base = r['base_point'] as int;
                final extra = r['extra_point'] as int;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.event),
                    title: Text(r['event_title']),
                    subtitle: Text(dateFmt.format(date)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(participated ? 'Katıldı' : 'Katılmadı'),
                        Text('Baz $base  •  Ekstra $extra  •  +$earned',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
