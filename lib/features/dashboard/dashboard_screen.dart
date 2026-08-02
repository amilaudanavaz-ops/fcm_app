import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/theme_provider.dart'; 
import '../auth/login_screen.dart';
import '../settings/settings_screen.dart';
import '../income/income_entry_screen.dart';
import '../expenses/expense_entry_screen.dart';
import '../savings/commitment_hub_screen.dart';
import '../reports/reports_screen.dart';
import '../accounts/accounts_screen.dart'; 
import '../initial_setup/initial_balance_screen.dart'; 

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _netWorth = 0.0;
  double _walletBalance = 0.0;
  double _bankBalance = 0.0;
  double _totalSaved = 0.0;
  double _expenseMTD = 0.0;
  double _pendingTotal = 0.0; 
  bool _isLoading = true;
  String _currencySymbol = '\$';

  final PageController _pageController = PageController(viewportFraction: 0.9);
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _checkInitialSetup();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialSetup() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('transactions')
          .select('id')
          .eq('user_id', userId)
          .count(CountOption.exact); 

      if (response.count == 0 && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const InitialBalanceScreen()),
        );
      } else {
        _fetchDashboardMetrics();
      }
    } catch (e) {
      debugPrint('Error checking initial setup: $e');
      _fetchDashboardMetrics(); 
    }
  }

 Future<void> _fetchDashboardMetrics() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // 1. Fetch Profile Currency (Safe Select)
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select() 
          .eq('id', userId)
          .maybeSingle();

      final symbol = profileData?['currency_symbol']?.toString() ?? '\$';

      // 2. Fetch Accounts (SAFE SELECT: won't crash if a specific column is missing)
      final accountsData = await Supabase.instance.client
          .from('accounts')
          .select() 
          .eq('user_id', userId);

      final Map<String, String> accountTypes = {
        for (var item in accountsData)
          item['id'].toString(): (item['type'] ?? 'wallet').toString()
      };

      double walletDirect = 0.0;
      double bankDirect = 0.0;
      bool hasAccountBalances = false;

      for (var acc in accountsData) {
        // Safely check for either current_balance or balance
        final bal = ((acc['current_balance'] ?? acc['balance']) as num?)?.toDouble() ?? 0.0;
        if (acc['current_balance'] != null || acc['balance'] != null) {
          hasAccountBalances = true;
        }
        final type = (acc['type'] ?? 'wallet').toString();
        if (type == 'wallet') {
          walletDirect += bal;
        } else {
          bankDirect += bal;
        }
      }

      // 3. Fetch Transactions (Safe Select)
      final txData = await Supabase.instance.client
          .from('transactions')
          .select() 
          .eq('user_id', userId);

      // 4. Fetch Expenses specifically for MTD (Safe Select)
      final expensesData = await Supabase.instance.client
          .from('expenses')
          .select() 
          .eq('user_id', userId);

      // 5. Fetch Transfers (Safe Select)
      final transferData = await Supabase.instance.client
          .from('transfers')
          .select() 
          .eq('user_id', userId);

      // 6. Fetch Commitments
      final savedData = await Supabase.instance.client
          .from('commitments')
          .select('amount, transactions(account_id)')
          .eq('user_id', userId)
          .eq('status', 'deposited');

      final pendingData = await Supabase.instance.client
          .from('commitments')
          .select()
          .eq('user_id', userId)
          .eq('status', 'pending');

      double incomeWallet = 0, expenseWallet = 0;
      double incomeBank = 0, expenseBank = 0;
      double mtdExpense = 0;
      final now = DateTime.now();

      // Calculate MTD Expenses
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

      // Process Transactions for cash balances
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

      // Process Transfers
      for (var tr in transferData) {
        final amt = (tr['amount'] as num?)?.toDouble() ?? 0.0;
        final fromId = tr['from_account_id']?.toString() ?? '';
        final toId = tr['to_account_id']?.toString() ?? '';
        final fromType = accountTypes[fromId];
        final toType = accountTypes[toId];

        if (fromType == 'wallet') incomeWallet -= amt;
        if (fromType == 'bank') incomeBank -= amt;
        if (toType == 'wallet') incomeWallet += amt;
        if (toType == 'bank') incomeBank += amt;
      }

      // Process Savings
      double totalSaved = 0;
      for (var s in savedData) {
        final amt = (s['amount'] as num?)?.toDouble() ?? 0.0;
        totalSaved += amt;

        final sourceTx = s['transactions'] as Map<String, dynamic>?;
        if (sourceTx != null && sourceTx['account_id'] != null) {
          final sourceAcctId = sourceTx['account_id'].toString();
          final acctType = accountTypes[sourceAcctId];

          if (acctType == 'wallet') {
            incomeWallet -= amt;
          } else if (acctType == 'bank') {
            incomeBank -= amt;
          }
        }
      }

      double pending = 0;
      for (var p in pendingData) {
        pending += (p['amount'] as num?)?.toDouble() ?? 0.0;
      }

      if (mounted) {
        setState(() {
          _currencySymbol = symbol;
          _walletBalance = hasAccountBalances ? walletDirect : (incomeWallet - expenseWallet);
          _bankBalance = hasAccountBalances ? bankDirect : (incomeBank - expenseBank);
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
        // This will pop up a red message at the bottom of your screen if any Supabase query fails!
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dashboard Sync Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      debugPrint('Error fetching dashboard metrics: $e');
    }
  }
  
  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
        .then((_) => _fetchDashboardMetrics());
  }

  Widget _buildBalanceCard(BuildContext context, {
    required String title, 
    required double amount, 
    required Color color,
    required IconData icon,
    VoidCallback? onTap
  }) {
    final uiStyle = Provider.of<ThemeProvider>(context).uiStyle;
    
    if (uiStyle == 'glass') {
      return _buildGlassCard(title, amount, color, icon, onTap);
    } else {
      return _buildSoftCard(title, amount, color, icon, onTap);
    }
  }

  Widget _buildGlassCard(String title, double amount, Color glowColor, IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
          color: glowColor.withValues(alpha: 0.05),
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.4,
            colors: [
              Colors.transparent,               
              glowColor.withValues(alpha: 0.0), 
              glowColor.withValues(alpha: 0.3), 
            ],
            stops: const [0.0, 0.6, 1.0], 
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(height: 8),
              Text(
                title, 
                style: const TextStyle(
                  color: Colors.white70, 
                  fontSize: 13, 
                  letterSpacing: 1.1, 
                  fontWeight: FontWeight.w500
                ),
              ),
              const SizedBox(height: 4),
              _isLoading
                  ? const SizedBox(
                      height: 20, 
                      width: 20, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    )
                  : Text(
                      '$_currencySymbol${amount.toStringAsFixed(2)}', 
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)
                    ),
              if (onTap != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1), 
                    borderRadius: BorderRadius.circular(20)
                  ),
                  child: const Text('Manage', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSoftCard(String title, double amount, Color color, IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 15, offset: const Offset(0, 8))
          ],
          border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                title, 
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13, letterSpacing: 1.1, fontWeight: FontWeight.w600)
              ),
              const SizedBox(height: 4),
              _isLoading
                  ? CircularProgressIndicator(color: color)
                  : Text(
                      '$_currencySymbol${amount.toStringAsFixed(2)}', 
                      style: TextStyle(color: Colors.grey.shade900, fontSize: 32, fontWeight: FontWeight.bold)
                    ),
              if (onTap != null) ...[
                const SizedBox(height: 12),
                Text('Tap to manage', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
              ]
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isGlass = themeProvider.uiStyle == 'glass';

    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Dashboard'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'expense_btn',
            onPressed: () async {
              final res = await Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => const ExpenseEntryScreen())
              );
              if (res == true || mounted) {
                _fetchDashboardMetrics();
              }
            },
            label: const Text('Expense'),
            icon: const Icon(Icons.remove),
            backgroundColor: isGlass ? Colors.white : Colors.red.shade700,
            foregroundColor: isGlass ? Colors.red : Colors.white,
          ),
          const SizedBox(width: 10),
          FloatingActionButton.extended(
            heroTag: 'income_btn',
            onPressed: () async {
              final res = await Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => const IncomeEntryScreen())
              );
              if (res == true || mounted) {
                _fetchDashboardMetrics();
              }
            },
            label: const Text('Income'),
            icon: const Icon(Icons.add),
            backgroundColor: isGlass ? Colors.white : Colors.green.shade700,
            foregroundColor: isGlass ? Colors.green : Colors.white,
          ),
        ],
      ),

      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.35,
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.primary, 
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _fetchDashboardMetrics,
              color: colorScheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 10, bottom: 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 220, 
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (index) => setState(() => _currentPage = index),
                        children: [
                          _buildBalanceCard(
                            context, 
                            title: 'NET WORTH', 
                            amount: _netWorth, 
                            color: Colors.blueAccent, 
                            icon: Icons.monetization_on_outlined
                          ),
                          _buildBalanceCard(
                            context, 
                            title: 'WALLET CASH', 
                            amount: _walletBalance, 
                            color: const Color(0xFF00C853), 
                            icon: Icons.wallet
                          ),
                          _buildBalanceCard(
                            context, 
                            title: 'BANK ACCOUNTS', 
                            amount: _bankBalance, 
                            color: const Color(0xFF6200EA), 
                            icon: Icons.account_balance,
                            onTap: () async {
                              await Navigator.push(
                                context, 
                                MaterialPageRoute(builder: (_) => const AccountsScreen())
                              );
                              _fetchDashboardMetrics();
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 10),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _currentPage == index ? Colors.white : Colors.white.withValues(alpha: 0.4),
                        ),
                      )),
                    ),

                    const SizedBox(height: 30),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              'Total Saved', 
                              '$_currencySymbol${_totalSaved.toStringAsFixed(0)}', 
                              Colors.green, 
                              isGlass
                            )
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMetricTile(
                              'Expense (MTD)', 
                              '$_currencySymbol${_expenseMTD.toStringAsFixed(0)}', 
                              Colors.red, 
                              isGlass
                            )
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildActionCard(
                        'Commitment Hub', 
                        _pendingTotal > 0 
                            ? 'Action Required: $_currencySymbol${_pendingTotal.toStringAsFixed(2)}' 
                            : 'All caught up!',
                        Icons.savings_outlined, 
                        Colors.orange, 
                        isGlass,
                        () async {
                          await Navigator.push(
                            context, 
                            MaterialPageRoute(builder: (_) => const CommitmentHubScreen())
                          );
                          _fetchDashboardMetrics();
                        },
                        subtitleColor: _pendingTotal > 0 ? Colors.redAccent : null,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildActionCard(
                        'View Reports', 
                        'Analytics & History', 
                        Icons.bar_chart_rounded, 
                        colorScheme.primary, 
                        isGlass,
                        () async {
                          await Navigator.push(
                            context, 
                            MaterialPageRoute(builder: (_) => const ReportsScreen())
                          );
                          _fetchDashboardMetrics();
                        }
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color color, bool isGlass) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGlass ? Colors.white.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isGlass ? Border.all(color: Colors.white12) : Border.all(color: Colors.grey.shade200),
        boxShadow: isGlass ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: isGlass ? Colors.white70 : Colors.grey.shade700)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String title, 
    String subtitle, 
    IconData icon, 
    Color color, 
    bool isGlass, 
    VoidCallback onTap, 
    {Color? subtitleColor}
  ) {
    final subColor = subtitleColor ?? (isGlass ? Colors.white60 : Colors.grey.shade600);

    return Card(
      color: isGlass ? Colors.white.withValues(alpha: 0.1) : Colors.white,
      elevation: isGlass ? 0 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16), 
        side: isGlass ? const BorderSide(color: Colors.white12) : BorderSide.none
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isGlass ? Colors.white24 : color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: isGlass ? Colors.white : color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title, 
                      style: TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.bold, 
                        color: isGlass ? Colors.white : Colors.grey.shade900
                      )
                    ),
                    Text(
                      subtitle, 
                      style: TextStyle(
                        color: subColor, 
                        fontWeight: subtitleColor != null ? FontWeight.bold : FontWeight.normal
                      )
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: isGlass ? Colors.white30 : Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}