import 'dart:async';

import 'package:flutter/material.dart';

import '../models/meter_snapshot.dart';
import '../services/device_client.dart';

const _kPollInterval = Duration(seconds: 1);

class MeterDataPage extends StatefulWidget {
  const MeterDataPage({
    super.key,
    required this.client,
    this.isActive = true,
  });

  final DeviceClient client;

  /// Set to false when this tab is not the selected tab in an [IndexedStack].
  /// The poll loop pauses automatically so no commands are sent to the Pi
  /// while the page is offscreen.
  final bool isActive;

  @override
  State<MeterDataPage> createState() => _MeterDataPageState();
}

class _MeterDataPageState extends State<MeterDataPage> {
  MeterSnapshot? _snapshot;
  bool _fetching = false;
  bool _alive = true;
  DateTime? _lastUpdated;
  String? _error;

  // ── Visibility guard ───────────────────────────────────────────────────────
  // Returns true only when:
  //   • this tab is the active IndexedStack child (widget.isActive), AND
  //   • no other route has been pushed on top of ours
  //     (ModalRoute.of(context).isCurrent).
  bool get _shouldPoll {
    if (!mounted || !widget.isActive) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  @override
  void initState() {
    super.initState();
    _poll();
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  Future<void> _poll() async {
    while (_alive) {
      if (_shouldPoll && !_fetching) await _fetch();
      await Future.delayed(_kPollInterval);
    }
  }

  Future<void> _fetch() async {
    _fetching = true;
    try {
      final snap = await widget.client.getMeterSnapshot();
      if (mounted) {
        setState(() {
          _snapshot = snap;
          _lastUpdated = DateTime.now();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final snap = _snapshot;

    return RefreshIndicator(
      onRefresh: _fetch,
      child: CustomScrollView(
        slivers: [
          // ── Status bar ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _LiveChip(hasData: snap?.isFoundData ?? false, error: _error),
                  const Spacer(),
                  if (_lastUpdated != null)
                    Text(
                      'Updated ${_timeAgo(_lastUpdated!)}',
                      style: TextStyle(color: cs.outline, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),

          if (_error != null && snap == null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.signal_wifi_connected_no_internet_4_outlined,
                          size: 56, color: cs.outlineVariant),
                      const SizedBox(height: 16),
                      Text('Cannot read meter data',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(_error!,
                          style: TextStyle(color: cs.outline, fontSize: 12),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            )
          else if (snap == null)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // ── Summary card ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _SummaryCard(total: snap.total),
              ),
            ),

            // ── Per-phase card ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _PhaseCard(lines: snap.lines),
              ),
            ),

            // ── Energy card ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: _EnergyCard(
                  total: snap.total,
                  startTime: snap.startClearWhtTime,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final secs = DateTime.now().difference(t).inSeconds;
    if (secs < 2) return 'just now';
    if (secs < 60) return '${secs}s ago';
    return '${(secs / 60).floor()}m ago';
  }
}

// ── Live chip ─────────────────────────────────────────────────────────────────

class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.hasData, this.error});

  final bool hasData;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = hasData && error == null;
    final color = ok
        ? const Color(0xFF1AAB5F)
        : error != null
            ? cs.error
            : cs.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: ok
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.5), blurRadius: 6)
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          ok
              ? 'Live'
              : error != null
                  ? 'Error'
                  : 'Waiting',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.total});

  final TotalData total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(context, Icons.bolt, 'Summary'),
            const SizedBox(height: 12),

