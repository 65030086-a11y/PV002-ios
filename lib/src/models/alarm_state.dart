import 'alarm_config.dart';

// ---------------------------------------------------------------------------
// Runtime state for a single alarm (from the Pi evaluator)
// ---------------------------------------------------------------------------

class AlarmState {
  const AlarmState({
    required this.configId,
    required this.state,
    this.pendingSince,
    this.activeSince,
    this.autoClearAt,
    this.currentValue,
  });

  final String configId;
  final String state;            // 'normal' | 'pending' | 'active'
  final DateTime? pendingSince;
  final DateTime? activeSince;
  final DateTime? autoClearAt;
  final double? currentValue;

  bool get isNormal  => state == 'normal';
  bool get isPending => state == 'pending';
  bool get isActive  => state == 'active';

  factory AlarmState.fromJson(Map<String, dynamic> j) => AlarmState(
        configId:     j['config_id'] as String? ?? '',
        state:        j['state'] as String? ?? 'normal',
        pendingSince: _dt(j['pending_since']),
        activeSince:  _dt(j['active_since']),
        autoClearAt:  _dt(j['auto_clear_at']),
        currentValue: (j['current_value'] as num?)?.toDouble(),
      );

  static DateTime? _dt(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}

// ---------------------------------------------------------------------------
// Combined list returned by :alarm_list
// ---------------------------------------------------------------------------

class AlarmList {
  const AlarmList({
    required this.alarms,
    required this.states,
    this.unseenHistory = 0,
  });

  final List<AlarmConfig> alarms;
  final List<AlarmState>  states;
  /// Number of history entries not yet seen in the app (from :alarm_states).
  final int unseenHistory;

  factory AlarmList.empty() =>
      const AlarmList(alarms: [], states: []);

  factory AlarmList.fromJson(Map<String, dynamic> j) {
    final rawAlarms  = j['alarms']  as List<dynamic>? ?? [];
    final rawStates  = j['states']  as List<dynamic>? ?? [];
    return AlarmList(
      alarms: rawAlarms.map((e) => AlarmConfig.fromJson(e as Map<String, dynamic>)).toList(),
      states: rawStates.map((e) => AlarmState.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Rebuild with updated states (and optionally unseen count) from a poll.
  AlarmList withStates(List<AlarmState> newStates, {int? unseen}) =>
      AlarmList(
        alarms:         alarms,
        states:         newStates,
        unseenHistory:  unseen ?? unseenHistory,
      );

  /// State for a given alarm config id, or `null` if not yet evaluated.
  AlarmState? stateFor(String configId) {
    for (final s in states) {
      if (s.configId == configId) return s;
    }
    return null;
  }

  int get activeCount  => states.where((s) => s.isActive).length;
  int get pendingCount => states.where((s) => s.isPending).length;
  bool get hasUnseenHistory => unseenHistory > 0;
}
