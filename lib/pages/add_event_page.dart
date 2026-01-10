// lib/pages/add_event_page.dart
//
// Material tabanlı, okunaklı ve yorumlu "Etkinlik Oluştur" sayfası.
// - Görsel yükleme KALDIRILDI
// - Puan: Slider (0–100)
// - Kontenjan UI KALDIRILDI (sınırsız kabul edilir; bkz. quota = 999999)
// - Tek seferlik / Tekrarlayan seri, RRULE üretimi, Supabase RPC akışı
// - "Son Başvuru" alanı KALDIRILDI → Kural: Etkinlik saatine kadar herkes başvurabilir.
//
// Bağımlılıklar: intl, shared_preferences, supabase_flutter
// Dahili: EventService, EventModel

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event_model.dart';
import '../services/event_service.dart';

/// ---- Tema (logo uyumlu) ----
const _kPrimary     = Color(0xFF123A8A); // lacivert
const _kPrimaryTint = Color(0xFFE6F3FF); // çok açık mavi (arka plan/rozet)

/// Tekrarlama seçenekleri
enum _Repeat { none, daily, weekly, biweekly, monthly }

/// Zamanlama modu (tek seferlik mi seri mi)
enum _Mode { single, series }

class AddEventPage extends StatefulWidget {
  const AddEventPage({super.key, this.onCreated});
  final void Function(EventModel created)? onCreated;

  @override
  State<AddEventPage> createState() => _AddEventPageState();
}

class _AddEventPageState extends State<AddEventPage> {
  // --- Form kontrolü ---
  final _formKey = GlobalKey<FormState>();

  // --- Metin kontrolcüleri ---
  final _titleController       = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController    = TextEditingController();

  // --- Tarih alanı (görünen metin) ---
  final _eventDateCtrl = TextEditingController();

  // --- Sayısal alanlar ---
  double _point = 10; // 0–100 slider

  // --- Zamanlama/seri ayarları ---
  _Mode _mode = _Mode.single;
  _Repeat _repeat = _Repeat.weekly;
  final _durationCtrl = TextEditingController(text: '60'); // dk
  final _graceCtrl    = TextEditingController(text: '2');  // saat

  // --- Kategori listesi ---
  final List<String> _categories = const [
    'Türkçe - Edebiyat',
    'Matematik',
    'Dil',
    'İHL Meslek Faaliyetleri',
    'Fen Bilimleri Faaliyetleri',
    'Sosyal Bilimleri Faaliyetleri',
    'Teknolojik Faaliyetler',
    'Sanat, Spor, Sosyal, Kültürel Faaliyetleri',
    'Diğer'
  ];
  String? _selectedCategory;

  // --- Tarih değerleri (gerçek) ---
  DateTime? _eventDate;

  // --- Servisler ---
  final _eventService = EventService();
  final _sb = Supabase.instance.client;

  // --- UI state ---
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _eventDateCtrl.dispose();
    _durationCtrl.dispose();
    _graceCtrl.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Yardımcılar
  // ===========================================================================

