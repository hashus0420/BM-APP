import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------- THEME ----------
const _kPrimary     = Color(0xFF123A8A);
const _kPrimaryDark = Color(0xFF0A2C6A);
const _kPrimaryTint = Color(0xFFE6F3FF);
const _kPrimaryChip = Color(0xFFBFDFFF);
const _kPositive    = _kPrimary;
const _kNegative    = Color(0xFFD32F2F);

/// ---------- Model ----------
class StudentScore {
  final String id;
  final String name;
  final num score;
  final int rank;
  const StudentScore({
    required this.id,
    required this.name,
    required this.score,
    required this.rank,
  });

  StudentScore copyWith({String? id, String? name, num? score, int? rank}) {
    return StudentScore(
      id: id ?? this.id,
      name: name ?? this.name,
      score: score ?? this.score,
      rank: rank ?? this.rank,
    );
  }
}

class StudentPointEntry {
  final String eventId;
  final String? eventTitle;
  final int delta;
  final String? reason;
  final DateTime createdAt;

  const StudentPointEntry({
    required this.eventId,
    required this.delta,
    required this.createdAt,
    this.eventTitle,
    this.reason,
  });
}

/// ---------- Repository ----------
abstract class StudentScoreRepository {
  Future<List<StudentScore>> fetchAll();
  Future<List<StudentPointEntry>> fetchHistory(String studentId, {int limit});
}

class SupabaseStudentScoreRepo implements StudentScoreRepository {
  final SupabaseClient _sb = Supabase.instance.client;

  String _pickName(Map<String, dynamic> m) {
    final fn = (m['first_name'] ?? m['firstname'] ?? '').toString().trim();
    final ln = (m['last_name']  ?? m['lastname']  ?? '').toString().trim();
    if (fn.isNotEmpty || ln.isNotEmpty) {
      return [fn, ln].where((s) => s.isNotEmpty).join(' ');
    }
    final candidates = [
      'display_name','full_name','fullname','student_name','name','username',
      'ad_soyad','ogrenci_ad_soyad','ogrenci_adi',
      'ad','adi','soyad','ogrenci'
    ];
    for (final k in candidates) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _inLiteral(List<String> ids, {required bool numeric}) {
    if (numeric) {
      return '(${ids.map((e) => int.parse(e)).join(',')})';
    } else {
      final esc = ids.map((e) => "'${e.replaceAll("'", "''")}'").join(',');
      return '($esc)';
    }
  }

  @override
  Future<List<StudentScore>> fetchAll() async {
    final rows = await _sb
        .from('v_student_total_points')
        .select('*')
        .order('total_points', ascending: false);

    final list = <StudentScore>[];
    final missingIds = <String>[];

    for (final row in (rows as List)) {
      final m = Map<String, dynamic>.from(row as Map);
      final id = (m['student_id'] ?? m['user_id'] ?? m['id']).toString();
      final score = (m['total_points'] ?? 0) as num;
      final rank = (m['rnk'] is num) ? (m['rnk'] as num).toInt() : 0;

      String name = _pickName(m);
      if (name.isEmpty) missingIds.add(id);

      list.add(StudentScore(id: id, name: name, score: score, rank: rank));
    }

    if (missingIds.isNotEmpty) {
      final uniq = missingIds.toSet().toList();
      final allInts = uniq.every((e) => int.tryParse(e) != null);
      final namesById = <String, String>{};

      try {
        final u = await _sb
            .from('users')
            .select('id, name, full_name, fullname, display_name, username, ad, ad_soyad, first_name, last_name')
            .filter('id', 'in', _inLiteral(uniq, numeric: allInts));
        for (final row in (u as List)) {
          final m = Map<String, dynamic>.from(row);
          final picked = _pickName(m);
          if (picked.isNotEmpty) namesById[m['id'].toString()] = picked;
        }
      } catch (_) {}

      try {
        final s = await _sb
            .from('students')
            .select('id, user_id, name, full_name, fullname, display_name, ad, ad_soyad, first_name, last_name')
            .or('id.in.${_inLiteral(uniq, numeric: allInts)},user_id.in.${_inLiteral(uniq, numeric: allInts)}');
        for (final row in (s as List)) {
          final m = Map<String, dynamic>.from(row);
          final key = (m['user_id'] ?? m['id']).toString();
          if (!namesById.containsKey(key)) {
            final picked = _pickName(m);
            if (picked.isNotEmpty) namesById[key] = picked;
          }
        }
      } catch (_) {}

      for (var i = 0; i < list.length; i++) {
        final it = list[i];
        if (it.name.isEmpty) {
          final found = namesById[it.id];
          list[i] = it.copyWith(
            name: (found != null && found.trim().isNotEmpty)
                ? found
                : 'Öğrenci #${it.id}',
          );
        }
      }
    }

    list.sort((a, b) {
      final by = b.score.compareTo(a.score);
      return by != 0 ? by : a.name.compareTo(b.name);
    });

    return list;
  }

  @override
  Future<List<StudentPointEntry>> fetchHistory(String studentId, {int limit = 1}) async {
    List ledgerResp;
    try {
      ledgerResp = await _sb
          .from('points_ledger')
          .select('event_id, delta, reason, created_at')
          .or('user_id.eq.$studentId,student_id.eq.$studentId')
          .order('created_at', ascending: false)
          .limit(limit);
    } on PostgrestException {
      ledgerResp = await _sb
          .from('points_ledger')
          .select('event_id, delta, reason, created_at')
          .eq('student_id', studentId)
          .order('created_at', ascending: false)
          .limit(limit);
    }

    final ledger = (ledgerResp)
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final eventIds = ledger
        .map((e) => e['event_id'])
        .where((e) => e != null)
        .map((e) => e.toString())
        .toSet()
        .toList();

    var titlesById = <String, String>{};
    if (eventIds.isNotEmpty) {
      final allInts = eventIds.every((e) => int.tryParse(e) != null);
      final evResp = await _sb
          .from('events')
          .select('id,title')
          .filter('id', 'in', _inLiteral(eventIds, numeric: allInts));
      titlesById = Map.fromEntries(
        (evResp as List).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return MapEntry(m['id'].toString(), (m['title'] ?? '').toString());
        }),
      );
    }

    return ledger.map((m) {
      final evId = m['event_id']?.toString() ?? '';
      final raw = m['delta'];
      final parsedDelta = (raw is int) ? raw : int.tryParse('$raw') ?? 0;
      return StudentPointEntry(
        eventId: evId,
        eventTitle: titlesById[evId],
        delta: parsedDelta,
        reason: m['reason']?.toString(),
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
    }).toList();
  }
}

/// ===============================================================
/// PAGE — Modern (podyum + ilerleme bar + filtre/sıralama) — HATASIZ
/// ===============================================================
class StudentPointListPage extends StatefulWidget {
  final StudentScoreRepository? repository;
  const StudentPointListPage({super.key, this.repository});

