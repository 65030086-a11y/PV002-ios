import 'discovery_service.dart';

Future<List<DiscoveredDevice>> platformDiscoverDevices({
  required Duration timeout,
  String? startIp,
  String? endIp,
  void Function(String status)? onProgress,
}) async {
  return const [];
}
