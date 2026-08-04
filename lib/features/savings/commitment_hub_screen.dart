import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class CommitmentHubScreen extends StatefulWidget {
  const CommitmentHubScreen({super.key});

  @override
  State<CommitmentHubScreen> createState() => _CommitmentHubScreenState();
}

class _CommitmentHubScreenState extends State<CommitmentHubScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _currencySymbol = '\$';

  List<Map<String, dynamic>> _pendingCommitments = [];
  List<Map<String, dynamic>> _depositedCommitments = [];
  Map<String, String> _accountNames = {};

  double _totalPending = 0.0;
  double _totalSaved = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchCommitmentsData();
  }

  // --- FAST CONCURRENT DATA LOADING ---
  Future<void> _fetchCommitmentsData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // PERFORMANCE UPGRADE: Fetch Profile, Commitments, and Accounts simultaneously
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select('currency_symbol').eq('id', userId).maybeSingle(),
        _supabase.from('commitments')
            .select('id, amount, status, created_at, source_transaction_id, transactions(account_id, description)')
            .eq('user_id', userId)
            .order('created_at', ascending: false),
        _supabase.from('accounts').select('id, name').eq('user_id', userId),
      ]);

      final profileData = results[0] as Map<String, dynamic>?;
      final commitmentsData = (results[1] as List<dynamic>?) ?? [];
      final accountsData = (results[2] as List<dynamic>?) ?? [];

      final symbol = profileData?['currency_symbol']?.toString() ?? '\$';

      // Create an in-memory map of Account ID -> Account Name for fast UI rendering
      final Map<String, String> accNames = {
        for (var acc in accountsData) acc['id'].toString(): acc['name'].toString()
      };

      List<Map<String, dynamic>> pending = [];
      List<Map<String, dynamic>> deposited = [];
      double tPending = 0.0;
      double tSaved = 0.0;

      for (var item in commitmentsData) {
        final cMap = Map<String, dynamic>.from(item);
        final status = cMap['status']?.toString();
        final amount = (cMap['amount'] as num?)?.toDouble() ?? 0.0;

        if (status == 'pending') {
          pending.add(cMap);
          tPending += amount;
        } else if (status == 'deposited') {
          deposited.add(cMap);
          tSaved += amount;
        }
      }

      if (mounted) {
        setState(() {
          _currencySymbol = symbol;
          _accountNames = accNames;
          _pendingCommitments = pending;
          _depositedCommitments = deposited;
          _totalPending = tPending;
          _totalSaved = tSaved;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load commitments: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // --- SAFE DATABASE EXPORT & UPDATE ---
  Future<void> _depositCommitment(Map<String, dynamic> commitment) async {
    HapticFeedback.mediumImpact();
    
    final amount = (commitment['amount'] as num?)?.toDouble() ?? 0.0;
    final sourceTx = commitment['transactions'] as Map<String, dynamic>?;
    final accountId = sourceTx?['account_id']?.toString();
    final accountName = _accountNames[accountId] ?? 'Source Account';

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.savings_rounded, color: Colors.teal, size: 28),
            SizedBox(width: 12),
            Text('Deposit Savings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'Confirm moving $_currencySymbol${amount.toStringAsFixed(2)} from "$accountName" into your savings vault?\n\nThis will deduct the funds from your wallet balance.',
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Deposit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final List<Future<dynamic>> parallelTasks = [];

      // 1. Update Commitment Status
      parallelTasks.add(
        _supabase.from('commitments').update({'status': 'deposited'}).eq('id', commitment['id'])
      );

      // 2. Safe Fallback Balance Update (Deducts from the source account's raw balance)
      if (accountId != null) {
        final accountData = await _supabase.from('accounts').select('current_balance').eq('id', accountId).single();
        final currentBal = (accountData['current_balance'] as num?)?.toDouble() ?? 0.0;
        parallelTasks.add(
          _supabase.from('accounts').update({'current_balance': currentBal - amount}).eq('id', accountId)
        );
      }

      await Future.wait(parallelTasks);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Savings deposited successfully!'), backgroundColor: Colors.green),
        );
        _fetchCommitmentsData(); // Refresh UI instantly
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to deposit: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // --- MODERN UI BUILDERS ---

  Widget _buildCommitmentCard({required Map<String, dynamic> commitment, required bool isPending}) {
    final amount = (commitment['amount'] as num?)?.toDouble() ?? 0.0;
    final dateStr = commitment['created_at']?.toString() ?? '';
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();
    
    final sourceTx = commitment['transactions'] as Map<String, dynamic>?;
    final accountId = sourceTx?['account_id']?.toString();
    final accountName = _accountNames[accountId] ?? 'Unknown Account';
    final desc = sourceTx?['description']?.toString() ?? 'Income Source';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: isPending ? Colors.orange.shade50 : Colors.teal.shade50,
                      child: Icon(
                        isPending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
                        color: isPending ? Colors.orange : Colors.teal,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPending ? 'Pending Deposit' : 'Saved Successfully',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isPending ? Colors.orange.shade800 : Colors.teal.shade800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat.yMMMd().format(date),
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  '$_currencySymbol${amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.black87, letterSpacing: -0.5),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: Colors.grey, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Source: $desc ($accountName)',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (isPending) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => _depositCommitment(commitment),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Move to Vault', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    shadowColor: Colors.teal.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Modern light grey background
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : RefreshIndicator(
              onRefresh: _fetchCommitmentsData,
              color: Colors.deepPurple,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  // --- MODERN GRADIENT HEADER ---
                  SliverAppBar(
                    expandedHeight: 280.0,
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
                              const Text('TOTAL IN VAULT', style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text(
                                '$_currencySymbol${_totalSaved.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold, letterSpacing: -1),
                              ),
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.hourglass_empty_rounded, color: _totalPending > 0 ? Colors.orangeAccent : Colors.white70, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$_currencySymbol${_totalPending.toStringAsFixed(2)} Action Required',
                                      style: TextStyle(color: _totalPending > 0 ? Colors.orangeAccent : Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),

                  // --- BODY CONTENT ---
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_pendingCommitments.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.notifications_active_rounded, color: Colors.orange, size: 22),
                                const SizedBox(width: 10),
                                const Text('Action Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(10)),
                                  child: Text('${_pendingCommitments.length}', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _pendingCommitments.length,
                              itemBuilder: (context, index) {
                                return _buildCommitmentCard(commitment: _pendingCommitments[index], isPending: true);
                              },
                            ),
                            const SizedBox(height: 24),
                          ],

                          Row(
                            children: [
                              const Icon(Icons.verified_rounded, color: Colors.teal, size: 22),
                              const SizedBox(width: 10),
                              const Text('Savings Vault History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (_depositedCommitments.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)]),
                                      child: Icon(Icons.savings_outlined, size: 64, color: Colors.grey[300]),
                                    ),
                                    const SizedBox(height: 24),
                                    Text('Vault is empty', style: TextStyle(color: Colors.grey[800], fontSize: 20, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 8),
                                    Text('Deposit your pending commitments to grow savings.', style: TextStyle(color: Colors.grey[500], fontSize: 14, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _depositedCommitments.length,
                              itemBuilder: (context, index) {
                                return _buildCommitmentCard(commitment: _depositedCommitments[index], isPending: false);
                              },
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