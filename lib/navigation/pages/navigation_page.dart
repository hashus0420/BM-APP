import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:msret/events/pages/activities_page.dart';
import 'package:msret/events/pages/add_event_page.dart';
import 'package:msret/points/pages/student_point_list_page.dart';
import 'package:msret/profile/pages/profile_page.dart';
import 'package:msret/profile/pages/settings_page.dart';

/// Uygulamanın ana alt gezinme yapısını yöneten sayfa.
///
/// Kullanıcının rolüne göre farklı sekmeler ve sayfalar gösterilir:
/// - admin   -> Etkinlikler, Puanlar, Etkinlik Ekle, Profil, Ayarlar
/// - teacher -> Etkinlikler, Etkinlik Ekle, Profil, Ayarlar
/// - student -> Etkinlikler, Profil, Ayarlar
class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  static const String _defaultRole = 'student';
  static const Set<String> _allowedRoles = {
    'admin',
    'teacher',
    'student',
  };

  int _selectedIndex = 0;
  String _currentRole = _defaultRole;
  bool _isLoading = true;

  bool get _isAdmin => _currentRole == 'admin';
  bool get _isTeacher => _currentRole == 'teacher';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  /// Kullanıcının rolünü yerel depolamadan okur.
  ///
  /// Geçersiz veya boş bir değer gelirse güvenli varsayılan olarak
  /// `student` kullanılır.
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final rawRole = prefs.getString('role');

    debugPrint('SharedPreferences role: $rawRole');

    String normalizedRole = (rawRole ?? _defaultRole).trim().toLowerCase();
    if (!_allowedRoles.contains(normalizedRole)) {
      normalizedRole = _defaultRole;
    }

    if (!mounted) return;

    setState(() {
      _currentRole = normalizedRole;
      _isLoading = false;
      _selectedIndex = 0;
    });
  }

  /// Alt gezinme çubuğunda yeni bir sekme seçildiğinde çalışır.
  void _onDestinationSelected(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Kullanıcının rolüne göre gösterilecek sayfa ve sekmeleri üretir.
  _NavigationConfig _buildNavigationConfig() {
    if (_isAdmin) {
      return const _NavigationConfig(
        pages: [
          ActivitiesPage(),
          StudentPointListPage(),
          AddEventPage(),
          ProfilePage(),
          SettingsPage(),
        ],
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Etkinlikler',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard),
            label: 'Puanlar',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Etkinlik Ekle',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ayarlar',
          ),
        ],
      );
    }

    if (_isTeacher) {
      return const _NavigationConfig(
        pages: [
          ActivitiesPage(),
          AddEventPage(),
          ProfilePage(),
          SettingsPage(),
        ],
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Etkinlikler',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Etkinlik Ekle',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ayarlar',
          ),
        ],
      );
    }

    return const _NavigationConfig(
      pages: [
        ActivitiesPage(),
        ProfilePage(),
        SettingsPage(),
      ],
      destinations: [
        NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          selectedIcon: Icon(Icons.list_alt),
          label: 'Etkinlikler',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profil',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Ayarlar',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final navigationConfig = _buildNavigationConfig();
    final safeIndex =
    _selectedIndex >= navigationConfig.pages.length ? 0 : _selectedIndex;

    return Scaffold(
      body: navigationConfig.pages[safeIndex],
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
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
                  indicatorColor: Colors.indigo.withOpacity(0.12),
                  indicatorShape: const StadiumBorder(),
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    final isSelected =
                    states.contains(WidgetState.selected);
                    return TextStyle(
                      fontSize: 12,
                      fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.indigo : Colors.black87,
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    final isSelected =
                    states.contains(WidgetState.selected);
                    return IconThemeData(
                      size: isSelected ? 26 : 24,
                      color: isSelected ? Colors.indigo : Colors.black54,
                    );
                  }),
                ),
              ),
              child: NavigationBar(
                selectedIndex: safeIndex,
                onDestinationSelected: _onDestinationSelected,
                labelBehavior:
                NavigationDestinationLabelBehavior.alwaysShow,
                destinations: navigationConfig.destinations,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rol bazlı gezinme ayarlarını tek nesnede toplamak için yardımcı sınıf.
class _NavigationConfig {
  const _NavigationConfig({
    required this.pages,
    required this.destinations,
  });

  final List<Widget> pages;
  final List<NavigationDestination> destinations;
}