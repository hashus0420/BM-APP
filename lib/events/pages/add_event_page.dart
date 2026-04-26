import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:msret/events/model/event_model.dart';
import 'package:msret/events/services/event_service.dart';

/// Uygulamanın etkinlik oluşturma sayfasında kullanılan ana tema renkleri.
const _kPrimary = Color(0xFF123A8A);
const _kPrimaryTint = Color(0xFFE6F3FF);

/// Tekrarlama seçenekleri.
enum _Repeat {
  none,
  daily,
  weekly,
  biweekly,
  monthly,
}

/// Zamanlama modu:
/// - single: tek seferlik etkinlik
/// - series: tekrarlayan seri etkinlik
enum _Mode {
  single,
  series,
}

class AddEventPage extends StatefulWidget {
  const AddEventPage({super.key, this.onCreated});

  final void Function(EventModel created)? onCreated;

  @override
  State<AddEventPage> createState() => _AddEventPageState();
}

class _AddEventPageState extends State<AddEventPage> {
  /// Form doğrulama anahtarı.
  final _formKey = GlobalKey<FormState>();

  /// Metin alanı kontrolcüleri.
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _eventDateController = TextEditingController();

  /// Seri ayar kontrolcüleri.
  final _durationController = TextEditingController(text: '60');
  final _graceController = TextEditingController(text: '2');

  /// Etkinlik puanı.
  double _point = 10;

  /// Zamanlama ayarları.
  _Mode _mode = _Mode.single;
  _Repeat _repeat = _Repeat.weekly;

  /// Kategori seçimi.
  final List<String> _categories = const [
    'Türkçe - Edebiyat',
    'Matematik',
    'Dil',
    'İHL Meslek Faaliyetleri',
    'Fen Bilimleri Faaliyetleri',
    'Sosyal Bilimleri Faaliyetleri',
    'Teknolojik Faaliyetler',
    'Sanat, Spor, Sosyal, Kültürel Faaliyetleri',
    'Diğer',
  ];
  String? _selectedCategory;

  /// Gerçek etkinlik tarihi.
  DateTime? _eventDate;

  /// Servisler.
  final EventService _eventService = EventService();
  final SupabaseClient _supabase = Supabase.instance.client;

  /// UI state.
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _eventDateController.dispose();
    _durationController.dispose();
    _graceController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Yardımcı metodlar
  // ===========================================================================

