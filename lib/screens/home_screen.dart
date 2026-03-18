// ─── screens/home_screen.dart ────────────────────────────
// HomeBody: bot toggle, watched pairs, alert log.
// No Scaffold here — MainShell owns the Scaffold + bottom nav.

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AlertLog {
  final String symbol;
  final String type;
  final double price;
  final String timeframe;
  final DateTime time;

  AlertLog({
    required this.symbol,
    required this.type,
    required this.price,
    required this.timeframe,
    required this.time,
  });
}

class HomeBody extends StatefulWidget {
  const HomeBody({super.key});

  @override
  State<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<HomeBody> {
  bool _isRunning   = false;
  String _lastCheck = '—';
  final List<AlertLog> _alertLogs = [];

  @override
  void initState() {
    super.initState();
    _checkIfRunning();
    _listenToBackground();
  }

  // ─── Check if bot is already running ─────────────────
  Future<void> _checkIfRunning() async {
    final running = await FlutterBackgroundService().isRunning();
    if (mounted) setState(() => _isRunning = running);
  }

  // ─── Listen to events from background service ─────────
  void _listenToBackground() {
    final service = FlutterBackgroundService();

    service.on('update').listen((data) {
      if (data != null && mounted) {
        setState(() => _lastCheck = data['lastCheck'] ?? '—');
      }
    });

    service.on('alert').listen((data) {
      if (data != null && mounted) {
        setState(() {
          _alertLogs.insert(
            0,
            AlertLog(
              symbol:    data['symbol'],
              type:      data['type'],
              price:     (data['price'] as num).toDouble(),
              timeframe: data['timeframe'],
              time:      DateTime.parse(data['time']),
            ),
          );
        });
      }
    });
  }

  // ─── Toggle bot ON / OFF ──────────────────────────────
  Future<void> _toggleBot() async {
    final service = FlutterBackgroundService();

    if (_isRunning) {
      service.invoke('stop');
      setState(() => _isRunning = false);
    } else {
      await service.startService();
      setState(() => _isRunning = true);
    }
  }

  // ─── Clear alerted levels ─────────────────────────────
  Future<void> _clearAlertedLevels() async {
    final prefs = await SharedPreferences.getInstance();
    final keys  = prefs.getKeys()
        .where((k) => k.startsWith('HH_') || k.startsWith('LL_'))
        .toList();

    for (final key in keys) {
      await prefs.remove(key);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Alerted levels cleared'),
          ]),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final isDark     = theme.brightness == Brightness.dark;
    final cardColor  = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final accentColor = _isRunning ? Colors.greenAccent : Colors.redAccent;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ─── Status Card ──────────────────────────────
        _buildCard(
          cardColor: cardColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isRunning ? '🟢 Bot is Running' : '🔴 Bot is Stopped',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Last check: $_lastCheck',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          'Every ${Config.checkEveryMinutes} min · '
                          '${Config.symbols.length} pairs · '
                          '${Config.timeframes.join(', ')}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isRunning,
                    onChanged: (_) => _toggleBot(),
                    activeColor: Colors.greenAccent,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _toggleBot,
                  icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(_isRunning ? 'Stop Bot' : 'Start Bot'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ─── Watched Pairs ────────────────────────────
        _buildCard(
          cardColor: cardColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Watched Pairs', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Config.symbols.map((s) {
                  return Chip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    backgroundColor: isDark
                        ? const Color(0xFF2A2A3E)
                        : Colors.blue.shade50,
                    side: BorderSide(
                      color: isDark
                          ? Colors.blueAccent.withOpacity(0.3)
                          : Colors.blue.shade200,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ─── Alert Log ────────────────────────────────
        _buildCard(
          cardColor: cardColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Alert Log', style: theme.textTheme.titleSmall),
                  TextButton.icon(
                    onPressed: _clearAlertedLevels,
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Clear Levels',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_alertLogs.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none_rounded,
                            size: 40,
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'No alerts yet.\nStart the bot to begin watching.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...(_alertLogs
                    .take(20)
                    .map((log) => _buildAlertTile(log, isDark))),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Alert tile ───────────────────────────────────────
  Widget _buildAlertTile(AlertLog log, bool isDark) {
    final isHH   = log.type == 'HH';
    final color  = isHH ? Colors.redAccent : Colors.greenAccent;
    final emoji  = isHH ? '🔴' : '🟢';
    final signal = isHH ? 'Resistance Hit' : 'Support Hit';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$emoji ${log.symbol} · ${log.type} · ${log.timeframe}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(signal,
                  style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                log.price.toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${log.time.hour.toString().padLeft(2, '0')}:'
                '${log.time.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Card wrapper ─────────────────────────────────────
  Widget _buildCard({required Widget child, required Color cardColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
