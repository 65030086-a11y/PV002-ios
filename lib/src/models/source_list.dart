import 'source_config.dart';

class SourceList {
  SourceList({
    required this.sources,
    required this.activeSourceId,
  });

  final List<SourceConfig> sources;
  final String activeSourceId;

  factory SourceList.empty() {
    return SourceList(sources: const [], activeSourceId: '');
  }

  factory SourceList.fromJson(Map<String, dynamic> json) {
    final sourceItems = json['sources'] as List? ?? const [];

    return SourceList(
      sources: sourceItems
          .map((item) => SourceConfig.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      activeSourceId: json['active_source_id'] as String? ?? '',
    );
  }
}
