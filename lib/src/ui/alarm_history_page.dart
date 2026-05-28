import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alarm_config.dart';
import '../models/alarm_history.dart';
import '../services/device_client.dart';
import 'connection_status_badge.dart';
import 'pi_settings_widgets.dart';

class AlarmHistoryPage extends StatefulWidget {
  const AlarmHistoryPage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<AlarmHistoryPage> createState() => _AlarmHistoryPageState();
}

class _AlarmHistoryPageState extends State<AlarmHistoryPage> {
  AlarmHistoryList _history = const AlarmHistoryList.empty();
  bool    _loading = true;
  bool    _busy    = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Fetch history and tell the Pi the user has seen it (clears the badge).
      final h = await widget.client.getAlarmHistory();
      if (!mounted) return;
      setState(() { _history = h; _loading = false; });
      // Fire-and-forget: mark seen after we have the data so the badge clears
      // only when the page actually loaded successfully.
      widget.client.markAlarmHistorySeen().ignore();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('All trigger records will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.client.clearAlarmHistory();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Clear failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          showCloseIcon: true,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alarm History'),
        actions: [
          ConnectionStatusBadge(client: widget.client),
          if (!_loading && !_history.isEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_sweep_outlined),
              onPressed: _busy ? null : _clearAll,
            ),
          if (!_loading)
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : _load,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? PiErrorView(message: _error!, onRetry: _load)
              : _history.isEmpty
                  ? _buildEmpty(cs)
                  : _buildList(cs),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_outlined, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No trigger history yet',
              style: TextStyle(color: cs.outline, fontSize: 15)),
          const SizedBox(height: 8),
          Text('Trigger events will appear here.',
              style: TextStyle(color: cs.outlineVariant, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme cs) {
    final entries = _history.entries;
    return Column(
      children: [
        // Summary bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cs.surfaceContainerHighest,
          child: Text(
            '${_history.total} trigger${_history.total == 1 ? '' : 's'}'
            '${_history.hasUnseen ? '  ·  ${_history.unseen} new' : ''}'
            '  ·  max ${_history.max} (oldest overwritten)',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) => _HistoryTile(entry: entries[i]),
          ),
        ),
      ],
    );
  }
}

// ── History tile ──────────────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final AlarmHistoryEntry entry;

  static final _dateFmt = DateFormat('dd MMM yyyy  HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final unit = AlarmParameter.unit(entry.parameter);

    final tStr = _fmtValue(entry.threshold, unit);
    final vStr = entry.value != null ? _fmtValue(entry.value!, unit) : '—';
    final cLbl = AlarmCondition.label(entry.condition);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Alarm dot ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.error,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // ── Content ─────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${AlarmParameter.label(entry.parameter)}  ·  '
                    '$cLbl $tStr',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dateFmt.format(entry.triggeredAt.toLocal()),
                    style: TextStyle(fontSize: 11, color: cs.outlineVariant),
                  ),
                ],
              ),
            ),

            // ── Value at trigger ─────────────────────────────────────────────
            Text(
              vStr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtValue(double v, String unit) {
    final s = v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(2);
    return unit.isEmpty ? s : '$s $unit';
  }
}
