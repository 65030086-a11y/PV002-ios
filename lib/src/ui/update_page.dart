import 'dart:async';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/update_info.dart';
import '../services/device_client.dart';
import 'connection_status_badge.dart';

// ── Page ──────────────────────────────────────────────────────────────────────

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

// ── Phase enum ────────────────────────────────────────────────────────────────

enum _Phase { idle, active, restarting, success }

// ── State ─────────────────────────────────────────────────────────────────────

class _UpdatePageState extends State<UpdatePage> {
  _Phase _phase = _Phase.idle;
  bool _loading = true;
  String? _error;

  UpdateVersionInfo? _currentVersion;
  UpdateVersionInfo? _newVersion;
  UpdateStatus _status = const UpdateStatus.idle();

  // Controllers
  final _pinCtrl         = TextEditingController();
  final _urlCtrl         = TextEditingController();
  final _currentPinCtrl  = TextEditingController();
  final _newPinCtrl      = TextEditingController();
  final _confirmPinCtrl  = TextEditingController();

  bool _pinVisible     = false;
  bool _changingPin    = false;
  String? _pinError;
  String? _pinSuccess;

  Timer? _pollTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _pinCtrl.dispose();
    _urlCtrl.dispose();
    _currentPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  // ── Load version ──────────────────────────────────────────────────────────

