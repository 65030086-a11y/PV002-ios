import 'dart:convert';

class DeviceResponse {
  DeviceResponse({
    required this.command,
    required this.ok,
    required this.payload,
    required this.raw,
    this.errorCode = '',
    this.message = '',
  });

  final String command;
  final bool ok;
  final Map<String, dynamic> payload;
  final String raw;
  final String errorCode;
  final String message;

  factory DeviceResponse.parse(String raw) {
    final trimmed = raw.trim();
    final firstSpace = trimmed.indexOf(' ');

    if (!trimmed.startsWith(':') || firstSpace < 0) {
      return DeviceResponse(
        command: '',
        ok: false,
        payload: const {},
        raw: raw,
        errorCode: 'invalid_response',
        message: 'Invalid response format',
      );
    }

    final command = trimmed.substring(0, firstSpace);
    final rest = trimmed.substring(firstSpace + 1).trim();
    final statusSpace = rest.indexOf(' ');
    final status = statusSpace < 0 ? rest : rest.substring(0, statusSpace);
    final body = statusSpace < 0 ? '' : rest.substring(statusSpace + 1).trim();

    Map<String, dynamic> payload = {};
    if (body.isNotEmpty) {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        payload = Map<String, dynamic>.from(decoded);
      }
    }

    return DeviceResponse(
      command: command,
      ok: status == 'ok',
      payload: payload,
      raw: raw,
      errorCode: status == 'ok' ? '' : status,
      message: payload['message'] as String? ?? '',
    );
  }
}
