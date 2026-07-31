import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _currentThemeName = 'system';
  String _uiStyle = 'soft'; // 'soft' or 'glass'
  
  // Getters
  ThemeMode get themeMode => _themeMode;
  String get currentThemeName => _currentThemeName;
  String get uiStyle => _uiStyle;

  // --- FIX: RESTORED PRIMARY COLOR GETTER ---
  Color get primaryColor {
    switch (_currentThemeName) {
      case 'ocean':  return Colors.cyan.shade800;
      case 'forest': return Colors.green.shade900;
      case 'royal':  return Colors.deepPurple.shade800;
      case 'dark':   return Colors.blueGrey;
      default:       return Colors.blue.shade800;
    }
  }

  // Load settings from Supabase
  Future<void> loadTheme() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await Supabase.instance.client
          .from('profiles')
          .select('theme, ui_style')
          .eq('id', userId)
          .maybeSingle();

      if (data != null) {
        if (data['theme'] != null) setTheme(data['theme'], save: false);
        if (data['ui_style'] != null) setUiStyle(data['ui_style'], save: false);
      }
    } catch (e) {
      debugPrint('Error loading theme: $e');
    }
  }

  // Set Theme Color (Ocean, Forest, etc.)
  Future<void> setTheme(String themeName, {bool save = true}) async {
    _currentThemeName = themeName;
    
    // Map names to Modes
    if (themeName == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (themeName == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system; // Default for colored themes
    }

    notifyListeners();

    if (save) _saveToProfile({'theme': themeName});
  }

  // Set UI Style (Soft vs Glass)
  Future<void> setUiStyle(String style, {bool save = true}) async {
    _uiStyle = style;
    notifyListeners();
    if (save) _saveToProfile({'ui_style': style});
  }

  Future<void> _saveToProfile(Map<String, dynamic> updates) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await Supabase.instance.client.from('profiles').upsert({
        'id': userId,
        ...updates,
      });
    }
  }
}