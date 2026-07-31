import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _pieData = [];
  
  // Bar Chart Data
  double _totalIncome = 0;
  double _totalExpense = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;

    try {
      // 1. Fetch Transactions (This Month)
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
      
      final data = await Supabase.instance.client
          .from('transactions')
          .select('type, amount, categories(name)')
          .gte('date', startOfMonth);

      double income = 0;
      double expense = 0;
      Map<String, double> expenseCategories = {};

      for (var item in data) {
        final amt = (item['amount'] as num).toDouble();
        final type = item['type'];

        // FIXED LOGIC: Only count transactions explicitly marked as 'income' for monthly analysis.
        // 'initial_balance' is now correctly excluded from monthly income metrics.
        if (type == 'income') {
          income += amt;
        } else if (type == 'expense') {
          expense += amt;
          // Pie Chart Logic (Only includes expenses)
          final catName = item['categories'] != null ? item['categories']['name'] : 'Other';
          expenseCategories[catName] = (expenseCategories[catName] ?? 0) + amt;
        }
        // Transactions of type 'initial_balance' are now ignored for monthly analytics.
      }

      // Prepare Pie Data
      List<Map<String, dynamic>> pieList = [];
      final colors = [Colors.blue, Colors.red, Colors.orange, Colors.purple, Colors.teal, Colors.amber];
      int i = 0;
      expenseCategories.forEach((k, v) {
        pieList.add({
          'name': k,
          'amount': v,
          'percent': expense > 0 ? (v / expense) * 100 : 0,
          'color': colors[i % colors.length],
        });
        i++;
      });

      if (mounted) {
        setState(() {
          _totalIncome = income;
          _totalExpense = expense;
          _pieData = pieList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Bar Chart: Income vs Expense
          const Text('Performance (This Month)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 1.5,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (_totalIncome > _totalExpense ? _totalIncome : _totalExpense) * 1.2, // Add some headroom
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const Text('Income', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold));
                        if (value == 1) return const Text('Expense', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold));
                        return const Text('');
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(toY: _totalIncome, color: Colors.green, width: 40, borderRadius: BorderRadius.circular(4))
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(toY: _totalExpense, color: Colors.red, width: 40, borderRadius: BorderRadius.circular(4))
                  ]),
                ],
              ),
            ),
          ),
          
          const Divider(height: 40),

          // 2. Pie Chart: Where did the money go?
          const Text('Expense Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          
          if (_totalExpense == 0) 
            const Center(child: Text('No expenses yet this month.'))
          else
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: _pieData.map((stat) {
                    return PieChartSectionData(
                      color: stat['color'],
                      value: stat['amount'],
                      title: '${(stat['percent'] as double).toStringAsFixed(0)}%',
                      radius: 80,
                      titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  }).toList(),
                ),
              ),
            ),
            
          // Legend for Pie Chart
          if (_totalExpense > 0)
            Column(
              children: _pieData.map((stat) => ListTile(
                leading: CircleAvatar(backgroundColor: stat['color'], radius: 8),
                title: Text(stat['name']),
                trailing: Text('\$${(stat['amount'] as double).toStringAsFixed(2)}'),
                dense: true,
              )).toList(),
            ),
        ],
      ),
    );
  }
}