// ─── screens/candle_pattern_alerts_screen.dart ───────────
// Candle pattern alert management.
// Each alert watches one symbol + timeframe and fires when
// a BE, MS, or ES candlestick pattern is detected on a
// newly closed candle.

import 'package:flutter/material.dart';
import '../config.dart';
import '../services/binance_service.dart';
import '../services/candle_pattern_service.dart';

// ══════════════════════════════════════════════════════════
// ─── MAIN SCREEN ─────────────────────────────────────────
// ══════════════════════════════════════════════════════════
class CandlePatternAlertsScreen extends StatefulWidget {
  const CandlePatternAlertsScreen({super.key});

  @override
  State<CandlePatternAlertsScreen> createState() =>
      _CandlePatternAlertsScreenState();
}

class _CandlePatternAlertsScreenState
    extends State<CandlePatternAlertsScreen> {
  List<CandlePatternAlert> _alerts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _alerts = List.from(Config.candlePatternAlerts));
  }

  Future<void> _save() async {
    await ConfigService.saveCandlePatternAlerts(_alerts);
  }

  Future<void> _openEdit(CandlePatternAlert? existing) async {
    final result = await showModalBottomSheet<CandlePatternAlert>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AlertEditSheet(existing: existing),
    );
    if (result != null && mounted) {
      setState(() {
        final idx = _alerts.indexWhere((a) => a.id == result.id);
        if (idx >= 0) _alerts[idx] = result;
        else _alerts.insert(0, result);
      });
      await _save();
    }
  }

  Future<void> _toggleActive(CandlePatternAlert alert) async {
    setState(() {
      final idx = _alerts.indexWhere((a) => a.id == alert.id);
      if (idx >= 0) {
        _alerts[idx] = alert.copyWith(isActive: !alert.isActive);
      }
    });
    await _save();
  }

  Future<void> _delete(CandlePatternAlert alert) async {
    final label = alert.label.isNotEmpty
        ? alert.label
        : '${alert.symbol} ${alert.pattern}';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Alert'),
        content: Text('Delete "$label"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      setState(() => _alerts.removeWhere((a) => a.id == alert.id));
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF12121E) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Candle Pattern Alerts'),
        centerTitle: false,
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        actions: [
          if (_alerts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _openEdit(null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.blueAccent),
              ),
            ),
        ],
      ),
      body: _alerts.isEmpty ? _buildEmpty() : _buildList(isDark),
      floatingActionButton: _alerts.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _openEdit(null),
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add_rounded),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.candlestick_chart_rounded,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('No candle pattern alerts yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Get notified when BE, MS, or ES patterns\nappear on any symbol and timeframe.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _openEdit(null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Pattern Alert'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool isDark) {
    final active = _alerts.where((a) => a.isActive).toList();
    final paused = _alerts.where((a) => !a.isActive).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (active.isNotEmpty) ...[
          _SectionLabel('Active (${active.length})'),
          ...active.map((a) => _AlertCard(
                alert:    a,
                isDark:   isDark,
                onEdit:   () => _openEdit(a),
                onToggle: () => _toggleActive(a),
                onDelete: () => _delete(a),
              )),
        ],
        if (paused.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionLabel('Paused (${paused.length})'),
          ...paused.map((a) => _AlertCard(
                alert:    a,
                isDark:   isDark,
                onEdit:   () => _openEdit(a),
                onToggle: () => _toggleActive(a),
                onDelete: () => _delete(a),
              )),
        ],
      ],
    );
  }
}

// ─── Section label ────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 0.8)),
    );
  }
}

// ─── Alert card ───────────────────────────────────────────
class _AlertCard extends StatelessWidget {
  final CandlePatternAlert alert;
  final bool               isDark;
  final VoidCallback       onEdit;
  final VoidCallback       onToggle;
  final VoidCallback       onDelete;

  const _AlertCard({
    required this.alert,
    required this.isDark,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  Color get _borderColor {
    if (!alert.isActive) return Colors.grey.shade500;
    final p = CandlePatternExt.fromString(alert.pattern);
    if (p == CandlePattern.ES) return Colors.redAccent.shade200;
    return Colors.green.shade400;
  }

  @override
  Widget build(BuildContext context) {
    final patternEnum = CandlePatternExt.fromString(alert.pattern);
    final cardBg      = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    // Bot name
    String botName = 'Unknown Bot';
    try {
      botName = Config.bots.firstWhere((b) => b.id == alert.botId).name;
    } catch (_) { botName = 'Bot deleted'; }

    final statusText  = alert.isActive ? 'Watching' : 'Paused';
    final statusColor = alert.isActive ? Colors.blueAccent : Colors.grey.shade500;

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: _borderColor, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              // ── Main info ───────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Label / Symbol
                    Text(
                      alert.label.isNotEmpty ? alert.label : alert.symbol,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: !alert.isActive ? Colors.grey.shade500 : null,
                      ),
                    ),
                    if (alert.label.isNotEmpty)
                      Text(alert.symbol,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade500)),

                    const SizedBox(height: 6),

                    // Pattern + timeframe
                    Row(children: [
                      Text(patternEnum.emoji,
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        '${patternEnum.label}  ·  ${alert.timeframe}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: !alert.isActive
                              ? Colors.grey.shade400
                              : (patternEnum.isBullish
                                  ? Colors.green.shade400
                                  : Colors.redAccent.shade200),
                        ),
                      ),
                    ]),

