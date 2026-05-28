import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/modbus_profile.dart';
import '../models/source_config.dart';
import '../services/device_client.dart';

/// Dialog to read and write CT (Current Transformer) configuration registers
/// from/to a Modbus collector device.
///
/// Usage:
/// ```dart
/// await showDialog(
///   context: context,
///   builder: (_) => CtSettingsDialog(
///     client: client,
///     source: source,
///     profile: profile,
///   ),
/// );
/// ```
class CtSettingsDialog extends StatefulWidget {
  const CtSettingsDialog({
    super.key,
    required this.client,
    required this.source,
    required this.profile,
  });

  final DeviceClient client;
  final SourceConfig source;
  final ModbusProfile profile;

  @override
  State<CtSettingsDialog> createState() => _CtSettingsDialogState();
}

class _CtSettingsDialogState extends State<CtSettingsDialog> {
  // Controllers keyed by CT register key (e.g. "ct_primary")
  final Map<String, TextEditingController> _controllers = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final key in widget.profile.ctRegisters.keys) {
      _controllers[key] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await widget.client.getCtSettings(widget.source.id);
      if (!mounted) return;
      for (final entry in values.entries) {
        final ctrl = _controllers[entry.key];
        if (ctrl != null) {
          ctrl.text = entry.value.toString();
        }
      }
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    // Collect values from controllers
    final values = <String, dynamic>{};
    for (final entry in _controllers.entries) {
      final raw = entry.value.text.trim();
      final spec = widget.profile.ctRegisters[entry.key] as Map?;
      final type = (spec?['type'] as String? ?? 'uint16').toLowerCase();

      if (type == 'float32') {
        final v = double.tryParse(raw);
        if (v == null) {
          _snack('Invalid value for ${widget.profile.ctLabel(entry.key)}',
              error: true);
          return;
        }
        values[entry.key] = v;
      } else {
        final v = int.tryParse(raw);
        if (v == null || v < 0 || v > 65535) {
          _snack('Invalid value for ${widget.profile.ctLabel(entry.key)}',
              error: true);
          return;
        }
        values[entry.key] = v;
      }
    }

    setState(() => _saving = true);
    try {
      final confirmed =
          await widget.client.setCtSettings(widget.source.id, values);
      if (!mounted) return;

      // Update fields with confirmed values from device
      for (final entry in confirmed.entries) {
        final ctrl = _controllers[entry.key];
        if (ctrl != null) ctrl.text = entry.value.toString();
      }

      _snack('CT settings saved');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        _snack(e.toString(), error: true);
        setState(() => _saving = false);
      }
    }
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
    final cs = Theme.of(context).colorScheme;
    final sourceName = widget.source.name.isNotEmpty
        ? widget.source.name
        : widget.source.id;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.transform_outlined,
                        size: 20, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CT Settings',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          sourceName,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.outline,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // ── Body ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: _loading
                  ? const _LoadingState()
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : _buildFields(cs),
            ),

            // ── Actions ───────────────────────────────────────────────────
            if (!_loading && _error == null)
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save to meter'),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFields(ColorScheme cs) {
    final keys = widget.profile.ctRegisters.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Read from and written directly to the meter device via Modbus.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.outline),
        ),
        const SizedBox(height: 16),
        ...keys.map((key) {
          final spec = widget.profile.ctRegisters[key] as Map?;
          final type =
              (spec?['type'] as String? ?? 'uint16').toLowerCase();
          final label = widget.profile.ctLabel(key);

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(
              controller: _controllers[key],
              keyboardType: type == 'float32'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.number,
              inputFormatters: type == 'float32'
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
                  : [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: label,
                helperText:
                    type == 'float32' ? 'float32' : 'uint16  (0–65535)',
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Loading state ─────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Reading from meter…'),
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 36),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
