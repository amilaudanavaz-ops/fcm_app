import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dashboard/dashboard_screen.dart';
import '../initial_setup/initial_balance_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _routeUser() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Check if the user already has a wallet/accounts
    final accounts = await Supabase.instance.client
        .from('accounts')
        .select('id')
        .eq('user_id', userId)
        .limit(1);

    if (mounted) {
      if (accounts.isEmpty) {
        // New user or user with no accounts
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const InitialBalanceScreen()),
        );
      } else {
        // Existing user with accounts
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    }
  }

  // 1. Sign Up Logic
  Future<void> _signUp() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      if (res.user != null) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _routeUser();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account Created! Please Sign In.'), backgroundColor: Colors.green),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. Sign In Logic
  Future<void> _signIn() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      await _routeUser();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 3. Password Reset Logic
  Future<void> _resetPassword() async {
    HapticFeedback.lightImpact();
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address first.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset link sent! Check your inbox.'), backgroundColor: Colors.green),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2E0854), Color(0xFF5D12D6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                clipBehavior: Clip.none,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight, 
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      
                      // --- MAIN CONTENT ---
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // --- LOGO / BRANDING ---
                            Image.asset(
                              'assets/icon.png', 
                              width: 140, 
                              height: 140,
                              fit: BoxFit.contain, 
                            ),
                            const SizedBox(height: 24),
                            Text('Manage your wealth seamlessly', style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
                            const SizedBox(height: 40),
                            
                            // --- LOGIN CARD ---
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, 10))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Welcome Back', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black87)),
                                  const SizedBox(height: 24),
                                  
                                  // Email Field
                                  TextField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      labelText: 'Email Address',
                                      labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                                      prefixIcon: const Icon(Icons.email_rounded, color: Colors.deepPurple),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  // Password Field
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _signIn(),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                                      prefixIcon: const Icon(Icons.lock_rounded, color: Colors.deepPurple),
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.grey),
                                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                    ),
                                  ),
                                  
                                  // Forgot Password Button
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _resetPassword,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('Forgot Password?', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w700, fontSize: 13)),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 8),
                                  
                                  // Buttons
                                  if (_isLoading)
                                    const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                                  else
                                    Column(
                                      children: [
                                        SizedBox(
                                          width: double.infinity,
                                          height: 55,
                                          child: ElevatedButton(
                                            onPressed: _signIn,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.deepPurple,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                              elevation: 4,
                                              shadowColor: Colors.deepPurple.withValues(alpha: 0.3),
                                            ),
                                            child: const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 55,
                                          child: TextButton(
                                            onPressed: _signUp,
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.deepPurple,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            ),
                                            child: const Text('Create New Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // --- HIDDEN OVERSCROLL WATERMARK ---
                      Positioned(
                        bottom: -60,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.code_rounded, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                            const SizedBox(width: 8),
                            Text(
                              'Developed by DDREXAR',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.5),
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),

                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}