                    const SizedBox(height: 4),

                    // Bot name + status badge
                    Row(children: [
                      Icon(Icons.smart_toy_rounded,
                          size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(botName,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(statusText,
                            style: TextStyle(
                                fontSize: 10,
                                color: statusColor,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ],
                ),
              ),

              // ── Actions ─────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: alert.isActive,
                    onChanged: (_) => onToggle(),
                    activeColor: Colors.blueAccent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: Colors.redAccent.withOpacity(0.7),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ─── ADD / EDIT SHEET ────────────────────────────────────
// ══════════════════════════════════════════════════════════
class _AlertEditSheet extends StatefulWidget {
  final CandlePatternAlert? existing;
  const _AlertEditSheet({this.existing});

  @override
  State<_AlertEditSheet> createState() => _AlertEditSheetState();
}

class _AlertEditSheetState extends State<_AlertEditSheet> {
  final _formKey   = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _symbolCtrl;
  late String _selectedPattern;
  late String _selectedTimeframe;
  late String _selectedBotId;
  bool _validating  = false;
  bool _symbolValid = false;

  @override
  void initState() {
    super.initState();
    final e         = widget.existing;
    _labelCtrl      = TextEditingController(text: e?.label ?? '');
    _symbolCtrl     = TextEditingController(text: e?.symbol ?? '');
    _selectedPattern   = e?.pattern   ?? 'BE';
    _selectedTimeframe = e?.timeframe ?? '1h';
    _selectedBotId     = e?.botId     ?? _defaultBotId();
    _symbolValid       = e != null;
  }

  String _defaultBotId() {
    if (Config.bots.isEmpty) return '';
    try { return Config.bots.firstWhere((b) => b.isConfigured).id; }
    catch (_) { return Config.bots.first.id; }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _symbolCtrl.dispose();
    super.dispose();
  }

  Future<void> _validateSymbol(String value) async {
    final sym = value.trim().toUpperCase();
    if (sym.isEmpty) { setState(() => _symbolValid = false); return; }
    setState(() => _validating = true);
    final result = await BinanceService.validateSymbol(sym);
    if (mounted) {
      setState(() { _validating = false; _symbolValid = result.isValid; });
    }
  }

  CandlePatternAlert _build() {
    final e = widget.existing;
    return CandlePatternAlert(
      id:        e?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      symbol:    _symbolCtrl.text.trim().toUpperCase(),
      pattern:   _selectedPattern,
      timeframe: _selectedTimeframe,
      botId:     _selectedBotId,
      label:     _labelCtrl.text.trim(),
      isActive:  e?.isActive ?? true,
      createdAt: e?.createdAt,
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_symbolValid) {
      _snack('Validate the symbol first', isError: true);
      return;
    }
    if (Config.bots.isEmpty) {
      _snack('No Telegram bots configured yet.\nAdd a bot first.',
          isError: true);
      return;
    }
    // Ensure selected bot still exists
    if (!Config.bots.any((b) => b.id == _selectedBotId)) {
      _selectedBotId = Config.bots.first.id;
    }
    Navigator.pop(context, _build());
  }

  void _snack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          isError ? Colors.red.shade700 : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final isEdit     = widget.existing != null;
    final bots       = Config.bots;

    if (bots.isNotEmpty && !bots.any((b) => b.id == _selectedBotId)) {
      _selectedBotId = bots.first.id;
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     0.97,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: sheetColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Drag handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(children: [
                const Icon(Icons.candlestick_chart_rounded,
                    color: Colors.blueAccent, size: 22),
                const SizedBox(width: 10),
                Text(
                  isEdit
                      ? 'Edit Pattern Alert'
                      : 'New Pattern Alert',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 1),

            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Label (optional) ──────────────
                      const _Label('Label (optional)'),
                      _Field(
                        controller: _labelCtrl,
                        hint:  'e.g. BTC 4h bullish reversal',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),

                      // ── Symbol ─────────────────────────
                      const _Label('Symbol'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _Field(
                              controller:     _symbolCtrl,
                              hint:           'e.g. BTCUSDT',
                              isDark:         isDark,
                              capitalization: TextCapitalization.characters,
                              suffix: _symbolValid
                                  ? const Icon(Icons.check_circle_rounded,
                                      color: Colors.green, size: 20)
                                  : null,
                              onChanged: (_) {
                                if (_symbolValid) {
                                  setState(() => _symbolValid = false);
                                }
                              },
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Symbol is required';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _validating
                                  ? null
                                  : () => _validateSymbol(_symbolCtrl.text),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14),
                              ),
                              child: _validating
                                  ? const SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Text('Check',
                                      style: TextStyle(fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Pattern picker ─────────────────
                      const _Label('Pattern'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: _PatternButton(
                            pattern:  CandlePattern.BE,
                            selected: _selectedPattern == 'BE',
                            isDark:   isDark,
                            onTap: () =>
                                setState(() => _selectedPattern = 'BE'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PatternButton(
                            pattern:  CandlePattern.MS,
                            selected: _selectedPattern == 'MS',
                            isDark:   isDark,
                            onTap: () =>
                                setState(() => _selectedPattern = 'MS'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PatternButton(
                            pattern:  CandlePattern.ES,
                            selected: _selectedPattern == 'ES',
                            isDark:   isDark,
                            onTap: () =>
                                setState(() => _selectedPattern = 'ES'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),

                      // ── Timeframe picker ───────────────
                      const _Label('Timeframe'),
                      const SizedBox(height: 8),
                      _TimeframePicker(
                        selected:  _selectedTimeframe,
                        isDark:    isDark,
                        onChanged: (tf) =>
                            setState(() => _selectedTimeframe = tf),
                      ),
                      const SizedBox(height: 20),

                      // ── Bot selector ───────────────────
                      const _Label('Send Alert Via'),
                      const SizedBox(height: 8),
                      if (bots.isEmpty)
                        _NoBotWarning()
                      else
                        ...bots.map((bot) => _BotOption(
                              bot:      bot,
                              selected: bot.id == _selectedBotId,
                              isDark:   isDark,
                              onTap: () =>
                                  setState(() => _selectedBotId = bot.id),
                            )),

                      const SizedBox(height: 28),

                      // ── Save button ────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: bots.isEmpty ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            isEdit ? 'Save Changes' : 'Create Alert',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pattern toggle button ────────────────────────────────
class _PatternButton extends StatelessWidget {
  final CandlePattern pattern;
  final bool          selected;
  final bool          isDark;
  final VoidCallback  onTap;

  const _PatternButton({
    required this.pattern,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  Color get _accentColor {
    if (pattern == CandlePattern.ES) return Colors.redAccent;
    return Colors.green.shade400;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _accentColor.withOpacity(0.12)
              : (isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? _accentColor.withOpacity(0.6)
                : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(pattern.emoji,
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              pattern.shortLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected ? _accentColor : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              pattern.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Timeframe grid picker ────────────────────────────────
class _TimeframePicker extends StatelessWidget {
  final String           selected;
  final bool             isDark;
  final ValueChanged<String> onChanged;

  const _TimeframePicker({
    required this.selected,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kAllTimeframes.map((tf) {
        final isSelected = tf == selected;
        return GestureDetector(
          onTap: () => onChanged(tf),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.blueAccent.withOpacity(0.15)
                  : (isDark
                      ? const Color(0xFF1A1A2E)
                      : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? Colors.blueAccent.withOpacity(0.6)
                    : (isDark
                        ? Colors.grey.shade700
                        : Colors.grey.shade300),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              tf,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blueAccent : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── No-bot warning ───────────────────────────────────────
class _NoBotWarning extends StatelessWidget {
  const _NoBotWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.orange.shade600, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'No Telegram bots configured yet.\n'
              'Add a bot from the main screen first.',
              style: TextStyle(fontSize: 12.5, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bot selection tile ───────────────────────────────────
class _BotOption extends StatelessWidget {
  final TelegramBot  bot;
  final bool         selected;
  final bool         isDark;
  final VoidCallback onTap;

  const _BotOption({
    required this.bot,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? Colors.blueAccent.withOpacity(0.08)
              : (isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? Colors.blueAccent.withOpacity(0.5)
                : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          // Radio dot
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.blueAccent : Colors.grey.shade400,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: selected
                ? Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          // Bot info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bot.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5)),
                if (!bot.isConfigured)
                  Text('Not configured',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade400))
                else
                  Text('Chat: ${bot.chatId}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          if (!bot.isConfigured)
            Icon(Icons.warning_amber_rounded,
                size: 16, color: Colors.orange.shade400),
        ]),
      ),
    );
  }
}

// ─── Shared form widgets ──────────────────────────────────
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.blueAccent)),
      );
}

class _Field extends StatelessWidget {
  final TextEditingController        controller;
  final String                       hint;
  final bool                         isDark;
  final Widget?                      suffix;
  final TextCapitalization           capitalization;
  final String? Function(String?)?   validator;
  final ValueChanged<String>?        onChanged;

  const _Field({
    required this.controller,
    required this.hint,
    required this.isDark,
    this.suffix,
    this.capitalization = TextCapitalization.none,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:         controller,
      textCapitalization: capitalization,
      onChanged:          onChanged,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText:   hint,
        hintStyle:  TextStyle(color: Colors.grey.shade500, fontSize: 13),
        suffixIcon: suffix,
        filled:     true,
        fillColor:  isDark ? const Color(0xFF12121E) : Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: isDark
                    ? Colors.grey.shade700
                    : Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Colors.blueAccent, width: 1.8)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.redAccent)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Colors.redAccent, width: 1.8)),
      ),
      validator: validator,
    );
  }
}
