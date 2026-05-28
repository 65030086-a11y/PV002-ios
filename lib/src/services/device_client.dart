import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/alarm_config.dart';
import '../models/alarm_history.dart';
import '../models/dashboard_config.dart';
import '../models/alarm_state.dart';
import '../models/update_info.dart';
import '../models/dashboard_info.dart';
import '../models/energy_log.dart';
import '../models/meter_snapshot.dart';
import '../models/pi_about_info.dart';
import '../models/pi_settings.dart';
import '../models/source_config.dart';
import '../models/source_list.dart';
import '../models/modbus_profile_list.dart';
import '../protocol/device_response.dart';
import '../protocol/power_view_commands.dart';
import '../transport/app_transport.dart';
import '../transport/tcp_transport.dart';
import '../transport/usb_transport.dart';

enum ConnectionMode { tcp, usb }

/// Connection-aware device client.  Extends [ChangeNotifier] so any widget
/// can call `AnimatedBuilder(animation: client, ...)` (or `client.addListener`)
/// to react when the device connects, disconnects, or drops unexpectedly.
class DeviceClient extends ChangeNotifier {
  AppTransport? _transport;
  String? _lastHost;
  int?    _lastPort;
  ConnectionMode? _mode;

  bool             get isConnected => _transport?.isConnected ?? false;
  String?          get host        => _lastHost;
  int?             get port        => _lastPort;
  ConnectionMode?  get mode        => _mode;

  /// Base URL of the Pi's HTTP screen-share server (tcp_port + 1).
  String? get screenshotBaseUrl {
    if (_lastHost == null || _lastPort == null) return null;
    return 'http://$_lastHost:${_lastPort! + 1}';
  }

  Future<void> connectTcp({
    required String host,
    required int port,
  }) async {
    final transport = createTcpTransport(host: host, port: port);
    await transport.connect();
    // Wire the unexpected-disconnect hook BEFORE storing the reference
    // so a connection that drops mid-handshake is still reported.
    transport.onDisconnected = _handleTransportDropped;
    _transport = transport;
    _lastHost  = host;
    _lastPort  = port;
    _mode      = ConnectionMode.tcp;
    notifyListeners();
  }

  /// Re-establish the TCP connection using the last known host/port.
  Future<void> reconnect() async {
    if (_lastHost == null || _lastPort == null) {
      throw StateError('No previous connection to reconnect to');
    }
    await close();
    await connectTcp(host: _lastHost!, port: _lastPort!);
  }

  Future<void> connectUsb({required String portName}) async {
    final transport = UsbTransport(portName: portName);
    await transport.connect();
    transport.onDisconnected = _handleTransportDropped;
    _transport = transport;
    _lastHost  = null;
    _lastPort  = null;
    _lastPort  = null;
    _mode      = ConnectionMode.usb;
    notifyListeners();
  }

  Future<void> close() async {
    final t = _transport;
    _transport = null;
    _mode      = null;
    await t?.close();
    notifyListeners();
  }

  /// Called by the underlying transport when its socket dies on its own
  /// (peer hung up, network drop, etc).  Clears state and notifies the UI.
  void _handleTransportDropped() {
    if (_transport == null) return;
    debugPrint('DeviceClient: transport dropped');
    _transport = null;
    _mode      = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    final response = await _send(PowerViewCommands.deviceInfo());
    return response.payload;
  }

  Future<SourceList> listSources() async {
    final response = await _send(PowerViewCommands.sourceList());
    return SourceList.fromJson(response.payload);
  }

  Future<ModbusProfileList> listModbusProfiles() async {
    final response = await _send(
      PowerViewCommands.modbusProfileList(),
      timeout: const Duration(seconds: 10),
    );
    return ModbusProfileList.fromJson(response.payload);
  }

  Future<void> addSource(SourceConfig source) async {
    await _send(PowerViewCommands.sourceAdd(source));
  }

  Future<void> removeSource(String sourceId) async {
    await _send(PowerViewCommands.sourceRemove(sourceId));
  }

