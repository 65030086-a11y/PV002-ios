import 'package:flutter/material.dart';

import '../services/device_client.dart';
import 'connection_status_badge.dart';

class PiMeterActionsPage extends StatefulWidget {
  const PiMeterActionsPage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<PiMeterActionsPage> createState() => _PiMeterActionsPageState();
}

class _PiMeterActionsPageState extends State<PiMeterActionsPage> {
  bool _resetting = false;

  Future<void> _resetMeter() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error, size: 32),
        title: const Text('Reset energy meter?'),
        content: const Text(
          'This will clear all accumulated energy counters (kWh, kVARh, kVAh) on the device. This action cannot be undone.',
        ),
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
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      await widget.client.resetMeter();
      if (mounted) _snack('Energy counters have been reset');
    } catch (e) {
      if (mounted) _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _resetting = false);
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meter Actions'),
        actions: [ConnectionStatusBadge(client: widget.client)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.restart_alt,
                            color: cs.onErrorContainer, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Reset Energy Meter',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(
                              'Clear all accumulated energy counters',
                              style: TextStyle(color: cs.outline, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: cs.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Resets kWh, kVARh, and kVAh counters to zero. This cannot be undone.',
                            style: TextStyle(
                                fontSize: 12, color: cs.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error),
                    ),
                    onPressed: _resetting ? null : _resetMeter,
                    icon: _resetting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.error),
                          )
                        : const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset Meter'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
