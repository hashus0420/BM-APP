import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:msret/core/services/notification_service.dart';
import 'package:msret/events/model/event_model.dart';
import 'package:msret/events/pages/add_event_page.dart';
import 'package:msret/events/pages/event_detail_page.dart';
import 'package:msret/events/services/event_service.dart';

/* ======= RENKLER ======= */
const kNavy = Color(0xFF113A7D);
const kSky = Color(0xFF57C3F6);
const kTeal = Color(0xFF00796B);
const kBg = Color(0xFFF7FAFF);
const kInk = Color(0xFF0F1F33);

/* ======= KATEGORİLER ======= */
const _catOrder = <String>['ihl', 'fen', 'sosyal', 'tech', 'sanat'];

const _catTitles = <String, String>{
  'ihl': 'İHL Mesleki Faaliyetler',
  'fen': 'Fen Bilimleri Faaliyetleri',
  'sosyal': 'Sosyal Bilimleri Faaliyetleri',
  'tech': 'Teknolojik Faaliyetler',
  'sanat': 'Sanat, Spor, Sosyal, Kültürel Faaliyetler',
};

Color _catMain(String key) {
  switch (key) {
    case 'ihl':
      return const Color(0xFF113A7D);
    case 'fen':
      return const Color(0xFF00796B);
    case 'sosyal':
      return const Color(0xFF6A1B9A);
    case 'tech':
      return const Color(0xFF1565C0);
    case 'sanat':
      return const Color(0xFFEF6C00);
    default:
      return kNavy;
  }
}

Color _catBg(String key) => _catMain(key).withOpacity(0.10);
Color _catFg(String key) => _catMain(key).withOpacity(0.95);

String _normalizeCategory(String raw) {
  final value = raw.toLowerCase().trim();

  if (value.contains('ihl') || value.contains('meslek')) return 'ihl';
  if (value.contains('fen') ||
      value.contains('fizik') ||
      value.contains('kimya') ||
      value.contains('biyoloji')) {
    return 'fen';
  }
  if (value.contains('sosyal') ||
      value.contains('tarih') ||
      value.contains('coğraf') ||
      value.contains('felse')) {
    return 'sosyal';
  }
  if (value.contains('tekno') ||
      value.contains('yazılım') ||
      value.contains('kod') ||
      value.contains('robot')) {
    return 'tech';
  }
  if (value.contains('spor') ||
      value.contains('sanat') ||
      value.contains('kültür') ||
      value.contains('kultur')) {
    return 'sanat';
  }
  if (value == 'spor') return 'sanat';

  return 'ihl';
}

