import 'package:flutter/material.dart';

import '../models/pi_settings.dart';
import '../services/device_client.dart';
import 'connection_status_badge.dart';
import 'pi_settings_widgets.dart';

class PiWifiPage extends StatefulWidget {
  const PiWifiPage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<PiWifiPage> createState() => _PiWifiPageState();
}

class _PiWifiPageState extends State<PiWifiPage> {
  final _ssidCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;

  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.client.getNetworkSettings();
      if (!mounted) return;
      setState(() {
        _ssidCtrl.text = s.ssid;
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

  Future<void> _apply() async {
    final ssid = _ssidCtrl.text.trim();
    if (ssid.isEmpty) {
      _snack('SSID cannot be empty', error: true);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.client.applyWifi(ssid, _passwordCtrl.text.trim());
      if (mounted) {
        _passwordCtrl.clear();
        _snack('WiFi settings applied — Pi will reconnect');
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    List<WifiNetwork> networks = [];
    try {
      networks = await widget.client.getWifiList();
    } catch (e) {
      if (mounted) _snack('Scan failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WifiPickerSheet(networks: networks),
    );
    if (picked != null && mounted) setState(() => _ssidCtrl.text = picked);
  }

  void _snack(String msg, {bool error = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? cs.errorContainer : null,
      showCloseIcon: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi'),
        actions: [ConnectionStatusBadge(client: widget.client)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? PiErrorView(message: _error!, onRetry: _load)
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Current connection status ──────────────────────────────
        if (_ssidCtrl.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1AAB5F).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF1AAB5F).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi, size: 18, color: Color(0xFF1AAB5F)),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connected to',
                          style: TextStyle(color: cs.outline, fontSize: 11)),
                      Text(_ssidCtrl.text,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),
          ),

        PiCard(
          child: Column(
            children: [
              // SSID field
              TextField(
                controller: _ssidCtrl,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'New SSID',
                  hintText: 'Enter network name or scan',
                  prefixIcon: const Icon(Icons.wifi_outlined, size: 20),
                  suffixIcon: IconButton(
                    tooltip: 'Scan networks',
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 20),
                    onPressed: _busy ? null : _scan,
                  ),
                ),
              ),
              const PiDivider(),

              const SizedBox(height: 4),
              // Password field
              TextField(
                controller: _passwordCtrl,
                enabled: !_busy,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Leave empty to keep current password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _apply,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.wifi_protected_setup, size: 18),
          label: const Text('Connect WiFi'),
        ),
        const SizedBox(height: 8),
        Text(
          'The Pi will disconnect briefly while connecting to the new network.',
          style: TextStyle(color: cs.outline, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── WiFi picker ───────────────────────────────────────────────────────────────

class _WifiPickerSheet extends StatelessWidget {
  const _WifiPickerSheet({required this.networks});

  final List<WifiNetwork> networks;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                Text('Available Networks',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${networks.length} found',
                    style: TextStyle(color: cs.outline, fontSize: 12)),
              ],
            ),
          ),
          const Divider(),
          if (networks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.wifi_off_outlined,
                      size: 40, color: cs.outlineVariant),
                  const SizedBox(height: 12),
                  Text('No networks found',
                      style: TextStyle(color: cs.outline)),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: networks.length,
                itemBuilder: (_, i) {
                  final n = networks[i];
                  return ListTile(
                    leading: _SignalIcon(signal: n.signal),
                    title: Text(n.ssid,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      n.security.isEmpty ? 'Open' : n.security,
                      style: TextStyle(color: cs.outline, fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (n.security.isNotEmpty)
                          Icon(Icons.lock_outline, size: 14, color: cs.outline),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 18, color: cs.outline),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, n.ssid),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SignalIcon extends StatelessWidget {
  const _SignalIcon({required this.signal});

  final int signal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = signal >= 70
        ? (Icons.wifi, const Color(0xFF1AAB5F))
        : signal >= 40
            ? (Icons.wifi_2_bar, cs.primary)
            : (Icons.wifi_1_bar, cs.outline);

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
