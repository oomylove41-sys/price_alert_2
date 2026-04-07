// ─── screens/chart_screen.dart ──────────────────────────
// Interactive candlestick chart
//   • Live price auto-refresh every 15 s
//   • 9 months of historical data with automatic gap-fill
//   • Multi-pair switcher with search
//   • Pinch-zoom · pan · crosshair · live price line
//   • OHLCV info bar · time axis · price axis

import 'dart:async';
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
  PivotResult? _pivots;
  DateTime?    _lastUpdated;

  // ── Live-price timer ──────────────────────────────────
  Timer?  _liveTimer;
  double? _livePrice;

  // ── Chart viewport ────────────────────────────────────
  // _rightPad: how many candle-widths of empty space to keep
  // on the right so the latest candle is NOT flush to the axis.
  static const double _rightPadCandles = 3.0;

  double _candleWidth   = 8.0;
  double _scrollCandles = 0.0;

  // ── Gesture tracking ──────────────────────────────────
  double _gStartCW     = 8.0;
  double _gStartScroll = 0.0;
  Offset _gStartFocal  = Offset.zero;

  // ── Crosshair ─────────────────────────────────────────
  Offset? _crosshair;
  int?    _selectedIdx;

  final TextEditingController _searchCtrl = TextEditingController();

  static const List<String> _timeframes = [
    '5m', '15m', '30m', '1h', '4h', '1d', '1w',
  ];

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

  /// Full history fetch — called on symbol / timeframe change.
  /// BinanceService always does a gap-fill at the end, so the
  /// array will be continuous right up to the current candle.
  Future<void> _fetchHistory() async {
    setState(() {
      _loading     = true;
      _error       = null;
      _candles     = [];
      _selectedIdx = null;
      _crosshair   = null;
      _livePrice   = null;
    });
    try {
      final candles = await BinanceService.fetchCandlesForChart(
          _symbol, _timeframe, months: 9);
      final piv = candles.length >= Config.pivotLen * 2 + 1
          ? PivotService.getHHLL(candles)
          : null;
      if (!mounted) return;
      setState(() {
        _candles       = candles;
        _pivots        = piv;
        _loading       = false;
        // Start view at the right edge (scrollCandles = 0)
        _scrollCandles = 0;
        _lastUpdated   = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Silent live tick every 15 s.
  /// Fetches all candles from the last known candle onward,
  /// which fills any gap that might have opened since the
  /// historical fetch completed.
  Future<void> _liveRefresh() async {
    if (_loading || _candles.isEmpty) return;
    setState(() => _refreshing = true);
    try {
      // Fetch ticker price (fast)
      final price = await BinanceService.getCurrentPrice(_symbol);

      // Fetch all candles from the last one we have to now
      // (this fills gaps AND updates the in-progress candle)
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
            // Update existing candle (the live in-progress one)
            _candles[idx] = fresh;
          } else if (fresh.time.isAfter(_candles.last.time)) {
            // Append new candle (gap-fill or new bar opened)
            _candles.add(fresh);
          }
        }

        // Recompute pivots on the updated dataset
        if (_candles.length >= Config.pivotLen * 2 + 1) {
          _pivots = PivotService.getHHLL(_candles);
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
    _liveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _liveRefresh();
    });
  }

  // ══════════════════════════════════════════════════════
  // GESTURES
  // ══════════════════════════════════════════════════════

  void _onScaleStart(ScaleStartDetails d) {
    _gStartCW     = _candleWidth;
    _gStartScroll = _scrollCandles;
    _gStartFocal  = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _candleWidth =
          (_gStartCW * d.scale).clamp(2.0, 40.0);

      // Max scroll: can't go further left than the first candle,
      // but allow negative scroll (shows empty space on left).
      final maxScroll = (_candles.length - 5).toDouble()
          .clamp(0.0, double.infinity);
      final dx = d.localFocalPoint.dx - _gStartFocal.dx;
      _scrollCandles =
          (_gStartScroll - dx / _candleWidth).clamp(0.0, maxScroll);

      if (d.pointerCount == 1) {
        _crosshair = d.localFocalPoint;
      } else {
        _crosshair   = null;
        _selectedIdx = null;
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    setState(() { _crosshair = null; _selectedIdx = null; });
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
            setState(() => _symbol = sym);
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
      // ── Pair selector ─────────────────────────────────
      title: GestureDetector(
        onTap: _openPairSelector,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_symbol,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(width: 3),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Color(0xFF888899)),
              const SizedBox(width: 10),
              if (displayPrice != null)
                Text(_fmtP(displayPrice),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
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
        // Live indicator dot
        Padding(
          padding: const EdgeInsets.only(right: 4, top: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: _refreshing
                      ? Colors.orange
                      : const Color(0xFF26A69A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 1),
              Text('LIVE',
                  style: TextStyle(
                      fontSize: 7,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5)),
            ],
          ),
        ),
        // ── Refresh button only — HH/LL toggle REMOVED ─
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
              margin:  const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(
                color: sel
                    ? Colors.blueAccent.withOpacity(0.9)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: sel
                    ? null
                    : Border.all(color: const Color(0xFF2A2A40)),
              ),
              child: Text(tf,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          sel ? FontWeight.bold : FontWeight.normal,
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
              style: const TextStyle(
                  fontSize: 9, color: Color(0xFF444466)),
            ),
          ),
      ]),
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
                style: TextStyle(
                    color: Color(0xFF333355), fontSize: 11)),
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
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _selectedIdx =
            _crosshair != null ? _resolveIdx(_crosshair!, size) : null;
        return CustomPaint(
          painter: _ChartPainter(
            candles:          _candles,
            candleWidth:      _candleWidth,
            scrollCandles:    _scrollCandles,
            rightPadCandles:  _rightPadCandles,
            selectedIdx:      _selectedIdx,
            crosshair:        _crosshair,
            livePrice:        _livePrice,
          ),
          size: size,
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
              style: const TextStyle(
                  fontSize: 9, color: Color(0xFF555577))),
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF26A69A).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: const Color(0xFF26A69A).withOpacity(0.4)),
              ),
              child: const Text('LIVE',
                  style: TextStyle(
                      fontSize: 8,
                      color: Color(0xFF26A69A),
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
              style: const TextStyle(
                  fontSize: 9, color: Color(0xFF555577))),
          TextSpan(text: _fmtP(value),
              style: TextStyle(
                  fontSize: 9.5, color: color,
                  fontWeight: FontWeight.w600)),
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
              style: const TextStyle(
                  fontSize: 9, color: Color(0xFF555577))),
          TextSpan(text: _fmtVol(value),
              style: const TextStyle(
                  fontSize: 9.5, color: Color(0xFF888899),
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────

  /// Convert screen x → candle index, accounting for right padding.
  int? _resolveIdx(Offset pos, Size size) {
    const pw = 66.0;
    final cW = size.width - pw;
    if (pos.dx < 0 || pos.dx > cW) return null;

    // x of last candle (same formula as painter, with rightPad)
    final rightPx = _rightPadCandles * _candleWidth;
    final lastIdx =
        (_candles.length - 1 - _scrollCandles).round()
            .clamp(0, _candles.length - 1);
    final fromRight = (cW - rightPx - pos.dx) / _candleWidth;
    return (lastIdx - fromRight).round()
        .clamp(0, _candles.length - 1);
  }

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
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(18)),
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
            // header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Text('Select Pair',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.grey, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            // search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: widget.searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[A-Za-z0-9]')),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFF2A2A40))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFF2A2A40))),
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
            // list
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
                              style: TextStyle(
                                  color: Color(0xFF555577))),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              final sym =
                                  _query.trim().toUpperCase();
                              if (sym.isNotEmpty) {
                                widget.onSelect(sym);
                              }
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
                                  color: Colors.blueAccent
                                      .withOpacity(0.12),
                                  borderRadius:
                                      BorderRadius.circular(4),
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
  final List<Candle> candles;
  final double       candleWidth;
  final double       scrollCandles;
  final double       rightPadCandles; // empty slots right of last candle
  final int?         selectedIdx;
  final Offset?      crosshair;
  final double?      livePrice;

  const _ChartPainter({
    required this.candles,
    required this.candleWidth,
    required this.scrollCandles,
    required this.rightPadCandles,
    this.selectedIdx,
    this.crosshair,
    this.livePrice,
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

    // ── Right padding: shift last candle left by N slots ──
    // This ensures the live candle is NOT flush against the axis.
    final rightPx = rightPadCandles * candleWidth;

    // ── Visible candle range ──────────────────────────────
    // lastVis = the candle drawn at the rightmost candle slot
    final lastVis = (candles.length - 1 - scrollCandles)
        .round()
        .clamp(0, candles.length - 1);

    // How many candles fit in the chart width (including right pad)
    final nVis     = ((cW - rightPx) / candleWidth).ceil() + 2;
    final firstVis = (lastVis - nVis).clamp(0, candles.length - 1);

    if (firstVis > lastVis) return;
    final vis = candles.sublist(firstVis, lastVis + 1);
    if (vis.isEmpty) return;

    // ── Candle x position ─────────────────────────────────
    // x(i) = right edge of chart area - right pad
    //        - (lastVis - i) * candleWidth - halfSlot
    double cX(int i) =>
        cW - rightPx - (lastVis - i) * candleWidth - candleWidth / 2;

    // ── Price range ───────────────────────────────────────
    var lo = vis.map((c) => c.low).reduce(math.min);
    var hi = vis.map((c) => c.high).reduce(math.max);
    if (livePrice != null) {
      hi = math.max(hi, livePrice!);
      lo = math.min(lo, livePrice!);
    }
    final range = hi - lo;
    if (range == 0) return;
    lo -= range * 0.07;
    hi += range * 0.07;

    double p2y(double p) => cH * (1 - (p - lo) / (hi - lo));

    // ── Background ────────────────────────────────────────
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF0A0A14));

    // ── Horizontal grid lines ─────────────────────────────
    final gp = Paint()..color = _grid..strokeWidth = 0.5;
    for (int i = 0; i <= 6; i++) {
      canvas.drawLine(
          Offset(0, cH * i / 6), Offset(cW, cH * i / 6), gp);
    }

    // ── Vertical grid lines ───────────────────────────────
    if (lastVis > firstVis) {
      final totalVis = lastVis - firstVis;
      final vStep    = math.max(1, totalVis ~/ (cW ~/ 80).clamp(1, 12));
      for (int i = firstVis; i <= lastVis; i += vStep) {
        final x = cX(i);
        if (x > 0 && x < cW) {
          canvas.drawLine(Offset(x, 0), Offset(x, cH), gp);
        }
      }
    }

    // ── Price axis separator ──────────────────────────────
    canvas.drawLine(Offset(cW, 0), Offset(cW, size.height),
        Paint()..color = const Color(0xFF1E1E35)..strokeWidth = 1);

    // ── Candles ───────────────────────────────────────────
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, cW, cH));

    for (int i = firstVis; i <= lastVis; i++) {
      final c    = candles[i];
      final x    = cX(i);
      if (x < -candleWidth * 2 || x > cW + candleWidth) continue;

      final isBull = c.close >= c.open;
      final isLive = i == candles.length - 1;

      // Live candle slightly brighter
      final col = isLive
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

      // Crosshair-selected highlight
      if (i == selectedIdx) {
        canvas.drawRect(
          Rect.fromLTWH(
              x - bodyW / 2 - 1.5, bTop - 1.5, bodyW + 3, bodyH + 3),
          Paint()
            ..color      = Colors.white.withOpacity(0.25)
            ..style      = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }

      // Soft glow ring on live candle
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

    // ── Live price dashed line ────────────────────────────
    final dispPrice = livePrice ?? candles.last.close;
    final lpY = p2y(dispPrice);
    if (lpY >= 0 && lpY <= cH) {
      final isBull = candles.last.close >= candles.last.open;
      _dashH(canvas, lpY, cW,
          (isBull ? _bull : _bear).withOpacity(0.45),
          dash: 3, gap: 6);
      _drawPriceBox(
        canvas, cW, lpY, dispPrice,
        Colors.white,
        isBull ? const Color(0xFF1A3A38) : const Color(0xFF3A1A1A),
      );
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

    // ── Price axis labels ─────────────────────────────────
    for (int i = 0; i <= 6; i++) {
      final y  = cH * i / 6;
      final pr = lo + (1 - i / 6) * (hi - lo);
      _pt(_fmtP(pr), _axis, 9.0, canvas, Offset(cW + 4, y - 5));
    }

    // ── Time axis labels ──────────────────────────────────
    final totalVis = lastVis - firstVis + 1;
    final step     = math.max(1, totalVis ~/ 6);
    for (int i = firstVis; i <= lastVis; i += step) {
      final x = cX(i);
      if (x < 8 || x > cW - 8) continue;
      final tp = _mkTP(_fmtT(candles[i].time), _axis, 9.0);
      tp.paint(canvas, Offset(
          (x - tp.width / 2).clamp(0.0, cW - tp.width), cH + 5));
    }
  }

  // ── Drawing helpers ───────────────────────────────────

  void _dashH(Canvas c, double y, double w, Color col,
      {double dash = 6, double gap = 4}) {
    final p    = Paint()..color = col..strokeWidth = 0.9;
    double x   = 0;
    bool   drw = true;
    while (x < w) {
      final end = math.min(x + (drw ? dash : gap), w);
      if (drw) c.drawLine(Offset(x, y), Offset(end, y), p);
      x = end; drw = !drw;
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

  void _pt(String t, Color c, double sz, Canvas canvas, Offset o) =>
      _mkTP(t, c, sz).paint(canvas, o);

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
      o.candles          != candles          ||
      o.candleWidth      != candleWidth      ||
      o.scrollCandles    != scrollCandles    ||
      o.rightPadCandles  != rightPadCandles  ||
      o.selectedIdx      != selectedIdx      ||
      o.crosshair        != crosshair        ||
      o.livePrice        != livePrice;
}