  Future<void> setActiveSource(String sourceId) async {
    await _send(PowerViewCommands.sourceSetActive(sourceId));
  }

  Future<void> updateSource(
    String sourceId,
    Map<String, dynamic> patch,
  ) async {
    await _send(PowerViewCommands.sourceUpdate(sourceId, patch));
  }

  Future<Map<String, dynamic>> testSource(String sourceId) async {
    final response = await _send(PowerViewCommands.sourceTest(sourceId));
    return response.payload;
  }

  // ── CT commands ────────────────────────────────────────────────────────────

  /// Read CT configuration registers from the device.
  /// Returns e.g. {"ct_primary": 200, "ct_secondary": 5}.
  Future<Map<String, dynamic>> getCtSettings(String sourceId) async {
    final response = await _send(
      PowerViewCommands.ctGet(sourceId),
      timeout: const Duration(seconds: 5),
    );
    return response.payload;
  }

  /// Write CT configuration registers to the device and return the confirmed values.
  Future<Map<String, dynamic>> setCtSettings(
      String sourceId, Map<String, dynamic> values) async {
    final response = await _send(
      PowerViewCommands.ctSet(sourceId, values),
      timeout: const Duration(seconds: 5),
    );
    return response.payload;
  }

  Future<MeterSnapshot> getMeterSnapshot() async {
    final response = await _send(
      PowerViewCommands.meterSnapshot(),
      timeout: const Duration(seconds: 3),
    );
    return MeterSnapshot.fromJson(response.payload);
  }

  Future<DashboardList> getDashboardList() async {
    final response = await _send(PowerViewCommands.dashboardList());
    return DashboardList.fromJson(response.payload);
  }

  Future<int> setDashboard(int index) async {
    final response = await _send(PowerViewCommands.dashboardSet(index));
    return (response.payload['current'] as num?)?.toInt() ?? index;
  }

  // ── Energy logs (history) ──────────────────────────────────────────────────

  Future<EnergyLog> getKwhHourLog({int count = 24}) async {
    final response = await _send(
      PowerViewCommands.logKwhHour(count: count),
      timeout: const Duration(seconds: 6),
    );
    return EnergyLog.fromJson(response.payload);
  }

  Future<EnergyLog> getKwhDayLog({int count = 30}) async {
    final response = await _send(
      PowerViewCommands.logKwhDay(count: count),
      timeout: const Duration(seconds: 6),
    );
    return EnergyLog.fromJson(response.payload);
  }

  Future<EnergyLog> getKwhMonthLog({int count = 12}) async {
    final response = await _send(
      PowerViewCommands.logKwhMonth(count: count),
      timeout: const Duration(seconds: 6),
    );
    return EnergyLog.fromJson(response.payload);
  }

  // ── Alarm commands ─────────────────────────────────────────────────────────

  Future<AlarmList> listAlarms() async {
    final response = await _send(PowerViewCommands.alarmList());
    return AlarmList.fromJson(response.payload);
  }

  Future<AlarmConfig> addAlarm(AlarmConfig alarm) async {
    final response = await _send(PowerViewCommands.alarmAdd(alarm));
    return AlarmConfig.fromJson(response.payload);
  }

  Future<void> updateAlarm(String id, Map<String, dynamic> patch) async {
    await _send(PowerViewCommands.alarmUpdate(id, patch));
  }

  Future<void> removeAlarm(String id) async {
    await _send(PowerViewCommands.alarmRemove(id));
  }

  Future<void> clearAlarm(String id) async {
    await _send(PowerViewCommands.alarmClear(id));
  }

  Future<void> clearAllAlarms() async {
    await _send(PowerViewCommands.alarmClearAll());
  }

  Future<({List<AlarmState> states, int unseen})> getAlarmStates() async {
    final response = await _send(PowerViewCommands.alarmStates());
    final raw = response.payload['states'] as List<dynamic>? ?? [];
    return (
      states: raw.map((e) => AlarmState.fromJson(e as Map<String, dynamic>)).toList(),
      unseen: (response.payload['unseen'] as num?)?.toInt() ?? 0,
    );
  }

