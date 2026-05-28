class LineData {
  const LineData({
    required this.voltage,
    required this.current,
    required this.activePowerKw,
    required this.reactivePowerKvar,
    required this.apparentPowerKva,
    required this.powerFactor,
    required this.voltageTHD,
    required this.currentTHD,
  });

  final double voltage;
  final double current;
  final double activePowerKw;
  final double reactivePowerKvar;
  final double apparentPowerKva;
  final double powerFactor;
  final double voltageTHD;
  final double currentTHD;

  factory LineData.fromJson(Map<String, dynamic> j) => LineData(
        voltage: _d(j['voltage']),
        current: _d(j['current']),
        activePowerKw: _d(j['active_power_kw']),
        reactivePowerKvar: _d(j['reactive_power_kvar']),
        apparentPowerKva: _d(j['apparent_power_kva']),
        powerFactor: _d(j['power_factor']),
        voltageTHD: _d(j['voltage_thd']),
        currentTHD: _d(j['current_thd']),
      );

  static LineData get zero => const LineData(
        voltage: 0,
        current: 0,
        activePowerKw: 0,
        reactivePowerKvar: 0,
        apparentPowerKva: 0,
        powerFactor: 0,
        voltageTHD: 0,
        currentTHD: 0,
      );
}

class TotalData {
  const TotalData({
    required this.frequency,
    required this.activePowerKw,
    required this.reactivePowerKvar,
    required this.apparentPowerKva,
    required this.powerFactor,
    required this.kwhImport,
    required this.kvarhImport,
    required this.kvah,
    required this.temperature,
  });

  final double frequency;
  final double activePowerKw;
  final double reactivePowerKvar;
  final double apparentPowerKva;
  final double powerFactor;
  final double kwhImport;
  final double kvarhImport;
  final double kvah;
  final double temperature;

  factory TotalData.fromJson(Map<String, dynamic> j) => TotalData(
        frequency: _d(j['frequency']),
        activePowerKw: _d(j['active_power_kw']),
        reactivePowerKvar: _d(j['reactive_power_kvar']),
        apparentPowerKva: _d(j['apparent_power_kva']),
        powerFactor: _d(j['power_factor']),
        kwhImport: _d(j['kwh_import']),
        kvarhImport: _d(j['kvarh_import']),
        kvah: _d(j['kvah']),
        temperature: _d(j['temperature']),
      );

  static TotalData get zero => const TotalData(
        frequency: 0,
        activePowerKw: 0,
        reactivePowerKvar: 0,
        apparentPowerKva: 0,
        powerFactor: 0,
        kwhImport: 0,
        kvarhImport: 0,
        kvah: 0,
        temperature: 0,
      );
}

class MeterSnapshot {
  const MeterSnapshot({
    required this.isFoundData,
    required this.startClearWhtTime,
    required this.lines,
    required this.total,
  });

  final bool isFoundData;
  final int startClearWhtTime;
  final List<LineData> lines; // [L1, L2, L3]
  final TotalData total;

  factory MeterSnapshot.fromJson(Map<String, dynamic> j) {
    final rawLines = j['lines'] as List<dynamic>? ?? [];
    final lines = rawLines
        .map((e) => LineData.fromJson(e as Map<String, dynamic>))
        .toList();
    while (lines.length < 3) {
      lines.add(LineData.zero);
    }

    return MeterSnapshot(
      isFoundData: j['is_found_data'] as bool? ?? false,
      startClearWhtTime: (j['start_clear_wht_time'] as num?)?.toInt() ?? 0,
      lines: lines,
      total: TotalData.fromJson(j['total'] as Map<String, dynamic>? ?? {}),
    );
  }

  static MeterSnapshot get empty => MeterSnapshot(
        isFoundData: false,
        startClearWhtTime: 0,
        lines: [LineData.zero, LineData.zero, LineData.zero],
        total: TotalData.zero,
      );
}

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
