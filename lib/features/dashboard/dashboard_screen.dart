import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../accounts/accounts_screen.dart';
import '../expenses/expense_entry_screen.dart';
import '../income/income_entry_screen.dart';
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
  final PageController _pageController = PageController();
  int _currentPage = 0;
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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchDashboardMetrics() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profileData = await Supabase.instance.client.from('profiles').select().eq('id', userId).maybeSingle();
      final symbol = profileData?['currency_symbol']?.toString() ?? '\$';

      final accountsData = await Supabase.instance.client.from('accounts').select().eq('user_id', userId);
      final Map<String, String> accountTypes = {
        for (var item in accountsData) item['id'].toString(): (item['type'] ?? 'wallet').toString()
      };

      final txData = await Supabase.instance.client.from('transactions').select().eq('user_id', userId);
      final expensesData = await Supabase.instance.client.from('expenses').select().eq('user_id', userId);
      final transferData = await Supabase.instance.client.from('transfers').select().eq('user_id', userId);
      final savedData = await Supabase.instance.client.from('commitments').select('amount, transactions(account_id)').eq('user_id', userId).eq('status', 'deposited');
      final pendingData = await Supabase.instance.client.from('commitments').select().eq('user_id', userId).eq('status', 'pending');

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
          if (date.year == now.year && date.month == now.month) mtdExpense += amt;
        }
      }

      // Live Transactions Aggregation
      for (var tx in txData) {
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final acctId = tx['account_id']?.toString() ?? '';
        final acctType = accountTypes[acctId] ?? 'wallet'; // Default to wallet if orphaned
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
      for (var s in savedData) {
        final amt = (s['amount'] as num?)?.toDouble() ?? 0.0;
        totalSaved += amt;
        final sourceTx = s['transactions'] as Map<String, dynamic>?;
        if (sourceTx != null && sourceTx['account_id'] != null) {
          final acctType = accountTypes[sourceTx['account_id'].toString()];
          if (acctType == 'wallet') incomeWallet -= amt;
          else if (acctType == 'bank') incomeBank -= amt;
        }
      }

      double pending = 0;
      for (var p in pendingData) pending += (p['amount'] as num?)?.toDouble() ?? 0.0;

      if (mounted) {
        setState(() {
          _currencySymbol = symbol;
          _walletBalance = incomeWallet - expenseWallet;
          _bankBalance = incomeBank - expenseBank;
          _netWorth = _walletBalance + _bankBalance + totalSaved;
          _totalSaved = totalSaved;
          _pendingTotal = pending;
          _expenseMTD = mtdExpense;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error fetching dashboard metrics: $e');
    }
  }
  
  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Widget _buildTopCard(String title, double amount, IconData icon, Color color) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccountsScreen()),
        ).then((_) => _fetchDashboardMetrics());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              radius: 24,
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_currencySymbol${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap to manage',
              style: TextStyle(
                color: Colors.deepPurpleAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        elevation: 0,
        title: const Text('Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ).then((_) => _fetchDashboardMetrics()),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDashboardMetrics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Purple Background Header + PageView
                    Stack(
                      children: [
                        Container(
                          height: 120,
                          decoration: const BoxDecoration(
                            color: Colors.deepPurple,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 200,
                              child: PageView(
                                controller: _pageController,
                                onPageChanged: (index) => setState(() => _currentPage = index),
                                children: [
                                  _buildTopCard('Net Worth', _netWorth, Icons.monetization_on, Colors.blue),
                                  _buildTopCard('Wallet Cash', _walletBalance, Icons.account_balance_wallet, Colors.green),
                                  _buildTopCard('Bank Accounts', _bankBalance, Icons.account_balance, Colors.indigo),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Page Indicators
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(3, (index) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  height: 8,
                                  width: _currentPage == index ? 24 : 8,
                                  decoration: BoxDecoration(
                                    color: _currentPage == index ? Colors.deepPurple : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // MTD & Saved Summary Row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    const Text('Total Saved', style: TextStyle(color: Colors.grey)),
                                    const SizedBox(height: 8),
                                    Text(
                                      '$_currencySymbol${_totalSaved.toStringAsFixed(0)}',
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    const Text('Expense (MTD)', style: TextStyle(color: Colors.grey)),
                                    const SizedBox(height: 8),
                                    Text(
                                      '$_currencySymbol${_expenseMTD.toStringAsFixed(0)}',
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Hub & Reports Links
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade50,
                            child: const Icon(Icons.savings_outlined, color: Colors.orange),
                          ),
                          title: const Text('Commitment Hub', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            _pendingTotal > 0 ? 'Action Required: $_currencySymbol${_pendingTotal.toStringAsFixed(2)}' : 'All caught up!',
                            style: TextStyle(color: _pendingTotal > 0 ? Colors.redAccent : Colors.grey),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommitmentHubScreen())).then((_) => _fetchDashboardMetrics()),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurple.shade50,
                            child: const Icon(Icons.bar_chart, color: Colors.deepPurple),
                          ),
                          title: const Text('View Reports', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Analytics & History', style: TextStyle(color: Colors.grey)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())).then((_) => _fetchDashboardMetrics()),
                        ),
                      ),
                    ),

                    const SizedBox(height: 100), // padding for bottom buttons
                  ],
                ),
              ),
            ),
      // Floating Bottom Action Buttons
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseEntryScreen())).then((_) => _fetchDashboardMetrics()),
                icon: const Icon(Icons.remove),
                label: const Text('Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IncomeEntryScreen())).then((_) => _fetchDashboardMetrics()),
                icon: const Icon(Icons.add),
                label: const Text('Income', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}