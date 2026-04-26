import 'package:flutter/material.dart';
import '../../models/event_model.dart';
import 'event_detail_page.dart';
import '../../services/event_service.dart';

class EventPage extends StatefulWidget {
  final String userRole;

  const EventPage({super.key, required this.userRole});

  @override
  _EventPageState createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  List<EventModel> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    loadEvents();
  }

  Future<void> loadEvents() async {
    final service = EventService();
    final data = await service.fetchEvents();
    setState(() {
      _events = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Etkinlikler')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          return ListTile(

            title: Text(event.title),

            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EventDetailPage(event: event)),
            ),
          );
        },
      ),
    );
  }
}

