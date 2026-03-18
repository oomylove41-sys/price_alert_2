// ─── services/telegram_service.dart ─────────────────────
// Sends alert messages to Telegram.
// Returns true on success, false on failure.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class TelegramService {
  static const String _baseUrl = 'https://api.telegram.org/bot';

  // ─── FIX 3: Full timeframe name map ──────────────────
  static const Map<String, String> _tfNames = {
    '1m':  '1 Minute',
    '3m':  '3 Minutes',
    '5m':  '5 Minutes',
    '15m': '15 Minutes',
    '30m': '30 Minutes',
    '1h':  '1 Hour',
    '2h':  '2 Hours',
    '4h':  '4 Hours',
    '6h':  '6 Hours',
    '8h':  '8 Hours',
    '12h': '12 Hours',
    '1d':  '1 Day',
    '3d':  '3 Days',
    '1w':  '1 Week',
    '1M':  '1 Month',
  };

  /// Send alert to Telegram.
  /// Returns true if message was delivered, false otherwise.
  static Future<bool> sendAlert({
    required String levelType,
    required double levelPrice,
    required String timeframe,
    required double currentPrice,
    required String symbol,
  }) async {
    // ─── FIX 2: Validate credentials before calling API ──
    if (Config.botToken.isEmpty ||
        Config.botToken == 'YOUR_TELEGRAM_BOT_TOKEN') {
      print('⚠️  Telegram bot token is not set. Skipping alert.');
      return false;
    }

    if (Config.chatId.isEmpty ||
        Config.chatId == 'YOUR_TELEGRAM_CHAT_ID') {
      print('⚠️  Telegram chat ID is not set. Skipping alert.');
      return false;
    }

    final bool   isHH   = levelType == 'HH';
    final String emoji  = isHH ? '🔴' : '🟢';
    final String signal = isHH
        ? 'Resistance hit — watch for reversal ↓'
        : 'Support hit — watch for bounce ↑';
    final String tfName = _tfNames[timeframe] ?? timeframe;

    final String message =
        '$emoji <b>$levelType Level Hit!</b>\n'
        '\n'
        '📊 <b>Symbol:</b>        $symbol\n'
        '⏱ <b>Timeframe:</b>    $tfName\n'
        '🎯 <b>Level Price:</b>  <code>${levelPrice.toStringAsFixed(5)}</code>\n'
        '💰 <b>Current Price:</b> <code>${currentPrice.toStringAsFixed(5)}</code>\n'
        '📌 <b>Signal:</b>       $signal\n';

    try {
      final uri = Uri.parse('${_baseUrl}${Config.botToken}/sendMessage');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id':    Config.chatId,
          'text':       message,
          'parse_mode': 'HTML',
        }),
      ).timeout(const Duration(seconds: 10));

      // ─── FIX 2: Check HTTP response ──────────────────
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['ok'] == true) {
          return true;
        } else {
          print('❌ Telegram API error: ${body['description']}');
          return false;
        }
      } else {
        print('❌ Telegram HTTP error: ${response.statusCode} — ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Telegram network error: $e');
      return false;
    }
  }

  /// Test connection — sends a simple ping message.
  /// Returns null on success, error string on failure.
  static Future<String?> testConnection() async {
    if (Config.botToken.isEmpty ||
        Config.botToken == 'YOUR_TELEGRAM_BOT_TOKEN') {
      return 'Bot token is not set';
    }

    if (Config.chatId.isEmpty ||
        Config.chatId == 'YOUR_TELEGRAM_CHAT_ID') {
      return 'Chat ID is not set';
    }

    try {
      final uri = Uri.parse('${_baseUrl}${Config.botToken}/sendMessage');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id':    Config.chatId,
          'text':       '✅ <b>HH/LL Bot Connected!</b>\n\nYour bot is configured correctly and ready to send alerts.',
          'parse_mode': 'HTML',
        }),
      ).timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body);

      if (response.statusCode == 200 && body['ok'] == true) {
        return null; // success
      } else {
        return body['description'] ?? 'Unknown Telegram error';
      }
    } catch (e) {
      return 'Network error: $e';
    }
  }
}
