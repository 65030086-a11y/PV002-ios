import 'package:flutter/material.dart';

import '../models/pi_settings.dart';
import '../services/device_client.dart';
import 'connection_status_badge.dart';
import 'pi_settings_widgets.dart';

class PiPowerViewPage extends StatefulWidget {
  const PiPowerViewPage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<PiPowerViewPage> createState() => _PiPowerViewPageState();
}

class _PiPowerViewPageState extends State<PiPowerViewPage> {
  int _ctType = 0;
  final _elecRateCtrl = TextEditingController();
  final _cefCtrl = TextEditingController();

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
    _elecRateCtrl.dispose();
    _cefCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.client.getPowerViewSettings();
      if (!mounted) return;
      setState(() {
        _ctType = s.ctType;
        _elecRateCtrl.text = s.elecRate.toString();
        _cefCtrl.text = s.cef.toString();
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
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.client.applyPowerViewSettings(PiPowerViewSettings(
        ctType: _ctType,
        elecRate: double.tryParse(_elecRateCtrl.text.trim()) ?? 4.0,
        cef: double.tryParse(_cefCtrl.text.trim()) ?? 0.399,
      ));
      if (mounted) _snack('PowerView config saved');
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
        title: const Text('PowerView Config'),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── CT Type ──────────────────────────────────────────────────
        PiCard(
          label: 'CT Type',
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CT Type',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Current transformer type',
                        style: TextStyle(color: cs.outline, fontSize: 12)),
                  ],
                ),
              ),
              DropdownButton<int>(
                value: _ctType,
                onChanged:
                    _busy ? null : (v) => setState(() => _ctType = v ?? 0),
                underline: const SizedBox(),
                items: [0, 1, 2, 3]
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text('Type $v'),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Rate / CEF ───────────────────────────────────────────────
        PiCard(
          label: 'Billing & Carbon',
          child: Column(
            children: [
              PiField(
                label: 'Electricity Rate',
                controller: _elecRateCtrl,
                enabled: !_busy,
                hint: '4.0',
                suffix: 'Baht/kWh',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              const PiDivider(),
              PiField(
                label: 'Carbon Emission Factor',
                controller: _cefCtrl,
                enabled: !_busy,
                hint: '0.399',
                suffix: 'kg/kWh',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

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
          label: const Text('Save Config'),
        ),
      ],
    );
  }
}

