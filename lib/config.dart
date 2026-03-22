// ─── config.dart ────────────────────────────────────────
// Runtime-editable config. Supports multiple Telegram bots
// with per-bot, per-alert-type timeframe selection.

import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── All standard Binance timeframes (canonical order) ───
const List<String> kAllTimeframes = [
  '1m','3m','5m','15m','30m',
  '1h','2h','4h','6h','8h','12h',
  '1d','3d','1w','1M',
];

// ══════════════════════════════════════════════════════════
// ─── TELEGRAM BOT MODEL ──────────────────────────────────
// ══════════════════════════════════════════════════════════
class TelegramBot {
  final String id;
  String name;
  String token;
  String chatId;

  /// Timeframes this bot receives HIT alerts for.
  /// Empty = hit alerts off.
  List<String> hitTimeframes;

  /// Timeframes this bot receives NEW LEVEL alerts for.
  /// Empty = new level alerts off.
  List<String> newTimeframes;

  TelegramBot({
    required this.id,
    required this.name,
    required this.token,
    required this.chatId,
    List<String>? hitTimeframes,
    List<String>? newTimeframes,
  })  : hitTimeframes = hitTimeframes ?? [],
        newTimeframes = newTimeframes ?? [];

  // ─── Derived helpers ──────────────────────────────────
  bool get alertOnHit => hitTimeframes.isNotEmpty;
  bool get alertOnNew => newTimeframes.isNotEmpty;

  bool get isConfigured =>
      token.isNotEmpty &&
      token != 'YOUR_TELEGRAM_BOT_TOKEN' &&
      chatId.isNotEmpty &&
      chatId != 'YOUR_TELEGRAM_CHAT_ID';

  TelegramBot copyWith({
    String? name,
    String? token,
    String? chatId,
    List<String>? hitTimeframes,
    List<String>? newTimeframes,
  }) {
    return TelegramBot(
      id:            id,
      name:          name          ?? this.name,
      token:         token         ?? this.token,
      chatId:        chatId        ?? this.chatId,
      hitTimeframes: hitTimeframes ?? List.from(this.hitTimeframes),
      newTimeframes: newTimeframes ?? List.from(this.newTimeframes),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':            id,
    'name':          name,
    'token':         token,
    'chatId':        chatId,
    'hitTimeframes': hitTimeframes,
    'newTimeframes': newTimeframes,
  };

  factory TelegramBot.fromJson(Map<String, dynamic> j) {
    // Migrate from old boolean-only format
    List<String> parseTfList(dynamic raw, bool fallbackEnabled) {
      if (raw is List) return List<String>.from(raw);
      return fallbackEnabled ? ['30m', '1h'] : [];
    }
    final hitEnabled = j['alertOnHit'] as bool? ?? true;
    final newEnabled = j['alertOnNew'] as bool? ?? false;

    return TelegramBot(
      id:            j['id']    as String? ?? _genId(),
      name:          j['name']  as String? ?? 'Bot',
      token:         j['token'] as String? ?? '',
      chatId:        j['chatId'] as String? ?? '',
      hitTimeframes: parseTfList(j['hitTimeframes'], hitEnabled),
      newTimeframes: parseTfList(j['newTimeframes'], newEnabled),
    );
  }

  static String _genId() =>
      DateTime.now().millisecondsSinceEpoch.toString();
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

  // ─── INDICATOR SETTINGS ───────────────────────────────
  static int pivotLen = 5;
  static int limit    = 1000;

  // ─── BOT SETTINGS ─────────────────────────────────────
  static int checkEveryMinutes = 5;

  // ─── Effective timeframes ─────────────────────────────
  // Union of every timeframe referenced across all bots.
  // The background service only fetches candles for these.
  static List<String> get effectiveTimeframes {
    final Set<String> all = {};
    for (final bot in bots) {
      all.addAll(bot.hitTimeframes);
      all.addAll(bot.newTimeframes);
    }
    // Return in canonical Binance order
    return kAllTimeframes.where(all.contains).toList();
  }
}

TelegramBot _defaultBot() => TelegramBot(
  id:            'default',
  name:          'Main Bot',
  token:         'YOUR_TELEGRAM_BOT_TOKEN',
  chatId:        'YOUR_TELEGRAM_CHAT_ID',
  hitTimeframes: ['30m', '1h'],
  newTimeframes: [],
);

// ══════════════════════════════════════════════════════════
// ─── CONFIG SERVICE ──────────────════════════════════════
// ══════════════════════════════════════════════════════════
class ConfigService {
  static const _kBotsV2    = 'cfg_bots_v2';
  static const _kBotToken  = 'cfg_bot_token'; // legacy migration
  static const _kChatId    = 'cfg_chat_id';   // legacy migration
  static const _kSymbols   = 'cfg_symbols';
  static const _kPivotLen  = 'cfg_pivot_len';
  static const _kLimit     = 'cfg_limit';
  static const _kCheckEvery = 'cfg_check_every';

  // ─── Load from disk ───────────────────────────────────
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final botsStr = prefs.getString(_kBotsV2);
    if (botsStr != null && botsStr.isNotEmpty) {
      try {
        final list = jsonDecode(botsStr) as List;
        final bots = list
            .map((j) => TelegramBot.fromJson(Map<String, dynamic>.from(j as Map)))
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
            id:            'migrated',
            name:          'Main Bot',
            token:         oldToken,
            chatId:        oldChatId ?? '',
            hitTimeframes: ['30m', '1h'],
            newTimeframes: [],
          ),
        ];
        await _persistBots(prefs);
      }
    }

    Config.symbols           = prefs.getStringList(_kSymbols) ?? Config.symbols;
    Config.pivotLen          = prefs.getInt(_kPivotLen)       ?? Config.pivotLen;
    Config.limit             = prefs.getInt(_kLimit)          ?? Config.limit;
    Config.checkEveryMinutes = prefs.getInt(_kCheckEvery)     ?? Config.checkEveryMinutes;
  }

  // ─── Push live config to background isolate ───────────
  static Future<void> _pushToBackground() async {
    final svc = FlutterBackgroundService();
    if (!await svc.isRunning()) return;
    svc.invoke('updateConfig', {
      'bots':              Config.bots.map((b) => b.toJson()).toList(),
      'symbols':           Config.symbols,
      'pivotLen':          Config.pivotLen,
      'limit':             Config.limit,
      'checkEveryMinutes': Config.checkEveryMinutes,
    });
  }

  static Future<void> _persistBots(SharedPreferences prefs) async {
    await prefs.setString(
        _kBotsV2, jsonEncode(Config.bots.map((b) => b.toJson()).toList()));
  }

  static Future<void> _clearAllDedupKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final stale = prefs.getKeys()
        .where((k) => k.startsWith('HH_') || k.startsWith('LL_'))
        .toList();
    for (final k in stale) await prefs.remove(k);
    print('🧹 Cleared ${stale.length} dedup keys');
  }

  static Future<void> saveBots(List<TelegramBot> bots) async {
    final prefs = await SharedPreferences.getInstance();
    Config.bots = List.from(bots);
    await _persistBots(prefs);
    await _pushToBackground();
  }

  static Future<void> saveSymbols(List<String> newSymbols) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearAllDedupKeys();
    await prefs.setStringList(_kSymbols, newSymbols);
    Config.symbols = newSymbols;
    await _pushToBackground();
  }

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

  static Future<void> saveBotSettings({required int checkEveryMinutes}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCheckEvery, checkEveryMinutes);
    Config.checkEveryMinutes = checkEveryMinutes;
    await _pushToBackground();
  }
}
