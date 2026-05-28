import 'discovery_service_stub.dart'
    if (dart.library.io) 'discovery_service_io.dart';

const discoveryPort = 30303;

class DiscoveredDevice {
  const DiscoveredDevice({
    required this.host,
    required this.tcpPort,
    required this.name,
  });

  final String host;
  final int tcpPort;
  final String name;

  @override
  String toString() => '$name ($host:$tcpPort)';
}

Future<List<DiscoveredDevice>> discoverDevices({
  Duration timeout = const Duration(seconds: 6),
  String? startIp,
  String? endIp,
  void Function(String status)? onProgress,
}) {
  return platformDiscoverDevices(
    timeout: timeout,
    startIp: startIp,
    endIp: endIp,
    onProgress: onProgress,
  );
}
