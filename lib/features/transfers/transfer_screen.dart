import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isInitLoading = true;

  List<Map<String, dynamic>> _accounts = [];
  Map<String, double> _liveBalances = {};
  String? _fromAccountId;
  String? _toAccountId;
  String _currencySymbol = '\$';

  @override
  void initState() {
    super.initState();
    _loadInitialDataConcurrently();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // --- FAST CONCURRENT DATA LOADING (LEDGER MATH) ---
  Future<void> _loadInitialDataConcurrently() async {
    setState(() => _isInitLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // PERFORMANCE UPGRADE: Fetch everything simultaneously
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select('currency_symbol').eq('id', userId).maybeSingle(),
        _supabase.from('accounts').select('id, name, type').eq('user_id', userId).order('id'),
        _supabase.from('transactions').select('type, amount, account_id').eq('user_id', userId),
        _supabase.from('transfers').select('from_account_id, to_account_id, amount').eq('user_id', userId),
        _supabase.from('commitments').select('amount, transactions(account_id)').eq('user_id', userId).eq('status', 'deposited'),
      ]);

      final profileData = results[0] as Map<String, dynamic>?;
      final accountsData = (results[1] as List<dynamic>?) ?? [];
      final txData = (results[2] as List<dynamic>?) ?? [];
      final transferData = (results[3] as List<dynamic>?) ?? [];
      final commitmentsData = (results[4] as List<dynamic>?) ?? [];

      Map<String, double> balances = {};
      final fetchedAccounts = List<Map<String, dynamic>>.from(accountsData);

      // Initialize base balances to 0
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
          _accounts = fetchedAccounts;
          _liveBalances = balances;

          // Auto-select first two accounts if available
          if (_accounts.length >= 2) {
            _fromAccountId = _accounts[0]['id'].toString();
            _toAccountId = _accounts[1]['id'].toString();
          } else if (_accounts.isNotEmpty) {
            _fromAccountId = _accounts[0]['id'].toString();
          }
          _isInitLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInitLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load accounts: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _executeTransfer() async {
    if (!_formKey.currentState!.validate()) return;

    if (_fromAccountId == null || _toAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select both From and To accounts')));
      return;
    }

    if (_fromAccountId == _toAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You cannot transfer money to the same account!')));
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount greater than 0')));
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);
    
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. STRICT LIVE BALANCE CHECK
      final double fromBal = _liveBalances[_fromAccountId!] ?? 0.0;
      final fromAcc = _accounts.firstWhere((acc) => acc['id'].toString() == _fromAccountId);
      final String fromAccName = fromAcc['name']?.toString() ?? 'Source Account';

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
              content: Text('Cannot transfer $_currencySymbol${amount.toStringAsFixed(2)}.\n\n"$fromAccName" currently only has a balance of $_currencySymbol${fromBal.toStringAsFixed(2)}.'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)))],
            ),
          );
        }
        return; // Abort transfer
      }

      // 2. Execute Transfer (and optionally update the legacy fallback column concurrently)
      await Future.wait([
        _supabase.from('transfers').insert({
          'user_id': userId,
          'from_account_id': int.parse(_fromAccountId!),
          'to_account_id': int.parse(_toAccountId!),
          'amount': amount,
          'date': _selectedDate.toIso8601String(),
        }),
        // Legacy fallback updates to prevent other un-updated screens from completely breaking
        _supabase.from('accounts').update({'current_balance': fromBal - amount}).eq('id', _fromAccountId!),
        _supabase.from('accounts').update({'current_balance': (_liveBalances[_toAccountId!] ?? 0.0) + amount}).eq('id', _toAccountId!),
      ]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer executed successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transfer failed: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Modern light background
      appBar: AppBar(
        title: const Text('Internal Transfer', style: TextStyle(fontWeight: FontWeight.bold)),
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
          : _accounts.length < 2
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
                          child: Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey[300]),
                        ),
                        const SizedBox(height: 24),
                        const Text('Not enough accounts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black87)),
                        const SizedBox(height: 12),
                        const Text(
                          'You need at least two accounts (e.g., Wallet and a Bank Account) to perform a transfer.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500, height: 1.5),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.deepPurple,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            elevation: 0,
                            side: const BorderSide(color: Colors.deepPurple),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Go Back', style: TextStyle(fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),
                )
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
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('TRANSFER AMOUNT', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _amountController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.blueAccent, letterSpacing: -1),
                                      decoration: InputDecoration(
                                        prefixText: '$_currencySymbol ',
                                        hintText: '0.00',
                                        border: InputBorder.none,
                                      ),
                                      validator: (val) {
                                        if (val == null || val.isEmpty) return 'Enter an amount';
                                        if (double.tryParse(val) == null || double.parse(val!) <= 0) return 'Invalid amount';
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
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
                          ),
                          child: Column(
                            children: [
                              // Source Account
                              DropdownButtonFormField<String>(
                                value: _fromAccountId,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                                decoration: InputDecoration(
                                  labelText: 'From Account (Source)',
                                  labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                                  prefixIcon: Container(
                                    margin: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                                    child: const Icon(Icons.outbound_rounded, color: Colors.redAccent, size: 20),
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                items: _accounts.map((acc) {
                                  final double bal = _liveBalances[acc['id'].toString()] ?? 0.0;
                                  return DropdownMenuItem<String>(
                                    value: acc['id'].toString(),
                                    child: Text(
                                      '${acc['name']} ($_currencySymbol${bal.toStringAsFixed(2)})', 
                                      style: const TextStyle(fontWeight: FontWeight.bold)
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _fromAccountId = val),
                              ),

                              // Flow Indicator
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16.0),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                                  child: const Icon(Icons.arrow_downward_rounded, color: Colors.blueAccent, size: 24),
                                ),
                              ),

                              // Destination Account
                              DropdownButtonFormField<String>(
                                value: _toAccountId,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                                decoration: InputDecoration(
                                  labelText: 'To Account (Destination)',
                                  labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                                  prefixIcon: Container(
                                    margin: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                                    child: const Icon(Icons.move_to_inbox_rounded, color: Colors.green, size: 20),
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                items: _accounts.map((acc) {
                                  final double bal = _liveBalances[acc['id'].toString()] ?? 0.0;
                                  return DropdownMenuItem<String>(
                                    value: acc['id'].toString(),
                                    child: Text(
                                      '${acc['name']} ($_currencySymbol${bal.toStringAsFixed(2)})', 
                                      style: const TextStyle(fontWeight: FontWeight.bold)
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _toAccountId = val),
                              ),

                              const SizedBox(height: 24),

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
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 8,
                              shadowColor: Colors.blueAccent.withOpacity(0.4),
                            ),
                            onPressed: _isLoading ? null : _executeTransfer,
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Confirm Transfer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}