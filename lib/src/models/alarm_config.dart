/// All measurable parameters that can be monitored by an alarm rule.
/// The string values match the keys used by the Pi evaluator.
class AlarmParameter {
  AlarmParameter._();

  // ── Voltage ────────────────────────────────────────────────────────────────
  static const voltageL1 = 'voltage_L1';
  static const voltageL2 = 'voltage_L2';
  static const voltageL3 = 'voltage_L3';

  // ── Current ────────────────────────────────────────────────────────────────
  static const currentL1        = 'current_L1';
  static const currentL2        = 'current_L2';
  static const currentL3        = 'current_L3';
  static const currentUnbalance = 'current_unbalance';

  // ── Active power ───────────────────────────────────────────────────────────
  static const activePowerL1    = 'active_power_L1';
  static const activePowerL2    = 'active_power_L2';
  static const activePowerL3    = 'active_power_L3';
  static const activePowerTotal = 'active_power_total';

  // ── Power factor ───────────────────────────────────────────────────────────
  static const powerFactorL1    = 'power_factor_L1';
  static const powerFactorL2    = 'power_factor_L2';
  static const powerFactorL3    = 'power_factor_L3';
  static const powerFactorTotal = 'power_factor_total';

  // ── Energy / counter (setpoint only) ──────────────────────────────────────
  static const energyKwh = 'energy_kwh';
  static const counter   = 'counter';

  // ── THD voltage ────────────────────────────────────────────────────────────
  static const thdVoltageL1 = 'thd_voltage_L1';
  static const thdVoltageL2 = 'thd_voltage_L2';
  static const thdVoltageL3 = 'thd_voltage_L3';

  // ── THD current ────────────────────────────────────────────────────────────
  static const thdCurrentL1 = 'thd_current_L1';
  static const thdCurrentL2 = 'thd_current_L2';
  static const thdCurrentL3 = 'thd_current_L3';

  // ── Frequency ──────────────────────────────────────────────────────────────
  static const frequency = 'frequency';

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Human-readable display name.
  static String label(String p) => _labels[p] ?? p;

  /// SI unit string (empty for dimensionless).
  static String unit(String p) => _units[p] ?? '';

  /// `true` for parameters that only support the 'setpoint' condition.
  static bool isSetpointOnly(String p) => _setpointOnly.contains(p);

  /// `true` for parameters where 'low' condition is not meaningful.
  static bool isHighOnly(String p) => _highOnly.contains(p);

  static const _setpointOnly = {energyKwh, counter};
  static const _highOnly     = {currentUnbalance};

  static const _labels = <String, String>{
    voltageL1: 'Voltage L1',         voltageL2: 'Voltage L2',
    voltageL3: 'Voltage L3',
    currentL1: 'Current L1',         currentL2: 'Current L2',
    currentL3: 'Current L3',         currentUnbalance: 'Current Unbalance',
    activePowerL1: 'Active Power L1', activePowerL2: 'Active Power L2',
    activePowerL3: 'Active Power L3', activePowerTotal: 'Active Power (Total)',
    powerFactorL1: 'Power Factor L1', powerFactorL2: 'Power Factor L2',
    powerFactorL3: 'Power Factor L3', powerFactorTotal: 'Power Factor (Total)',
    energyKwh: 'Energy',              counter: 'Counter',
    thdVoltageL1: 'THDv L1',          thdVoltageL2: 'THDv L2',
    thdVoltageL3: 'THDv L3',
    thdCurrentL1: 'THDi L1',          thdCurrentL2: 'THDi L2',
    thdCurrentL3: 'THDi L3',
    frequency: 'Frequency',
  };

  static const _units = <String, String>{
    voltageL1: 'V',           voltageL2: 'V',         voltageL3: 'V',
    currentL1: 'A',           currentL2: 'A',         currentL3: 'A',
    currentUnbalance: '%',
    activePowerL1: 'kW',      activePowerL2: 'kW',    activePowerL3: 'kW',
    activePowerTotal: 'kW',
    powerFactorL1: '',        powerFactorL2: '',       powerFactorL3: '',
    powerFactorTotal: '',
    energyKwh: 'kWh',         counter: '',
    thdVoltageL1: '%',        thdVoltageL2: '%',       thdVoltageL3: '%',
    thdCurrentL1: '%',        thdCurrentL2: '%',       thdCurrentL3: '%',
    frequency: 'Hz',
  };