  Future<AlarmHistoryList> getAlarmHistory() async {
    final response = await _send(PowerViewCommands.alarmHistory());
    return AlarmHistoryList.fromJson(response.payload);
  }

  Future<void> markAlarmHistorySeen() async {
    await _send(PowerViewCommands.alarmHistoryMarkSeen());
  }

  Future<int> clearAlarmHistory() async {
    final response = await _send(PowerViewCommands.alarmHistoryClear());
    return (response.payload['cleared'] as num?)?.toInt() ?? 0;
  }

  // ── Update commands ────────────────────────────────────────────────────────

  Future<UpdateVersionInfo> checkUpdate() async {
    final response = await _send(PowerViewCommands.updateCheck());
    return UpdateVersionInfo.fromJson(response.payload);
  }

  Future<UpdateStatus> getUpdateStatus() async {
    final response = await _send(PowerViewCommands.updateStatus());
    return UpdateStatus.fromJson(response.payload);
  }

  Future<void> cancelUpdate() async {
    await _send(PowerViewCommands.updateCancel());
  }

  Future<PrepareUploadResult> prepareUpload(String pin) async {
    final response = await _send(
      PowerViewCommands.updatePrepareUpload(pin),
      timeout: const Duration(seconds: 5),
    );
    return PrepareUploadResult.fromJson(response.payload);
  }

  Future<void> updateFromUrl(String pin, String url) async {
    await _send(
      PowerViewCommands.updateFromUrl(pin, url),
      timeout: const Duration(seconds: 10),
    );
  }

  Future<void> rollbackUpdate(String pin) async {
    await _send(
      PowerViewCommands.updateRollback(pin),
      timeout: const Duration(seconds: 10),
    );
  }

  Future<void> setUpdatePin(String currentPin, String newPin) async {
    await _send(PowerViewCommands.updateSetPin(currentPin, newPin));
  }

  // ── Dashboard config ────────────────────────────────────────────────────────

  Future<DashboardConfig> getDashboardConfig(int index) async {
    final response = await _send(PowerViewCommands.dashboardConfigGet(index));
    return DashboardConfig.fromJson(response.payload);
  }

  Future<DashboardConfig> resetDashboardConfig(int index) async {
    final response = await _send(PowerViewCommands.dashboardConfigReset(index));
    return DashboardConfig.fromJson(response.payload);
  }

  Future<void> setDashboardConfig(
    int index,
    Map<String, String> slots,
    Map<String, String> labels,
  ) async {
    await _send(PowerViewCommands.dashboardConfigSet(index, slots, labels));
  }

  Future<List<FieldCatalogEntry>> getFieldCatalog() async {
    final response = await _send(PowerViewCommands.dashboardFieldCatalog());
    final fields = response.payload['fields'] as Map<String, dynamic>? ?? {};
    return fields.entries
        .map((e) => FieldCatalogEntry.fromJson(e.key, e.value as Map<String, dynamic>))
        .toList();
  }

  // ── Legacy commands (old :command value format) ───────────────────────────

  Future<String> _sendRaw(
    String command, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final transport = _transport;
    if (transport == null) throw StateError('Device is not connected');
    return transport.sendCommand(command, timeout: timeout);
  }

  String _legacyValue(String raw) {
    final t = raw.trim();
    final idx = t.indexOf(' ');
    if (idx < 0) return '';
    final rest = t.substring(idx + 1).trim();
    if (rest == 'err' || rest.startsWith('err ')) {
      throw StateError('Command error: $rest');
    }
    return rest;
  }

  String _legacyInfoValue(String raw, String infoId) {
    final value = _legacyValue(raw);
    final prefix = '$infoId ';
    if (value == infoId) return '';
    if (value.startsWith(prefix)) return value.substring(prefix.length).trim();
    return value;
  }

