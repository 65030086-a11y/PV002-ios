import 'app_transport.dart';

AppTransport createPlatformTcpTransport({
  required String host,
  required int port,
  required Duration timeout,
}) {
  return _UnsupportedTcpTransport();
}

class _UnsupportedTcpTransport implements AppTransport {
  @override
  bool get isConnected => false;

  @override
  Future<void> connect() {
    throw UnsupportedError('TCP transport is not available on this platform');
  }

  @override
  Future<String> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 3),
  }) {
    throw UnsupportedError('TCP transport is not available on this platform');
  }

  @override
  Future<void> close() async {}

  @override
  set onDisconnected(void Function()? callback) {}
}
