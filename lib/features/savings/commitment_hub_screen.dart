import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommitmentHubScreen extends StatefulWidget {
  const CommitmentHubScreen({super.key});

  @override
  State<CommitmentHubScreen> createState() => _CommitmentHubScreenState();
}

class _CommitmentHubScreenState extends State<CommitmentHubScreen> {
  // 1. We keep a list of IDs that we have "visually" removed
  final Set<int> _optimisticallyDeletedIds = {};

  final _commitmentsStream = Supabase.instance.client
      .from('commitments')
      .stream(primaryKey: ['id'])
      .eq('status', 'pending')
      .order('created_at');

  Future<void> _markDeposited(Map<String, dynamic> commitment) async {
    final int id = commitment['id'];

    // 2. Optimistic Update: Remove it from the screen INSTANTLY
    setState(() {
      _optimisticallyDeletedIds.add(id);
    });

    try {
      // 3. Send the actual request to the database in the background
      await Supabase.instance.client
          .from('commitments')
          .update({'status': 'deposited'})
          .eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Great job! Savings confirmed.'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // If it fails, put it back on the screen (Undo the optimistic update)
      setState(() {
        _optimisticallyDeletedIds.remove(id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commitment Hub')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _commitmentsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // 4. Filter the data: Take the server data AND remove our "optimistically deleted" items
          final commitments = snapshot.data!
              .where((item) => !_optimisticallyDeletedIds.contains(item['id']))
              .toList();

          if (commitments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.thumb_up_alt_outlined, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('All caught up! No pending deposits.'),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: commitments.length,
            padding: const EdgeInsets.all(10),
            itemBuilder: (context, index) {
              final item = commitments[index];
              final amount = (item['amount'] as num).toDouble();
              
              return Card(
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PENDING DEPOSIT', 
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)
                      ),
                      const SizedBox(height: 5),
                      Text('\$${amount.toStringAsFixed(2)}', 
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
                      ),
                      const Text('From recent income source', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _markDeposited(item),
                          icon: const Icon(Icons.check_circle),
                          label: const Text('CONFIRM DEPOSITED'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}