  void _showSnack(
      String message, {
        required Color backgroundColor,
        required IconData icon,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(child: Text(message)),
          ],
        ),
      ),
    );
  }

  String _weekdayCode(DateTime date) {
    const codes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    return codes[date.weekday - 1];
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

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '-';
    return DateFormat('HH:mm').format(dateTime);
  }

  String _humanRepeatSummary() {
    if (_mode == _Mode.single || _eventDate == null) {
      return 'Tek seferlik etkinlik';
    }

    final anchor = _eventDate!;
    final dayName = DateFormat.EEEE('tr_TR').format(anchor);

    switch (_repeat) {
      case _Repeat.daily:
        return 'Her gün, ${_formatTime(anchor)}';
      case _Repeat.weekly:
        return 'Her $dayName, ${_formatTime(anchor)}';
      case _Repeat.biweekly:
        return 'İki haftada bir $dayName, ${_formatTime(anchor)}';
      case _Repeat.monthly:
        return 'Her ay, ${DateFormat('d. gün – HH:mm').format(anchor)}';
      case _Repeat.none:
        return 'Tek seferlik etkinlik';
    }
  }

  // ===========================================================================
  // Tarih seçimi
  // ===========================================================================

  Future<void> _pickDate() async {
    final today = DateTime.now();

    final pickedDate = await showDatePicker(
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

    if (pickedDate == null) return;

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

    final selectedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime?.hour ?? 0,
      pickedTime?.minute ?? 0,
    );

    setState(() {
      _eventDate = selectedDateTime;
      _eventDateController.text =
          DateFormat('dd.MM.yyyy – HH:mm').format(selectedDateTime);
    });
  }

  // ===========================================================================
  // UI yardımcıları
  // ===========================================================================

  InputDecoration _buildInputDecoration(
      String label, {
        IconData? icon,
        String? hint,
      }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: _kPrimary) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 14,
      ),
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

  Widget _buildResponsiveTwoColumn({
    required Widget left,
    required Widget right,
  }) {
    return LayoutBuilder(
      builder: (_, constraints) {
        if (constraints.maxWidth >= 700) {
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
      },
    );
  }

  Widget _buildQuickChips<T>({
    required String label,
    required List<T> values,
    required T? current,
    required void Function(T value) onSelected,
    String Function(T value)? display,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: -6,
          children: values.map((value) {
            final text = display == null ? '$value' : display(value);
            final isSelected = current == value;

            return ChoiceChip(
              label: Text(text),
              selected: isSelected,
              onSelected: (_) => onSelected(value),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _showPageInfo() async {
    await showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Etkinlik Oluşturma – Bilgilendirme'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 6),
                Text(
                  'Tek seferlik vs. tekrarlayan',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  'Tek seferlik etkinlik bir kez gerçekleşir. '
                      'Tekrarlayan seri, seçtiğiniz kurala göre otomatik oturumlar üretir.',
                ),
                SizedBox(height: 12),
                Text(
                  'Başvuru kuralı',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  'Son başvuru alanı kaldırıldı. '
                      'Etkinlik saatine kadar herkes başvurabilir.',
                ),
                SizedBox(height: 12),
                Text(
                  'İpuçları',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  '• Etkinlik tarihi/saati zorunludur.\n'
                      '• Süre/yoklama için hızlı çipleri kullanabilirsiniz.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // UI bileşenleri
  // ===========================================================================

  Widget _buildPointSlider() {
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
          const Text(
            'Puan',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
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
                  onChanged: (value) {
                    setState(() => _point = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _kPrimaryTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_point.round()}',
                  style: const TextStyle(
                    color: _kPrimary,
                    fontWeight: FontWeight.w800,
                  ),
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

  Widget _buildModeCard() {
    final isSeries = _mode == _Mode.series;

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
          const Text(
            'Zamanlama',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tek seferlik'),
                selected: _mode == _Mode.single,
                onSelected: (_) {
                  setState(() => _mode = _Mode.single);
                },
              ),
              ChoiceChip(
                label: const Text('Tekrarlayan seri'),
                selected: _mode == _Mode.series,
                onSelected: (_) {
                  setState(() => _mode = _Mode.series);
                },
              ),
            ],
          ),
          if (isSeries) ...[
            const SizedBox(height: 12),
            _buildQuickChips<_Repeat>(
              label: 'Tekrar sıklığı',
              values: const [
                _Repeat.daily,
                _Repeat.weekly,
                _Repeat.biweekly,
                _Repeat.monthly,
              ],
              current: _repeat,
              onSelected: (value) => setState(() => _repeat = value),
              display: (value) {
                switch (value) {
                  case _Repeat.daily:
                    return 'Günlük';
                  case _Repeat.weekly:
                    return 'Haftalık';
                  case _Repeat.biweekly:
                    return '15 günde bir';
                  case _Repeat.monthly:
                    return 'Aylık';
                  case _Repeat.none:
                    return '—';
                }
              },
            ),
            const SizedBox(height: 8),
            _buildResponsiveTwoColumn(
              left: TextFormField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _buildInputDecoration(
                  'Süre (dakika)',
                  icon: Icons.timer,
                ).copyWith(
                  helperText: 'starts_at → ends_at hesaplanır',
                ),
                validator: (_) {
                  if (_mode != _Mode.series) return null;
                  final value = int.tryParse(_durationController.text);
                  if (value == null || value <= 0) {
                    return 'Geçerli süre girin';
                  }
                  return null;
                },
              ),
              right: TextFormField(
                controller: _graceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _buildInputDecoration(
                  'Yoklama uzatma (saat)',
                  icon: Icons.lock_clock,
                ).copyWith(
                  helperText: 'Bitişten sonra yoklama açık kalır',
                ),
                validator: (_) {
                  if (_mode != _Mode.series) return null;
                  final value = int.tryParse(_graceController.text);
                  if (value == null || value < 0) {
                    return 'Geçerli saat girin';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 8),
            _buildQuickChips<int>(
              label: 'Hızlı süre',
              values: const [30, 45, 60, 90],
              current: int.tryParse(_durationController.text),
              onSelected: (value) {
                setState(() => _durationController.text = '$value');
              },
              display: (value) => '$value dk',
            ),
            const SizedBox(height: 6),
            _buildQuickChips<int>(
              label: 'Hızlı yoklama uzatma',
              values: const [0, 1, 2, 4],
              current: int.tryParse(_graceController.text),
              onSelected: (value) {
                setState(() => _graceController.text = '$value');
              },
              display: (value) => '$value saat',
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: Colors.black54,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _humanRepeatSummary(),
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
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
    final isValid = _formKey.currentState!.validate();

    if (!isValid || _eventDate == null) {
      _showSnack(
        'Lütfen zorunlu alanları doldurun',
        backgroundColor: Colors.orange,
        icon: Icons.info_outline,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final createdBy = prefs.getInt('user_id') ??
          int.tryParse(prefs.getString('user_id') ?? '') ??
          1;

      final applicationDeadline = _eventDate!;
      const unlimitedQuota = 999999;

      final isSeries = _mode == _Mode.series;

      if (isSeries) {
        if (_repeat == _Repeat.none) {
          _showSnack(
            'Tekrar sıklığı seçmelisiniz (Günlük/Haftalık/15 günde bir/Aylık)',
            backgroundColor: Colors.orange,
            icon: Icons.info_outline,
          );
          setState(() => _isSubmitting = false);
          return;
        }

        final startsAt = _eventDate!;
        final durationMin = int.tryParse(_durationController.text.trim()) ?? 60;
        final graceHours = int.tryParse(_graceController.text.trim()) ?? 2;
        final endsAt = startsAt.add(Duration(minutes: durationMin));

        final rrule = _buildRrule(startsAt);

        final seriesId = await _eventService.createSeries(
          requesterId: createdBy,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          rrule: rrule,
          graceHours: graceHours,
          timezone: 'Europe/Istanbul',
        );

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

        final patch = <String, dynamic>{
          'point': _point.round(),
          'category': _selectedCategory ?? 'Diğer',
          'application_deadline':
          applicationDeadline.toUtc().toIso8601String(),
        };

        final updated = await _supabase
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

        final created = EventModel.fromMap(
          Map<String, dynamic>.from(updated as Map),
        );

        if (!mounted) return;

        _showSnack(
          'Etkinlik planlandı ve yayınlandı',
          backgroundColor: Colors.green,
          icon: Icons.check_circle,
        );

        widget.onCreated?.call(created);

        final popped = await Navigator.maybePop(context, created);
        if (!popped) _resetForm();
        return;
      }

      final event = EventModel(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory ?? 'Diğer',
        location: _locationController.text.trim(),
        point: _point.round(),
        quota: unlimitedQuota,
        eventDate: _eventDate!,
        applicationDeadline: applicationDeadline,
        createdBy: createdBy,
      );

      final inserted = await _eventService.addEvent(event);
      final isSuccess = inserted != null;

      if (!mounted) return;

      if (isSuccess) {
        _showSnack(
          'Etkinlik başarıyla eklendi',
          backgroundColor: Colors.green,
          icon: Icons.check_circle,
        );

        widget.onCreated?.call(inserted);

        final popped = await Navigator.maybePop(context, inserted);
        if (!popped) _resetForm();
      } else {
        _showSnack(
          'Etkinlik eklenemedi',
          backgroundColor: Colors.red,
          icon: Icons.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _resetForm() {
    setState(() {
      _titleController.clear();
      _descriptionController.clear();
      _locationController.clear();
      _selectedCategory = null;
      _eventDate = null;
      _eventDateController.clear();
      _durationController.text = '60';
      _graceController.text = '2';
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
    final isSaveEnabled = !_isSubmitting;

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
                    Text(
                      'Temel Bilgiler',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Etkinlik detaylarını doldur.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: _buildInputDecoration(
                  'Etkinlik Başlığı',
                  icon: Icons.title,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Bu alan zorunludur';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: _buildInputDecoration(
                  'Açıklama (Kimler Başvurabilir?)',
                  icon: Icons.description,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Bu alan zorunludur';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: _buildInputDecoration(
                  'Kategori',
                  icon: Icons.category,
                ),
                items: _categories
                    .map(
                      (category) => DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  ),
                )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedCategory = value);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bu alan zorunludur';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: _buildInputDecoration(
                  'Konum',
                  icon: Icons.location_on,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Bu alan zorunludur';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFE2E8F0),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Puan',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
              _buildPointSlider(),
              const SizedBox(height: 24),
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFE2E8F0),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tarihler',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                readOnly: true,
                controller: _eventDateController,
                decoration: _buildInputDecoration(
                  'Etkinlik Tarihi',
                  icon: Icons.event,
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.calendar_month_rounded,
                      color: _kPrimary,
                    ),
                    onPressed: _pickDate,
                    tooltip: 'Tarih seç',
                  ),
                  hintText: 'Seçilmedi',
                ),
                onTap: _pickDate,
                validator: (_) {
                  if (_eventDate == null) {
                    return 'Bu alan zorunludur';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildModeCard(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isSaveEnabled ? _submitForm : null,
              style: FilledButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 1,
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _isSubmitting
                    ? 'Kaydediliyor...'
                    : (_mode == _Mode.series
                    ? 'Planla & Yayınla'
                    : 'Etkinliği Kaydet'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}