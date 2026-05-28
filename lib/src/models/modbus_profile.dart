class ModbusProfile {
  ModbusProfile({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.readonly,
    required this.registers,
    this.sources = const {},
    this.defaultSource = '',
    this.ctRegisters = const {},
  });

  final String id;
  final String name;
  final String brand;
  final String model;
  final bool readonly;
  final Map<String, dynamic> registers;
  final Map<String, dynamic> sources;
  final String defaultSource;

  /// CT configuration registers on the meter device.
  /// Keys are field names (e.g. "ct_primary"), values are register specs.
  /// Empty map means this meter does not expose CT registers.
  final Map<String, dynamic> ctRegisters;

  bool get hasCtRegisters => ctRegisters.isNotEmpty;

  /// Human-readable label for a CT register key.
  /// Uses "label" from the spec if present, otherwise capitalises the key.
  String ctLabel(String key) {
    final spec = ctRegisters[key];
    if (spec is Map && (spec['label'] as String? ?? '').isNotEmpty) {
      return spec['label'] as String;
    }
    return key.replaceAll('_', ' ').replaceFirstMapped(
          RegExp(r'^.'),
          (m) => m.group(0)!.toUpperCase(),
        );
  }

  factory ModbusProfile.fromJson(Map<String, dynamic> json) {
    return ModbusProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      model: json['model'] as String? ?? '',
      readonly: json['readonly'] as bool? ?? false,
      registers: Map<String, dynamic>.from(
        json['registers'] as Map? ?? const <String, dynamic>{},
      ),
      sources: Map<String, dynamic>.from(
        json['sources'] as Map? ?? const <String, dynamic>{},
      ),
      defaultSource: json['default_source'] as String? ?? '',
      ctRegisters: Map<String, dynamic>.from(
        json['ct_registers'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }

  List<String> get availableSources => sources.keys.toList();

  bool get hasVariants => sources.isNotEmpty;

  String get displayLabel {
    if (name.isNotEmpty) {
      return name;
    }
    if (brand.isNotEmpty && model.isNotEmpty) {
      return '$brand $model';
    }
    return id;
  }

  String resolveDefaultSourceKey() {
    if (defaultSource.isNotEmpty && sources.containsKey(defaultSource)) {
      return defaultSource;
    }
    if (sources.isEmpty) {
      return '';
    }
    return sources.keys.first;
  }

  String variantLabel(String key) {
    final full = getSourceName(key);
    if (full == null || full.isEmpty) {
      return _shortGroupLabel(key);
    }

    // Prefer compact "Group A" style when name is long.
    final short = _shortGroupLabel(key);
    if (full.length > 40) {
      return short;
    }
    return full;
  }

  String _shortGroupLabel(String key) {
    switch (key) {
      case 'group_a':
        return 'Group A';
      case 'group_b':
        return 'Group B';
      case 'group_c':
        return 'Group C';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  String? getSourceName(String key) {
    final source = sources[key] as Map?;
    return source?['name'] as String?;
  }
}
