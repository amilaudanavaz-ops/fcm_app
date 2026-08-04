import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ItemizationScreen extends StatefulWidget {
  final dynamic categoryId;
  final String categoryName;
  final String? existingBreakdown;

  const ItemizationScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.existingBreakdown,
  });

  @override
  State<ItemizationScreen> createState() => _ItemizationScreenState();
}

class _ItemizationScreenState extends State<ItemizationScreen> {
  final List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _parseExistingBreakdown();
  }

  // Smart Parser: Safely extracts previous items even if formatting slightly varies
  void _parseExistingBreakdown() {
    if (widget.existingBreakdown == null || widget.existingBreakdown!.isEmpty) return;

    if (widget.existingBreakdown!.contains('Itemized Breakdown:')) {
      final parts = widget.existingBreakdown!.split('Itemized Breakdown:');
      if (parts.length > 1) {
        final breakdownLines = parts[1].trim().split('\n');
        for (var line in breakdownLines) {
          if (line.trim().startsWith('- ')) {
            final itemStr = line.trim().substring(2); 
            final splitIdx = itemStr.lastIndexOf(': ');
            
            if (splitIdx != -1) {
              final name = itemStr.substring(0, splitIdx).trim();
              String amountStr = itemStr.substring(splitIdx + 2).trim();
              if (amountStr.startsWith('\$')) {
                amountStr = amountStr.substring(1); 
              }
              final amount = double.tryParse(amountStr) ?? 0.0;
              _items.add({'name': name, 'amount': amount});
            }
          }
        }
      }
    }
  }

  void _showAddEditSheet({int? index}) {
    HapticFeedback.lightImpact();
    final isEditing = index != null;
    final initialName = isEditing ? _items[index]['name'] : '';
    final initialAmount = isEditing ? _items[index]['amount'].toString() : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddEditItemSheet(
        initialName: initialName,
        initialAmount: initialAmount,
        isEditing: isEditing,
        onSave: (name, amount) {
          setState(() {
            if (isEditing) {
              _items[index] = {'name': name, 'amount': amount};
            } else {
              _items.add({'name': name, 'amount': amount});
            }
          });
        },
      ),
    );
  }

  void _saveAndReturn() {
    HapticFeedback.mediumImpact();
    double total = 0;
    String breakdown = '';
    for (var item in _items) {
      total += item['amount'];
      breakdown += '- ${item['name']}: \$${item['amount'].toStringAsFixed(2)}\n';
    }
    // Return back to ExpenseEntryScreen with calculated total and string
    Navigator.pop(context, {'total': total, 'breakdown': breakdown.trim()});
  }

  @override
  Widget build(BuildContext context) {
    double currentTotal = _items.fold(0.0, (sum, item) => sum + item['amount']);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Modern light background
      appBar: AppBar(
        title: Text('Itemize: ${widget.categoryName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditSheet(),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Line Item', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
      body: Column(
        children: [
          // --- HERO HEADER SUMMARY ---
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2E0854), Color(0xFF5D12D6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Running Total', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                    SizedBox(height: 4),
                    Text('Breakdown Sum', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
                Text(
                  '\$${currentTotal.toStringAsFixed(2)}', 
                  style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          // --- FAST LISTVIEW (FPS OPTIMIZED) ---
          Expanded(
            child: _items.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white, 
                          shape: BoxShape.circle, 
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8))]
                        ),
                        child: Icon(Icons.receipt_long_rounded, size: 60, color: Colors.deepPurple.shade100),
                      ),
                      const SizedBox(height: 24),
                      Text('No items added', style: TextStyle(color: Colors.grey[800], fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('Tap "Add Line Item" to start breaking down.', style: TextStyle(color: Colors.grey[500], fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 10, left: 20, right: 20, bottom: 80),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Dismissible(
                      key: Key('${item['name']}_${DateTime.now().millisecondsSinceEpoch}_$index'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (direction) {
                        HapticFeedback.mediumImpact();
                        final removedName = item['name'];
                        setState(() => _items.removeAt(index));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$removedName removed', style: const TextStyle(fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.black87,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      },
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
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _showAddEditSheet(index: index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.deepPurple.shade50,
                                  radius: 20,
                                  child: const Icon(Icons.label_outline_rounded, color: Colors.deepPurple, size: 20),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                                      const SizedBox(height: 4),
                                      
                                    ],
                                  ),
                                ),
                                Text('\$${item['amount'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.deepPurple)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),

          // --- FOOTER APPLY BUTTON ---
          Container(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 20, bottom: 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, -5))],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _items.isEmpty ? null : _saveAndReturn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600, 
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 4,
                  shadowColor: Colors.green.withValues(alpha: 0.3),
                ),
                child: const Text('Apply Breakdown to Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// PERFORMANCE FIX: Localized Stateful Widget for BottomSheet
// Prevents the main ListView from rebuilding on every keystroke!
// ----------------------------------------------------------------------
class _AddEditItemSheet extends StatefulWidget {
  final String initialName;
  final String initialAmount;
  final bool isEditing;
  final Function(String name, double amount) onSave;

  const _AddEditItemSheet({
    required this.initialName,
    required this.initialAmount,
    required this.isEditing,
    required this.onSave,
  });

  @override
  State<_AddEditItemSheet> createState() => _AddEditItemSheetState();
}

class _AddEditItemSheetState extends State<_AddEditItemSheet> {
  late TextEditingController _nameController;
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _amountController = TextEditingController(text: widget.initialAmount);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    HapticFeedback.lightImpact();
    final name = _nameController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    
    if (name.isNotEmpty && amount > 0) {
      widget.onSave(name, amount);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Text(widget.isEditing ? 'Edit Breakdown Item' : 'New Line Item', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black87)),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Item Name',
                hintText: 'e.g. Breakfast',
                prefixIcon: const Icon(Icons.receipt_long_rounded, color: Colors.deepPurple),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixIcon: const Icon(Icons.attach_money_rounded, color: Colors.deepPurple),
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
                child: Text(widget.isEditing ? 'Update Item' : 'Add Item', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}