  void _showSnack(String msg, {required Color bg, required IconData icon}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(child: Text(msg)),
          ],
        ),
      ),
    );
  }

  String _weekdayCode(DateTime d) {
    const codes = ['MO','TU','WE','TH','FR','SA','SU'];
    return codes[d.weekday - 1];
  }

  String _buildRrule(DateTime anchor) {
    switch (_repeat) {
      case _Repeat.daily:
        return 'FREQ=DAILY';
      case _Repeat.weekly:
        return 'FREQ=WEEKLY;BYDAY=${_weekdayCode(anchor)}';
      case _Repeat.biweekly:
        return 'FREQ=WEEKLY;INTERVAL=2;BYDAY=${_weekdayCode(anchor)}';
      case _Repeat.monthly:
        return 'FREQ=MONTHLY';
      case _Repeat.none:
        return '';
    }
  }

  String _fmtTime(DateTime? dt) =>
      dt == null ? '-' : DateFormat('HH:mm').format(dt);

  String _humanRepeatSummary() {
    if (_mode == _Mode.single || _eventDate == null) return 'Tek seferlik etkinlik';
    final anchor = _eventDate!;
    final day = DateFormat.EEEE('tr_TR').format(anchor);
    switch (_repeat) {
      case _Repeat.daily:    return 'Her gün, ${_fmtTime(anchor)}';
      case _Repeat.weekly:   return 'Her $day, ${_fmtTime(anchor)}';
      case _Repeat.biweekly: return 'İki haftada bir $day, ${_fmtTime(anchor)}';
      case _Repeat.monthly:  return 'Her ay, ${DateFormat('d. gün – HH:mm').format(anchor)}';
      case _Repeat.none:     return 'Tek seferlik etkinlik';
    }
  }

  // ===========================================================================
  // Tarih seçimleri
  // ===========================================================================

  Future<void> _pickDate() async {
    final today = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: _kPrimary,
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: _kPrimary),
          ),
          child: child!,
        );
      },
    );

    final withTime = DateTime(
      picked.year, picked.month, picked.day,
      pickedTime?.hour ?? 0, pickedTime?.minute ?? 0,
    );

    setState(() {
      _eventDate = withTime;
      _eventDateCtrl.text = DateFormat('dd.MM.yyyy – HH:mm').format(withTime);
    });
  }

  // ===========================================================================
  // UI yardımcıları
  // ===========================================================================

  InputDecoration _inputDec(String label, {IconData? icon, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: _kPrimary) : null,
      filled: true,
      fillColor: Colors.white,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: _kPrimary, width: 1.6),
      ),
    );
  }

  Widget _twoCol(BuildContext context, {required Widget left, required Widget right}) {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      if (w >= 700) {
        return Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      }
      return Column(
        children: [
          left,
          const SizedBox(height: 12),
          right,
        ],
      );
    });
  }

  // Genel amaçlı “hızlı seçim” çipleri
  Widget _quickChips<T>({
    required String label,
    required List<T> values,
    required T? current,
    required void Function(T v) onSelected,
    String Function(T v)? display,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: -6,
          children: values.map((v) {
            final text = display == null ? '$v' : display(v);
            final selected = current == v;
            return ChoiceChip(
              label: Text(text),
              selected: selected,
              onSelected: (_) => onSelected(v),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Genel bilgi diyalogu
  Future<void> _showPageInfo() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Etkinlik Oluşturma – Bilgilendirme'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SizedBox(height: 6),
              Text('Tek seferlik vs. tekrarlayan', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('Tek seferlik etkinlik bir kez gerçekleşir. Tekrarlayan seri, seçtiğiniz kurala göre otomatik oturumlar üretir.'),
              SizedBox(height: 12),
              Text('Başvuru kuralı', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('Son başvuru alanı kaldırıldı. Etkinlik saatine kadar herkes başvurabilir.'),
              SizedBox(height: 12),
              Text('İpuçları', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('• Etkinlik tarihi/saati zorunludur.\n• Süre/yoklama için hızlı çipleri kullanabilirsiniz.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
        ],
      ),
    );
  }

  // ===========================================================================
  // Puan Slider
  // ===========================================================================
  Widget _pointSlider() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Puan', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _point,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: _point.round().toString(),
                  activeColor: _kPrimary,
                  onChanged: (v) => setState(() => _point = v),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _kPrimaryTint, borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_point.round()}',
                  style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('0–100 arası puan. Sürükleyerek hızlıca ayarlayın.'),
        ],
      ),
    );
  }

  // ===========================================================================
  // Zamanlama Kartı (Tek seferlik / Tekrarlayan)
  // ===========================================================================
  Widget _modeCard() {
    final isSeries = _mode == _Mode.series;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Zamanlama', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tek seferlik'),
                selected: _mode == _Mode.single,
                onSelected: (_) => setState(() => _mode = _Mode.single),
              ),
              ChoiceChip(
                label: const Text('Tekrarlayan seri'),
                selected: _mode == _Mode.series,
                onSelected: (_) => setState(() => _mode = _Mode.series),
              ),
            ],
          ),

          if (isSeries) ...[
            const SizedBox(height: 12),
            _quickChips<_Repeat>(
              label: 'Tekrar sıklığı',
              values: const [_Repeat.daily, _Repeat.weekly, _Repeat.biweekly, _Repeat.monthly],
              current: _repeat,
              onSelected: (v) => setState(() => _repeat = v),
              display: (v) {
                switch (v) {
                  case _Repeat.daily:    return 'Günlük';
                  case _Repeat.weekly:   return 'Haftalık';
                  case _Repeat.biweekly: return '15 günde bir';
                  case _Repeat.monthly:  return 'Aylık';
                  case _Repeat.none:     return '—';
                }
              },
            ),
            const SizedBox(height: 8),
            _twoCol(
              context,
              left: TextFormField(
                controller: _durationCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDec('Süre (dakika)', icon: Icons.timer)
                    .copyWith(helperText: 'starts_at → ends_at hesaplanır'),
                validator: (_) {
                  if (_mode != _Mode.series) return null;
                  final n = int.tryParse(_durationCtrl.text);
                  if (n == null || n <= 0) return 'Geçerli süre girin';
                  return null;
                },
              ),
              right: TextFormField(
                controller: _graceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDec('Yoklama uzatma (saat)', icon: Icons.lock_clock)
                    .copyWith(helperText: 'Bitişten sonra yoklama açık kalır'),
                validator: (_) {
                  if (_mode != _Mode.series) return null;
                  final n = int.tryParse(_graceCtrl.text);
                  if (n == null || n < 0) return 'Geçerli saat girin';
                  return null;
                },
              ),
            ),
            const SizedBox(height: 8),
            _quickChips<int>(
              label: 'Hızlı süre',
              values: const [30, 45, 60, 90],
              current: int.tryParse(_durationCtrl.text),
              onSelected: (v) => setState(() => _durationCtrl.text = '$v'),
              display: (v) => '$v dk',
            ),
            const SizedBox(height: 6),
            _quickChips<int>(
              label: 'Hızlı yoklama uzatma',
              values: const [0, 1, 2, 4],
              current: int.tryParse(_graceCtrl.text),
              onSelected: (v) => setState(() => _graceCtrl.text = '$v'),
              display: (v) => '$v saat',
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.black54, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _humanRepeatSummary(),
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),

          if (_mode == _Mode.series && _eventDate == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Not: Tekrar kuralı için önce “Etkinlik Tarihi” seçin.',
                style: TextStyle(color: Colors.orange.shade700),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Submit
  // ===========================================================================

  Future<void> _submitForm() async {
    final valid = _formKey.currentState!.validate();
    if (!valid || _eventDate == null) {
      _showSnack('Lütfen zorunlu alanları doldurun',
          bg: Colors.orange, icon: Icons.info_outline);
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final createdBy =
          prefs.getInt('user_id') ??
              int.tryParse(prefs.getString('user_id') ?? '') ??
              1;

      // Başvuru kuralı:
      // "Son başvuru" alanı kaldırıldığı için, backend'e türetilmiş bir değer geçmek isterseniz
      // application_deadline = eventDate olabilir. (Etkinlik saatine kadar başvuru)
      final applicationDeadline = _eventDate!;

      // Sınırsız kontenjan temsili: 999999 (Model alanı zorunluysa)
      const unlimitedQuota = 999999;

      final useSeries = _mode == _Mode.series;
      if (useSeries) {
        if (_repeat == _Repeat.none) {
          _showSnack('Tekrar sıklığı seçmelisiniz (Günlük/Haftalık/15 günde bir/Aylık)',
              bg: Colors.orange, icon: Icons.info_outline);
          setState(() => _submitting = false);
          return;
        }

        final startsAt    = _eventDate!;
        final durationMin = int.tryParse(_durationCtrl.text.trim()) ?? 60;
        final graceHours  = int.tryParse(_graceCtrl.text.trim()) ?? 2;
        final endsAt      = startsAt.add(Duration(minutes: durationMin));

        // 1) Seri oluştur
        final rrule = _buildRrule(startsAt);
        final seriesId = await _eventService.createSeries(
          requesterId: createdBy,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          rrule: rrule,
          graceHours: graceHours,
          timezone: 'Europe/Istanbul',
        );

        // 2) İlk etkinlik
        final eventId = await _eventService.createEventAdvanced(
          requesterId: createdBy,
          seriesId: seriesId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          startsAt: startsAt,
          endsAt: endsAt,
          location: _locationController.text.trim(),
          status: 'published',
        );

        // 3) Eski kolonları patch et (application_deadline/point gibi)
        final patch = <String, dynamic>{
          'point': _point.round(),
          // 'quota': null, // DB NULL'u "sınırsız" yorumluyorsa açabilirsiniz
          'category': _selectedCategory ?? 'Diğer',
          'application_deadline': applicationDeadline.toUtc().toIso8601String(),
        };

        final updated = await _sb
            .from('events')
            .update(patch)
            .eq('id', eventId)
            .select(
          '''
              id, title, category, description, location,
              event_date, application_deadline, point, quota, created_by, created_at,
              series_id, starts_at, ends_at, status, contact_name, contact_email, image_url
              ''',
        )
            .single();

        final created = EventModel.fromMap(Map<String, dynamic>.from(updated as Map));

        if (!mounted) return;
        _showSnack('Etkinlik planlandı ve yayınlandı',
            bg: Colors.green, icon: Icons.check_circle);
        widget.onCreated?.call(created);
        final popped = await Navigator.maybePop(context, created);
        if (!popped) _resetForm();
        return;
      }

      // Tek seferlik — doğrudan insert
      final event = EventModel(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory ?? 'Diğer',
        location: _locationController.text.trim(),
        point: _point.round(),
        // Kontenjan UI yok → sınırsız temsili
        quota: unlimitedQuota,
        eventDate: _eventDate!,
        // "Son başvuru" alanı yok → etkinlik saatine eşitledik
        applicationDeadline: applicationDeadline,
        createdBy: createdBy,
      );

      final inserted = await _eventService.addEvent(event);
      final ok = inserted != null;

      if (!mounted) return;

      if (ok) {
        _showSnack('Etkinlik başarıyla eklendi',
            bg: Colors.green, icon: Icons.check_circle);

        widget.onCreated?.call(inserted);

        final popped = await Navigator.maybePop(context, inserted);
        if (!popped) _resetForm();
      } else {
        _showSnack('Etkinlik eklenemedi',
            bg: Colors.red, icon: Icons.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _resetForm() {
    setState(() {
      _titleController.clear();
      _descriptionController.clear();
      _locationController.clear();
      _selectedCategory = null;
      _eventDate = null;
      _eventDateCtrl.clear();
      _durationCtrl.text = '60';
      _graceCtrl.text = '2';
      _mode = _Mode.single;
      _repeat = _Repeat.weekly;
      _point = 10;
    });
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final saveEnabled = !_submitting;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      appBar: AppBar(
        title: const Text('Etkinlik Oluştur'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Bilgilendirme',
            onPressed: _showPageInfo,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 140),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Temel Bilgiler',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Etkinlik detaylarını doldur.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.black54)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _titleController,
                decoration: _inputDec("Etkinlik Başlığı", icon: Icons.title),
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Bu alan zorunludur' : null,
              ),
              const SizedBox(height: 16),

              // İSTEK: Açıklama başlığına parantez içinde "Kimler Başvurabilir?"
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: _inputDec("Açıklama (Kimler Başvurabilir?)", icon: Icons.description),
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Bu alan zorunludur' : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: _inputDec("Kategori", icon: Icons.category),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                validator: (v) =>
                (v == null || v.isEmpty) ? 'Bu alan zorunludur' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _locationController,
                decoration: _inputDec("Konum", icon: Icons.location_on),
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Bu alan zorunludur' : null,
              ),

              const SizedBox(height: 24),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 16),

              Align(
                alignment: Alignment.centerLeft,
                child: Text('Puan',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 12),

              // Kontenjan UI KALDIRILDI → yalnız puan gösteriliyor
              _pointSlider(),

              const SizedBox(height: 24),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 16),

              Align(
                alignment: Alignment.centerLeft,
                child: Text('Tarihler',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 12),

              // SADECE Etkinlik Tarihi
              TextFormField(
                readOnly: true,
                controller: _eventDateCtrl,
                decoration: _inputDec("Etkinlik Tarihi", icon: Icons.event).copyWith(
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_month_rounded, color: _kPrimary),
                    onPressed: _pickDate,
                    tooltip: 'Tarih seç',
                  ),
                  hintText: 'Seçilmedi',
                ),
                onTap: _pickDate,
                validator: (_) => _eventDate == null ? 'Bu alan zorunludur' : null,
              ),

              const SizedBox(height: 16),

              // --- Zamanlama (Tek seferlik / Seri) ---
              _modeCard(),
            ],
          ),
        ),
      ),

      // sabit alt Kaydet
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saveEnabled ? _submitForm : null,
              style: FilledButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 1,
              ),
              icon: _submitting
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _submitting
                    ? 'Kaydediliyor...'
                    : (_mode == _Mode.series ? 'Planla & Yayınla' : 'Etkinliği Kaydet'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
