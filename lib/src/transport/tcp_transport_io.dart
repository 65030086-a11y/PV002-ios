import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_transport.dart';

AppTransport createPlatformTcpTransport({
  required String host,
  required int port,
  required Duration timeout,
}) {
  return TcpTransportIo(host: host, port: port, connectTimeout: timeout);
}

class TcpTransportIo implements AppTransport {
  TcpTransportIo({
    required this.host,
    required this.port,
    required this.connectTimeout,
  });

  final String host;
  final int port;
  final Duration connectTimeout;

  Socket? _socket;
  StreamSubscription<String>? _subscription;
  Completer<String>? _pendingResponse;
  final StringBuffer _buffer = StringBuffer();

  // Set by DeviceClient — invoked once when the socket dies on its own.
  void Function()? _onDisconnected;
  bool _userClosing = false;   // true while close() is running

  @override
  set onDisconnected(void Function()? callback) {
    _onDisconnected = callback;
  }

  // ── Serialisation queue ──────────────────────────────────────────────────
  // All sendCommand calls are chained onto this future so they execute one
  // at a time.  This prevents "Another command is still waiting" errors when
  // multiple widgets (e.g. MeterDataPage polling in the background while
  // DataSourcePage saves) share the same DeviceClient.
  Future<void> _queue = Future.value();

  // When a command times out the Pi may still send its response later.
  // Reconnecting before the next command flushes the stale data.
  bool _streamDirty = false;

  // ── AppTransport ─────────────────────────────────────────────────────────

  @override
  bool get isConnected => _socket != null;

  @override
  Future<void> connect() async {
    await _closeSocket();
    _socket = await Socket.connect(host, port, timeout: connectTimeout);
    _buffer.clear();
    _subscription = _socket!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(_onData, onDone: _onDone, onError: _onError);
    _streamDirty = false;
  }

  @override
  Future<String> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 3),
  }) {
    // Chain onto the queue so every call is serialised.
    final myFuture = _queue.then(
      (_) => _doSendCommand(command, timeout: timeout),
    );
    // Absorb errors so a failed command doesn't block subsequent ones.
    _queue = myFuture.then((_) {}, onError: (_) {});
    return myFuture;
  }

  @override
  Future<void> close() async {
    _userClosing = true;
    _queue = Future.value(); // reset queue
    await _closeSocket();
    _userClosing = false;
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<String> _doSendCommand(
    String command, {
    required Duration timeout,
  }) async {
    // If a previous command timed out the stream may carry a stale response.
    // Reconnect to get a clean socket before sending the next command.
    if (_streamDirty) {
      _streamDirty = false;
      await _reconnect();
    }

    final socket = _socket;
    if (socket == null) throw StateError('TCP is not connected');

    assert(_pendingResponse == null,
        '_pendingResponse should be null inside the serialised queue');

    final completer = Completer<String>();
    _pendingResponse = completer;

    socket.write('$command\r');
    await socket.flush();

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingResponse = null;
        _streamDirty = true; // Pi may still reply — reconnect next time
        throw TimeoutException('No response from device', timeout);
      },
    );
  }

  /// Tear down and re-establish the socket (keeps host/port/timeout).
  Future<void> _reconnect() async {
    await _closeSocket();
    try {
      _socket = await Socket.connect(host, port, timeout: connectTimeout);
      _buffer.clear();
      _subscription = _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(_onData, onDone: _onDone, onError: _onError);
    } catch (_) {
      _socket = null;
      rethrow;
    }
  }

  Future<void> _closeSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    // Resolve any pending completer so the queue can move on.
    final c = _pendingResponse;
    _pendingResponse = null;
    if (c != null && !c.isCompleted) {
      c.completeError(StateError('TCP connection closed'));
    }
    _buffer.clear();
  }

  void _onData(String data) {
    _buffer.write(data);

    final text = _buffer.toString();
    final delimiterIndex = _firstDelimiterIndex(text);
    if (delimiterIndex < 0) return;

    final line = text.substring(0, delimiterIndex).trim();
    final remaining = text.substring(delimiterIndex + 1);
    _buffer
      ..clear()
      ..write(remaining);

    final completer = _pendingResponse;
    _pendingResponse = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(line);
    }
  }

  void _onDone() {
    final completer = _pendingResponse;
    _pendingResponse = null;
    _socket = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('TCP connection closed'));
    }
    if (!_userClosing) _onDisconnected?.call();
  }

  void _onError(Object error) {
    final completer = _pendingResponse;
    _pendingResponse = null;
    _socket = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
    if (!_userClosing) _onDisconnected?.call();
  }

  int _firstDelimiterIndex(String text) {
    final cr = text.indexOf('\r');
    final lf = text.indexOf('\n');
    if (cr < 0) return lf;
    if (lf < 0) return cr;
    return cr < lf ? cr : lf;
  }
}
