import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/global_state_provider.dart';
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
  // We still track these locally because they are specific to the dashboard view
  double _totalSaved = 0.0;
  double _expenseMTD = 0.0;
  double _pendingTotal = 0.0;
  bool _isSecondaryLoading = true;

  @override
  void initState() {
    super.initState();
    // 1. Kick off the Global Provider Fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GlobalStateProvider>().loadGlobalData();
    });
    // 2. Fetch Dashboard-specific metrics (MTD expenses & commitments)
    _fetchSecondaryMetrics();
  }

  Future<void> _fetchSecondaryMetrics() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final results = await Future.wait([
        Supabase.instance.client.from('expenses').select('amount, date').eq('user_id', userId),
        Supabase.instance.client.from('commitments').select('amount, status').eq('user_id', userId),
      ]);

      final expensesData = (results[0] as List<dynamic>?) ?? [];
      final commitmentsData = (results[1] as List<dynamic>?) ?? [];

      double mtdExpense = 0;
      final now = DateTime.now();

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

      double totalSaved = 0;
      double pending = 0;
      for (var s in commitmentsData) {
        final amt = (s['amount'] as num?)?.toDouble() ?? 0.0;
        final status = s['status']?.toString();
        
        if (status == 'deposited') {
          totalSaved += amt;
        } else if (status == 'pending') {
          pending += amt;
        }
      }

      if (mounted) {
        setState(() {
          _expenseMTD = mtdExpense;
          _totalSaved = totalSaved;
          _pendingTotal = pending;
          _isSecondaryLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSecondaryLoading = false);
    }
  }

  Future<void> _logout() async {
    HapticFeedback.mediumImpact();
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _navigateTo(Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) {
      // THE MAGIC: When you return from any screen, tell the Provider to refresh the global memory!
      context.read<GlobalStateProvider>().loadGlobalData();
      _fetchSecondaryMetrics();
    });
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
    // 1. Hook into the Global State
    final globalState = context.watch<GlobalStateProvider>();
    
    // 2. Compute dynamic balances purely from the secure global state
    double walletBalance = 0;
    double bankBalance = 0;
    
    for (var acc in globalState.accounts) {
      if (acc['type'] == 'wallet') walletBalance += (acc['current_balance'] as num).toDouble();
      if (acc['type'] == 'bank') bankBalance += (acc['current_balance'] as num).toDouble();
    }
    
    final double netWorth = walletBalance + bankBalance + _totalSaved;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: (globalState.isLoading && _isSecondaryLoading)
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : RefreshIndicator(
              onRefresh: () async {
                await context.read<GlobalStateProvider>().loadGlobalData();
                await _fetchSecondaryMetrics();
              },
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
                              if (globalState.isOffline)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
                                  child: const Text('OFFLINE MODE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              const Text('TOTAL NET WORTH', style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text(
                                '${globalState.currencySymbol}${netWorth.toStringAsFixed(2)}',
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
                                amount: '${globalState.currencySymbol}${walletBalance.toStringAsFixed(2)}',
                                icon: Icons.account_balance_wallet_rounded,
                                iconColor: Colors.green,
                                onTap: () => _navigateTo(const AccountsScreen()),
                              ),
                              const SizedBox(width: 16),
                              _buildFlatCard(
                                title: 'Bank Accounts',
                                amount: '${globalState.currencySymbol}${bankBalance.toStringAsFixed(2)}',
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
                                amount: '${globalState.currencySymbol}${_totalSaved.toStringAsFixed(0)}',
                                icon: Icons.shield_rounded,
                                iconColor: Colors.teal,
                                onTap: () => _navigateTo(const CommitmentHubScreen()),
                              ),
                              const SizedBox(width: 16),
                              _buildFlatCard(
                                title: 'Spent (MTD)',
                                amount: '${globalState.currencySymbol}${_expenseMTD.toStringAsFixed(0)}',
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
                            subtitle: _pendingTotal > 0 ? 'Action Required: ${globalState.currencySymbol}${_pendingTotal.toStringAsFixed(2)}' : 'All caught up!',
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