import 'system_wifi_stub.dart'
    if (dart.library.io) 'system_wifi_io.dart';

/// Open the OS Wi-Fi picker so the user can join a network (e.g. `PI_AP`)
/// without leaving the app permanently — on Android 10+ this is a slide-up
/// panel; older versions fall back to the full Wi-Fi settings page.
///
/// Returns silently on platforms where this isn't supported (iOS, desktop).
Future<void> openWifiPicker() => platformOpenWifiPicker();

/// Returns the SSID the device is currently joined to, or null if unknown.
/// May return null on Android 10+ when the app does not hold location
/// permission — callers should treat null as "cannot tell".
Future<String?> getCurrentSsid() => platformGetCurrentSsid();

/// Reachability probe for the PI_AP gateway.  Used as a fallback signal
/// when [getCurrentSsid] returns null: if the Pi gateway answers a TCP
/// connect we treat the device as being on PI_AP.
Future<bool> isPiApReachable({
  String host = '192.168.50.1',
  int port    = 5555,
  Duration timeout = const Duration(seconds: 1),
}) =>
    platformProbePiAp(host: host, port: port, timeout: timeout);
