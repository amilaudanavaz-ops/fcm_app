import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Filters
  DateTimeRange? _dateRange;
  String _typeFilter = 'all'; 
  int? _selectedCategoryId; 

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _categories = [];
  String _currencySymbol = '\$';
  
  bool _isLoading = true;
  bool _isOffline = false; // New Offline Tracking State

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
    _fetchDataConcurrently();
  }

  // --- FAST CONCURRENT DATA LOADING WITH OFFLINE PROTECTION ---
  Future<void> _fetchDataConcurrently() async {
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

      var txQuery = _supabase
          .from('transactions')
          .select('*, categories(name), accounts(name)')
          .eq('user_id', userId);

      if (_typeFilter != 'all') {
        if (_typeFilter == 'income') {
          txQuery = txQuery.inFilter('type', ['income', 'initial_balance']);
        } else {
          txQuery = txQuery.eq('type', _typeFilter);
        }
      }

      if (_selectedCategoryId != null) {
        txQuery = txQuery.eq('category_id', _selectedCategoryId!);
      }

      if (_dateRange != null) {
        txQuery = txQuery.gte('date', _dateRange!.start.toIso8601String())
                         .lte('date', _dateRange!.end.toIso8601String());
      }

      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select('currency_symbol').eq('id', userId).maybeSingle(),
        _supabase.from('categories').select().eq('user_id', userId),
        txQuery.order('date', ascending: false),
      ]);

      if (mounted) {
        setState(() {
          _currencySymbol = (results[0] as Map?)?['currency_symbol']?.toString() ?? '\$';
          _categories = List<Map<String, dynamic>>.from(results[1] ?? []);
          _transactions = List<Map<String, dynamic>>.from(results[2] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load history: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _pickDateRange() async {
    HapticFeedback.lightImpact();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Colors.deepPurple)),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _fetchDataConcurrently();
    }
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _typeFilter == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _typeFilter = value;
          if (_typeFilter == 'income') _selectedCategoryId = null;
        });
        _fetchDataConcurrently();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurple : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected ? [BoxShadow(color: Colors.deepPurple.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
          border: Border.all(color: isSelected ? Colors.deepPurple : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.white : Colors.grey.shade700),
        ),
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
            onPressed: _fetchDataConcurrently,
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
    return Column(
      children: [
        // --- FILTER SECTION ---
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 5))],
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: _pickDateRange,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
                  child: Row(
                    children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.deepPurple.shade50, shape: BoxShape.circle), child: const Icon(Icons.calendar_month_rounded, color: Colors.deepPurple, size: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _dateRange == null ? 'All Time History' : '${DateFormat('MMM d, yyyy').format(_dateRange!.start)}  -  ${DateFormat('MMM d, yyyy').format(_dateRange!.end)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black87),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildFilterChip('All Activity', 'all'),
                    const SizedBox(width: 10),
                    _buildFilterChip('Income Only', 'income'),
                    const SizedBox(width: 10),
                    _buildFilterChip('Expenses Only', 'expense'),
                  ],
                ),
              ),
              if (_typeFilter != 'income') ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedCategoryId,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                  decoration: InputDecoration(
                    labelText: 'Filter Category',
                    labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13),
                    prefixIcon: const Icon(Icons.category_rounded, color: Colors.deepPurple, size: 20),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('All Categories', style: TextStyle(fontWeight: FontWeight.bold))),
                    ..._categories.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold)))),
                  ],
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedCategoryId = val);
                    _fetchDataConcurrently();
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 10),

        // --- LIST SECTION ---
        Expanded(
          child: _isOffline 
            ? _buildOfflineState()
            : _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple)) 
              : _transactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)]), child: Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey[300])),
                        const SizedBox(height: 24),
                        Text('No transactions found', style: TextStyle(color: Colors.grey[800], fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text('Try adjusting your date or category filters.', style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      final isPositive = tx['type'] == 'income' || tx['type'] == 'initial_balance';
                      final isInitialBalance = tx['type'] == 'initial_balance';
                      final amount = (tx['amount'] as num).toDouble();
                      final date = DateTime.parse(tx['date']);
                      
                      final catName = isInitialBalance ? 'Initial Balance' : (tx['categories'] != null ? tx['categories']['name'] : (isPositive ? 'Income' : 'Uncategorized'));
                      final accName = tx['accounts'] != null ? tx['accounts']['name'] : 'Unknown';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: isPositive ? Colors.green.shade50 : Colors.red.shade50,
                                child: Icon(isPositive ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: isPositive ? Colors.green : Colors.redAccent, size: 22),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(catName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text('$accName • ${DateFormat('MMM d, yyyy').format(date)}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              Text(
                                '${isPositive ? '+' : '-'}$_currencySymbol${amount.toStringAsFixed(2)}',
                                style: TextStyle(color: isPositive ? Colors.green.shade700 : Colors.redAccent.shade700, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: -0.5),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}