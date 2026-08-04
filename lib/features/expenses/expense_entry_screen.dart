import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/category_model.dart';
import '../../core/services/category_service.dart';
import 'itemization_screen.dart';

class ExpenseEntryScreen extends StatefulWidget {
  const ExpenseEntryScreen({super.key});

  @override
  State<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends State<ExpenseEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  final CategoryService _categoryService = CategoryService();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<CategoryModel> _categories = [];
  List<Map<String, dynamic>> _accounts = [];
  Map<String, double> _liveBalances = {};
  String _currencySymbol = '\$';

  CategoryModel? _selectedCategory;
  String? _selectedAccountId;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isInitLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialDataConcurrently();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // --- FAST CONCURRENT DATA LOADING (LEDGER MATH) ---
  Future<void> _loadInitialDataConcurrently() async {
    setState(() => _isInitLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // PERFORMANCE UPGRADE: Fetch all necessary data simultaneously
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select('currency_symbol').eq('id', userId).maybeSingle(),
        _categoryService.getCategories('expense'),
        _supabase.from('accounts').select('id, name, type').eq('user_id', userId).order('id'),
        _supabase.from('transactions').select('type, amount, account_id').eq('user_id', userId),
        _supabase.from('transfers').select('from_account_id, to_account_id, amount').eq('user_id', userId),
        _supabase.from('commitments').select('amount, transactions(account_id)').eq('user_id', userId).eq('status', 'deposited'),
      ]);

      final profileData = results[0] as Map<String, dynamic>?;
      final fetchedCategories = (results[1] as List<CategoryModel>?) ?? [];
      final accountsData = (results[2] as List<dynamic>?) ?? [];
      final txData = (results[3] as List<dynamic>?) ?? [];
      final transferData = (results[4] as List<dynamic>?) ?? [];
      final commitmentsData = (results[5] as List<dynamic>?) ?? [];

      Map<String, double> balances = {};
      final fetchedAccounts = List<Map<String, dynamic>>.from(accountsData);

      // Initialize base balances
      for (var acc in fetchedAccounts) {
        balances[acc['id'].toString()] = 0.0;
      }

      // Add/Subtract Transactions
      for (var tx in txData) {
        final acctId = tx['account_id']?.toString();
        if (acctId == null || !balances.containsKey(acctId)) continue;
        
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final type = tx['type']?.toString();

        if (type == 'income' || type == 'initial_balance') {
          balances[acctId] = (balances[acctId] ?? 0.0) + amt;
        } else if (type == 'expense') {
          balances[acctId] = (balances[acctId] ?? 0.0) - amt;
        }
      }

      // Add/Subtract Transfers
      for (var tr in transferData) {
        final amt = (tr['amount'] as num?)?.toDouble() ?? 0.0;
        final fromId = tr['from_account_id']?.toString();
        final toId = tr['to_account_id']?.toString();

        if (fromId != null && balances.containsKey(fromId)) balances[fromId] = (balances[fromId] ?? 0.0) - amt;
        if (toId != null && balances.containsKey(toId)) balances[toId] = (balances[toId] ?? 0.0) + amt;
      }

      // Deduct deposited commitments
      for (var c in commitmentsData) {
        final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
        final sourceTx = c['transactions'] as Map<String, dynamic>?;
        if (sourceTx != null && sourceTx['account_id'] != null) {
          final acctId = sourceTx['account_id'].toString();
          if (balances.containsKey(acctId)) balances[acctId] = (balances[acctId] ?? 0.0) - amt;
        }
      }

