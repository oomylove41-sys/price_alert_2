// ─── config.dart ────────────────────────────────────────
// Runtime-editable config. Supports multiple Telegram bots
// with per-bot per-alert-type timeframe selection,
// plus manual price alerts.

import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> kAllTimeframes = [
  '1m',
  '3m',
  '5m',
  '15m',
  '30m',
  '1h',
  '2h',
  '4h',
  '6h',
  '8h',
  '12h',
  '1d',
  '3d',
  '1w',
  '1M',
];

// ══════════════════════════════════════════════════════════
// ─── TELEGRAM BOT ────────────────────────────────────────
// ══════════════════════════════════════════════════════════
class TelegramBot {
  final String id;
  String name;
  String token;
  String chatId;
  List<String> hitTimeframes;
  List<String> newTimeframes;

  /// Whether this bot can be selected for manual price alerts.
  bool canReceiveManualAlerts;

  TelegramBot({
    required this.id,
    required this.name,
    required this.token,
    required this.chatId,
    List<String>? hitTimeframes,
    List<String>? newTimeframes,
    this.canReceiveManualAlerts = false,
  })  : hitTimeframes = hitTimeframes ?? [],
        newTimeframes = newTimeframes ?? [];

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
    bool? canReceiveManualAlerts,
  }) =>
      TelegramBot(
        id: id,
        name: name ?? this.name,
        token: token ?? this.token,
        chatId: chatId ?? this.chatId,
        hitTimeframes: hitTimeframes ?? List.from(this.hitTimeframes),
        newTimeframes: newTimeframes ?? List.from(this.newTimeframes),
        canReceiveManualAlerts:
            canReceiveManualAlerts ?? this.canReceiveManualAlerts,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'token': token,
        'chatId': chatId,
        'hitTimeframes': hitTimeframes,
        'newTimeframes': newTimeframes,
        'canReceiveManualAlerts': canReceiveManualAlerts,
      };

  factory TelegramBot.fromJson(Map<String, dynamic> j) {
    List<String> parseTfList(dynamic raw, bool fallback) =>
        raw is List ? List<String>.from(raw) : (fallback ? ['30m', '1h'] : []);
    return TelegramBot(
      id: j['id'] as String? ?? _genId(),
      name: j['name'] as String? ?? 'Bot',
      token: j['token'] as String? ?? '',
      chatId: j['chatId'] as String? ?? '',
      hitTimeframes:
          parseTfList(j['hitTimeframes'], j['alertOnHit'] as bool? ?? true),
      newTimeframes:
          parseTfList(j['newTimeframes'], j['alertOnNew'] as bool? ?? false),
      canReceiveManualAlerts: j['canReceiveManualAlerts'] as bool? ?? false,
    );
  }

  static String _genId() => DateTime.now().millisecondsSinceEpoch.toString();
}

// ══════════════════════════════════════════════════════════
// ─── PRICE ALERT ─────────────────────────────────────════
// ══════════════════════════════════════════════════════════
class PriceAlert {
  final String id;
  String symbol;
  double targetPrice;

  /// 'above' → alert when current price >= targetPrice
  /// 'below' → alert when current price <= targetPrice
  /// 'touch' → alert when current price is within 0.2% of targetPrice (either side)
  String condition;

  /// Which TelegramBot to use
  String botId;

  /// Optional user-friendly label
  String label;

  bool isActive;
  bool isTriggered;
  final DateTime createdAt;

