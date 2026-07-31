import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _amountController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  List<Map<String, dynamic>> _accounts = [];
  int? _fromAccountId;
  int? _toAccountId;

  @override
  void initState() {
    super.initState();
    _fetchAccounts();
  }

  Future<void> _fetchAccounts() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client.from('accounts').select().eq('user_id', userId);
    
    setState(() {
      _accounts = List<Map<String, dynamic>>.from(data);
      if (_accounts.length >= 2) {
        // Smart defaults: First is From, Second is To
        _fromAccountId = _accounts[0]['id'];
        _toAccountId = _accounts[1]['id'];
      } else if (_accounts.isNotEmpty) {
         _fromAccountId = _accounts[0]['id'];
      }
    });
  }

  Future<void> _saveTransfer() async {
    if (_amountController.text.isEmpty || _fromAccountId == null || _toAccountId == null) return;
    if (_fromAccountId == _toAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot transfer to same account')));
      return;
    }

    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;

    try {
      await Supabase.instance.client.from('transfers').insert({
        'user_id': userId,
        'from_account_id': _fromAccountId,
        'to_account_id': _toAccountId,
        'amount': double.parse(_amountController.text),
        'date': _selectedDate.toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transfer Successful!')));
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
      appBar: AppBar(title: const Text('Transfer / Withdraw')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // FROM Account
            DropdownButtonFormField<int>(
              value: _fromAccountId,
              decoration: const InputDecoration(labelText: 'From Account', border: OutlineInputBorder()),
              items: _accounts.map((acc) {
                return DropdownMenuItem<int>(
                  value: acc['id'],
                  child: Text(acc['name']),
                );
              }).toList(),
              onChanged: (val) => setState(() => _fromAccountId = val),
            ),
            const SizedBox(height: 20),

            // Arrow Icon
            const Icon(Icons.arrow_downward, size: 30, color: Colors.blueGrey),
            const SizedBox(height: 20),

            // TO Account
            DropdownButtonFormField<int>(
              value: _toAccountId,
              decoration: const InputDecoration(labelText: 'To Account', border: OutlineInputBorder()),
              items: _accounts.map((acc) {
                return DropdownMenuItem<int>(
                  value: acc['id'],
                  child: Text(acc['name']),
                );
              }).toList(),
              onChanged: (val) => setState(() => _toAccountId = val),
            ),
            const SizedBox(height: 20),

            // Amount
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Date
            ListTile(
              title: Text('Date: ${DateFormat.yMMMd().format(_selectedDate)}'),
              trailing: const Icon(Icons.calendar_today),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.grey)),
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveTransfer,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                child: _isLoading ? const CircularProgressIndicator() : const Text('Confirm Transfer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}