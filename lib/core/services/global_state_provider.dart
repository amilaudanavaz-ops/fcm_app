import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class GlobalStateProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isOffline = false;

  String _currencySymbol = '\$';
  double _totalBalance = 0.0;
  
  // Data held globally in memory
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _expenseCategories = [];
  List<Map<String, dynamic>> _incomeCategories = [];

  // Getters
  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String get currencySymbol => _currencySymbol;
  double get totalBalance => _totalBalance;
  List<Map<String, dynamic>> get accounts => _accounts;
  List<Map<String, dynamic>> get expenseCategories => _expenseCategories;
  List<Map<String, dynamic>> get incomeCategories => _incomeCategories;

  /// Fetch all crucial user data instantly and calculate live balances
  Future<void> loadGlobalData() async {
    _isLoading = true;
    notifyListeners();

    // Offline Protection
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      _isOffline = true;
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isOffline = false;

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Concurrently fetch Profiles, Accounts, Transactions, Transfers, Commitments, and Categories
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select('currency_symbol').eq('id', userId).maybeSingle(),
        _supabase.from('accounts').select('id, name, type').eq('user_id', userId).order('id'),
        _supabase.from('transactions').select('type, amount, account_id').eq('user_id', userId),
        _supabase.from('transfers').select('from_account_id, to_account_id, amount').eq('user_id', userId),
        _supabase.from('commitments').select('amount, transactions(account_id)').eq('user_id', userId).eq('status', 'deposited'),
        _supabase.from('categories').select().eq('user_id', userId).order('name', ascending: true),
      ]);

      _currencySymbol = (results[0] as Map?)?['currency_symbol']?.toString() ?? '\$';
      
      final fetchedAccounts = List<Map<String, dynamic>>.from(results[1] ?? []);
      final txData = (results[2] as List<dynamic>?) ?? [];
      final transferData = (results[3] as List<dynamic>?) ?? [];
      final commitmentsData = (results[4] as List<dynamic>?) ?? [];
      
      final allCategories = List<Map<String, dynamic>>.from(results[5] ?? []);
      _expenseCategories = allCategories.where((c) => c['type'] == 'expense').toList();
      _incomeCategories = allCategories.where((c) => c['type'] == 'income').toList();

      // Live Ledger Math Engine
      Map<String, double> balances = {};
      for (var acc in fetchedAccounts) {
        balances[acc['id'].toString()] = 0.0;
      }

      for (var tx in txData) {
        final acctId = tx['account_id']?.toString();
        if (acctId == null || !balances.containsKey(acctId)) continue;
        
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final type = tx['type']?.toString();

        if (type == 'income' || type == 'initial_balance') {
          balances[acctId] = (balances[acctId] ?? 0.0) + amt;
        } else if (type == 'expense') {
          balances[acctId] = (balances[acctId] ?? 0.0) - amt;
        }
      }

      for (var tr in transferData) {
        final amt = (tr['amount'] as num?)?.toDouble() ?? 0.0;
        final fromId = tr['from_account_id']?.toString();
        final toId = tr['to_account_id']?.toString();

        if (fromId != null && balances.containsKey(fromId)) balances[fromId] = (balances[fromId] ?? 0.0) - amt;
        if (toId != null && balances.containsKey(toId)) balances[toId] = (balances[toId] ?? 0.0) + amt;
      }

      for (var c in commitmentsData) {
        final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
        final sourceTx = c['transactions'] as Map<String, dynamic>?;
        if (sourceTx != null && sourceTx['account_id'] != null) {
          final acctId = sourceTx['account_id'].toString();
          if (balances.containsKey(acctId)) balances[acctId] = (balances[acctId] ?? 0.0) - amt;
        }
      }

      // Map balances to the global state variables
      _totalBalance = 0.0;
      _accounts = fetchedAccounts.map((acc) {
        final idStr = acc['id'].toString();
        final bal = balances[idStr] ?? 0.0;
        _totalBalance += bal;
        return {
          ...acc,
          'current_balance': bal, // Safe, perfectly calculated balance injected
        };
      }).toList();

    } catch (e) {
      debugPrint('GlobalState Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners(); // Notifies the entire app to instantly rebuild with new data
    }
  }
}