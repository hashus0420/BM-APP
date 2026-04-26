import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/event_model.dart';

class AttendancePage extends StatefulWidget {
  final EventModel event;

  const AttendancePage({super.key, required this.event});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchParticipants();
  }

  Future<void> _fetchParticipants() async {
    setState(() => _isLoading = true);

    try {
      final data = await supabase
          .from('participants')
          .select()
          .eq('event_id', widget.event.id)
          .order('name', ascending: true);

      setState(() {
        _participants = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (error) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Katılımcılar alınamadı: $error')),
      );
    }
  }

  Future<void> _updateAttendance(int participantId, bool present) async {
    try {
      await supabase
          .from('participants')
          .update({'attendance': present})
          .eq('id', participantId);

      await _fetchParticipants(); // Listeyi yenile
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yoklama güncellenemedi: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Yoklama - ${widget.event.title}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _participants.length,
        itemBuilder: (context, index) {
          final participant = _participants[index];
          final bool present = participant['attendance'] ?? false;

          return ListTile(
            title: Text(participant['name'] ?? 'İsimsiz'),
            subtitle: Text(participant['email'] ?? ''),
            trailing: Checkbox(
              value: present,
              onChanged: (value) {
                _updateAttendance(participant['id'], value ?? false);
              },
            ),
          );
        },
      ),
    );
  }
}
