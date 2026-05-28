import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:characters/characters.dart';
import 'app_transport.dart';

class UsbTransport implements AppTransport {
  final String portName;
  final int baudRate;

  UsbTransport({
    required this.portName,
    this.baudRate = 115200,
  });

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;

  final StringBuffer _rxBuffer = StringBuffer();
  final List<Completer<String>> _pending = [];
  void Function()? _onDisconnected;

  @override
  bool get isConnected => _port?.isOpen ?? false;

  @override
  set onDisconnected(void Function()? callback) {
    _onDisconnected = callback;
  }

  // ── connect ───────────────────────────────────────────────────────────────

  @override
  Future<void> connect() async {
    if (_port != null && _port!.isOpen) return;

    //print('[USB] Opening port: $portName @ ${baudRate}baud');

    _port = SerialPort(portName);

    final config = SerialPortConfig()
      ..baudRate = baudRate
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none
      ..setFlowControl(SerialPortFlowControl.none);

    if (!_port!.openReadWrite()) {
      final err = SerialPort.lastError;
      throw Exception('Cannot open $portName: $err');
    }

    _port!.config = config;

    //print('[USB] Port opened successfully');
    await Future.delayed(const Duration(milliseconds: 1500));
    _reader = SerialPortReader(_port!);
    _sub = _reader!.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );

    //print('[USB] RX stream listener attached');
  }

  // ── rx handling ───────────────────────────────────────────────────────────

  void _onData(Uint8List bytes) {
    // Show raw hex bytes so we can see EXACTLY what Python is sending
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    //print('[USB RX] ${bytes.length} bytes: $hex');
    //print('[USB RX] as text: "${utf8.decode(bytes, allowMalformed: true)}"');

    final chunk = utf8.decode(bytes, allowMalformed: true);
    for (final ch in chunk.characters) {
      if (ch == '\r' || ch == '\n') {
        final line = _rxBuffer.toString().trim();
        _rxBuffer.clear();
        //print('[USB RX] \\r or \\n received — line: "$line" | pending: ${_pending.length}');
        if (line.isNotEmpty && _pending.isNotEmpty) {
          final completer = _pending.removeAt(0);
          if (!completer.isCompleted) {
            //print('[USB RX] Resolving completer with: "$line"');
            completer.complete(line);
          }
        } else if (line.isEmpty) {
          print('[USB RX] Empty line ignored');
        } else if (_pending.isEmpty) {
          print('[USB RX] WARNING: got line but no pending command: "$line"');
        }
      } else {
        _rxBuffer.write(ch);
      }
    }
  }

  void _onError(Object error) {
    print('[USB ERROR] $error');
    _failAllPending('USB read error: $error');
    _notifyDisconnected();
  }

  void _onDone() {
    print('[USB] Stream done — port closed unexpectedly');
    _failAllPending('USB port closed unexpectedly');
    _notifyDisconnected();
  }

  void _failAllPending(String reason) {
    print('[USB] Failing ${_pending.length} pending command(s): $reason');
    for (final c in _pending) {
      if (!c.isCompleted) c.completeError(StateError(reason));
    }
    _pending.clear();
  }

  void _notifyDisconnected() {
    final cb = _onDisconnected;
    _onDisconnected = null;
    cb?.call();
  }

  // ── sendCommand ───────────────────────────────────────────────────────────

  @override
  Future<String> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!isConnected) throw StateError('USB port is not open');

    const maxAttempts = 3;
    const retryDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final bytes = utf8.encode('$command\r');
      //print('[USB TX] Sending: "$command\\r" attempt $attempt');
      _port!.write(Uint8List.fromList(bytes));

      final completer = Completer<String>();
      _pending.add(completer);

      try {
        return await completer.future.timeout(timeout);
      } on TimeoutException {
        _pending.remove(completer);
        if (!completer.isCompleted) completer.completeError(
          StateError('removed after timeout'),
        );
        //print('[USB TIMEOUT] Attempt $attempt failed for "$command"');
        if (attempt < maxAttempts) {
          //print('[USB RETRY] Waiting ${retryDelay.inSeconds}s before retry...');
          await Future.delayed(retryDelay);
          if (!isConnected) throw StateError('USB port closed during retry');
        }
      }
    }

    throw TimeoutException(
      'USB command failed after $maxAttempts attempts: $command',
    );
  }

  // ── close ─────────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    //print('[USB] Closing port: $portName');
    _failAllPending('Transport closed by caller');
    await _sub?.cancel();
    _sub = null;
    _reader?.close();
    _reader = null;
    _port?.close();
    _port?.dispose();
    _port = null;
  }
}