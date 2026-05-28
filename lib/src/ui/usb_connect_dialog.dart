// widgets/usb_connect_dialog.dart
//
// Shows a dialog that:
//   1. Scans available COM ports using flutter_libserialport
//   2. Lets the user pick one (or auto-selects if only one exists)
//   3. Calls deviceClient.connectUsb(portName: selected)
//
// Usage — open from any button:
//   UsbConnectDialog.show(context, deviceClient);

import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../services/device_client.dart';

class UsbConnectDialog extends StatefulWidget {
  final DeviceClient client;

  const UsbConnectDialog({super.key, required this.client});

  /// Convenience: open as a modal dialog.
  static Future<void> show(BuildContext context, DeviceClient client) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UsbConnectDialog(client: client),
    );
  }

  @override
  State<UsbConnectDialog> createState() => _UsbConnectDialogState();
}

class _UsbConnectDialogState extends State<UsbConnectDialog> {
  List<String> _ports = [];
  String? _selected;
  bool _scanning = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  // ── scan ──────────────────────────────────────────────────────────────────

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      final seen = <String>{};
      final allPorts = SerialPort.availablePorts
          .where((p) => seen.add(p))
          .toList();

      // Filter out ghost ports (no description and no manufacturer)
      final ports = allPorts.where((portName) {
        try {
          final p = SerialPort(portName);
          final desc = p.description ?? '';
          final mfr  = p.manufacturer ?? '';
          p.dispose();
          // Keep port if it has any description or manufacturer info
          return desc.isNotEmpty || mfr.isNotEmpty;
        } catch (_) {
          return false; // can't open = ghost
        }
      }).toList();

      setState(() {
        _ports = ports;
        _selected = ports.length == 1 ? ports.first : _selected;
        _scanning = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not list COM ports: $e';
        _scanning = false;
      });
    }
  }

  // ── connect ───────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    final port = _selected;
    if (port == null) return;

    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      await widget.client.connectUsb(portName: port);
      if (mounted) Navigator.of(context).pop(); // success → close dialog
    } catch (e) {
      setState(() {
        _error = e.toString();
        _connecting = false;
      });
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect via USB'),
      content: SizedBox(
        width: 320,
        child: _scanning
            ? const _ScanningIndicator()
            : _ports.isEmpty
                ? _EmptyState(onRetry: _scan)
                : _PortList(
                    ports: _ports,
                    selected: _selected,
                    onChanged: (p) => setState(() => _selected = p),
                  ),
      ),
      actions: [
        // Error banner
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),

        TextButton(
          onPressed: _connecting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),

        // Refresh button
        if (!_scanning && !_connecting)
          TextButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh'),
          ),

        FilledButton(
          onPressed: (_selected == null || _connecting) ? null : _connect,
          child: _connecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }
}

// ── sub-widgets ───────────────────────────────────────────────────────────────

class _ScanningIndicator extends StatelessWidget {
  const _ScanningIndicator();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Scanning COM ports…'),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.usb_off, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No COM ports found.\nPlug in the USB cable and try again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan again'),
            ),
          ],
        ),
      );
}

class _PortList extends StatelessWidget {
  final List<String> ports;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _PortList({
    required this.ports,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ports.length} port${ports.length == 1 ? '' : 's'} found:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ...ports.map(
            (port) => RadioListTile<String>(
              dense: true,
              value: port,
              groupValue: selected,
              toggleable: false,
              title: Text(port),
              subtitle: _portDescription(port),
              onChanged: (_) => onChanged(port),
            ),
          ),
        ],
      );

  // Try to show a friendly description alongside the port name.
  Widget? _portDescription(String portName) {
    try {
      final p = SerialPort(portName);
      final desc = p.description ?? '';
      final mfr  = p.manufacturer ?? '';
      p.dispose();
      final label = [desc, mfr].where((s) => s.isNotEmpty).join(' · ');
      if (label.isNotEmpty) {
        return Text(label, style: const TextStyle(fontSize: 11));
      }
    } catch (_) {}
    return null;
  }
}