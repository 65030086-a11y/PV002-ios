// Stub for platforms without dart:io (web).  All no-ops.

Future<void>   platformOpenWifiPicker() async {}
Future<String?> platformGetCurrentSsid() async => null;
Future<bool>   platformProbePiAp({
  String host = '192.168.50.1',
  int port    = 5555,
  Duration timeout = const Duration(seconds: 1),
}) async =>
    false;