            // Big power values
            Row(
              children: [
                _BigValue(
                  label: 'Active Power',
                  value: total.activePowerKw,
                  unit: 'kW',
                  color: cs.primary,
                ),
                _BigValue(
                  label: 'Reactive',
                  value: total.reactivePowerKvar,
                  unit: 'kVAR',
                ),
                _BigValue(
                  label: 'Apparent',
                  value: total.apparentPowerKva,
                  unit: 'kVA',
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Secondary row
            Row(
              children: [
                _InlineValue(
                    label: 'PF', value: total.powerFactor.toStringAsFixed(3)),
                _InlineValue(
                    label: 'Hz', value: total.frequency.toStringAsFixed(1)),
                _InlineValue(
                    label: 'Temp',
                    value: '${total.temperature.toStringAsFixed(1)} °C'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Per-phase card ────────────────────────────────────────────────────────────

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({required this.lines});

  final List<LineData> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(context, Icons.stacked_bar_chart, 'Per Phase'),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
                3: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                _phaseHeader(context),
                _phaseRow(context, 'Voltage',
                    lines.map((l) => _fmt(l.voltage, 1, 'V')).toList()),
                _phaseRow(context, 'Current',
                    lines.map((l) => _fmt(l.current, 2, 'A')).toList()),
                _phaseRow(context, 'kW',
                    lines.map((l) => _fmt(l.activePowerKw, 3, '')).toList()),
                _phaseRow(
                    context,
                    'kVAR',
                    lines
                        .map((l) => _fmt(l.reactivePowerKvar, 3, ''))
                        .toList()),
                _phaseRow(context, 'kVA',
                    lines.map((l) => _fmt(l.apparentPowerKva, 3, '')).toList()),
                _phaseRow(
                    context,
                    'PF',
                    lines
                        .map((l) => l.powerFactor.toStringAsFixed(3))
                        .toList()),
                _phaseRow(
                    context,
                    'THD(I)',
                    lines
                        .map((l) => '${l.currentTHD.toStringAsFixed(1)}%')
                        .toList()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _phaseHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    cell(String t, {bool label = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            t,
            textAlign: label ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
        );
    return TableRow(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      children: [cell('', label: true), cell('L1'), cell('L2'), cell('L3')],
    );
  }

  TableRow _phaseRow(BuildContext context, String label, List<String> vals) {
    final cs = Theme.of(context).colorScheme;
    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: cs.outline,
                  fontWeight: FontWeight.w500)),
        ),
        for (final v in vals)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Text(v,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
      ],
    );
  }

  String _fmt(double v, int dp, String unit) =>
      '${v.toStringAsFixed(dp)}${unit.isEmpty ? '' : ' $unit'}';
}

// ── Energy card ───────────────────────────────────────────────────────────────

class _EnergyCard extends StatelessWidget {
  const _EnergyCard({required this.total, required this.startTime});

  final TotalData total;
  final int startTime;

  @override
  Widget build(BuildContext context) {
    final elecRate = 4.0; // TODO: read from config
    final cef = 0.399;
    final bill = total.kwhImport * elecRate;
    final carbon = total.kwhImport * cef;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(context, Icons.electric_meter_outlined, 'Energy'),
            const SizedBox(height: 12),
            _EnergyRow(
                label: 'Active Energy',
                value: total.kwhImport,
                unit: 'kWh',
                dp: 2),
            _EnergyRow(
                label: 'Reactive Energy',
                value: total.kvarhImport,
                unit: 'kVARh',
                dp: 2),
            _EnergyRow(
                label: 'Apparent Energy',
                value: total.kvah,
                unit: 'kVAh',
                dp: 2),
            const Divider(height: 20),
            _EnergyRow(
              label: 'Est. Cost',
              value: bill,
              unit: 'Baht',
              dp: 2,
              highlight: true,
            ),
            _EnergyRow(
              label: 'Carbon Footprint',
              value: carbon,
              unit: 'kg CO₂',
              dp: 2,
            ),
            if (startTime > 0) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 13, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Recording since ${_formatDate(startTime)}',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _EnergyRow extends StatelessWidget {
  const _EnergyRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.dp,
    this.highlight = false,
  });

  final String label;
  final double value;
  final String unit;
  final int dp;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: highlight ? cs.onSurface : cs.outline)),
          ),
          Text(
            value.toStringAsFixed(dp),
            style: TextStyle(
              fontSize: 14,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'monospace',
              color: highlight ? cs.primary : cs.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 52,
            child: Text(
              unit,
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _BigValue extends StatelessWidget {
  const _BigValue({
    required this.label,
    required this.value,
    required this.unit,
    this.color,
  });

  final String label;
  final double value;
  final String unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = color ?? cs.onSurface;

    return Expanded(
      child: Column(
        children: [
          Text(
            value.toStringAsFixed(3),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: col,
            ),
          ),
          Text(unit,
              style: TextStyle(
                  fontSize: 11, color: col, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: cs.outline)),
        ],
      ),
    );
  }
}

class _InlineValue extends StatelessWidget {
  const _InlineValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace')),
          Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
        ],
      ),
    );
  }
}

Widget _cardHeader(BuildContext context, IconData icon, String title) {
  final cs = Theme.of(context).colorScheme;
  return Row(
    children: [
      Icon(icon, size: 16, color: cs.primary),
      const SizedBox(width: 8),
      Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
    ],
  );
}
