/// Data class holding device information fetched from the Pi for the About page.
class PiAboutInfo {
  const PiAboutInfo({
    required this.meterVersion,
    required this.meterSerial,
    required this.meterProduct,
    required this.meterModel,
    this.collectorName,
    this.collectorType,
    this.collectorEnabled,
  });

  /// Software version reported by the Pi (`:info 99` → `version`).
  final String meterVersion;

  /// Serial number stored on the Pi (`:info 99` → `serial`).
  final String meterSerial;

  /// Product name (`:info 99` → `product`, e.g. `"PowerView"`).
  final String meterProduct;

  /// Model identifier (`:info 99` → `model`, e.g. `"A1"`).
  final String meterModel;

  /// Display name of the active data source, or `null` when no source is set.
  final String? collectorName;

  /// Internal type key of the active source (e.g. `pic_uart`, `modbus_rtu`).
  final String? collectorType;

  /// Whether the active source is enabled, or `null` when no source is set.
  final bool? collectorEnabled;

  /// `true` when an active data source was found.
  bool get hasCollector => collectorName != null;
}
