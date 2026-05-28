/// One kWh sample read from the Pi's flash log.
///
/// The Pi sends each entry as `{"ts": <unix-time>, "kwh": <float>}`.
class EnergyEntry {
  const EnergyEntry({required this.timestamp, required this.kwh});

  /// Unix timestamp marking the start of the period this entry covers.
  final int timestamp;

  /// kWh consumed during the period.
  final double kwh;

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

  static EnergyEntry fromJson(Map<String, Object?> map) {
    final ts  = map['ts']  as num?;
    final kwh = map['kwh'] as num?;
    return EnergyEntry(
      timestamp: ts?.toInt()    ?? 0,
      kwh:       kwh?.toDouble() ?? 0.0,
    );
  }

  @override
  String toString() => 'EnergyEntry($dateTime, ${kwh.toStringAsFixed(4)} kWh)';
}

/// Container returned by `:log_kwh_*` commands.
class EnergyLog {
  const EnergyLog({required this.entries, this.error});

  /// Oldest → newest.
  final List<EnergyEntry> entries;

  /// Non-null when the Pi reported an error reading the flash log
  /// (e.g. "no_flash" on a Windows dev build).
  final String? error;

  bool   get isEmpty   => entries.isEmpty;
  bool   get hasData   => entries.isNotEmpty;
  double get totalKwh  => entries.fold(0.0, (sum, e) => sum + e.kwh);

  static EnergyLog fromJson(Map<String, Object?> map) {
    final raw = map['entries'] as List? ?? const [];
    return EnergyLog(
      entries: raw
          .whereType<Map>()
          .map((e) => EnergyEntry.fromJson(Map<String, Object?>.from(e)))
          .toList(),
      error: map['error'] as String?,
    );
  }

  static const EnergyLog empty = EnergyLog(entries: []);
}
