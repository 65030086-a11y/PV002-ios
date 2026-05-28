import 'package:flutter/material.dart';

import '../models/energy_log.dart';
import '../services/device_client.dart';

/// Energy history panel — reads kWh logs from the Pi's SPI flash and
/// shows them as a simple table.
///
/// Designed to be rendered **inside** the HomePage Scaffold (no Scaffold
/// of its own — that would stack a second AppBar/badge on top of
/// HomePage's).  Three tabs: Hour / Day / Month; each fetches
/// `:log_kwh_*` lazily on first view and caches the result.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  final Map<_Range, EnergyLog> _cache    = {};
  final Map<_Range, bool>      _loading  = {};
  final Map<_Range, String?>   _errors   = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _Range.values.length, vsync: this);
    _tab.addListener(_onTabChanged);
    _load(_Range.hour);
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    final range = _Range.values[_tab.index];
    if (!_cache.containsKey(range)) _load(range);
  }

  Future<void> _load(_Range range, {bool force = false}) async {
    if (!force && (_loading[range] ?? false)) return;
    setState(() {
      _loading[range] = true;
      _errors[range]  = null;
    });

    EnergyLog? result;
    String? error;
    try {
      result = await switch (range) {
        _Range.hour  => widget.client.getKwhHourLog(),
        _Range.day   => widget.client.getKwhDayLog(),
        _Range.month => widget.client.getKwhMonthLog(),
      };
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _loading[range] = false;
      if (result != null) {
        _cache[range] = result;
        if (result.error != null) _errors[range] = result.error;
      } else {
        _errors[range] = error;
      }
    });
  }

  Future<void> _refreshCurrent() =>
      _load(_Range.values[_tab.index], force: true);

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final busy = _loading[_Range.values[_tab.index]] ?? false;
    return Column(
      children: [
        // ── Tab bar + refresh (no AppBar — parent provides one) ──────────
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tab,
                  tabs: const [
                    Tab(text: 'Hour'),
                    Tab(text: 'Day'),
                    Tab(text: 'Month'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reload',
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: busy ? null : _refreshCurrent,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: _Range.values.map(_buildPanel).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(_Range range) {
    final log     = _cache[range];
    final loading = _loading[range] ?? false;
    final error   = _errors[range];

    if (log == null && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (log == null) {
      return _ErrorView(
        message: error ?? 'No data',
        onRetry: () => _load(range, force: true),
      );
    }
    if (log.isEmpty) {
      return _EmptyView(error: error);
    }
    return _TableView(log: log, range: range);
  }
}

// ── Range enum ────────────────────────────────────────────────────────────────

enum _Range { hour, day, month }

extension on _Range {
  String get label => switch (this) {
        _Range.hour  => 'Hourly',
        _Range.day   => 'Daily',
        _Range.month => 'Monthly',
      };

  String get timeHeader => switch (this) {
        _Range.hour  => 'Hour',
        _Range.day   => 'Day',
        _Range.month => 'Month',
      };
}

// ── Table view ────────────────────────────────────────────────────────────────

class _TableView extends StatelessWidget {
  const _TableView({required this.log, required this.range});

  final EnergyLog log;
  final _Range    range;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Newest first for readability.
    final rows = log.entries.reversed.toList();

    return Column(
      children: [
        // ── Summary card ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bolt, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${range.label} consumption',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${log.totalKwh.toStringAsFixed(2)} kWh',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${log.entries.length} rows',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Table header ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(
              top:    BorderSide(color: cs.outlineVariant),
              bottom: BorderSide(color: cs.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  range.timeHeader,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.outline,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'kWh',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.outline,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Rows ────────────────────────────────────────────────────────
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: cs.outlineVariant),
            itemBuilder: (context, i) {
              final isLatest = (i == 0);
              return _TableRow(
                entry:    rows[i],
                range:    range,
                isLatest: isLatest,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Single row ────────────────────────────────────────────────────────────────

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.entry,
    required this.range,
    required this.isLatest,
  });

  final EnergyEntry entry;
  final _Range      range;
  final bool        isLatest;

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final live = const Color(0xFF1AAB5F);
    final kwhColor   = isLatest ? live : cs.primary;
    final accent     = isLatest ? live : cs.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  isLatest ? Icons.fiber_manual_record : Icons.access_time,
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Text(
                  _formatTime(entry, range),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              entry.kwh.toStringAsFixed(3),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kwhColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(EnergyEntry e, _Range range) {
    final dt = e.dateTime;
    String p(int n) => n.toString().padLeft(2, '0');
    return switch (range) {
      _Range.hour  =>
        '${dt.year}-${p(dt.month)}-${p(dt.day)}  ${p(dt.hour)}:00',
      _Range.day   => '${dt.year}-${p(dt.month)}-${p(dt.day)}',
      _Range.month => '${dt.year}-${p(dt.month)}',
    };
  }
}

// ── Empty / error views ───────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_chart_outlined, size: 56, color: cs.outlineVariant),
          const SizedBox(height: 14),
          Text(
            error == 'no_flash' ? 'No flash storage on device' : 'No data yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            error == 'no_flash'
                ? 'Energy history requires SPI flash hardware'
                : 'Wait for the next period boundary',
            style: TextStyle(color: cs.outline, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String       message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: cs.error),
            const SizedBox(height: 14),
            const Text(
              'Failed to load history',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
