import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/category_model.dart';
import '../../core/services/category_service.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CategoryService _service = CategoryService();

  List<CategoryModel> _expenseCategories = [];
  List<CategoryModel> _incomeCategories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCategoriesConcurrently();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- FAST CONCURRENT DATA LOADING ---
  Future<void> _loadCategoriesConcurrently() async {
    setState(() => _isLoading = true);
    try {
      // Fetch both lists simultaneously to halve load time
      final results = await Future.wait([
        _service.getCategories('expense'),
        _service.getCategories('income'),
      ]);

      if (mounted) {
        setState(() {
          _expenseCategories = results[0];
          _incomeCategories = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading categories: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _showAddCategorySheet(String type) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddCategorySheet(
        type: type,
        onSave: (String name) async {
          setState(() => _isLoading = true);
          try {
            final newCat = await _service.addCategory(name, type);
            if (newCat != null) {
              setState(() {
                if (type == 'expense') {
                  _expenseCategories.add(newCat);
                  _expenseCategories.sort((a, b) => a.name.compareTo(b.name));
                } else {
                  _incomeCategories.add(newCat);
                  _incomeCategories.sort((a, b) => a.name.compareTo(b.name));
                }
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category Added!'), backgroundColor: Colors.green));
              }
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent));
            }
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },
      ),
    );
  }

  Future<void> _deleteCategory(CategoryModel category) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text('Delete Category', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Are you sure you want to delete "${category.name}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await _service.deleteCategory(category.id);
        setState(() {
          if (category.type == 'expense') {
            _expenseCategories.removeWhere((c) => c.id == category.id);
          } else {
            _incomeCategories.removeWhere((c) => c.id == category.id);
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted "${category.name}"'), backgroundColor: Colors.black87));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.redAccent));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildCategoryList(List<CategoryModel> categories, String type) {
    if (categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)]),
                child: Icon(Icons.category_outlined, size: 64, color: Colors.grey[300]),
              ),
              const SizedBox(height: 24),
              Text('No $type categories', style: TextStyle(color: Colors.grey[800], fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Tap the + button to create one.', style: TextStyle(color: Colors.grey[500], fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 100),
      physics: const BouncingScrollPhysics(),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final isExpense = type == 'expense';

        return Dismissible(
          key: Key(category.id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _deleteCategory(category),
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 30),
          ),
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
            color: Colors.white,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              leading: CircleAvatar(
                backgroundColor: isExpense ? Colors.red.shade50 : Colors.green.shade50,
                radius: 24,
                child: Icon(
                  isExpense ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  color: isExpense ? Colors.redAccent : Colors.green,
                  size: 22,
                ),
              ),
              title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
              subtitle: Text(isExpense ? 'Expense Tag' : 'Income Tag', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
                onPressed: () => _deleteCategory(category),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Modern light background
      appBar: AppBar(
        title: const Text('Manage Categories', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E0854), Color(0xFF5D12D6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.outbound_rounded), text: 'Expenses'),
            Tab(icon: Icon(Icons.move_to_inbox_rounded), text: 'Income'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : TabBarView(
              controller: _tabController,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildCategoryList(_expenseCategories, 'expense'),
                _buildCategoryList(_incomeCategories, 'income'),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final currentType = _tabController.index == 0 ? 'expense' : 'income';
          _showAddCategorySheet(currentType);
        },
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Category', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// PERFORMANCE FIX: Localized Stateful Widget for BottomSheet
// Prevents the main ListView from rebuilding on every keystroke!
// ----------------------------------------------------------------------
class _AddCategorySheet extends StatefulWidget {
  final String type;
  final Function(String name) onSave;

  const _AddCategorySheet({required this.type, required this.onSave});

  @override
  State<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<_AddCategorySheet> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    HapticFeedback.lightImpact();
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      Navigator.pop(context);
      widget.onSave(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = widget.type == 'expense';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 24),
            Text(isExpense ? 'New Expense Tag' : 'New Income Tag', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black87)),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Category Name',
                hintText: isExpense ? 'e.g. Groceries, Rent' : 'e.g. Salary, Freelance',
                prefixIcon: Icon(Icons.label_outline_rounded, color: isExpense ? Colors.redAccent : Colors.green),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 4,
                  shadowColor: Colors.deepPurple.withValues(alpha: 0.3),
                ),
                onPressed: _submit,
                child: const Text('Save Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}