  @override
  State<StudentPointListPage> createState() => _StudentPointListPageState();
}

enum _SortMode { scoreDesc, nameAsc }

class _StudentPointListPageState extends State<StudentPointListPage> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  List<StudentScore> _all = [];
  List<StudentScore> _visible = [];
  bool _loading = true;
  String _query = '';
  bool _onlyTop50 = false;
  _SortMode _sort = _SortMode.scoreDesc;

  StudentScoreRepository get _repo =>
      widget.repository ?? SupabaseStudentScoreRepo();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _repo.fetchAll();
      _all = data;
      _applyAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Puanlar yüklenemedi: $e')),
        );
      }
      setState(() => _loading = false);
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _query = _searchCtrl.text.trim();
      _applyAll();
    });
  }

  void _applyAll() {
    final q = _normalizeTr(_query);
    var list = _all.where((s) => _normalizeTr(s.name).contains(q)).toList();

    if (_sort == _SortMode.scoreDesc) {
      list.sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    } else {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    if (_onlyTop50 && list.length > 50) list = list.take(50).toList();

    setState(() {
      _visible = list;
      _loading = false;
    });
  }

  String _normalizeTr(String input) {
    const map = {'I':'ı','İ':'i','Ş':'ş','Ğ':'ğ','Ç':'ç','Ö':'ö','Ü':'ü'};
    final sb = StringBuffer();
    for (var r in input.runes) {
      var ch = String.fromCharCode(r);
      if (map.containsKey(ch)) ch = map[ch]!;
      sb.write(ch.toLowerCase());
    }
    return sb.toString()
        .replaceAll(RegExp(r'[âáàä]'), 'a')
        .replaceAll(RegExp(r'[îíìï]'), 'i')
        .replaceAll(RegExp(r'[ûúùü]'), 'u')
        .replaceAll(RegExp(r'[ôóòö]'), 'o')
        .replaceAll(RegExp(r'[êéèë]'), 'e');
  }

  num _maxScoreIn(List<StudentScore> list) {
    num max = 0;
    for (final s in list) {
      if (s.score > max) max = s.score;
    }
    return max <= 0 ? 1 : max;
  }

  @override
  Widget build(BuildContext context) {
    final padTop = MediaQuery.of(context).padding.top;
    final maxScore = _maxScoreIn(_visible.isEmpty ? _all : _visible);

    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _load,
        child: Scrollbar(
          child: CustomScrollView(
            slivers: [
              // ---------- HERO ----------
              SliverToBoxAdapter(
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, padTop + 18, 16, 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_kPrimary, _kPrimaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Liderlik Tablosu',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text('Öğrenci Puanları',
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 14),
                      _SearchGlass(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        hint: 'İsimle ara (örn: Hasan)',
                        hasQuery: _query.isNotEmpty,
                        onClear: () { _searchCtrl.clear(); FocusScope.of(context).unfocus(); },
                      ),
                      const SizedBox(height: 12),
                      _ControlsRow(
                        loading: _loading,
                        showing: _visible.length,
                        total: _all.length,
                        onlyTop50: _onlyTop50,
                        sort: _sort,
                        onToggleTop50: () { _onlyTop50 = !_onlyTop50; _applyAll(); },
                        onToggleSort: () {
                          _sort = (_sort == _SortMode.scoreDesc) ? _SortMode.nameAsc : _SortMode.scoreDesc;
                          _applyAll();
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ---------- PODYUM ----------
              if (!_loading && _visible.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: _Podium(items: _visible.take(3).toList()),
                  ),
                ),

              // ---------- LİSTE BAŞLIK ----------
              if (!_loading && _visible.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: _SectionHeader(icon: Icons.list_alt, text: 'Tüm Katılımcılar'),
                  ),
                ),

              // ---------- LİSTE ----------
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: _kPrimary)),
                )
              else if (_visible.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final s = _visible[index];
                      final rank = s.rank > 0 ? s.rank : (index + 1);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                        child: _ModernCard(
                          rank: rank,
                          name: s.name,
                          score: s.score,
                          maxScore: maxScore,
                          query: _query,
                          onTap: () => _openDetail(context, s),
                        ),
                      );
                    },
                    childCount: _visible.length,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 18)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, StudentScore student) async {
    final history = await _repo.fetchHistory(student.id, limit: 1);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final last = history.isNotEmpty ? history.first : null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _kPrimaryTint,
                    child: Text(
                      student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(student.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text('Toplam Puan: ${student.score}', style: const TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (last == null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _kPrimaryTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kPrimary.withValues(alpha: 0.15)),
                  ),
                  child: const Text('Kayıt bulunamadı'),
                )
              else
                _LastEntry(last: last),
            ],
          ),
        );
      },
    );
  }
}