  ({String version, String serial, String product, String model, String devname})
      _parseInfo99(String raw) {
    // Split first so the RDPW_ prefix check works for both single- and
    // multi-line responses.  Checking raw.startsWith('RDPW_') before splitting
    // caused the entire multi-line string to be treated as the serial.
    final lines = raw
        .trim()
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isNotEmpty && lines.first.startsWith('RDPW_')) {
      // Full legacy block (8 lines joined by \r — kept for very old firmware):
      //   line 0  RDPW_{serial}
      //   line 1  MAC
      //   line 2  port
      //   line 3  {product},{model}
      //   line 4  devname
      //   line 5  version
      if (lines.length >= 6) {
        final pm = lines[3].split(',');
        return (
          version: lines[5],
          serial: lines.first.substring(5).trim(),
          product: pm.isNotEmpty ? pm[0].trim() : '',
          model: pm.length >= 2 ? pm[1].trim() : '',
          devname: lines[4],
        );
      }
      // Short legacy response — serial only
      return (version: '', serial: lines.first.substring(5).trim(),
              product: '', model: '', devname: '');
    }

    // Current format: single-line JSON prefixed with ":info 99 "
    final text = raw.trim();
    final value = _legacyInfoValue(text, '99');
    if (value.isEmpty || value == 'ok') {
      return (version: '', serial: '', product: '', model: '', devname: '');
    }

    try {
      final j = jsonDecode(value);
      if (j is Map<String, dynamic>) {
        String s(String k, [String k2 = '', String k3 = '']) =>
            (j[k] ?? (k2.isNotEmpty ? j[k2] : null) ?? (k3.isNotEmpty ? j[k3] : null) ?? '')
                .toString();
        return (
          version: s('version', 'meter_version', 'version_main'),
          serial:  s('serial',  'serialnum',     'meter_serial'),
          product: s('product'),
          model:   s('model'),
          devname: s('devname', 'device_name'),
        );
      }
    } catch (_) {}

    // key=value fallback
    final fields = <String, String>{};
    for (final token in value.split(RegExp(r'[\s,;]+'))) {
      final idx = token.indexOf('=');
      if (idx <= 0) continue;
      fields[token.substring(0, idx).toLowerCase()] = token.substring(idx + 1);
    }
    if (fields.isNotEmpty) {
      return (
        version: fields['version'] ?? fields['ver'] ?? '',
        serial:  fields['serial']  ?? fields['serialnum'] ?? fields['sn'] ?? '',
        product: fields['product'] ?? '',
        model:   fields['model']   ?? '',
        devname: fields['devname'] ?? fields['device_name'] ?? '',
      );
    }

