import 'dart:async';

import 'package:flutter/material.dart';

import '../services/system_wifi.dart';

/// Step-by-step dialog for joining the Raspberry Pi's `PI_AP` hotspot.
///
/// Behaviour:
///   • Shows 3 numbered steps.
///   • Polls the OS every 1.5 s for the current SSID.  If the SSID equals
///     `PI_AP` (or is unknown but the Pi gateway is reachable) the
///     **ถัดไป** button activates.
///   • Returns `true` when the user taps **ถัดไป** with PI_AP joined,
///     `false` if cancelled.
class PiApGuideDialog extends StatefulWidget {
  const PiApGuideDialog({
    super.key,
    this.ssid     = 'PI_AP',
    this.password = '123456789',
  });

  final String ssid;
  final String password;

  static Future<bool> show(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const PiApGuideDialog(),
    );
    return ok ?? false;
  }

  @override
  State<PiApGuideDialog> createState() => _PiApGuideDialogState();
}

class _PiApGuideDialogState extends State<PiApGuideDialog> {
  static const _pollInterval = Duration(milliseconds: 1500);

  Timer?  _timer;
  String? _ssid;           // last known SSID (null until first poll completes)
  bool    _ssidQueried   = false;   // becomes true after first poll
  bool    _piApReachable = false;   // fallback signal for Android 10+ w/o loc

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// One refresh tick: read SSID, and if it's unknown also probe Pi gateway
  /// reachability so we can still detect PI_AP on Android 10+.
  Future<void> _poll() async {
    final ssid = await getCurrentSsid();
    bool reachable = false;
    if (ssid == null) {
      reachable = await isPiApReachable();
    }
    if (!mounted) return;
    setState(() {
      _ssid          = ssid;
      _ssidQueried   = true;
      _piApReachable = reachable;
    });
  }

  /// True if we're confident the device is on the PI_AP network.
  bool get _onPiAp {
    if (_ssid == widget.ssid) return true;
    // SSID hidden by OS (Android 10+ w/o location perm) but Pi is reachable:
    if (_ssid == null && _piApReachable) return true;
    return false;
  }

  /// Display string for the "current wifi:" line.
  String get _currentWifiText {
    if (!_ssidQueried)         return '…';
    if (_ssid != null)         return _ssid!;
    if (_piApReachable)        return '(เชื่อม PI_AP สำเร็จ)';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onPiAp = _onPiAp;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ───────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              child: Row(
                children: [
                  Icon(Icons.wifi_tethering, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'เชื่อม Wi-Fi ของ Raspberry Pi',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context, false),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Steps ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Step(n: '1', text: 'แตะปุ่มด้านล่างเพื่อเปิดรายการ Wi-Fi'),
                  const SizedBox(height: 8),
                  _Step(
                    n: '2',
                    text:
                        'เลือก "${widget.ssid}" จากรายการ',
                  ),
                  const SizedBox(height: 8),
                  _Step(n: '3', text: 'กลับมาที่แอปแล้วแตะ "ถัดไป"'),
                ],
              ),
            ),

            // ── Current Wi-Fi status ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: _CurrentWifiBox(
                ssidText: _currentWifiText,
                onPiAp:   onPiAp,
              ),
            ),

            // ── Action buttons ───────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => openWifiPicker(),
                    icon: const Icon(Icons.wifi, size: 18),
                    label: const Text('เปิดรายการ Wi-Fi'),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    // "ถัดไป" appears active only when we detect PI_AP.
                    onPressed:
                        onPiAp ? () => Navigator.pop(context, true) : null,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('ถัดไป'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final String n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            n,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

class _CurrentWifiBox extends StatelessWidget {
  const _CurrentWifiBox({required this.ssidText, required this.onPiAp});
  final String ssidText;
  final bool   onPiAp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = onPiAp ? const Color(0xFF1AAB5F) : cs.outline;
    final bg     = onPiAp
        ? const Color(0xFF1AAB5F).withValues(alpha: 0.08)
        : cs.surfaceContainerLowest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            onPiAp ? Icons.check_circle : Icons.wifi,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Text(
            'current wifi:',
            style: TextStyle(
              fontSize: 12,
              color: cs.outline,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              ssidText,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