/// ===================== HERO BİLEŞENLERİ =====================
class _SearchGlass extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onClear;
  final bool hasQuery;

  const _SearchGlass({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onClear,
    required this.hasQuery,
  });

  @override
  State<_SearchGlass> createState() => _SearchGlassState();
}

class _SearchGlassState extends State<_SearchGlass> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() {
      if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _focused ? 0.18 : 0.10),
            blurRadius: _focused ? 16 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: _kPrimaryDark, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: _kPrimaryDark),
          prefixIcon: const Icon(Icons.search, color: _kPrimaryDark),
          suffixIcon: widget.hasQuery
              ? IconButton(
            tooltip: 'Temizle',
            icon: const Icon(Icons.clear, color: _kPrimaryDark),
            onPressed: widget.onClear,
          )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _ControlsRow extends StatelessWidget {
  final bool loading;
  final int showing;
  final int total;
  final bool onlyTop50;
  final _SortMode sort;
  final VoidCallback onToggleTop50;
  final VoidCallback onToggleSort;

  const _ControlsRow({
    required this.loading,
    required this.showing,
    required this.total,
    required this.onlyTop50,
    required this.sort,
    required this.onToggleTop50,
    required this.onToggleSort,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
          ),
        Expanded(
          child: Text(
            'Gösterilen: $showing / $total',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            _glassPill(
              icon: Icons.filter_alt_outlined,
              label: onlyTop50 ? 'İlk 50' : 'Tümü',
              onTap: onToggleTop50,
            ),
            _glassPill(
              icon: Icons.swap_vert,
              label: sort == _SortMode.scoreDesc ? 'Puan' : 'İsim',
              onTap: onToggleSort,
            ),
          ],
        ),
      ],
    );
  }

  Widget _glassPill({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionHeader({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _kPrimaryDark),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: _kPrimaryDark, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

/// ===================== PODYUM (OVERFLOW-FIX) =====================
class _Podium extends StatelessWidget {
  final List<StudentScore> items;
  const _Podium({required this.items});

  @override
  Widget build(BuildContext context) {
    final s1 = items.isNotEmpty ? items[0] : null;
    final s2 = items.length > 1 ? items[1] : null;
    final s3 = items.length > 2 ? items[2] : null;

    final w = MediaQuery.of(context).size.width;
    final double h = w < 380 ? 178 : 168; // küçük cihazlara nefes

    return SizedBox(
      height: h,
      child: Row(
        children: [
          Expanded(child: _PodiumTile(data: s2, rank: 2)),
          const SizedBox(width: 10),
          Expanded(child: _PodiumTile(data: s1, rank: 1, tall: true)),
          const SizedBox(width: 10),
          Expanded(child: _PodiumTile(data: s3, rank: 3)),
        ],
      ),
    );
  }
}

class _PodiumTile extends StatelessWidget {
  final StudentScore? data;
  final int rank;
  final bool tall;
  const _PodiumTile({required this.data, required this.rank, this.tall = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      // Kare zorunluluğunu kaldırdık; üstteki SizedBox yüksekliğine uyar.
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: data == null
          ? const Center(child: Text('-'))
          : Stack(
        children: [
          // Sağ üst rank rozeti
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _kPrimaryTint,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _kPrimary.withValues(alpha: 0.18)),
              ),
              child: Text('#$rank',
                  style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800)),
            ),
          ),

          // İçerik — Spacer yok → overflow yok
          Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, tall ? 12 : 16, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    rank == 1 ? Icons.emoji_events
                        : rank == 2 ? Icons.military_tech
                        : Icons.workspace_premium,
                    color: rank == 1 ? Colors.amber : rank == 2 ? Colors.blueGrey : Colors.brown,
                    size: rank == 1 ? 30 : 26,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data!.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _kPrimaryTint,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _kPrimary.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      '${data!.score} puan',
                      style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===================== LİSTE KARTI =====================
class _ModernCard extends StatelessWidget {
  final int rank;
  final String name;
  final num score;
  final num maxScore;
  final String query;
  final VoidCallback onTap;

  const _ModernCard({
    required this.rank,
    required this.name,
    required this.score,
    required this.maxScore,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (score <= 0 || maxScore <= 0) ? 0.0 : (score / maxScore).clamp(0, 1).toDouble();
    final isTop3 = rank <= 3;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 6)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        backgroundColor: _kPrimaryTint,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Positioned(
                        right: -6,
                        bottom: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('#$rank',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HighlightedText(text: name, query: query),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              isTop3 ? Icons.workspace_premium : Icons.person,
                              size: 14,
                              color: isTop3 ? Colors.amber : Colors.black45,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                isTop3 ? 'Podyumda' : 'Katılımcı',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black54, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kPrimaryTint,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _kPrimary.withValues(alpha: 0.15)),
                    ),
                    child: Text('${score.toString()} puan',
                        style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.grey.shade200),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: ratio,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_kPrimary, _kPrimaryDark],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
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
        ),
      ),
    );
  }
}