      if (mounted) {
        setState(() {
          _currencySymbol = profileData?['currency_symbol']?.toString() ?? '\$';
          _categories = fetchedCategories;
          _accounts = fetchedAccounts;
          _liveBalances = balances;

          if (_categories.isNotEmpty) {
            _selectedCategory = _categories.first;
          }
          if (_accounts.isNotEmpty) {
            _selectedAccountId = _accounts.first['id']?.toString();
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

  // --- TEMPLATE PICKER SHEET ---
  void _showTemplatePicker() async {
    HapticFeedback.lightImpact();
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final response = await _supabase.from('expense_templates').select().eq('user_id', userId);
    final templates = List<Map<String, dynamic>>.from(response);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Saved Templates', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black87)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (templates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No saved expense templates found.', style: TextStyle(color: Colors.grey, fontSize: 16))),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple.shade50,
                          child: const Icon(Icons.style_rounded, color: Colors.deepPurple, size: 20),
                        ),
                        title: Text(template['name'] ?? 'Unnamed', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text('${template['category'] ?? 'General'} • $_currencySymbol${template['amount'] ?? '0.00'}', style: TextStyle(color: Colors.grey.shade600)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                        onTap: () {
                          _applyTemplate(template);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _applyTemplate(Map<String, dynamic> template) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (template['amount'] != null) _amountController.text = template['amount'].toString();
      if (template['notes'] != null || template['name'] != null) {
        _noteController.text = template['notes'] ?? template['name'] ?? '';
      }
      if (_categories.isNotEmpty) {
        _selectedCategory = _categories.firstWhere(
          (c) => c.name.toLowerCase() == (template['category'] ?? '').toString().toLowerCase(),
          orElse: () => _categories.first,
        );
      }
      if (template['account_id'] != null) {
        _selectedAccountId = template['account_id'].toString();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Applied "${template['name'] ?? 'Template'}"'), backgroundColor: Colors.deepPurple),
    );
  }

  // --- SAVE TEMPLATE ---
  Future<void> _saveAsTemplate() async {
    HapticFeedback.lightImpact();
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a category first')));
      return;
    }

    final nameController = TextEditingController();
    final templateName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Save Template', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Template Name',
            hintText: 'e.g., Weekly Groceries',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (templateName != null && templateName.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final userId = _supabase.auth.currentUser?.id;
        if (userId == null) return;

        final amountVal = double.tryParse(_amountController.text) ?? 0.0;
        final noteVal = _noteController.text.trim();

        await _supabase.from('expense_templates').insert({
          'user_id': userId,
          'name': templateName,
          'category_id': _selectedCategory!.id,
          'category': _selectedCategory!.name,
          'amount': amountVal,
          'total_amount': amountVal,
          'account_id': _selectedAccountId,
          'notes': noteVal.isNotEmpty ? noteVal : null,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Template "$templateName" saved!'), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _openItemizationScreen() async {
    HapticFeedback.lightImpact();
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a category first')));
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemizationScreen(
          categoryId: _selectedCategory!.id,
          categoryName: _selectedCategory!.name,
          existingBreakdown: _noteController.text,
          // currencySymbol removed to fix LSP Error 'undefined_named_parameter'
        ),
      ),
    );

    if (result != null && result is Map) {
      final calculatedTotal = result['total'] as double;
      final breakdownText = result['breakdown'] as String;

      if (calculatedTotal > 0) {
        setState(() {
          _amountController.text = calculatedTotal.toStringAsFixed(2);

          String noteText = _noteController.text;
          if (noteText.contains('Itemized Breakdown:')) {
            noteText = noteText.split('Itemized Breakdown:')[0].trim();
          }

          if (breakdownText.isNotEmpty) {
            _noteController.text = noteText.isEmpty
                ? "Itemized Breakdown:\n$breakdownText"
                : "$noteText\n\nItemized Breakdown:\n$breakdownText";
          } else {
            _noteController.text = noteText;
          }
        });
      }
    }
  }

  Future<void> _submitExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a category')));
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw 'User unauthenticated';

      final amount = double.parse(_amountController.text);
      final noteText = _noteController.text.trim();
      final isoDate = _selectedDate.toIso8601String();

      // 1. STRICT LIVE BALANCE CHECK (Uses the concurrent map math)
      if (_selectedAccountId != null) {
        final double fromBal = _liveBalances[_selectedAccountId!] ?? 0.0;
        final fromAcc = _accounts.firstWhere((acc) => acc['id'].toString() == _selectedAccountId, orElse: () => {});
        final String accountName = fromAcc['name']?.toString() ?? 'Selected Account';

        if (fromBal < amount) {
          setState(() => _isLoading = false);
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                    SizedBox(width: 12),
                    Text('Insufficient Funds', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                content: Text('Cannot record expense of $_currencySymbol${amount.toStringAsFixed(2)}.\n\n"$accountName" currently only has a balance of $_currencySymbol${fromBal.toStringAsFixed(2)}.'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)))],
              ),
            );
          }
          return; // Abort
        }
      }

      // 2. Insert safely concurrently
      await Future.wait([
        _supabase.from('expenses').insert({
          'user_id': userId,
          'amount': amount,
          'category_id': _selectedCategory!.id,
          'category': _selectedCategory!.name,
          'category_name': _selectedCategory!.name,
          'account_id': _selectedAccountId,
          'title': noteText.isNotEmpty ? noteText : _selectedCategory!.name,
          'description': noteText,
          'note': noteText,
          'date': isoDate,
        }),
        _supabase.from('transactions').insert({
          'user_id': userId,
          'amount': amount,
          'type': 'expense',
          'category': _selectedCategory!.name,
          'category_id': _selectedCategory!.id,
          'account_id': _selectedAccountId != null ? int.tryParse(_selectedAccountId!) ?? _selectedAccountId : null,
          'title': noteText.isNotEmpty ? noteText : _selectedCategory!.name,
          'description': noteText,
          'date': isoDate,
        }),
      ]);

      // 3. Fallback schema update (Safety fallback)
      if (_selectedAccountId != null) {
        final accountData = await _supabase.from('accounts').select('current_balance').eq('id', _selectedAccountId!).single();
        final currentBal = (accountData['current_balance'] as num?)?.toDouble() ?? 0.0;
        await _supabase.from('accounts').update({'current_balance': currentBal - amount}).eq('id', _selectedAccountId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense logged successfully!'), backgroundColor: Colors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Modern Background
      appBar: AppBar(
        title: const Text('Log Expense', style: TextStyle(fontWeight: FontWeight.bold)),
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
        actions: [
          IconButton(icon: const Icon(Icons.bookmark_add_rounded), tooltip: 'Save Template', onPressed: _saveAsTemplate),
          IconButton(icon: const Icon(Icons.style_rounded), tooltip: 'Apply Template', onPressed: _showTemplatePicker),
        ],
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
                          const Text('ENTER AMOUNT', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _amountController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.redAccent, letterSpacing: -1),
                                  decoration: InputDecoration(
                                    prefixText: '$_currencySymbol ',
                                    hintText: '0.00',
                                    border: InputBorder.none,
                                  ),
                                  validator: (val) {
                                    if (val == null || val.isEmpty) return 'Enter an amount';
                                    if (double.tryParse(val) == null) return 'Invalid number';
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _openItemizationScreen,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.receipt_long_rounded, color: Colors.deepPurple.shade700, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Itemize Receipt', style: TextStyle(color: Colors.deepPurple.shade700, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          )
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
                        children: [
                          // Category Dropdown
                          DropdownButtonFormField<CategoryModel>(
                            initialValue: _selectedCategory,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                            decoration: InputDecoration(
                              labelText: 'Category',
                              labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                                child: const Icon(Icons.category_rounded, color: Colors.orange, size: 20),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                            onChanged: (val) => setState(() => _selectedCategory = val),
                            validator: (val) => val == null ? 'Select category' : null,
                          ),

                          const SizedBox(height: 16),

                          // Account Dropdown
                          if (_accounts.isNotEmpty)
                            DropdownButtonFormField<String>(
                              initialValue: _selectedAccountId,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                              decoration: InputDecoration(
                                labelText: 'Account',
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
                                final double bal = _liveBalances[acc['id'].toString()] ?? 0.0;
                                return DropdownMenuItem<String>(
                                  value: acc['id']?.toString(), 
                                  child: Text('${acc['name']} ($_currencySymbol${bal.toStringAsFixed(2)})', style: const TextStyle(fontWeight: FontWeight.bold))
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedAccountId = val),
                            ),

                          const SizedBox(height: 16),

                          // Notes Field
                          TextFormField(
                            controller: _noteController,
                            minLines: 1,
                            maxLines: 4,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'Notes / Description',
                              labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.teal.shade50, shape: BoxShape.circle),
                                child: const Icon(Icons.notes_rounded, color: Colors.teal, size: 20),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
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
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 8,
                          shadowColor: Colors.deepPurple.withValues(alpha: 0.4),
                        ),
                        onPressed: _isLoading ? null : _submitExpense,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Save Expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}