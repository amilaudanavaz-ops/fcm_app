import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/category_model.dart';
import '../../core/services/category_service.dart';
import 'itemization_screen.dart';

class ExpenseEntryScreen extends StatefulWidget {
  const ExpenseEntryScreen({super.key});

  @override
  State<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends State<ExpenseEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  final CategoryService _categoryService = CategoryService();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<CategoryModel> _categories = [];
  List<Map<String, dynamic>> _accounts = [];

  CategoryModel? _selectedCategory;
  String? _selectedAccountId;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isCategoriesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isCategoriesLoading = true);
    try {
      final fetchedCategories = await _categoryService.getCategories('expense');
      
      final userId = _supabase.auth.currentUser?.id;
      List<Map<String, dynamic>> fetchedAccounts = [];
      if (userId != null) {
        final accResponse = await _supabase
            .from('accounts')
            .select()
            .eq('user_id', userId);
        fetchedAccounts = List<Map<String, dynamic>>.from(accResponse);
      }

      setState(() {
        _categories = fetchedCategories;
        _accounts = fetchedAccounts;
        if (_categories.isNotEmpty) {
          _selectedCategory = _categories.first;
        }
        if (_accounts.isNotEmpty) {
          _selectedAccountId = _accounts.first['id']?.toString();
        }
        _isCategoriesLoading = false;
      });
    } catch (e) {
      setState(() => _isCategoriesLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  // --- TEMPLATES WORKFLOW ---
  Future<List<Map<String, dynamic>>> _fetchExpenseTemplates() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _supabase
        .from('expense_templates')
        .select()
        .eq('user_id', userId);

    return List<Map<String, dynamic>>.from(response);
  }

  void _showTemplatePicker() async {
    final templates = await _fetchExpenseTemplates();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Expense Template',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(),
            if (templates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Text('No saved expense templates found.'),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.bookmark_outline, size: 20),
                      ),
                      title: Text(
                        template['name'] ?? 'Unnamed Template',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${template['category'] ?? 'General'} • \$${template['amount'] ?? '0.00'}',
                      ),
                      onTap: () {
                        _applyTemplate(template);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _applyTemplate(Map<String, dynamic> template) {
    setState(() {
      if (template['amount'] != null) {
        _amountController.text = template['amount'].toString();
      }
      if (template['notes'] != null || template['name'] != null) {
        _noteController.text = template['notes'] ?? template['name'] ?? '';
      }
      
      if (_categories.isNotEmpty) {
        final matchedCategory = _categories.firstWhere(
          (c) => c.name.toLowerCase() == (template['category'] ?? '').toString().toLowerCase(),
          orElse: () => _categories.first,
        );
        _selectedCategory = matchedCategory;
      }

      if (template['account_id'] != null) {
        _selectedAccountId = template['account_id'].toString();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Applied "${template['name'] ?? 'Template'}"')),
    );
  }

  // --- SAVE AS TEMPLATE ---
  Future<void> _saveAsTemplate() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category first')),
      );
      return;
    }

    final templateNameController = TextEditingController();

    final templateName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as Template'),
        content: TextField(
          controller: templateNameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Template Name',
            hintText: 'e.g., Weekly Groceries',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, templateNameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (templateName != null && templateName.isNotEmpty) {
      try {
        final userId = _supabase.auth.currentUser?.id;
        if (userId == null) throw 'User not authenticated';

        await _supabase.from('expense_templates').insert({
          'user_id': userId,
          'name': templateName,
          'amount': double.tryParse(_amountController.text),
          'category': _selectedCategory!.name,
          'account_id': _selectedAccountId,
          'notes': _noteController.text.trim(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Template "$templateName" saved!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save template: $e')),
          );
        }
      }
    }
  }

  void _openItemizationScreen() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category first')),
      );
      return;
    }

    // Capture the Map returned by ItemizationScreen
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemizationScreen(
          categoryId: _selectedCategory!.id,
          categoryName: _selectedCategory!.name,
        ),
      ),
    );

    if (result != null && result is Map) {
      final calculatedTotal = result['total'] as double;
      final breakdownText = result['breakdown'] as String;

      if (calculatedTotal > 0) {
        setState(() {
          // 1. Update the total amount
          _amountController.text = calculatedTotal.toStringAsFixed(2);
          
          // 2. Append the breakdown to the notes field
          if (breakdownText.isNotEmpty) {
            final currentNote = _noteController.text.trim();
            
            if (!currentNote.contains(breakdownText)) {
              _noteController.text = currentNote.isEmpty 
                  ? "Itemized Breakdown:\n$breakdownText" 
                  : "$currentNote\n\nItemized Breakdown:\n$breakdownText";
            }
          }
        });
      }
    }
  }

  Future<void> _submitExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw 'User not authenticated';

      final amount = double.parse(_amountController.text);
      final noteText = _noteController.text.trim();
      final isoDate = _selectedDate.toIso8601String();

      // 1. Insert into 'expenses' table
      await _supabase.from('expenses').insert({
        'user_id': userId,
        'amount': amount,
        'category_id': _selectedCategory!.id,
        'category': _selectedCategory!.name,
        'category_name': _selectedCategory!.name,
        'account_id': _selectedAccountId,
        'title': noteText.isNotEmpty ? noteText : _selectedCategory!.name,
        'description': noteText,
        'note': noteText,
        'date': isoDate,
      });

      // 2. Insert into 'transactions' table (Required for Dashboard, History, & Graphs)
      await _supabase.from('transactions').insert({
        'user_id': userId,
        'amount': amount,
        'type': 'expense',
        'category': _selectedCategory!.name,
        'category_id': _selectedCategory!.id,
        'account_id': _selectedAccountId != null ? int.tryParse(_selectedAccountId!) ?? _selectedAccountId : null,
        'title': noteText.isNotEmpty ? noteText : _selectedCategory!.name,
        'description': noteText,
        'date': isoDate,
      });

      // 3. Update target account balance
      if (_selectedAccountId != null) {
        try {
          final accountData = await _supabase
              .from('accounts')
              .select('id, current_balance, balance')
              .eq('id', _selectedAccountId!)
              .single();

          if (accountData['current_balance'] != null) {
            final currentBal = (accountData['current_balance'] as num).toDouble();
            await _supabase
                .from('accounts')
                .update({'current_balance': currentBal - amount})
                .eq('id', _selectedAccountId!);
          } else if (accountData['balance'] != null) {
            final currentBal = (accountData['balance'] as num).toDouble();
            await _supabase
                .from('accounts')
                .update({'balance': currentBal - amount})
                .eq('id', _selectedAccountId!);
          }
        } catch (accError) {
          debugPrint('Account balance update skipped: $accError');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense logged successfully!')),
        );
        Navigator.pop(context, true); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save expense: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Expense'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Save as Template',
            onPressed: _saveAsTemplate,
          ),
          IconButton(
            icon: const Icon(Icons.style_outlined),
            tooltip: 'Apply Template',
            onPressed: _showTemplatePicker,
          ),
        ],
      ),
      body: _isCategoriesLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Amount Field & Itemize Action
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixText: '\$ ',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.receipt_long_outlined),
                          tooltip: 'Itemize Expense',
                          onPressed: _openItemizationScreen,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter an amount';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Category Dropdown
                    DropdownButtonFormField<CategoryModel>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: _categories.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(cat.name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedCategory = val);
                      },
                      validator: (val) => val == null ? 'Select a category' : null,
                    ),
                    const SizedBox(height: 20),

                    // Account Dropdown
                    if (_accounts.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: _selectedAccountId,
                        decoration: const InputDecoration(
                          labelText: 'Account',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        ),
                        items: _accounts.map((acc) {
                          return DropdownMenuItem(
                            value: acc['id']?.toString(),
                            child: Text(acc['name'] ?? 'Account'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() => _selectedAccountId = val);
                        },
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Note Field
                    TextFormField(
                      controller: _noteController,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Note / Description',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Date Picker Tile
                    ListTile(
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: Text(
                        'Date: ${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.edit),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 30),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitExpense,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Save Expense', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}