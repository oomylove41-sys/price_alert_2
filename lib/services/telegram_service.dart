// ─── services/telegram_service.dart ─────────────────────
// Sends alert messages to Telegram.
// Each send method filters to only the bots that have the
// given timeframe enabled for that alert type.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class TelegramService {
  static const String _baseUrl = 'https://api.telegram.org/bot';

  static const Map<String, String> _tfNames = {
    '1m':  '1 Minute',   '3m':  '3 Minutes',  '5m':  '5 Minutes',
    '15m': '15 Minutes', '30m': '30 Minutes',  '1h':  '1 Hour',
    '2h':  '2 Hours',    '4h':  '4 Hours',     '6h':  '6 Hours',
    '8h':  '8 Hours',    '12h': '12 Hours',    '1d':  '1 Day',
    '3d':  '3 Days',     '1w':  '1 Week',      '1M':  '1 Month',
  };

  // ──────────────────────────────────────────────────────
  // ALERT TYPE 1: Price HITS an existing HH/LL level
  // Only sends to bots that have [timeframe] in hitTimeframes.
  // ──────────────────────────────────────────────────────
  static Future<bool> sendHitAlert({
    required String levelType,
    required double levelPrice,
    required String timeframe,
    required double currentPrice,
    required String symbol,
  }) async {
    final targets = Config.bots.where(
        (b) => b.isConfigured && b.hitTimeframes.contains(timeframe));
    if (targets.isEmpty) return false;

    final bool   isHH   = levelType == 'HH';
    final String emoji  = isHH ? '🔴' : '🟢';
    final String signal = isHH
        ? 'Resistance hit — watch for reversal ↓'
        : 'Support hit — watch for bounce ↑';
    final String tfName = _tfNames[timeframe] ?? timeframe;

    final message =
        '$emoji <b>$levelType Level Hit!</b>\n'
        '\n'
        '📊 <b>Symbol:</b>        $symbol\n'
        '⏱ <b>Timeframe:</b>    $tfName\n'
        '🎯 <b>Level Price:</b>  <code>${levelPrice.toStringAsFixed(5)}</code>\n'
        '💰 <b>Current Price:</b> <code>${currentPrice.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>       $signal\n';

    bool anyOk = false;
    for (final bot in targets) {
      if (await _sendToBot(bot, message)) anyOk = true;
    }
    return anyOk;
  }

  // ──────────────────────────────────────────────────────
  // ALERT TYPE 2: A NEW HH/LL pivot is FORMED
  // Only sends to bots that have [timeframe] in newTimeframes.
  // ──────────────────────────────────────────────────────
  static Future<bool> sendNewLevelAlert({
    required String levelType,
    required double levelPrice,
    required String timeframe,
    required String symbol,
  }) async {
    final targets = Config.bots.where(
        (b) => b.isConfigured && b.newTimeframes.contains(timeframe));
    if (targets.isEmpty) return false;

    final bool   isHH   = levelType == 'HH';
    final String emoji  = isHH ? '📈' : '📉';
    final String desc   = isHH ? 'Higher High' : 'Lower Low';
    final String signal = isHH
        ? 'New resistance zone formed ↑'
        : 'New support zone formed ↓';
    final String tfName = _tfNames[timeframe] ?? timeframe;

    final message =
        '$emoji <b>New $desc Formed!</b>\n'
        '\n'
        '📊 <b>Symbol:</b>       $symbol\n'
        '⏱ <b>Timeframe:</b>   $tfName\n'
        '🎯 <b>Level Price:</b> <code>${levelPrice.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>      $signal\n';

    bool anyOk = false;
    for (final bot in targets) {
      if (await _sendToBot(bot, message)) anyOk = true;
    }
    return anyOk;
  }

  // ──────────────────────────────────────────────────────
  // TEST CONNECTION for a specific bot
  // ──────────────────────────────────────────────────────
  static Future<String?> testConnection(TelegramBot bot) async {
    if (!bot.isConfigured) {
      if (bot.token.isEmpty || bot.token == 'YOUR_TELEGRAM_BOT_TOKEN') {
        return 'Bot token is not set';
      }
      return 'Chat ID is not set';
    }

    final hitTfs = bot.hitTimeframes.isEmpty
        ? 'None'
        : bot.hitTimeframes.join(', ');
    final newTfs = bot.newTimeframes.isEmpty
        ? 'None'
        : bot.newTimeframes.join(', ');

    try {
      final uri = Uri.parse('${_baseUrl}${bot.token}/sendMessage');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': bot.chatId,
          'text':
              '✅ <b>HH/LL Bot Connected!</b>\n\n'
              '🤖 Bot: <b>${bot.name}</b>\n\n'
              '🎯 Hit alert timeframes: <code>$hitTfs</code>\n'
              '✨ New level timeframes: <code>$newTfs</code>\n\n'
              'This bot is configured and ready to send alerts.',
          'parse_mode': 'HTML',
        }),
      ).timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['ok'] == true) return null;
      return body['description'] as String? ?? 'Unknown Telegram error';
    } catch (e) {
      return 'Network error: $e';
    }
  }

  // ──────────────────────────────────────────────────────
  // PRIVATE: send one message to one bot
  // ──────────────────────────────────────────────────────
  static Future<bool> _sendToBot(TelegramBot bot, String message) async {
    try {
      final uri = Uri.parse('${_baseUrl}${bot.token}/sendMessage');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id':    bot.chatId,
          'text':       message,
          'parse_mode': 'HTML',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['ok'] == true) return true;
        print('❌ Telegram error [${bot.name}]: ${body['description']}');
        return false;
      }
      print('❌ Telegram HTTP ${response.statusCode} [${bot.name}]');
      return false;
    } catch (e) {
      print('❌ Telegram network error [${bot.name}]: $e');
      return false;
    }
  }
}
