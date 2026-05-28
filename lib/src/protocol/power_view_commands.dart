import 'dart:convert';

import '../models/alarm_config.dart';
import '../models/source_config.dart';

class PowerViewCommands {
  static String deviceInfo() => ':device_info';

  static String sourceList() => ':source_list';

  static String sourceSetActive(String sourceId) {
    return ':source_set_active $sourceId';
  }

  static String sourceRemove(String sourceId) {
    return ':source_remove $sourceId';
  }

  static String sourceAdd(SourceConfig source) {
    return ':source_add ${jsonEncode(source.toJson())}';
  }

  static String sourceUpdate(String sourceId, Map<String, dynamic> patch) {
    return ':source_update $sourceId ${jsonEncode(patch)}';
  }

  static String sourceTest(String sourceId) {
    return ':source_test $sourceId';
  }

  static String modbusProfileList() => ':modbus_profile_list';

  // ── CT commands ─────────────────────────────────────────────────────────────

  /// Read CT configuration registers from the active Modbus source.
  static String ctGet(String sourceId) => ':ct_get $sourceId';

  /// Write CT configuration registers to the active Modbus source.
  static String ctSet(String sourceId, Map<String, dynamic> values) =>
      ':ct_set $sourceId ${jsonEncode(values)}';

  static String meterSnapshot() => ':meter_snapshot';

  static String dashboardList() => ':dashboard_list';

  static String dashboardSet(int index) => ':dashboard_set $index';

  // ── Energy logs (read from Pi's SPI flash) ─────────────────────────────────

  /// Last [count] hourly kWh entries (oldest → newest).
  static String logKwhHour({int count = 24}) => ':log_kwh_hour $count';

  /// Last [count] daily kWh entries.
  static String logKwhDay({int count = 30}) => ':log_kwh_day $count';

  /// Last [count] monthly kWh entries.
  static String logKwhMonth({int count = 12}) => ':log_kwh_month $count';

  // ── Alarm commands ──────────────────────────────────────────────────────────

  static String alarmList() => ':alarm_list';

  static String alarmAdd(AlarmConfig alarm) =>
      ':alarm_add ${jsonEncode(alarm.toJson())}';

  static String alarmUpdate(String id, Map<String, dynamic> patch) =>
      ':alarm_update $id ${jsonEncode(patch)}';

  static String alarmRemove(String id) => ':alarm_remove $id';

  static String alarmClear(String id) => ':alarm_clear $id';

  static String alarmClearAll() => ':alarm_clear_all';

  static String alarmStates() => ':alarm_states';

  static String alarmHistory() => ':alarm_history';

  static String alarmHistoryMarkSeen() => ':alarm_history_mark_seen';

  static String alarmHistoryClear() => ':alarm_history_clear';

  // ── Update commands ─────────────────────────────────────────────────────────

  static String updateCheck() => ':update_check';

  static String updateStatus() => ':update_status';

  static String updateCancel() => ':update_cancel';

  static String updatePrepareUpload(String pin) =>
      ':update_prepare_upload ${jsonEncode({"pin": pin})}';

  static String updateFromUrl(String pin, String url) =>
      ':update_from_url ${jsonEncode({"pin": pin, "url": url})}';

  static String updateRollback(String pin) =>
      ':update_rollback ${jsonEncode({"pin": pin})}';

  static String updateSetPin(String currentPin, String newPin) =>
      ':update_set_pin ${jsonEncode({"current_pin": currentPin, "new_pin": newPin})}';

  // ── Dashboard config ────────────────────────────────────────────────────────

  static String dashboardConfigGet(int index) => ':dashboard_config_get $index';

  static String dashboardConfigSet(
    int index,
    Map<String, String> slots,
    Map<String, String> labels,
  ) =>
      ':dashboard_config_set $index ${jsonEncode({"slots": slots, "labels": labels})}';

  static String dashboardConfigReset(int index) => ':dashboard_config_reset $index';

  static String dashboardFieldCatalog() => ':dashboard_field_catalog';
}
