import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../transfers/transfer_screen.dart'; // Import Transfer Screen

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _nameController = TextEditingController();
  final _initialBalanceController = TextEditingController(); 
  List<Map<String, dynamic>> _accounts = [];
  bool _isLoading = true;
  String _currencySymbol = '\$'; // NEW: Default Currency Symbol

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // NEW: Combined data load function
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
    try {
      final data = await Supabase.instance.client.from('accounts').select().eq('user_id', userId).order('created_at');
      if(mounted) setState(() { _accounts = List<Map<String, dynamic>>.from(data); _isLoading = false; });
    } catch (e) {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addAccount(String name, String type, double initialBalance) async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    
    // 1. Insert the new account
    final newAccount = await Supabase.instance.client.from('accounts').insert({
      'user_id': userId, 
      'name': name, 
      'type': type
    }).select().single();
    final newAccountId = newAccount['id'];

    // 2. Insert the initial balance as a transaction
    if (initialBalance > 0) {
      await Supabase.instance.client.from('transactions').insert({
        'user_id': userId,
        'type': 'initial_balance', 
        'amount': initialBalance,
        'account_id': newAccountId,
        'date': DateTime.now().toIso8601String(),
        'description': 'Initial Balance entry for new account',
      });
    }

    _nameController.clear();
    _initialBalanceController.clear(); 
    Navigator.pop(context);
    _fetchAccounts();
  }

  void _showAddDialog() {
    String selectedType = 'bank';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Account Name')),
                const SizedBox(height: 10),
                // UPDATED INPUT: Use dynamic currency symbol for prefix
                TextField(
                  controller: _initialBalanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Initial Balance', 
                    prefixText: '$_currencySymbol ', // USE DYNAMIC SYMBOL
                    hintText: '0.00'
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButton<String>(
                  value: selectedType,
                  isExpanded: true,
                  items: const [DropdownMenuItem(value: 'bank', child: Text('Bank Account')), DropdownMenuItem(value: 'wallet', child: Text('Physical Wallet'))],
                  onChanged: (val) => setState(() => selectedType = val!),
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(onPressed: () { 
                if (_nameController.text.isNotEmpty) {
                  final initialBalance = double.tryParse(_initialBalanceController.text) ?? 0.0;
                  _addAccount(_nameController.text, selectedType, initialBalance); 
                }
              }, child: const Text('Add')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Management')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        label: const Text('New Account'),
        icon: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // --- NEW TRANSFER SECTION ---
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).primaryColor.withOpacity(0.05),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Internal Transfer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Move money between wallet & banks', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransferScreen())).then((_) => _fetchAccounts()),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Transfer Now'),
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // --- ACCOUNT LIST ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _accounts.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final acc = _accounts[index];
                      final isWallet = acc['type'] == 'wallet';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isWallet ? Colors.green.shade100 : Colors.blue.shade100,
                            child: Icon(isWallet ? Icons.wallet : Icons.account_balance, color: isWallet ? Colors.green : Colors.blue),
                          ),
                          title: Text(acc['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(isWallet ? 'Cash on hand' : 'Bank Account'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}