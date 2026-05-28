import 'package:flutter/material.dart';

import '../models/modbus_profile.dart';
import '../models/source_config.dart';

/// Flat list of configured sources grouped by type (PIC / Modbus).
/// Only sources present in sources.json are shown; catalog profiles are
/// not listed here — they belong in the add/edit dialog.
class SourceListView extends StatelessWidget {
  const SourceListView({
    super.key,
    required this.profiles,
    required this.sources,
    required this.activeSourceId,
    required this.busy,
    required this.onSetActive,
    required this.onEdit,
    required this.onAdd,
    this.onCtSettings,
  });

  final List<ModbusProfile> profiles;
  final List<SourceConfig> sources;
  final String activeSourceId;
  final bool busy;
  final ValueChanged<SourceConfig> onSetActive;
  final ValueChanged<SourceConfig> onEdit;
  final VoidCallback onAdd;
  /// Called when the CT-settings button is tapped.
  /// Null means the button is not shown.
  final ValueChanged<SourceConfig>? onCtSettings;

  List<SourceConfig> get _picSources =>
      sources.where((s) => s.type == 'pic_uart').toList();

  List<SourceConfig> get _modbusSources =>
      sources.where((s) => s.type == 'modbus_rtu').toList();

  ModbusProfile? _profileFor(SourceConfig source) {
    final pid = source.profileId.isNotEmpty
        ? source.profileId
        : source.settings['profile_id']?.toString() ?? '';
    if (pid.isEmpty) return null;
    return profiles.where((p) => p.id == pid).firstOrNull;
  }

  String _profileLabel(SourceConfig source) {
    final pid = source.profileId.isNotEmpty
        ? source.profileId
        : source.settings['profile_id']?.toString() ?? '';
    if (pid.isEmpty) return '';

    final profile = profiles.where((p) => p.id == pid).firstOrNull;
    if (profile == null) return pid;

    final key = source.sourceKey.isNotEmpty
        ? source.sourceKey
        : source.settings['source_key']?.toString() ?? '';

    if (key.isNotEmpty && profile.hasVariants) {
      return '${profile.displayLabel} · ${profile.variantLabel(key)}';
    }
    return profile.displayLabel;
  }

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return _EmptyState(busy: busy, onAdd: onAdd);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ── PIC ───────────────────────────────────────────────────────
        if (_picSources.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.developer_board,
            title: 'PIC (collector)',
            count: _picSources.length,
          ),
          ..._picSources.map(
            (s) => _SourceCard(
              source: s,
              subtitle: 'UART · ${s.settings['port'] ?? ''}',
              active: s.id == activeSourceId,
              busy: busy,
              onSetActive: () => onSetActive(s),
              onEdit: () => onEdit(s),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ── Modbus ────────────────────────────────────────────────────
        if (_modbusSources.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.cable,
            title: 'Modbus meters',
            count: _modbusSources.length,
          ),
          ..._modbusSources.map((s) {
            final profile = _profileFor(s);
            final hasCt = profile?.hasCtRegisters ?? false;
            return _SourceCard(
              source: s,
              subtitle: _profileLabel(s),
              active: s.id == activeSourceId,
              busy: busy,
              onSetActive: () => onSetActive(s),
              onEdit: () => onEdit(s),
              onCtSettings:
                  (hasCt && onCtSettings != null) ? () => onCtSettings!(s) : null,
            );
          }),
          const SizedBox(height: 8),
        ],

        // ── Add button ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: OutlinedButton.icon(
            onPressed: busy ? null : onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add source'),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.busy, required this.onAdd});

  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.electrical_services_outlined,
              size: 48,
              color: cs.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No sources configured',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Add a meter source to get started',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: busy ? null : onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add source'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style:
                Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Source card ───────────────────────────────────────────────────────────────

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.subtitle,
    required this.active,
    required this.busy,
    required this.onSetActive,
    required this.onEdit,
    this.onCtSettings,
  });

  final SourceConfig source;
  final String subtitle;
  final bool active;
  final bool busy;
  final VoidCallback onSetActive;
  final VoidCallback onEdit;
  final VoidCallback? onCtSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: Material(
        color: active
            ? primary.withValues(alpha: 0.08)
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: busy ? null : onSetActive,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: active ? primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              children: [
                Icon(
                  active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: active ? primary : cs.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name.isNotEmpty ? source.name : source.id,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.normal,
                              color: active ? primary : null,
                            ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.outline),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!source.enabled)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _StatusChip(
                      label: 'Disabled',
                      color: cs.error,
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
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: busy ? null : onEdit,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
