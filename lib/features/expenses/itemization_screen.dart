import 'package:flutter/material.dart';

class ItemizationScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const ItemizationScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<ItemizationScreen> createState() => _ItemizationScreenState();
}

class _ItemizedItem {
  TextEditingController nameController;
  TextEditingController amountController;

  _ItemizedItem({String name = '', String amount = ''})
      : nameController = TextEditingController(text: name),
        amountController = TextEditingController(text: amount);

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

class _ItemizationScreenState extends State<ItemizationScreen> {
  final List<_ItemizedItem> _items = [];

  @override
  void initState() {
    super.initState();
    _addItem(name: 'Tea', amount: '100');
    _addItem(name: 'Bun', amount: '200');
  }

  @override
  void dispose() {
    for (var item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem({String name = '', String amount = ''}) {
    final newItem = _ItemizedItem(name: name, amount: amount);
    newItem.amountController.addListener(() {
      setState(() {});
    });
    setState(() {
      _items.add(newItem);
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  double _calculateTotal() {
    double total = 0.0;
    for (var item in _items) {
      final val = double.tryParse(item.amountController.text) ?? 0.0;
      total += val;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final currentTotal = _calculateTotal();

    return PopScope(
      canPop: true, // ✅ Allow normal popping
      onPopInvokedWithResult: (didPop, result) {
        // If popped via system back gesture/button, pass calculated total
        if (didPop) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.categoryName} Breakdown'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // Explicitly pass total when back button in AppBar is clicked
              Navigator.pop(context, _calculateTotal());
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: item.nameController,
                              decoration: const InputDecoration(
                                hintText: 'Item Name',
                                border: InputBorder.none,
                              ),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: item.amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          if (_items.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                              onPressed: () => _removeItem(index),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              TextButton.icon(
                onPressed: () => _addItem(),
                icon: const Icon(Icons.add),
                label: const Text('Create New Sub-Item'),
              ),

              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '\$${currentTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}