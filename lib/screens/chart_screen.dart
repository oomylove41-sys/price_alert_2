// ─── screens/chart_screen.dart ──────────────────────────
// Interactive candlestick chart
//   • Live price auto-refresh every 15 s
//   • 9 months of historical data with gap-fill
//   • Multi-pair switcher with search
//   • Pinch-zoom X · Pan · Crosshair (cursor mode)
//   • Auto-scale toggle (Y-axis fits visible candles)
//   • Draw: Trend Lines and Horizontal Lines
//   • OHLCV info bar · time axis · price axis

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/binance_service.dart';
import '../services/pivot_service.dart';

// ══════════════════════════════════════════════════════════
// DRAWING DATA CLASSES
// ══════════════════════════════════════════════════════════

enum DrawTool { cursor, trendLine, hLine }

class TrendLineData {
  final String id;
  final int    idx1;
  final double price1;
  final int    idx2;
  final double price2;
  final Color  color;

  TrendLineData({
    required this.id,
    required this.idx1,
    required this.price1,
    required this.idx2,
    required this.price2,
    required this.color,
  });
}

class HorizLineData {
  final String id;
  final double price;
  final Color  color;

  HorizLineData({required this.id, required this.price, required this.color});
}

class _PriceRange {
  final double lo;
  final double hi;
  _PriceRange(this.lo, this.hi);
}

