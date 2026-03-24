// ─── services/background_service.dart ───────────────────
// Runs the bot logic in the background even when app is closed.

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'binance_service.dart';
import 'candlestick_pattern_service.dart';
import 'pivot_service.dart';
import 'telegram_service.dart';

// ─── Top-level state (isolate-local) ─────────────────────
Timer? _checkTimer;
bool _isBusy = false;
bool _shouldStop = false;

// ─── INIT BACKGROUND SERVICE ─────────────────────────────
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'hh_ll_bot_channel',
    'HH/LL Bot',
    description: 'Running HH/LL Alert Bot',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
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

// ─── iOS BACKGROUND HANDLER ──────────────────────────────
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

// ─── MAIN BACKGROUND LOOP ────────────────────────────────
@pragma('vm:entry-point')
void onBackgroundStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  _shouldStop = false;
  _isBusy = false;
  _checkTimer?.cancel();
  _checkTimer = null;

  print('🚀 Background service started');

  await ConfigService.load();
  print(
      '✅ Config loaded: ${Config.symbols} | ${Config.timeframes} | every ${Config.checkEveryMinutes}m');

  // ─── Stop command ─────────────────────────────────────
  service.on('stop').listen((event) {
    print('🛑 Stop command received');
    _shouldStop = true;
    _checkTimer?.cancel();
    _checkTimer = null;
    service.stopSelf();
  });

  // ─── Live config update ───────────────────────────────
  service.on('updateConfig').listen((data) {
    if (data == null) return;

    if (data['symbols'] != null) {
      Config.symbols = List<String>.from(data['symbols'] as List);
    }
    if (data['timeframes'] != null) {
      Config.timeframes = List<String>.from(data['timeframes'] as List);
    }
    if (data['botToken'] != null) {
      Config.botToken = data['botToken'] as String;
    }
    if (data['chatId'] != null) {
      Config.chatId = data['chatId'] as String;
    }
    if (data['pivotLen'] != null) {
      Config.pivotLen = data['pivotLen'] as int;
    }
    if (data['limit'] != null) {
      Config.limit = data['limit'] as int;
    }
    if (data['checkEveryMinutes'] != null) {
      final newInterval = data['checkEveryMinutes'] as int;
      final changed = newInterval != Config.checkEveryMinutes;
      Config.checkEveryMinutes = newInterval;
      if (changed) {
        print(
            '⏱ Interval changed to ${Config.checkEveryMinutes}m — restarting timer');
        _restartTimer(service);
      }
    }

    // Pattern settings
    if (data['patternBE'] != null) {
      Config.patternBE = data['patternBE'] as bool;
    }
    if (data['patternMS'] != null) {
      Config.patternMS = data['patternMS'] as bool;
    }
    if (data['patternES'] != null) {
      Config.patternES = data['patternES'] as bool;
    }
    if (data['patternRequireTrend'] != null) {
      Config.patternRequireTrend = data['patternRequireTrend'] as bool;
    }
    if (data['patternStarBodyPct'] != null) {
      Config.patternStarBodyPct =
          (data['patternStarBodyPct'] as num).toDouble();
    }
    if (data['patternRecoveryPct'] != null) {
      Config.patternRecoveryPct =
          (data['patternRecoveryPct'] as num).toDouble();
    }

    print('🔄 Config updated: symbols=${Config.symbols}, '
        'interval=${Config.checkEveryMinutes}m, '
        'patterns BE=${Config.patternBE} MS=${Config.patternMS} ES=${Config.patternES}');
  });

  // Run one check immediately on start
  await _runAllChecks(service);

  // Start the repeating timer
  _restartTimer(service);
}

// ─── Start/restart the periodic timer ────────────────────
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
        print('⏳ Previous check still running — skipping tick');
        return;
      }
      await ConfigService.load();
      await _runAllChecks(service);
    },
  );
  print('⏱ Timer started — fires every ${Config.checkEveryMinutes} minute(s)');
}

// ─── CHECK ALL SYMBOLS & TIMEFRAMES ──────────────────────
Future<void> _runAllChecks(ServiceInstance service) async {
  if (_isBusy) return;
  _isBusy = true;

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final now = DateTime.now();

    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    print('🔍 Checking ${Config.symbols} on ${Config.timeframes} at $timeStr');

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'HH/LL Bot — Last check: $timeStr',
        content:
            '${Config.symbols.length} pairs · ${Config.timeframes.join(', ')}',
      );
    }

    service.invoke('update', {'lastCheck': timeStr});

    for (final symbol in Config.symbols) {
      for (final timeframe in Config.timeframes) {
        if (_shouldStop) return;
        await _checkTimeframe(symbol, timeframe, prefs, service);
      }
    }
  } catch (e) {
    print('❌ Error in _runAllChecks: $e');
  } finally {
    _isBusy = false;
  }
}

