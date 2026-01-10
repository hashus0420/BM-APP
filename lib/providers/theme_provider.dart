import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulamanın tema modunu (light/dark) yöneten provider.
class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadTheme();
  }

  /// Tema durumunu değiştir
  void toggleTheme(bool isOn) {
    _isDarkMode = isOn;
    _saveTheme();
    notifyListeners();
  }

  /// SharedPreferences’ten tema yükle
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    notifyListeners();
  }

  /// Tema durumunu kaydet
  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }
}