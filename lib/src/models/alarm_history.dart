/// A single alarm trigger event stored in the history log.
class AlarmHistoryEntry {
  const AlarmHistoryEntry({
    required this.alarmId,
    required this.label,
    required this.parameter,
    required this.condition,
    required this.threshold,
    required this.triggeredAt,
    this.value,
  });

  final String   alarmId;
  final String   label;
  final String   parameter;
  final String   condition;
  final double   threshold;
  final double?  value;
  final DateTime triggeredAt;

  factory AlarmHistoryEntry.fromJson(Map<String, dynamic> json) {
    return AlarmHistoryEntry(
      alarmId:     json['alarm_id']  as String? ?? '',
      label:       json['label']     as String? ?? '',
      parameter:   json['parameter'] as String? ?? '',
      condition:   json['condition'] as String? ?? '',
      threshold:   (json['threshold'] as num?)?.toDouble() ?? 0.0,
      value:       (json['value']     as num?)?.toDouble(),
      triggeredAt: DateTime.parse(json['triggered_at'] as String),
    );
  }
}

/// Response wrapper returned by :alarm_history.
class AlarmHistoryList {
  const AlarmHistoryList({
    required this.entries,
    required this.total,
    required this.max,
    required this.unseen,
  });

  const AlarmHistoryList.empty()
      : entries = const [],
        total   = 0,
        max     = 100,
        unseen  = 0;

  final List<AlarmHistoryEntry> entries;   // newest first
  final int total;
  final int max;
  final int unseen;   // entries not yet seen in the app

  bool get isEmpty => entries.isEmpty;
  bool get hasUnseen => unseen > 0;

  factory AlarmHistoryList.fromJson(Map<String, dynamic> json) {
    final raw = json['entries'] as List<dynamic>? ?? [];
    return AlarmHistoryList(
      entries: raw
          .map((e) => AlarmHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      total:  (json['total']  as num?)?.toInt() ?? 0,
      max:    (json['max']    as num?)?.toInt() ?? 100,
      unseen: (json['unseen'] as num?)?.toInt() ?? 0,
    );
  }
}
