import 'package:flutter/material.dart';

import '../services/device_client.dart';

/// Compact connect/disconnect indicator suitable for placing in any page's
/// `AppBar(actions: ...)`.
///
/// Listens to [DeviceClient] (a [ChangeNotifier]) and redraws automatically
/// whenever the connection state changes — including unexpected drops
/// signalled by the transport.
class ConnectionStatusBadge extends StatefulWidget {
  const ConnectionStatusBadge({super.key, required this.client});

  final DeviceClient client;

  @override
  State<ConnectionStatusBadge> createState() => _ConnectionStatusBadgeState();
}

class _ConnectionStatusBadgeState extends State<ConnectionStatusBadge> {
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onClientChanged);
  }

  @override
  void didUpdateWidget(ConnectionStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.client != oldWidget.client) {
      oldWidget.client.removeListener(_onClientChanged);
      widget.client.addListener(_onClientChanged);
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClientChanged);
    super.dispose();
  }

  void _onClientChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.client.isConnected;
    return _Pill(
      connected: connected,
      label: connected ? _modeLabel() : 'Disconnected',
    );
  }

  String _modeLabel() {
    switch (widget.client.mode) {
      case ConnectionMode.tcp:
        return widget.client.host == null ? 'Connected' : 'TCP ${widget.client.host}';
      case ConnectionMode.usb:
        return 'USB';
      case null:
        return 'Connected';
    }
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.connected, required this.label});

  final bool   connected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final accent   = connected
        ? const Color(0xFF1AAB5F)        // green
        : const Color(0xFFE53935);       // red
    final bg       = accent.withValues(alpha: 0.10);
    final border   = accent.withValues(alpha: 0.45);
    final iconData = connected ? Icons.cloud_done : Icons.cloud_off;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconData, size: 14, color: accent),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
