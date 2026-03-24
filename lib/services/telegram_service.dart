// ─── services/telegram_service.dart ─────────────────────
// Sends alert messages to Telegram.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class TelegramService {
  static const String _baseUrl = 'https://api.telegram.org/bot';

  static const Map<String, String> _tfNames = {
    '1m': '1 Minute',
    '3m': '3 Minutes',
    '5m': '5 Minutes',
    '15m': '15 Minutes',
    '30m': '30 Minutes',
    '1h': '1 Hour',
    '2h': '2 Hours',
    '4h': '4 Hours',
    '6h': '6 Hours',
    '8h': '8 Hours',
    '12h': '12 Hours',
    '1d': '1 Day',
    '3d': '3 Days',
    '1w': '1 Week',
    '1M': '1 Month',
  };

  // ─── Credential guard ──────────────────────────────────
  static bool _credentialsOk() {
    if (Config.botToken.isEmpty ||
        Config.botToken == 'YOUR_TELEGRAM_BOT_TOKEN') {
      print('⚠️  Telegram bot token is not set. Skipping alert.');
      return false;
    }
    if (Config.chatId.isEmpty || Config.chatId == 'YOUR_TELEGRAM_CHAT_ID') {
      print('⚠️  Telegram chat ID is not set. Skipping alert.');
      return false;
    }
    return true;
  }

  // ─── Generic send ──────────────────────────────────────
  static Future<bool> _send(String message) async {
    try {
      final uri = Uri.parse('${_baseUrl}${Config.botToken}/sendMessage');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': Config.chatId,
              'text': message,
              'parse_mode': 'HTML',
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['ok'] == true) return true;
        print('❌ Telegram API error: ${body['description']}');
        return false;
      }
      print('❌ Telegram HTTP error: ${response.statusCode} — ${response.body}');
      return false;
    } catch (e) {
      print('❌ Telegram network error: $e');
      return false;
    }
  }

  // -------------------------
  // Multi-bot helpers (new flows)
  // -------------------------
  /// Send hit alert to all configured bots that subscribe to [timeframe].
  static Future<bool> sendHitAlert({
    required String levelType,
    required double levelPrice,
    required String timeframe,
    required double currentPrice,
    required String symbol,
  }) async {
    final targets = Config.bots
        .where((b) => b.isConfigured && b.hitTimeframes.contains(timeframe));
    if (targets.isEmpty) return false;

    final isHH = levelType == 'HH';
    final tfName = _tfNames[timeframe] ?? timeframe;
    final msg = '${isHH ? "🔴" : "🟢"} <b>$levelType Level Hit!</b>\n\n'
        '📊 <b>Symbol:</b>        $symbol\n'
        '⏱ <b>Timeframe:</b>    $tfName\n'
        '🎯 <b>Level Price:</b>  <code>${levelPrice.toStringAsFixed(5)}</code>\n'
        '💰 <b>Current Price:</b> <code>${currentPrice.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>       ${isHH ? "Resistance hit — watch for reversal ↓" : "Support hit — watch for bounce ↑"}\n';

    var anyOk = false;
    for (final bot in targets) {
      if (await _sendToBot(bot, msg)) anyOk = true;
    }
    return anyOk;
  }

  /// Send new HH/LL level notification to subscribed bots.
  static Future<bool> sendNewLevelAlert({
    required String levelType,
    required double levelPrice,
    required String timeframe,
    required String symbol,
  }) async {
    final targets = Config.bots
        .where((b) => b.isConfigured && b.newTimeframes.contains(timeframe));
    if (targets.isEmpty) return false;

    final isHH = levelType == 'HH';
    final tfName = _tfNames[timeframe] ?? timeframe;
    final msg =
        '${isHH ? "📈" : "📉"} <b>New ${isHH ? "Higher High" : "Lower Low"} Formed!</b>\n\n'
        '📊 <b>Symbol:</b>       $symbol\n'
        '⏱ <b>Timeframe:</b>   $tfName\n'
        '🎯 <b>Level Price:</b> <code>${levelPrice.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>      ${isHH ? "New resistance zone formed ↑" : "New support zone formed ↓"}\n';

    var anyOk = false;
    for (final bot in targets) {
      if (await _sendToBot(bot, msg)) anyOk = true;
    }
    return anyOk;
  }

  /// Send a manual price alert to a specific bot (multi-bot flow).
  static Future<bool> sendPriceAlert({
    required TelegramBot bot,
    required PriceAlert alert,
    required double currentPrice,
  }) async {
    if (!bot.isConfigured) return false;

    final String emoji;
    final String signal;
    switch (alert.condition) {
      case 'above':
        emoji = '🚀';
        signal = 'Price crossed above ${alert.targetPrice.toStringAsFixed(5)}';
        break;
      case 'below':
        emoji = '📉';
        signal = 'Price crossed below ${alert.targetPrice.toStringAsFixed(5)}';
        break;
      case 'touch':
        emoji = '🎯';
        signal = 'Price touched ${alert.targetPrice.toStringAsFixed(5)}';
        break;
      default:
        emoji = '🔔';
        signal = 'Price reached ${alert.targetPrice.toStringAsFixed(5)}';
    }

    final dispLabel =
        alert.label.isNotEmpty ? alert.label : '${alert.symbol} Price Alert';
    final msg = '$emoji <b>Price Alert Triggered!</b>\n\n'
        '🏷 <b>Alert:</b>   $dispLabel\n'
        '📊 <b>Symbol:</b>  ${alert.symbol}\n'
        '🎯 <b>Target:</b>  <code>${alert.targetPrice.toStringAsFixed(5)}</code>\n'
        '💰 <b>Current:</b> <code>${currentPrice.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>  $signal\n';

    return _sendToBot(bot, msg);
  }

  // Private helper to send for a TelegramBot object
  static Future<bool> _sendToBot(TelegramBot bot, String message) async {
    try {
      final uri = Uri.parse('${_baseUrl}${bot.token}/sendMessage');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': bot.chatId,
              'text': message,
              'parse_mode': 'HTML',
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['ok'] == true) return true;
        print('❌ Telegram API error [${bot.name}]: ${body['description']}');
        return false;
      }
      print(
          '❌ Telegram HTTP error: ${response.statusCode} — ${response.body} [${bot.name}]');
      return false;
    } catch (e) {
      print('❌ Telegram network error [${bot.name}]: $e');
      return false;
    }
  }

  /// Send a candlestick pattern alert to all configured bots.
  static Future<bool> sendPatternAlertAll({
    required String patternType,
    required String symbol,
    required String timeframe,
    required double price,
  }) async {
    final patternNames = {
      'BE': '🟢 Bullish Engulfing',
      'MS': '☀️  Morning Star',
      'ES': '🌙 Evening Star',
    };
    final patternSignals = {
      'BE': 'Bullish reversal — engulfing bar absorbed prior selling ↑',
      'MS': 'Bullish reversal after downtrend — watch for bounce ↑',
      'ES': 'Bearish reversal after uptrend — watch for pullback ↓',
    };
    final patternDesc = {
      'BE':
          'A bullish candle fully engulfed the prior bearish candle (wick-to-wick).',
      'MS': 'Large bearish candle → doji/star → bullish recovery candle.',
      'ES': 'Large bullish candle → doji/star → bearish reversal candle.',
    };

    final name = patternNames[patternType] ?? patternType;
    final signal = patternSignals[patternType] ?? '';
    final desc = patternDesc[patternType] ?? '';
    final tfName = _tfNames[timeframe] ?? timeframe;

    final message = '$name Pattern Detected!\n\n'
        '📊 <b>Symbol:</b>     $symbol\n'
        '⏱ <b>Timeframe:</b> $tfName\n'
        '💰 <b>Close:</b>     <code>${price.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>    $signal\n\n'
        '<i>$desc</i>\n';

    var anyOk = false;
    for (final bot in Config.bots.where((b) => b.isConfigured)) {
      if (await _sendToBot(bot, message)) anyOk = true;
    }
    return anyOk;
  }

  /// Send a candlestick pattern alert to a specific bot.
  static Future<bool> sendPatternAlertToBot({
    required TelegramBot bot,
    required String patternType,
    required String symbol,
    required String timeframe,
    required double price,
  }) async {
    if (!bot.isConfigured) return false;

    final patternNames = {
      'BE': '🟢 Bullish Engulfing',
      'MS': '☀️  Morning Star',
      'ES': '🌙 Evening Star',
    };
    final patternSignals = {
      'BE': 'Bullish reversal — engulfing bar absorbed prior selling ↑',
      'MS': 'Bullish reversal after downtrend — watch for bounce ↑',
      'ES': 'Bearish reversal after uptrend — watch for pullback ↓',
    };
    final patternDesc = {
      'BE':
          'A bullish candle fully engulfed the prior bearish candle (wick-to-wick).',
      'MS': 'Large bearish candle → doji/star → bullish recovery candle.',
      'ES': 'Large bullish candle → doji/star → bearish reversal candle.',
    };

    final name = patternNames[patternType] ?? patternType;
    final signal = patternSignals[patternType] ?? '';
    final desc = patternDesc[patternType] ?? '';
    final tfName = _tfNames[timeframe] ?? timeframe;

    final message = '$name Pattern Detected!\n\n'
        '📊 <b>Symbol:</b>     $symbol\n'
        '⏱ <b>Timeframe:</b> $tfName\n'
        '💰 <b>Close:</b>     <code>${price.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>    $signal\n\n'
        '<i>$desc</i>\n';

    return _sendToBot(bot, message);
  }

  // ══════════════════════════════════════════════════════
  // ─── HH / LL ALERT ───────────────────────────────────
  // ══════════════════════════════════════════════════════
  static Future<bool> sendAlert({
    required String levelType,
    required double levelPrice,
    required String timeframe,
    required double currentPrice,
    required String symbol,
  }) async {
    if (!_credentialsOk()) return false;

    final bool isHH = levelType == 'HH';
    final String emoji = isHH ? '🔴' : '🟢';
    final String signal = isHH
        ? 'Resistance hit — watch for reversal ↓'
        : 'Support hit — watch for bounce ↑';
    final String tfName = _tfNames[timeframe] ?? timeframe;

    final message = '$emoji <b>$levelType Level Hit!</b>\n'
        '\n'
        '📊 <b>Symbol:</b>        $symbol\n'
        '⏱ <b>Timeframe:</b>    $tfName\n'
        '🎯 <b>Level Price:</b>  <code>${levelPrice.toStringAsFixed(5)}</code>\n'
        '💰 <b>Current Price:</b> <code>${currentPrice.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>       $signal\n';

    return _send(message);
  }

  // ══════════════════════════════════════════════════════
  // ─── CANDLESTICK PATTERN ALERT ───────────────────────
  // ══════════════════════════════════════════════════════
  /// [patternType] is one of: 'BE', 'MS', 'ES'
  static Future<bool> sendPatternAlert({
    required String patternType,
    required String symbol,
    required String timeframe,
    required double price,
  }) async {
    if (!_credentialsOk()) return false;

    const Map<String, String> _patternName = {
      'BE': '🟢 Bullish Engulfing',
      'MS': '☀️  Morning Star',
      'ES': '🌙 Evening Star',
    };

    const Map<String, String> _patternSignal = {
      'BE': 'Bullish reversal — engulfing bar absorbed prior selling ↑',
      'MS': 'Bullish reversal after downtrend — watch for bounce ↑',
      'ES': 'Bearish reversal after uptrend — watch for pullback ↓',
    };

    const Map<String, String> _patternDesc = {
      'BE':
          'A bullish candle fully engulfed the prior bearish candle (wick-to-wick).',
      'MS': 'Large bearish candle → doji/star → bullish recovery candle.',
      'ES': 'Large bullish candle → doji/star → bearish reversal candle.',
    };

    final name = _patternName[patternType] ?? patternType;
    final signal = _patternSignal[patternType] ?? '';
    final desc = _patternDesc[patternType] ?? '';
    final tfName = _tfNames[timeframe] ?? timeframe;

    final message = '$name Pattern Detected!\n'
        '\n'
        '📊 <b>Symbol:</b>     $symbol\n'
        '⏱ <b>Timeframe:</b> $tfName\n'
        '💰 <b>Close:</b>     <code>${price.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>    $signal\n'
        '\n'
        '<i>$desc</i>\n';

    return _send(message);
  }

  // ══════════════════════════════════════════════════════
  // ─── TEST CONNECTION ─────────────────────────────────
  // ══════════════════════════════════════════════════════
  static Future<String?> testConnection() async {
    if (Config.botToken.isEmpty ||
        Config.botToken == 'YOUR_TELEGRAM_BOT_TOKEN') {
      return 'Bot token is not set';
    }
    if (Config.chatId.isEmpty || Config.chatId == 'YOUR_TELEGRAM_CHAT_ID') {
      return 'Chat ID is not set';
    }

    try {
      final uri = Uri.parse('${_baseUrl}${Config.botToken}/sendMessage');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': Config.chatId,
              'text':
                  '✅ <b>HH/LL Bot Connected!</b>\n\nYour bot is configured correctly and ready to send HH/LL and candlestick pattern alerts.',
              'parse_mode': 'HTML',
            }),
          )
          .timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['ok'] == true) return null;
      return body['description'] ?? 'Unknown Telegram error';
    } catch (e) {
      return 'Network error: $e';
    }
  }
}
