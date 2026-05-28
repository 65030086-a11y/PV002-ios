import 'package:flutter/material.dart';

import '../models/modbus_profile.dart';

/// Production-style meter type selector.
/// Displays brands as selectable cards; profiles with variants show
/// inline group chips once the brand card is tapped.
class MeterTypePicker extends StatelessWidget {
  const MeterTypePicker({
    super.key,
    required this.profiles,
    required this.busy,
    required this.picSelected,
    required this.selectedProfileId,
    required this.selectedSourceKey,
    required this.onSelectPic,
    required this.onSelectModbus,
    this.showPicOption = true,
  });

  final List<ModbusProfile> profiles;
  final bool busy;
  final bool picSelected;
  final bool showPicOption;
  final String selectedProfileId;
  final String selectedSourceKey;
  final VoidCallback onSelectPic;
  final void Function(String profileId, String sourceKey) onSelectModbus;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Loading meter profiles…'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (showPicOption)
          _BrandCard(
            icon: Icons.developer_board,
            title: 'PIC Collector',
            subtitle: 'Built-in serial collector',
            selected: picSelected,
            enabled: !busy,
            onTap: onSelectPic,
          ),
        ...profiles.map(
          (profile) => _ModbusBrandCard(
            profile: profile,
            busy: busy,
            picSelected: picSelected,
            selectedProfileId: selectedProfileId,
            selectedSourceKey: selectedSourceKey,
            onSelectModbus: onSelectModbus,
          ),
        ),
      ],
    );
  }
}

// ── Generic selectable brand card ─────────────────────────────────────────────

class _BrandCard extends StatelessWidget {
  const _BrandCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: selected ? primary.withValues(alpha: 0.08) : cs.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? primary : cs.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? primary.withValues(alpha: 0.12)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? primary : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: selected ? primary : null,
                            ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.outline,
                            ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 20, color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Modbus brand card (with optional variant chips) ───────────────────────────

class _ModbusBrandCard extends StatelessWidget {
  const _ModbusBrandCard({
    required this.profile,
    required this.busy,
    required this.picSelected,
    required this.selectedProfileId,
    required this.selectedSourceKey,
    required this.onSelectModbus,
  });

  final ModbusProfile profile;
  final bool busy;
  final bool picSelected;
  final String selectedProfileId;
  final String selectedSourceKey;
  final void Function(String profileId, String sourceKey) onSelectModbus;

  bool get _brandSelected =>
      !picSelected &&
      selectedProfileId == profile.id &&
      (!profile.hasVariants || selectedSourceKey.isNotEmpty);

  bool get _brandExpanded => !picSelected && selectedProfileId == profile.id;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: _brandSelected
            ? primary.withValues(alpha: 0.08)
            : _brandExpanded
                ? cs.surfaceContainerLow
                : cs.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: busy
              ? null
              : () {
                  if (!profile.hasVariants) {
                    onSelectModbus(profile.id, '');
                  } else {
                    // expand without selecting yet
                    final key = profile.resolveDefaultSourceKey();
                    onSelectModbus(profile.id, key);
                  }
                },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _brandSelected
                    ? primary
                    : _brandExpanded
                        ? primary.withValues(alpha: 0.4)
                        : cs.outlineVariant,
                width: _brandSelected ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _brandSelected
                            ? primary.withValues(alpha: 0.12)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.sensors,
                        size: 20,
                        color: _brandSelected ? primary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.displayLabel,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: _brandSelected ? primary : null,
                                ),
                          ),
                          if (profile.brand.isNotEmpty &&
                              profile.model.isNotEmpty)
                            Text(
                              '${profile.brand} · ${profile.model}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: cs.outline),
                            ),
                        ],
                      ),
                    ),
                    if (_brandSelected)
                      Icon(Icons.check_circle_rounded,
                          size: 20, color: primary),
                  ],
                ),
                // Variant chips shown when this brand is expanded
                if (profile.hasVariants && _brandExpanded) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: profile.availableSources.map((key) {
                      final selected =
                          _brandExpanded && selectedSourceKey == key;
                      return ChoiceChip(
                        label: Text(profile.variantLabel(key)),
                        selected: selected,
                        onSelected: busy
                            ? null
                            : (_) => onSelectModbus(profile.id, key),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