  /// All parameters grouped for display in the editor picker.
  static const groups = <_ParameterGroup>[
    _ParameterGroup('Voltage', [voltageL1, voltageL2, voltageL3]),
    _ParameterGroup('Current', [currentL1, currentL2, currentL3, currentUnbalance]),
    _ParameterGroup('Active Power',
        [activePowerL1, activePowerL2, activePowerL3, activePowerTotal]),
    _ParameterGroup('Power Factor',
        [powerFactorL1, powerFactorL2, powerFactorL3, powerFactorTotal]),
    _ParameterGroup('Energy', [energyKwh]),
    _ParameterGroup('Counter', [counter]),
    _ParameterGroup('THD Voltage', [thdVoltageL1, thdVoltageL2, thdVoltageL3]),
    _ParameterGroup('THD Current', [thdCurrentL1, thdCurrentL2, thdCurrentL3]),
    _ParameterGroup('Frequency', [frequency]),
  ];
}

class _ParameterGroup {
  const _ParameterGroup(this.name, this.parameters);
  final String name;
  final List<String> parameters;
}

// ---------------------------------------------------------------------------
// Alarm condition
// ---------------------------------------------------------------------------

class AlarmCondition {
  AlarmCondition._();

  static const high     = 'high';      // value > threshold
  static const low      = 'low';       // value < threshold
  static const setpoint = 'setpoint';  // value >= threshold (one-shot)

  static String label(String c) {
    switch (c) {
      case high:     return 'High (Over)';
      case low:      return 'Low (Under)';
      case setpoint: return 'Setpoint';
      default:       return c;
    }
  }

  /// Valid conditions for a given parameter.
  static List<String> allowedFor(String parameter) {
    if (AlarmParameter.isSetpointOnly(parameter)) return [setpoint];
    if (AlarmParameter.isHighOnly(parameter))     return [high];
    return [high, low];
  }
}

// ---------------------------------------------------------------------------
// AlarmConfig model
// ---------------------------------------------------------------------------

class AlarmConfig {
  const AlarmConfig({
    required this.id,
    required this.label,
    required this.parameter,
    required this.condition,
    required this.threshold,
    this.hysteresis = 0.0,
    this.enabled = true,
    this.triggerDelaySec = 0,
    this.autoClearDelaySec = 0,
  });

  final String id;
  final String label;
  final String parameter;
  final String condition;
  final double threshold;
  final double hysteresis;
  final bool enabled;
  final int triggerDelaySec;
  final int autoClearDelaySec;

  factory AlarmConfig.fromJson(Map<String, dynamic> j) => AlarmConfig(
        id:                j['id'] as String? ?? '',
        label:             j['label'] as String? ?? '',
        parameter:         j['parameter'] as String? ?? '',
        condition:         j['condition'] as String? ?? AlarmCondition.high,
        threshold:         (j['threshold'] as num?)?.toDouble() ?? 0.0,
        hysteresis:        (j['hysteresis'] as num?)?.toDouble() ?? 0.0,
        enabled:           j['enabled'] as bool? ?? true,
        triggerDelaySec:   (j['trigger_delay_sec'] as num?)?.toInt() ?? 0,
        autoClearDelaySec: (j['auto_clear_delay_sec'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id':                   id,
        'label':                label,
        'parameter':            parameter,
        'condition':            condition,
        'threshold':            threshold,
        'hysteresis':           hysteresis,
        'enabled':              enabled,
        'trigger_delay_sec':    triggerDelaySec,
        'auto_clear_delay_sec': autoClearDelaySec,
      };

  AlarmConfig copyWith({
    String? id, String? label, String? parameter, String? condition,
    double? threshold, double? hysteresis, bool? enabled,
    int? triggerDelaySec, int? autoClearDelaySec,
  }) =>
      AlarmConfig(
        id:                id                ?? this.id,
        label:             label             ?? this.label,
        parameter:         parameter         ?? this.parameter,
        condition:         condition         ?? this.condition,
        threshold:         threshold         ?? this.threshold,
        hysteresis:        hysteresis        ?? this.hysteresis,
        enabled:           enabled           ?? this.enabled,
        triggerDelaySec:   triggerDelaySec   ?? this.triggerDelaySec,
        autoClearDelaySec: autoClearDelaySec ?? this.autoClearDelaySec,
      );
}
