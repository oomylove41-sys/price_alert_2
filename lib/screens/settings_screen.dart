// ─── screens/settings_screen.dart ────────────────────────
// Exports public settings page widgets used by MainShell.
// No Scaffold here — MainShell owns the Scaffold + bottom nav.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import '../services/binance_service.dart';
import '../services/telegram_service.dart';

// ══════════════════════════════════════════════════════════
// ─── PAGE 1: TELEGRAM BOTS ───────────────────────────────
// ══════════════════════════════════════════════════════════
class TelegramBotsPage extends StatefulWidget {
  final VoidCallback onSaved;
  const TelegramBotsPage({super.key, required this.onSaved});

  @override
  State<TelegramBotsPage> createState() => _TelegramBotsPageState();
}

class _TelegramBotsPageState extends State<TelegramBotsPage> {
  late List<TelegramBot> _bots;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bots = List.from(Config.bots);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ConfigService.saveBots(_bots);
    setState(() => _saving = false);
    widget.onSaved();
  }

  Future<void> _openEdit(TelegramBot bot) async {
    final updated = await showModalBottomSheet<TelegramBot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BotEditSheet(bot: bot),
    );
    if (updated != null && mounted) {
      setState(() {
        final idx = _bots.indexWhere((b) => b.id == updated.id);
        if (idx >= 0) {
          _bots[idx] = updated;
        } else {
          _bots.add(updated);
        }
      });
    }
  }

  void _addBot() {
    _openEdit(TelegramBot(
      id:         DateTime.now().millisecondsSinceEpoch.toString(),
      name:       'Bot ${_bots.length + 1}',
      token:      '',
      chatId:     '',
      alertOnHit: true,
      alertOnNew: false,
    ));
  }

  void _deleteBot(String id) {
    if (_bots.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('At least one bot is required'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Bot'),
        content: const Text('Are you sure you want to delete this bot?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _bots.removeWhere((b) => b.id == id));
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(
            icon: Icons.send_rounded,
            text:
                'Configure one or more Telegram bots. Each bot can receive '
                '"Hit" alerts (price touches a level) and/or "New Level" alerts '
                '(a fresh HH/LL pivot forms).',
          ),
          const SizedBox(height: 16),

          // Bot list
          ..._bots.asMap().entries.map((entry) => _BotCard(
                bot:      entry.value,
                index:    entry.key,
                onEdit:   () => _openEdit(entry.value),
                onDelete: () => _deleteBot(entry.value.id),
              )),

          const SizedBox(height: 12),

          // Add bot button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _addBot,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Another Bot'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blueAccent,
                side: const BorderSide(color: Colors.blueAccent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 20),
          _SaveButton(onPressed: _save, loading: _saving),
        ],
      ),
    );
  }
}

