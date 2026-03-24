// ─── config.dart ────────────────────────────────────────
// Runtime-editable config. Values load from SharedPreferences
// on app start; defaults are used if no saved value exists.

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Config {
  // ─── TELEGRAM ─────────────────────────────────────────
  static String botToken = 'YOUR_TELEGRAM_BOT_TOKEN';
  static String chatId   = 'YOUR_TELEGRAM_CHAT_ID';

  // ─── TRADING PAIRS ────────────────────────────────────
  static List<String> symbols = [
    'BTCUSDT',
    'ETHUSDT',
    'SOLUSDT',
    'XRPUSDT',
  ];

  // ─── TIMEFRAMES ───────────────────────────────────────
  static List<String> timeframes = ['30m', '1h'];

  // ─── INDICATOR SETTINGS ───────────────────────────────
  static int pivotLen = 5;
  static int limit    = 1000;

  // ─── BOT SETTINGS ─────────────────────────────────────
  static int checkEveryMinutes = 5;

  // ─── CANDLESTICK PATTERN SETTINGS ─────────────────────
  static bool   patternBE          = true;   // Bullish Engulfing
  static bool   patternMS          = true;   // Morning Star
  static bool   patternES          = true;   // Evening Star
  static bool   patternRequireTrend = true;  // Require prior trend
  static double patternStarBodyPct  = 30.0;  // Star max body % of range (5–50)
  static double patternRecoveryPct  = 50.0;  // MS/ES recovery % into C1 body (20–80)
}

// ─── CONFIG SERVICE ──────────────────────────────────────
class ConfigService {
  // HH/LL keys
  static const _kBotToken   = 'cfg_bot_token';
  static const _kChatId     = 'cfg_chat_id';
  static const _kSymbols    = 'cfg_symbols';
  static const _kTimeframes = 'cfg_timeframes';
  static const _kPivotLen   = 'cfg_pivot_len';
  static const _kLimit      = 'cfg_limit';
  static const _kCheckEvery = 'cfg_check_every';

  // Pattern keys
  static const _kPatternBE           = 'cfg_pattern_be';
  static const _kPatternMS           = 'cfg_pattern_ms';
  static const _kPatternES           = 'cfg_pattern_es';
  static const _kPatternRequireTrend = 'cfg_pattern_require_trend';
  static const _kPatternStarBodyPct  = 'cfg_pattern_star_body_pct';
  static const _kPatternRecoveryPct  = 'cfg_pattern_recovery_pct';

  // ─── Load from disk ───────────────────────────────────
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    Config.botToken          = prefs.getString(_kBotToken)       ?? Config.botToken;
    Config.chatId            = prefs.getString(_kChatId)         ?? Config.chatId;
    Config.symbols           = prefs.getStringList(_kSymbols)    ?? Config.symbols;
    Config.timeframes        = prefs.getStringList(_kTimeframes) ?? Config.timeframes;
    Config.pivotLen          = prefs.getInt(_kPivotLen)          ?? Config.pivotLen;
    Config.limit             = prefs.getInt(_kLimit)             ?? Config.limit;
    Config.checkEveryMinutes = prefs.getInt(_kCheckEvery)        ?? Config.checkEveryMinutes;