  PriceAlert({
    required this.id,
    required this.symbol,
    required this.targetPrice,
    required this.condition,
    required this.botId,
    this.label = '',
    this.isActive = true,
    this.isTriggered = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get shouldFire => isActive && !isTriggered;

  bool matches(double currentPrice) {
    switch (condition) {
      case 'above':
        return currentPrice >= targetPrice;
      case 'below':
        return currentPrice <= targetPrice;
      case 'touch':
        final pct = (currentPrice - targetPrice).abs() / targetPrice;
        return pct <= 0.002;
      default:
        return false;
    }
  }

  PriceAlert copyWith({
    String? symbol,
    double? targetPrice,
    String? condition,
    String? botId,
    String? label,
    bool? isActive,
    bool? isTriggered,
  }) =>
      PriceAlert(
        id: id,
        symbol: symbol ?? this.symbol,
        targetPrice: targetPrice ?? this.targetPrice,
        condition: condition ?? this.condition,
        botId: botId ?? this.botId,
        label: label ?? this.label,
        isActive: isActive ?? this.isActive,
        isTriggered: isTriggered ?? this.isTriggered,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'symbol': symbol,
        'targetPrice': targetPrice,
        'condition': condition,
        'botId': botId,
        'label': label,
        'isActive': isActive,
        'isTriggered': isTriggered,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PriceAlert.fromJson(Map<String, dynamic> j) => PriceAlert(
        id: j['id'] as String? ?? _genId(),
        symbol: j['symbol'] as String,
        targetPrice: (j['targetPrice'] as num).toDouble(),
        condition: j['condition'] as String,
        botId: j['botId'] as String,
        label: j['label'] as String? ?? '',
        isActive: j['isActive'] as bool? ?? true,
        isTriggered: j['isTriggered'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  static String _genId() => DateTime.now().microsecondsSinceEpoch.toString();
}

// ══════════════════════════════════════════════════════════
// ─── CONFIG ──────────────────────────────────────────────
// ══════════════════════════════════════════════════════════
class Config {
  static List<TelegramBot> bots = [_defaultBot()];
  static List<String> symbols = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT'];
  // Global (user-selected) timeframes. Stored separately from per-bot timeframes.
  static List<String> timeframes = ['30m', '1h'];
  static int pivotLen = 5;
  static int limit = 1000;
  static int checkEveryMinutes = 5;
  static List<PriceAlert> priceAlerts = [];

  // ─── NEW: Candlestick pattern settings ────────────────
  static bool patternBE = true;
  static bool patternMS = true;
  static bool patternES = true;
  static bool patternRequireTrend = true;
  static double patternStarBodyPct = 30.0;
  static double patternRecoveryPct = 50.0;

  static List<String> get effectiveTimeframes {
    final Set<String> all = {};
    for (final bot in bots) {
      all.addAll(bot.hitTimeframes);
      all.addAll(bot.newTimeframes);
    }
    return kAllTimeframes.where(all.contains).toList();
  }

  // Convenience getters/setters for legacy single-bot flows used across the app.
  static String get botToken {
    if (bots.isEmpty) return '';
    try {
      return bots.firstWhere((b) => b.isConfigured).token;
    } catch (_) {
      return bots.first.token;
    }
  }

  static set botToken(String v) {
    if (bots.isEmpty) bots = [_defaultBot()];
    final first = bots.first;
    bots[0] = first.copyWith(token: v);
  }

  static String get chatId {
    if (bots.isEmpty) return '';
    try {
      return bots.firstWhere((b) => b.isConfigured).chatId;
    } catch (_) {
      return bots.first.chatId;
    }
  }

  static set chatId(String v) {
    if (bots.isEmpty) bots = [_defaultBot()];
    final first = bots.first;
    bots[0] = first.copyWith(chatId: v);
  }
}

TelegramBot _defaultBot() => TelegramBot(
      id: 'default',
      name: 'Main Bot',
      token: 'YOUR_TELEGRAM_BOT_TOKEN',
      chatId: 'YOUR_TELEGRAM_CHAT_ID',
      hitTimeframes: ['30m', '1h'],
      newTimeframes: [],
    );

// ══════════════════════════════════════════════════════════
// ─── CONFIG SERVICE ──────────────════════════════════════
// ══════════════════════════════════════════════════════════
class ConfigService {
  static const _kBotsV2 = 'cfg_bots_v2';
  static const _kBotToken = 'cfg_bot_token'; // legacy
  static const _kChatId = 'cfg_chat_id'; // legacy
  static const _kSymbols = 'cfg_symbols';
  static const _kTimeframes = 'cfg_timeframes';
  static const _kPivotLen = 'cfg_pivot_len';
  static const _kLimit = 'cfg_limit';
  static const _kCheckEvery = 'cfg_check_every';
  static const _kPriceAlerts = 'cfg_price_alerts_v1';

  // ─── NEW: pattern keys ────────────────────────────────
  static const _kPatternBE = 'cfg_pattern_be';
  static const _kPatternMS = 'cfg_pattern_ms';
  static const _kPatternES = 'cfg_pattern_es';
  static const _kPatternRequireTrend = 'cfg_pattern_require_trend';
  static const _kPatternStarBodyPct = 'cfg_pattern_star_body_pct';
  static const _kPatternRecoveryPct = 'cfg_pattern_recovery_pct';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // ── Bots ──────────────────────────────────────────────
    final botsStr = prefs.getString(_kBotsV2);
    if (botsStr != null && botsStr.isNotEmpty) {
      try {
        final list = jsonDecode(botsStr) as List;
        final bots = list
            .map((j) =>
                TelegramBot.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
        Config.bots = bots.isNotEmpty ? bots : [_defaultBot()];
      } catch (_) {
        Config.bots = [_defaultBot()];
      }
    } else {
      final oldToken = prefs.getString(_kBotToken);
      final oldChatId = prefs.getString(_kChatId);
      if (oldToken != null && oldToken.isNotEmpty) {
        Config.bots = [
          TelegramBot(
            id: 'migrated',
            name: 'Main Bot',
            token: oldToken,
            chatId: oldChatId ?? '',
            hitTimeframes: ['30m', '1h'],
            newTimeframes: [],
          )
        ];
        await _persistBots(prefs);
      }
    }

    // ── Price Alerts ──────────────────────────────────────
    final alertsStr = prefs.getString(_kPriceAlerts);
    if (alertsStr != null && alertsStr.isNotEmpty) {
      try {
        final list = jsonDecode(alertsStr) as List;
        Config.priceAlerts = list
            .map(
                (j) => PriceAlert.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
      } catch (_) {
        Config.priceAlerts = [];
      }
    }

    Config.symbols = prefs.getStringList(_kSymbols) ?? Config.symbols;
    Config.timeframes = prefs.getStringList(_kTimeframes) ?? Config.timeframes;
    Config.pivotLen = prefs.getInt(_kPivotLen) ?? Config.pivotLen;
    Config.limit = prefs.getInt(_kLimit) ?? Config.limit;
    Config.checkEveryMinutes =
        prefs.getInt(_kCheckEvery) ?? Config.checkEveryMinutes;

    // ─── NEW: load pattern settings ───────────────────────
    Config.patternBE = prefs.getBool(_kPatternBE) ?? Config.patternBE;
    Config.patternMS = prefs.getBool(_kPatternMS) ?? Config.patternMS;
    Config.patternES = prefs.getBool(_kPatternES) ?? Config.patternES;
    Config.patternRequireTrend =
        prefs.getBool(_kPatternRequireTrend) ?? Config.patternRequireTrend;
    Config.patternStarBodyPct =
        prefs.getDouble(_kPatternStarBodyPct) ?? Config.patternStarBodyPct;
    Config.patternRecoveryPct =
        prefs.getDouble(_kPatternRecoveryPct) ?? Config.patternRecoveryPct;
  }

  static Future<void> _pushToBackground() async {
    final svc = FlutterBackgroundService();
    if (!await svc.isRunning()) return;
    svc.invoke('updateConfig', {
      'bots': Config.bots.map((b) => b.toJson()).toList(),
      'symbols': Config.symbols,
      'pivotLen': Config.pivotLen,
      'limit': Config.limit,
      'checkEveryMinutes': Config.checkEveryMinutes,
      'priceAlerts': Config.priceAlerts.map((a) => a.toJson()).toList(),
      // ─── NEW: pattern settings ───────────────────────
      'patternBE': Config.patternBE,
      'patternMS': Config.patternMS,
      'patternES': Config.patternES,
      'patternRequireTrend': Config.patternRequireTrend,
      'patternStarBodyPct': Config.patternStarBodyPct,
      'patternRecoveryPct': Config.patternRecoveryPct,
    });
  }

  static Future<void> _persistBots(SharedPreferences prefs) async =>
      prefs.setString(
          _kBotsV2, jsonEncode(Config.bots.map((b) => b.toJson()).toList()));

  static Future<void> _persistAlerts(SharedPreferences prefs) async =>
      prefs.setString(_kPriceAlerts,
          jsonEncode(Config.priceAlerts.map((a) => a.toJson()).toList()));

  static Future<void> _clearAllDedupKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final stale = prefs
        .getKeys()
        .where((k) =>
            k.startsWith('HH_') ||
            k.startsWith('LL_') ||
            k.startsWith('PAT_')) // ← NEW: also clear pattern dedup keys
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

  static Future<void> saveTimeframes(List<String> newTimeframes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kTimeframes, newTimeframes);
    Config.timeframes = List.from(newTimeframes);
    await _pushToBackground();
  }

  /// Save token/chat as a single migrated Telegram bot (legacy single-bot UI).
  static Future<void> saveTelegram(
      {required String botToken, required String chatId}) async {
    final prefs = await SharedPreferences.getInstance();
    // Create/update the first bot entry to hold these credentials.
    if (Config.bots.isEmpty) Config.bots = [_defaultBot()];
    final first = Config.bots.first.copyWith(token: botToken, chatId: chatId);
    Config.bots[0] = first;
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

  static Future<void> saveIndicator(
      {required int pivotLen, required int limit}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPivotLen, pivotLen);
    await prefs.setInt(_kLimit, limit);
    Config.pivotLen = pivotLen;
    Config.limit = limit;
    await _pushToBackground();
  }

  static Future<void> saveBotSettings({required int checkEveryMinutes}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCheckEvery, checkEveryMinutes);
    Config.checkEveryMinutes = checkEveryMinutes;
    await _pushToBackground();
  }

  /// Called from the main isolate — saves + pushes to background.
  static Future<void> savePriceAlerts(List<PriceAlert> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    Config.priceAlerts = List.from(alerts);
    await _persistAlerts(prefs);
    await _pushToBackground();
  }

  /// Called from the BACKGROUND isolate — saves directly, no push.
  static Future<void> savePriceAlertsFromBackground(
      SharedPreferences prefs) async {
    await _persistAlerts(prefs);
  }

  // ─── NEW: Save pattern settings ───────────────────────
  static Future<void> savePatternSettings({
    required bool patternBE,
    required bool patternMS,
    required bool patternES,
    required bool patternRequireTrend,
    required double patternStarBodyPct,
    required double patternRecoveryPct,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPatternBE, patternBE);
    await prefs.setBool(_kPatternMS, patternMS);
    await prefs.setBool(_kPatternES, patternES);
    await prefs.setBool(_kPatternRequireTrend, patternRequireTrend);
    await prefs.setDouble(_kPatternStarBodyPct, patternStarBodyPct);
    await prefs.setDouble(_kPatternRecoveryPct, patternRecoveryPct);

    Config.patternBE = patternBE;
    Config.patternMS = patternMS;
    Config.patternES = patternES;
    Config.patternRequireTrend = patternRequireTrend;
    Config.patternStarBodyPct = patternStarBodyPct;
    Config.patternRecoveryPct = patternRecoveryPct;

    await _pushToBackground();
  }
}
