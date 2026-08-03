import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

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
  bool _isLoading = true;
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _accounts = [];
  dynamic _fromAccountId;
  dynamic _toAccountId;
  String _currencySymbol = '\$';

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // 1. Fetch Currency Symbol
      final profileData = await _supabase
          .from('profiles')
          .select() // Safe select
          .eq('id', userId)
          .maybeSingle();

      if (profileData != null && profileData['currency_symbol'] != null) {
        _currencySymbol = profileData['currency_symbol'].toString();
      }

      // 2. Fetch Accounts
      final data = await _supabase
          .from('accounts')
          .select() // Safe select
          .eq('user_id', userId)
          .order('id', ascending: true);

      if (mounted) {
        setState(() {
          _accounts = List<Map<String, dynamic>>.from(data);
          if (_accounts.length >= 2) {
            _fromAccountId = _accounts[0]['id'];
            _toAccountId = _accounts[1]['id'];
          } else if (_accounts.isNotEmpty) {
            _fromAccountId = _accounts[0]['id'];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading accounts: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _executeTransfer() async {
    if (!_formKey.currentState!.validate()) return;

    if (_fromAccountId == null || _toAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both From and To accounts')),
      );
      return;
    }

    if (_fromAccountId.toString() == _toAccountId.toString()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot transfer money to the same account!')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount greater than 0')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final userId = _supabase.auth.currentUser?.id;

    if (userId == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    try {
      // 1. STRICT BALANCE CHECK using SAFE select()
      final fromAccFresh = await _supabase
          .from('accounts')
          .select() // Safe select - grabs whatever columns exist
          .eq('id', _fromAccountId)
          .single();

      final toAccFresh = await _supabase
          .from('accounts')
          .select() // Safe select
          .eq('id', _toAccountId)
          .single();

      final double fromBal = ((fromAccFresh['current_balance'] ?? fromAccFresh['balance']) as num?)?.toDouble() ?? 0.0;
      final double toBal = ((toAccFresh['current_balance'] ?? toAccFresh['balance']) as num?)?.toDouble() ?? 0.0;
      final String fromAccName = fromAccFresh['name']?.toString() ?? 'Selected Account';

      if (fromBal < amount) {
        setState(() => _isSubmitting = false);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Insufficient Funds'),
                ],
              ),
              content: Text(
                'Cannot transfer $_currencySymbol${amount.toStringAsFixed(2)}.\n\n"$fromAccName" only has an available balance of $_currencySymbol${fromBal.toStringAsFixed(2)}.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return; // Abort transfer
      }

      // 2. Record Transfer History
      await _supabase.from('transfers').insert({
        'user_id': userId,
        'from_account_id': _fromAccountId,
        'to_account_id': _toAccountId,
        'amount': amount,
        'date': _selectedDate.toIso8601String(),
      });

      // 3. Deduct from Source Account
      await _supabase
          .from('accounts')
          .update({'current_balance': fromBal - amount})
          .eq('id', _fromAccountId);

      // 4. Add to Destination Account
      await _supabase
          .from('accounts')
          .update({'current_balance': toBal + amount})
          .eq('id', _toAccountId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transfer executed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Internal Transfer'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.length < 2
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined, size: 80, color: Colors.grey),
                        const SizedBox(height: 20),
                        const Text(
                          'Not enough accounts',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'You need at least two accounts (e.g., Wallet and a Bank Account) to perform a transfer.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Go Back'),
                        )
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // FROM ACCOUNT CARD
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: DropdownButtonFormField<dynamic>(
                              value: _fromAccountId,
                              decoration: const InputDecoration(
                                labelText: 'From Account (Source)',
                                prefixIcon: Icon(Icons.outbound, color: Colors.redAccent),
                                border: InputBorder.none,
                              ),
                              items: _accounts.map((acc) {
                                final double bal = ((acc['current_balance'] ?? acc['balance']) as num?)?.toDouble() ?? 0.0;
                                return DropdownMenuItem<dynamic>(
                                  value: acc['id'],
                                  child: Text('${acc['name']} ($_currencySymbol${bal.toStringAsFixed(2)})'),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _fromAccountId = val),
                            ),
                          ),
                        ),

                        // ARROW INDICATOR
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_downward_rounded, color: Colors.deepPurple, size: 32),
                          ),
                        ),

                        // TO ACCOUNT CARD
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: DropdownButtonFormField<dynamic>(
                              value: _toAccountId,
                              decoration: const InputDecoration(
                                labelText: 'To Account (Destination)',
                                prefixIcon: Icon(Icons.move_to_inbox, color: Colors.green),
                                border: InputBorder.none,
                              ),
                              items: _accounts.map((acc) {
                                final double bal = ((acc['current_balance'] ?? acc['balance']) as num?)?.toDouble() ?? 0.0;
                                return DropdownMenuItem<dynamic>(
                                  value: acc['id'],
                                  child: Text('${acc['name']} ($_currencySymbol${bal.toStringAsFixed(2)})'),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _toAccountId = val),
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),

                        // AMOUNT INPUT
                        TextFormField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            labelText: 'Transfer Amount',
                            prefixText: '$_currencySymbol ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Enter an amount';
                            final val = double.tryParse(value);
                            if (val == null || val <= 0) return 'Enter a valid amount';
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        // DATE PICKER
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.calendar_today, color: Colors.deepPurple),
                            title: const Text('Date of Transfer', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            subtitle: Text(
                              DateFormat.yMMMMd().format(_selectedDate),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            trailing: const Icon(Icons.edit, size: 20),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: Colors.deepPurple,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                              }
                            },
                          ),
                        ),

                        const SizedBox(height: 40),

                        // SUBMIT BUTTON
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _executeTransfer,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text(
                                    'Confirm Transfer',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}