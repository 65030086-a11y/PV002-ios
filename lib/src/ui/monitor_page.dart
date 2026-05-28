import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_client.dart';
import 'dashboard_selector_sheet.dart';

const _kPollInterval = Duration(milliseconds: 200); // ~5 fps target
const _kRequestTimeout = Duration(seconds: 5);

Uri _screenshotUri(String host, int port) {
  return Uri(
    scheme: 'http',
    host: _normalizeHost(host),
    port: port,
    path: '/screenshot',
  );
}

String _normalizeHost(String host) {
  final trimmed = host.trim();
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.host.isNotEmpty) {
    return parsed.host;
  }

  final withoutPath = trimmed.split('/').first;
  if (withoutPath.contains(':')) {
    return withoutPath.split(':').first;
  }
  return withoutPath;
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({
    super.key,
    required this.host,
    this.screenSharePort = 5556,
    required this.client,
    this.embedded = false,
    this.enablePolling = true,
  });

  final String host;
  final int screenSharePort;
  final DeviceClient client;
  final bool embedded;
  final bool enablePolling;

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  Uint8List? _frame;
  bool _connected = false;
  int _fps = 0;
  String? _lastError;

  // FPS counter
  int _frameCount = 0;
  DateTime _fpsWindow = DateTime.now();

  bool _fetching = false;
  bool _alive = true;

  final _httpClient = HttpClient()
    ..connectionTimeout = _kRequestTimeout
    ..idleTimeout = const Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    if (!widget.embedded) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    if (widget.enablePolling) {
      _fetchLoop();
    }
  }

  @override
  void dispose() {
    _alive = false;
    _httpClient.close(force: true);
    if (!widget.embedded) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  // ── Fetch loop ─────────────────────────────────────────────────────────────

  Future<void> _fetchLoop() async {
    while (_alive) {
      if (!_fetching) _fetchFrame(); // fire-and-forget
      await Future.delayed(_kPollInterval);
    }
  }

  Future<void> _fetchFrame() async {
    _fetching = true;
    try {
      // Guard every await resumption: _alive is set to false synchronously
      // in dispose(), so checking it prevents setState on defunct elements
      // even if 'mounted' momentarily lags behind the lifecycle transition.
      if (!_alive) return;
      final uri = _screenshotUri(widget.host, widget.screenSharePort);
      final request = await _httpClient.getUrl(uri).timeout(_kRequestTimeout);
      if (!_alive) return;
      final response = await request.close().timeout(_kRequestTimeout);
      if (!_alive) return;

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final chunks = <int>[];
      await response.forEach(chunks.addAll).timeout(_kRequestTimeout);
      if (!_alive) return;
      final bytes = Uint8List.fromList(chunks);

      _frameCount++;
      final now = DateTime.now();
      final elapsed = now.difference(_fpsWindow).inMilliseconds;
      if (elapsed >= 1000) {
        final fps = (_frameCount * 1000 / elapsed).round();
        _frameCount = 0;
        _fpsWindow = now;
        if (_alive && mounted) {
          setState(() {
            _frame = bytes;
            _connected = true;
            _lastError = null;
            _fps = fps;
          });
        }
      } else {
        if (_alive && mounted) {
          setState(() {
            _frame = bytes;
            _connected = true;
            _lastError = null;
          });
        }
      }
    } catch (error) {
      if (_alive && mounted) {
        setState(() {
          _connected = false;
          _lastError = '${_screenshotUri(widget.host, widget.screenSharePort)}\n$error';
        });
      }
      if (_alive) await Future.delayed(const Duration(seconds: 1));
    } finally {
      _fetching = false;
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildEmbedded(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(context),
        body: _buildBody(context),
      ),
    );
  }

  /// Renders as a plain black content area with a minimal floating action row
  /// (status dot + fps + fullscreen button) suitable for embedding in a tab.
  Widget _buildEmbedded(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ColoredBox(color: Colors.black, child: _buildBody(context)),
        ),

        // ── Minimal overlay ────────────────────────────────────────────
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ConnectionDot(connected: _connected),
                const SizedBox(width: 6),
                Text(
                  _connected ? '$_fps fps' : 'Connecting…',
                  style: TextStyle(
                    color:
                        _connected ? const Color(0xFF1AAB5F) : Colors.white38,
                    fontSize: 10,
                  ),
                ),
                if (widget.client != null) ...[
                  const SizedBox(width: 20),
                  GestureDetector(
                    onTap: () =>
                        showDashboardSelectorSheet(context, widget.client!),
                    child: const Icon(Icons.dashboard_customize_outlined,
                        size: 18, color: Colors.white70),
                  ),
                ],
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: _enterFullscreen,
                  child: const Icon(Icons.fullscreen,
                      size: 18, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF0D0D0D),
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          const Text(
            'Monitor',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(width: 10),
          _ConnectionDot(connected: _connected),
          const SizedBox(width: 6),
          Text(
            _connected ? '$_fps fps' : 'Connecting…',
            style: TextStyle(
              fontSize: 11,
              color: _connected ? const Color(0xFF1AAB5F) : Colors.white38,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.client != null)
          IconButton(
            tooltip: 'Switch dashboard',
            icon: const Icon(Icons.dashboard_customize_outlined, size: 22),
            onPressed: () =>
                showDashboardSelectorSheet(context, widget.client!),
          ),
        IconButton(
          tooltip: 'Fullscreen',
          icon: const Icon(Icons.fullscreen, size: 22),
          onPressed: _enterFullscreen,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_frame == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monitor_outlined, size: 72, color: Colors.white12),
            const SizedBox(height: 20),
            Text(
              widget.embedded
                  ? 'Connecting to Pi display…'
                  : 'Connecting to ${widget.host}:${widget.screenSharePort}',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            if (_lastError != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _lastError!,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white24,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // ── Display ─────────────────────────────────────────────────────
        InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Center(
            child: Image.memory(
              _frame!,
              gaplessPlayback: true,
              fit: BoxFit.contain,
            ),
          ),
        ),

        // ── Disconnected overlay ────────────────────────────────────────
        if (!_connected)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.signal_wifi_off, size: 48, color: Colors.white54),
                  SizedBox(height: 12),
                  Text(
                    'Connection lost — retrying…',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    // Restore on next back press via WillPopScope or just rely on Navigator.pop
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _FullscreenViewer(
          frame: _frame,
          host: widget.host,
          screenSharePort: widget.screenSharePort,
          onFrameUpdate: (bytes) {
            if (mounted) setState(() => _frame = bytes);
          },
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    ).then((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }
}

// ── Fullscreen overlay ────────────────────────────────────────────────────────

class _FullscreenViewer extends StatefulWidget {
  const _FullscreenViewer({
    required this.frame,
    required this.host,
    required this.screenSharePort,
    required this.onFrameUpdate,
  });

  final Uint8List? frame;
  final String host;
  final int screenSharePort;
  final ValueChanged<Uint8List> onFrameUpdate;

  @override
  State<_FullscreenViewer> createState() => _FullscreenViewerState();
}

class _FullscreenViewerState extends State<_FullscreenViewer> {
  Uint8List? _frame;
  bool _alive = true;
  bool _fetching = false;

  final _http = HttpClient()
    ..connectionTimeout = _kRequestTimeout
    ..idleTimeout = const Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _frame = widget.frame;
    _fetchLoop();
  }

  @override
  void dispose() {
    _alive = false;
    _http.close(force: true);
    super.dispose();
  }

  Future<void> _fetchLoop() async {
    while (_alive) {
      if (!_fetching) _fetchFrame();
      await Future.delayed(_kPollInterval);
    }
  }

  Future<void> _fetchFrame() async {
    _fetching = true;
    try {
      if (!_alive) return;
      final req = await _http
          .getUrl(_screenshotUri(widget.host, widget.screenSharePort))
          .timeout(_kRequestTimeout);
      if (!_alive) return;
      final res = await req.close().timeout(_kRequestTimeout);
      if (!_alive) return;
      if (res.statusCode != 200) throw Exception();
      final chunks = <int>[];
      await res.forEach(chunks.addAll).timeout(_kRequestTimeout);
      if (!_alive) return;
      final bytes = Uint8List.fromList(chunks);
      if (_alive && mounted) {
        setState(() => _frame = bytes);
        widget.onFrameUpdate(bytes);
      }
    } catch (_) {
      if (_alive) await Future.delayed(const Duration(seconds: 1));
    } finally {
      _fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: _frame == null
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white24),
              )
            : InteractiveViewer(
                minScale: 0.8,
                maxScale: 6.0,
                child: SizedBox.expand(
                  child: Image.memory(
                    _frame!,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
      ),
    );
  }
}

// ── Connection dot indicator ──────────────────────────────────────────────────

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected ? const Color(0xFF1AAB5F) : Colors.red.shade400,
        boxShadow: connected
            ? [
                BoxShadow(
                  color: const Color(0xFF1AAB5F).withValues(alpha: 0.5),
                  blurRadius: 6,
                )
              ]
            : null,
      ),
    );
  }
}
