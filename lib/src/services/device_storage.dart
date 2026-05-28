import 'package:shared_preferences/shared_preferences.dart';

/// Persisted info about the **single** PowerView device the app remembers.
///
/// Per the design in `connect.md` §8, the app stores at most one device
/// at a time — re-running the search overwrites whatever was there.
class SavedDevice {
  const SavedDevice({
    required this.host,
    required this.port,
    required this.name,
  });

  final String host;
  final int    port;
  final String name;

  Map<String, Object?> toJson() => {
        'host': host,
        'port': port,
        'name': name,
      };

  static SavedDevice? fromJson(Map<String, Object?> map) {
    final host = map['host'];
    final port = map['port'];
    final name = map['name'];
    if (host is! String || host.isEmpty) return null;
    if (port is! int) return null;
    return SavedDevice(
      host: host,
      port: port,
      name: name is String ? name : host,
    );
  }
}

/// Thin wrapper around SharedPreferences for the saved device.
class DeviceStorage {
  static const _kHost = 'pv.device.host';
  static const _kPort = 'pv.device.port';
  static const _kName = 'pv.device.name';

  /// Returns the saved device, or null if none has ever been saved.
  static Future<SavedDevice?> load() async {
    final p = await SharedPreferences.getInstance();
    final host = p.getString(_kHost);
    final port = p.getInt(_kPort);
    if (host == null || host.isEmpty || port == null) return null;
    return SavedDevice(
      host: host,
      port: port,
      name: p.getString(_kName) ?? host,
    );
  }

  /// Persist the device (overwrites any previous value).
  static Future<void> save(SavedDevice d) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHost, d.host);
    await p.setInt(_kPort, d.port);
    await p.setString(_kName, d.name);
  }

  /// Forget the saved device (used by Disconnect → "forget" action).
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kHost);
    await p.remove(_kPort);
    await p.remove(_kName);
  }
}