// ══════════════════════════════════════════════════════════
// CHART SCREEN
// ══════════════════════════════════════════════════════════
class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Symbol / timeframe ────────────────────────────────
  late String _symbol;
  String _timeframe = '1h';

  // ── Data ──────────────────────────────────────────────
  List<Candle> _candles    = [];
  bool         _loading    = false;
  bool         _refreshing = false;
  String?      _error;
  DateTime?    _lastUpdated;

  // ── Live price ────────────────────────────────────────
  Timer?  _liveTimer;
  double? _livePrice;

  // ── Viewport ──────────────────────────────────────────
  static const double _rightPadCandles = 3.0;
  double _candleWidth   = 8.0;
  double _scrollCandles = 0.0;

  // ── Auto-scale ────────────────────────────────────────
  bool   _autoScale = true;
  double _manualLo  = 0;
  double _manualHi  = 1;

  // ── Drawing tools ─────────────────────────────────────
  DrawTool            _drawTool  = DrawTool.cursor;
  final List<TrendLineData>  _trendLines = [];
  final List<HorizLineData>  _horizLines = [];
  int    _lineIdCounter = 0;

  // Pending trend line (first point placed)
  int?    _pendingTlIdx;
  double? _pendingTlPrice;

  // Current touch position (for rubber-band preview)
  Offset? _touchPos;

  // ── Gesture tracking ──────────────────────────────────
  double  _gStartCW     = 8.0;
  double  _gStartScroll = 0.0;
  Offset  _gStartFocal  = Offset.zero;
  Offset? _tapStart;
  bool    _tapMoved     = false;
  int     _tapPointers  = 1;

  // ── Crosshair ─────────────────────────────────────────
  Offset? _crosshair;
  int?    _selectedIdx;

  // ── Chart size (set by LayoutBuilder) ─────────────────
  Size _chartSize = Size.zero;

  // ── Pair search ───────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();

  static const List<String> _timeframes = [
    '5m','15m','30m','1h','4h','1d','1w',
  ];

  // Line color palette
  static const List<Color> _lineColors = [
    Color(0xFF26C6DA), Color(0xFFFFB74D), Color(0xFFAB47BC),
    Color(0xFF66BB6A), Color(0xFFEF9A9A), Color(0xFFFFEE58),
  ];

  Color _nextColor() =>
      _lineColors[(_trendLines.length + _horizLines.length) % _lineColors.length];

  String _nextId() => '${++_lineIdCounter}';

  // ══════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _symbol = Config.symbols.isNotEmpty ? Config.symbols.first : 'BTCUSDT';
    _fetchHistory();
    _startLiveTimer();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════
  // DATA FETCHING
  // ══════════════════════════════════════════════════════

  Future<void> _fetchHistory() async {
    setState(() {
      _loading      = true;
      _error        = null;
      _candles      = [];
      _selectedIdx  = null;
      _crosshair    = null;
      _livePrice    = null;
      // Clear pending draw state on symbol/TF change
      _pendingTlIdx   = null;
      _pendingTlPrice = null;
      _touchPos       = null;
    });
    try {
      final candles = await BinanceService.fetchCandlesForChart(
          _symbol, _timeframe, months: 9);
      if (!mounted) return;
      setState(() {
        _candles       = candles;
        _loading       = false;
        _scrollCandles = 0;
        _lastUpdated   = DateTime.now();
        if (_autoScale) _captureRange(candles);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _liveRefresh() async {
    if (_loading || _candles.isEmpty) return;
    setState(() => _refreshing = true);
    try {
      final price  = await BinanceService.getCurrentPrice(_symbol);
      final recent = await BinanceService.fetchCandlesFrom(
          _symbol, _timeframe, _candles.last.time);
      if (!mounted) return;
      setState(() {
        _livePrice   = price;
        _lastUpdated = DateTime.now();
        for (final fresh in recent) {
          final idx = _candles.indexWhere(
              (c) => c.time.isAtSameMomentAs(fresh.time));
          if (idx >= 0) {
            _candles[idx] = fresh;
          } else if (fresh.time.isAfter(_candles.last.time)) {
            _candles.add(fresh);
          }
        }
        _refreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _refreshing = false);
    }
  }

  void _startLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 15), (_) => _liveRefresh());
  }

  // ══════════════════════════════════════════════════════
  // AUTO-SCALE HELPERS
  // ══════════════════════════════════════════════════════

  void _captureRange(List<Candle> vis) {
    if (vis.isEmpty) return;
    var lo = vis.map((c) => c.low).reduce(math.min);
    var hi = vis.map((c) => c.high).reduce(math.max);
    final rng = hi - lo;
    _manualLo = lo - rng * 0.07;
    _manualHi = hi + rng * 0.07;
  }

  _PriceRange _computeRange() {
    final vis = _getVisibleCandles();
    if (vis.isEmpty) return _PriceRange(_manualLo, _manualHi);
    var lo = vis.map((c) => c.low).reduce(math.min);
    var hi = vis.map((c) => c.high).reduce(math.max);
    if (_livePrice != null) {
      hi = math.max(hi, _livePrice!);
      lo = math.min(lo, _livePrice!);
    }
    // Expand range to include user lines in view
    for (final hl in _horizLines) {
      hi = math.max(hi, hl.price);
      lo = math.min(lo, hl.price);
    }
    final rng = hi - lo;
    return _PriceRange(lo - rng * 0.07, hi + rng * 0.07);
  }

  List<Candle> _getVisibleCandles() {
    if (_candles.isEmpty || _chartSize == Size.zero) return _candles;
    const priceW = 66.0;
    final cW     = _chartSize.width - priceW;
    final rightPx = _rightPadCandles * _candleWidth;
    final lastVis  = (_candles.length - 1 - _scrollCandles)
        .round().clamp(0, _candles.length - 1);
    final nVis     = ((cW - rightPx) / _candleWidth).ceil() + 2;
    final firstVis = (lastVis - nVis).clamp(0, _candles.length - 1);
    if (firstVis > lastVis) return [];
    return _candles.sublist(firstVis, lastVis + 1);
  }

  // ══════════════════════════════════════════════════════
  // GESTURE HANDLERS
  // ══════════════════════════════════════════════════════

  void _onScaleStart(ScaleStartDetails d) {
    _tapStart    = d.localFocalPoint;
    _tapMoved    = false;
    _tapPointers = d.pointerCount;
    _gStartCW     = _candleWidth;
    _gStartScroll = _scrollCandles;
    _gStartFocal  = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    _tapPointers = d.pointerCount;
    _touchPos    = d.localFocalPoint; // always track for preview

    // Detect if this is a drag vs tap
    if (_tapStart != null) {
      final dx = (d.localFocalPoint.dx - _tapStart!.dx).abs();
      final dy = (d.localFocalPoint.dy - _tapStart!.dy).abs();
      if (dx > 10 || dy > 10 || (d.scale - 1.0).abs() > 0.05) {
        _tapMoved = true;
      }
    }

    // ── 2-finger: always zoom & scroll (even in draw mode) ──
    if (d.pointerCount >= 2) {
      setState(() {
        _candleWidth =
            (_gStartCW * d.scale).clamp(2.0, 40.0);
        final maxScroll = (_candles.length - 5)
            .toDouble().clamp(0.0, double.infinity);
        final dx = d.localFocalPoint.dx - _gStartFocal.dx;
        _scrollCandles =
            (_gStartScroll - dx / _candleWidth).clamp(0.0, maxScroll);
        // Re-capture range if auto-scale off so Y stays stable while zooming
        if (!_autoScale) {
          // keep current manual range
        }
      });
      return;
    }

    // ── 1-finger cursor mode: scroll + crosshair ──────────
    if (_drawTool == DrawTool.cursor && _tapMoved) {
      setState(() {
        _candleWidth =
            (_gStartCW * d.scale).clamp(2.0, 40.0);
        final maxScroll = (_candles.length - 5)
            .toDouble().clamp(0.0, double.infinity);
        final dx = d.localFocalPoint.dx - _gStartFocal.dx;
        _scrollCandles =
            (_gStartScroll - dx / _candleWidth).clamp(0.0, maxScroll);
        _crosshair   = d.localFocalPoint;
        _selectedIdx = _posToIdx(d.localFocalPoint);
      });
      return;
    }

    // ── 1-finger draw mode: just refresh preview ──────────
    if (_drawTool != DrawTool.cursor) {
      setState(() {}); // triggers repaint for rubber-band
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Detect tap: single finger, no significant movement
    if (!_tapMoved && _tapPointers == 1 && _drawTool != DrawTool.cursor) {
      if (_tapStart != null) _handleDrawTap(_tapStart!);
    }
    setState(() {
      _crosshair   = null;
      _selectedIdx = null;
      _touchPos    = null;
    });
  }

  // ══════════════════════════════════════════════════════
  // DRAWING HANDLERS
  // ══════════════════════════════════════════════════════

  void _handleDrawTap(Offset pos) {
    if (_candles.isEmpty) return;
    final idx   = _posToIdx(pos);
    final price = _posToPrice(pos);
    if (idx == null || price == null) return;

    setState(() {
      if (_drawTool == DrawTool.hLine) {
        _horizLines.add(HorizLineData(
            id: _nextId(), price: price, color: _nextColor()));
      } else if (_drawTool == DrawTool.trendLine) {
        if (_pendingTlIdx == null) {
          // First point
          _pendingTlIdx   = idx;
          _pendingTlPrice = price;
        } else {
          // Second point → complete line
          _trendLines.add(TrendLineData(
            id:     _nextId(),
            idx1:   _pendingTlIdx!,
            price1: _pendingTlPrice!,
            idx2:   idx,
            price2: price,
            color:  _nextColor(),
          ));
          _pendingTlIdx   = null;
          _pendingTlPrice = null;
        }
      }
    });
  }

  // Convert screen x → candle index (matches painter's cX formula)
  int? _posToIdx(Offset pos) {
    const priceW = 66.0;
    final cW     = _chartSize.width - priceW;
    if (pos.dx < 0 || pos.dx > cW) return null;
    final rightPx = _rightPadCandles * _candleWidth;
    final lastVis = (_candles.length - 1 - _scrollCandles)
        .round().clamp(0, _candles.length - 1);
    // cX(i) = cW - rightPx - (lastVis-i)*cW - cW/2
    // Solve for i:
    final i = lastVis -
        (cW - rightPx - _candleWidth / 2 - pos.dx) / _candleWidth;
    return i.round().clamp(0, _candles.length - 1);
  }

  // Convert screen y → price
  double? _posToPrice(Offset pos) {
    const timeH = 26.0;
    final cH    = _chartSize.height - timeH;
    if (pos.dy < 0 || pos.dy > cH) return null;
    final range = _autoScale ? _computeRange() : _PriceRange(_manualLo, _manualHi);
    return range.lo + (1 - pos.dy / cH) * (range.hi - range.lo);
  }

  // ══════════════════════════════════════════════════════
  // PAIR SELECTOR
  // ══════════════════════════════════════════════════════

  void _openPairSelector() {
    _searchCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PairSheet(
        current:    _symbol,
        searchCtrl: _searchCtrl,
        onSelect:   (sym) {
          Navigator.pop(context);
          if (sym != _symbol) {
            setState(() {
              _symbol     = sym;
              _trendLines.clear();
              _horizLines.clear();
              _pendingTlIdx   = null;
              _pendingTlPrice = null;
            });
            _fetchHistory();
          }
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTfBar(),
          _buildDrawToolbar(),
          Expanded(child: _buildBody()),
          _buildInfoBar(),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    final liveColor = _candles.isNotEmpty
        ? (_candles.last.close >= _candles.last.open
            ? const Color(0xFF26A69A)
            : const Color(0xFFEF5350))
        : Colors.grey;
    final displayPrice =
        _livePrice ?? (_candles.isNotEmpty ? _candles.last.close : null);

    return AppBar(
      backgroundColor: const Color(0xFF12121E),
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: GestureDetector(
        onTap: _openPairSelector,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_symbol,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(width: 3),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Color(0xFF888899)),
              const SizedBox(width: 10),
              if (displayPrice != null)
                Text(_fmtP(displayPrice),
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold,
                        color: liveColor)),
              if (_refreshing) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 8, height: 8,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.blueAccent.withOpacity(0.7)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        // Live dot
        Padding(
          padding: const EdgeInsets.only(right: 4, top: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: _refreshing ? Colors.orange : const Color(0xFF26A69A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 1),
              Text('LIVE',
                  style: TextStyle(
                      fontSize: 7, color: Colors.grey.shade600,
                      letterSpacing: 0.5)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: _loading ? null : _fetchHistory,
        ),
        const SizedBox(width: 2),
      ],
    );
  }

  // ── Timeframe bar ─────────────────────────────────────
  Widget _buildTfBar() {
    return Container(
      color: const Color(0xFF12121E),
      height: 34,
      child: Row(children: [
        const SizedBox(width: 6),
        ..._timeframes.map((tf) {
          final sel = tf == _timeframe;
          return GestureDetector(
            onTap: () {
              if (tf != _timeframe) {
                setState(() => _timeframe = tf);
                _fetchHistory();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(
                color: sel ? Colors.blueAccent.withOpacity(0.9) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: sel ? null : Border.all(color: const Color(0xFF2A2A40)),
              ),
              child: Text(tf,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      color: sel ? Colors.white : Colors.grey.shade500)),
            ),
          );
        }),
        const Spacer(),
        if (_lastUpdated != null)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              '${_p2(_lastUpdated!.hour)}:${_p2(_lastUpdated!.minute)}:${_p2(_lastUpdated!.second)}',
              style: const TextStyle(fontSize: 9, color: Color(0xFF444466)),
            ),
          ),
      ]),
    );
  }

  // ── Drawing toolbar ───────────────────────────────────
  Widget _buildDrawToolbar() {
    return Container(
      height: 38,
      color: const Color(0xFF0D0D1A),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          // ── Tool buttons ──────────────────────────────
          _ToolBtn(
            icon:    Icons.near_me_rounded,
            label:   'Cursor',
            active:  _drawTool == DrawTool.cursor,
            onTap:   () => setState(() {
              _drawTool       = DrawTool.cursor;
              _pendingTlIdx   = null;
              _pendingTlPrice = null;
            }),
          ),
          const SizedBox(width: 4),
          _ToolBtn(
            icon:   Icons.show_chart_rounded,
            label:  'Trend',
            active: _drawTool == DrawTool.trendLine,
            onTap:  () => setState(() {
              _drawTool       = DrawTool.trendLine;
              _pendingTlIdx   = null;
              _pendingTlPrice = null;
            }),
            // Show a dot indicator when first point is placed
            badge: _drawTool == DrawTool.trendLine && _pendingTlIdx != null
                ? '1/2'
                : null,
          ),
          const SizedBox(width: 4),
          _ToolBtn(
            icon:   Icons.horizontal_rule_rounded,
            label:  'H-Line',
            active: _drawTool == DrawTool.hLine,
            onTap:  () => setState(() {
              _drawTool       = DrawTool.hLine;
              _pendingTlIdx   = null;
              _pendingTlPrice = null;
            }),
          ),

          const Spacer(),

          // ── Auto-scale toggle ─────────────────────────
          GestureDetector(
            onTap: () {
              setState(() {
                _autoScale = !_autoScale;
                if (_autoScale) {
                  // Refit to visible candles
                  final vis = _getVisibleCandles();
                  _captureRange(vis);
                } else {
                  // Lock current range
                  final r = _computeRange();
                  _manualLo = r.lo;
                  _manualHi = r.hi;
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _autoScale
                    ? Colors.blueAccent.withOpacity(0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: _autoScale
                      ? Colors.blueAccent.withOpacity(0.7)
                      : Colors.grey.shade700,
                ),
              ),
              child: Text(
                'Auto',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _autoScale ? Colors.blueAccent : Colors.grey.shade500,
                ),
              ),
            ),
          ),

          // ── Clear all lines ───────────────────────────
          if (_trendLines.isNotEmpty || _horizLines.isNotEmpty) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() {
                _trendLines.clear();
                _horizLines.clear();
                _pendingTlIdx   = null;
                _pendingTlPrice = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: Icon(Icons.delete_outline_rounded,
                    size: 14, color: Colors.grey.shade500),
              ),
            ),
          ],
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  // ── Chart body ────────────────────────────────────────
  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 32, height: 32,
              child: CircularProgressIndicator(
                  color: Colors.blueAccent, strokeWidth: 2),
            ),
            const SizedBox(height: 14),
            Text('Loading $_symbol...',
                style: const TextStyle(
                    color: Color(0xFF555577), fontSize: 13)),
            const SizedBox(height: 4),
            const Text('Fetching historical data',
                style: TextStyle(color: Color(0xFF333355), fontSize: 11)),
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
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF888888), fontSize: 12)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchHistory,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_candles.isEmpty) {
      return const Center(
          child: Text('No data',
              style: TextStyle(color: Color(0xFF555577), fontSize: 14)));
    }

    return GestureDetector(
      onScaleStart:  _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd:    _onScaleEnd,
      child: LayoutBuilder(builder: (ctx, constraints) {
        _chartSize = Size(constraints.maxWidth, constraints.maxHeight);
        final priceRange = _autoScale
            ? _computeRange()
            : _PriceRange(_manualLo, _manualHi);
        return CustomPaint(
          painter: _ChartPainter(
            candles:         _candles,
            candleWidth:     _candleWidth,
            scrollCandles:   _scrollCandles,
            rightPadCandles: _rightPadCandles,
            trendLines:      List.unmodifiable(_trendLines),
            horizLines:      List.unmodifiable(_horizLines),
            pendingTlIdx:    _pendingTlIdx,
            pendingTlPrice:  _pendingTlPrice,
            pendingTlScreen: (_pendingTlIdx != null && _touchPos != null)
                ? _touchPos
                : null,
            rangeLo:         priceRange.lo,
            rangeHi:         priceRange.hi,
            selectedIdx:     _selectedIdx,
            crosshair:       _crosshair,
            livePrice:       _livePrice,
            drawTool:        _drawTool,
          ),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      }),
    );
  }

  // ── OHLCV info bar ────────────────────────────────────
  Widget _buildInfoBar() {
    Candle? c;
    if (_selectedIdx != null &&
        _selectedIdx! >= 0 &&
        _selectedIdx! < _candles.length) {
      c = _candles[_selectedIdx!];
    } else if (_candles.isNotEmpty) {
      c = _candles.last;
    }

    if (c == null) {
      return Container(color: const Color(0xFF0D0D1A), height: 38);
    }

    final isBull = c.close >= c.open;
    final col    = isBull ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final chg    = (c.close - c.open) / c.open * 100;
    final date   =
        '${c.time.year}-${_p2(c.time.month)}-${_p2(c.time.day)} '
        '${_p2(c.time.hour)}:${_p2(c.time.minute)}';

    return Container(
      color: const Color(0xFF0D0D1A),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          Text(date,
              style: const TextStyle(fontSize: 9, color: Color(0xFF555577))),
          const SizedBox(width: 6),
          _ov('O', c.open,   const Color(0xFF888899)),
          _ov('H', c.high,   const Color(0xFF26A69A)),
          _ov('L', c.low,    const Color(0xFFEF5350)),
          _ov('C', c.close,  col),
          _ovVol('V', c.volume),
          const Spacer(),
          Text(
            '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: col),
          ),
          const SizedBox(width: 4),
          if (_selectedIdx == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF26A69A).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: const Color(0xFF26A69A).withOpacity(0.4)),
              ),
              child: const Text('LIVE',
                  style: TextStyle(
                      fontSize: 8, color: Color(0xFF26A69A),
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _ov(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(text: '$label ',
              style: const TextStyle(fontSize: 9, color: Color(0xFF555577))),
          TextSpan(text: _fmtP(value),
              style: TextStyle(
                  fontSize: 9.5, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _ovVol(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(text: '$label ',
              style: const TextStyle(fontSize: 9, color: Color(0xFF555577))),
          TextSpan(text: _fmtVol(value),
              style: const TextStyle(
                  fontSize: 9.5, color: Color(0xFF888899),
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Formatters ────────────────────────────────────────
  String _fmtP(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100)   return v.toStringAsFixed(2);
    if (v >= 1)     return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }

  String _fmtVol(double v) {
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _p2(int n) => n.toString().padLeft(2, '0');
}

// ══════════════════════════════════════════════════════════
// TOOL BUTTON WIDGET
// ══════════════════════════════════════════════════════════
class _ToolBtn extends StatelessWidget {
  final IconData   icon;
  final String     label;
  final bool       active;
  final VoidCallback onTap;
  final String?    badge; // small text badge

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active
                  ? Colors.blueAccent.withOpacity(0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: active
                    ? Colors.blueAccent.withOpacity(0.7)
                    : Colors.grey.shade800,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 15,
                    color: active ? Colors.blueAccent : Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.blueAccent : Colors.grey.shade500,
                    )),
              ],
            ),
          ),
          // Badge: "1/2" when first point of trend line is placed
          if (badge != null)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge!,
                    style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// PAIR SELECTOR SHEET
// ══════════════════════════════════════════════════════════
class _PairSheet extends StatefulWidget {
  final String                current;
  final TextEditingController searchCtrl;
  final ValueChanged<String>  onSelect;
  const _PairSheet({
    required this.current,
    required this.searchCtrl,
    required this.onSelect,
  });

  @override
  State<_PairSheet> createState() => _PairSheetState();
}

class _PairSheetState extends State<_PairSheet> {
  String _query = '';

  static const List<String> _popular = [
    'BTCUSDT','ETHUSDT','SOLUSDT','BNBUSDT','XRPUSDT',
    'DOGEUSDT','ADAUSDT','AVAXUSDT','DOTUSDT','LINKUSDT',
    'MATICUSDT','LTCUSDT','UNIUSDT','ATOMUSDT','NEARUSDT',
    'APTUSDT','ARBUSDT','OPUSDT','SUIUSDT','SEIUSDT',
    'INJUSDT','TIAUSDT','WIFUSDT','BONKUSDT','PEPEUSDT',
    'TRXUSDT','FTMUSDT','LDOUSDT','STXUSDT','RUNEUSDT',
    'ETHBTC','BNBBTC',
  ];

  List<String> get _symbols {
    final all = {...Config.symbols, ..._popular}.toList();
    if (_query.isEmpty) return all;
    final q = _query.toUpperCase();
    return all.where((s) => s.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Text('Select Pair',
                    style: TextStyle(
                        color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: widget.searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                decoration: InputDecoration(
                  hintText: 'Search… e.g. ETH, SOL, BNB',
                  hintStyle: const TextStyle(
                      color: Color(0xFF555577), fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Color(0xFF555577), size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            widget.searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: const Icon(Icons.close,
                              color: Color(0xFF555577), size: 18),
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFF2A2A40))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFF2A2A40))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Colors.blueAccent, width: 1.5)),
                ),
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (v) {
                  final sym = v.trim().toUpperCase();
                  if (sym.isNotEmpty) widget.onSelect(sym);
                },
              ),
            ),
            Expanded(
              child: _symbols.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off_rounded,
                              color: Color(0xFF444466), size: 40),
                          const SizedBox(height: 8),
                          const Text('No matches',
                              style:
                                  TextStyle(color: Color(0xFF555577))),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              final sym = _query.trim().toUpperCase();
                              if (sym.isNotEmpty) widget.onSelect(sym);
                            },
                            child: Text('Open "$_query" anyway →',
                                style: const TextStyle(
                                    color: Colors.blueAccent)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: ctrl,
                      itemCount: _symbols.length,
                      itemBuilder: (_, i) {
                        final sym   = _symbols[i];
                        final isCur = sym == widget.current;
                        final isWL  = Config.symbols.contains(sym);
                        final base  = sym.replaceAll(
                            RegExp(r'(USDT|BTC|ETH|BNB)$'), '');
                        return ListTile(
                          dense: true,
                          onTap: () => widget.onSelect(sym),
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: isCur
                                  ? Colors.blueAccent.withOpacity(0.2)
                                  : const Color(0xFF1A1A2E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              base.isNotEmpty ? base[0] : sym[0],
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isCur
                                      ? Colors.blueAccent
                                      : Colors.grey.shade400),
                            ),
                          ),
                          title: Row(children: [
                            Text(sym,
                                style: TextStyle(
                                    color: isCur
                                        ? Colors.blueAccent
                                        : Colors.white,
                                    fontWeight: isCur
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 13.5)),
                            if (isWL) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('WL',
                                    style: TextStyle(
                                        fontSize: 8,
                                        color: Colors.blueAccent,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ]),
                          trailing: isCur
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.blueAccent, size: 18)
                              : const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Color(0xFF444466), size: 13),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// CUSTOM PAINTER
// ══════════════════════════════════════════════════════════
class _ChartPainter extends CustomPainter {
  final List<Candle>         candles;
  final double               candleWidth;
  final double               scrollCandles;
  final double               rightPadCandles;
  final List<TrendLineData>  trendLines;
  final List<HorizLineData>  horizLines;
  final int?                 pendingTlIdx;
  final double?              pendingTlPrice;
  final Offset?              pendingTlScreen;
  final double               rangeLo;
  final double               rangeHi;
  final int?                 selectedIdx;
  final Offset?              crosshair;
  final double?              livePrice;
  final DrawTool             drawTool;

  const _ChartPainter({
    required this.candles,
    required this.candleWidth,
    required this.scrollCandles,
    required this.rightPadCandles,
    required this.trendLines,
    required this.horizLines,
    required this.rangeLo,
    required this.rangeHi,
    this.pendingTlIdx,
    this.pendingTlPrice,
    this.pendingTlScreen,
    this.selectedIdx,
    this.crosshair,
    this.livePrice,
    this.drawTool = DrawTool.cursor,
  });

  static const double _priceW = 66.0;
  static const double _timeH  = 26.0;
  static const Color  _bull   = Color(0xFF26A69A);
  static const Color  _bear   = Color(0xFFEF5350);
  static const Color  _grid   = Color(0xFF181828);
  static const Color  _axis   = Color(0xFF555575);

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final cW = size.width - _priceW;
    final cH = size.height - _timeH;

    // ── Coordinate helpers ────────────────────────────────
    final rightPx = rightPadCandles * candleWidth;
    final lastVis  = (candles.length - 1 - scrollCandles)
        .round().clamp(0, candles.length - 1);
    final nVis     = ((cW - rightPx) / candleWidth).ceil() + 2;
    final firstVis = (lastVis - nVis).clamp(0, candles.length - 1);
    if (firstVis > lastVis) return;

    final lo = rangeLo;
    final hi = rangeHi;
    if ((hi - lo).abs() < 1e-10) return;

    // x position for candle index i
    double cX(int i) =>
        cW - rightPx - (lastVis - i) * candleWidth - candleWidth / 2;

    // price → y
    double p2y(double p) => cH * (1 - (p - lo) / (hi - lo));

    // ── Background ────────────────────────────────────────
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF0A0A14));

    // ── Horizontal grid ───────────────────────────────────
    final gp = Paint()..color = _grid..strokeWidth = 0.5;
    for (int i = 0; i <= 6; i++) {
      canvas.drawLine(
          Offset(0, cH * i / 6), Offset(cW, cH * i / 6), gp);
    }

    // ── Vertical grid ─────────────────────────────────────
    if (lastVis > firstVis) {
      final total = lastVis - firstVis;
      final vStep = math.max(1, total ~/ (cW ~/ 80).clamp(1, 12));
      for (int i = firstVis; i <= lastVis; i += vStep) {
        final x = cX(i);
        if (x > 0 && x < cW) {
          canvas.drawLine(Offset(x, 0), Offset(x, cH), gp);
        }
      }
    }

    // ── Axis separator ────────────────────────────────────
    canvas.drawLine(Offset(cW, 0), Offset(cW, size.height),
        Paint()..color = const Color(0xFF1E1E35)..strokeWidth = 1);

    // ── User horizontal lines (behind candles) ────────────
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, cW, cH));
    for (final hl in horizLines) {
      final y = p2y(hl.price);
      if (y >= -1 && y <= cH + 1) {
        _dashH(canvas, y, cW, hl.color, dash: 8, gap: 5);
      }
    }
    canvas.restore();

    // ── User trend lines (behind candles) ─────────────────
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, cW, cH));
    for (final tl in trendLines) {
      final x1 = cX(tl.idx1);
      final y1 = p2y(tl.price1);
      final x2 = cX(tl.idx2);
      final y2 = p2y(tl.price2);
      _drawTrendLine(canvas, cW, cH, x1, y1, x2, y2, tl.color);
    }
    canvas.restore();

    // ── Candles ───────────────────────────────────────────
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, cW, cH));

    for (int i = firstVis; i <= lastVis; i++) {
      final c    = candles[i];
      final x    = cX(i);
      if (x < -candleWidth * 2 || x > cW + candleWidth) continue;

      final isBull = c.close >= c.open;
      final isLive = i == candles.length - 1;
      final col    = isLive
          ? (isBull ? const Color(0xFF00C8B4) : const Color(0xFFFF5252))
          : (isBull ? _bull : _bear);

      final wickW = math.max(candleWidth * 0.12, 1.0);
      final bodyW = math.max(candleWidth * 0.65, 1.0);

      // Wick
      canvas.drawLine(
        Offset(x, p2y(c.high)), Offset(x, p2y(c.low)),
        Paint()..color = col..strokeWidth = wickW,
      );

      // Body
      final bTop  = p2y(math.max(c.open, c.close));
      final bBot  = p2y(math.min(c.open, c.close));
      final bodyH = math.max(bBot - bTop, 1.0);

      canvas.drawRect(
          Rect.fromLTWH(x - bodyW / 2, bTop, bodyW, bodyH),
          Paint()..color = col);

      // Selected highlight
      if (i == selectedIdx) {
        canvas.drawRect(
          Rect.fromLTWH(x - bodyW / 2 - 1.5, bTop - 1.5,
              bodyW + 3, bodyH + 3),
          Paint()
            ..color      = Colors.white.withOpacity(0.25)
            ..style      = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }

      // Live candle glow
      if (isLive) {
        canvas.drawRect(
          Rect.fromLTWH(
              x - bodyW / 2 - 1, bTop - 1, bodyW + 2, bodyH + 2),
          Paint()
            ..color      = col.withOpacity(0.35)
            ..style      = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }
    canvas.restore();

    // ── Pending trend line preview ────────────────────────
    if (pendingTlIdx != null && pendingTlPrice != null) {
      final x1 = cX(pendingTlIdx!);
      final y1 = p2y(pendingTlPrice!);

      // First-point dot (always visible)
      canvas.drawCircle(Offset(x1, y1), 5,
          Paint()..color = Colors.cyan..style = PaintingStyle.fill);
      canvas.drawCircle(Offset(x1, y1), 5,
          Paint()
            ..color      = Colors.white.withOpacity(0.4)
            ..style      = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      // Rubber-band line to finger
      if (pendingTlScreen != null) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, cW, cH));
        canvas.drawLine(
          Offset(x1, y1), pendingTlScreen!,
          Paint()
            ..color      = Colors.cyan.withOpacity(0.6)
            ..strokeWidth = 1.5
            ..isAntiAlias = true,
        );
        canvas.restore();
      }
    }

    // ── Live price dashed line ────────────────────────────
    final dispPrice = livePrice ?? candles.last.close;
    final lpY = p2y(dispPrice);
    if (lpY >= 0 && lpY <= cH) {
      final isBull = candles.last.close >= candles.last.open;
      _dashH(canvas, lpY, cW,
          (isBull ? _bull : _bear).withOpacity(0.45), dash: 3, gap: 6);
      _drawPriceBox(canvas, cW, lpY, dispPrice, Colors.white,
          isBull ? const Color(0xFF1A3A38) : const Color(0xFF3A1A1A));
    }

    // ── Crosshair ─────────────────────────────────────────
    if (crosshair != null &&
        crosshair!.dx >= 0 && crosshair!.dx <= cW) {
      final xp = Paint()
        ..color      = Colors.white.withOpacity(0.2)
        ..strokeWidth = 0.8;
      canvas.drawLine(
          Offset(crosshair!.dx, 0), Offset(crosshair!.dx, cH), xp);
      if (crosshair!.dy >= 0 && crosshair!.dy <= cH) {
        canvas.drawLine(
            Offset(0, crosshair!.dy), Offset(cW, crosshair!.dy), xp);
        final chP = lo + (1 - crosshair!.dy / cH) * (hi - lo);
        _drawPriceBox(canvas, cW, crosshair!.dy, chP,
            Colors.white.withOpacity(0.9), const Color(0xFF222240));
      }
    }

    // ── Price axis ────────────────────────────────────────
    for (int i = 0; i <= 6; i++) {
      final y  = cH * i / 6;
      final pr = lo + (1 - i / 6) * (hi - lo);
      _pt(_fmtP(pr), _axis, 9.0, canvas, Offset(cW + 4, y - 5));
    }

    // ── Horizontal line price labels on axis ──────────────
    for (final hl in horizLines) {
      final y = p2y(hl.price);
      if (y < -10 || y > cH + 10) continue;
      _drawTagBox(canvas, cW, y.clamp(4.0, cH - 14.0),
          hl.price, hl.color);
    }

    // ── Live price box ────────────────────────────────────
    // (already drawn above with dashed line)

    // ── Time axis ─────────────────────────────────────────
    final totalVis = lastVis - firstVis + 1;
    final step     = math.max(1, totalVis ~/ 6);
    for (int i = firstVis; i <= lastVis; i += step) {
      final x = cX(i);
      if (x < 8 || x > cW - 8) continue;
      final tp = _mkTP(_fmtT(candles[i].time), _axis, 9.0);
      tp.paint(canvas, Offset(
          (x - tp.width / 2).clamp(0.0, cW - tp.width), cH + 5));
    }

    // ── Draw-mode cursor hint ─────────────────────────────
    if (drawTool != DrawTool.cursor) {
      final hint = drawTool == DrawTool.trendLine
          ? (pendingTlIdx == null ? 'Tap to place first point' : 'Tap to place second point')
          : 'Tap to place horizontal line';
      final tp = _mkTP(hint, Colors.white.withOpacity(0.35), 10.0);
      tp.paint(canvas, Offset(
          (cW - tp.width) / 2, cH - 22));
    }
  }

  // ── Extended trend line (infinite in both directions) ──
  void _drawTrendLine(Canvas canvas, double cW, double cH,
      double x1, double y1, double x2, double y2, Color color) {
    const far = 9999.0;
    final paint = Paint()
      ..color      = color
      ..strokeWidth = 1.5
      ..isAntiAlias = true;

    if ((x2 - x1).abs() < 0.5) {
      // Vertical
      canvas.drawLine(Offset(x1, -far), Offset(x1, far), paint);
    } else {
      final m = (y2 - y1) / (x2 - x1);
      final b = y1 - m * x1;
      canvas.drawLine(
        Offset(-far, m * -far + b),
        Offset(cW + far, m * (cW + far) + b),
        paint,
      );
    }

    // Draw endpoint dots
    for (final pt in [Offset(x1, y1), Offset(x2, y2)]) {
      if (pt.dx >= -5 && pt.dx <= cW + 5) {
        canvas.drawCircle(pt, 3.5,
            Paint()..color = color..style = PaintingStyle.fill);
        canvas.drawCircle(pt, 3.5,
            Paint()
              ..color      = Colors.white.withOpacity(0.3)
              ..style      = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────

  void _dashH(Canvas c, double y, double w, Color col,
      {double dash = 6, double gap = 4}) {
    final p = Paint()..color = col..strokeWidth = 0.9;
    double x = 0; bool draw = true;
    while (x < w) {
      final end = math.min(x + (draw ? dash : gap), w);
      if (draw) c.drawLine(Offset(x, y), Offset(end, y), p);
      x = end; draw = !draw;
    }
  }

  void _drawPriceBox(Canvas canvas, double cW, double y, double price,
      Color textCol, Color bgCol) {
    final tp   = _mkTP(_fmtP(price), textCol, 10.0, bold: true);
    final rect = Rect.fromLTWH(
        cW + 2, y - tp.height / 2 - 2, tp.width + 8, tp.height + 4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = bgCol);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color      = textCol.withOpacity(0.35)
          ..style      = PaintingStyle.stroke
          ..strokeWidth = 0.8);
    tp.paint(canvas, Offset(cW + 6, y - tp.height / 2));
  }

  void _drawTagBox(Canvas canvas, double cW, double y, double price, Color color) {
    final tp   = _mkTP(_fmtP(price), color, 9.0, bold: true);
    final rect = Rect.fromLTWH(
        cW + 2, y - tp.height / 2 - 2, tp.width + 8, tp.height + 4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = color.withOpacity(0.2));
    tp.paint(canvas, Offset(cW + 6, y - tp.height / 2));
  }

  void _pt(String text, Color color, double sz, Canvas canvas, Offset o) =>
      _mkTP(text, color, sz).paint(canvas, o);

  TextPainter _mkTP(String text, Color color, double sz,
      {bool bold = false}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize:   sz,
              color:      color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

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
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.candles.length    != candles.length    ||
      o.candleWidth       != candleWidth       ||
      o.scrollCandles     != scrollCandles     ||
      o.trendLines.length != trendLines.length ||
      o.horizLines.length != horizLines.length ||
      o.pendingTlIdx      != pendingTlIdx      ||
      o.pendingTlPrice    != pendingTlPrice    ||
      o.pendingTlScreen   != pendingTlScreen   ||
      o.rangeLo           != rangeLo           ||
      o.rangeHi           != rangeHi           ||
      o.selectedIdx       != selectedIdx       ||
      o.crosshair         != crosshair         ||
      o.livePrice         != livePrice         ||
      o.drawTool          != drawTool;
}
