import 'package:flutter/material.dart';

import '../models/modbus_profile.dart';
import '../models/source_config.dart';
import 'meter_type_picker.dart';

class SourceEditorResult {
  SourceEditorResult({required this.source});

  final SourceConfig source;
}

/// Production-style source editor dialog.
/// Sections: Display name → Meter type → Connection settings.
class SourceEditorDialog extends StatefulWidget {
  const SourceEditorDialog({
    super.key,
    required this.profiles,
    required this.existing,
  });

  final List<ModbusProfile> profiles;
  final SourceConfig existing;

  @override
  State<SourceEditorDialog> createState() => _SourceEditorDialogState();
}

class _SourceEditorDialogState extends State<SourceEditorDialog> {
  late final TextEditingController _portController;
  late final TextEditingController _baudController;
  late final TextEditingController _slaveController;

  late String _profileId;
  late String _sourceKey;

  bool _portError = false;

  bool get _isModbus => widget.existing.type == 'modbus_rtu';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _portController = TextEditingController(
      text: e.settings['port']?.toString() ??
          (_isModbus ? '/dev/ttyUSB0' : '/dev/ttyS0'),
    );
    _baudController = TextEditingController(
      text:
          e.settings['baudrate']?.toString() ?? (_isModbus ? '9600' : '115200'),
    );
    _slaveController = TextEditingController(
      text: e.settings['slave_id']?.toString() ?? '1',
    );

    _profileId = e.profileId.isNotEmpty
        ? e.profileId
        : e.settings['profile_id']?.toString() ?? '';
    _sourceKey = e.sourceKey.isNotEmpty
        ? e.sourceKey
        : e.settings['source_key']?.toString() ?? '';

    if (_profileId.isEmpty && widget.profiles.isNotEmpty) {
      _profileId = widget.profiles.first.id;
    }
    _syncSourceKey();
  }

  @override
  void dispose() {
    _portController.dispose();
    _baudController.dispose();
    _slaveController.dispose();
    super.dispose();
  }

  void _syncSourceKey() {
    for (final profile in widget.profiles) {
      if (profile.id != _profileId) continue;
      if (!profile.hasVariants) {
        _sourceKey = '';
        return;
      }
      if (_sourceKey.isEmpty ||
          !profile.availableSources.contains(_sourceKey)) {
        _sourceKey = profile.resolveDefaultSourceKey();
      }
      return;
    }
  }

  void _submit() {
    final port = _portController.text.trim();

    setState(() {
      _portError = port.isEmpty;
    });

    if (_portError) return;
    if (_isModbus && _profileId.isEmpty) return;

    final baudrate = int.tryParse(_baudController.text.trim()) ??
        (_isModbus ? 9600 : 115200);

    final settings = Map<String, dynamic>.from(widget.existing.settings);
    settings['port'] = port;
    settings['baudrate'] = baudrate;

    var profileId = '';
    var sourceKey = '';

    if (_isModbus) {
      profileId = _profileId;
      sourceKey = _sourceKey;
      settings['slave_id'] = int.tryParse(_slaveController.text.trim()) ?? 1;
      settings['profile_id'] = profileId;
      if (sourceKey.isNotEmpty) settings['source_key'] = sourceKey;
    }

    Navigator.pop(
      context,
      SourceEditorResult(
        source: SourceConfig(
          id: widget.existing.id,
          name: widget.existing.name,
          type: widget.existing.type,
          enabled: widget.existing.enabled,
          settings: settings,
          profileId: profileId,
          sourceKey: sourceKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────
            _DialogHeader(
              icon: _isModbus ? Icons.sensors : Icons.developer_board,
              title: widget.existing.name.isNotEmpty
                  ? widget.existing.name
                  : widget.existing.id,
              subtitle: widget.existing.id,
            ),

            // ── Scrollable body ─────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // METER TYPE (modbus only)
                    if (_isModbus) ...[
                      const SizedBox(height: 20),
                      _SectionLabel(label: 'Meter type'),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 260,
                        child: MeterTypePicker(
                          profiles: widget.profiles,
                          busy: false,
                          picSelected: false,
                          selectedProfileId: _profileId,
                          selectedSourceKey: _sourceKey,
                          showPicOption: false,
                          onSelectPic: () {},
                          onSelectModbus: (profileId, sourceKey) {
                            setState(() {
                              _profileId = profileId;
                              _sourceKey = sourceKey;
                            });
                          },
                        ),
                      ),
                    ],

                    // CONNECTION
                    const SizedBox(height: 20),
                    _SectionLabel(label: 'Connection'),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _portController,
                            autofocus: true,
                            onChanged: (_) {
                              if (_portError) {
                                setState(() => _portError = false);
                              }
                            },
                            decoration: InputDecoration(
                              labelText:
                                  _isModbus ? 'Serial port' : 'UART port',
                              hintText:
                                  _isModbus ? '/dev/ttyUSB0' : '/dev/ttyS0',
                              errorText: _portError ? 'Required' : null,
                              prefixIcon: const Icon(Icons.usb_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _baudController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Baudrate',
                              prefixIcon: Icon(Icons.speed_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isModbus) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _slaveController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Modbus slave ID',
                            hintText: '1',
                            prefixIcon: Icon(Icons.tag_outlined),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Actions ─────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: cs.outlineVariant),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _submit,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save to Pi'),
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

// ── Dialog header ─────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.outline,
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
    );
  }
}