// ─── Bot card (summary) ───────────────────────────────────
class _BotCard extends StatefulWidget {
  final TelegramBot bot;
  final int         index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _BotCard({
    required this.bot,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_BotCard> createState() => _BotCardState();
}

class _BotCardState extends State<_BotCard> {
  bool _testing = false;

  Future<void> _test() async {
    setState(() => _testing = true);
    final error = await TelegramService.testConnection(widget.bot);
    setState(() => _testing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            error == null ? Icons.check_circle : Icons.error_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error == null
                ? '✅ Test message sent to ${widget.bot.name}!'
                : '❌ ${widget.bot.name}: $error'),
          ),
        ]),
        backgroundColor:
            error == null ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: Duration(seconds: error == null ? 3 : 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bot    = widget.bot;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bot.isConfigured
              ? Colors.blueAccent.withOpacity(0.3)
              : Colors.orange.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${widget.index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                      fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bot.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      bot.isConfigured
                          ? 'Configured ✓'
                          : '⚠ Not yet configured',
                      style: TextStyle(
                        fontSize: 11,
                        color: bot.isConfigured
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              // Edit
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 20),
                color: Colors.blueAccent,
                tooltip: 'Edit bot',
                onPressed: widget.onEdit,
              ),
              // Delete
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: Colors.redAccent,
                tooltip: 'Delete bot',
                onPressed: widget.onDelete,
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Alert type badges
          Row(
            children: [
              _AlertBadge(
                label: '🎯 Hit alerts',
                enabled: bot.alertOnHit,
                color: Colors.orange,
              ),
              const SizedBox(width: 8),
              _AlertBadge(
                label: '✨ New level',
                enabled: bot.alertOnNew,
                color: Colors.purple,
              ),
            ],
          ),

          // Token preview
          if (bot.token.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Token: ${_mask(bot.token)}',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? Colors.grey.shade400
                      : Colors.grey.shade600),
            ),
          ],

          const SizedBox(height: 10),

          // Test button
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton.icon(
              onPressed: (bot.isConfigured && !_testing) ? _test : null,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.blueAccent)),
                    )
                  : const Icon(Icons.send_rounded, size: 14),
              label: Text(_testing ? 'Sending...' : 'Test Connection',
                  style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blueAccent,
                side: const BorderSide(color: Colors.blueAccent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _mask(String s) {
    if (s.length <= 8) return '****';
    return '${s.substring(0, 4)}...${s.substring(s.length - 4)}';
  }
}

// ─── Alert type badge ─────────────────────────────────────
class _AlertBadge extends StatelessWidget {
  final String label;
  final bool   enabled;
  final Color  color;
  const _AlertBadge(
      {required this.label, required this.enabled, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: enabled ? color.withOpacity(0.15) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled ? color.withOpacity(0.5) : Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: enabled ? color : Colors.grey,
        ),
      ),
    );
  }
}

// ─── Bot edit sheet (modal) ───────────────────────────────
class _BotEditSheet extends StatefulWidget {
  final TelegramBot bot;
  const _BotEditSheet({required this.bot});

  @override
  State<_BotEditSheet> createState() => _BotEditSheetState();
}