// ─── CHECK ONE SYMBOL + TIMEFRAME ────────────────────────
Future<void> _checkTimeframe(
  String symbol,
  String timeframe,
  SharedPreferences prefs,
  ServiceInstance service,
) async {
  try {
    final candles = await BinanceService.fetchCandles(symbol, timeframe);
    if (candles.length < 6) return; // need ≥ 6 for patterns + live candle

    final lastClosed = candles[candles.length - 2];
    final liveCandle = candles[candles.length - 1];

    // ═══════════════════════════════════════════════════
    // HH / LL ALERTS
    // ═══════════════════════════════════════════════════
    final result = PivotService.getHHLL(candles);

    // ─── Higher High ───────────────────────────────────
    if (result.hh != null) {
      final key = 'HH_${symbol}_${timeframe}_${result.hh!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(key) ?? false;
      final isHit = PivotService.isHit(lastClosed, result.hh!, true) ||
          PivotService.isHit(liveCandle, result.hh!, true);

      if (!alreadyAlerted && isHit) {
        final ok = await TelegramService.sendHitAlert(
          levelType: 'HH',
          levelPrice: result.hh!,
          timeframe: timeframe,
          currentPrice: liveCandle.close,
          symbol: symbol,
        );
        if (ok) {
          await prefs.setBool(key, true);
          service.invoke('alert', {
            'symbol': symbol,
            'type': 'HH',
            'price': result.hh!,
            'timeframe': timeframe,
            'time': DateTime.now().toIso8601String(),
          });
          print('✅ $symbol HH @ ${result.hh} ($timeframe)');
        } else {
          print('❌ Telegram failed — $symbol HH');
        }
      }
    }

    // ─── Lower Low ─────────────────────────────────────
    if (result.ll != null) {
      final key = 'LL_${symbol}_${timeframe}_${result.ll!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(key) ?? false;
      final isHit = PivotService.isHit(lastClosed, result.ll!, false) ||
          PivotService.isHit(liveCandle, result.ll!, false);

      if (!alreadyAlerted && isHit) {
        final ok = await TelegramService.sendHitAlert(
          levelType: 'LL',
          levelPrice: result.ll!,
          timeframe: timeframe,
          currentPrice: liveCandle.close,
          symbol: symbol,
        );
        if (ok) {
          await prefs.setBool(key, true);
          service.invoke('alert', {
            'symbol': symbol,
            'type': 'LL',
            'price': result.ll!,
            'timeframe': timeframe,
            'time': DateTime.now().toIso8601String(),
          });
          print('✅ $symbol LL @ ${result.ll} ($timeframe)');
        } else {
          print('❌ Telegram failed — $symbol LL');
        }
      }
    }

    // ═══════════════════════════════════════════════════
    // CANDLESTICK PATTERN ALERTS
    // Detect on last-closed candle only (exclude live candle)
    // so the timestamp dedup key is stable between bot ticks.
    // ═══════════════════════════════════════════════════
    final closedCandles = candles.sublist(0, candles.length - 1);
    final patResult = CandlestickPatternService.detect(closedCandles);

    if (patResult.hasPattern) {
      // Dedup key uses the last-closed candle's open-time
      final barTimestamp =
          closedCandles.last.time.millisecondsSinceEpoch.toString();
      final closePrice = closedCandles.last.close;

      // ─── Bullish Engulfing ──────────────────────────
      if (patResult.isBE) {
        final key = 'PAT_BE_${symbol}_${timeframe}_$barTimestamp';
        if (!(prefs.getBool(key) ?? false)) {
          final ok = await TelegramService.sendPatternAlertAll(
            patternType: 'BE',
            symbol: symbol,
            timeframe: timeframe,
            price: closePrice,
          );
          if (ok) {
            await prefs.setBool(key, true);
            service.invoke('alert', {
              'symbol': symbol,
              'type': 'BE',
              'price': closePrice,
              'timeframe': timeframe,
              'time': DateTime.now().toIso8601String(),
            });
            print('✅ $symbol Bullish Engulfing ($timeframe)');
          } else {
            print('❌ Telegram failed — $symbol BE');
          }
        }
      }

      // ─── Morning Star ───────────────────────────────
      if (patResult.isMS) {
        final key = 'PAT_MS_${symbol}_${timeframe}_$barTimestamp';
        if (!(prefs.getBool(key) ?? false)) {
          final ok = await TelegramService.sendPatternAlertAll(
            patternType: 'MS',
            symbol: symbol,
            timeframe: timeframe,
            price: closePrice,
          );
          if (ok) {
            await prefs.setBool(key, true);
            service.invoke('alert', {
              'symbol': symbol,
              'type': 'MS',
              'price': closePrice,
              'timeframe': timeframe,
              'time': DateTime.now().toIso8601String(),
            });
            print('✅ $symbol Morning Star ($timeframe)');
          } else {
            print('❌ Telegram failed — $symbol MS');
          }
        }
      }

      // ─── Evening Star ───────────────────────────────
      if (patResult.isES) {
        final key = 'PAT_ES_${symbol}_${timeframe}_$barTimestamp';
        if (!(prefs.getBool(key) ?? false)) {
          final ok = await TelegramService.sendPatternAlertAll(
            patternType: 'ES',
            symbol: symbol,
            timeframe: timeframe,
            price: closePrice,
          );
          if (ok) {
            await prefs.setBool(key, true);
            service.invoke('alert', {
              'symbol': symbol,
              'type': 'ES',
              'price': closePrice,
              'timeframe': timeframe,
              'time': DateTime.now().toIso8601String(),
            });
            print('✅ $symbol Evening Star ($timeframe)');
          } else {
            print('❌ Telegram failed — $symbol ES');
          }
        }
      }
    }
  } catch (e) {
    print('❌ Error on $symbol $timeframe: $e');
  }
}
