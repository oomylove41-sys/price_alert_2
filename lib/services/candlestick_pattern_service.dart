// ─── services/candlestick_pattern_service.dart ───────────
// Detects Bullish Engulfing, Morning Star, Evening Star
// patterns from candle data. Ported from Pine Script v6.

import '../config.dart';
import 'binance_service.dart';

// ══════════════════════════════════════════════════════════
// ─── RESULT ──────────────────────────────────────────────
// ══════════════════════════════════════════════════════════
class PatternResult {
  final bool isBE; // Bullish Engulfing
  final bool isMS; // Morning Star
  final bool isES; // Evening Star

  const PatternResult({
    this.isBE = false,
    this.isMS = false,
    this.isES = false,
  });

  bool get hasPattern => isBE || isMS || isES;
}

// ══════════════════════════════════════════════════════════
// ─── SERVICE ─────────────────────────────────────────────
// ══════════════════════════════════════════════════════════
class CandlestickPatternService {

  // ─── Candle helpers ────────────────────────────────────
  static double _body(Candle c) => (c.close - c.open).abs();
  static double _rng(Candle c)  => c.high - c.low;

  /// Star: body/range ratio ≤ Config.patternStarBodyPct
  static bool _isStar(Candle c) {
    final r = _rng(c);
    if (r == 0) return true;
    return (_body(c) / r * 100) <= Config.patternStarBodyPct;
  }

  /// Large: body ≥ 50% of the 14-bar avg range
  static bool _isLarge(Candle c, double avgRng) {
    return _body(c) >= avgRng * 0.5;
  }

  /// Simple 14-bar avg of high-low range (ending at the last candle)
  static double _avgRange(List<Candle> candles) {
    const period = 14;
    final n      = candles.length;
    final start  = (n - period).clamp(0, n - 1);
    double sum   = 0;
    int    count = 0;
    for (int i = start; i < n; i++) {
      sum  += candles[i].high - candles[i].low;
      count++;
    }
    return count > 0 ? sum / count : 0;
  }

  // ══════════════════════════════════════════════════════
  // ─── MAIN DETECT ─────────────────────────────────────
  // ══════════════════════════════════════════════════════
  /// Pass the CLOSED-candle slice (exclude the live/forming candle).
  /// Detects patterns at the tail of [candles] — candles.last = c0 (current bar).
  /// Requires ≥ 5 candles (trend filter needs ≥ 5 for MS/ES).
  static PatternResult detect(List<Candle> candles) {
    final n = candles.length;
    if (n < 5) return const PatternResult();

    // Pine Script convention mapped to Dart indices:
    // [0] = newest = candles[n-1]
    final c0 = candles[n - 1]; // current (last closed)
    final c1 = candles[n - 2]; // 1 bar ago
    final c2 = candles[n - 3]; // 2 bars ago
    final c3 = candles[n - 4]; // 3 bars ago
    final c4 = candles[n - 5]; // 4 bars ago (same as c3 if n==5)

    final avgRng       = _avgRange(candles);
    final requireTrend = Config.patternRequireTrend;
    final recovPct     = Config.patternRecoveryPct / 100.0;

    // ─── Bullish Engulfing ────────────────────────────
    // Pine: close[1]<open[1] && close>open && open<=low[1] && close>=high[1]
    bool isBE = false;
    if (Config.patternBE) {
      final beDowntrend = requireTrend
          ? (c3.close > c2.close && c2.close > c1.close)
          : true;
      isBE = c1.close < c1.open       // C1 bearish
          && c0.close > c0.open       // C0 bullish
          && c0.open  <= c1.low       // engulfs full wick-to-wick
          && c0.close >= c1.high
          && beDowntrend;
    }

    // ─── Morning Star ─────────────────────────────────
    // C2: large bearish | C1: star | C0: bullish recovery
    // Pine: close[4]>close[3]>close[2] (downtrend into C2)
    bool isMS = false;
    if (Config.patternMS) {
      final msDowntrend = requireTrend
          ? (c4.close > c3.close && c3.close > c2.close)
          : true;
      // Recovery: C0 closes above C2.close + (C2.open - C2.close) * pct
      final msRecovery = c0.close >
          c2.close + (c2.open - c2.close) * recovPct;
      isMS = c2.close < c2.open     // C2 bearish
          && _isLarge(c2, avgRng)
          && _isStar(c1)
          && c0.close > c0.open     // C0 bullish
          && msRecovery
          && msDowntrend;
    }

    // ─── Evening Star ─────────────────────────────────
    // C2: large bullish | C1: star | C0: bearish recovery
    // Pine: close[4]<close[3]<close[2] (uptrend into C2)
    bool isES = false;
    if (Config.patternES) {
      final esUptrend = requireTrend
          ? (c4.close < c3.close && c3.close < c2.close)
          : true;
      // Recovery: C0 closes below C2.close - (C2.close - C2.open) * pct
      final esRecovery = c0.close <
          c2.close - (c2.close - c2.open) * recovPct;
      isES = c2.close > c2.open     // C2 bullish
          && _isLarge(c2, avgRng)
          && _isStar(c1)
          && c0.close < c0.open     // C0 bearish
          && esRecovery
          && esUptrend;
    }

    return PatternResult(isBE: isBE, isMS: isMS, isES: isES);
  }
}
