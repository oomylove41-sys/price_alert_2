// ─── config.dart ────────────────────────────────────────
// Runtime-editable config. Supports multiple Telegram bots
// with configurable alert types per bot.

import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════
// ─── TELEGRAM BOT MODEL ──────────────────────────────────
// ══════════════════════════════════════════════════════════
class TelegramBot {
  final String id;
  String name;
  String token;
  String chatId;
  bool alertOnHit;   // alert when price HITS an existing HH/LL level
  bool alertOnNew;   // alert when a NEW HH/LL is created

  TelegramBot({
    required this.id,
    required this.name,
    required this.token,
    required this.chatId,
    this.alertOnHit = true,
    this.alertOnNew = false,
  });

  TelegramBot copyWith({
    String? name,
    String? token,
    String? chatId,
    bool? alertOnHit,
    bool? alertOnNew,
  }) {
    return TelegramBot(
      id: id,
      name: name ?? this.name,
      token: token ?? this.token,
      chatId: chatId ?? this.chatId,
      alertOnHit: alertOnHit ?? this.alertOnHit,
      alertOnNew: alertOnNew ?? this.alertOnNew,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'token': token,
    'chatId': chatId,
    'alertOnHit': alertOnHit,
    'alertOnNew': alertOnNew,
  };

  factory TelegramBot.fromJson(Map<String, dynamic> j) => TelegramBot(
    id:         j['id']         as String? ?? _genId(),
    name:       j['name']       as String? ?? 'Bot',
    token:      j['token']      as String? ?? '',
    chatId:     j['chatId']     as String? ?? '',
    alertOnHit: j['alertOnHit'] as bool?   ?? true,
    alertOnNew: j['alertOnNew'] as bool?   ?? false,
  );

  static String _genId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  bool get isConfigured =>
      token.isNotEmpty &&
      token != 'YOUR_TELEGRAM_BOT_TOKEN' &&
      chatId.isNotEmpty &&
      chatId != 'YOUR_TELEGRAM_CHAT_ID';
}

// ══════════════════════════════════════════════════════════
// ─── CONFIG ──────────────────────────────────────────────
// ══════════════════════════════════════════════════════════
class Config {
  // ─── TELEGRAM BOTS ────────────────────────────────────
  static List<TelegramBot> bots = [_defaultBot()];

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

TelegramBot _defaultBot() => TelegramBot(
  id:         'default',
  name:       'Main Bot',
  token:      'YOUR_TELEGRAM_BOT_TOKEN',
  chatId:     'YOUR_TELEGRAM_CHAT_ID',
  alertOnHit: true,
  alertOnNew: false,
);

// ══════════════════════════════════════════════════════════
// ─── CONFIG SERVICE ──────────────────────────────────────
// ══════════════════════════════════════════════════════════
class ConfigService {
  static const _kBotsV2   = 'cfg_bots_v2';
  // Legacy single-bot keys (used for migration)
  static const _kBotToken = 'cfg_bot_token';
  static const _kChatId   = 'cfg_chat_id';

  static const _kSymbols   = 'cfg_symbols';
  static const _kTimeframes = 'cfg_timeframes';
  static const _kPivotLen  = 'cfg_pivot_len';
  static const _kLimit     = 'cfg_limit';
  static const _kCheckEvery = 'cfg_check_every';

  // ─── Load from disk ───────────────────────────────────
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // Load bots (with v1 → v2 migration)
    final botsStr = prefs.getString(_kBotsV2);
    if (botsStr != null && botsStr.isNotEmpty) {
      try {
        final list = jsonDecode(botsStr) as List;
        final bots = list
            .map((j) => TelegramBot.fromJson(
                Map<String, dynamic>.from(j as Map)))
            .toList();
        Config.bots = bots.isNotEmpty ? bots : [_defaultBot()];
      } catch (_) {
        Config.bots = [_defaultBot()];
      }
    } else {
      // Migrate from legacy single-bot config
      final oldToken  = prefs.getString(_kBotToken);
      final oldChatId = prefs.getString(_kChatId);
      if (oldToken != null && oldToken.isNotEmpty) {
        Config.bots = [
          TelegramBot(
            id:         'migrated',
            name:       'Main Bot',
            token:      oldToken,
            chatId:     oldChatId ?? '',
            alertOnHit: true,
            alertOnNew: false,
          ),
        ];
        // Persist in new format
        await _persistBots(prefs);
      }
    }

    Config.symbols          = prefs.getStringList(_kSymbols)    ?? Config.symbols;
    Config.timeframes       = prefs.getStringList(_kTimeframes) ?? Config.timeframes;
    Config.pivotLen         = prefs.getInt(_kPivotLen)          ?? Config.pivotLen;
    Config.limit            = prefs.getInt(_kLimit)             ?? Config.limit;
    Config.checkEveryMinutes = prefs.getInt(_kCheckEvery)       ?? Config.checkEveryMinutes;
  }

  // ─── Push live config update to background isolate ────
  static Future<void> _pushToBackground() async {
    final svc = FlutterBackgroundService();
    if (!await svc.isRunning()) return;

    svc.invoke('updateConfig', {
      'bots':              Config.bots.map((b) => b.toJson()).toList(),
      'symbols':           Config.symbols,
      'timeframes':        Config.timeframes,
      'pivotLen':          Config.pivotLen,
      'limit':             Config.limit,
      'checkEveryMinutes': Config.checkEveryMinutes,
    });
  }

  // ─── Persist bots to SharedPreferences ────────────────
  static Future<void> _persistBots(SharedPreferences prefs) async {
    final json = jsonEncode(Config.bots.map((b) => b.toJson()).toList());
    await prefs.setString(_kBotsV2, json);
  }

  // ─── Clear all HH_* / LL_* dedup keys ────────────────
  // Covers both hit keys (HH_...) and new-level keys (HH_NEW_...)
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

  // ─── Save bots ────────────────────────────────────────
  static Future<void> saveBots(List<TelegramBot> bots) async {
    final prefs = await SharedPreferences.getInstance();
    Config.bots = List.from(bots);
    await _persistBots(prefs);
    await _pushToBackground();
  }

  // ─── Save Telegram (legacy single-bot shim) ───────────
  static Future<void> saveTelegram({
    required String botToken,
    required String chatId,
  }) async {
    if (Config.bots.isNotEmpty) {
      Config.bots[0] = Config.bots[0].copyWith(
        token: botToken,
        chatId: chatId,
      );
    }
    await saveBots(Config.bots);
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
}