    Config.patternBE           = prefs.getBool(_kPatternBE)             ?? Config.patternBE;
    Config.patternMS           = prefs.getBool(_kPatternMS)             ?? Config.patternMS;
    Config.patternES           = prefs.getBool(_kPatternES)             ?? Config.patternES;
    Config.patternRequireTrend = prefs.getBool(_kPatternRequireTrend)   ?? Config.patternRequireTrend;
    Config.patternStarBodyPct  = prefs.getDouble(_kPatternStarBodyPct)  ?? Config.patternStarBodyPct;
    Config.patternRecoveryPct  = prefs.getDouble(_kPatternRecoveryPct)  ?? Config.patternRecoveryPct;
  }

  // ─── Push ALL config live to background isolate ───────
  static Future<void> _pushToBackground() async {
    final svc = FlutterBackgroundService();
    if (!await svc.isRunning()) return;

    svc.invoke('updateConfig', {
      'botToken':          Config.botToken,
      'chatId':            Config.chatId,
      'symbols':           Config.symbols,
      'timeframes':        Config.timeframes,
      'pivotLen':          Config.pivotLen,
      'limit':             Config.limit,
      'checkEveryMinutes': Config.checkEveryMinutes,
      // Pattern settings
      'patternBE':           Config.patternBE,
      'patternMS':           Config.patternMS,
      'patternES':           Config.patternES,
      'patternRequireTrend': Config.patternRequireTrend,
      'patternStarBodyPct':  Config.patternStarBodyPct,
      'patternRecoveryPct':  Config.patternRecoveryPct,
    });
  }

  // ─── Wipe ALL dedup keys (HH_, LL_, PAT_) ────────────
  static Future<void> _clearAllDedupKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final stale = prefs.getKeys()
        .where((k) =>
            k.startsWith('HH_') ||
            k.startsWith('LL_') ||
            k.startsWith('PAT_'))
        .toList();
    for (final k in stale) {
      await prefs.remove(k);
    }
    print('🧹 Cleared ${stale.length} dedup keys');
  }

  // ─── Save Telegram ────────────────────────────────────
  static Future<void> saveTelegram({
    required String botToken,
    required String chatId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBotToken, botToken);
    await prefs.setString(_kChatId, chatId);
    Config.botToken = botToken;
    Config.chatId   = chatId;
    await _pushToBackground();
  }

  // ─── Save Trading Pairs ───────────────────────────────
  static Future<void> saveSymbols(List<String> newSymbols) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearAllDedupKeys();
    await prefs.setStringList(_kSymbols, newSymbols);
    Config.symbols = newSymbols;
    await _pushToBackground();
  }

  // ─── Save Timeframes ──────────────────────────────────
  static Future<void> saveTimeframes(List<String> timeframes) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearAllDedupKeys();
    await prefs.setStringList(_kTimeframes, timeframes);
    Config.timeframes = timeframes;
    await _pushToBackground();
  }

  // ─── Save Indicator Settings ──────────────────────────
  static Future<void> saveIndicator({
    required int pivotLen,
    required int limit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPivotLen, pivotLen);
    await prefs.setInt(_kLimit, limit);
    Config.pivotLen = pivotLen;
    Config.limit    = limit;
    await _pushToBackground();
  }

  // ─── Save Bot Settings ────────────────────────────────
  static Future<void> saveBotSettings({required int checkEveryMinutes}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCheckEvery, checkEveryMinutes);
    Config.checkEveryMinutes = checkEveryMinutes;
    await _pushToBackground();
  }

  // ─── Save Pattern Settings ────────────────────────────
  static Future<void> savePatternSettings({
    required bool   patternBE,
    required bool   patternMS,
    required bool   patternES,
    required bool   patternRequireTrend,
    required double patternStarBodyPct,
    required double patternRecoveryPct,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPatternBE,           patternBE);
    await prefs.setBool(_kPatternMS,           patternMS);
    await prefs.setBool(_kPatternES,           patternES);
    await prefs.setBool(_kPatternRequireTrend, patternRequireTrend);
    await prefs.setDouble(_kPatternStarBodyPct, patternStarBodyPct);
    await prefs.setDouble(_kPatternRecoveryPct, patternRecoveryPct);

    Config.patternBE           = patternBE;
    Config.patternMS           = patternMS;
    Config.patternES           = patternES;
    Config.patternRequireTrend = patternRequireTrend;
    Config.patternStarBodyPct  = patternStarBodyPct;
    Config.patternRecoveryPct  = patternRecoveryPct;

    await _pushToBackground();
  }
}
