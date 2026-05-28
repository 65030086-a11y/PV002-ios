abstract class AppTransport {
  bool get isConnected;

  Future<void> connect();

  Future<String> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 3),
  });

  Future<void> close();

  /// Invoked exactly once if the transport loses the connection
  /// unexpectedly (socket closed by peer, network error, etc).  Will
  /// NOT fire when the caller explicitly invokes [close].
  ///
  /// DeviceClient sets this so it can clear its transport reference and
  /// notify the UI to display a "disconnected" badge.
  set onDisconnected(void Function()? callback);
}
