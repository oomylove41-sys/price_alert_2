// ─── services/background_service.dart ───────────────────
// Runs the bot logic in the background even when app is closed.

import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'binance_service.dart';
import 'pivot_service.dart';
import 'telegram_service.dart';

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
  return true;
}

// ─── MAIN BACKGROUND LOOP ────────────────────────────────
@pragma('vm:entry-point')
void onBackgroundStart(ServiceInstance service) async {
  print('🚀 Background service started');

  // Load saved config from disk into this isolate's Config.*
  await ConfigService.load();
  print('✅ Config loaded: ${Config.symbols} | ${Config.timeframes}');

  // ─── Stop command ────────────────────────────────────
  service.on('stop').listen((event) {
    service.stopSelf();
    print('🛑 Background service stopped');
  });

  // ─── Live config update from main isolate ────────────
  // When the user saves any setting, ConfigService._pushToBackground()
  // calls service.invoke('updateConfig', {...}) which is received here.
  // This immediately updates Config.* without waiting for next timer
  // tick and without relying on unreliable cross-isolate prefs caching.
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
      Config.checkEveryMinutes = data['checkEveryMinutes'] as int;
    }

    print('🔄 Config updated live: symbols=${Config.symbols}');
  });

  // Run one check immediately on start
  await _runAllChecks(service);

  // Then repeat on interval
  Timer.periodic(Duration(minutes: Config.checkEveryMinutes), (timer) async {
    final isRunning = await FlutterBackgroundService().isRunning();
    if (!isRunning) {
      timer.cancel();
      return;
    }
    // Also reload from disk each tick as a fallback
    await ConfigService.load();
    await _runAllChecks(service);
  });
}

// ─── CHECK ALL SYMBOLS & TIMEFRAMES ──────────────────────
Future<void> _runAllChecks(ServiceInstance service) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // always flush cache before reading dedup keys
  final now = DateTime.now();

  print('🔍 Checking ${Config.symbols} on ${Config.timeframes} — ${now.hour}:${now.minute}');

  service.invoke('update', {
    'lastCheck':
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
  });

  for (final symbol in Config.symbols) {
    for (final timeframe in Config.timeframes) {
      await _checkTimeframe(symbol, timeframe, prefs, service);
    }
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

    // ─── HH ─────────────────────────────────────────────
    if (result.hh != null) {
      final key          = 'HH_${symbol}_${timeframe}_${result.hh!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(key) ?? false;
      final isHit = PivotService.isHit(lastClosed, result.hh!, true) ||
                    PivotService.isHit(liveCandle,  result.hh!, true);

      if (!alreadyAlerted && isHit) {
        final ok = await TelegramService.sendAlert(
          levelType:    'HH',
          levelPrice:   result.hh!,
          timeframe:    timeframe,
          currentPrice: liveCandle.close,
          symbol:       symbol,
        );
        if (ok) {
          await prefs.setBool(key, true);
          service.invoke('alert', {
            'symbol':    symbol,
            'type':      'HH',
            'price':     result.hh!,
            'timeframe': timeframe,
            'time':      DateTime.now().toIso8601String(),
          });
          print('✅ $symbol HH @ ${result.hh} ($timeframe)');
        } else {
          print('❌ Telegram failed — $symbol HH');
        }
      }
    }

    // ─── LL ─────────────────────────────────────────────
    if (result.ll != null) {
      final key          = 'LL_${symbol}_${timeframe}_${result.ll!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(key) ?? false;
      final isHit = PivotService.isHit(lastClosed, result.ll!, false) ||
                    PivotService.isHit(liveCandle,  result.ll!, false);

      if (!alreadyAlerted && isHit) {
        final ok = await TelegramService.sendAlert(
          levelType:    'LL',
          levelPrice:   result.ll!,
          timeframe:    timeframe,
          currentPrice: liveCandle.close,
          symbol:       symbol,
        );
        if (ok) {
          await prefs.setBool(key, true);
          service.invoke('alert', {
            'symbol':    symbol,
            'type':      'LL',
            'price':     result.ll!,
            'timeframe': timeframe,
            'time':      DateTime.now().toIso8601String(),
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
