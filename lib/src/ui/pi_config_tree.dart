import 'package:flutter/material.dart';

import '../models/modbus_profile.dart';
import '../models/source_config.dart';

/// Tree of meter types and configured sources loaded from Raspberry Pi JSON.
class PiConfigTree extends StatelessWidget {
  const PiConfigTree({
    super.key,
    required this.profiles,
    required this.sources,
    required this.activeSourceId,
    required this.busy,
    required this.onSetActive,
    required this.onEdit,
  });

  final List<ModbusProfile> profiles;
  final List<SourceConfig> sources;
  final String activeSourceId;
  final bool busy;
  final ValueChanged<SourceConfig> onSetActive;
  final ValueChanged<SourceConfig> onEdit;

  List<SourceConfig> get _picSources =>
      sources.where((source) => source.type == 'pic_uart').toList();

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Connect to Raspberry Pi to load\nconfig from JSON files',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SectionLabel(title: 'PIC (collector)'),
        if (_picSources.isEmpty)
          const ListTile(
            dense: true,
            subtitle: Text(
              'Not configured — define pic_uart in config/sources.json on Pi',
            ),
          )
        else
          ..._picSources.map(
            (source) => _SourceTile(
              source: source,
              active: source.id == activeSourceId,
              busy: busy,
              onSetActive: () => onSetActive(source),
              onEdit: () => onEdit(source),
            ),
          ),
        const Divider(height: 1),
        _SectionLabel(title: 'Modbus meters (from Pi profile JSON)'),
        ...profiles.map(
          (profile) => _ProfileSection(
            profile: profile,
            sources: sources,
            activeSourceId: activeSourceId,
            busy: busy,
            onSetActive: onSetActive,
            onEdit: onEdit,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.profile,
    required this.sources,
    required this.activeSourceId,
    required this.busy,
    required this.onSetActive,
    required this.onEdit,
  });

  final ModbusProfile profile;
  final List<SourceConfig> sources;
  final String activeSourceId;
  final bool busy;
  final ValueChanged<SourceConfig> onSetActive;
  final ValueChanged<SourceConfig> onEdit;

  List<SourceConfig> _matching(String sourceKey) {
    return sources.where((source) {
      if (source.type != 'modbus_rtu') {
        return false;
      }
      return _sourceMatchesProfile(source, profile.id, sourceKey);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!profile.hasVariants) {
      final matched = _matching('');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            title: Text(profile.displayLabel),
          ),
          if (matched.isEmpty)
            const _NotConfiguredTile()
          else
            ...matched.map(
              (source) => _SourceTile(
                source: source,
                active: source.id == activeSourceId,
                busy: busy,
                indent: 16,
                onSetActive: () => onSetActive(source),
                onEdit: () => onEdit(source),
              ),
            ),
        ],
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>(profile.id),
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: EdgeInsets.zero,
        title: Text(profile.displayLabel),
        children: profile.availableSources.map((key) {
          final matched = _matching(key);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 24, right: 8),
                title: Text(profile.variantLabel(key)),
              ),
              if (matched.isEmpty)
                const _NotConfiguredTile(indent: 40)
              else
                ...matched.map(
                  (source) => _SourceTile(
                    source: source,
                    active: source.id == activeSourceId,
                    busy: busy,
                    indent: 40,
                    onSetActive: () => onSetActive(source),
                    onEdit: () => onEdit(source),
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _NotConfiguredTile extends StatelessWidget {
  const _NotConfiguredTile({this.indent = 24});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: indent, right: 12),
      subtitle: Text(
        'Not configured — add modbus_rtu in config/sources.json on Pi',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.active,
    required this.busy,
    required this.onSetActive,
    required this.onEdit,
    this.indent = 0,
  });

  final SourceConfig source;
  final bool active;
  final bool busy;
  final VoidCallback onSetActive;
  final VoidCallback onEdit;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: indent + 8, right: 4),
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_off,
        color: active ? colorScheme.primary : null,
        size: 20,
      ),
      title: Text(source.name),
      subtitle: Text(source.id),
      selected: active,
      enabled: !busy,
      onTap: busy ? null : onSetActive,
      trailing: IconButton(
        tooltip: 'Edit (saved to sources.json on Pi)',
        icon: const Icon(Icons.edit_outlined, size: 20),
        onPressed: busy ? null : onEdit,
      ),
    );
  }
}

bool _sourceMatchesProfile(
  SourceConfig source,
  String profileId,
  String sourceKey,
) {
  final pid = source.profileId.isNotEmpty
      ? source.profileId
      : source.settings['profile_id']?.toString() ?? '';

  if (pid != profileId) {
    return false;
  }

  if (sourceKey.isEmpty) {
    return true;
  }

  final key = source.sourceKey.isNotEmpty
      ? source.sourceKey
      : source.settings['source_key']?.toString() ?? '';

  return key == sourceKey;
}
