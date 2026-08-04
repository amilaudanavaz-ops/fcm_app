import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../categories/categories_screen.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  double _savingsPercentage = 10.0;
  String _currencySymbol = '\$';
  bool _isLoading = true;

  final List<String> _commonCurrencies = ['\$', '€', '£', '¥', '₹', 'A\$', 'C\$', 'Rp', 'Rs', 'kr', 'R', '₱'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final data = await _supabase
          .from('profiles')
          .select('savings_percentage, currency_symbol')
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (data != null) {
            _savingsPercentage = (data['savings_percentage'] as num?)?.toDouble() ?? 10.0;
            _currencySymbol = data['currency_symbol']?.toString() ?? '\$';
            
            // Ensure the fetched symbol exists in our list, otherwise add it
            if (!_commonCurrencies.contains(_currencySymbol)) {
              _commonCurrencies.insert(0, _currencySymbol);
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load settings: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _saveSettingsSilently() async {
    HapticFeedback.lightImpact();
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('profiles').upsert({
        'id': userId,
        'savings_percentage': _savingsPercentage.toInt(),
        'currency_symbol': _currencySymbol,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings automatically saved!', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving settings: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _signOut() async {
    HapticFeedback.mediumImpact();
    try {
      await _supabase.auth.signOut();
      if (mounted) {
        // Clear navigation stack and route to Login
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to sign out: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Modern light background
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E0854), Color(0xFF5D12D6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // --- FINANCIAL LOGIC SECTION ---
                  const Text('Financial Logic', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      children: [
                        // Savings Percentage Slider
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.teal.shade50, shape: BoxShape.circle),
                                    child: const Icon(Icons.savings_rounded, color: Colors.teal, size: 22),
                                  ),
                                  const SizedBox(width: 16),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Savings Commitment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                                        SizedBox(height: 2),
                                        Text('Auto-calculated from income', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ),
                                  Text('${_savingsPercentage.toInt()}%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.teal)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: Colors.teal,
                                  inactiveTrackColor: Colors.teal.shade100,
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.teal.withValues(alpha: 0.2),
                                  trackHeight: 6,
                                ),
                                child: Slider(
                                  value: _savingsPercentage,
                                  min: 0, 
                                  max: 50, 
                                  divisions: 50,
                                  onChanged: (val) {
                                    setState(() => _savingsPercentage = val);
                                    HapticFeedback.selectionClick();
                                  },
                                  onChangeEnd: (_) => _saveSettingsSilently(), // Auto-save when finger released
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        Divider(height: 1, color: Colors.grey.shade100),

                        // Currency Selector
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                                child: const Icon(Icons.payments_rounded, color: Colors.blue, size: 22),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Currency Symbol', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                                    SizedBox(height: 2),
                                    Text('Used across all dashboards', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _currencySymbol,
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87),
                                    items: _commonCurrencies.map((String sym) {
                                      return DropdownMenuItem<String>(
                                        value: sym,
                                        child: Text(sym),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _currencySymbol = val);
                                        _saveSettingsSilently();
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // --- DATA MANAGEMENT SECTION ---
                  const Text('Data Management', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      children: [
                        // Categories Navigator
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const CategoriesScreen()));
                          },
                          borderRadius: BorderRadius.circular(32),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                                  child: const Icon(Icons.category_rounded, color: Colors.orange, size: 22),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Manage Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                                      SizedBox(height: 2),
                                      Text('Add or delete income & expense tags', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // --- ACCOUNT AUTHENTICATION SECTION ---
                  const Text('Account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      children: [
                        // Sign Out Button
                        InkWell(
                          onTap: _signOut,
                          borderRadius: BorderRadius.circular(32),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                                  child: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.redAccent)),
                                      SizedBox(height: 2),
                                      Text('Securely log out of your device', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- DEVELOPER WATERMARK ---
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.deepPurple.withValues(alpha: 0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          )
                        ],
                        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.code_rounded, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          const Text(
                            'Developed by ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                          ),
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF2E0854), Color(0xFF5D12D6)],
                            ).createShader(bounds),
                            child: const Text(
                              'DDREXAR',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Colors.white, // Required for ShaderMask to work correctly
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 40), // Safe bottom padding
                ],
              ),
            ),
    );
  }
}