import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IncomeEntryScreen extends StatefulWidget {
  const IncomeEntryScreen({super.key});

  @override
  State<IncomeEntryScreen> createState() => _IncomeEntryScreenState();
}

class _IncomeEntryScreenState extends State<IncomeEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _sourceController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isInitLoading = true;

  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _incomeCategories = [];
  String? _selectedAccountId;
  String _currencySymbol = '\$';
  int _savingsPercentage = 10;

  @override
  void initState() {
    super.initState();
    _loadInitialDataConcurrently();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  // --- FAST CONCURRENT DATA LOADING ---
  Future<void> _loadInitialDataConcurrently() async {
    setState(() => _isInitLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // PERFORMANCE UPGRADE: Fetch Profile, Accounts, and Income Categories simultaneously
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select('currency_symbol, savings_percentage').eq('id', userId).maybeSingle(),
        _supabase.from('accounts').select('id, name, type, current_balance').eq('user_id', userId).order('id', ascending: true),
        _supabase.from('categories').select('id, name').eq('user_id', userId).eq('type', 'income').order('name', ascending: true),
      ]);

      final profileData = results[0] as Map<String, dynamic>?;
      final accountsData = (results[1] as List<dynamic>?) ?? [];
      final categoriesData = (results[2] as List<dynamic>?) ?? [];

      if (mounted) {
        setState(() {
          _currencySymbol = profileData?['currency_symbol']?.toString() ?? '\$';
          _savingsPercentage = (profileData?['savings_percentage'] as num?)?.toInt() ?? 10;
          _incomeCategories = List<Map<String, dynamic>>.from(categoriesData);

          _accounts = List<Map<String, dynamic>>.from(accountsData);
          if (_accounts.isNotEmpty) {
            // Default to wallet, fallback to first account
            final defaultWallet = _accounts.firstWhere(
              (acc) => acc['type'] == 'wallet',
              orElse: () => _accounts.first,
            );
            _selectedAccountId = defaultWallet['id']?.toString();
          }
          _isInitLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInitLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _saveIncome() async {
    if (!_formKey.currentState!.validate() || _selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields correctly')));
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final description = _sourceController.text.trim();
    final userId = _supabase.auth.currentUser?.id;

    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final double commitmentAmount = amount * (_savingsPercentage / 100);
      final isoDate = _selectedDate.toIso8601String();

      // SMART LINKING: Check if typed text matches an existing category
      final matchedCat = _incomeCategories.where((c) => c['name'].toString().toLowerCase() == description.toLowerCase()).firstOrNull;
      final categoryId = matchedCat?['id'];
      final categoryName = matchedCat?['name'];

      // 1. Insert Transaction
      final transactionResponse = await _supabase
          .from('transactions')
          .insert({
            'user_id': userId,
            'type': 'income',
            'amount': amount,
            'description': description,
            'title': description.isNotEmpty ? description : 'Income',
            'category_id': categoryId, 
            'category': categoryName, 
            'date': isoDate,
            'account_id': int.tryParse(_selectedAccountId!) ?? _selectedAccountId,
          })
          .select('id')
          .single();

      // 2. Process side-effects concurrently (Commitment & Balance Update)
      final List<Future<dynamic>> parallelTasks = [];

      if (commitmentAmount > 0) {
        parallelTasks.add(
          _supabase.from('commitments').insert({
            'user_id': userId,
            'source_transaction_id': transactionResponse['id'],
            'amount': commitmentAmount,
            'status': 'pending',
          })
        );
      }

      final accountData = await _supabase
          .from('accounts')
          .select('current_balance')
          .eq('id', _selectedAccountId!)
          .single();

      final currentBal = (accountData['current_balance'] as num?)?.toDouble() ?? 0.0;
      parallelTasks.add(
        _supabase.from('accounts').update({'current_balance': currentBal + amount}).eq('id', _selectedAccountId!)
      );

      await Future.wait(parallelTasks);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Income logged successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Modern light background
      appBar: AppBar(
        title: const Text('Add Income', style: TextStyle(fontWeight: FontWeight.bold)),
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
      body: _isInitLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // --- MODERN AMOUNT DISPLAY CARD ---
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('INCOME AMOUNT', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _amountController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.green, letterSpacing: -1),
                                  decoration: InputDecoration(
                                    prefixText: '$_currencySymbol ',
                                    hintText: '0.00',
                                    border: InputBorder.none,
                                  ),
                                  validator: (val) {
                                    if (val == null || val.isEmpty) return 'Enter an amount';
                                    if (double.tryParse(val) == null || double.parse(val) <= 0) return 'Invalid amount';
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // --- INPUT FIELDS GROUP ---
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hybrid Source Text Field
                          TextFormField(
                            controller: _sourceController,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'Income Source',
                              hintText: 'Type or pick below',
                              labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                                child: const Icon(Icons.work_outline_rounded, color: Colors.green, size: 20),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Enter an income source' : null,
                          ),

                          // Quick Select Category Chips
                          if (_incomeCategories.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 38,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: _incomeCategories.length,
                                itemBuilder: (context, index) {
                                  final catName = _incomeCategories[index]['name']?.toString() ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        _sourceController.text = catName;
                                      },
                                      child: Container(
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.green.shade200, width: 1.5),
                                        ),
                                        child: Text(
                                          catName, 
                                          style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Account Dropdown
                          if (_accounts.isNotEmpty)
                            DropdownButtonFormField<String>(
                              value: _selectedAccountId,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                              decoration: InputDecoration(
                                labelText: 'Deposit To',
                                labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                                  child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.blue, size: 20),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              items: _accounts.map((acc) {
                                return DropdownMenuItem<String>(
                                  value: acc['id']?.toString(),
                                  child: Text(acc['name'] ?? 'Account', style: const TextStyle(fontWeight: FontWeight.bold)),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedAccountId = val),
                              validator: (val) => val == null ? 'Select an account' : null,
                            ),

                          const SizedBox(height: 16),

                          // Date Tile
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Colors.deepPurple)),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) setState(() => _selectedDate = picked);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.purple.shade50, shape: BoxShape.circle),
                                    child: const Icon(Icons.calendar_today_rounded, color: Colors.purple, size: 20),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Date', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                                        Text('${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.edit_calendar_rounded, color: Colors.grey),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // --- SAVE BUTTON ---
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 8,
                          shadowColor: Colors.green.withValues(alpha: 0.4),
                        ),
                        onPressed: _isLoading ? null : _saveIncome,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Save Income', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}