// ─── services/background_service.dart ───────────────────
// Background bot. Three alert types run each tick:
//   1. HIT  — price touches an existing HH/LL level
//   2. NEW  — a fresh HH/LL pivot is formed
//   3. PRICE ALERT — price crosses a manually set level

import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'binance_service.dart';
import 'pivot_service.dart';
import 'telegram_service.dart';
import 'pattern_service.dart';

Timer? _checkTimer;
bool _isBusy = false;
bool _shouldStop = false;

// ─── Init ─────────────────────────────────────────────────
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'hh_ll_bot_channel',
    'HH/LL Bot',
    description: 'Running HH/LL Alert Bot',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'hh_ll_bot_channel',
      initialNotificationTitle: 'HH/LL Bot',
      initialNotificationContent: 'Bot is running...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

// ─── Background entry point ───────────────────────────────
@pragma('vm:entry-point')
void onBackgroundStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  _shouldStop = false;
  _isBusy = false;
  _checkTimer?.cancel();
  _checkTimer = null;

  print('🚀 Background service started');
  await ConfigService.load();

  print('✅ Config: ${Config.symbols} | '
      'TFs: ${Config.effectiveTimeframes} | '
      'every ${Config.checkEveryMinutes}m | '
      '${Config.bots.length} bot(s) | '
      '${Config.priceAlerts.length} price alert(s)');

  // ── Stop ────────────────────────────────────────────────
  service.on('stop').listen((event) {
    print('🛑 Stop command received');
    _shouldStop = true;
    _checkTimer?.cancel();
    _checkTimer = null;
    service.stopSelf();
  });

  // ── Live config update ───────────────────────────────────
  service.on('updateConfig').listen((data) {
    if (data == null) return;
    if (data['bots'] != null) {
      try {
        Config.bots = (data['bots'] as List)
            .map((j) =>
                TelegramBot.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
      } catch (e) {
        print('⚠️ Bots parse error: $e');
      }
    }
    if (data['priceAlerts'] != null) {
      try {
        Config.priceAlerts = (data['priceAlerts'] as List)
            .map(
                (j) => PriceAlert.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
      } catch (e) {
        print('⚠️ PriceAlerts parse error: $e');
      }
    }
    if (data['symbols'] != null)
      Config.symbols = List<String>.from(data['symbols'] as List);
    if (data['pivotLen'] != null) Config.pivotLen = data['pivotLen'] as int;
    if (data['limit'] != null) Config.limit = data['limit'] as int;
    if (data['checkEveryMinutes'] != null) {
      final newInterval = data['checkEveryMinutes'] as int;
      if (newInterval != Config.checkEveryMinutes) {
        Config.checkEveryMinutes = newInterval;
        _restartTimer(service);
      }
    }
    print('🔄 Config updated | TFs: ${Config.effectiveTimeframes} | '
        '${Config.priceAlerts.length} price alert(s)');
  });

  await _runAllChecks(service);
  _restartTimer(service);
}

void _restartTimer(ServiceInstance service) {
  _checkTimer?.cancel();
  _checkTimer = Timer.periodic(
    Duration(minutes: Config.checkEveryMinutes),
    (timer) async {
      if (_shouldStop) {
        timer.cancel();
        return;
      }
      if (_isBusy) {
        print('⏳ Skipping tick — still busy');
        return;
      }
      await ConfigService.load();
      await _runAllChecks(service);
    },
  );
  print('⏱ Timer: every ${Config.checkEveryMinutes}m');
}

// ─── Master check loop ────────────────────────────────────
Future<void> _runAllChecks(ServiceInstance service) async {
  if (_isBusy) return;
  _isBusy = true;

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final timeframes = Config.effectiveTimeframes;
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'HH/LL Bot — $timeStr',
        content: '${Config.symbols.length} pairs · ${timeframes.join(', ')}',
      );
    }
    service.invoke('update', {'lastCheck': timeStr});

    // ── HH/LL checks (hit + new level) ──────────────────
    if (timeframes.isNotEmpty) {
      print('🔍 HH/LL: ${Config.symbols} on $timeframes at $timeStr');
      for (final symbol in Config.symbols) {
        for (final tf in timeframes) {
          if (_shouldStop) return;
          await _checkHHLL(symbol, tf, prefs, service);
          await _checkPatterns(symbol, tf, prefs, service);
        }
      }
    }

    // ── Manual price alerts ──────────────────────────────
    await _checkPriceAlerts(prefs, service);
  } catch (e) {
    print('❌ Error in _runAllChecks: $e');
  } finally {
    _isBusy = false;
  }
}

