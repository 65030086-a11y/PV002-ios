import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.app_power_view/wifi_settings');

Future<void> platformOpenWifiPicker() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('openWifiPanel');
  } catch (_) {
    // Ignore — the dialog still lets the user proceed manually.
  }
}

Future<String?> platformGetCurrentSsid() async {
  if (!Platform.isAndroid) return null;
  try {
    return await _channel.invokeMethod<String>('getCurrentSsid');
  } catch (_) {
    return null;
  }
}

/// Probe whether a TCP host:port is reachable within [timeout].
/// Used as a fallback when SSID lookup is blocked (Android 10+ without
/// location permission) — if we can talk to the Pi gateway, we treat the
/// network as "PI_AP" even though we can't read the SSID name.
Future<bool> platformProbePiAp({
  String host         = '192.168.50.1',
  int    port         = 5555,
  Duration timeout    = const Duration(seconds: 1),
}) async {
  Socket? s;
  try {
    s = await Socket.connect(host, port, timeout: timeout);
    return true;
  } catch (_) {
    return false;
  } finally {
    try { s?.destroy(); } catch (_) {}
  }
}
