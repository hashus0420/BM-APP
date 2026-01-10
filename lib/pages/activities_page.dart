import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter/services.dart'; // HapticFeedback için

import '../models/event_model.dart';
import '../services/event_service.dart';
import '../services/notification_service.dart';
import 'add_event_page.dart';
import 'common/event_detail_page.dart';

/* ======= RENKLER ======= */
const kNavy = Color(0xFF113A7D);
const kSky = Color(0xFF57C3F6);
const kTeal = Color(0xFF00796B);
const kBg = Color(0xFFF7FAFF);
const kInk = Color(0xFF0F1F33);

/* ======= KATEGORİLER ======= */
const _catOrder = <String>['ihl', 'fen', 'sosyal', 'tech', 'sanat'];
const _catTitles = <String, String>{
  'ihl':   'İHL Mesleki Faaliyetler',
  'fen':   'Fen Bilimleri Faaliyetleri',
  'sosyal':'Sosyal Bilimleri Faaliyetleri',
  'tech':  'Teknolojik Faaliyetler',
  'sanat': 'Sanat, Spor, Sosyal, Kültürel Faaliyetler',
};
Color _catMain(String key) {
  switch (key) {
    case 'ihl':   return const Color(0xFF113A7D);
    case 'fen':   return const Color(0xFF00796B);
    case 'sosyal':return const Color(0xFF6A1B9A);
    case 'tech':  return const Color(0xFF1565C0);
    case 'sanat': return const Color(0xFFEF6C00);
    default:      return kNavy;
  }
}
Color _catBg(String key) => _catMain(key).withValues(alpha: .10);
Color _catFg(String key) => _catMain(key).withValues(alpha: .95);

String _normalizeCategory(String raw) {
  final s = (raw.isEmpty ? '' : raw).toLowerCase().trim();
  if (s.contains('ihl') || s.contains('meslek')) return 'ihl';
  if (s.contains('fen') || s.contains('fizik') || s.contains('kimya') || s.contains('biyoloji')) return 'fen';
  if (s.contains('sosyal') || s.contains('tarih') || s.contains('coğraf') || s.contains('felse')) return 'sosyal';
  if (s.contains('tekno') || s.contains('yazılım') || s.contains('kod') || s.contains('robot')) return 'tech';
  if (s.contains('spor') || s.contains('sanat') || s.contains('kültür') || s.contains('kultur')) return 'sanat';
  if (s == 'spor') return 'sanat';
  return 'ihl';
}

/* ============================================= */

class ActivitiesPage extends StatefulWidget {
  const ActivitiesPage({super.key});
  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

enum CardVisualMode { none, thumb, bannerIfExists }
const CardVisualMode kCardVisualMode = CardVisualMode.thumb; // seçenekler: none | thumb | bannerIfExists

class _ActivitiesPageState extends State<ActivitiesPage> with SingleTickerProviderStateMixin {
  // ignore: unused_field
  final _df = DateFormat('d MMMM y, HH:mm', 'tr');

  late Map<DateTime, List<EventModel>> _eventsMap;
  late TabController _tabController;
  int _tabIndex = 0; // 0: Yaklaşan, 1: Geçmiş

  final DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  bool _showAllEvents = true;
  String _searchQuery = "";
  String _role = 'student';
  bool _loading = true;
  String? _loadError;
  Timer? _debounce;

  // filtreler
  String _selectedCategory = 'all'; // all | ihl | fen | sosyal | tech | sanat
  int? _gradeFilter;                // null = Tümü, 9/10/11/12
  int? _myGrade;                    // öğrencinin sınıfı (10/A → 10)
  // ignore: unused_field
  final bool _onlyUpcoming = true;  // sekmeler ile yönetiliyor

  // --- Tarih aralığı filtresi ---
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  RangeSelectionMode _rangeSelectionMode = RangeSelectionMode.toggledOff;

