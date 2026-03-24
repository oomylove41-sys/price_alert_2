// ─── screens/main_shell.dart ─────────────────────────────
// Root widget. 6-tab BottomNavigationBar:
// Home, Pairs, Timeframes, Indicator, Bot, Patterns
// Telegram accessible via the top-right send icon in AppBar.

import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'price_alerts_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // ─── 6 bottom nav tabs ───────────────────────────────
  static const _tabs = [
    _TabItem(label: 'Home', icon: Icons.home_rounded),
    _TabItem(label: 'Pairs', icon: Icons.currency_bitcoin),
    _TabItem(label: 'Timeframes', icon: Icons.access_time_rounded),
    _TabItem(label: 'Indicator', icon: Icons.tune_rounded),
    _TabItem(label: 'Bot', icon: Icons.settings_rounded),
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

  // ─── Telegram bottom sheet ───────────────────────────
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
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.blueAccent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SizedBox(height: 8),
                    Icon(Icons.show_chart, color: Colors.white, size: 36),
                    SizedBox(height: 12),
                    Text('HH/LL Alert Bot',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Crypto trading alerts',
                        style: TextStyle(color: Colors.white70)),
                    SizedBox(height: 12),
                  ],
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.notifications, color: Colors.blueAccent),
                title: const Text('Price Alerts'),
                subtitle: const Text('Set custom price targets'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PriceAlertsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.candlestick_chart,
                    color: Colors.blueAccent),
                title: const Text('Patterns'),
                subtitle: const Text('Pattern detection settings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => Scaffold(
                                appBar: AppBar(
                                    title: const Text('Pattern Settings')),
                                body: PatternSettingsPage(onSaved: _onSaved),
                              )));
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('More features coming soon',
                    style: TextStyle(color: Colors.grey)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('HH/LL Alert Bot • v1.0',
                    style: TextStyle(color: Theme.of(context).dividerColor)),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: Text(_titles[_index]),
        centerTitle: false,
        actions: [
          // ─── Telegram icon ────────────────────────
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
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ─── Drag handle ───────────────────────
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
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
