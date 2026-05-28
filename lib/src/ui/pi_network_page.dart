import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pi_settings.dart';
import '../services/device_client.dart';
import 'connection_status_badge.dart';
import 'pi_settings_widgets.dart';

class PiNetworkPage extends StatefulWidget {
  const PiNetworkPage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<PiNetworkPage> createState() => _PiNetworkPageState();
}

class _PiNetworkPageState extends State<PiNetworkPage> {
  bool _dhcp = true;
  final _ipCtrl = TextEditingController();
  final _netmaskCtrl = TextEditingController();
  final _gatewayCtrl = TextEditingController();
  final _dnsCtrl = TextEditingController();
  final _portCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  bool _busy = false;
  bool _portError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _netmaskCtrl.dispose();
    _gatewayCtrl.dispose();
    _dnsCtrl.dispose();
    _portCtrl.dispose();
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
        _dhcp = s.dhcp;
        _ipCtrl.text = s.ip;
        _netmaskCtrl.text = s.netmask;
        _gatewayCtrl.text = s.gateway;
        _dnsCtrl.text = s.dns;
        _portCtrl.text = s.port.toString();
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

  void _validatePort(String value) {
    final port = int.tryParse(value) ?? 0;
    setState(() => _portError = port > 0 && (port < 1024 || port > 65533));
  }

  Future<void> _apply() async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply network settings?'),
        content: const Text(
          'Changing network settings may disconnect the current session. '
          'You will need to reconnect using the new settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final port = int.tryParse(_portCtrl.text.trim()) ?? 5555;
    if (port < 1024 || port > 65533) {
      _snack('Port must be between 1024 and 65533', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.client.applyNetworkSettings(PiNetworkSettings(
        dhcp: _dhcp,
        ip: _ipCtrl.text.trim(),
        netmask: _netmaskCtrl.text.trim(),
        gateway: _gatewayCtrl.text.trim(),
        port: port,
        dns: _dnsCtrl.text.trim(),
        ssid: '',
      ));
      // Network change may disconnect — show a message
      if (mounted) {
        final portChanged = port != 5555;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(portChanged
              ? 'Network settings saved — port change takes effect after reboot'
              : 'Network settings applied — reconnecting may be required'),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ));
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        title: const Text('Network'),
        actions: [
          ConnectionStatusBadge(client: widget.client),
          if (!_loading)
            IconButton(
              tooltip: 'Reload',
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
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    final cs = Theme.of(context).colorScheme;
    final staticReadOnly = _dhcp; // show values but lock editing
    final fieldsEnabled = !_busy;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── DHCP ────────────────────────────────────────────────────
        PiCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('DHCP',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              _dhcp ? 'IP assigned by router' : 'Using static IP',
              style: TextStyle(color: cs.outline, fontSize: 12),
            ),
            value: _dhcp,
            onChanged: _busy ? null : (v) => setState(() => _dhcp = v),
          ),
        ),
        const SizedBox(height: 12),

        // ── Static IP fields ─────────────────────────────────────────
        PiCard(
          child: Column(
            children: [
              PiField(
                label: 'IP Address',
                controller: _ipCtrl,
                enabled: fieldsEnabled,
                readOnly: staticReadOnly,
                hint: '192.168.1.170',
                keyboard: TextInputType.url,
              ),
              const PiDivider(),
              PiField(
                label: 'Subnet Mask',
                controller: _netmaskCtrl,
                enabled: fieldsEnabled,
                readOnly: staticReadOnly,
                hint: '255.255.255.0',
                keyboard: TextInputType.url,
              ),
              const PiDivider(),
              PiField(
                label: 'Gateway',
                controller: _gatewayCtrl,
                enabled: fieldsEnabled,
                readOnly: staticReadOnly,
                hint: '192.168.1.1',
                keyboard: TextInputType.url,
              ),
              const PiDivider(),
              PiField(
                label: 'DNS',
                controller: _dnsCtrl,
                enabled: fieldsEnabled,
                readOnly: staticReadOnly,
                hint: '8.8.8.8',
                keyboard: TextInputType.url,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── TCP Port ─────────────────────────────────────────────────
        PiCard(
          child: PiField(
            label: 'TCP Port',
            controller: _portCtrl,
            enabled: fieldsEnabled,
            hint: '5555',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            suffix: 'tcp',
            onChanged: _validatePort,
          ),
        ),

        if (_portError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: cs.error),
                const SizedBox(width: 4),
                Text(
                  'Port must be 1024–65533',
                  style: TextStyle(color: cs.error, fontSize: 12),
                ),
              ],
            ),
          ),

        if (_dhcp) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 13, color: cs.outline),
              const SizedBox(width: 4),
              Text(
                'IP/network fields are read-only while DHCP is on.',
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
            ],
          ),
        ],

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
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('Apply Network Settings'),
        ),
      ],
    );
  }
}
