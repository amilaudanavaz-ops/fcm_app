import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ExportService {
  static Future<void> exportTransactionsToCSV() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("User not authenticated.");

    // Fetch all transactions
    final response = await supabase
        .from('transactions')
        .select('*, categories(name), accounts(name)')
        .eq('user_id', userId)
        .order('date', ascending: false);

    final List<dynamic> data = response as List<dynamic>;

    // 1. Create CSV Header
    List<List<dynamic>> csvData = [
      ['Date', 'Type', 'Amount', 'Category', 'Account', 'Description'],
    ];

    // 2. Map Database rows to CSV rows
    for (var tx in data) {
      final isInitialBalance = tx['type'] == 'initial_balance';
      final isPositive = tx['type'] == 'income' || isInitialBalance;
      
      final date = DateFormat('yyyy-MM-dd').format(DateTime.parse(tx['date']));
      final type = isPositive ? 'Credit' : 'Debit';
      final amount = (tx['amount'] as num).toDouble().toStringAsFixed(2);
      
      final category = isInitialBalance 
          ? 'Initial Balance' 
          : (tx['categories'] != null ? tx['categories']['name'] : 'Uncategorized');
          
      final account = tx['accounts'] != null ? tx['accounts']['name'] : 'Unknown';
      final description = tx['description'] ?? '';

      csvData.add([date, type, amount, category, account, description]);
    }

    // 3. Convert to CSV String
    String csvString = const ListToCsvConverter().convert(csvData);

    // 4. Save to temporary file
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/Financial_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    final file = File(path);
    await file.writeAsString(csvString);

    // 5. Trigger Native Share Sheet
    await Share.shareXFiles([XFile(path)], text: 'Here is your financial export.');
  }
}