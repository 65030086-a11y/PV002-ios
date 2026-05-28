import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/alarm_config.dart';
import '../services/device_client.dart';
import 'connection_status_badge.dart';

/// Full-screen page for creating or editing a single alarm rule.
class AlarmEditorPage extends StatefulWidget {
  const AlarmEditorPage({super.key, this.existing, this.client});

  /// When non-null, the page is in edit mode; fields are pre-filled.
  final AlarmConfig? existing;

  /// Optional client — when provided, a connection status badge is shown
  /// in the app bar so the user can see live disconnect events.
  final DeviceClient? client;

  @override
  State<AlarmEditorPage> createState() => _AlarmEditorPageState();
}

class _AlarmEditorPageState extends State<AlarmEditorPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _labelCtrl;
  late final TextEditingController _thresholdCtrl;
  late final TextEditingController _hysteresisCtrl;
  late final TextEditingController _triggerDelayCtrl;
  late final TextEditingController _autoClearCtrl;

  String _parameter = AlarmParameter.voltageL1;
  String _condition = AlarmCondition.high;
  bool   _enabled   = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _parameter = e?.parameter ?? AlarmParameter.voltageL1;
    _condition = e?.condition ?? AlarmCondition.high;
    _enabled   = e?.enabled   ?? true;

    _labelCtrl        = TextEditingController(text: e?.label ?? '');
    _thresholdCtrl    = TextEditingController(text: e != null ? _fmt(e.threshold) : '');
    _hysteresisCtrl   = TextEditingController(text: e != null ? _fmt(e.hysteresis) : '0');
    _triggerDelayCtrl = TextEditingController(text: '${e?.triggerDelaySec ?? 0}');
    _autoClearCtrl    = TextEditingController(text: '${e?.autoClearDelaySec ?? 0}');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _thresholdCtrl.dispose();
    _hysteresisCtrl.dispose();
    _triggerDelayCtrl.dispose();
    _autoClearCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);

  // ── Actions ────────────────────────────────────────────────────────────────

  void _onParameterChanged(String p) {
    setState(() {
      _parameter = p;
      // Fix condition if not allowed for the new parameter
      final allowed = AlarmCondition.allowedFor(p);
      if (!allowed.contains(_condition)) _condition = allowed.first;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final result = AlarmConfig(
      id:                widget.existing?.id ?? '',
      label:             _labelCtrl.text.trim(),
      parameter:         _parameter,
      condition:         _condition,
      threshold:         double.parse(_thresholdCtrl.text.trim()),
      hysteresis:        double.tryParse(_hysteresisCtrl.text.trim()) ?? 0.0,
      enabled:           _enabled,
      triggerDelaySec:   int.tryParse(_triggerDelayCtrl.text.trim()) ?? 0,
      autoClearDelaySec: int.tryParse(_autoClearCtrl.text.trim()) ?? 0,
    );
    Navigator.pop(context, result);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unit = AlarmParameter.unit(_parameter);
    final allowed = AlarmCondition.allowedFor(_parameter);
    final isSetpoint = _condition == AlarmCondition.setpoint;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Alarm' : 'New Alarm'),
        actions: [
          if (widget.client != null)
            ConnectionStatusBadge(client: widget.client!),
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            // ── Label ─────────────────────────────────────────────────────
            _SectionHeader('Name'),
            TextFormField(
              controller: _labelCtrl,
              decoration: _dec('Alarm label', 'e.g. Overvoltage L1'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),

            const SizedBox(height: 20),

            // ── Parameter ─────────────────────────────────────────────────
            _SectionHeader('Parameter'),
            _ParameterField(
              value: _parameter,
              onChanged: _onParameterChanged,
            ),

            const SizedBox(height: 20),

            // ── Condition ─────────────────────────────────────────────────
            _SectionHeader('Condition'),
            SegmentedButton<String>(
              segments: allowed
                  .map((c) => ButtonSegment(value: c, label: Text(AlarmCondition.label(c))))
                  .toList(),
              selected: {_condition},
              onSelectionChanged: (s) => setState(() => _condition = s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),

            const SizedBox(height: 20),

            // ── Threshold ─────────────────────────────────────────────────
            _SectionHeader('Threshold${unit.isNotEmpty ? " ($unit)" : ""}'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _thresholdCtrl,
                    decoration: _dec(
                      isSetpoint ? 'Setpoint value' : 'Threshold value',
                      unit.isNotEmpty ? unit : null,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-\d.]'))],
                    validator: _validateNumber,
                  ),
                ),
                if (!isSetpoint) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hysteresisCtrl,
                      decoration: _dec('Hysteresis', unit.isNotEmpty ? '±$unit' : null),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                      validator: _validateNonNeg,
                    ),
                  ),
                ],
              ],
            ),
            if (!isSetpoint)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Alarm activates above threshold; clears below (threshold − hysteresis).',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ),

            const SizedBox(height: 20),

            // ── Timing ────────────────────────────────────────────────────
            _SectionHeader('Timing'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _triggerDelayCtrl,
                    decoration: _dec('Trigger delay', 'seconds'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: _validateNonNegInt,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _autoClearCtrl,
                    decoration: _dec('Auto-clear after', '0 = manual'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: _validateNonNegInt,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Trigger delay: condition must hold for this many seconds before the alarm fires.\n'
                'Auto-clear: alarm clears automatically after this many seconds (0 = clear manually in app).',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),

            const SizedBox(height: 20),

            // ── Enable toggle ─────────────────────────────────────────────
            _SectionHeader('Status'),
            SwitchListTile(
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              title: Text(_enabled ? 'Enabled' : 'Disabled'),
              subtitle: Text(_enabled
                  ? 'Alarm will be evaluated against live meter data.'
                  : 'Alarm is paused; no notifications will be triggered.',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Validators ─────────────────────────────────────────────────────────────

  static String? _validateNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
    return null;
  }

  static String? _validateNonNeg(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n < 0) return 'Must be ≥ 0';
    return null;
  }

  static String? _validateNonNegInt(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = int.tryParse(v.trim());
    if (n == null) return 'Enter a whole number';
    if (n < 0) return 'Must be ≥ 0';
    return null;
  }

  // ── Decoration helper ──────────────────────────────────────────────────────

  static InputDecoration _dec(String label, [String? hint]) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      );
}