class ActivitiesPage extends StatefulWidget {
  const ActivitiesPage({super.key});

  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage>
    with SingleTickerProviderStateMixin {
  static final DateFormat _dfList = DateFormat('d MMMM y, HH:mm', 'tr');
  static final DateFormat _dfChipShort = DateFormat('d MMM', 'tr');
  static final DateFormat _dfChipLong = DateFormat('d MMM y', 'tr');

  late TabController _tabController;

  int _tabIndex = 0;

  Map<DateTime, List<EventModel>> _eventsMap = {};
  List<EventModel> _allSorted = [];
  List<EventModel> _cachedUpcoming = [];
  List<EventModel> _cachedPast = [];
  _CacheKey? _lastKey;

  final DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  bool _showAllEvents = true;
  String _searchQuery = '';
  String _role = 'student';
  bool _loading = true;
  String? _loadError;
  Timer? _debounce;

  String _selectedCategory = 'all';
  int? _gradeFilter;
  int? _myGrade;

  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  RangeSelectionMode _rangeSelectionMode = RangeSelectionMode.toggledOff;

  final NotificationService _notif = NotificationService();

  bool get isAdmin => _role == 'admin';
  bool get isTeacher => _role == 'teacher';

  bool get _filtersActive {
    final defaultGrade = _role == 'student' ? _myGrade : null;
    final gradeChanged = _gradeFilter != defaultGrade;
    final categoryChanged = _selectedCategory != 'all';
    return gradeChanged || categoryChanged;
  }

  bool get _dateFilterActive => _rangeStart != null || !_showAllEvents;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() => _tabIndex = _tabController.index);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await _notif.init();
    } catch (_) {}

    await _loadRoleAndGrade();
    await _loadEvents();
  }

  Future<void> _loadRoleAndGrade() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawRole = prefs.getString('role');
      final normalized = (rawRole ?? 'student').trim().toLowerCase();
      final role = const {'admin', 'teacher', 'student'}.contains(normalized)
          ? normalized
          : 'student';

      final classStr = prefs.getString('class') ?? '';
      final match = RegExp(r'(\d{1,2})').firstMatch(classStr);
      final grade = match != null ? int.tryParse(match.group(1)!) : null;

      if (!mounted) return;

      setState(() {
        _role = role;
        _myGrade = grade;
        _gradeFilter = role == 'student' ? grade : null;
      });
    } catch (_) {}
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final events = await EventService().fetchEvents();

      final sorted = List<EventModel>.from(events)
        ..sort((a, b) => a.eventDate.compareTo(b.eventDate));

      final groupedMap = _groupEventsByDate(sorted);

      if (!mounted) return;

      setState(() {
        _allSorted = sorted;
        _eventsMap = groupedMap;
        _loading = false;
      });

      _recomputeIfNeeded(force: true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _loadError = 'Etkinlikler yüklenemedi';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Etkinlik yüklenemedi: $e')),
      );
    }
  }

  DateTime _dayKey(DateTime date) => DateTime(date.year, date.month, date.day);

  Map<DateTime, List<EventModel>> _groupEventsByDate(List<EventModel> events) {
    final grouped = <DateTime, List<EventModel>>{};

    for (final event in events) {
      final key = _dayKey(event.eventDate);
      (grouped[key] ??= []).add(event);
    }

    for (final list in grouped.values) {
      list.sort((a, b) => a.eventDate.compareTo(b.eventDate));
    }

    return grouped;
  }

  List<EventModel> _getEventsForDay(DateTime day) {
    final key = _dayKey(day);
    final events = List<EventModel>.from(_eventsMap[key] ?? const []);
    events.sort((a, b) => a.eventDate.compareTo(b.eventDate));
    return events;
  }

  bool _matchesGrade(EventModel event, int grade) {
    final haystack = [
      event.title,
      event.description,
      event.category,
      event.eventType ?? '',
    ].join(' ').toLowerCase();

    final explicitGrades =
    RegExp(r'grades?\s*[:=]\s*([0-9,\s\-]+)').firstMatch(haystack);

    if (explicitGrades != null) {
      final source = explicitGrades.group(1)!;

      final range = RegExp(r'(\d{1,2})\s*-\s*(\d{1,2})').firstMatch(source);
      if (range != null) {
        final start = int.parse(range.group(1)!);
        final end = int.parse(range.group(2)!);
        if (grade >= start && grade <= end) return true;
      }

      final parts =
      source.split(RegExp(r'[,\s]+')).where((item) => item.isNotEmpty);
      if (parts.contains('$grade')) return true;
    }

    if (RegExp(r'\b$grade\s*\.?\s*sınıf').hasMatch(haystack)) return true;

    final classRange =
    RegExp(r'(\d{1,2})\s*[-–]\s*(\d{1,2})\s*sınıf').firstMatch(haystack);
    if (classRange != null) {
      final start = int.parse(classRange.group(1)!);
      final end = int.parse(classRange.group(2)!);
      if (grade >= start && grade <= end) return true;
    }

    return true;
  }

  List<EventModel> _applyFilters(List<EventModel> base) {
    Iterable<EventModel> filtered = base;

    if (_rangeStart != null && _rangeEnd != null) {
      final from = DateTime(
        _rangeStart!.year,
        _rangeStart!.month,
        _rangeStart!.day,
      );
      final to = DateTime(
        _rangeEnd!.year,
        _rangeEnd!.month,
        _rangeEnd!.day,
        23,
        59,
        59,
      );

      filtered = filtered.where(
            (event) =>
        !event.eventDate.isBefore(from) && !event.eventDate.isAfter(to),
      );
    } else if (!_showAllEvents) {
      filtered = _getEventsForDay(_selectedDay);
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where(
            (event) =>
        event.title.toLowerCase().contains(query) ||
            event.description.toLowerCase().contains(query),
      );
    }

    if (_selectedCategory != 'all') {
      filtered = filtered.where(
            (event) => _normalizeCategory(event.category) == _selectedCategory,
      );
    }

    if (_gradeFilter != null) {
      filtered =
          filtered.where((event) => _matchesGrade(event, _gradeFilter!));
    }

    return filtered.toList(growable: false);
  }

  void _recomputeIfNeeded({bool force = false}) {
    final key = _CacheKey(
      search: _searchQuery.trim().toLowerCase(),
      cat: _selectedCategory,
      grade: _gradeFilter,
      showAll: _showAllEvents,
      selDay: _dayKey(_selectedDay),
      rStart: _rangeStart != null ? _dayKey(_rangeStart!) : null,
      rEnd: _rangeEnd != null ? _dayKey(_rangeEnd!) : null,
      dataLen: _allSorted.length,
      dataStamp: _allSorted.isEmpty
          ? 0
          : _allSorted.first.eventDate.millisecondsSinceEpoch ^
      _allSorted.last.eventDate.millisecondsSinceEpoch,
    );

    if (!force && _lastKey == key) return;
    _lastKey = key;

    final filtered = _applyFilters(_allSorted);
    final now = DateTime.now().subtract(const Duration(hours: 1));

    final upcoming = <EventModel>[];
    final past = <EventModel>[];

    for (final event in filtered) {
      if (event.eventDate.isAfter(now)) {
        upcoming.add(event);
      } else {
        past.add(event);
      }
    }

    upcoming.sort((a, b) => a.eventDate.compareTo(b.eventDate));
    past.sort((a, b) => b.eventDate.compareTo(a.eventDate));

    if (!mounted) return;

    setState(() {
      _cachedUpcoming = upcoming;
      _cachedPast = past;
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
      _recomputeIfNeeded();
    });
  }

  Future<void> _addEvent() async {
    final newEvent = await Navigator.push<EventModel>(
      context,
      MaterialPageRoute(builder: (_) => const AddEventPage()),
    );

    if (newEvent != null && mounted) {
      setState(() {
        _allSorted = List<EventModel>.from(_allSorted)
          ..add(newEvent)
          ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
        _eventsMap = _groupEventsByDate(_allSorted);
      });

      _recomputeIfNeeded(force: true);
    }
  }

  void _showCalendarPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        List<EventModel> eventsLoader(DateTime day) => _getEventsForDay(day);

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Material(
            color: Colors.white,
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                DateTime localFocused = _focusedDay;

                void selectToday() {
                  setLocal(() {
                    _selectedDay = DateTime.now();
                    _rangeStart = null;
                    _rangeEnd = null;
                    _rangeSelectionMode = RangeSelectionMode.toggledOff;
                    _showAllEvents = false;
                    localFocused = _selectedDay;
                  });
                }

                void selectThisWeek() {
                  final now = DateTime.now();
                  final start = now.subtract(Duration(days: now.weekday - 1));
                  final end = start.add(const Duration(days: 6));

                  setLocal(() {
                    _rangeStart = _dayKey(start);
                    _rangeEnd = _dayKey(end);
                    _rangeSelectionMode = RangeSelectionMode.enforced;
                    _showAllEvents = true;
                  });
                }

                void selectThisMonth() {
                  final now = DateTime.now();
                  final start = DateTime(now.year, now.month, 1);
                  final end = DateTime(now.year, now.month + 1, 0);

                  setLocal(() {
                    _rangeStart = _dayKey(start);
                    _rangeEnd = _dayKey(end);
                    _rangeSelectionMode = RangeSelectionMode.enforced;
                    _showAllEvents = true;
                  });
                }

                void clearDateFilterLocal() {
                  setLocal(() {
                    _rangeStart = null;
                    _rangeEnd = null;
                    _rangeSelectionMode = RangeSelectionMode.toggledOff;
                    _showAllEvents = true;
                  });
                }

                return DraggableScrollableSheet(
                  initialChildSize: 0.82,
                  minChildSize: 0.60,
                  maxChildSize: 0.95,
                  expand: false,
                  builder: (ctx, scrollController) {
                    return SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.event_available,
                                  color: kTeal,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Takvimden Seç',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: kTeal,
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: selectToday,
                                  icon: const Icon(
                                    Icons.my_location,
                                    size: 18,
                                  ),
                                  label: const Text('Bugün'),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding:
                            const EdgeInsets.fromLTRB(12, 6, 12, 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('Bu hafta'),
                                  selected: false,
                                  onSelected: (_) => selectThisWeek(),
                                ),
                                ChoiceChip(
                                  label: const Text('Bu ay'),
                                  selected: false,
                                  onSelected: (_) => selectThisMonth(),
                                ),
                                ChoiceChip(
                                  label: const Text('Tüm tarihler'),
                                  selected: _rangeStart == null &&
                                      _rangeEnd == null &&
                                      _showAllEvents,
                                  onSelected: (_) => clearDateFilterLocal(),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                            child: TableCalendar<EventModel>(
                              firstDay: DateTime.utc(2020, 1, 1),
                              lastDay: DateTime.utc(2035, 12, 31),
                              focusedDay: localFocused,
                              selectedDayPredicate: (day) =>
                                  isSameDay(day, _selectedDay),
                              rangeStartDay: _rangeStart,
                              rangeEndDay: _rangeEnd,
                              rangeSelectionMode: _rangeSelectionMode,
                              calendarFormat: CalendarFormat.month,
                              availableCalendarFormats: const {
                                CalendarFormat.month: 'Ay',
                              },
                              sixWeekMonthsEnforced: true,
                              rowHeight: 46,
                              daysOfWeekHeight: 22,
                              eventLoader: eventsLoader,
                              headerStyle: const HeaderStyle(
                                formatButtonVisible: false,
                                titleCentered: true,
                                titleTextStyle: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                                leftChevronIcon: Icon(
                                  Icons.chevron_left,
                                  color: kTeal,
                                ),
                                rightChevronIcon: Icon(
                                  Icons.chevron_right,
                                  color: kTeal,
                                ),
                              ),
                              calendarStyle: CalendarStyle(
                                todayDecoration: const BoxDecoration(
                                  color: kTeal,
                                  shape: BoxShape.circle,
                                ),
                                selectedDecoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                rangeStartDecoration: BoxDecoration(
                                  color: kTeal.withOpacity(0.90),
                                  shape: BoxShape.circle,
                                ),
                                rangeEndDecoration: BoxDecoration(
                                  color: kTeal.withOpacity(0.90),
                                  shape: BoxShape.circle,
                                ),
                                withinRangeDecoration: BoxDecoration(
                                  color: kTeal.withOpacity(0.18),
                                  shape: BoxShape.circle,
                                ),
                                todayTextStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                selectedTextStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                defaultTextStyle:
                                const TextStyle(fontSize: 14),
                                weekendTextStyle:
                                const TextStyle(fontSize: 14),
                                outsideDaysVisible: false,
                                markersAlignment: Alignment.bottomCenter,
                                markersOffset:
                                const PositionedOffset(bottom: 4),
                              ),
                              calendarBuilders:
                              CalendarBuilders<EventModel>(
                                markerBuilder: (context, day, events) {
                                  if (events.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  final dotCount = events.length > 3
                                      ? 3
                                      : events.length;

                                  return Padding(
                                    padding:
                                    const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.center,
                                      children: List.generate(
                                        dotCount,
                                            (_) => Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 1,
                                          ),
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            color: kTeal.withOpacity(0.90),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              onDaySelected: (selectedDay, focusedDay) {
                                setState(() {
                                  _selectedDay = selectedDay;
                                  localFocused = focusedDay;
                                  _rangeStart = null;
                                  _rangeEnd = null;
                                  _rangeSelectionMode =
                                      RangeSelectionMode.toggledOff;
                                  _showAllEvents = false;
                                });
                                _recomputeIfNeeded();
                              },
                              onRangeSelected:
                                  (start, end, focusedDay) {
                                setState(() {
                                  _selectedDay = focusedDay;
                                  localFocused = focusedDay;
                                  _rangeStart =
                                  start != null ? _dayKey(start) : null;
                                  _rangeEnd =
                                  end != null ? _dayKey(end) : null;
                                  _rangeSelectionMode =
                                      RangeSelectionMode.toggledOn;
                                  _showAllEvents = true;
                                });
                                _recomputeIfNeeded();
                              },
                              onPageChanged: (focusedDay) {
                                setLocal(() => localFocused = focusedDay);
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        clearDateFilterLocal();
                                        Navigator.pop(context);
                                        setState(() {});
                                        _recomputeIfNeeded();
                                      },
                                      icon: const Icon(
                                        Icons.clear,
                                        color: kTeal,
                                      ),
                                      label: const Text(
                                        'Tarihi Temizle',
                                        style: TextStyle(color: kTeal),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side:
                                        const BorderSide(color: kTeal),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(12),
                                        ),
                                        padding:
                                        const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _recomputeIfNeeded();
                                      },
                                      icon: const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                      ),
                                      label: const Text('Uygula'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kTeal,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(12),
                                        ),
                                        padding:
                                        const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openFilterSheet() {
    String tempCat = _selectedCategory;
    int? tempGrade = _gradeFilter;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: Material(
            color: Colors.white,
            child: StatefulBuilder(
              builder: (context, setLocal) {
                Widget categoryChip(String key) {
                  final selected = tempCat == key;

                  return ChoiceChip(
                    selected: selected,
                    label: Text(
                      _catTitles[key]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selectedColor: _catMain(key),
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : kInk,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(color: _catBg(key)),
                    onSelected: (_) => setLocal(() => tempCat = key),
                  );
                }

                Widget gradeChip(int? grade) {
                  final selected =
                      tempGrade == grade ||
                          (tempGrade == null && grade == null);
                  final label = grade == null ? 'Tümü' : '$grade. Sınıf';

                  return ChoiceChip(
                    selected: selected,
                    label: Text(label),
                    selectedColor: kSky,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : kInk,
                      fontWeight: FontWeight.w700,
                    ),
                    side: const BorderSide(color: Color(0xFFE8EEF7)),
                    onSelected: (_) => setLocal(() => tempGrade = grade),
                  );
                }

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const ListTile(
                        dense: true,
                        leading: Icon(Icons.tune_rounded, color: kNavy),
                        title: Text(
                          'Filtrele',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: kNavy,
                          ),
                        ),
                        subtitle: Text('Kategori ve sınıf'),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Kategori',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              selected: tempCat == 'all',
                              label: const Text('Tümü'),
                              selectedColor: kNavy,
                              backgroundColor: Colors.white,
                              labelStyle: TextStyle(
                                color: tempCat == 'all'
                                    ? Colors.white
                                    : kInk,
                                fontWeight: FontWeight.w700,
                              ),
                              side: const BorderSide(
                                color: Color(0xFFE8EEF7),
                              ),
                              onSelected: (_) => setLocal(() => tempCat = 'all'),
                            ),
                            for (final key in _catOrder) categoryChip(key),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Sınıf',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            gradeChip(null),
                            gradeChip(9),
                            gradeChip(10),
                            gradeChip(11),
                            gradeChip(12),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding:
                          const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setLocal(() {
                                      tempCat = 'all';
                                      tempGrade =
                                      _role == 'student' ? _myGrade : null;
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.refresh,
                                    color: kNavy,
                                  ),
                                  label: const Text(
                                    'Temizle',
                                    style: TextStyle(color: kNavy),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side:
                                    const BorderSide(color: kNavy),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(12),
                                    ),
                                    padding:
                                    const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedCategory = tempCat;
                                      _gradeFilter = tempGrade;
                                    });
                                    Navigator.pop(context);
                                    _recomputeIfNeeded(force: true);
                                  },
                                  icon: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                  ),
                                  label: const Text('Uygula'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kNavy,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(12),
                                    ),
                                    padding:
                                    const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _cachedUpcoming;
    final past = _cachedPast;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text(
          'Etkinlikler',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: kNavy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEvents,
            tooltip: 'Yenile',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Yaklaşan'),
            Tab(text: 'Geçmiş'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openFilterSheet,
                    icon: const Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                    ),
                    label: Text(
                      _filtersActive ? 'Filtrele (Aktif)' : 'Filtrele',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _filtersActive ? kTeal : kNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.calendar_month_rounded,
                    color: kNavy,
                    size: 28,
                  ),
                  onPressed: _showCalendarPopup,
                  tooltip: 'Takvim',
                ),
                if (_dateFilterActive) ...[
                  const SizedBox(width: 6),
                  InputChip(
                    label: Text(
                      _rangeStart != null && _rangeEnd != null
                          ? '${_dfChipShort.format(_rangeStart!)} – ${_dfChipLong.format(_rangeEnd!)}'
                          : _dfChipLong.format(_selectedDay),
                    ),
                    onDeleted: () {
                      setState(() {
                        _rangeStart = null;
                        _rangeEnd = null;
                        _rangeSelectionMode = RangeSelectionMode.toggledOff;
                        _showAllEvents = true;
                      });
                      _recomputeIfNeeded(force: true);
                    },
                    deleteIcon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: _tabIndex == 0
                    ? 'Yaklaşan etkinlik ara...'
                    : 'Geçmiş etkinlik ara...',
                prefixIcon: const Icon(Icons.search, color: kNavy),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  const BorderSide(color: Color(0xFFE8EEF7)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  const BorderSide(color: Color(0xFFE8EEF7)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  const BorderSide(color: kNavy, width: 1.5),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_dateFilterActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _rangeStart != null && _rangeEnd != null
                      ? 'Seçili aralık: ${_dfChipShort.format(_rangeStart!)} – ${_dfChipLong.format(_rangeEnd!)}'
                      : 'Seçili gün: ${_dfChipLong.format(_selectedDay)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const _SkeletonList()
                : _loadError != null
                ? _ErrorState(
              message: _loadError!,
              onRetry: _loadEvents,
            )
                : TabBarView(
              controller: _tabController,
              children: [
                _EventListView(
                  items: upcoming,
                  emptyLabel: 'Yaklaşan etkinlik yok.',
                  df: _dfList,
                  onRefresh: _loadEvents,
                ),
                _EventListView(
                  items: past,
                  emptyLabel: 'Geçmiş etkinlik bulunamadı.',
                  df: _dfList,
                  onRefresh: _loadEvents,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButtonAnimator: FloatingActionButtonAnimator.scaling,
      floatingActionButton: Visibility(
        visible: isAdmin || isTeacher,
        child: FloatingActionButton.extended(
          heroTag: 'fab-add-event',
          onPressed: _addEvent,
          backgroundColor: kNavy,
          foregroundColor: Colors.white,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Etkinlik Ekle',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _EventListView extends StatelessWidget {
  const _EventListView({
    required this.items,
    required this.emptyLabel,
    required this.df,
    required this.onRefresh,
  });

  final List<EventModel> items;
  final String emptyLabel;
  final DateFormat df;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_busy, color: kNavy, size: 40),
              const SizedBox(height: 10),
              Text(emptyLabel),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: kNavy,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        await onRefresh();
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: RepaintBoundary(
            child: _EventCardPro(
              e: items[index],
              df: df,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Tekrar dene'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemBuilder: (_, __) => const _SkeletonCard(),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: 6,
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    Widget box({double h = 12, double w = 80, double r = 8}) {
      return Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: Colors.black12.withOpacity(0.06),
          borderRadius: BorderRadius.circular(r),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 120,
              height: 120,
              color: Colors.black12.withOpacity(0.08),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                box(h: 18, w: 160, r: 6),
                const SizedBox(height: 8),
                box(w: 120),
                const SizedBox(height: 6),
                box(w: 200),
                const SizedBox(height: 10),
                box(w: 240),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCardPro extends StatelessWidget {
  const _EventCardPro({
    required this.e,
    required this.df,
  });

  final EventModel e;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final categoryKey = _normalizeCategory(e.category);
    final mainColor = _catMain(categoryKey);

    Future<void> notify() async {
      final when = e.eventDate.subtract(const Duration(minutes: 30));
      final service = NotificationService();

      if (when.isAfter(DateTime.now())) {
        await service.scheduleAt(
          when,
          title: 'Etkinlik yaklaşıyor',
          body: '${e.title} • ${df.format(e.eventDate)}',
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hatırlatma ayarlandı (30 dk önce).'),
            ),
          );
        }
      } else {
        await service.showNow(
          title: e.title,
          body: df.format(e.eventDate),
        );
      }
    }

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Colors.black12.withOpacity(0.06),
        ),
      ),
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventDetailPage(event: e),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              child: (e.imageUrl != null && e.imageUrl!.isNotEmpty)
                  ? AspectRatio(
                aspectRatio: 16 / 5,
                child: Image.network(
                  e.imageUrl!,
                  fit: BoxFit.cover,
                  cacheWidth: 1200,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: _catBg(categoryKey),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) =>
                      _CategoryStripe(catKey: categoryKey),
                ),
              )
                  : _CategoryStripe(catKey: categoryKey),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                      letterSpacing: -0.2,
                      color: kInk,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 16,
                        color: Colors.black45,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          df.format(e.eventDate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const _Dot(),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.place,
                        size: 16,
                        color: Colors.black45,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          e.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: mainColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    e.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.25,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: notify,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        foregroundColor: kNavy,
                      ),
                      icon: const Icon(
                        Icons.notifications_active_outlined,
                        size: 18,
                      ),
                      label: const Text('30 dk önce hatırlat'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryStripe extends StatelessWidget {
  const _CategoryStripe({required this.catKey});

  final String catKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_catBg(catKey), Colors.white],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(_catIcon(catKey), color: _catFg(catKey)),
          const SizedBox(width: 8),
          Text(
            (_catTitles[catKey] ?? '').toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _catFg(catKey),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _catIcon(String key) {
  switch (key) {
    case 'ihl':
      return Icons.menu_book_rounded;
    case 'fen':
      return Icons.biotech_rounded;
    case 'sosyal':
      return Icons.groups_2_rounded;
    case 'tech':
      return Icons.memory_rounded;
    case 'sanat':
      return Icons.sports_esports_rounded;
    default:
      return Icons.category_rounded;
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(
        color: Colors.black26,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _CacheKey {
  const _CacheKey({
    required this.search,
    required this.cat,
    required this.grade,
    required this.showAll,
    required this.selDay,
    required this.rStart,
    required this.rEnd,
    required this.dataLen,
    required this.dataStamp,
  });

  final String search;
  final String cat;
  final int? grade;
  final bool showAll;
  final DateTime selDay;
  final DateTime? rStart;
  final DateTime? rEnd;
  final int dataLen;
  final int dataStamp;

  @override
  bool operator ==(Object other) {
    return other is _CacheKey &&
        search == other.search &&
        cat == other.cat &&
        grade == other.grade &&
        showAll == other.showAll &&
        selDay == other.selDay &&
        rStart == other.rStart &&
        rEnd == other.rEnd &&
        dataLen == other.dataLen &&
        dataStamp == other.dataStamp;
  }

  @override
  int get hashCode => Object.hash(
    search,
    cat,
    grade,
    showAll,
    selDay,
    rStart,
    rEnd,
    dataLen,
    dataStamp,
  );
}