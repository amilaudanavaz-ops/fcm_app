import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../transfers/transfer_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _accounts = [];
  Map<String, double> _liveBalances = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAccountsAndLiveBalances();
  }

  Future<void> _fetchAccountsAndLiveBalances() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // 1. Fetch Accounts
      final accResponse = await _supabase
          .from('accounts')
          .select()
          .eq('user_id', userId);
      final fetchedAccounts = List<Map<String, dynamic>>.from(accResponse);

      // 2. Fetch Transactions (Income, Expense, Initial Balance)
      final txResponse = await _supabase
          .from('transactions')
          .select('type, amount, account_id')
          .eq('user_id', userId);

      // 3. Fetch Transfers
      final transferResponse = await _supabase
          .from('transfers')
          .select('from_account_id, to_account_id, amount')
          .eq('user_id', userId);

      // 4. Fetch Commitments
      final commitmentsResponse = await _supabase
          .from('commitments')
          .select('amount, transactions(account_id)')
          .eq('user_id', userId)
          .eq('status', 'deposited');

      Map<String, double> balances = {};

      // Initialize all accounts to 0
      for (var acc in fetchedAccounts) {
        balances[acc['id'].toString()] = 0.0;
      }

      // Add/Subtract Transactions
      for (var tx in txResponse) {
        final acctId = tx['account_id']?.toString();
        if (acctId == null) continue;
        
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final type = tx['type']?.toString();

        if (type == 'income' || type == 'initial_balance') {
          balances[acctId] = (balances[acctId] ?? 0.0) + amt;
        } else if (type == 'expense') {
          balances[acctId] = (balances[acctId] ?? 0.0) - amt;
        }
      }

      // Add/Subtract Transfers
      for (var tr in transferResponse) {
        final amt = (tr['amount'] as num?)?.toDouble() ?? 0.0;
        final fromId = tr['from_account_id']?.toString();
        final toId = tr['to_account_id']?.toString();

        if (fromId != null) balances[fromId] = (balances[fromId] ?? 0.0) - amt;
        if (toId != null) balances[toId] = (balances[toId] ?? 0.0) + amt;
      }

      // Subtract deposited commitments from source accounts
      for (var c in commitmentsResponse) {
        final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
        final sourceTx = c['transactions'] as Map<String, dynamic>?;
        if (sourceTx != null && sourceTx['account_id'] != null) {
          final acctId = sourceTx['account_id'].toString();
          balances[acctId] = (balances[acctId] ?? 0.0) - amt;
        }
      }

      if (mounted) {
        setState(() {
          _accounts = fetchedAccounts;
          _liveBalances = balances;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error fetching account management balances: $e');
    }
  }

  void _showNewAccountDialog() {
    final nameController = TextEditingController();
    final balanceController = TextEditingController();
    String selectedType = 'bank';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Account Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: balanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Initial Balance (\$)', prefixText: '\$ '),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'bank', child: Text('Bank Account')),
                  DropdownMenuItem(value: 'wallet', child: Text('Cash / Wallet')),
                ],
                onChanged: (val) => setDialogState(() => selectedType = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final initialBal = double.tryParse(balanceController.text) ?? 0.0;
                if (name.isEmpty) return;

                final userId = _supabase.auth.currentUser?.id;
                if (userId != null) {
                  final newAcc = await _supabase.from('accounts').insert({
                    'user_id': userId,
                    'name': name,
                    'type': selectedType,
                    'current_balance': initialBal,
                  }).select().single();

                  if (initialBal > 0) {
                    await _supabase.from('transactions').insert({
                      'user_id': userId,
                      'account_id': newAcc['id'],
                      'type': 'initial_balance',
                      'amount': initialBal,
                      'title': 'Initial Balance',
                      'date': DateTime.now().toIso8601String(),
                    });
                  }

                  if (mounted) {
                    Navigator.pop(ctx);
                    _fetchAccountsAndLiveBalances();
                  }
                }
              },
              child: const Text('Add Account'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Management'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewAccountDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Account'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Internal Transfer',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const TransferScreen()),
                                  );
                                  _fetchAccountsAndLiveBalances();
                                },
                                icon: const Icon(Icons.swap_horiz, size: 16),
                                label: const Text('Transfer Now', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Move money between wallet & bank accounts',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_accounts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('No accounts created yet.')),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _accounts.length,
                      itemBuilder: (context, index) {
                        final acc = _accounts[index];
                        final idStr = acc['id'].toString();
                        final isBank = acc['type'] == 'bank';
                        final double balance = _liveBalances[idStr] ?? 0.0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundColor: isBank ? Colors.blue.shade100 : Colors.green.shade100,
                              child: Icon(
                                isBank ? Icons.account_balance : Icons.account_balance_wallet,
                                color: isBank ? Colors.blue.shade800 : Colors.green.shade800,
                              ),
                            ),
                            title: Text(
                              acc['name'] ?? 'Account',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            subtitle: Text(
                              isBank ? 'Bank Account' : 'Cash on hand',
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            trailing: Text(
                              '\$${balance.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: balance < 0 ? Colors.red : Colors.grey.shade900,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}