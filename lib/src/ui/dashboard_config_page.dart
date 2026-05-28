import 'package:flutter/material.dart';

import '../models/dashboard_config.dart';
import '../services/device_client.dart';

class DashboardConfigPage extends StatefulWidget {
  const DashboardConfigPage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<DashboardConfigPage> createState() => _DashboardConfigPageState();
}

class _DashboardConfigPageState extends State<DashboardConfigPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<FieldCatalogEntry> _catalog = [];
  List<DashboardConfig?> _configs = [null, null, null];

  // Mutable edited copies — one entry per dashboard tab.
  final List<Map<String, String>> _editedSlots  = [{}, {}, {}];
  final List<Map<String, String>> _editedLabels = [{}, {}, {}];

  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ //
  // Data loading
  // ------------------------------------------------------------------ //

  Future<void> _load() async {
    try {
      final catalog = await widget.client.getFieldCatalog();
      final config0 = await widget.client.getDashboardConfig(0);
      final config1 = await widget.client.getDashboardConfig(1);
      final config2 = await widget.client.getDashboardConfig(2);

      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _configs = [config0, config1, config2];
        for (var i = 0; i < 3; i++) {
          _editedSlots[i]  = Map.from(_configs[i]!.slots);
          _editedLabels[i] = Map.from(_configs[i]!.labels);
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = e.toString();
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------------ //
  // Save
  // ------------------------------------------------------------------ //

  Future<void> _save() async {
    final i = _tabController.index;
    setState(() => _saving = true);
    try {
      await widget.client.setDashboardConfig(
        i,
        Map.from(_editedSlots[i]),
        Map.from(_editedLabels[i]),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dashboard $i config saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefault() async {
    final i = _tabController.index;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset to default?'),
        content: Text('Dashboard $i will revert to its original values.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final fresh = await widget.client.resetDashboardConfig(i);
      if (!mounted) return;
      setState(() {
        _configs[i]      = fresh;
        _editedSlots[i]  = Map.from(fresh.slots);
        _editedLabels[i] = Map.from(fresh.labels);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dashboard $i reset to defaults')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------------ //
  // Build
  // ------------------------------------------------------------------ //

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Config'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Dashboard 0'),
            Tab(text: 'Dashboard 1'),
            Tab(text: 'Dashboard 2'),
          ],
        ),
        actions: [
          if (!_loading && _error == null)
            _saving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(onPressed: _save, child: const Text('Save')),
                      PopupMenuButton<_Action>(
                        onSelected: (action) {
                          if (action == _Action.reset) _resetToDefault();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _Action.reset,
                            child: Row(children: [
                              Icon(Icons.restart_alt, size: 18),
                              SizedBox(width: 10),
                              Text('Reset to default'),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: () {
                  setState(() { _loading = true; _error = null; });
                  _load();
                })
              : TabBarView(
                  controller: _tabController,
                  children: List.generate(3, _buildTab),
                ),
    );
  }

  Widget _buildTab(int index) {
    final config = _configs[index];
    if (config == null) return const SizedBox();

    final baseUrl = widget.client.screenshotBaseUrl;
    final imageUrl = baseUrl != null ? '$baseUrl/layout/$index' : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Reference image ──────────────────────────────────────────── //
        SizedBox(
          height: 220,
          child: imageUrl != null
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator()),
                )
              : const _ImagePlaceholder(),
        ),
        const Divider(height: 1),
        // ── Slot editor ──────────────────────────────────────────────── //
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (config.schemaSlots.isNotEmpty) ...[
                _SectionHeader(title: 'Values'),
                ...config.schemaSlots.map((slot) => _SlotRow(
                  slot: slot,
                  currentSource: _editedSlots[index][slot] ?? '',
                  catalog: _catalog,
                  onChanged: (val) => setState(() => _editedSlots[index][slot] = val),
                )),
              ],
              if (config.schemaLabels.isNotEmpty) ...[
                _SectionHeader(title: 'Labels'),
                ...config.schemaLabels.map((slot) => _LabelRow(
                  key: ValueKey('label-$index-$slot'),
                  slot: slot,
                  initialValue: _editedLabels[index][slot] ?? '',
                  onChanged: (val) => _editedLabels[index][slot] = val,
                )),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────── //

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.currentSource,
    required this.catalog,
    required this.onChanged,
  });

  final String slot;
  final String currentSource;
  final List<FieldCatalogEntry> catalog;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentEntry = catalog.firstWhere(
      (e) => e.key == currentSource,
      orElse: () => const FieldCatalogEntry(key: '', label: '— None —', unit: ''),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          // Slot name chip
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              slot,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Value dropdown
          Expanded(
            child: DropdownButtonFormField<String>(
              value: currentSource.isEmpty ? null : currentSource,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              hint: const Text('— Select —', style: TextStyle(fontSize: 13)),
              isExpanded: true,
              items: catalog
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) onChanged(val);
              },
            ),
          ),
          // Unit label
          SizedBox(
            width: 52,
            child: Text(
              currentEntry.unit,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: cs.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({
    super.key,
    required this.slot,
    required this.initialValue,
    required this.onChanged,
  });

  final String slot;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Container(
            width: 72,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              slot,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: cs.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              initialValue: initialValue,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Icon(Icons.dashboard_outlined,
            size: 48, color: Colors.white24),
      ),
    );
  }
}

enum _Action { reset }

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