// ─── HH/LL check for one symbol + timeframe ───────────────
Future<void> _checkHHLL(
  String symbol,
  String timeframe,
  SharedPreferences prefs,
  ServiceInstance service,
) async {
  // ─── Pattern detection for one symbol + timeframe ───────
  Future<void> _checkPatterns(
    String symbol,
    String timeframe,
    SharedPreferences prefs,
    ServiceInstance service,
  ) async {
    try {
      final candles = await BinanceService.fetchCandles(symbol, timeframe);
      if (candles.length < 4) return;

      final hits = PatternService.detectOnLastClosed(candles);
      if (hits.isEmpty) return;

      for (final hit in hits) {
        if (_shouldStop) return;

        final key =
            'PAT_${hit.pattern}_${symbol}_${timeframe}_${hit.price.toStringAsFixed(5)}';
        if (prefs.getBool(key) ?? false) continue;

        // Find pattern alerts that match this symbol and pattern
        final matching = Config.patternAlerts.where((p) {
          if (!p.isActive) return false;
          if (p.symbol.toUpperCase() != symbol.toUpperCase()) return false;
          if (!p.patterns.contains(hit.pattern)) return false;
          if (p.timeframes.isNotEmpty && !p.timeframes.contains(timeframe))
            return false;
          return true;
        }).toList();

        bool anyOk = false;
        for (final alert in matching) {
          TelegramBot? bot;
          try {
            bot = Config.bots.firstWhere((b) => b.id == alert.botId);
          } catch (_) {
            bot = null;
          }
          if (bot == null || !bot.isConfigured) {
            print(
                '⚠️ No configured bot for pattern alert ${alert.id} — skipping');
            continue;
          }
          final ok = await TelegramService.sendPatternAlert(
            bot: bot,
            pattern: hit.pattern,
            symbol: symbol,
            timeframe: timeframe,
            price: hit.price,
          );
          if (ok) anyOk = true;
        }

        if (anyOk) {
          await prefs.setBool(key, true);
          service.invoke('alert', {
            'symbol': symbol,
            'type': hit.pattern,
            'kind': 'pattern',
            'price': hit.price,
            'timeframe': timeframe,
            'time': DateTime.now().toIso8601String(),
          });
          print(
              '🔔 PATTERN $symbol ${hit.pattern} @ ${hit.price} ($timeframe)');
        }
      }
    } catch (e) {
      print('❌ Pattern check error on $symbol $timeframe: $e');
    }
  }

  try {
    final candles = await BinanceService.fetchCandles(symbol, timeframe);
    if (candles.length < 2) return;

    final result = PivotService.getHHLL(candles);
    final lastClosed = candles[candles.length - 2];
    final liveCandle = candles[candles.length - 1];

    // Alert type 1 — HIT
    Future<void> checkHit(String type, double? level, bool isHH) async {
      if (level == null) return;
      final key =
          '${type}_HIT_${symbol}_${timeframe}_${level.toStringAsFixed(5)}';
      if (prefs.getBool(key) ?? false) return;
      final isHit = PivotService.isHit(lastClosed, level, isHH) ||
          PivotService.isHit(liveCandle, level, isHH);
      if (!isHit) return;
      final ok = await TelegramService.sendHitAlert(
        levelType: type,
        levelPrice: level,
        timeframe: timeframe,
        currentPrice: liveCandle.close,
        symbol: symbol,
      );
      if (ok) {
        await prefs.setBool(key, true);
        service.invoke('alert', {
          'symbol': symbol,
          'type': type,
          'kind': 'hit',
          'price': level,
          'timeframe': timeframe,
          'time': DateTime.now().toIso8601String(),
        });
        print('✅ HIT $symbol $type @ $level ($timeframe)');
      }
    }

    // Alert type 2 — NEW LEVEL
    Future<void> checkNew(String type, double? level) async {
      if (level == null) return;
      final key =
          '${type}_NEW_${symbol}_${timeframe}_${level.toStringAsFixed(5)}';
      if (prefs.getBool(key) ?? false) return;
      final ok = await TelegramService.sendNewLevelAlert(
        levelType: type,
        levelPrice: level,
        timeframe: timeframe,
        symbol: symbol,
      );
      await prefs.setBool(key, true);
      if (ok) {
        service.invoke('alert', {
          'symbol': symbol,
          'type': type,
          'kind': 'new',
          'price': level,
          'timeframe': timeframe,
          'time': DateTime.now().toIso8601String(),
        });
        print('✨ NEW $symbol $type @ $level ($timeframe)');
      }
    }

    await checkHit('HH', result.hh, true);
    await checkHit('LL', result.ll, false);
    await checkNew('HH', result.hh);
    await checkNew('LL', result.ll);
  } catch (e) {
    print('❌ Error on $symbol $timeframe: $e');
  }
}

