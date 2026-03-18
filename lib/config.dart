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
}

// ─── CONFIG SERVICE ──────────────────────────────────────
class ConfigService {
  static const _kBotToken   = 'cfg_bot_token';
  static const _kChatId     = 'cfg_chat_id';
  static const _kSymbols    = 'cfg_symbols';
  static const _kTimeframes = 'cfg_timeframes';
  static const _kPivotLen   = 'cfg_pivot_len';
  static const _kLimit      = 'cfg_limit';
  static const _kCheckEvery = 'cfg_check_every';

  // ─── Load from disk ───────────────────────────────────
  // Called in BOTH isolates. prefs.reload() forces a fresh
  // disk read so the background isolate's stale cache is flushed.
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
  }

  // ─── Push config live to background service via IPC ───
  // This bypasses SharedPreferences cross-isolate caching and
  // updates Config.* in the background isolate immediately.
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
    });
  }

  // ─── Wipe ALL HH_* / LL_* dedup keys ─────────────────
  // Ensures no pair is permanently silenced by a stale flag.
  // Called every time symbols or timeframes change.
  static Future<void> _clearAllDedupKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final stale = prefs.getKeys()
        .where((k) => k.startsWith('HH_') || k.startsWith('LL_'))
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
  // Clears ALL dedup keys so every pair gets a fresh start —
  // both kept pairs (whose old HH/LL flags would block them)
  // and newly added pairs.
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
}
