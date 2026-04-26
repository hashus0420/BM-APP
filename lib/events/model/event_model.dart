// ignore_for_file: public_member_api_docs

/// Küçük yardımcı: dynamic -> DateTime?
DateTime? _toDateTime(dynamic v, {bool toLocal = true}) {
  if (v == null) return null;
  if (v is DateTime) return toLocal ? v.toLocal() : v;
  final s = v.toString();
  final dt = DateTime.tryParse(s);
  return dt == null ? null : (toLocal ? dt.toLocal() : dt);
}

class EventModel {
  // ---- Eski alanlar (uygulaman mevcut UI ile uyumlu) ----
  final int? id; // insert sırasında null olabilir
  final String title;
  final String category;
  final String description;
  final String location;
  final DateTime eventDate;                 // DB: event_date (DATE)
  final DateTime? applicationDeadline;      // DB: application_deadline (TIMESTAMP?)
  final int point;
  final int quota;
  final int? createdBy;                     // DB: created_by
  final DateTime? createdAt;                // DB: created_at
  final String? imageUrl;                   // opsiyonel kolon
  final String? eventType;                  // opsiyonel kolon

  // ---- Yeni alanlar (tekrarlayan etkinlik ve yoklama akışı için) ----
  final String? seriesId;                   // DB: series_id (uuid)
  final DateTime? startsAt;                 // DB: starts_at (timestamptz)
  final DateTime? endsAt;                   // DB: ends_at (timestamptz)
  final String? status;                     // draft|published|completed|cancelled
  final String? contactName;                // DB: contact_name
  final String? contactEmail;               // DB: contact_email
  final String? ownerName;                  // view: owner_name
  final String? ownerEmail;                 // view: owner_email

  const EventModel({
    // eski
    this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.location,
    required this.eventDate,
    this.applicationDeadline,
    required this.point,
    required this.quota,
    this.createdBy,
    this.createdAt,
    this.imageUrl,
    this.eventType,
    // yeni
    this.seriesId,
    this.startsAt,
    this.endsAt,
    this.status,
    this.contactName,
    this.contactEmail,
    this.ownerName,
    this.ownerEmail,
  });

  /// Her iki dünyadan (doğrudan tablo select'i ya da RPC/view) gelen map'i
  /// akıllıca yorumlar. Alan yoksa default’lar korunur.
  factory EventModel.fromMap(Map<String, dynamic> m) {
    // eventDate’i önce event_date (DATE) sonra starts_at’tan türet
    final rawEventDate = m['event_date'] ?? m['eventDate'] ?? m['start_at'] ?? m['starts_at'];
    final evDate = _toDateTime(rawEventDate)?.toLocal() ?? DateTime.now();

    return EventModel(
      id: (m['id'] as num?)?.toInt(),
      title: (m['title'] ?? '').toString(),
      category: (m['category'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      location: (m['location'] ?? '').toString(),
      eventDate: evDate,
      applicationDeadline: _toDateTime(m['application_deadline']),
      point: (m['point'] as num?)?.toInt() ?? 0,
      quota: (m['quota'] as num?)?.toInt() ?? 0,
      createdBy: (m['created_by'] as num?)?.toInt(),
      createdAt: _toDateTime(m['created_at']),
      imageUrl: m['image_url'] as String?,
      eventType: m['event_type'] as String?,
      // yeni alanlar
      seriesId: m['series_id']?.toString(),
      startsAt: _toDateTime(m['starts_at']),
      endsAt: _toDateTime(m['ends_at']),
      status: m['status']?.toString(),
      contactName: m['contact_name']?.toString(),
      contactEmail: m['contact_email']?.toString(),
      ownerName: m['owner_name']?.toString(),
      ownerEmail: m['owner_email']?.toString(),
    );
  }

  /// List helper
  static List<EventModel> listFrom(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data
          .map((e) => EventModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return [];
  }

  /// Doğrudan tabloya insert eden akış için (geriye dönük).
  /// Not: starts/ends/status gibi yeni alanlar RPC ile set edilmeli.
  Map<String, dynamic> toInsertMap() {
    return <String, dynamic>{
      'title': title,
      'category': category,
      'description': description,
      'location': location,
      'event_date': eventDate.toIso8601String(),
      if (applicationDeadline != null)
        'application_deadline': applicationDeadline!.toIso8601String(),
      'point': point,
      'quota': quota,
      if (createdBy != null) 'created_by': createdBy,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
      if (eventType != null && eventType!.isNotEmpty) 'event_type': eventType,
    };
  }

  EventModel copyWith({
    int? id,
    String? imageUrl,
    String? status,
    DateTime? startsAt,
    DateTime? endsAt,
  }) {
    return EventModel(
      id: id ?? this.id,
      title: title,
      category: category,
      description: description,
      location: location,
      eventDate: eventDate,
      applicationDeadline: applicationDeadline,
      point: point,
      quota: quota,
      createdBy: createdBy,
      createdAt: createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
      eventType: eventType,
      // yeni
      status: status ?? this.status,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      seriesId: seriesId,
      contactName: contactName,
      contactEmail: contactEmail,
      ownerName: ownerName,
      ownerEmail: ownerEmail,
    );
  }
}
