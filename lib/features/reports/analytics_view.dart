import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOffline = false;
  String _currencySymbol = '\$';
  
  // Metrics
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _netSurplus = 0;
  double _savingsRate = 0;

  // Breakdown Data
  List<Map<String, dynamic>> _expensePieData = [];
  List<Map<String, dynamic>> _incomePieData = [];
  
  // UI State
  int _selectedBreakdownIndex = 0; // 0 for Expense, 1 for Income

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() { _isLoading = true; _isOffline = false; });

    // OFFLINE CHECK
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted) setState(() { _isLoading = false; _isOffline = true; });
      return;
    }

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
      
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select('currency_symbol').eq('id', userId).maybeSingle(),
        _supabase.from('transactions').select('type, amount, categories(name)').eq('user_id', userId).gte('date', startOfMonth),
      ]);

      final profileData = results[0] as Map<String, dynamic>?;
      final txData = (results[1] as List<dynamic>?) ?? [];
      
      final symbol = profileData?['currency_symbol']?.toString() ?? '\$';

      double income = 0;
      double expense = 0;
      Map<String, double> expenseCategories = {};
      Map<String, double> incomeCategories = {};

      for (var item in txData) {
        // FLOATING POINT MATH FIX: Strict 2-decimal truncation for analytics precision
        final rawAmt = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final amt = double.parse(rawAmt.toStringAsFixed(2));
        
        final type = item['type']?.toString();
        final catName = item['categories'] != null ? item['categories']['name'] : 'Other';

        if (type == 'income') {
          income += amt;
          incomeCategories[catName] = (incomeCategories[catName] ?? 0) + amt;
        } else if (type == 'expense') {
          expense += amt;
          expenseCategories[catName] = (expenseCategories[catName] ?? 0) + amt;
        }
      }

      // Calculate Advanced Metrics Safely
      final surplus = double.parse((income - expense).toStringAsFixed(2));
      final rate = income > 0 ? double.parse(((surplus / income) * 100).toStringAsFixed(1)) : 0.0;

      // Modern Pastel Colors for Charts
      final expColors = [Colors.redAccent.shade400, Colors.orange.shade400, Colors.pink.shade400, Colors.purple.shade400, Colors.amber.shade600];
      final incColors = [Colors.green.shade400, Colors.teal.shade400, Colors.blue.shade400, Colors.cyan.shade400, Colors.lightGreen.shade500];

      // Build Expense Breakdown
      List<Map<String, dynamic>> expList = [];
      int eIdx = 0;
      expenseCategories.forEach((k, v) {
        expList.add({
          'name': k,
          'amount': v,
          'percent': expense > 0 ? (v / expense) * 100 : 0,
          'color': expColors[eIdx % expColors.length],
        });
        eIdx++;
      });
      expList.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

      // Build Income Breakdown
      List<Map<String, dynamic>> incList = [];
      int iIdx = 0;
      incomeCategories.forEach((k, v) {
        incList.add({
          'name': k,
          'amount': v,
          'percent': income > 0 ? (v / income) * 100 : 0,
          'color': incColors[iIdx % incColors.length],
        });
        iIdx++;
      });
      incList.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

      if (mounted) {
        setState(() {
          _currencySymbol = symbol;
          _totalIncome = income;
          _totalExpense = expense;
          _netSurplus = surplus;
          _savingsRate = rate;
          _expensePieData = expList;
          _incomePieData = incList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load chart data: $e'), backgroundColor: Colors.redAccent));
      }
    }
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
          Text('Analytics require an active connection.', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchData,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry Connection'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          )
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, {String? subtitle}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade100, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 16),
            Text(value, style: const TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.w600)),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isOffline) return _buildOfflineState();
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.deepPurple));
    }

    double maxVal = _totalIncome > _totalExpense ? _totalIncome : _totalExpense;
    double yAxisLimit = maxVal > 0 ? maxVal * 1.2 : 100;

    final currentPieData = _selectedBreakdownIndex == 0 ? _expensePieData : _incomePieData;
    final currentTotal = _selectedBreakdownIndex == 0 ? _totalExpense : _totalIncome;
    final isExpenseView = _selectedBreakdownIndex == 0;

    return RefreshIndicator(
      onRefresh: _fetchData,
      color: Colors.deepPurple,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // --- 1. THE 4-PILLAR METRICS GRID ---
                  Row(
                    children: [
                      _buildMetricCard('INCOME (MTD)', '$_currencySymbol${_totalIncome.toStringAsFixed(0)}', Icons.arrow_downward_rounded, Colors.green),
                      const SizedBox(width: 12),
                      _buildMetricCard('SPENT (MTD)', '$_currencySymbol${_totalExpense.toStringAsFixed(0)}', Icons.arrow_upward_rounded, Colors.redAccent),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildMetricCard('NET SURPLUS', '$_currencySymbol${_netSurplus.toStringAsFixed(0)}', Icons.account_balance_wallet_rounded, _netSurplus >= 0 ? Colors.blue : Colors.orange),
                      const SizedBox(width: 12),
                      _buildMetricCard('SAVINGS RATE', '${_savingsRate.toStringAsFixed(1)}%', Icons.analytics_rounded, _savingsRate >= 0 ? Colors.teal : Colors.red, subtitle: 'Of total income'),
                    ],
                  ),
                  
                  const SizedBox(height: 24),

                  // --- 2. BAR CHART (INCOME VS EXPENSE) ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cash Flow Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                        const SizedBox(height: 30),
                        AspectRatio(
                          aspectRatio: 1.5,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: yAxisLimit,
                              barTouchData: BarTouchData(enabled: false),
                              titlesData: FlTitlesData(
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      if (value == 0) return const Padding(padding: EdgeInsets.only(top: 8), child: Text('Income', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)));
                                      if (value == 1) return const Padding(padding: EdgeInsets.only(top: 8), child: Text('Expense', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)));
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              gridData: const FlGridData(show: false),
                              barGroups: [
                                BarChartGroupData(x: 0, barRods: [
                                  BarChartRodData(toY: _totalIncome, color: Colors.green.shade400, width: 50, borderRadius: BorderRadius.circular(8))
                                ]),
                                BarChartGroupData(x: 1, barRods: [
                                  BarChartRodData(toY: _totalExpense, color: Colors.redAccent.shade400, width: 50, borderRadius: BorderRadius.circular(8))
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),

                  // --- 3. DYNAMIC BREAKDOWN SECTION ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          'Category Breakdown', 
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedBreakdownIndex = 0);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _selectedBreakdownIndex == 0 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: _selectedBreakdownIndex == 0 ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))] : [],
                                ),
                                child: Text('Expense', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _selectedBreakdownIndex == 0 ? Colors.redAccent : Colors.grey.shade600)),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedBreakdownIndex = 1);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _selectedBreakdownIndex == 1 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: _selectedBreakdownIndex == 1 ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))] : [],
                                ),
                                child: Text('Income', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _selectedBreakdownIndex == 1 ? Colors.green : Colors.grey.shade600)),
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (currentTotal == 0) 
                    Center(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
                        child: Column(
                          children: [
                            Icon(Icons.pie_chart_outline_rounded, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('No ${isExpenseView ? 'expenses' : 'income'} this month.', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )
                    )
                  else ...[
                    // The Dynamic Pie Chart
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      child: SizedBox(
                        height: 220,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 4,
                            centerSpaceRadius: 45,
                            sections: currentPieData.map((stat) {
                              return PieChartSectionData(
                                color: stat['color'],
                                value: stat['amount'],
                                title: '${(stat['percent'] as double).toStringAsFixed(0)}%',
                                radius: 60,
                                titleStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Modern Interactive Legend list
                    ...currentPieData.map((stat) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade100, width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: (stat['color'] as Color).withOpacity(0.15),
                          child: Container(width: 14, height: 14, decoration: BoxDecoration(color: stat['color'], shape: BoxShape.circle)),
                        ),
                        title: Text(stat['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        trailing: Text(
                          '$_currencySymbol${(stat['amount'] as double).toStringAsFixed(2)}', 
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: isExpenseView ? Colors.redAccent.shade700 : Colors.green.shade700)
                        ),
                        onTap: () => HapticFeedback.selectionClick(),
                      ),
                    )),
                  ],

                  const SizedBox(height: 80), // Bottom padding
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}