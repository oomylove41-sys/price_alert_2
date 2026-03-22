// ─── services/background_service.dart ───────────────────
// Background bot. Monitors the UNION of all bot timeframes
// (Config.effectiveTimeframes). Each alert is routed only to
// bots that have subscribed to that specific timeframe.

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

// ─── Top-level isolate-local state ───────────────────────
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
      onStart:                         onBackgroundStart,
      autoStart:                       false,
      isForegroundMode:                true,
      notificationChannelId:           'hh_ll_bot_channel',
      initialNotificationTitle:        'HH/LL Bot',
      initialNotificationContent:      'Bot is running...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart:    false,
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

// ─── MAIN BACKGROUND ENTRY POINT ─────────────────────────
@pragma('vm:entry-point')
void onBackgroundStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  _shouldStop = false;
  _isBusy     = false;
  _checkTimer?.cancel();
  _checkTimer = null;

  print('🚀 Background service started');
  await ConfigService.load();

  final tfs = Config.effectiveTimeframes;
  print('✅ Config loaded — symbols: ${Config.symbols} | '
      'effective timeframes: $tfs | '
      'every ${Config.checkEveryMinutes}m | '
      '${Config.bots.length} bot(s)');

  // ─── Stop ─────────────────────────────────────────────
  service.on('stop').listen((event) {
    print('🛑 Stop command received');
    _shouldStop = true;
    _checkTimer?.cancel();
    _checkTimer = null;
    service.stopSelf();
  });

  // ─── Live config push from main isolate ───────────────
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
    if (data['symbols']  != null) Config.symbols   = List<String>.from(data['symbols']  as List);
    if (data['pivotLen'] != null) Config.pivotLen   = data['pivotLen'] as int;
    if (data['limit']    != null) Config.limit      = data['limit']    as int;

    if (data['checkEveryMinutes'] != null) {
      final newInterval = data['checkEveryMinutes'] as int;
      final changed = newInterval != Config.checkEveryMinutes;
      Config.checkEveryMinutes = newInterval;
      if (changed) {
        print('⏱ Interval changed to ${Config.checkEveryMinutes}m — restarting timer');
        _restartTimer(service);
      }
    }
    print('🔄 Config updated: ${Config.bots.length} bot(s), '
        'effective TFs: ${Config.effectiveTimeframes}');
  });

  await _runAllChecks(service);
  _restartTimer(service);
}

// ─── Timer ───────────────────────────────────────────────
void _restartTimer(ServiceInstance service) {
  _checkTimer?.cancel();
  _checkTimer = Timer.periodic(
    Duration(minutes: Config.checkEveryMinutes),
    (timer) async {
      if (_shouldStop) { timer.cancel(); return; }
      if (_isBusy) {
        print('⏳ Previous check still running — skipping tick');
        return;
      }
      await ConfigService.load();
      await _runAllChecks(service);
    },
  );
  print('⏱ Timer started — every ${Config.checkEveryMinutes}m');
}

// ─── Run all checks ──────────────────────────────────────
Future<void> _runAllChecks(ServiceInstance service) async {
  if (_isBusy) return;
  _isBusy = true;

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // Compute the effective timeframes NOW so it reflects
    // any config changes since the last tick.
    final timeframes = Config.effectiveTimeframes;

    if (timeframes.isEmpty) {
      print('⚠️ No timeframes configured across any bot — skipping check');
      _isBusy = false;
      return;
    }

    final now     = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    print('🔍 Checking ${Config.symbols} on $timeframes at $timeStr');

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title:   'HH/LL Bot — Last check: $timeStr',
        content: '${Config.symbols.length} pair(s) · ${timeframes.join(', ')}',
      );
    }
    service.invoke('update', {'lastCheck': timeStr});

    for (final symbol in Config.symbols) {
      for (final timeframe in timeframes) {
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

// ─── Check one symbol + timeframe ────────────────────────
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

    // ── ALERT TYPE 1: HIT ────────────────────────────────
    // Only fires for bots that have this timeframe in hitTimeframes.

    if (result.hh != null) {
      final hitKey = 'HH_HIT_${symbol}_${timeframe}_'
          '${result.hh!.toStringAsFixed(5)}';
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
          print('❌ Telegram failed — HIT $symbol HH ($timeframe)');
        }
      }
    }

    if (result.ll != null) {
      final hitKey = 'LL_HIT_${symbol}_${timeframe}_'
          '${result.ll!.toStringAsFixed(5)}';
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
          print('❌ Telegram failed — HIT $symbol LL ($timeframe)');
        }
      }
    }

    // ── ALERT TYPE 2: NEW LEVEL ───────────────────────────
    // Only fires for bots that have this timeframe in newTimeframes.
    // Dedup key uses HH_NEW_ / LL_NEW_ prefix so it's independent.

    if (result.hh != null) {
      final newKey = 'HH_NEW_${symbol}_${timeframe}_'
          '${result.hh!.toStringAsFixed(5)}';
      final alreadyAlerted = prefs.getBool(newKey) ?? false;

      if (!alreadyAlerted) {
        final ok = await TelegramService.sendNewLevelAlert(
          levelType:  'HH',
          levelPrice: result.hh!,
          timeframe:  timeframe,
          symbol:     symbol,
        );
        // Always mark seen so we don't spam on same level value.
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

    if (result.ll != null) {
      final newKey = 'LL_NEW_${symbol}_${timeframe}_'
          '${result.ll!.toStringAsFixed(5)}';
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
