import 'package:flutter/material.dart';

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

  void _parseExistingBreakdown() {
    if (widget.existingBreakdown == null || widget.existingBreakdown!.isEmpty) return;

    if (widget.existingBreakdown!.contains('Itemized Breakdown:')) {
      final parts = widget.existingBreakdown!.split('Itemized Breakdown:');
      if (parts.length > 1) {
        final breakdownLines = parts[1].trim().split('\n');
        for (var line in breakdownLines) {
          if (line.startsWith('- ')) {
            final itemStr = line.substring(2); 
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

  // Modern Bottom Sheet for both Adding and Editing
  void _showAddEditSheet({int? index}) {
    final isEditing = index != null;
    final nameController = TextEditingController(text: isEditing ? _items[index]['name'] : '');
    final amountController = TextEditingController(text: isEditing ? _items[index]['amount'].toString() : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom, // Moves up with keyboard
          left: 20,
          right: 20,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEditing ? 'Edit Item' : 'New Item',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Item Name',
                prefixIcon: const Icon(Icons.receipt_long),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixIcon: const Icon(Icons.attach_money),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final name = nameController.text.trim();
                  final amount = double.tryParse(amountController.text) ?? 0.0;
                  if (name.isNotEmpty && amount > 0) {
                    setState(() {
                      if (isEditing) {
                        _items[index] = {'name': name, 'amount': amount};
                      } else {
                        _items.add({'name': name, 'amount': amount});
                      }
                    });
                    Navigator.pop(ctx);
                  }
                },
                child: Text(isEditing ? 'Update Item' : 'Add Item', style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _saveAndReturn() {
    double total = 0;
    String breakdown = '';
    for (var item in _items) {
      total += item['amount'];
      breakdown += '- ${item['name']}: \$${item['amount'].toStringAsFixed(2)}\n';
    }
    Navigator.pop(context, {'total': total, 'breakdown': breakdown.trim()});
  }

  @override
  Widget build(BuildContext context) {
    double currentTotal = _items.fold(0.0, (sum, item) => sum + item['amount']);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('Itemize: ${widget.categoryName}'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditSheet(),
        backgroundColor: Colors.deepPurple,
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
      body: Column(
        children: [
          // Elegant Header Summary
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: const BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Running Total',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                Text(
                  '\$${currentTotal.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 10),

          // Main List (Swipe to delete, Tap to edit)
          Expanded(
            child: _items.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('No items yet.', style: TextStyle(color: Colors.grey[500], fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('Tap Add Item below to start.', style: TextStyle(color: Colors.grey[400])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Dismissible(
                      key: Key('${item['name']}_$index'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (direction) {
                        setState(() => _items.removeAt(index));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${item['name']} removed')),
                        );
                      },
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
                      ),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 1,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: const Text('Tap to edit • Swipe to delete', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          trailing: Text(
                            '\$${item['amount'].toStringAsFixed(2)}', 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepPurple),
                          ),
                          onTap: () => _showAddEditSheet(index: index),
                        ),
                      ),
                    );
                  },
                ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _items.isEmpty ? null : _saveAndReturn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, 
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                child: const Text('Save & Apply to Expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}