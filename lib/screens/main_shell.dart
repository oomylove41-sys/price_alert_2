// ─── screens/main_shell.dart ─────────────────────────────
// Root widget. 5-tab BottomNavigationBar (Home, Pairs,
// Timeframes, Indicator, Bot). Telegram accessible via the
// top-right send icon in the AppBar.

import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // ─── 5 bottom nav tabs ───────────────────────────────
  static const _tabs = [
    _TabItem(label: 'Home',       icon: Icons.home_rounded),
    _TabItem(label: 'Pairs',      icon: Icons.currency_bitcoin),
    _TabItem(label: 'Timeframes', icon: Icons.access_time_rounded),
    _TabItem(label: 'Indicator',  icon: Icons.tune_rounded),
    _TabItem(label: 'Bot',        icon: Icons.settings_rounded),
  ];

  static const _titles = [
    'HH/LL Alert Bot',
    'Trading Pairs',
    'Timeframes',
    'Indicator Settings',
    'Bot Settings',
  ];

  // ─── Snackbar on save ────────────────────────────────
  void _onSaved() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(children: [
          Icon(Icons.check_circle, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('Settings saved successfully'),
        ]),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─── Open Telegram settings as a modal bottom sheet ──
  void _openTelegram() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TelegramSheet(onSaved: _onSaved),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // IndexedStack keeps all pages alive so state is preserved
    final pages = [
      const HomeBody(),
      TradingPairsSettingsPage(onSaved: _onSaved),
      TimeframesSettingsPage(onSaved: _onSaved),
      IndicatorSettingsPage(onSaved: _onSaved),
      BotSettingsPage(onSaved: _onSaved),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        centerTitle: false,
        actions: [
          // ─── Telegram icon top-right ───────────────
          IconButton(
            tooltip: 'Telegram Settings',
            icon: const Icon(Icons.send_rounded),
            onPressed: _openTelegram,
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor:
            isDark ? Colors.grey.shade600 : Colors.grey.shade500,
        backgroundColor:
            isDark ? const Color(0xFF1E1E2E) : Colors.white,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        elevation: 12,
        items: _tabs
            .map((t) => BottomNavigationBarItem(
                  icon: Icon(t.icon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

// ─── Tab definition ───────────────────────────────────────
class _TabItem {
  final String label;
  final IconData icon;
  const _TabItem({required this.label, required this.icon});
}

// ══════════════════════════════════════════════════════════
// ─── TELEGRAM BOTTOM SHEET ───────────────────────────────
// ══════════════════════════════════════════════════════════
class _TelegramSheet extends StatelessWidget {
  final VoidCallback onSaved;
  const _TelegramSheet({required this.onSaved});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: sheetColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ─── Drag handle ───────────────────────
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.grey.shade700
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // ─── Header ────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.send_rounded,
                      color: Colors.blueAccent, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Telegram Settings',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ─── Page content ──────────────────────
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                child: TelegramSettingsPage(
                  onSaved: () {
                    onSaved();
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
