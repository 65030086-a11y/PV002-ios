import 'package:flutter/material.dart';

import '../models/modbus_profile.dart';
import '../models/modbus_profile_list.dart';
import '../models/source_config.dart';
import '../models/source_list.dart';
import '../services/device_client.dart';
import 'connection_status_badge.dart';
import 'ct_settings_dialog.dart';
import 'pi_settings_widgets.dart';
import 'source_editor_dialog.dart';

// ── Page ──────────────────────────────────────────────────────────────────────

/// Full-screen page for selecting the active meter data source.
///
/// Displays one card per meter type (Collector + one card per brand from the
/// Pi's profile list).  The currently active source is highlighted.
/// Tapping a card activates it; the edit icon opens connection / model settings.
class DataSourcePage extends StatefulWidget {
  const DataSourcePage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<DataSourcePage> createState() => _DataSourcePageState();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _DataSourcePageState extends State<DataSourcePage> {
  SourceList _sourceList = SourceList.empty();
  ModbusProfileList _profileList = ModbusProfileList.empty();

  bool _loading = true;
  String? _error;
  bool _busy = false;

  // ── Load ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sl = await widget.client.listSources();
      final pl = await widget.client.listModbusProfiles();

      if (!mounted) return;
      setState(() {
        _sourceList = sl;
        _profileList = pl;
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

  Future<void> _reload() async {
    final sl = await widget.client.listSources();
    final pl = await widget.client.listModbusProfiles();
    if (mounted) {
      setState(() {
        _sourceList = sl;
        _profileList = pl;
      });
    }
  }

  // ── Build brand entries ────────────────────────────────────────────────────

  List<_BrandEntry> get _entries {
    final result = <_BrandEntry>[];

    // ── Collector ────────────────────────────────────────────────────────────
    final picSource = _sourceList.sources
        .where((s) => s.type == 'pic_uart')
        .firstOrNull;
    result.add(_BrandEntry.collector(
      source: picSource,
      isActive: picSource != null &&
          picSource.id == _sourceList.activeSourceId,
    ));

    // ── One card per Modbus brand/profile ─────────────────────────────────
    for (final profile in _profileList.profiles) {
      final source = _sourceList.sources.where((s) {
        final pid = s.profileId.isNotEmpty
            ? s.profileId
            : s.settings['profile_id']?.toString() ?? '';
        return s.type == 'modbus_rtu' && pid == profile.id;
      }).firstOrNull;

      result.add(_BrandEntry.modbus(
        profile: profile,
        source: source,
        isActive: source != null &&
            source.id == _sourceList.activeSourceId,
      ));
    }

    return result;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _activate(_BrandEntry entry) async {
    if (entry.isActive) return;

    if (entry.source != null) {
      // Source already exists on Pi — just activate it
      await _run(() async {
        await widget.client.setActiveSource(entry.source!.id);
        await _reload();
      });
    } else {
      // Not configured yet — open editor to create it first
      await _openEditor(entry);
    }
  }

  Future<void> _openEditor(_BrandEntry entry) async {
    // For Modbus: pass only this brand's profile so the picker shows one brand.
    // For Collector: no profile needed.
    final profiles = entry.profile != null ? [entry.profile!] : <ModbusProfile>[];

    final existing = entry.source ?? _blankSource(entry);

    final result = await showDialog<SourceEditorResult>(
      context: context,
      builder: (_) => SourceEditorDialog(
        profiles: profiles,
        existing: existing,
      ),
    );
    if (result == null || !mounted) return;

    await _run(() async {
      if (entry.source != null) {
        // Update existing source
        await widget.client.updateSource(entry.source!.id, {
          'name':       result.source.name,
          'settings':   result.source.settings,
          'profile_id': result.source.profileId,
          'source_key': result.source.sourceKey,
        });
      } else {
        // Create new source and activate it
        await widget.client.addSource(result.source);
        await widget.client.setActiveSource(result.source.id);
      }
      await _reload();
    });
  }

  Future<void> _openCtSettings(_BrandEntry entry) async {
    final source = entry.source;
    final profile = entry.profile;
    if (source == null || profile == null || !profile.hasCtRegisters) return;

    await showDialog<void>(
      context: context,
      builder: (_) => CtSettingsDialog(
        client: widget.client,
        source: source,
        profile: profile,
      ),
    );
  }

  SourceConfig _blankSource(_BrandEntry entry) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    if (entry.isCollector) {
      return SourceConfig(
        id: 'pic_uart_$ts',
        name: 'Collector',
        type: 'pic_uart',
        enabled: true,
        settings: {'port': '/dev/ttyS0', 'baudrate': 115200},
      );
    }
    final profile = entry.profile!;
    return SourceConfig(
      id: '${profile.id}_$ts',
      name: profile.brand.isNotEmpty ? profile.brand : profile.displayLabel,
      type: 'modbus_rtu',
      enabled: true,
      settings: {
        'port': '/dev/ttyUSB0',
        'baudrate': 9600,
        'slave_id': 1,
        'profile_id': profile.id,
        if (profile.hasVariants) 'source_key': profile.resolveDefaultSourceKey(),
      },
      profileId: profile.id,
      sourceKey: profile.hasVariants ? profile.resolveDefaultSourceKey() : '',
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Source'),
        actions: [
          ConnectionStatusBadge(client: widget.client),
          if (!_loading)
            IconButton(
              tooltip: 'Reload',
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _busy ? null : _load,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? PiErrorView(message: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final entries = _entries;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final entry = entries[i];
        return _BrandCard(
          entry: entry,
          busy: _busy,
          onTap: () => _activate(entry),
          onEdit: () => _openEditor(entry),
          onCtSettings: (entry.source != null &&
                  entry.profile != null &&
                  entry.profile!.hasCtRegisters)
              ? () => _openCtSettings(entry)
              : null,
        );
      },
    );
  }
}

// ── Brand entry data class ────────────────────────────────────────────────────

class _BrandEntry {
  _BrandEntry.collector({this.source, required this.isActive})
      : isCollector = true,
        profile = null;

  _BrandEntry.modbus({
    required this.profile,
    this.source,
    required this.isActive,
  }) : isCollector = false;

  final bool isCollector;
  final ModbusProfile? profile;
  final SourceConfig? source;
  final bool isActive;

  bool get isConfigured => source != null;

  String get displayName {
    if (isCollector) return 'Collector';
    final b = profile?.brand ?? '';
    return b.isNotEmpty ? b : (profile?.displayLabel ?? '');
  }

  String get modelLabel {
    if (isCollector) return 'Built-in UART collector';
    if (profile == null) return '';
    final m = profile!.model;
    return m.isNotEmpty ? m : profile!.name;
  }

  /// Currently selected variant label (e.g. "Group A") or empty string.
  String get activeVariantLabel {
    if (profile == null || source == null) return '';
    final key = source!.sourceKey.isNotEmpty
        ? source!.sourceKey
        : source!.settings['source_key']?.toString() ?? '';
    if (key.isEmpty || !profile!.hasVariants) return '';
    return profile!.variantLabel(key);
  }

  /// Connection subtitle (port info).
  String get portLabel {
    if (source == null) return '';
    return source!.settings['port']?.toString() ?? '';
  }
}

// ── Brand card widget ─────────────────────────────────────────────────────────

class _BrandCard extends StatelessWidget {
  const _BrandCard({
    required this.entry,
    required this.busy,
    required this.onTap,
    required this.onEdit,
    this.onCtSettings,
  });

  final _BrandEntry entry;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onCtSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = entry.isActive;
    final primary = cs.primary;

    final bgColor = active
        ? primary.withValues(alpha: 0.07)
        : cs.surfaceContainerLowest;
    final borderColor = active ? primary : cs.outlineVariant;
    final borderWidth = active ? 1.5 : 1.0;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              // ── Icon ──────────────────────────────────────────────────
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: active
                      ? primary.withValues(alpha: 0.12)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  entry.isCollector
                      ? Icons.developer_board
                      : Icons.sensors,
                  size: 22,
                  color: active ? primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 14),

              // ── Labels ────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand name
                    Text(
                      entry.displayName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: active ? primary : null,
                          ),
                    ),
                    const SizedBox(height: 2),

                    // Model / variant row
                    _SubtitleRow(entry: entry, active: active),

                    // Port info
                    if (entry.portLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.portLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.outline,
                              fontFamily: 'monospace',
                            ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Actions ───────────────────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: primary,
                      ),
                    ),
                  if (onCtSettings != null)
                    IconButton(
                      tooltip: 'CT settings',
                      icon: const Icon(Icons.transform_outlined, size: 18),
                      onPressed: busy ? null : onCtSettings,
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    tooltip: entry.isConfigured
                        ? 'Edit settings'
                        : 'Configure',
                    icon: Icon(
                      entry.isConfigured
                          ? Icons.edit_outlined
                          : Icons.settings_outlined,
                      size: 18,
                    ),
                    onPressed: busy ? null : onEdit,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Subtitle row (model + variant + not-configured badge) ─────────────────────

class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({required this.entry, required this.active});

  final _BrandEntry entry;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final parts = <String>[];
    if (entry.modelLabel.isNotEmpty) parts.add(entry.modelLabel);
    if (entry.activeVariantLabel.isNotEmpty) {
      parts.add(entry.activeVariantLabel);
    }

    if (!entry.isConfigured) {
      return Row(
        children: [
          if (parts.isNotEmpty)
            Text(
              parts.join(' · '),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outline),
            ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              'Not configured',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.outline,
                  ),
            ),
          ),
        ],
      );
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: active ? cs.primary.withValues(alpha: 0.8) : cs.outline,
          ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
