import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activities_page.dart';
import 'add_event_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';

// ✅ YENİ: puan listesi sayfası
import 'student_point_list_page.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  int _selectedIndex = 0;
  String _role = 'student';
  bool _loading = true;

  bool get isAdmin => _role == 'admin';
  bool get isTeacher => _role == 'teacher';
  bool get isStudent => _role == 'student';

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('role');
    debugPrint("SharedPreferences role: $raw");

    String normalized = (raw ?? 'student').trim().toLowerCase();
    const allowed = {'admin', 'teacher', 'student'};
    if (!allowed.contains(normalized)) normalized = 'student';

    if (!mounted) return;
    setState(() {
      _role = normalized;
      _loading = false;
      _selectedIndex = 0; // rol değişmiş olabilir, güvenli başlangıç
    });
  }

  void _onItemTapped(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
  }

  /// Her rol için ayrı sayfa ve destination seti
  ({List<Widget> pages, List<NavigationDestination> destinations}) _configForRole() {
    if (isAdmin) {
      // ADMIN: Etkinlikler, Puanlar (YENİ), Yönetim(=AddEvent), Profil, Ayarlar
      return (
      pages: <Widget>[
        const ActivitiesPage(),
        const StudentPointListPage(), // ✅ sadece admin'de
        const AddEventPage(),
        const ProfilePage(),
        const SettingsPage(),
      ],
      destinations: <NavigationDestination>[
        const NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon: Icon(Icons.event_note),
          label: 'Etkinlikler',
        ),
        const NavigationDestination(
          icon: Icon(Icons.leaderboard_outlined),
          selectedIcon: Icon(Icons.leaderboard),
          label: 'Puanlar',
        ),
        const NavigationDestination(
          icon: Icon(Icons.add_circle_outline),
          selectedIcon: Icon(Icons.add_circle),
          label: 'Etkinlik Ekle',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profil',
        ),
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Ayarlar',
        ),
      ],
      );
    }

    if (isTeacher) {
      // TEACHER: Etkinlikler, Etkinlik Ekle(=AddEvent), Profil, Ayarlar
      return (
      pages: <Widget>[
        const ActivitiesPage(),
        const AddEventPage(),
        const ProfilePage(),
        const SettingsPage(),
      ],
      destinations: <NavigationDestination>[
        const NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: 'Etkinlikler',
        ),
        const NavigationDestination(
          icon: Icon(Icons.add_circle_outline),
          selectedIcon: Icon(Icons.add_circle),
          label: 'Etkinlik Ekle',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profil',
        ),
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Ayarlar',
        ),
      ],
      );
    }

    // STUDENT (default): Etkinlikler, Profil, Ayarlar — AddEvent yok
    return (
    pages: <Widget>[
      const ActivitiesPage(),
      const ProfilePage(),
      const SettingsPage(),
    ],
    destinations: <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.list_alt_outlined),
        selectedIcon: Icon(Icons.list_alt),
        label: 'Etkinlikler',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profil',
      ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Ayarlar',
      ),
    ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final cfg = _configForRole();
    final pages = cfg.pages;
    final destinations = cfg.destinations;

    if (_selectedIndex >= pages.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Theme(
              data: Theme.of(context).copyWith(
                navigationBarTheme: NavigationBarThemeData(
                  height: 70,
                  elevation: 6,
                  backgroundColor: Colors.white,
                  indicatorColor: Colors.indigo.withValues(alpha: .12),
                  indicatorShape: const StadiumBorder(),
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.indigo : Colors.black87,
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return IconThemeData(
                      size: selected ? 26 : 24,
                      color: selected ? Colors.indigo : Colors.black54,
                    );
                  }),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onItemTapped,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: destinations,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
