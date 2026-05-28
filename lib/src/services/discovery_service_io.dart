import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'discovery_service.dart';

// Android: acquire MulticastLock so the OS delivers inbound UDP packets.
const _multicastChannel = MethodChannel(
  'com.example.app_power_view/multicast_lock',
);

Future<void> _acquireMulticastLock() async {
  if (!Platform.isAndroid) return;
  try {
    await _multicastChannel.invokeMethod<void>('acquire');
  } catch (_) {}
}

Future<void> _releaseMulticastLock() async {
  if (!Platform.isAndroid) return;
  try {
    await _multicastChannel.invokeMethod<void>('release');
  } catch (_) {}
}

Future<List<DiscoveredDevice>> platformDiscoverDevices({
  required Duration timeout,
  String? startIp,
  String? endIp,
  void Function(String status)? onProgress,
}) async {
  final found = <String, DiscoveredDevice>{};

  final ips = <String>[];
  if (startIp != null && endIp != null) {
    final start = _ipToInt(startIp);
    final end = _ipToInt(endIp);
    if (start > 0 && end >= start) {
      for (var i = start; i <= end; i++) {
        ips.add(_intToIp(i));
      }
    }
  } else {
    onProgress?.call('Detecting network...');
    final prefixes = await _localSubnetPrefixes();
    if (prefixes.isEmpty) {
      onProgress?.call('No network interface found');
      return [];
    }
    for (final p in prefixes) {
      for (var i = 1; i <= 254; i++) {
        ips.add('$p.$i');
      }
    }
    final label = prefixes.map((p) => '$p.x').join(', ');
    onProgress?.call('Scanning $label (${ips.length} hosts)...');
  }

  final payload = utf8.encode('Discovery');

  await _acquireMulticastLock();
  RawDatagramSocket? socket;
  try {
    // Single socket bound to port 30303 — Pi responds back to this port.
    socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);

    final completer = Completer<void>();

    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        try {
          final map = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          final nameBios = map['name_bios']?.toString() ?? '';
          if (!nameBios.startsWith('RDPW_')) return;
          final host = dg.address.address;
          final tcpPort = (map['tcp_port'] as num?)?.toInt() ?? 5555;
          final name = map['name']?.toString() ?? host;
          found[host] =
              DiscoveredDevice(host: host, tcpPort: tcpPort, name: name);
        } catch (_) {}
      },
      onError: (_) {},
      cancelOnError: false,
    );

    // Send Discovery to every IP — all on the same socket.
    for (final ip in ips) {
      try {
        socket.send(payload, InternetAddress(ip), discoveryPort);
      } catch (_) {}
    }

    // Wait for responses during the full timeout window.
    await Future.any([
      completer.future,
      Future.delayed(timeout),
    ]);
  } catch (_) {
  } finally {
    socket?.close();
    await _releaseMulticastLock();
  }

  if (found.isNotEmpty) {
    onProgress?.call('Found ${found.length} device(s).');
  }

  return found.values.toList();
}

Future<List<String>> _localSubnetPrefixes() async {
  final prefixes = <String>{};

  // Method 1: NetworkInterface.list()
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback) continue;
        final parts = addr.address.split('.');
        if (parts.length == 4) {
          prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
    }
  } catch (_) {}

  // Method 2: TCP connect trick to find the outbound interface IP.
  if (prefixes.isEmpty) {
    try {
      final tcp = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 2),
      );
      final localIp = tcp.address.address;
      tcp.destroy();
      final parts = localIp.split('.');
      if (parts.length == 4 && localIp != '0.0.0.0') {
        prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    } catch (_) {}
  }

  return prefixes.toList();
}

int _ipToInt(String ip) {
  final p = ip.split('.');
  if (p.length != 4) return 0;
  return (int.tryParse(p[0]) ?? 0) << 24 |
      (int.tryParse(p[1]) ?? 0) << 16 |
      (int.tryParse(p[2]) ?? 0) << 8 |
      (int.tryParse(p[3]) ?? 0);
}

String _intToIp(int v) =>
    '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