  Future<void> _loadVersion() async {
    setState(() {
      _loading = true;
      _error   = null;
    });
    try {
      final v = await widget.client.checkUpdate();
      if (mounted) setState(() { _currentVersion = v; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Option B — upload from phone ──────────────────────────────────────────

  Future<void> _startUpload() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) { _snack('Enter PIN first'); return; }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) { _snack('Could not read file'); return; }

    setState(() { _phase = _Phase.active; _error = null; });

    try {
      final prep = await widget.client.prepareUpload(pin);
      final host = widget.client.host;
      if (host == null) throw StateError('Not connected via TCP');

      final statusCode = await _uploadBytes(
        host:    host,
        port:    prep.port,
        token:   prep.token,
        bytes:   bytes,
        timeout: Duration(seconds: prep.expiresIn + 10),
      );

      if (statusCode != 200) {
        throw Exception('Upload failed — HTTP $statusCode');
      }

      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() { _phase = _Phase.idle; _error = e.toString(); });
      }
    }
  }

  // ── Upload helper (dart:io, streamed) ────────────────────────────────────
  //
  // req.add() in a for-loop is synchronous: all bytes are buffered BEFORE
  // any I/O happens, so the OS still gets the full file in one shot.
  // addStream() with an async* generator lets the event loop drain the TCP
  // send-buffer between chunks — fixing WSAECONNABORTED (errno 10053) on
  // Windows when the firmware zip is large (30-80 MB).

  Future<int> _uploadBytes({
    required String host,
    required int port,
    required String token,
    required List<int> bytes,
    required Duration timeout,
  }) async {
    final ioClient = io.HttpClient();
    ioClient.connectionTimeout = const Duration(seconds: 30);

    try {
      final uri = Uri.parse('http://$host:$port/upload');
      final req  = await ioClient.postUrl(uri);
      req.headers.set('X-Update-Token', token);
      req.headers.contentType =
          io.ContentType('application', 'octet-stream');
      req.contentLength = bytes.length;

      // addStream() respects backpressure: waits for the OS to accept each
      // chunk before the async* generator yields the next one.
      await req.addStream(_chunkStream(bytes, 65536));

      final resp = await req.close().timeout(timeout);
      await resp.drain<void>();
      return resp.statusCode;
    } finally {
      ioClient.close(force: false);
    }
  }

  /// Yields [bytes] in [chunkSize]-byte pieces, pausing the Dart event loop
  /// (`await Future.delayed(Duration.zero)`) between each yield so the OS
  /// TCP send-buffer drains before the next chunk is written.
  Stream<List<int>> _chunkStream(List<int> bytes, int chunkSize) async* {
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      yield bytes.sublist(offset, end);
      await Future<void>.delayed(Duration.zero);
    }
  }

  // ── Option C — download from URL ──────────────────────────────────────────

  Future<void> _startDownload() async {
    final pin = _pinCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (pin.isEmpty) { _snack('Enter PIN first');       return; }
    if (url.isEmpty) { _snack('Enter a download URL'); return; }

    setState(() { _phase = _Phase.active; _error = null; });

    try {
      await widget.client.updateFromUrl(pin, url);
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() { _phase = _Phase.idle; _error = e.toString(); });
      }
    }
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final status = await widget.client.getUpdateStatus();
      if (!mounted) return;
      setState(() => _status = status);

      if (status.isRestarting) {
        _pollTimer?.cancel();
        setState(() { _phase = _Phase.restarting; _reconnectAttempts = 0; });
        _scheduleReconnect();
      } else if (status.isFailed) {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _phase  = _Phase.idle;
            _error  = status.error ?? status.message;
            _status = const UpdateStatus.idle();
          });
        }
      }
    } catch (_) {
      // Connection dropped mid-update → assume restarting
      if (mounted && _phase == _Phase.active) {
        _pollTimer?.cancel();
        setState(() { _phase = _Phase.restarting; _reconnectAttempts = 0; });
        _scheduleReconnect();
      }
    }
  }

  // ── Reconnect after restart ────────────────────────────────────────────────

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), _tryReconnect);
  }

  Future<void> _tryReconnect() async {
    if (!mounted) return;
    _reconnectAttempts++;
    setState(() {});          // refresh attempt counter

    try {
      await widget.client.reconnect();
      final v = await widget.client.checkUpdate();
      if (mounted) {
        setState(() {
          _newVersion     = v;
          _currentVersion = v;
          _phase          = _Phase.success;
        });
      }
    } catch (_) {
      if (mounted) _scheduleReconnect();
    }
  }

  // ── Cancel ─────────────────────────────────────────────────────────────────

  Future<void> _cancel() async {
    _pollTimer?.cancel();
    try { await widget.client.cancelUpdate(); } catch (_) {}
    if (mounted) {
      setState(() { _phase = _Phase.idle; _status = const UpdateStatus.idle(); });
    }
  }

  // ── Rollback ───────────────────────────────────────────────────────────────

  Future<void> _rollback() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) { _snack('Enter PIN to confirm rollback'); return; }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rollback to previous version?'),
        content: const Text(
          'The device will restart and revert to the backup version. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rollback'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _phase  = _Phase.active;
      _error  = null;
      _status = const UpdateStatus(
        stage: 'staging', progress: 0, message: 'Preparing rollback…',
      );
    });

    try {
      await widget.client.rollbackUpdate(pin);
      setState(() { _phase = _Phase.restarting; _reconnectAttempts = 0; });
      _scheduleReconnect();
    } catch (e) {
      if (mounted) setState(() { _phase = _Phase.idle; _error = e.toString(); });
    }
  }

  // ── Change PIN ─────────────────────────────────────────────────────────────

  Future<void> _changePin() async {
    final current = _currentPinCtrl.text.trim();
    final next    = _newPinCtrl.text.trim();
    final confirm = _confirmPinCtrl.text.trim();

    setState(() { _pinError = null; _pinSuccess = null; });

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _pinError = 'All fields are required');
      return;
    }
    if (next != confirm) {
      setState(() => _pinError = 'New PIN and confirmation do not match');
      return;
    }

    setState(() => _changingPin = true);
    try {
      await widget.client.setUpdatePin(current, next);
      if (mounted) {
        _currentPinCtrl.clear();
        _newPinCtrl.clear();
        _confirmPinCtrl.clear();
        setState(() {
          _changingPin = false;
          _pinSuccess  = 'PIN changed successfully';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _changingPin = false; _pinError = e.toString(); });
      }
    }
  }

  // ── Snack helper ──────────────────────────────────────────────────────────

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Software Update'),
        actions: [
          ConnectionStatusBadge(client: widget.client),
          if (_phase == _Phase.idle)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh version info',
              onPressed: _loadVersion,
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.restarting:
        return _buildRestartingView();
      case _Phase.success:
        return _buildSuccessView();
      case _Phase.active:
        return _buildActiveView();
      case _Phase.idle:
        return _buildIdleView();
    }
  }

  // ── Idle ──────────────────────────────────────────────────────────────────

  Widget _buildIdleView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.all(16),
      children: [
        _VersionCard(version: _currentVersion, loading: _loading),
        const SizedBox(height: 16),

        if (_error != null) ...[
          _ErrorBanner(_error!),
          const SizedBox(height: 16),
        ],

        // ── Shared PIN ─────────────────────────────────────────────────
        _PinField(
          controller: _pinCtrl,
          visible: _pinVisible,
          onToggle: () => setState(() => _pinVisible = !_pinVisible),
        ),
        const SizedBox(height: 16),

        // ── Option B ───────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OptionHeader(
                  icon: Icons.upload_file_outlined,
                  color: const Color(0xFF1565C0),
                  title: 'Option B — Upload from Phone',
                  subtitle: 'Select a .zip file on this device and send it to the Pi',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _startUpload,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Pick .zip & Upload'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Option C ───────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OptionHeader(
                  icon: Icons.cloud_download_outlined,
                  color: const Color(0xFF00796B),
                  title: 'Option C — Download from URL',
                  subtitle: 'Pi downloads and installs the update directly',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Download URL',
                    hintText: 'https://example.com/update.zip',
                    isDense: true,
                    prefixIcon: Icon(Icons.link, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _startDownload,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00796B),
                    ),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download & Install'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Rollback ───────────────────────────────────────────────────
        Card(
          color: cs.errorContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Text('Rollback',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: cs.error)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Revert to the previous backup version. '
                  'The Pi will restart automatically.',
                  style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _rollback,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                    ),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Rollback to Previous Version'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Change PIN ─────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.key_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text('Change Update PIN',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: cs.primary)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _currentPinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Current PIN',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newPinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'New PIN',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _confirmPinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New PIN',
                    isDense: true,
                  ),
                ),
                if (_pinError != null) ...[
                  const SizedBox(height: 8),
                  Text(_pinError!,
                      style: TextStyle(color: cs.error, fontSize: 12)),
                ],
                if (_pinSuccess != null) ...[
                  const SizedBox(height: 8),
                  Text(_pinSuccess!,
                      style: const TextStyle(
                          color: Color(0xFF1AAB5F), fontSize: 12)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _changingPin ? null : _changePin,
                    icon: _changingPin
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Save New PIN'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Active ────────────────────────────────────────────────────────────────

  Widget _buildActiveView() {
    final cs = Theme.of(context).colorScheme;
    final indeterminate = _status.progress == 0;
    return Center(
      key: const ValueKey('active'),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.system_update_alt,
                  size: 40, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 28),
            Text(
              _stageLabel(_status.stage),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (_status.message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _status.message,
                style: TextStyle(fontSize: 13, color: cs.outline),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 28),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: indeterminate ? null : _status.progress / 100.0,
                minHeight: 8,
              ),
            ),
            if (!indeterminate) ...[
              const SizedBox(height: 8),
              Text('${_status.progress}%',
                  style: TextStyle(fontSize: 13, color: cs.outline)),
            ],
            const SizedBox(height: 36),
            OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Restarting ────────────────────────────────────────────────────────────

  Widget _buildRestartingView() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('restarting'),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                strokeWidth: 5,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Restarting Pi…',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Applying update and restarting.\nReconnecting automatically…',
              style: TextStyle(fontSize: 13, color: cs.outline),
              textAlign: TextAlign.center,
            ),
            if (_reconnectAttempts > 0) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Attempt $_reconnectAttempts',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Success ───────────────────────────────────────────────────────────────

  Widget _buildSuccessView() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('success'),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: Color(0x1F1AAB5F),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline,
                  size: 48, color: Color(0xFF1AAB5F)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Update Successful!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            if (_newVersion != null) ...[
              const SizedBox(height: 8),
              Text(
                'Now running  v${_newVersion!.version}',
                style: TextStyle(fontSize: 15, color: cs.outline),
              ),
            ],
            const SizedBox(height: 36),
            FilledButton.icon(
              onPressed: () => setState(() {
                _phase      = _Phase.idle;
                _newVersion = null;
                _status     = const UpdateStatus.idle();
              }),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stage label ────────────────────────────────────────────────────────────

  String _stageLabel(String stage) => switch (stage) {
        'downloading' => 'Downloading…',
        'validating'  => 'Validating…',
        'backing_up'  => 'Backing up…',
        'staging'     => 'Staging files…',
        'restarting'  => 'Restarting…',
        _             => 'Processing…',
      };
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.version, required this.loading});
  final UpdateVersionInfo? version;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.memory_outlined,
                  color: cs.onPrimaryContainer, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Version',
                      style: TextStyle(fontSize: 12, color: cs.outline)),
                  const SizedBox(height: 4),
                  loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          version?.version ?? '—',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                  if (version?.hasDate == true)
                    Text(
                      version!.updatedAt!,
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.visible,
    required this.onToggle,
  });
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text('Update PIN',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.primary)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              obscureText: !visible,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'PIN',
                hintText: 'Required for all update operations',
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    visible ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: onToggle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionHeader extends StatelessWidget {
  const _OptionHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
