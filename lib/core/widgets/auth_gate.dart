import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/update_password_screen.dart'; // The UI I gave you previously
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/initial_setup/initial_balance_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    // This listens globally for Supabase deep links the moment the app boots!
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;

      // Catch the Deep Link and push the Password Reset screen
      if (event == AuthChangeEvent.passwordRecovery) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UpdatePasswordScreen()),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  // Safely determine which screen to show on boot
  Future<Widget> _getHomeWidget() async {
    final session = Supabase.instance.client.auth.currentSession;
    
    // Not logged in -> Login Screen
    if (session == null) return const LoginScreen();

    try {
      // Logged in -> Check if they have a wallet/accounts
      final accounts = await Supabase.instance.client
          .from('accounts')
          .select('id')
          .eq('user_id', session.user.id)
          .limit(1);

      if (accounts.isEmpty) {
        return const InitialBalanceScreen();
      }
      return const DashboardScreen();
    } catch (e) {
      return const LoginScreen(); // Fallback on error
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _getHomeWidget(),
      builder: (context, snapshot) {
        // While checking the database, show a clean, native-feeling loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8F9FE),
            body: Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
          );
        }
        
        // Render the resolved screen
        if (snapshot.hasData) {
          return snapshot.data!;
        }
        
        return const LoginScreen();
      },
    );
  }
}