import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_constants.dart';
import 'core/services/theme_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConstants.url,
    anonKey: SupabaseConstants.anonKey,
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider()..loadTheme(),
      child: const FCMApp(),
    ),
  );
}

class FCMApp extends StatelessWidget {
  const FCMApp({super.key});

  ThemeData _buildTheme(String flavor, Brightness brightness, String uiStyle) {
    // 1. Define Base Colors
    Color seedColor;
    
    // We use darker shades for better contrast
    switch (flavor) {
      case 'ocean':  seedColor = Colors.cyan.shade800; break;
      case 'forest': seedColor = Colors.green.shade900; break;
      case 'royal':  seedColor = Colors.deepPurple.shade800; break;
      case 'dark':   seedColor = Colors.blueGrey; break;
      default:       seedColor = Colors.blue.shade800;
    }

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      primary: seedColor,
    );

    // 2. Define Backgrounds based on Style
    Color? scaffoldBg;
    Color? appBarBg;
    Color? appBarText;

    if (uiStyle == 'glass') {
      // GLASS MODE: The background is the Theme Color (Dark), App Bar matches it
      // This creates the "Immersive" look
      scaffoldBg = seedColor; 
      appBarBg = seedColor;
      appBarText = Colors.white;
    } else {
      // SOFT MODE: Standard Clean Look
      if (brightness == Brightness.light) {
        scaffoldBg = const Color(0xFFF5F7FA); // Very light grey/blue
        appBarBg = seedColor;
        appBarText = Colors.white;
      } else {
        // Dark Mode Soft
        scaffoldBg = const Color(0xFF121212);
        appBarBg = Colors.grey.shade900;
        appBarText = Colors.white;
      }
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: appBarText,
        elevation: 0,
        centerTitle: true,
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: uiStyle == 'glass' ? Colors.white : seedColor,
          foregroundColor: uiStyle == 'glass' ? seedColor : Colors.white,
          elevation: uiStyle == 'glass' ? 0 : 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: uiStyle == 'glass' ? Colors.white : seedColor,
        foregroundColor: uiStyle == 'glass' ? seedColor : Colors.white,
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // In Glass mode, inputs are semi-transparent white
        fillColor: uiStyle == 'glass' 
            ? Colors.white.withOpacity(0.15) 
            : (brightness == Brightness.light ? Colors.white : Colors.grey.shade900),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: TextStyle(color: uiStyle == 'glass' ? Colors.white54 : Colors.grey),
        labelStyle: TextStyle(color: uiStyle == 'glass' ? Colors.white70 : Colors.grey.shade700),
      ),
      
      // Text Theme overrides for Glass Mode
      textTheme: uiStyle == 'glass' 
          ? const TextTheme(
              bodyMedium: TextStyle(color: Colors.white),
              bodyLarge: TextStyle(color: Colors.white),
              titleMedium: TextStyle(color: Colors.white),
            )
          : null, // Use default for Soft
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      title: 'FCM',
      debugShowCheckedModeBanner: false,
      // Pass the uiStyle to the builder
      theme: _buildTheme(themeProvider.currentThemeName, Brightness.light, themeProvider.uiStyle),
      darkTheme: _buildTheme(themeProvider.currentThemeName, Brightness.dark, themeProvider.uiStyle),
      themeMode: themeProvider.currentThemeName == 'dark' ? ThemeMode.dark : ThemeMode.light,
      
      home: Supabase.instance.client.auth.currentSession == null 
          ? const LoginScreen() 
          : const DashboardScreen(),
    );
  }
}