  bool get isAdmin => _role == 'admin';
  bool get isTeacher => _role == 'teacher';
  bool get _filtersActive {
    final defaultGrade = (_role == 'student') ? _myGrade : null;
    final gradeChanged = _gradeFilter != defaultGrade;
    final catChanged = _selectedCategory != 'all';
    return gradeChanged || catChanged;
  }

  bool get _dateFilterActive => _rangeStart != null || !_showAllEvents;

  @override
  void initState() {
    super.initState();
    _eventsMap = {};
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await NotificationService().init();
    await _loadRoleAndGrade();
    await _loadEvents();
  }

  Future<void> _loadRoleAndGrade() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawRole = prefs.getString('role');
      final normalized = (rawRole ?? 'student').trim().toLowerCase();
      final r = const {'admin', 'teacher', 'student'}.contains(normalized) ? normalized : 'student';

      // sınıf (ör: "10/A") → 10
      final classStr = prefs.getString('class') ?? '';
      final m = RegExp(r'(\d{1,2})').firstMatch(classStr);
      final g = m != null ? int.tryParse(m.group(1)!) : null;

      if (!mounted) return;
      setState(() {
        _role = r;
        _myGrade = g;
        _gradeFilter = (r == 'student') ? g : null; // öğrenci → kendi sınıfı
      });
    } catch (_) {/* varsayılanlar */}
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final events = await EventService().fetchEvents();
      if (!mounted) return;
      setState(() {
        _eventsMap = _groupEventsByDate(events);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = "Etkinlikler yüklenemedi";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Etkinlik yüklenemedi: $e')),
      );
    }
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<DateTime, List<EventModel>> _groupEventsByDate(List<EventModel> events) {
    final map = <DateTime, List<EventModel>>{};
    for (final e in events) {
      final key = _dayKey(e.eventDate);
      (map[key] ??= []).add(e);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.eventDate.compareTo(b.eventDate));
    }
    return map;
  }

  List<EventModel> _getEventsForDay(DateTime day) {
    final key = _dayKey(day);
    final events = List<EventModel>.from(_eventsMap[key] ?? const []);
    events.sort((a, b) => a.eventDate.compareTo(b.eventDate));
    return events;
  }

  List<EventModel> _getAllEvents() {
    final all = _eventsMap.values.expand((list) => list).toList();
    all.sort((a, b) => a.eventDate.compareTo(b.eventDate));
    return all;
  }

  /* ---------- Filtre zinciri ---------- */
  List<EventModel> _applySearch(List<EventModel> events) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return events;
    return events.where((e) =>
    e.title.toLowerCase().contains(q) || e.description.toLowerCase().contains(q)
    ).toList();
  }

  List<EventModel> _applyCategory(List<EventModel> events) {
    if (_selectedCategory == 'all') return events;
    return events.where((e) => _normalizeCategory(e.category) == _selectedCategory).toList();
  }

  List<EventModel> _applyGrade(List<EventModel> events) {
    if (_gradeFilter == null) return events;
    return events.where((e) => _matchesGrade(e, _gradeFilter!)).toList();
  }

  // Sekmelerle zaman ayrımı yapacağımız için _onlyUpcoming kullanılmıyor;
  // tarih aralığı/tek gün filtresi burada uygulanıyor.
  List<EventModel> _applyDateWindow(List<EventModel> events) {
    if (_rangeStart != null && _rangeEnd != null) {
      final from = DateTime(_rangeStart!.year, _rangeStart!.month, _rangeStart!.day);
      final to   = DateTime(_rangeEnd!.year, _rangeEnd!.month, _rangeEnd!.day, 23, 59, 59);
      return events.where((e) =>
      !e.eventDate.isBefore(from) && !e.eventDate.isAfter(to)
      ).toList();
    }
    if (!_showAllEvents) {
      return _getEventsForDay(_selectedDay);
    }
    return events;
  }

  // Etkinliğin hedef sınıf(lar)ını metinden tahmin et
  bool _matchesGrade(EventModel e, int g) {
    final haystack = [
      e.title,
      e.description,
      e.category,
      e.eventType ?? '',
    ].join(' ').toLowerCase();

    final m1 = RegExp(r'grades?\s*[:=]\s*([0-9,\s\-]+)').firstMatch(haystack);
    if (m1 != null) {
      final s = m1.group(1)!;
      final range = RegExp(r'(\d{1,2})\s*-\s*(\d{1,2})').firstMatch(s);
      if (range != null) {
        final a = int.parse(range.group(1)!);
        final b = int.parse(range.group(2)!);
        if (g >= a && g <= b) return true;
      }
      final parts = s.split(RegExp(r'[,\s]+')).where((x) => x.isNotEmpty);
      if (parts.contains('$g')) return true;
    }

    if (RegExp(r'\b g\s*\.?\s*sınıf').hasMatch(haystack)) return true;

    final s2 = RegExp(r'(\d{1,2})\s*[-–]\s*(\d{1,2})\s*sınıf').firstMatch(haystack);
    if (s2 != null) {
      final a = int.parse(s2.group(1)!);
      final b = int.parse(s2.group(2)!);
      if (g >= a && g <= b) return true;
    }

    return true; // belirti yoksa tüm sınıflara açık varsay
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _searchQuery = val);
    });
  }

  Future<void> _addEvent() async {
    final newEvent = await Navigator.push<EventModel>(
      context,
      MaterialPageRoute(builder: (_) => const AddEventPage()),
    );
    if (newEvent != null && mounted) {
      setState(() {
        final key = _dayKey(newEvent.eventDate);
        (_eventsMap[key] ??= []).add(newEvent);
        (_eventsMap[key]!).sort((a, b) => a.eventDate.compareTo(b.eventDate));
      });
    }
  }

  /* ---------- Takvim ---------- */
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
                  final start = now.subtract(Duration(days: now.weekday - 1)); // Pazartesi
                  final end   = start.add(const Duration(days: 6));
                  setLocal(() {
                    _rangeStart = _dayKey(start);
                    _rangeEnd   = _dayKey(end);
                    _rangeSelectionMode = RangeSelectionMode.enforced;
                    _showAllEvents = true;
                  });
                }

                void selectThisMonth() {
                  final now = DateTime.now();
                  final start = DateTime(now.year, now.month, 1);
                  final end   = DateTime(now.year, now.month + 1, 0);
                  setLocal(() {
                    _rangeStart = _dayKey(start);
                    _rangeEnd   = _dayKey(end);
                    _rangeSelectionMode = RangeSelectionMode.enforced;
                    _showAllEvents = true;
                  });
                }

                void clearDateFilter() {
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
                            width: 44, height: 5,
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Başlık + Bugün butonu
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.event_available, color: kTeal),
                                const SizedBox(width: 8),
                                const Text(
                                  "Takvimden Seç",
                                  style: TextStyle(fontWeight: FontWeight.w800, color: kTeal),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: selectToday,
                                  icon: const Icon(Icons.my_location, size: 18),
                                  label: const Text("Bugün"),
                                ),
                              ],
                            ),
                          ),

                          // Hızlı aralık çipleri
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                            child: Wrap(
                              spacing: 8, runSpacing: 8,
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
                                  selected: _rangeStart == null && _rangeEnd == null && _showAllEvents,
                                  onSelected: (_) => clearDateFilter(),
                                ),
                              ],
                            ),
                          ),

                          // TableCalendar: aralık seçimi + işaretçiler
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: TableCalendar<EventModel>(
                              firstDay: DateTime.utc(2020, 1, 1),
                              lastDay: DateTime.utc(2035, 12, 31),
                              focusedDay: localFocused,
                              selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
                              rangeStartDay: _rangeStart,
                              rangeEndDay: _rangeEnd,
                              rangeSelectionMode: _rangeSelectionMode,
                              calendarFormat: CalendarFormat.month,
                              availableCalendarFormats: const { CalendarFormat.month: 'Ay' },
                              sixWeekMonthsEnforced: true,
                              rowHeight: 46,
                              daysOfWeekHeight: 22,
                              eventLoader: eventsLoader,
                              headerStyle: const HeaderStyle(
                                formatButtonVisible: false,
                                titleCentered: true,
                                titleTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                leftChevronIcon: Icon(Icons.chevron_left, color: kTeal),
                                rightChevronIcon: Icon(Icons.chevron_right, color: kTeal),
                              ),
                              calendarStyle: CalendarStyle(
                                todayDecoration: const BoxDecoration(color: kTeal, shape: BoxShape.circle),
                                selectedDecoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                rangeStartDecoration: BoxDecoration(
                                    color: kTeal.withValues(alpha: .9), shape: BoxShape.circle),
                                rangeEndDecoration: BoxDecoration(
                                    color: kTeal.withValues(alpha: .9), shape: BoxShape.circle),
                                withinRangeDecoration: BoxDecoration(
                                    color: kTeal.withValues(alpha: .18), shape: BoxShape.circle),
                                todayTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                defaultTextStyle: const TextStyle(fontSize: 14),
                                weekendTextStyle: const TextStyle(fontSize: 14),
                                outsideDaysVisible: false,
                                markersAlignment: Alignment.bottomCenter,
                                markersOffset: const PositionedOffset(bottom: 4),
                              ),
                              calendarBuilders: CalendarBuilders<EventModel>(
                                markerBuilder: (context, day, events) {
                                  if (events.isEmpty) return const SizedBox.shrink();
                                  final count = events.length;
                                  final dots = count > 3 ? 3 : count; // int güvenli
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(
                                        dots,
                                            (_) => Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 1),
                                          width: 5, height: 5,
                                          decoration: BoxDecoration(
                                            color: kTeal.withValues(alpha: .9),
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
                                  _rangeSelectionMode = RangeSelectionMode.toggledOff;
                                  _showAllEvents = false; // sadece o gün
                                });
                              },
                              onRangeSelected: (start, end, focusedDay) {
                                setState(() {
                                  _selectedDay = focusedDay;
                                  localFocused = focusedDay;
                                  _rangeStart = start != null ? _dayKey(start) : null;
                                  _rangeEnd   = end   != null ? _dayKey(end)   : null;
                                  _rangeSelectionMode = RangeSelectionMode.toggledOn;
                                  _showAllEvents = true; // liste aralığa göre
                                });
                              },
                              onPageChanged: (focusedDay) => setLocal(() => localFocused = focusedDay),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Alt butonlar
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        clearDateFilter();
                                        Navigator.pop(context);
                                        setState(() {}); // UI yenile
                                      },
                                      icon: const Icon(Icons.clear, color: kTeal),
                                      label: const Text("Tarihi Temizle", style: TextStyle(color: kTeal)),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: kTeal),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        setState(() {/* local → parent state */});
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.check, color: Colors.white),
                                      label: const Text("Uygula"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kTeal,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
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

  /* ---------- FİLTRE (Kategori + Sınıf) ---------- */
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
                Widget catChip(String key) {
                  final selected = tempCat == key;
                  return ChoiceChip(
                    selected: selected,
                    label: Text(_catTitles[key]!, maxLines: 1, overflow: TextOverflow.ellipsis),
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

                Widget gradeChip(int? g) {
                  final selected = tempGrade == g || (tempGrade == null && g == null);
                  final label = g == null ? 'Tümü' : '$g. Sınıf';
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
                    onSelected: (_) => setLocal(() => tempGrade = g),
                  );
                }

                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 44, height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const ListTile(
                        dense: true,
                        leading: Icon(Icons.tune_rounded, color: kNavy),
                        title: Text('Filtrele', style: TextStyle(fontWeight: FontWeight.w800, color: kNavy)),
                        subtitle: Text('Kategori ve sınıf'),
                      ),

                      // Kategori
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Kategori', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            ChoiceChip(
                              selected: tempCat == 'all',
                              label: const Text('Tümü'),
                              selectedColor: kNavy,
                              backgroundColor: Colors.white,
                              labelStyle: TextStyle(
                                color: tempCat == 'all' ? Colors.white : kInk,
                                fontWeight: FontWeight.w700,
                              ),
                              side: const BorderSide(color: Color(0xFFE8EEF7)),
                              onSelected: (_) => setLocal(() => tempCat = 'all'),
                            ),
                            for (final key in _catOrder) catChip(key),
                          ],
                        ),
                      ),

                      // Sınıf
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Sınıf', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          spacing: 8, runSpacing: 8,
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
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setLocal(() {
                                      tempCat = 'all';
                                      tempGrade = (_role == 'student') ? _myGrade : null;
                                    });
                                  },
                                  icon: const Icon(Icons.refresh, color: kNavy),
                                  label: const Text('Temizle', style: TextStyle(color: kNavy)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: kNavy),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                                  },
                                  icon: const Icon(Icons.check, color: Colors.white),
                                  label: const Text('Uygula'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kNavy,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
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
    // 1) Tüm etkinlikler → tarih penceresi → arama → kategori → sınıf
    final all = _getAllEvents();
    final byDate = _applyDateWindow(all);
    final bySearch = _applySearch(byDate);
    final byCat = _applyCategory(bySearch);
    final byGrade = _applyGrade(byCat);

    // 2) Sekmeye göre zaman dilimi ayır
    final now = DateTime.now().subtract(const Duration(hours: 1));
    final upcoming = byGrade.where((e) => e.eventDate.isAfter(now)).toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
    final past = byGrade.where((e) => e.eventDate.isBefore(now)).toList()
      ..sort((a, b) => b.eventDate.compareTo(a.eventDate)); // ters kronolojik

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text("Etkinlikler", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
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
          // Üst aksiyonlar: Filtrele + Takvim + Tarih çipi
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openFilterSheet,
                    icon: const Icon(Icons.tune_rounded, color: Colors.white),
                    label: Text(_filtersActive ? "Filtrele (Aktif)" : "Filtrele",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _filtersActive ? kTeal : kNavy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.calendar_month_rounded, color: kNavy, size: 28),
                  onPressed: _showCalendarPopup,
                  tooltip: 'Takvim',
                ),
                if (_dateFilterActive) ...[
                  const SizedBox(width: 6),
                  InputChip(
                    label: Text(
                      _rangeStart != null && _rangeEnd != null
                          ? '${DateFormat('d MMM', 'tr').format(_rangeStart!)} – ${DateFormat('d MMM y', 'tr').format(_rangeEnd!)}'
                          : DateFormat('d MMM y', 'tr').format(_selectedDay),
                    ),
                    onDeleted: () {
                      setState(() {
                        _rangeStart = null;
                        _rangeEnd = null;
                        _rangeSelectionMode = RangeSelectionMode.toggledOff;
                        _showAllEvents = true;
                      });
                    },
                    deleteIcon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ],
            ),
          ),

          // Arama
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: _tabIndex == 0 ? 'Yaklaşan etkinlik ara...' : 'Geçmiş etkinlik ara...',
                prefixIcon: const Icon(Icons.search, color: kNavy),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE8EEF7)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE8EEF7)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kNavy, width: 1.5),
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
                      ? "Seçili aralık: ${DateFormat('d MMM', 'tr').format(_rangeStart!)} – ${DateFormat('d MMM y', 'tr').format(_rangeEnd!)}"
                      : "Seçili gün: ${DateFormat('d MMM y', 'tr').format(_selectedDay)}",
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54, fontWeight: FontWeight.w600),
                ),
              ),
            ),

          const SizedBox(height: 4),

          // Sekme içerikleri
          Expanded(
            child: _loading
                ? const _SkeletonList()
                : _loadError != null
                ? _ErrorState(message: _loadError!, onRetry: _loadEvents)
                : TabBarView(
              controller: _tabController,
              children: [
                _EventListView(items: upcoming, emptyLabel: 'Yaklaşan etkinlik yok.'),
                _EventListView(items: past, emptyLabel: 'Geçmiş etkinlik bulunamadı.'),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Etkinlik Ekle', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/* ======= Liste kapsayıcı (sekme içinde kullanılır) ======= */
class _EventListView extends StatelessWidget {
  final List<EventModel> items;
  final String emptyLabel;
  const _EventListView({required this.items, required this.emptyLabel});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMMM y, HH:mm', 'tr');
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
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
        // üst parent’taki yenile butonu ile senkron; burada no-op
        HapticFeedback.lightImpact();
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _EventCardPro(e: items[i], df: df),
        ),
      ),
    );
  }
}

