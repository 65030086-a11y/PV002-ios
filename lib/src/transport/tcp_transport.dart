import 'tcp_transport_stub.dart' if (dart.library.io) 'tcp_transport_io.dart';

import 'app_transport.dart';

AppTransport createTcpTransport({
  required String host,
  required int port,
  Duration timeout = const Duration(seconds: 3),
}) {
  return createPlatformTcpTransport(
    host: host,
    port: port,
    timeout: timeout,
  );
}
