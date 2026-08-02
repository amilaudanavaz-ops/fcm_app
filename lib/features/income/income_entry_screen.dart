import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class IncomeEntryScreen extends StatefulWidget {
  const IncomeEntryScreen({super.key});

  @override
  State<IncomeEntryScreen> createState() => _IncomeEntryScreenState();
}

class _IncomeEntryScreenState extends State<IncomeEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _sourceController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  // Accounts
  List<Map<String, dynamic>> _accounts = [];
  int? _selectedAccountId;
  String _currencySymbol = '\$'; // NEW: Default Currency Symbol

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // NEW: Load Data
  Future<void> _loadData() async {
    await Future.wait([
      _fetchCurrencySymbol(),
      _fetchAccounts(),
    ]);
  }

  // NEW: Fetch currency symbol
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

  Future<void> _fetchAccounts() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    var data = await Supabase.instance.client.from('accounts').select().eq('user_id', userId);

    setState(() {
      _accounts = List<Map<String, dynamic>>.from(data);
      if (_accounts.isNotEmpty) { 
        final defaultWallet = _accounts.firstWhere(
          (acc) => acc['type'] == 'wallet',
          orElse: () => _accounts.first,
        );
        _selectedAccountId = defaultWallet['id'];
      }
    });
  }

  Future<void> _saveIncome() async {
    if (!_formKey.currentState!.validate() || _selectedAccountId == null) return;
    setState(() => _isLoading = true);

    final amount = double.parse(_amountController.text);
    final description = _sourceController.text;
    final userId = Supabase.instance.client.auth.currentUser!.id;

    try {
      // 1. Savings Calculation (Existing Logic)
      final profileData = await Supabase.instance.client.from('profiles').select('savings_percentage').eq('id', userId).maybeSingle();
      final int percentage = profileData != null ? profileData['savings_percentage'] : 10;
      final double commitmentAmount = amount * (percentage / 100);

      // 2. Insert Transaction with Account ID
      final transactionResponse = await Supabase.instance.client
          .from('transactions')
          .insert({
            'user_id': userId,
            'type': 'income',
            'amount': amount,
            'description': description,
            'date': _selectedDate.toIso8601String(),
            'account_id': _selectedAccountId, // <--- LINKED TO ACCOUNT
          })
          .select()
          .single();

      // 3. Create Commitment (Existing Logic)
      if (commitmentAmount > 0) {
        await Supabase.instance.client.from('commitments').insert({
          'user_id': userId,
          'source_transaction_id': transactionResponse['id'],
          'amount': commitmentAmount,
          'status': 'pending',
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Income Saved!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Income')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // UPDATED INPUT: Use dynamic currency symbol for prefix
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount', 
                  prefixText: '$_currencySymbol ', // USE DYNAMIC SYMBOL
                  border: const OutlineInputBorder()
                ),
                validator: (val) => val == null || val.isEmpty ? 'Enter amount' : null,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _sourceController,
                decoration: const InputDecoration(labelText: 'Source', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'Enter source' : null,
              ),
              const SizedBox(height: 16),

              // Account Selector
              DropdownButtonFormField<int>(
                initialValue: _selectedAccountId,
                decoration: const InputDecoration(labelText: 'Deposit To (Wallet/Bank)', border: OutlineInputBorder()),
                items: _accounts.map((acc) {
                  return DropdownMenuItem<int>(
                    value: acc['id'],
                    child: Row(
                      children: [
                        Icon(acc['type'] == 'wallet' ? Icons.wallet : Icons.account_balance, size: 16, color: Colors.grey),
                        const SizedBox(width: 10),
                        Text(acc['name']),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedAccountId = val),
              ),
              
              const SizedBox(height: 16),

              ListTile(
                title: Text('Date: ${DateFormat.yMMMd().format(_selectedDate)}'),
                trailing: const Icon(Icons.calendar_today),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.grey)),
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                  if (picked != null) setState(() => _selectedDate = picked);
                },
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveIncome,
                  child: _isLoading ? const CircularProgressIndicator() : const Text('Save Income'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}