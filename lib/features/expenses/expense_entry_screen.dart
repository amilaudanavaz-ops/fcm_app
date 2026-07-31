import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'itemization_screen.dart';

class ExpenseEntryScreen extends StatefulWidget {
  const ExpenseEntryScreen({super.key});

  @override
  State<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends State<ExpenseEntryScreen> {
  // Controllers
  final _amountController = TextEditingController();
  final _templateNameController = TextEditingController();
  
  // State Variables
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _saveAsTemplate = false;
  String _currencySymbol = '\$'; // NEW: Default Currency Symbol

  // Data Lists
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _currentBreakdown = []; 
  
  // Selections
  int? _selectedCategoryId;
  int? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // NEW: Load Data
  Future<void> _loadData() async {
    await Future.wait([
      _fetchCurrencySymbol(),
      _fetchCategories(),
      _fetchTemplates(),
      _fetchAccounts(),
    ]);
  }

  // NEW: Fetch currency symbol
  Future<void> _fetchCurrencySymbol() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profileData = await Supabase.instance.client
        .from('profiles')
        .select('currency_symbol')
        .eq('id', userId)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _currencySymbol = profileData?['currency_symbol'] as String? ?? '\$';
      });
    }
  }

  Future<void> _fetchCategories() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client.from('categories').select().eq('user_id', userId);
    if (mounted) {
      setState(() => _categories = List<Map<String, dynamic>>.from(data));
    }
  }

  Future<void> _fetchTemplates() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client
        .from('expense_templates')
        .select()
        .eq('user_id', userId)
        .order('created_at');
    if (mounted) {
      setState(() => _templates = List<Map<String, dynamic>>.from(data));
    }
  }

  Future<void> _fetchAccounts() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    var data = await Supabase.instance.client.from('accounts').select().eq('user_id', userId);

    if (mounted) {
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(data);
        if (_accounts.isNotEmpty) { 
          final defaultAccount = _accounts.firstWhere(
            (acc) => acc['type'] == 'wallet',
            orElse: () => _accounts.first,
          );
          _selectedAccountId = defaultAccount['id'];
        }
      });
    }
  }

  void _applyTemplate(Map<String, dynamic> template) {
    setState(() {
      _amountController.text = template['total_amount'].toString();
      _selectedCategoryId = template['category_id'];
      
      // Load breakdown if it exists
      if (template['breakdown'] != null) {
        _currentBreakdown = List<Map<String, dynamic>>.from(template['breakdown']);
      } else {
        _currentBreakdown = [];
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Applied template: "${template['name']}"'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _openItemization() async {
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a Category first')));
      return;
    }

    final categoryName = _categories.firstWhere((c) => c['id'] == _selectedCategoryId)['name'];

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemizationScreen(
          categoryId: _selectedCategoryId!, 
          categoryName: categoryName,
          initialBreakdown: _currentBreakdown.isNotEmpty ? _currentBreakdown : null,
        ),
      ),
    );

    if (result != null && result is Map) {
      setState(() {
        _amountController.text = (result['total'] as double).toStringAsFixed(2);
        _currentBreakdown = List<Map<String, dynamic>>.from(result['breakdown']);
      });
    }
  }

  Future<void> _saveExpense() async {
    if (_amountController.text.isEmpty || _selectedCategoryId == null || _selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }
    
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;

    try {
      // 1. Save Transaction
      await Supabase.instance.client.from('transactions').insert({
        'user_id': userId,
        'type': 'expense',
        'amount': double.parse(_amountController.text),
        'category_id': _selectedCategoryId,
        'account_id': _selectedAccountId, // <--- LINKED TO ACCOUNT
        'date': _selectedDate.toIso8601String(),
        'description': _currentBreakdown.isNotEmpty 
            ? _currentBreakdown.map((e) => "${e['name']}: ${e['amount']}").join(", ") 
            : null,
      });

      // 2. Save as Template (if checked)
      if (_saveAsTemplate && _templateNameController.text.isNotEmpty) {
        await Supabase.instance.client.from('expense_templates').insert({
          'user_id': userId,
          'name': _templateNameController.text,
          'category_id': _selectedCategoryId,
          'total_amount': double.parse(_amountController.text),
          'breakdown': _currentBreakdown,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense Saved!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter templates based on selected category
    final visibleTemplates = _selectedCategoryId == null 
        ? <Map<String, dynamic>>[] 
        : _templates.where((t) => t['category_id'] == _selectedCategoryId).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Add Expense')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Amount Input
            // UPDATED INPUT: Use dynamic currency symbol for prefix
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Total Amount',
                prefixText: '$_currencySymbol ', // USE DYNAMIC SYMBOL
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Paid From (Account Selector)
            DropdownButtonFormField<int>(
              value: _selectedAccountId,
              decoration: const InputDecoration(labelText: 'Paid From', border: OutlineInputBorder()),
              items: _accounts.map((acc) {
                final isWallet = acc['type'] == 'wallet';
                return DropdownMenuItem<int>(
                  value: acc['id'],
                  child: Row(
                    children: [
                      Icon(isWallet ? Icons.wallet : Icons.account_balance, size: 16, color: Colors.grey),
                      const SizedBox(width: 10),
                      Text(acc['name']),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedAccountId = val),
            ),
            const SizedBox(height: 20),

            // 3. Category Dropdown
            DropdownButtonFormField<int>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: _categories.map((cat) {
                return DropdownMenuItem<int>(
                  value: cat['id'],
                  child: Text(cat['name']),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedCategoryId = val),
            ),
            
            // 4. Templates List (Appears if Category matches saved templates)
            if (visibleTemplates.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Quick Fill (Templates):', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: visibleTemplates.length,
                  itemBuilder: (context, index) {
                    final t = visibleTemplates[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ActionChip(
                        avatar: const Icon(Icons.copy, size: 14, color: Colors.blue),
                        // UPDATED DISPLAY: Use dynamic currency symbol
                        label: Text('${t['name']} ($_currencySymbol${t['total_amount']})'), 
                        onPressed: () => _applyTemplate(t),
                        backgroundColor: Colors.blue.shade50,
                        padding: EdgeInsets.zero,
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 20),

            // 5. Smart Breakdown Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openItemization,
                icon: const Icon(Icons.list_alt),
                label: Text(_currentBreakdown.isEmpty 
                  ? 'Smart Breakdown (Itemize)' 
                  : 'Edit Breakdown (${_currentBreakdown.length} items)'),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 6. Date Picker
            ListTile(
              title: Text('Date: ${DateFormat.yMMMd().format(_selectedDate)}'),
              trailing: const Icon(Icons.calendar_today),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.grey)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),

            const SizedBox(height: 20),

            // 7. Save as Template Option
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  CheckboxListTile(
                    title: const Text('Save as new Template?'),
                    subtitle: const Text('For future one-tap entry'),
                    value: _saveAsTemplate,
                    onChanged: (val) => setState(() => _saveAsTemplate = val!),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_saveAsTemplate)
                    TextField(
                      controller: _templateNameController,
                      decoration: const InputDecoration(
                        labelText: 'Template Name',
                        hintText: 'e.g. Morning Commute',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 8. Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveExpense,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                child: _isLoading ? const CircularProgressIndicator() : const Text('Save Expense'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}