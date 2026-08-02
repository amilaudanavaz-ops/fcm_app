import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  // Filters
  DateTimeRange? _dateRange;
  String _typeFilter = 'all'; // 'all', 'income', 'expense'
  int? _selectedCategoryId; // null means 'all categories'

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _categories = []; 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Default: This Month
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
    _fetchCategories();
    _fetchTransactions();
  }

  Future<void> _fetchCategories() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client.from('categories').select().eq('user_id', userId);
    if (mounted) setState(() => _categories = List<Map<String, dynamic>>.from(data));
  }

  Future<void> _fetchTransactions() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;

    try {
      // 1. Base Query (FilterBuilder)
      var query = Supabase.instance.client
          .from('transactions')
          .select('*, categories(name), accounts(name)')
          .eq('user_id', userId);

      // 2. Apply Filters (Chaining onto the FilterBuilder)
      if (_typeFilter != 'all') {
        // Special handling: if 'income' is selected, also fetch 'initial_balance'
        if (_typeFilter == 'income') {
            query = query.inFilter('type', ['income', 'initial_balance']);
        } else {
            query = query.eq('type', _typeFilter);
        }
      }
      
      if (_selectedCategoryId != null) {
        query = query.eq('category_id', _selectedCategoryId!);
      }

      if (_dateRange != null) {
        // Apply Date Range Filters
        query = query.gte('date', _dateRange!.start.toIso8601String())
                     .lte('date', _dateRange!.end.toIso8601String());
      }

      // 3. Apply Order and Execute (TransformBuilder)
      final data = await query.order('date', ascending: false);

      if (mounted) {
        setState(() {
          _transactions = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      // Debug print to help you see the error in console
      debugPrint('History Fetch Error: $e'); 
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _fetchTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- FILTER SECTION ---
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade50,
          child: Column(
            children: [
              // Row 1: Date & Type
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDateRange,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        _dateRange == null 
                          ? 'All Time' 
                          : '${DateFormat('MMM d').format(_dateRange!.start)} - ${DateFormat('MMM d').format(_dateRange!.end)}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ToggleButtons(
                    isSelected: [_typeFilter == 'all', _typeFilter == 'income', _typeFilter == 'expense'],
                    onPressed: (index) {
                      setState(() {
                        if (index == 0) _typeFilter = 'all';
                        if (index == 1) _typeFilter = 'income';
                        if (index == 2) _typeFilter = 'expense';
                        if (_typeFilter == 'income') _selectedCategoryId = null; 
                      });
                      _fetchTransactions();
                    },
                    borderRadius: BorderRadius.circular(8),
                    constraints: const BoxConstraints(minHeight: 36, minWidth: 40),
                    children: const [
                      Text('All'),
                      Text('In'), 
                      Text('Ex'), 
                    ],
                  ),
                ],
              ),
              
              // Row 2: Category Dropdown
              if (_typeFilter != 'income') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Specific Category',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('All Categories')),
                    ..._categories.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text(c['name']))),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedCategoryId = val);
                    _fetchTransactions();
                  },
                ),
              ],
            ],
          ),
        ),

        // --- LIST SECTION ---
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : _transactions.isEmpty
              ? const Center(child: Text('No transactions found matching filters.'))
              : ListView.builder(
                  itemCount: _transactions.length,
                  itemBuilder: (context, index) {
                    final tx = _transactions[index];
                    
                    // NEW LOGIC: Check for both 'income' and 'initial_balance'
                    final isPositive = tx['type'] == 'income' || tx['type'] == 'initial_balance';
                    final isInitialBalance = tx['type'] == 'initial_balance';
                    final amount = (tx['amount'] as num).toDouble();
                    final date = DateTime.parse(tx['date']);
                    
                    // Determine displayed category name
                    final catName = isInitialBalance
                        ? 'Initial Balance' // Specific label for initial balance
                        : tx['categories'] != null 
                            ? tx['categories']['name'] 
                            : (isPositive ? 'Income' : 'Uncategorized'); // Default for others
                            
                    // Safety check for null joins
                    final accName = tx['accounts'] != null ? tx['accounts']['name'] : 'Unknown';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isPositive ? Colors.green.shade50 : Colors.red.shade50,
                        child: Icon(isPositive ? Icons.arrow_downward : Icons.arrow_upward, 
                          color: isPositive ? Colors.green : Colors.red, size: 20
                        ),
                      ),
                      title: Text(catName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('$accName • ${DateFormat.yMMMd().format(date)}'),
                      trailing: Text(
                        '${isPositive ? '+' : '-'} \$${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isPositive ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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