/* ======= DURUM BİLEŞENLERİ ======= */
class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      itemBuilder: (_, __) => _SkeletonCard(),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: 6,
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget box({double h = 12, double w = 80, double r = 8}) => Container(
      height: h, width: w, decoration: BoxDecoration(color: Colors.black12.withValues(alpha: .06), borderRadius: BorderRadius.circular(r)),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(width: 120, height: 120, color: Colors.black12.withValues(alpha: .08)),
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

/* ======= Kart ======= */
class _EventCardPro extends StatelessWidget {
  final EventModel e;
  final DateFormat df;
  const _EventCardPro({required this.e, required this.df});

  @override
  Widget build(BuildContext context) {
    final catKey = _normalizeCategory(e.category);
    final main = _catMain(catKey);

    Future<void> notify() async {
      final when = e.eventDate.subtract(const Duration(minutes: 30));
      final svc = NotificationService();
      if (when.isAfter(DateTime.now())) {
        await svc.scheduleAt(
          when,
          title: 'Etkinlik yaklaşıyor',
          body: '${e.title} • ${df.format(e.eventDate)}',
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hatırlatma ayarlandı (30 dk önce).')),
          );
        }
      } else {
        await svc.showNow(title: e.title, body: df.format(e.eventDate));
      }
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 1),
      duration: const Duration(milliseconds: 150),
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Material(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.black12.withValues(alpha: .06)),
        ),
        shadowColor: Colors.black12,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EventDetailPage(event: e)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KAPAK
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                child: (e.imageUrl != null && e.imageUrl!.isNotEmpty)
                    ? AspectRatio(
                  aspectRatio: 16 / 5,
                  child: Image.network(e.imageUrl!, fit: BoxFit.cover),
                )
                    : _CategoryStripe(catKey: catKey),
              ),

              // İÇERİK
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Başlık
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

                    // Meta (saat · konum)
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 16, color: Colors.black45),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            df.format(e.eventDate),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const _Dot(),
                        const SizedBox(width: 8),
                        const Icon(Icons.place, size: 16, color: Colors.black45),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            e.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: main,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Açıklama
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

                    // Hatırlat
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: notify,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          foregroundColor: kNavy,
                        ),
                        icon: const Icon(Icons.notifications_active_outlined, size: 18),
                        label: const Text('30 dk önce hatırlat'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ======= Yardımcılar (kapak için) ======= */
class _CategoryStripe extends StatelessWidget {
  final String catKey;
  const _CategoryStripe({required this.catKey});
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
              letterSpacing: .3,
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

/* ======= Diğer yardımcılar ======= */
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip, // <-- eklendi
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .8)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: IconButton(icon: Icon(icon, color: kNavy, size: 18), onPressed: onTap),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
    );
  }
}

class _ScorePill extends StatelessWidget {
  final int score;
  final bool compact;
  const _ScorePill({
    required this.score,
    this.compact = false, // <-- varsayılan
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2.5 : 3.5,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF1C7), Color(0xFFFFF9E6)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFE39C)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.star, size: 12, color: Color(0xFFF9A825)),
          SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool bold;
  final Color? color;
  const _Info({
    required this.icon,
    required this.text,
    this.bold = false, // <-- varsayılan
    this.color,        // <-- opsiyonel
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? Colors.black45),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: color ?? Colors.black87,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