class _BotEditSheetState extends State<_BotEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _chatCtrl;
  late bool _alertOnHit;
  late bool _alertOnNew;
  bool _obscureToken = true;
  bool _testing      = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl    = TextEditingController(text: widget.bot.name);
    _tokenCtrl   = TextEditingController(text: widget.bot.token);
    _chatCtrl    = TextEditingController(text: widget.bot.chatId);
    _alertOnHit  = widget.bot.alertOnHit;
    _alertOnNew  = widget.bot.alertOnNew;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tokenCtrl.dispose();
    _chatCtrl.dispose();
    super.dispose();
  }

  TelegramBot _buildBot() => widget.bot.copyWith(
    name:       _nameCtrl.text.trim(),
    token:      _tokenCtrl.text.trim(),
    chatId:     _chatCtrl.text.trim(),
    alertOnHit: _alertOnHit,
    alertOnNew: _alertOnNew,
  );

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _testing = true);
    final tempBot = _buildBot();
    final error   = await TelegramService.testConnection(tempBot);
    setState(() => _testing = false);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            error == null ? Icons.check_circle : Icons.error_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error == null
                ? '✅ Test message sent! Check Telegram.'
                : '❌ Failed: $error'),
          ),
        ]),
        backgroundColor:
            error == null ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: Duration(seconds: error == null ? 3 : 5),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_alertOnHit && !_alertOnNew) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enable at least one alert type'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
      return;
    }
    Navigator.pop(context, _buildBot());
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final sheetColor  = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize:     0.5,
      maxChildSize:     0.95,
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
              child: Row(
                children: [
                  const Icon(Icons.smart_toy_rounded,
                      color: Colors.blueAccent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.bot.token.isEmpty
                          ? 'Add New Bot'
                          : 'Edit Bot',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Form
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ─── Bot Name ──────────────────
                      _FieldLabel('Bot Name'),
                      _StyledField(
                        controller: _nameCtrl,
                        hint: 'e.g. Price Alert Bot',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),

                      const SizedBox(height: 16),

                      // ─── Token ─────────────────────
                      _FieldLabel('Bot Token'),
                      _StyledField(
                        controller: _tokenCtrl,
                        hint: 'e.g. 123456:ABC-DEF...',
                        obscure: _obscureToken,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureToken
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscureToken = !_obscureToken),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Bot token is required'
                            : null,
                        inputType: TextInputType.visiblePassword,
                      ),

                      const SizedBox(height: 16),

                      // ─── Chat ID ───────────────────
                      _FieldLabel('Chat ID'),
                      _StyledField(
                        controller: _chatCtrl,
                        hint: 'e.g. -100123456789',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Chat ID is required'
                            : null,
                        inputType: TextInputType.number,
                      ),

                      const SizedBox(height: 24),

                      // ─── Alert types ───────────────
                      const _FieldLabel('Alert Types'),
                      const SizedBox(height: 8),
                      _AlertTypeToggle(
                        title: '🎯 Price Hits HH/LL Level',
                        subtitle:
                            'Alert when current price touches an existing '
                            'Higher High or Lower Low level.',
                        value: _alertOnHit,
                        color: Colors.orange,
                        onChanged: (v) => setState(() => _alertOnHit = v),
                      ),
                      const SizedBox(height: 10),
                      _AlertTypeToggle(
                        title: '✨ New HH/LL Level Formed',
                        subtitle:
                            'Alert when a new Higher High or Lower Low pivot '
                            'is detected on the chart.',
                        value: _alertOnNew,
                        color: Colors.purple,
                        onChanged: (v) => setState(() => _alertOnNew = v),
                      ),

                      const SizedBox(height: 24),

                      // ─── Test button ───────────────
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : _testConnection,
                          icon: _testing
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                        Colors.blueAccent),
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                              _testing ? 'Sending test...' : 'Test Connection'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blueAccent,
                            side:
                                const BorderSide(color: Colors.blueAccent),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                      _SaveButton(onPressed: _save, loading: false),
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

// ─── Alert type toggle card ───────────────────────────────
class _AlertTypeToggle extends StatelessWidget {
  final String   title;
  final String   subtitle;
  final bool     value;
  final Color    color;
  final ValueChanged<bool> onChanged;
  const _AlertTypeToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: value
            ? color.withOpacity(0.08)
            : (isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value
              ? color.withOpacity(0.4)
              : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: value ? color : null)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: color,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ─── PAGE 2: TRADING PAIRS ───────────────────────────────
// ══════════════════════════════════════════════════════════
class TradingPairsSettingsPage extends StatefulWidget {
  final VoidCallback onSaved;
  const TradingPairsSettingsPage({super.key, required this.onSaved});

  @override
  State<TradingPairsSettingsPage> createState() =>
      _TradingPairsSettingsPageState();
}

class _TradingPairsSettingsPageState extends State<TradingPairsSettingsPage> {
  late List<String> _symbols;
  final _addCtrl   = TextEditingController();
  bool _saving     = false;
  bool _validating = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _symbols = List<String>.from(Config.symbols);
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPair() async {
    final val = _addCtrl.text.trim().toUpperCase();
    if (val.isEmpty) return;
    if (_symbols.contains(val)) {
      _showSnack('$val is already in the list', isError: true);
      return;
    }
    setState(() => _validating = true);
    final result = await BinanceService.validateSymbol(val);
    setState(() => _validating = false);
    if (!mounted) return;

    if (!result.isValid) {
      _showSnack('❌ "$val" not found on Binance: ${result.error}',
          isError: true, duration: 4);
      return;
    }
    setState(() {
      _symbols.add(val);
      _addCtrl.clear();
      _hasChanges = true;
    });
    _showSnack('✅ $val added', isError: false);
  }

  void _removePair(String symbol) {
    if (_symbols.length <= 1) {
      _showSnack('At least one trading pair is required', isError: true);
      return;
    }
    setState(() {
      _symbols.remove(symbol);
      _hasChanges = true;
    });
  }

  void _showSnack(String msg, {required bool isError, int duration = 2}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: Duration(seconds: duration),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ConfigService.saveSymbols(_symbols);
    setState(() {
      _saving     = false;
      _hasChanges = false;
    });
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(
            icon: Icons.currency_bitcoin,
            text:
                'Type a Binance symbol and tap + to validate & add. Tap ✕ to remove.',
          ),
          const SizedBox(height: 16),

          if (_hasChanges)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade400),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade600, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Save changes then restart the bot for new pairs to take effect.',
                      style:
                          TextStyle(fontSize: 12.5, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StyledField(
                  controller: _addCtrl,
                  hint: 'e.g. BNBUSDT',
                  inputType: TextInputType.text,
                  capitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _addPair(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _validating ? null : _addPair,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    elevation: 0,
                  ),
                  child: _validating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.add_rounded, size: 22),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          _FieldLabel('Active Pairs (${_symbols.length})'),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _symbols.map((s) {
              return Chip(
                label: Text(s,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removePair(s),
                backgroundColor:
                    isDark ? const Color(0xFF2A2A3E) : Colors.blue.shade50,
                side: BorderSide(
                  color: isDark
                      ? Colors.blueAccent.withOpacity(0.3)
                      : Colors.blue.shade200,
                ),
                deleteIconColor: Colors.redAccent,
              );
            }).toList(),
          ),

          const SizedBox(height: 28),
          _SaveButton(onPressed: _save, loading: _saving),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ─── PAGE 3: TIMEFRAMES ──────────────────────────────────
// ══════════════════════════════════════════════════════════
class TimeframesSettingsPage extends StatefulWidget {
  final VoidCallback onSaved;
  const TimeframesSettingsPage({super.key, required this.onSaved});

  @override
  State<TimeframesSettingsPage> createState() =>
      _TimeframesSettingsPageState();
}

class _TimeframesSettingsPageState extends State<TimeframesSettingsPage> {
  late List<String> _timeframes;
  bool _saving = false;

  static const _available = [
    '1m','3m','5m','15m','30m',
    '1h','2h','4h','6h','8h','12h',
    '1d','3d','1w','1M',
  ];

  @override
  void initState() {
    super.initState();
    _timeframes = List<String>.from(Config.timeframes);
  }

  void _toggle(String tf) {
    if (_timeframes.contains(tf)) {
      if (_timeframes.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('At least one timeframe is required'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
        return;
      }
      setState(() => _timeframes.remove(tf));
    } else {
      setState(() {
        _timeframes.add(tf);
        _timeframes.sort(
            (a, b) => _available.indexOf(a).compareTo(_available.indexOf(b)));
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ConfigService.saveTimeframes(_timeframes);
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(
            icon: Icons.access_time_rounded,
            text: 'Select Binance timeframes the bot monitors. Tap to toggle.',
          ),
          const SizedBox(height: 20),
          _FieldLabel('Selected: ${_timeframes.join(', ')}'),
          const SizedBox(height: 14),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _available.map((tf) {
              final selected = _timeframes.contains(tf);
              return GestureDetector(
                onTap: () => _toggle(tf),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.blueAccent
                        : (isDark
                            ? const Color(0xFF2A2A3E)
                            : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? Colors.blueAccent
                          : (isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300),
                    ),
                  ),
                  child: Text(
                    tf,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : (isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade700),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),
          _SaveButton(onPressed: _save, loading: _saving),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ─── PAGE 4: INDICATOR SETTINGS ──────────────────────────
// ══════════════════════════════════════════════════════════
class IndicatorSettingsPage extends StatefulWidget {
  final VoidCallback onSaved;
  const IndicatorSettingsPage({super.key, required this.onSaved});

  @override
  State<IndicatorSettingsPage> createState() => _IndicatorSettingsPageState();
}

class _IndicatorSettingsPageState extends State<IndicatorSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pivotCtrl;
  late final TextEditingController _limitCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pivotCtrl = TextEditingController(text: Config.pivotLen.toString());
    _limitCtrl = TextEditingController(text: Config.limit.toString());
  }

  @override
  void dispose() {
    _pivotCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ConfigService.saveIndicator(
      pivotLen: int.parse(_pivotCtrl.text.trim()),
      limit:    int.parse(_limitCtrl.text.trim()),
    );
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoBanner(
              icon: Icons.tune_rounded,
              text:
                  'Pivot Length controls how many candles each side define a pivot point.',
            ),
            const SizedBox(height: 20),

            _FieldLabel('Pivot Length'),
            _StyledField(
              controller: _pivotCtrl,
              hint: 'e.g. 5',
              inputType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              helperText: 'Recommended: 3 – 10',
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1) return 'Must be a positive number';
                if (n > 50) return 'Maximum value is 50';
                return null;
              },
            ),

            const SizedBox(height: 16),
            _FieldLabel('Candle Limit'),
            _StyledField(
              controller: _limitCtrl,
              hint: 'e.g. 1000',
              inputType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              helperText: 'Max 1000 (Binance API limit)',
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 50) return 'Minimum is 50 candles';
                if (n > 1000) return 'Maximum is 1000 (Binance limit)';
                return null;
              },
            ),

            const SizedBox(height: 28),
            _SaveButton(onPressed: _save, loading: _saving),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ─── PAGE 5: BOT SETTINGS ────────────────────────────────
// ══════════════════════════════════════════════════════════
class BotSettingsPage extends StatefulWidget {
  final VoidCallback onSaved;
  const BotSettingsPage({super.key, required this.onSaved});

  @override
  State<BotSettingsPage> createState() => _BotSettingsPageState();
}

class _BotSettingsPageState extends State<BotSettingsPage> {
  late int _checkEvery;
  bool _saving = false;

  static const _presets = [1, 3, 5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    _checkEvery = Config.checkEveryMinutes;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ConfigService.saveBotSettings(checkEveryMinutes: _checkEvery);
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(
            icon: Icons.timer_rounded,
            text: 'Set how often the bot checks Binance for new HH/LL levels.',
          ),
          const SizedBox(height: 20),

          _FieldLabel('Check Interval'),
          const SizedBox(height: 4),
          Text(
            'Every $_checkEvery minute${_checkEvery == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.blueAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.blueAccent,
              inactiveTrackColor:
                  isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              thumbColor: Colors.blueAccent,
              overlayColor: Colors.blueAccent.withOpacity(0.15),
              trackHeight: 4,
            ),
            child: Slider(
              value: _checkEvery.toDouble(),
              min: 1,
              max: 60,
              divisions: 59,
              onChanged: (v) => setState(() => _checkEvery = v.round()),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('1 min', style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text('60 min',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),

          const SizedBox(height: 20),
          _FieldLabel('Quick Presets'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((p) {
              final selected = _checkEvery == p;
              return GestureDetector(
                onTap: () => setState(() => _checkEvery = p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.blueAccent
                        : (isDark
                            ? const Color(0xFF2A2A3E)
                            : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? Colors.blueAccent
                          : Colors.grey.shade600,
                    ),
                  ),
                  child: Text(
                    '${p}m',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : (isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade700),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),
          _SaveButton(onPressed: _save, loading: _saving),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ─── SHARED PRIVATE WIDGETS ──────────────────────════════
// ══════════════════════════════════════════════════════════

class _PageScaffold extends StatelessWidget {
  final Widget child;
  const _PageScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: child,
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blueAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.blueAccent,
        ),
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final TextInputType? inputType;
  final List<TextInputFormatter>? inputFormatters;
  final String? helperText;
  final TextCapitalization capitalization;
  final void Function(String)? onSubmitted;

  const _StyledField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.suffixIcon,
    this.validator,
    this.inputType,
    this.inputFormatters,
    this.helperText,
    this.capitalization = TextCapitalization.none,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: inputType,
      inputFormatters: inputFormatters,
      textCapitalization: capitalization,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        helperText: helperText,
        helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300)),
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

class _SaveButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool loading;
  const _SaveButton({required this.onPressed, required this.loading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Text('Save Changes',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
