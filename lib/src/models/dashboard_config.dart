class FieldCatalogEntry {
  final String key;
  final String label;
  final String unit;

  const FieldCatalogEntry({
    required this.key,
    required this.label,
    required this.unit,
  });

  factory FieldCatalogEntry.fromJson(String key, Map<String, dynamic> json) {
    return FieldCatalogEntry(
      key:   key,
      label: json['label']?.toString() ?? key,
      unit:  json['unit']?.toString()  ?? '',
    );
  }
}

class DashboardConfig {
  final int index;

  /// Ordered list of X-slot names the user may configure (e.g. ["X10", "X20"]).
  final List<String> schemaSlots;

  /// Ordered list of Text_N slot names the user may edit.
  final List<String> schemaLabels;

  /// Current mapping: slot name → field key (e.g. "X10" → "_total_active_power_kw").
  final Map<String, String> slots;

  /// Current text label values (e.g. "Text_1" → "Power").
  final Map<String, String> labels;

  const DashboardConfig({
    required this.index,
    required this.schemaSlots,
    required this.schemaLabels,
    required this.slots,
    required this.labels,
  });

  factory DashboardConfig.fromJson(Map<String, dynamic> json) {
    final schema = json['schema'] as Map<String, dynamic>? ?? {};
    final config = json['config'] as Map<String, dynamic>? ?? {};

    List<String> toStringList(dynamic raw) =>
        (raw as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    Map<String, String> toStringMap(dynamic raw) {
      final m = raw as Map<String, dynamic>? ?? {};
      return m.map((k, v) => MapEntry(k, v.toString()));
    }

    return DashboardConfig(
      index:        (json['index'] as num?)?.toInt() ?? 0,
      schemaSlots:  toStringList(schema['slots']),
      schemaLabels: toStringList(schema['labels']),
      slots:        toStringMap(config['slots']),
      labels:       toStringMap(config['labels']),
    );
  }
}
