import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_constants.dart';
import 'core/services/global_state_provider.dart';
import 'core/widgets/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for a native financial app feel
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: SupabaseConstants.url,
    anonKey: SupabaseConstants.anonKey,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GlobalStateProvider()),
      ],
      child: const FCMApp(),
    ),
  );
}

class FCMApp extends StatelessWidget {
  const FCMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finance Hub',
      debugShowCheckedModeBanner: false,
      
      // Clean, global fallback theme since screens handle their own premium UI
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5D12D6), // Deep Purple
          primary: const Color(0xFF5D12D6),
          secondary: Colors.teal,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FE),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      
      home: const AuthGate(), // Seamless routing based on Session and Accounts
    );
  }
}