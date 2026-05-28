import 'dart:async';

import 'package:flutter/material.dart';

import '../models/alarm_config.dart';
import '../models/alarm_state.dart';
import '../services/device_client.dart';
import 'alarm_editor_page.dart';
import 'alarm_history_page.dart';
import 'connection_status_badge.dart';
import 'pi_settings_widgets.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  AlarmList _list = AlarmList.empty();
  bool _loading = true;
  bool _busy    = false;
  String? _error;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Poll alarm states every 3 s while page is open.
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollStates());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await widget.client.listAlarms();
      if (!mounted) return;
      setState(() { _list = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _pollStates() async {
    if (!mounted || _loading || _busy) return;
    try {
      final result = await widget.client.getAlarmStates();
      if (!mounted) return;
      setState(() {
        _list = _list.withStates(result.states, unseen: result.unseen);
      });
    } catch (_) {}
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _snack('$label failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAlarm() async {
    final result = await Navigator.push<AlarmConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => AlarmEditorPage(client: widget.client),
      ),
    );
    if (result == null || !mounted) return;
    await _run('Add alarm', () async {
      await widget.client.addAlarm(result);
      await _reload();
    });
  }

  Future<void> _editAlarm(AlarmConfig alarm) async {
    final result = await Navigator.push<AlarmConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => AlarmEditorPage(existing: alarm, client: widget.client),
      ),
    );
    if (result == null || !mounted) return;
    await _run('Update alarm', () async {
      await widget.client.updateAlarm(alarm.id, result.toJson());
      await _reload();
    });
  }

  Future<void> _deleteAlarm(AlarmConfig alarm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete alarm?'),
        content: Text('Remove "${alarm.label}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run('Delete alarm', () async {
      await widget.client.removeAlarm(alarm.id);
      await _reload();
    });
  }

  Future<void> _clearAlarm(String configId) async {
    await _run('Clear alarm', () async {
      await widget.client.clearAlarm(configId);
      await _pollStates();
    });
  }

  Future<void> _clearAll() async {
    await _run('Clear all alarms', () async {
      await widget.client.clearAllAlarms();
      await _pollStates();
    });
  }

  Future<void> _toggleEnabled(AlarmConfig alarm) async {
    await _run('Toggle alarm', () async {
      await widget.client.updateAlarm(alarm.id, {'enabled': !alarm.enabled});
      await _reload();
    });
  }

  Future<void> _reload() async {
    _list = await widget.client.listAlarms();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? cs.errorContainer : null,
      showCloseIcon: true,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasActive = _list.activeCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alarms'),
        actions: [
          ConnectionStatusBadge(client: widget.client),
          if (!_loading && hasActive)
            TextButton.icon(
              onPressed: _busy ? null : _clearAll,
              icon: const Icon(Icons.notifications_off_outlined, size: 18),
              label: const Text('Clear All'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          IconButton(
            tooltip: 'Trigger history',
            icon: Badge(
              isLabelVisible: _list.hasUnseenHistory,
              label: Text('${_list.unseenHistory}'),
              child: const Icon(Icons.history),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlarmHistoryPage(client: widget.client),
                ),
              );
              // Refresh unseen count when returning from history page
              if (mounted) _pollStates();
            },
          ),
          if (!_loading)
            IconButton(
              tooltip: 'Reload',
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: _busy ? null : _load,
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton(
              onPressed: _busy ? null : _addAlarm,
              tooltip: 'Add alarm',
              child: const Icon(Icons.add),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? PiErrorView(message: _error!, onRetry: _load)
              : _list.alarms.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    );
  }

  Widget _buildEmpty() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_outlined, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No alarms configured',
              style: TextStyle(color: cs.outline, fontSize: 15)),
          const SizedBox(height: 8),
          Text('Tap + to add your first alarm rule.',
              style: TextStyle(color: cs.outlineVariant, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _list.alarms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final alarm = _list.alarms[i];
        final state = _list.stateFor(alarm.id);
        return _AlarmTile(
          alarm: alarm,
          state: state,
          onEdit:   () => _editAlarm(alarm),
          onDelete: () => _deleteAlarm(alarm),
          onClear:  state?.isActive == true ? () => _clearAlarm(alarm.id) : null,
          onToggle: () => _toggleEnabled(alarm),
        );
      },
    );
  }
}

// ── Alarm tile ────────────────────────────────────────────────────────────────

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({
    required this.alarm,
    required this.state,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    this.onClear,
  });

  final AlarmConfig  alarm;
  final AlarmState?  state;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final s   = state;
    final active  = s?.isActive  == true;
    final pending = s?.isPending == true;

    Color dotColor;
    if (!alarm.enabled)       { dotColor = cs.outlineVariant; }
    else if (active)          { dotColor = cs.error; }
    else if (pending)         { dotColor = Colors.orange; }
    else                      { dotColor = const Color(0xFF1AAB5F); }

    final unit  = AlarmParameter.unit(alarm.parameter);
    final cLabel = AlarmCondition.label(alarm.condition);
    final tStr   = _fmtValue(alarm.threshold, unit);
    final curStr = s?.currentValue != null ? _fmtValue(s!.currentValue!, unit) : '—';

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              // ── Status dot ─────────────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: dotColor,
                  boxShadow: active ? [BoxShadow(color: dotColor.withValues(alpha: 0.5), blurRadius: 6)] : null,
                ),
              ),
              const SizedBox(width: 12),

              // ── Content ────────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alarm.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14,
                          color: alarm.enabled ? cs.onSurface : cs.outline,
                        )),
                    const SizedBox(height: 3),
                    Text(
                      '${AlarmParameter.label(alarm.parameter)}  ·  $cLabel $tStr',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                    if (alarm.triggerDelaySec > 0 || alarm.autoClearDelaySec > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _timerLine(alarm),
                          style: TextStyle(fontSize: 11, color: cs.outlineVariant),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Current value ──────────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(curStr,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: active ? cs.error : cs.onSurface,
                      )),
                  if (active)
                    GestureDetector(
                      onTap: onClear,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Clear',
                            style: TextStyle(fontSize: 11, color: cs.error)),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 8),

              // ── Actions ────────────────────────────────────────────────────
              PopupMenuButton<_TileAction>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (a) {
                  switch (a) {
                    case _TileAction.toggle: onToggle(); break;
                    case _TileAction.edit:   onEdit();   break;
                    case _TileAction.delete: onDelete(); break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _TileAction.toggle,
                    child: Text(alarm.enabled ? 'Disable' : 'Enable'),
                  ),
                  const PopupMenuItem(value: _TileAction.edit,   child: Text('Edit')),
                  const PopupMenuItem(value: _TileAction.delete, child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtValue(double v, String unit) {
    final s = v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
    return unit.isEmpty ? s : '$s $unit';
  }

  static String _timerLine(AlarmConfig a) {
    final parts = <String>[];
    if (a.triggerDelaySec > 0) { parts.add('delay ${a.triggerDelaySec}s'); }
    if (a.autoClearDelaySec > 0)           { parts.add('auto-clear ${a.autoClearDelaySec}s'); }
    else if (a.condition != AlarmCondition.setpoint) { parts.add('manual clear'); }
    return parts.join('  ·  ');
  }
}

enum _TileAction { toggle, edit, delete }
