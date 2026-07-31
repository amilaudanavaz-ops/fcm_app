import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dashboard/dashboard_screen.dart';

class InitialBalanceScreen extends StatefulWidget {
  const InitialBalanceScreen({super.key});

  @override
  State<InitialBalanceScreen> createState() => _InitialBalanceScreenState();
}

class _InitialBalanceScreenState extends State<InitialBalanceScreen> {
  final _amountController = TextEditingController();
  bool _isLoading = false;
  String _currencySymbol = '\$'; // NEW: Default Currency Symbol

  @override
  void initState() {
    super.initState();
    _fetchCurrencySymbol();
  }

  // NEW: Fetch currency symbol on init
  Future<void> _fetchCurrencySymbol() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
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
  }

  Future<void> _setInitialBalance() async {
    if (_amountController.text.isEmpty) return;
    setState(() => _isLoading = true);

    final userId = Supabase.instance.client.auth.currentUser!.id;
    final amount = double.parse(_amountController.text);

    try {
      // 1. Ensure 'My Wallet' exists and get its ID
      var accounts = await Supabase.instance.client.from('accounts').select().eq('user_id', userId).eq('name', 'My Wallet');
      int walletId;

      if (accounts.isEmpty) {
        // Create the default wallet if it doesn't exist
        final newAccount = await Supabase.instance.client.from('accounts').insert({
          'user_id': userId, 
          'name': 'My Wallet', 
          'type': 'wallet'
        }).select().single();
        walletId = newAccount['id'];
      } else {
        walletId = accounts.first['id'];
      }

      // 2. Insert the initial balance as a special transaction
      await Supabase.instance.client.from('transactions').insert({
        'user_id': userId,
        'type': 'initial_balance', 
        'amount': amount,
        'account_id': walletId,
        'date': DateTime.now().toIso8601String(),
        'description': 'Initial Balance/Cash on Hand',
      });

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wallet_outlined, size: 80, color: Colors.green),
              const SizedBox(height: 20),
              const Text('Welcome!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('What is your starting cash on hand (Wallet Balance)?', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
              const SizedBox(height: 40),
              
              // UPDATED INPUT: Use dynamic currency symbol for prefix
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Initial Cash Amount',
                  prefixText: '$_currencySymbol ', // USE DYNAMIC SYMBOL
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _setInitialBalance,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Confirm and Start Tracking'),
                ),
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: () {
                  _amountController.text = '0';
                  _setInitialBalance();
                },
                child: const Text('Start with \$0'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}