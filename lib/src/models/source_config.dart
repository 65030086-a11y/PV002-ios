class SourceConfig {
  SourceConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.enabled,
    required this.settings,
    this.profileId = '',
    this.sourceKey = '',
  });

  final String id;
  final String name;
  final String type;
  final bool enabled;
  final Map<String, dynamic> settings;
  final String profileId;
  final String sourceKey;

  factory SourceConfig.fromJson(Map<String, dynamic> json) {
    return SourceConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      settings: Map<String, dynamic>.from(
        json['settings'] as Map? ?? const <String, dynamic>{},
      ),
      profileId: json['profile_id'] as String? ?? '',
      sourceKey: json['source_key'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'enabled': enabled,
      'settings': settings,
      'profile_id': profileId,
      'source_key': sourceKey,
    };
  }
}
