import 'package:flutter/material.dart';
import 'analytics_view.dart';
import 'history_view.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Analytics & History'),
          centerTitle: true,
          // --- FIX START: Force White Colors for Tabs ---
          bottom: const TabBar(
            labelColor: Colors.white,            // Selected Icon/Text Color
            unselectedLabelColor: Colors.white70,// Unselected Icon/Text Color (70% opacity)
            indicatorColor: Colors.white,        // The underline bar color
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              Tab(icon: Icon(Icons.pie_chart), text: 'Visuals'),
              Tab(icon: Icon(Icons.history), text: 'History'),
            ],
          ),
          // --- FIX END ---
        ),
        body: const TabBarView(
          children: [
            AnalyticsView(), // The Graphs
            HistoryView(),   // The Detailed List
          ],
        ),
      ),
    );
  }
}