// ── Parameter picker field ────────────────────────────────────────────────────

class _ParameterField extends StatelessWidget {
  const _ParameterField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showPicker(context),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          '${_groupName(value)}  ·  ${AlarmParameter.label(value)}',
          style: TextStyle(fontSize: 14, color: cs.onSurface),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ParameterPickerSheet(
        selected: value,
        onPicked: (p) {
          Navigator.pop(context);
          onChanged(p);
        },
      ),
    );
  }

  static String _groupName(String param) {
    for (final g in AlarmParameter.groups) {
      if (g.parameters.contains(param)) return g.name;
    }
    return '';
  }
}

class _ParameterPickerSheet extends StatelessWidget {
  const _ParameterPickerSheet({required this.selected, required this.onPicked});

  final String selected;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Select Parameter',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: AlarmParameter.groups.length,
              itemBuilder: (_, gi) {
                final group = AlarmParameter.groups[gi];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(group.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: cs.primary, letterSpacing: 0.8)),
                    ),
                    ...group.parameters.map((p) => ListTile(
                          dense: true,
                          title: Text(AlarmParameter.label(p)),
                          subtitle: Text(AlarmParameter.unit(p),
                              style: TextStyle(color: cs.outline, fontSize: 11)),
                          trailing: p == selected
                              ? Icon(Icons.check, color: cs.primary, size: 18)
                              : null,
                          selected: p == selected,
                          onTap: () => onPicked(p),
                        )),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
