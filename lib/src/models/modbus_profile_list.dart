import 'modbus_profile.dart';

class ModbusProfileList {
  ModbusProfileList({required this.profiles});

  final List<ModbusProfile> profiles;

  factory ModbusProfileList.empty() {
    return ModbusProfileList(profiles: const []);
  }

  /// Parses the Pi's `:modbus_profile_list` response.
  ///
  /// Expected JSON shape: `{"profiles": [ {...}, ... ]}`
  factory ModbusProfileList.fromJson(Map<String, dynamic> json) {
    final items = json['profiles'] as List? ?? const [];
    return ModbusProfileList(
      profiles: items
          .map((item) => ModbusProfile.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((p) => p.id.isNotEmpty)
          .toList(),
    );
  }
}
