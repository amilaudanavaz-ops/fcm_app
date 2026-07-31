import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ItemizationScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  // NEW: Optional initial data to pre-fill the screen
  final List<Map<String, dynamic>>? initialBreakdown; 

  const ItemizationScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.initialBreakdown,
  });

  @override
  State<ItemizationScreen> createState() => _ItemizationScreenState();
}

class _ItemizationScreenState extends State<ItemizationScreen> {
  final Map<int, TextEditingController> _controllers = {};
  List<Map<String, dynamic>> _subItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSubItems();
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchSubItems() async {
    try {
      // 1. Fetch the list of item names (Bus, Train)
      final data = await Supabase.instance.client
          .from('sub_items')
          .select()
          .eq('category_id', widget.categoryId)
          .order('name');

      setState(() {
        _subItems = List<Map<String, dynamic>>.from(data);
        
        // 2. Initialize controllers
        for (var item in _subItems) {
          _controllers[item['id']] = TextEditingController();
        }

        // 3. NEW: If we passed a template (initialBreakdown), fill the values now!
        if (widget.initialBreakdown != null) {
          for (var templateItem in widget.initialBreakdown!) {
            // Find the matching sub_item by name (e.g., "Bus")
            final matchingSubItem = _subItems.firstWhere(
              (sub) => sub['name'] == templateItem['name'],
              orElse: () => {},
            );

            if (matchingSubItem.isNotEmpty) {
              final id = matchingSubItem['id'];
              _controllers[id]?.text = templateItem['amount'].toString();
            }
          }
        }
        
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _addNewSubItem(String name) async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    try {
      final newItem = await Supabase.instance.client
          .from('sub_items')
          .insert({'user_id': userId, 'category_id': widget.categoryId, 'name': name})
          .select()
          .single();

      setState(() {
        _subItems.add(newItem);
        _controllers[newItem['id']] = TextEditingController();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showAddItemDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Item to ${widget.categoryName}'),
        content: TextField(controller: textController, decoration: const InputDecoration(hintText: 'Name (e.g. Taxi)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                _addNewSubItem(textController.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _finish() {
    double total = 0;
    List<Map<String, dynamic>> breakdown = [];
    
    _controllers.forEach((key, controller) {
      if (controller.text.isNotEmpty) {
        final val = double.tryParse(controller.text) ?? 0;
        total += val;
        
        // Find the name of this item
        final name = _subItems.firstWhere((item) => item['id'] == key)['name'];
        breakdown.add({'name': name, 'amount': val});
      }
    });

    // Return BOTH the total amount AND the breakdown list
    Navigator.pop(context, {'total': total, 'breakdown': breakdown});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.categoryName} Breakdown')),
      floatingActionButton: FloatingActionButton(
        onPressed: _finish,
        child: const Icon(Icons.check),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _subItems.length + 1,
              itemBuilder: (context, index) {
                if (index == _subItems.length) {
                  return TextButton.icon(
                    onPressed: _showAddItemDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Create New Sub-Item'),
                  );
                }
                final item = _subItems[index];
                final id = item['id'] as int;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(item['name'], style: const TextStyle(fontSize: 16))),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _controllers[id],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(prefixText: '\$ ', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}