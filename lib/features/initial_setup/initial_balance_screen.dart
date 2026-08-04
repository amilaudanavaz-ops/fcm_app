import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../dashboard/dashboard_screen.dart';

class InitialBalanceScreen extends StatefulWidget {
  const InitialBalanceScreen({super.key});

  @override
  State<InitialBalanceScreen> createState() => _InitialBalanceScreenState();
}

class _InitialBalanceScreenState extends State<InitialBalanceScreen> {
  final _amountController = TextEditingController();
  bool _isLoading = false;
  String _currencySymbol = '\$';

  @override
  void initState() {
    super.initState();
    _fetchCurrencySymbol();
  }

  Future<void> _fetchCurrencySymbol() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select('currency_symbol')
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _currencySymbol = profileData?['currency_symbol'] as String? ?? '\$';
        });
      }
    } catch (e) {
      debugPrint('Failed to load currency symbol: $e');
    }
  }

  Future<void> _setInitialBalance() async {
    final textVal = _amountController.text.trim();
    if (textVal.isEmpty) return;

    // OFFLINE CHECK
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No internet connection. Cannot save your wallet.'), backgroundColor: Colors.orange));
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    final userId = Supabase.instance.client.auth.currentUser!.id;
    
    // FLOATING POINT MATH FIX: Strict 2-decimal truncation
    final rawAmount = double.tryParse(textVal) ?? 0.0;
    final amount = double.parse(rawAmount.toStringAsFixed(2));

    try {
      var accounts = await Supabase.instance.client.from('accounts').select().eq('user_id', userId).eq('name', 'My Wallet');
      dynamic walletId;

      // 1. Ensure Account Exists Safely
      if (accounts.isEmpty) {
        final newAccount = await Supabase.instance.client.from('accounts').insert({
          'user_id': userId, 
          'name': 'My Wallet', 
          'type': 'wallet',
          'current_balance': amount // Sync for schema safety
        }).select().single();
        walletId = newAccount['id'];
      } else {
        walletId = accounts.first['id'];
        await Supabase.instance.client.from('accounts').update({'current_balance': amount}).eq('id', walletId);
      }

      // 2. Insert ledger transaction
      await Supabase.instance.client.from('transactions').insert({
        'user_id': userId,
        'type': 'initial_balance', 
        'amount': amount,
        'account_id': walletId,
        'date': DateTime.now().toIso8601String(),
        'title': 'Initial Balance',
        'description': 'Initial Balance / Cash on Hand',
      });

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Modern Background
      appBar: AppBar(
        title: const Text('Setup Your Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
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
      body: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- HERO ICON ---
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: const Icon(Icons.account_balance_wallet_rounded, size: 70, color: Colors.green),
              ),
              const SizedBox(height: 32),
              
              const Text('Welcome to Finance Hub!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
              const SizedBox(height: 12),
              Text(
                'Let\'s get started. How much cash do you currently have on hand in your wallet?', 
                textAlign: TextAlign.center, 
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500, height: 1.5),
              ),
              const SizedBox(height: 40),
              
              // --- MODERN AMOUNT DISPLAY CARD ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('STARTING BALANCE', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            autofocus: true,
                            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.green, letterSpacing: -1),
                            decoration: InputDecoration(
                              prefixText: '$_currencySymbol ',
                              hintText: '0.00',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // --- ACTION BUTTONS ---
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _setInitialBalance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 8,
                    shadowColor: Colors.green.withOpacity(0.4),
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text('Start Tracking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(height: 16),
              
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _amountController.text = '0';
                  _setInitialBalance();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                ),
                child: const Text('Skip / Start with \$0', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}