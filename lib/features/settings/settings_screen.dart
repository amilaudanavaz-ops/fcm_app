import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _savingsPercentage = 10.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client.from('profiles').select().eq('id', userId).maybeSingle();
    if (data != null) {
      setState(() {
        _savingsPercentage = (data['savings_percentage'] as int).toDouble();
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePercentage() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;
    await Supabase.instance.client.from('profiles').upsert({
      'id': userId,
      'savings_percentage': _savingsPercentage.toInt(),
    });
    setState(() => _isLoading = false);
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    // Helper to determine text color based on background (Glass mode backgrounds are dark)
    final isGlass = themeProvider.uiStyle == 'glass';
    final textColor = isGlass ? Colors.white : Colors.black87;
    final subTextColor = isGlass ? Colors.white70 : Colors.grey;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Appearance')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Financial Logic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: subTextColor)),
                const SizedBox(height: 10),
                Card(
                  // In Glass mode, card is semi-transparent white
                  color: isGlass ? Colors.white.withOpacity(0.1) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text('Savings Commitment %', style: TextStyle(color: textColor)),
                        Text('${_savingsPercentage.toInt()}%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textColor)),
                        Slider(
                          value: _savingsPercentage,
                          min: 0, max: 50, divisions: 50,
                          activeColor: isGlass ? Colors.white : themeProvider.primaryColor,
                          onChanged: (val) => setState(() => _savingsPercentage = val),
                          onChangeEnd: (_) => _savePercentage(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                Text('UI Style', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: subTextColor)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildStyleCard(themeProvider, 'Soft / Clean', 'soft', Icons.check_circle_outline)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStyleCard(themeProvider, 'Glass / Premium', 'glass', Icons.blur_on)),
                  ],
                ),

                const SizedBox(height: 30),

                Text('Color Theme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: subTextColor)),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    _buildThemeCard(themeProvider, 'System', 'system', Colors.grey),
                    _buildThemeCard(themeProvider, 'Light', 'light', Colors.amber),
                    _buildThemeCard(themeProvider, 'Dark', 'dark', Colors.black87),
                    _buildThemeCard(themeProvider, 'Ocean', 'ocean', Colors.cyan),
                    _buildThemeCard(themeProvider, 'Forest', 'forest', Colors.green),
                    _buildThemeCard(themeProvider, 'Royal', 'royal', Colors.deepPurple),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildStyleCard(ThemeProvider provider, String label, String value, IconData icon) {
    final isSelected = provider.uiStyle == value;
    final isGlass = provider.uiStyle == 'glass';
    
    return InkWell(
      onTap: () => provider.setUiStyle(value),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: isSelected 
              ? (isGlass ? Colors.white : provider.primaryColor) 
              : (isGlass ? Colors.white.withOpacity(0.1) : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? (isGlass ? provider.primaryColor : Colors.white) : Colors.grey),
            const SizedBox(height: 5),
            Text(label, style: TextStyle(
              color: isSelected ? (isGlass ? provider.primaryColor : Colors.white) : Colors.grey,
              fontWeight: FontWeight.bold
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeCard(ThemeProvider provider, String label, String value, Color color) {
    final isSelected = provider.currentThemeName == value;
    return InkWell(
      onTap: () => provider.setTheme(value),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: [if (isSelected) const BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: value == 'light' ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}