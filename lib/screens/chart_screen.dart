// ─── screens/chart_screen.dart ──────────────────────────
// Interactive candlestick chart — 2 months of Binance data.
// Features: pinch-zoom, pan, crosshair, HH/LL pivot lines,
// current price line, OHLCV info bar.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/binance_service.dart';
import '../services/pivot_service.dart';

// ══════════════════════════════════════════════════════════
// CHART SCREEN
// ══════════════════════════════════════════════════════════
class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  // ── Symbol / timeframe ────────────────────────────────
  String _symbol    = Config.symbols.isNotEmpty ? Config.symbols.first : 'BTCUSDT';
  String _timeframe = '1h';

  // ── Data ──────────────────────────────────────────────
  List<Candle> _candles  = [];
  bool         _loading  = false;
  String?      _error;
  PivotResult? _pivots;
  bool         _showPivots = true;

  // ── Chart viewport ────────────────────────────────────
  double _candleWidth   = 8.0; // px per candle slot
  double _scrollCandles = 0.0; // candles scrolled from right edge

  // ── Gesture tracking ──────────────────────────────────
  double _gStartCW     = 8.0;
  double _gStartScroll = 0.0;
  Offset _gStartFocal  = Offset.zero;

  // ── Crosshair ─────────────────────────────────────────
  Offset? _crosshair;
  int?    _selectedIdx;

  final TextEditingController _symCtrl = TextEditingController();

  static const List<String> _timeframes = [
    '5m', '15m', '30m', '1h', '4h', '1d', '1w',
  ];

  @override
  void initState() {
    super.initState();
    _symCtrl.text = _symbol;
    _fetch();
  }

  @override
  void dispose() {
    _symCtrl.dispose();
    super.dispose();
  }

  // ── Fetch 2 months of candles ─────────────────────────
  Future<void> _fetch() async {
    setState(() {
      _loading     = true;
      _error       = null;
      _candles     = [];
      _selectedIdx = null;
      _crosshair   = null;
    });
    try {
      final candles = await BinanceService.fetchCandlesForChart(
          _symbol, _timeframe);
      PivotResult? piv;
      if (candles.length >= Config.pivotLen * 2 + 1) {
        piv = PivotService.getHHLL(candles);
      }
      setState(() {
        _candles       = candles;
        _pivots        = piv;
        _loading       = false;
        _scrollCandles = 0;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Gesture handlers ──────────────────────────────────
  void _onScaleStart(ScaleStartDetails d) {
    _gStartCW     = _candleWidth;
    _gStartScroll = _scrollCandles;
    _gStartFocal  = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      // Pinch = zoom
      _candleWidth =
          (_gStartCW * d.scale).clamp(2.0, 40.0);

      // Pan = scroll
      final dx       = d.localFocalPoint.dx - _gStartFocal.dx;
      final maxScroll =
          (_candles.length - 5).toDouble().clamp(0.0, double.infinity);
      _scrollCandles =
          (_gStartScroll - dx / _candleWidth).clamp(0.0, maxScroll);

      // Crosshair only on single-finger drag
      if (d.pointerCount == 1) {
        _crosshair = d.localFocalPoint;
      } else {
        _crosshair   = null;
        _selectedIdx = null;
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    setState(() {
      _crosshair   = null;
      _selectedIdx = null;
    });
  }

  // ── Symbol submit ─────────────────────────────────────
  void _submitSymbol() {
    final s = _symCtrl.text.trim().toUpperCase();
    if (s.isNotEmpty && s != _symbol) {
      setState(() => _symbol = s);
      _fetch();
    }
  }

  // ── Build ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121E),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: _buildTitle(),
        actions: [
          IconButton(
            icon: Icon(
              Icons.horizontal_rule_rounded,
              color: _showPivots ? Colors.orange : Colors.grey.shade600,
            ),
            tooltip: 'Toggle HH/LL pivot lines',
            onPressed: () => setState(() => _showPivots = !_showPivots),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loading ? null : _fetch,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildTfBar(),
          Expanded(child: _buildBody()),
          _buildInfoBar(),
        ],
      ),
    );
  }

  // ── AppBar title — symbol input + live price ──────────
  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _symCtrl,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.search,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(12),
              ],
              onSubmitted: (_) => _submitSymbol(),
              decoration: const InputDecoration(
                hintText: 'Symbol...',
                hintStyle: TextStyle(color: Color(0xFF555577), fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_candles.isNotEmpty) ...[
            Text(
              _fmtP(_candles.last.close),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _candles.last.close >= _candles.last.open
                    ? const Color(0xFF26A69A)
                    : const Color(0xFFEF5350),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  // ── Timeframe selector bar ────────────────────────────
  Widget _buildTfBar() {
    return Container(
      color: const Color(0xFF12121E),
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 8),
          ..._timeframes.map((tf) {
            final sel = tf == _timeframe;
            return GestureDetector(
              onTap: () {
                if (tf != _timeframe) {
                  setState(() => _timeframe = tf);
                  _fetch();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: sel
                      ? Colors.blueAccent.withOpacity(0.9)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: sel
                      ? null
                      : Border.all(color: const Color(0xFF2A2A40)),
                ),
                child: Text(
                  tf,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    color: sel ? Colors.white : Colors.grey.shade500,
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          if (_candles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '${_candles.length} bars · 2m',
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF444466)),
              ),
            ),
        ],
      ),
    );
  }

  // ── Main chart body ───────────────────────────────────
  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
                color: Colors.blueAccent, strokeWidth: 2),
            SizedBox(height: 14),
            Text('Fetching 2 months of data...',
                style: TextStyle(color: Color(0xFF555577), fontSize: 13)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 12),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_candles.isEmpty) {
      return const Center(
        child: Text('No data',
            style: TextStyle(color: Color(0xFF555577), fontSize: 14)),
      );
    }

    return GestureDetector(
      onScaleStart:  _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd:    _onScaleEnd,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          _selectedIdx = _crosshair != null
              ? _resolveIdx(_crosshair!, size)
              : null;
          return CustomPaint(
            painter: _ChartPainter(
              candles:       _candles,
              candleWidth:   _candleWidth,
              scrollCandles: _scrollCandles,
              pivots:        _showPivots ? _pivots : null,
              selectedIdx:   _selectedIdx,
              crosshair:     _crosshair,
            ),
            size: size,
          );
        },
      ),
    );
  }

  // ── OHLCV info bar ────────────────────────────────────
  Widget _buildInfoBar() {
    final Candle? c;
    if (_selectedIdx != null &&
        _selectedIdx! >= 0 &&
        _selectedIdx! < _candles.length) {
      c = _candles[_selectedIdx!];
    } else if (_candles.isNotEmpty) {
      c = _candles.last;
    } else {
      c = null;
    }

    if (c == null) {
      return Container(color: const Color(0xFF0D0D1A), height: 36);
    }

    final isBull  = c.close >= c.open;
    final color   = isBull ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final chg     = (c.close - c.open) / c.open * 100;
    final dateStr = '${c.time.year}-${_p2(c.time.month)}-${_p2(c.time.day)}'
        ' ${_p2(c.time.hour)}:${_p2(c.time.minute)}';

    return Container(
      color: const Color(0xFF0D0D1A),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Text(dateStr,
              style:
                  const TextStyle(fontSize: 9, color: Color(0xFF555577))),
          const SizedBox(width: 8),
          _ohlcv('O', c.open,  Colors.grey.shade500),
          _ohlcv('H', c.high,  const Color(0xFF26A69A)),
          _ohlcv('L', c.low,   const Color(0xFFEF5350)),
          _ohlcv('C', c.close, color),
          const Spacer(),
          Text(
            '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _ohlcv(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
              text: '$label ',
              style: const TextStyle(
                  fontSize: 9, color: Color(0xFF555577))),
          TextSpan(
              text: _fmtP(value),
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Resolve candle index from crosshair x ─────────────
  int? _resolveIdx(Offset pos, Size size) {
    const priceAxisW = 65.0;
    final chartW = size.width - priceAxisW;
    if (pos.dx < 0 || pos.dx > chartW) return null;
    final lastIdx =
        (_candles.length - 1 - _scrollCandles).round().clamp(0, _candles.length - 1);
    final fromRight = (chartW - pos.dx) / _candleWidth;
    return (lastIdx - fromRight).round().clamp(0, _candles.length - 1);
  }

  // ── Formatters ────────────────────────────────────────
  String _fmtP(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100)   return v.toStringAsFixed(2);
    if (v >= 1)     return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }

  String _p2(int n) => n.toString().padLeft(2, '0');
}

// ══════════════════════════════════════════════════════════
// CUSTOM PAINTER
// ══════════════════════════════════════════════════════════
class _ChartPainter extends CustomPainter {
  final List<Candle> candles;
  final double       candleWidth;
  final double       scrollCandles;
  final PivotResult? pivots;
  final int?         selectedIdx;
  final Offset?      crosshair;

  _ChartPainter({
    required this.candles,
    required this.candleWidth,
    required this.scrollCandles,
    this.pivots,
    this.selectedIdx,
    this.crosshair,
  });

  static const double _priceW   = 65.0;
  static const double _timeH    = 26.0;
  static const Color  _bull     = Color(0xFF26A69A);
  static const Color  _bear     = Color(0xFFEF5350);
  static const Color  _gridLine = Color(0xFF1A1A2E);
  static const Color  _axisCol  = Color(0xFF606080);

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final cW = size.width - _priceW;
    final cH = size.height - _timeH;

    // ── Visible range ─────────────────────────────────
    final lastVis  = (candles.length - 1 - scrollCandles)
        .round()
        .clamp(0, candles.length - 1);
    final nVis     = (cW / candleWidth).ceil() + 2;
    final firstVis = (lastVis - nVis).clamp(0, candles.length - 1);

    if (firstVis > lastVis) return;
    final vis = candles.sublist(firstVis, lastVis + 1);
    if (vis.isEmpty) return;

    // ── Price range ───────────────────────────────────
    var lo = vis.map((c) => c.low).reduce(math.min);
    var hi = vis.map((c) => c.high).reduce(math.max);
    if (pivots?.hh != null) hi = math.max(hi, pivots!.hh!);
    if (pivots?.ll != null) lo = math.min(lo, pivots!.ll!);
    final range = hi - lo;
    if (range == 0) return;
    final pad = range * 0.06;
    lo -= pad;
    hi += pad;

    double p2y(double p) => cH * (1 - (p - lo) / (hi - lo));

    // ── Background ────────────────────────────────────
    canvas.drawRect(Rect.fromLTWH(0, 0, cW, cH),
        Paint()..color = const Color(0xFF0A0A14));

    // ── Grid lines ────────────────────────────────────
    final gridPaint = Paint()..color = _gridLine..strokeWidth = 0.5;
    for (int i = 0; i <= 5; i++) {
      final y = cH * i / 5;
      canvas.drawLine(Offset(0, y), Offset(cW, y), gridPaint);
    }

    // Vertical separator
    canvas.drawLine(Offset(cW, 0), Offset(cW, cH),
        Paint()..color = const Color(0xFF1E1E35)..strokeWidth = 1);

    // ── HH / LL horizontal dashed lines ───────────────
    if (pivots?.hh != null) {
      _dashH(canvas, p2y(pivots!.hh!), cW,
          const Color(0xFFFFA726), 5, 4);
    }
    if (pivots?.ll != null) {
      _dashH(canvas, p2y(pivots!.ll!), cW,
          const Color(0xFFAB47BC), 5, 4);
    }

    // ── Candles (clip to chart area) ──────────────────
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, cW, cH));

    for (int i = firstVis; i <= lastVis; i++) {
      final c   = candles[i];
      final x   = cW - (lastVis - i) * candleWidth - candleWidth / 2;
      if (x < -candleWidth * 2 || x > cW + candleWidth) continue;

      final isBull = c.close >= c.open;
      final col    = isBull ? _bull : _bear;
      final isHl   = i == selectedIdx;

      // Wick
      canvas.drawLine(
        Offset(x, p2y(c.high)),
        Offset(x, p2y(c.low)),
        Paint()
          ..color      = col
          ..strokeWidth = math.max(1.0, candleWidth * 0.1),
      );

      // Body
      final bTop  = p2y(math.max(c.open, c.close));
      final bBot  = p2y(math.min(c.open, c.close));
      final bodyH = math.max(bBot - bTop, 1.0);
      final bodyW = math.max(candleWidth * 0.65, 1.0);

      canvas.drawRect(
        Rect.fromLTWH(x - bodyW / 2, bTop, bodyW, bodyH),
        Paint()..color = col,
      );

      // Highlight ring for selected candle
      if (isHl) {
        canvas.drawRect(
          Rect.fromLTWH(x - bodyW / 2 - 1, bTop - 1, bodyW + 2, bodyH + 2),
          Paint()
            ..color      = Colors.white.withOpacity(0.2)
            ..style      = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }

    canvas.restore();

    // ── Current price dashed line ─────────────────────
    final curY = p2y(candles.last.close);
    if (curY >= 0 && curY <= cH) {
      _dashH(canvas, curY, cW, Colors.white.withOpacity(0.3), 3, 5);
    }

    // ── Crosshair ─────────────────────────────────────
    if (crosshair != null) {
      final xp = Paint()
        ..color      = Colors.white.withOpacity(0.22)
        ..strokeWidth = 0.7;
      canvas.drawLine(
          Offset(crosshair!.dx, 0), Offset(crosshair!.dx, cH), xp);
      if (crosshair!.dy >= 0 && crosshair!.dy <= cH) {
        canvas.drawLine(
            Offset(0, crosshair!.dy), Offset(cW, crosshair!.dy), xp);
        // Price tag at crosshair Y
        final chPrice = lo + (1 - crosshair!.dy / cH) * (hi - lo);
        _drawPriceBox(canvas, cW, crosshair!.dy, chPrice,
            Colors.white.withOpacity(0.9), const Color(0xFF222240));
      }
    }

    // ── Price axis (right) ────────────────────────────
    for (int i = 0; i <= 5; i++) {
      final y  = cH * i / 5;
      final pr = lo + (1 - i / 5) * (hi - lo);
      _paintText(_fmtP(pr), _axisCol, 9.5, canvas,
          Offset(cW + 4, y - 5));
    }

    // ── HH / LL price tag boxes ───────────────────────
    if (pivots?.hh != null) {
      final y = p2y(pivots!.hh!).clamp(4.0, cH - 14.0);
      _drawTagBox(canvas, cW, y, pivots!.hh!,
          const Color(0xFFFFA726), 'HH');
    }
    if (pivots?.ll != null) {
      final y = p2y(pivots!.ll!).clamp(4.0, cH - 14.0);
      _drawTagBox(canvas, cW, y, pivots!.ll!,
          const Color(0xFFAB47BC), 'LL');
    }

    // ── Current price box ─────────────────────────────
    if (curY >= 0 && curY <= cH) {
      final isBull = candles.last.close >= candles.last.open;
      _drawPriceBox(
        canvas, cW, curY, candles.last.close,
        isBull ? _bull : _bear,
        isBull ? const Color(0xFF1A3A38) : const Color(0xFF3A1A1A),
      );
    }

    // ── Time axis (bottom) ────────────────────────────
    final totalVis = lastVis - firstVis + 1;
    final step     = math.max(1, totalVis ~/ 5);
    for (int i = firstVis; i <= lastVis; i += step) {
      final x = cW - (lastVis - i) * candleWidth - candleWidth / 2;
      if (x < 10 || x > cW - 10) continue;
      final lbl = _fmtT(candles[i].time);
      final tp  = _makeTP(lbl, _axisCol, 9.0);
      tp.paint(canvas,
          Offset((x - tp.width / 2).clamp(0.0, cW - tp.width), cH + 5));
    }
  }

  // ── Draw dashed horizontal line ───────────────────────
  void _dashH(Canvas canvas, double y, double w, Color color,
      double dash, double gap) {
    final paint = Paint()..color = color..strokeWidth = 0.9;
    double x    = 0;
    bool   draw = true;
    while (x < w) {
      final end = math.min(x + (draw ? dash : gap), w);
      if (draw) canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x    = end;
      draw = !draw;
    }
  }

  // ── Filled price box on right axis ───────────────────
  void _drawPriceBox(Canvas canvas, double cW, double y, double price,
      Color textColor, Color bgColor) {
    final tp   = _makeTP(_fmtP(price), textColor, 10.0, bold: true);
    final rect = Rect.fromLTWH(
        cW + 2, y - tp.height / 2 - 2, tp.width + 8, tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = bgColor);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color      = textColor.withOpacity(0.35)
          ..style      = PaintingStyle.stroke
          ..strokeWidth = 0.8);
    tp.paint(canvas, Offset(cW + 6, y - tp.height / 2));
  }

  // ── HH/LL tag box ─────────────────────────────────────
  void _drawTagBox(Canvas canvas, double cW, double y, double price,
      Color color, String tag) {
    final tp   = _makeTP('$tag ${_fmtP(price)}', color, 9.0, bold: true);
    final rect = Rect.fromLTWH(
        cW + 2, y - tp.height / 2 - 2, tp.width + 8, tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = color.withOpacity(0.18));
    tp.paint(canvas, Offset(cW + 6, y - tp.height / 2));
  }

  // ── Simple text helper ────────────────────────────────
  void _paintText(String text, Color color, double fontSize,
      Canvas canvas, Offset offset) {
    _makeTP(text, color, fontSize).paint(canvas, offset);
  }

  TextPainter _makeTP(String text, Color color, double size,
      {bool bold = false}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize:   size,
          color:      color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  // ── Formatters ────────────────────────────────────────
  String _fmtP(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100)   return v.toStringAsFixed(2);
    if (v >= 1)     return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }

  String _fmtT(DateTime t) {
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    if (t.hour == 0 && t.minute == 0) return '$m/$d';
    return '${t.hour.toString().padLeft(2,'0')}:'
           '${t.minute.toString().padLeft(2,'0')}';
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.candles       != candles       ||
      old.candleWidth   != candleWidth   ||
      old.scrollCandles != scrollCandles ||
      old.pivots        != pivots        ||
      old.selectedIdx   != selectedIdx   ||
      old.crosshair     != crosshair;
}
