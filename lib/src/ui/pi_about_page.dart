import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pi_about_info.dart';
import '../services/device_client.dart';
import 'connection_status_badge.dart';
import 'pi_settings_widgets.dart';

/// App version string — keep in sync with pubspec.yaml.
const _kAppVersion = '1.0.0';

/// Human-readable label for a source type key.
String _collectorTypeLabel(String type) {
  switch (type) {
    case 'pic_uart':
      return 'PIC Collector (UART)';
    case 'modbus_rtu':
      return 'Modbus RTU Meter';
    default:
      return type;
  }
}

class PiAboutPage extends StatefulWidget {
  const PiAboutPage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<PiAboutPage> createState() => _PiAboutPageState();
}

class _PiAboutPageState extends State<PiAboutPage> {
  PiAboutInfo? _info;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await widget.client.getAboutInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        actions: [
          ConnectionStatusBadge(client: widget.client),
          if (!_loading)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? PiErrorView(message: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final info = _info!;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── About App ────────────────────────────────────────────────────
        _AboutCard(
          title: 'App',
          icon: Icons.phone_android_outlined,
          iconColor: cs.primary,
          children: [
            _InfoRow(label: 'Version', value: _kAppVersion),
          ],
        ),

        const SizedBox(height: 12),

        // ── About Meter ──────────────────────────────────────────────────
        _AboutCard(
          title: 'Meter',
          icon: Icons.memory_outlined,
          iconColor: const Color(0xFF1565C0),
          children: [
            if (info.meterProduct.isNotEmpty)
              _InfoRow(label: 'Product', value: info.meterProduct),
            if (info.meterModel.isNotEmpty)
              _InfoRow(label: 'Model', value: info.meterModel),
            _InfoRow(
              label: 'Version',
              value: info.meterVersion.isEmpty ? '—' : info.meterVersion,
            ),
            _InfoRow(
              label: 'Serial',
              value: info.meterSerial.isEmpty ? '—' : info.meterSerial,
              copyable: info.meterSerial.isNotEmpty,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── About Collector ──────────────────────────────────────────────
        _AboutCard(
          title: 'Collector',
          icon: Icons.developer_board_outlined,
          iconColor: const Color(0xFF2E7D32),
          children: info.hasCollector
              ? _collectorRows(info)
              : [const _NoCollectorBanner()],
        ),

        const SizedBox(height: 24),

        // ── Footer ───────────────────────────────────────────────────────
        Center(
          child: Text(
            'PowerView Manager v$_kAppVersion',
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  List<Widget> _collectorRows(PiAboutInfo info) {
    final typeLabel = info.collectorType != null
        ? _collectorTypeLabel(info.collectorType!)
        : '—';
    final enabledText =
        info.collectorEnabled == null ? '—' : (info.collectorEnabled! ? 'Enabled' : 'Disabled');

    return [
      _InfoRow(
        label: 'Name',
        value: info.collectorName ?? '—',
      ),
      _InfoRow(label: 'Type', value: typeLabel),
      _InfoRow(label: 'Status', value: enabledText),
      const _InfoRow(
        label: 'Version',
        value: '—',
        note: 'Not available',
      ),
      const _InfoRow(
        label: 'Serial',
        value: '—',
        note: 'Not available',
      ),
    ];
  }
}

// ── No-collector banner ───────────────────────────────────────────────────────

class _NoCollectorBanner extends StatelessWidget {
  const _NoCollectorBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No collector configured',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Go to Settings → Data Source to add a data source.',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── About info card ───────────────────────────────────────────────────────────

class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card header ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: iconColor,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          // ── Rows ───────────────────────────────────────────────────────
          ...children,
        ],
      ),
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.note,
    this.copyable = false,
  });

  final String label;
  final String value;

  /// Optional greyed-out annotation shown after the value (e.g. "Not available").
  final String? note;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          // Label
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
          ),
          // Value + optional note + copy icon
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '($note)',
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
                ],
                if (copyable) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied: $value'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Icon(Icons.copy_outlined, size: 14, color: cs.outline),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
