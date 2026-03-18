// ─── services/binance_service.dart ──────────────────────
// Fetches OHLCV candles from Binance REST API.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });
}

/// Result of symbol validation
class SymbolValidationResult {
  final bool isValid;
  final String? error; // null if valid

  const SymbolValidationResult({required this.isValid, this.error});
}

class BinanceService {
  static const String _baseUrl       = 'https://api.binance.com/api/v3/klines';
  static const String _exchangeInfo  = 'https://api.binance.com/api/v3/exchangeInfo';
  static const String _tickerUrl     = 'https://api.binance.com/api/v3/ticker/price';

  /// Validate a symbol against Binance — returns error string or null if OK
  static Future<SymbolValidationResult> validateSymbol(String symbol) async {
    if (symbol.isEmpty) {
      return const SymbolValidationResult(isValid: false, error: 'Symbol cannot be empty');
    }

    try {
      // Use ticker/price endpoint — fast single-symbol check
      final uri = Uri.parse('$_tickerUrl?symbol=${symbol.toUpperCase()}');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return const SymbolValidationResult(isValid: true);
      }

      // Parse Binance error message
      final body = jsonDecode(response.body);
      final msg  = body['msg'] as String? ?? 'Invalid symbol';
      return SymbolValidationResult(isValid: false, error: msg);
    } catch (e) {
      return SymbolValidationResult(isValid: false, error: 'Network error: $e');
    }
  }

  /// Fetch candles for a given symbol and timeframe
  static Future<List<Candle>> fetchCandles(String symbol, String timeframe) async {
    final uri = Uri.parse(
      '$_baseUrl?symbol=$symbol&interval=$timeframe&limit=${Config.limit}',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final msg  = body['msg'] as String? ?? response.statusCode.toString();
      throw Exception('Binance error for $symbol: $msg');
    }

    final List<dynamic> raw = jsonDecode(response.body);

    return raw.map((item) {
      return Candle(
        time:   DateTime.fromMillisecondsSinceEpoch(item[0] as int),
        open:   double.parse(item[1].toString()),
        high:   double.parse(item[2].toString()),
        low:    double.parse(item[3].toString()),
        close:  double.parse(item[4].toString()),
        volume: double.parse(item[5].toString()),
      );
    }).toList();
  }
}
