// ─── services/background_service.dart ───────────────────
// Runs the bot logic in the background even when app is closed.

import 'dart:async';
import 'package:flutter/widgets.dart'; // ← FIX 1: needed for DartPluginRegistrant
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'binance_service.dart';
import 'pivot_service.dart';
import 'telegram_service.dart';

// ─── FIX 2: Top-level timer so it can be cancelled/restarted ─
Timer? _checkTimer;
bool _isBusy = false; // guard against overlapping runs

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
      // ─── FIX 4: declare the foreground service type ───
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
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
  // ─── FIX 1: required in every isolate entry point ────
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

// ─── MAIN BACKGROUND LOOP ────────────────────────────────
@pragma('vm:entry-point')
void onBackgroundStart(ServiceInstance service) async {
  // ─── FIX 1: CRITICAL — without this, ALL Flutter plugins
  //     (http, SharedPreferences, etc.) silently do nothing
  //     in the background isolate. This is the #1 cause of
  //     the bot "doing nothing" after start. ───────────────
  WidgetsFlutterBinding.ensureInitialized();
  ;

  print('🚀 Background service started');

  // Load saved config from disk into this isolate's Config.*
  await ConfigService.load();
  print(
      '✅ Config loaded: ${Config.symbols} | ${Config.timeframes} | every ${Config.checkEveryMinutes}m');

  // ─── Stop command ─────────────────────────────────────
  // FIX 3: also cancel the timer so it stops firing
  service.on('stop').listen((event) {
    _checkTimer?.cancel();
    _checkTimer = null;
    service.stopSelf();
    print('🛑 Background service stopped');
  });

  // ─── Live config update from main isolate ─────────────
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
      final intervalChanged = newInterval != Config.checkEveryMinutes;
      Config.checkEveryMinutes = newInterval;

      // ─── FIX 2: restart the timer when the interval changes ──
      if (intervalChanged) {
        print(
            '⏱ Interval changed to ${Config.checkEveryMinutes}m — restarting timer');
        _restartTimer(service);
      }
    }

    print('🔄 Config updated live: symbols=${Config.symbols}');
  });

  // Run one check immediately on start
  await _runAllChecks(service);

  // ─── FIX 2: use a restartable timer instead of a
  //     one-shot Timer.periodic that never updates ─────────
  _restartTimer(service);
}

// ─── FIX 2: Cancels any existing timer and starts a fresh one ─
void _restartTimer(ServiceInstance service) {
  _checkTimer?.cancel();
  _checkTimer = Timer.periodic(
    Duration(minutes: Config.checkEveryMinutes),
    (timer) async {
      // Guard: skip if a previous run is still in progress
      if (_isBusy) {
        print('⏳ Previous check still running — skipping tick');
        return;
      }

      final isRunning = await FlutterBackgroundService().isRunning();
      if (!isRunning) {
        timer.cancel();
        return;
      }

      // Reload from disk each tick as a fallback for missed IPC updates
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
    await prefs.reload(); // flush cache before reading dedup keys
    final now = DateTime.now();

    print('🔍 Checking ${Config.symbols} on ${Config.timeframes} — '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');

    service.invoke('update', {
      'lastCheck':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    });

    for (final symbol in Config.symbols) {
      for (final timeframe in Config.timeframes) {
        await _checkTimeframe(symbol, timeframe, prefs, service);
      }
    }
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

    final result = PivotService.getHHLL(candles);
    final lastClosed = candles[candles.length - 2];
    final liveCandle = candles[candles.length - 1];

    // ─── HH ─────────────────────────────────────────────
    if (result.hh != null) {
      final key = 'HH_${symbol}_${timeframe}_${result.hh!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(key) ?? false;
      final isHit = PivotService.isHit(lastClosed, result.hh!, true) ||
          PivotService.isHit(liveCandle, result.hh!, true);

      if (!alreadyAlerted && isHit) {
        final ok = await TelegramService.sendAlert(
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

    // ─── LL ─────────────────────────────────────────────
    if (result.ll != null) {
      final key = 'LL_${symbol}_${timeframe}_${result.ll!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(key) ?? false;
      final isHit = PivotService.isHit(lastClosed, result.ll!, false) ||
          PivotService.isHit(liveCandle, result.ll!, false);

      if (!alreadyAlerted && isHit) {
        final ok = await TelegramService.sendAlert(
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
  } catch (e) {
    print('❌ Error on $symbol $timeframe: $e');
  }
}
