import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _fetchAccountsAndLiveBalances();
  }

  // --- FAST CONCURRENT DATA LOADING WITH OFFLINE PROTECTION ---
  Future<void> _fetchAccountsAndLiveBalances() async {
    setState(() { _isLoading = true; _isOffline = false; });
    
    // 1. OFFLINE CHECK
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted) setState(() { _isLoading = false; _isOffline = true; });
      return;
    }

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final results = await Future.wait<dynamic>([
        _supabase.from('accounts').select('id, name, type').eq('user_id', userId).order('id'),
        _supabase.from('transactions').select('type, amount, account_id').eq('user_id', userId),
        _supabase.from('transfers').select('from_account_id, to_account_id, amount').eq('user_id', userId),
        _supabase.from('commitments').select('amount, transactions(account_id)').eq('user_id', userId).eq('status', 'deposited'),
      ]);

      final fetchedAccounts = List<Map<String, dynamic>>.from(results[0] ?? []);
      final txResponse = (results[1] as List<dynamic>?) ?? [];
      final transferResponse = (results[2] as List<dynamic>?) ?? [];
      final commitmentsResponse = (results[3] as List<dynamic>?) ?? [];

      Map<String, double> balances = {};
      
      for (var acc in fetchedAccounts) {
        balances[acc['id'].toString()] = 0.0;
      }

      for (var tx in txResponse) {
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

      for (var tr in transferResponse) {
        final amt = (tr['amount'] as num?)?.toDouble() ?? 0.0;
        final fromId = tr['from_account_id']?.toString();
        final toId = tr['to_account_id']?.toString();

        if (fromId != null && balances.containsKey(fromId)) {
          balances[fromId] = (balances[fromId] ?? 0.0) - amt;
        }
        if (toId != null && balances.containsKey(toId)) {
          balances[toId] = (balances[toId] ?? 0.0) + amt;
        }
      }

      for (var c in commitmentsResponse) {
        final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
        final sourceTx = c['transactions'] as Map<String, dynamic>?;
        if (sourceTx != null && sourceTx['account_id'] != null) {
          final acctId = sourceTx['account_id'].toString();
          if (balances.containsKey(acctId)) {
            balances[acctId] = (balances[acctId] ?? 0.0) - amt;
          }
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
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching accounts: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _showNewAccountSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddAccountSheet(
        onSave: (String name, double initialBal, String type) async {
          final connectivityResult = await Connectivity().checkConnectivity();
          if (connectivityResult.contains(ConnectivityResult.none)) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No internet connection. Cannot create account.'), backgroundColor: Colors.orange));
            return;
          }

          setState(() => _isLoading = true);
          try {
            final userId = _supabase.auth.currentUser?.id;
            if (userId == null) throw Exception("User not authenticated");

            // 1. Create Account First
            final newAcc = await _supabase.from('accounts').insert({
              'user_id': userId,
              'name': name,
              'type': type,
              'current_balance': initialBal, 
            }).select().single();

            // 2. Log Initial Balance Transaction if applicable
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Account "$name" created!'), backgroundColor: Colors.green),
              );
              _fetchAccountsAndLiveBalances();
            }
          } catch (e) {
            if (mounted) {
              setState(() => _isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
              );
            }
          }
        },
      ),
    );
  }

  // --- OFFLINE UI BUILDER ---
  Widget _buildOfflineState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('You are offline', style: TextStyle(color: Colors.grey.shade800, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Please check your connection and try again.', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchAccountsAndLiveBalances,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry Connection'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalAllAccounts = _liveBalances.values.fold(0.0, (sum, bal) => sum + bal);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text('Accounts', style: TextStyle(fontWeight: FontWeight.bold)),
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
      floatingActionButton: _isOffline ? null : FloatingActionButton.extended(
        onPressed: _showNewAccountSheet,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Account', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isOffline 
        ? _buildOfflineState()
        : _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : RefreshIndicator(
              onRefresh: _fetchAccountsAndLiveBalances,
              color: Colors.deepPurple,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  // --- HEADER METRIC ---
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2E0854), Color(0xFF5D12D6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Liquidity', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                              SizedBox(height: 4),
                              Text('Across all accounts', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                          Text(
                            '\$${totalAllAccounts.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- MODERN TRANSFER BANNER ---
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.blue.shade700, Colors.blue.shade500],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                                  child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 28),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Internal Transfer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                                      SizedBox(height: 4),
                                      Text('Move money between wallets', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.blue.shade700,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    elevation: 0,
                                  ),
                                  onPressed: () async {
                                    HapticFeedback.lightImpact();
                                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const TransferScreen()));
                                    _fetchAccountsAndLiveBalances();
                                  },
                                  child: const Text('Move', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                          const Text('Your Accounts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                          const SizedBox(height: 12),

                          if (_accounts.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Column(
                                  children: [
                                    Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey[300]),
                                    const SizedBox(height: 16),
                                    Text('No accounts found.', style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
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
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  elevation: 0,
                                  color: Colors.white,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    leading: CircleAvatar(
                                      radius: 26,
                                      backgroundColor: isBank ? Colors.blue.shade50 : Colors.green.shade50,
                                      child: Icon(
                                        isBank ? Icons.account_balance_rounded : Icons.account_balance_wallet_rounded,
                                        color: isBank ? Colors.blue.shade700 : Colors.green.shade700,
                                        size: 24,
                                      ),
                                    ),
                                    title: Text(
                                      acc['name'] ?? 'Account',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                    ),
                                    subtitle: Text(
                                      isBank ? 'Bank Account' : 'Cash / Wallet',
                                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
                                    trailing: Text(
                                      '\$${balance.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                        color: balance < 0 ? Colors.redAccent : Colors.deepPurple,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 80), 
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ----------------------------------------------------------------------
// PERFORMANCE FIX: Localized Stateful Widget for Add Account BottomSheet
// Prevents the main screen from rebuilding on every keystroke
// ----------------------------------------------------------------------
class _AddAccountSheet extends StatefulWidget {
  final Function(String name, double initialBal, String type) onSave;

  const _AddAccountSheet({required this.onSave});

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  String _selectedType = 'bank';

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  void _submit() {
    HapticFeedback.lightImpact();
    final name = _nameController.text.trim();
    
    // FLOATING POINT MATH FIX: Strict 2-decimal truncation
    final rawBal = double.tryParse(_balanceController.text) ?? 0.0;
    final initialBal = double.parse(rawBal.toStringAsFixed(2));
    
    if (name.isNotEmpty) {
      Navigator.pop(context); 
      widget.onSave(name, initialBal, _selectedType);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 24),
            const Text('Create New Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black87)),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Account Name',
                hintText: 'e.g. Chase Checking',
                prefixIcon: const Icon(Icons.account_balance_rounded, color: Colors.deepPurple),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Initial Balance',
                prefixIcon: const Icon(Icons.attach_money_rounded, color: Colors.deepPurple),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedType,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
              decoration: InputDecoration(
                labelText: 'Account Type',
                prefixIcon: const Icon(Icons.category_rounded, color: Colors.deepPurple),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
              items: const [
                DropdownMenuItem(value: 'bank', child: Text('Bank Account', style: TextStyle(fontWeight: FontWeight.bold))),
                DropdownMenuItem(value: 'wallet', child: Text('Cash / Wallet', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedType = val);
              },
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 4,
                  shadowColor: Colors.deepPurple.withOpacity(0.3),
                ),
                onPressed: _submit,
                child: const Text('Add Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}