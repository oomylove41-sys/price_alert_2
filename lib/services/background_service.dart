// ─── services/background_service.dart ───────────────────
// Runs the bot logic in the background even when app is closed.
// Supports two alert types:
//   1. HIT  — price touches an existing HH/LL level
//   2. NEW  — a brand-new HH/LL pivot is formed

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

// ─── Top-level state (isolate-local) ─────────────────────
Timer? _checkTimer;
bool   _isBusy     = false;
bool   _shouldStop = false;

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
      onStart:                     onBackgroundStart,
      autoStart:                   false,
      isForegroundMode:            true,
      notificationChannelId:       'hh_ll_bot_channel',
      initialNotificationTitle:    'HH/LL Bot',
      initialNotificationContent:  'Bot is running...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart:    false,
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

  // Reset state from any previous run
  _shouldStop = false;
  _isBusy     = false;
  _checkTimer?.cancel();
  _checkTimer = null;

  print('🚀 Background service started');

  await ConfigService.load();
  print('✅ Config loaded: ${Config.symbols} | ${Config.timeframes} | '
      'every ${Config.checkEveryMinutes}m | ${Config.bots.length} bot(s)');

  // ─── Stop command ─────────────────────────────────────
  service.on('stop').listen((event) {
    print('🛑 Stop command received');
    _shouldStop = true;
    _checkTimer?.cancel();
    _checkTimer = null;
    service.stopSelf();
  });

  // ─── Live config update from main isolate ─────────────
  service.on('updateConfig').listen((data) {
    if (data == null) return;

    if (data['bots'] != null) {
      try {
        final list = data['bots'] as List;
        Config.bots = list
            .map((j) => TelegramBot.fromJson(
                Map<String, dynamic>.from(j as Map)))
            .toList();
      } catch (e) {
        print('⚠️ Failed to parse bots update: $e');
      }
    }
    if (data['symbols']  != null) Config.symbols   = List<String>.from(data['symbols'] as List);
    if (data['timeframes'] != null) Config.timeframes = List<String>.from(data['timeframes'] as List);
    if (data['pivotLen'] != null) Config.pivotLen  = data['pivotLen'] as int;
    if (data['limit']    != null) Config.limit     = data['limit']    as int;

    if (data['checkEveryMinutes'] != null) {
      final newInterval = data['checkEveryMinutes'] as int;
      final changed = newInterval != Config.checkEveryMinutes;
      Config.checkEveryMinutes = newInterval;
      if (changed) {
        print('⏱ Interval changed to ${Config.checkEveryMinutes}m — restarting timer');
        _restartTimer(service);
      }
    }

    print('🔄 Config updated: symbols=${Config.symbols}, '
        'interval=${Config.checkEveryMinutes}m, '
        '${Config.bots.length} bot(s)');
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
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    print('🔍 Checking ${Config.symbols} on ${Config.timeframes} at $timeStr');

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title:   'HH/LL Bot — Last check: $timeStr',
        content: '${Config.symbols.length} pairs · ${Config.timeframes.join(', ')}',
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
    if (candles.length < 2) return;

    final result     = PivotService.getHHLL(candles);
    final lastClosed = candles[candles.length - 2];
    final liveCandle = candles[candles.length - 1];

    // ──────────────────────────────────────────────────
    // ALERT TYPE 1 — HIT: Price touches existing HH/LL
    // ──────────────────────────────────────────────────

    // HH Hit
    if (result.hh != null) {
      final hitKey = 'HH_HIT_${symbol}_${timeframe}_${result.hh!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(hitKey) ?? false;
      final isHit = PivotService.isHit(lastClosed, result.hh!, true) ||
                    PivotService.isHit(liveCandle,  result.hh!, true);

      if (!alreadyAlerted && isHit) {
        final ok = await TelegramService.sendHitAlert(
          levelType:    'HH',
          levelPrice:   result.hh!,
          timeframe:    timeframe,
          currentPrice: liveCandle.close,
          symbol:       symbol,
        );
        if (ok) {
          await prefs.setBool(hitKey, true);
          service.invoke('alert', {
            'symbol':    symbol,
            'type':      'HH',
            'kind':      'hit',
            'price':     result.hh!,
            'timeframe': timeframe,
            'time':      DateTime.now().toIso8601String(),
          });
          print('✅ HIT $symbol HH @ ${result.hh} ($timeframe)');
        } else {
          print('❌ Telegram failed — HIT $symbol HH');
        }
      }
    }

    // LL Hit
    if (result.ll != null) {
      final hitKey = 'LL_HIT_${symbol}_${timeframe}_${result.ll!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(hitKey) ?? false;
      final isHit = PivotService.isHit(lastClosed, result.ll!, false) ||
                    PivotService.isHit(liveCandle,  result.ll!, false);

      if (!alreadyAlerted && isHit) {
        final ok = await TelegramService.sendHitAlert(
          levelType:    'LL',
          levelPrice:   result.ll!,
          timeframe:    timeframe,
          currentPrice: liveCandle.close,
          symbol:       symbol,
        );
        if (ok) {
          await prefs.setBool(hitKey, true);
          service.invoke('alert', {
            'symbol':    symbol,
            'type':      'LL',
            'kind':      'hit',
            'price':     result.ll!,
            'timeframe': timeframe,
            'time':      DateTime.now().toIso8601String(),
          });
          print('✅ HIT $symbol LL @ ${result.ll} ($timeframe)');
        } else {
          print('❌ Telegram failed — HIT $symbol LL');
        }
      }
    }

    // ──────────────────────────────────────────────────
    // ALERT TYPE 2 — NEW: A new HH/LL pivot was formed
    // Uses a separate dedup key (HH_NEW_ / LL_NEW_) so
    // it fires once per newly detected level regardless
    // of whether price has touched it.
    // ──────────────────────────────────────────────────

    // New HH
    if (result.hh != null) {
      final newKey = 'HH_NEW_${symbol}_${timeframe}_${result.hh!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(newKey) ?? false;

      if (!alreadyAlerted) {
        final ok = await TelegramService.sendNewLevelAlert(
          levelType:  'HH',
          levelPrice: result.hh!,
          timeframe:  timeframe,
          symbol:     symbol,
        );
        // Always mark seen (even if no bots enabled) to prevent
        // repeated checks on the same level value.
        await prefs.setBool(newKey, true);

        if (ok) {
          service.invoke('alert', {
            'symbol':    symbol,
            'type':      'HH',
            'kind':      'new',
            'price':     result.hh!,
            'timeframe': timeframe,
            'time':      DateTime.now().toIso8601String(),
          });
          print('✨ NEW $symbol HH @ ${result.hh} ($timeframe)');
        }
      }
    }

    // New LL
    if (result.ll != null) {
      final newKey = 'LL_NEW_${symbol}_${timeframe}_${result.ll!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(newKey) ?? false;

      if (!alreadyAlerted) {
        final ok = await TelegramService.sendNewLevelAlert(
          levelType:  'LL',
          levelPrice: result.ll!,
          timeframe:  timeframe,
          symbol:     symbol,
        );
        await prefs.setBool(newKey, true);

        if (ok) {
          service.invoke('alert', {
            'symbol':    symbol,
            'type':      'LL',
            'kind':      'new',
            'price':     result.ll!,
            'timeframe': timeframe,
            'time':      DateTime.now().toIso8601String(),
          });
          print('✨ NEW $symbol LL @ ${result.ll} ($timeframe)');
        }
      }
    }
  } catch (e) {
    print('❌ Error on $symbol $timeframe: $e');
  }
}