    return (version: value, serial: '', product: '', model: '', devname: '');
  }

  Future<PiNetworkSettings> getNetworkSettings() async {
    final dhcpRaw = await _sendRaw(':dhcp');
    final ipRaw = await _sendRaw(':ipaddr');
    final nmRaw = await _sendRaw(':netmask');
    final gwRaw = await _sendRaw(':gateway');
    final portRaw = await _sendRaw(':port');
    final dnsRaw = await _sendRaw(':dns');
    final ssidRaw = await _sendRaw(':ssid');
    return PiNetworkSettings(
      dhcp: _legacyValue(dhcpRaw) == '1',
      ip: _legacyValue(ipRaw),
      netmask: _legacyValue(nmRaw),
      gateway: _legacyValue(gwRaw),
      port: int.tryParse(_legacyValue(portRaw)) ?? 5555,
      dns: _legacyValue(dnsRaw),
      ssid: _legacyValue(ssidRaw),
    );
  }

  Future<void> applyNetworkSettings(PiNetworkSettings s) async {
    if (!s.dhcp) {
      await _sendRaw(':ipaddr ${s.ip}');
      await _sendRaw(':netmask ${s.netmask}');
      await _sendRaw(':gateway ${s.gateway}');
      await _sendRaw(':dns ${s.dns}');
    }
    await _sendRaw(':port ${s.port}');
    // DHCP last — triggers _apply_network() on the backend with all values set
    await _sendRaw(':dhcp ${s.dhcp ? 1 : 0}');
  }

  Future<void> applyWifi(String ssid, String password) async {
    await _sendRaw(':ssid $ssid');
    if (password.isNotEmpty) {
      await _sendRaw(':ssid_pswd $password');
    }
  }

  Future<List<WifiNetwork>> getWifiList() async {
    final raw = await _sendRaw(':ssid_ls', timeout: const Duration(seconds: 8));
    final value = _legacyValue(raw);
    try {
      final list = jsonDecode(value) as List<dynamic>;
      return list
          .map((e) {
            final m = e as Map<String, dynamic>;
            return WifiNetwork(
              ssid: m['ssid']?.toString() ?? '',
              signal: (m['signal'] as num?)?.toInt() ?? 0,
              security: m['security']?.toString() ?? '',
            );
          })
          .where((w) => w.ssid.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<PiPowerViewSettings> getPowerViewSettings() async {
    final ctRaw = await _sendRaw(':pvget_ct_type');
    final rateRaw = await _sendRaw(':pvget_elec_rate');
    final cefRaw = await _sendRaw(':pvget_cef');
    return PiPowerViewSettings(
      ctType: int.tryParse(_legacyValue(ctRaw)) ?? 0,
      elecRate: double.tryParse(_legacyValue(rateRaw)) ?? 4.0,
      cef: double.tryParse(_legacyValue(cefRaw)) ?? 0.399,
    );
  }

  Future<void> applyPowerViewSettings(PiPowerViewSettings s) async {
    await _sendRaw(':pvset_ct_type ${s.ctType}');
    await _sendRaw(':pvset_elec_rate ${s.elecRate}');
    await _sendRaw(':pvset_cef ${s.cef}');
  }

  Future<void> resetMeter() async {
    await _sendRaw(':pv_reset_meter', timeout: const Duration(seconds: 5));
  }

  Future<PiAboutInfo> getAboutInfo() async {
    String meterVersion = '';
    String meterSerial = '';
    String meterProduct = '';
    String meterModel = '';

    try {
      final parsed = _parseInfo99(await _sendRaw(':info 99'));
      meterVersion = parsed.version;
      meterSerial  = parsed.serial;
      meterProduct = parsed.product;
      meterModel   = parsed.model;
    } catch (_) {}

    // Fallbacks for older firmware that doesn't support :info 99 properly.
    try {
      if (meterVersion.isEmpty) {
        meterVersion = _legacyInfoValue(await _sendRaw(':info 3'), '3');
      }
    } catch (_) {}

    try {
      if (meterSerial.isEmpty) {
        meterSerial = _legacyValue(await _sendRaw(':serialnum'));
      }
    } catch (_) {}

    // ── Collector: resolve active source from source list ─────────────────────
    String? collectorName;
    String? collectorType;
    bool? collectorEnabled;
    try {
      final sl = await listSources();
      if (sl.sources.isNotEmpty) {
        final active = sl.sources.firstWhere(
          (s) => s.id == sl.activeSourceId,
          orElse: () => sl.sources.first,
        );
        collectorName = active.name.isNotEmpty ? active.name : active.type;
        collectorType = active.type;
        collectorEnabled = active.enabled;
      }
    } catch (_) {
      // Source list unavailable — leave collector fields null.
    }

    return PiAboutInfo(
      meterVersion: meterVersion,
      meterSerial:  meterSerial,
      meterProduct: meterProduct,
      meterModel:   meterModel,
      collectorName: collectorName,
      collectorType: collectorType,
      collectorEnabled: collectorEnabled,
    );
  }

  Future<DeviceResponse> _send(
    String command, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final transport = _transport;
    if (transport == null) {
      throw StateError('Device is not connected');
    }

    final raw = await transport.sendCommand(
      command,
      timeout: timeout,
    );
    final response = DeviceResponse.parse(raw);
    if (!response.ok) {
      throw StateError(response.message.isEmpty
          ? 'Command failed: ${response.errorCode}'
          : response.message);
    }

    return response;
  }
}