/// ===================== ORTAK KÜÇÜK WIDGET’LAR =====================
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  const _HighlightedText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    final base = const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _kPrimaryDark);

    if (query.isEmpty) return Text(text, style: base);

    String normalize(String s) {
      const map = {'I':'ı','İ':'i','Ş':'ş','Ğ':'ğ','Ç':'ç','Ö':'ö','Ü':'ü'};
      final sb = StringBuffer();
      for (var r in s.runes) {
        var ch = String.fromCharCode(r);
        if (map.containsKey(ch)) ch = map[ch]!;
        sb.write(ch.toLowerCase());
      }
      return sb.toString()
          .replaceAll(RegExp(r'[âáàä]'), 'a')
          .replaceAll(RegExp(r'[îíìï]'), 'i')
          .replaceAll(RegExp(r'[ûúùü]'), 'u')
          .replaceAll(RegExp(r'[ôóòö]'), 'o')
          .replaceAll(RegExp(r'[êéèë]'), 'e');
    }

    final nText = normalize(text);
    final nQuery = normalize(query);
    final start = nText.indexOf(nQuery);
    if (start < 0) return Text(text, style: base);

    final end = start + nQuery.length;
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(
              backgroundColor: _kPrimaryChip,
              color: _kPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }
}

class _LastEntry extends StatelessWidget {
  final StudentPointEntry last;
  const _LastEntry({required this.last});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _kPrimaryTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(
              last.delta >= 0 ? Icons.trending_up : Icons.trending_down,
              color: last.delta >= 0 ? _kPositive : _kNegative,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(last.eventTitle?.isNotEmpty == true ? last.eventTitle! : 'Etkinlik #${last.eventId}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6, runSpacing: -6,
                  children: [
                    _pill('${last.delta >= 0 ? '+' : ''}${last.delta} puan', bg: _kPrimaryChip, fg: _kPrimary),
                    if ((last.reason ?? '').isNotEmpty) _pill(last.reason!),
                    _pill(_fmtDate(last.createdAt)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _pill(String text, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (bg ?? Colors.grey.shade200),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (fg ?? Colors.black54).withValues(alpha: 0.08)),
      ),
      child: Text(text, style: TextStyle(color: fg ?? Colors.black87, fontSize: 12.5)),
    );
  }

  String _fmtDate(DateTime dt) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${two(dt.day)}.${two(dt.month)}.${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: _kPrimary),
            SizedBox(height: 12),
            Text('Kayıt bulunamadı'),
          ],
        ),
      ),
    );
  }
}
