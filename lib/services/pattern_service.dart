// ─── services/pattern_service.dart ───────────────────────
// Detect Bullish Engulfing (BE), Morning Star (MS), Evening Star (ES)
// based on the Pine script logic provided by the user.

import 'package:meta/meta.dart';
import 'binance_service.dart';

class PatternHit {
  final String pattern; // 'BE' | 'MS' | 'ES'
  final double price;
  PatternHit({required this.pattern, required this.price});
}

class PatternService {
  /// Detect patterns on the last CLOSED candle using the last few candles.
  /// Returns list of detected patterns (possibly empty).
  static List<PatternHit> detectOnLastClosed(
    List<Candle> candles, {
    int starBodyPct = 30,
    int recoveryPct = 50,
    bool requireTrend = true,
  }) {
    final n = candles.length;
    // Need at least 4 candles to evaluate (C2 at -2, C1 at -3)
    if (n < 4) return [];

    // Indexing: c0 = last closed (candles[n-2]), c1 = prev (n-3), c2 = n-4, c3 = n-5 if exists
    final c0 = candles[n - 2];
    final c1 = candles[n - 3];
    final c2 = candles[n - 4];
    final c3 = n >= 5 ? candles[n - 5] : null;

    double body(Candle c) => (c.close - c.open).abs();
    double range(Candle c) => (c.high - c.low);
    double avgRange = 0.0;
    // compute 14-period avg range if available
    final start = (n - 1 - 14).clamp(0, n - 1);
    final rngs = <double>[];
    for (int i = start; i < n; i++) rngs.add(range(candles[i]));
    if (rngs.isNotEmpty) avgRange = rngs.reduce((a, b) => a + b) / rngs.length;

    bool isStar(Candle c) {
      final r = range(c);
      if (r == 0) return true;
      return (body(c) / r * 100) <= starBodyPct;
    }

    bool isLarge(Candle c) {
      return body(c) >= avgRange * 0.5;
    }

    final List<PatternHit> out = [];

    // ── Bullish Engulfing (BE)
    final beDowntrend =
        c3 != null ? (c3!.close > c2.close && c2.close > c1.close) : false;
    final isBe = (c1.close < c1.open) &&
        (c0.close > c0.open) &&
        (c0.open <= c1.low) &&
        (c0.close >= c1.high) &&
        (requireTrend ? beDowntrend : true);
    if (isBe) out.add(PatternHit(pattern: 'BE', price: c0.close));

    // ── Morning Star (MS)
    final msDowntrend = (n >= 6)
        ? (candles[n - 6].close > candles[n - 5].close &&
            candles[n - 5].close > c2.close)
        : false;
    final ms_c1_bear = (c2.close < c2.open) && isLarge(c2);
    final ms_c2_star = isStar(c1);
    final ms_c3_bull = c0.close > c0.open;
    final ms_recovery =
        c0.close > c2.close + (c2.open - c2.close) * (recoveryPct / 100);
    final isMs = ms_c1_bear &&
        ms_c2_star &&
        ms_c3_bull &&
        ms_recovery &&
        (requireTrend ? msDowntrend : true);
    if (isMs) out.add(PatternHit(pattern: 'MS', price: c0.close));

    // ── Evening Star (ES)
    final esUptrend = (n >= 6)
        ? (candles[n - 6].close < candles[n - 5].close &&
            candles[n - 5].close < c2.close)
        : false;
    final es_c1_bull = (c2.close > c2.open) && isLarge(c2);
    final es_c2_star = isStar(c1);
    final es_c3_bear = c0.close < c0.open;
    final es_recovery =
        c0.close < c2.close - (c2.close - c2.open) * (recoveryPct / 100);
    final isEs = es_c1_bull &&
        es_c2_star &&
        es_c3_bear &&
        es_recovery &&
        (requireTrend ? esUptrend : true);
    if (isEs) out.add(PatternHit(pattern: 'ES', price: c0.close));

    return out;
  }
}
