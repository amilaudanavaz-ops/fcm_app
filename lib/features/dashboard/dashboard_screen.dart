import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../accounts/accounts_screen.dart';
import '../expenses/expense_entry_screen.dart';
import '../income/income_entry_screen.dart';
import '../transfers/transfer_screen.dart';
import '../reports/reports_screen.dart';
import '../savings/commitment_hub_screen.dart';
import '../settings/settings_screen.dart';
import '../auth/login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;

  String _currencySymbol = '\$';
  double _netWorth = 0.0;
  double _walletBalance = 0.0;
  double _bankBalance = 0.0;
  double _totalSaved = 0.0;
  double _expenseMTD = 0.0;
  double _pendingTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchDashboardMetrics();
  }

  Future<void> _fetchDashboardMetrics() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // PERFORMANCE UPGRADE: Concurrent DB calls via Future.wait
      final results = await Future.wait<dynamic>([
        Supabase.instance.client.from('profiles').select('currency_symbol').eq('id', userId).maybeSingle(),
        Supabase.instance.client.from('accounts').select('id, type').eq('user_id', userId),
        Supabase.instance.client.from('transactions').select('type, amount, account_id').eq('user_id', userId),
        Supabase.instance.client.from('expenses').select('amount, date').eq('user_id', userId),
        Supabase.instance.client.from('transfers').select('from_account_id, to_account_id, amount').eq('user_id', userId),
        Supabase.instance.client.from('commitments').select('amount, status, transactions(account_id)').eq('user_id', userId),
      ]);

      final profileData = results[0] as Map<String, dynamic>?;
      final accountsData = (results[1] as List<dynamic>?) ?? [];
      final txData = (results[2] as List<dynamic>?) ?? [];
      final expensesData = (results[3] as List<dynamic>?) ?? [];
      final transferData = (results[4] as List<dynamic>?) ?? [];
      final commitmentsData = (results[5] as List<dynamic>?) ?? [];

      final symbol = profileData?['currency_symbol']?.toString() ?? '\$';

      final Map<String, String> accountTypes = {
        for (var item in accountsData) item['id'].toString(): (item['type'] ?? 'wallet').toString()
      };

      double incomeWallet = 0, expenseWallet = 0;
      double incomeBank = 0, expenseBank = 0;
      double mtdExpense = 0;
      final now = DateTime.now();

      // MTD Expenses
      for (var exp in expensesData) {
        final amt = (exp['amount'] as num?)?.toDouble() ?? 0.0;
        final dateStr = exp['date']?.toString();
        if (dateStr != null) {
          final date = DateTime.tryParse(dateStr) ?? now;
          if (date.year == now.year && date.month == now.month) {
            mtdExpense += amt;
          }
        }
      }

      // Transactions Aggregation
      for (var tx in txData) {
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final acctId = tx['account_id']?.toString() ?? '';
        final acctType = accountTypes[acctId] ?? 'wallet';
        final type = tx['type']?.toString();

        if (type == 'income' || type == 'initial_balance') {
          if (acctType == 'wallet') incomeWallet += amt;
          if (acctType == 'bank') incomeBank += amt;
        } else if (type == 'expense') {
          if (acctType == 'wallet') expenseWallet += amt;
          if (acctType == 'bank') expenseBank += amt;
        }
      }

      // Transfers
      for (var tr in transferData) {
        final amt = (tr['amount'] as num?)?.toDouble() ?? 0.0;
        final fromType = accountTypes[tr['from_account_id']?.toString() ?? ''];
        final toType = accountTypes[tr['to_account_id']?.toString() ?? ''];

        if (fromType == 'wallet') incomeWallet -= amt;
        if (fromType == 'bank') incomeBank -= amt;
        if (toType == 'wallet') incomeWallet += amt;
        if (toType == 'bank') incomeBank += amt;
      }

      // Savings Commits
      double totalSaved = 0;
      double pending = 0;
      for (var s in commitmentsData) {
        final amt = (s['amount'] as num?)?.toDouble() ?? 0.0;
        final status = s['status']?.toString();
        
        if (status == 'deposited') {
          totalSaved += amt;
          final sourceTx = s['transactions'] as Map<String, dynamic>?;
          if (sourceTx != null && sourceTx['account_id'] != null) {
            final acctType = accountTypes[sourceTx['account_id'].toString()];
            if (acctType == 'wallet') incomeWallet -= amt;
            else if (acctType == 'bank') incomeBank -= amt;
          }
        } else if (status == 'pending') {
          pending += amt;
        }
      }

      // STRICT OVERRIDE: Force Dashboard to use the live ledger math
      final calculatedWallet = incomeWallet - expenseWallet;
      final calculatedBank = incomeBank - expenseBank;

      if (mounted) {
        setState(() {
          _currencySymbol = symbol;
          _walletBalance = calculatedWallet;
          _bankBalance = calculatedBank;
          _netWorth = _walletBalance + _bankBalance + totalSaved;
          _totalSaved = totalSaved;
          _pendingTotal = pending;
          _expenseMTD = mtdExpense;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dashboard Sync Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _logout() async {
    HapticFeedback.mediumImpact();
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  void _navigateTo(Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
        .then((_) => _fetchDashboardMetrics());
  }

  Widget _buildQuickActionButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildFlatCard({required String title, required String amount, required IconData icon, required Color iconColor, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade100, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(backgroundColor: iconColor.withOpacity(0.1), radius: 18, child: Icon(icon, color: iconColor, size: 20)),
              const SizedBox(height: 12),
              Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(amount, style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTile({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(color: subtitle.contains('Required') ? Colors.redAccent : Colors.grey.shade500, fontSize: 13)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : RefreshIndicator(
              onRefresh: _fetchDashboardMetrics,
              color: Colors.deepPurple,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverAppBar(
                    expandedHeight: 310.0,
                    floating: false,
                    pinned: true,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2E0854), Color(0xFF5D12D6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('TOTAL NET WORTH', style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text(
                                '$_currencySymbol${_netWorth.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold, letterSpacing: -1),
                              ),
                              const SizedBox(height: 35),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildQuickActionButton(icon: Icons.add, label: 'Income', onTap: () => _navigateTo(const IncomeEntryScreen())),
                                  _buildQuickActionButton(icon: Icons.remove, label: 'Expense', onTap: () => _navigateTo(const ExpenseEntryScreen())),
                                  _buildQuickActionButton(icon: Icons.swap_horiz, label: 'Transfer', onTap: () => _navigateTo(const TransferScreen())),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white), onPressed: () => _navigateTo(const SettingsScreen())),
                      IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.white70), onPressed: _logout),
                    ],
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Accounts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildFlatCard(
                                title: 'Wallet Cash',
                                amount: '$_currencySymbol${_walletBalance.toStringAsFixed(2)}',
                                icon: Icons.account_balance_wallet_rounded,
                                iconColor: Colors.green,
                                onTap: () => _navigateTo(const AccountsScreen()),
                              ),
                              const SizedBox(width: 16),
                              _buildFlatCard(
                                title: 'Bank Accounts',
                                amount: '$_currencySymbol${_bankBalance.toStringAsFixed(2)}',
                                icon: Icons.account_balance_rounded,
                                iconColor: Colors.blue,
                                onTap: () => _navigateTo(const AccountsScreen()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text('Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildFlatCard(
                                title: 'Total Saved',
                                amount: '$_currencySymbol${_totalSaved.toStringAsFixed(0)}',
                                icon: Icons.shield_rounded,
                                iconColor: Colors.teal,
                                onTap: () => _navigateTo(const CommitmentHubScreen()),
                              ),
                              const SizedBox(width: 16),
                              _buildFlatCard(
                                title: 'Spent (MTD)',
                                amount: '$_currencySymbol${_expenseMTD.toStringAsFixed(0)}',
                                icon: Icons.trending_down_rounded,
                                iconColor: Colors.redAccent,
                                onTap: () {},
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text('Quick Hub', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                          const SizedBox(height: 12),
                          _buildListTile(
                            title: 'Commitment Hub',
                            subtitle: _pendingTotal > 0 ? 'Action Required: $_currencySymbol${_pendingTotal.toStringAsFixed(2)}' : 'All caught up!',
                            icon: Icons.savings_rounded,
                            color: Colors.orange,
                            onTap: () => _navigateTo(const CommitmentHubScreen()),
                          ),
                          _buildListTile(
                            title: 'View Reports',
                            subtitle: 'Analytics & History',
                            icon: Icons.bar_chart_rounded,
                            color: Colors.deepPurple,
                            onTap: () => _navigateTo(const ReportsScreen()),
                          ),
                          const SizedBox(height: 40),
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