// ─── Manual price alert check ─────────────────────────────
Future<void> _checkPriceAlerts(
    SharedPreferences prefs, ServiceInstance service) async {
  final active = Config.priceAlerts.where((a) => a.shouldFire).toList();
  if (active.isEmpty) return;

  print('🔔 Checking ${active.length} price alert(s)...');

  // Group by symbol to minimize API calls
  final Map<String, List<PriceAlert>> bySymbol = {};
  for (final alert in active) {
    bySymbol.putIfAbsent(alert.symbol, () => []).add(alert);
  }

  bool anyTriggered = false;

  for (final entry in bySymbol.entries) {
    if (_shouldStop) break;

    final symbol = entry.key;
    final currentPrice = await BinanceService.getCurrentPrice(symbol);
    if (currentPrice == null) {
      print('⚠️ Could not get price for $symbol — skipping');
      continue;
    }

    for (final alert in entry.value) {
      if (!alert.matches(currentPrice)) continue;

      // Find the specific bot assigned to this alert
      TelegramBot? bot;
      try {
        bot = Config.bots.firstWhere((b) => b.id == alert.botId);
      } catch (_) {
        // Bot deleted — fall back to first bot with manual alerts enabled
        try {
          bot = Config.bots
              .firstWhere((b) => b.isConfigured && b.canReceiveManualAlerts);
        } catch (_) {/* none available */}
      }

      if (bot == null || !bot.isConfigured) {
        print('⚠️ No configured bot for alert "${alert.label}" — skipping');
        // Still mark triggered so we don't spam the check
        alert.isTriggered = true;
        anyTriggered = true;
        continue;
      }

      final ok = await TelegramService.sendPriceAlert(
        bot: bot,
        alert: alert,
        currentPrice: currentPrice,
      );

      // Always mark triggered (even if send failed) to prevent spam
      alert.isTriggered = true;
      anyTriggered = true;

      if (ok) {
        service.invoke('priceAlert', {
          'id': alert.id,
          'symbol': alert.symbol,
          'label': alert.label,
          'targetPrice': alert.targetPrice,
          'currentPrice': currentPrice,
          'condition': alert.condition,
          'time': DateTime.now().toIso8601String(),
        });
        print(
            '🔔 PRICE ALERT: ${alert.label.isNotEmpty ? alert.label : alert.symbol} '
            '@ $currentPrice (target ${alert.targetPrice})');
      } else {
        print('❌ Price alert send failed for ${alert.symbol}');
      }
    }
  }

  // Persist updated triggered state back to SharedPreferences
  if (anyTriggered) {
    await ConfigService.savePriceAlertsFromBackground(prefs);
  }
}
