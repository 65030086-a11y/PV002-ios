import 'package:flutter/material.dart';
import 'usb_connect_dialog.dart';
import '../services/device_client.dart';
import '../services/device_storage.dart';
import '../services/discovery_service.dart';
import 'connection_status_badge.dart';
import 'data_source_page.dart';
import 'history_page.dart';
import 'meter_data_page.dart';
import 'pi_ap_dialog.dart';
import 'monitor_page.dart';
import 'alarm_page.dart';
import 'update_page.dart';
import 'dashboard_config_page.dart';
import 'pi_about_page.dart';
import 'pi_network_page.dart';
import 'pi_wifi_page.dart';
import 'pi_power_view_page.dart';
import 'pi_meter_actions_page.dart';
// ── Page ──────────────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client});

  final DeviceClient client;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // PI_AP hotspot well-known address (see WifiController setup.sh)
  static const _piApHost = '192.168.50.1';
  static const _piApPort = 5555;
  String? _selectedPort;

  final _logController = TextEditingController();

  // Current device state — populated by one of the three connect actions.
  String _host       = '';
  int    _port       = 5555;
  String _deviceName = '';

  bool _busy      = false;
  bool _connected = false;
  int  _navIndex  = 0;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onClientChanged);
    _loadSavedDevice();
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClientChanged);
    _logController.dispose();
    widget.client.close();
    super.dispose();
  }

  void _onClientChanged() {
    if (!mounted) return;

    final wasConnected = _connected;
    final wasUsb = widget.client.mode == ConnectionMode.usb;

    setState(() {
      _connected = widget.client.isConnected;
      if (wasConnected && !_connected) {
        _navIndex = 0;
      }
    });

    // USB dropped unexpectedly → auto-reopen port picker after short delay
    if (wasConnected && !widget.client.isConnected && wasUsb) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted || widget.client.isConnected) return;
        _connectViaUsb();
      });
    }
  }

  /// Restore the last successfully-connected device so its name/IP can be
  /// shown on the connected app bar after the user reconnects.
  Future<void> _loadSavedDevice() async {
    final saved = await DeviceStorage.load();
    if (saved == null || !mounted) return;
    setState(() {
      _host       = saved.host;
      _port       = saved.port;
      _deviceName = saved.name;
    });
  }

  // ── Root build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_connected) return _buildConnectScreen();
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 600;
      return _buildConnectedScaffold(wide: wide);
    });
  }

  // ── Pre-connection screen ─────────────────────────────────────────────────

  Widget _buildConnectScreen() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── App logo ────────────────────────────────────────────
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cs.primary, cs.tertiary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.bolt,
                          size: 36, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'PowerView Manager',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'เลือกวิธีเชื่อมต่อกับ PowerView',
                    style: TextStyle(color: cs.outline, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),

                  // ── 3 connect cards ─────────────────────────────────────
                  _ConnectCard(
                    icon: Icons.wifi,
                    title: 'Connect via Wi-Fi',
                    subtitle: 'เชื่อมผ่าน network เดียวกัน',
                    busy: _busy,
                    onTap: _busy ? null : _connectViaWifi,
                  ),
                  const SizedBox(height: 12),
                  _ConnectCard(
                    icon: Icons.wifi_tethering,
                    title: 'Connect via PI AP',
                    subtitle: 'เชื่อมผ่าน AP ของ Raspberry Pi',
                    busy: _busy,
                    onTap: _busy ? null : _connectViaPiAp,
                  ),
                  const SizedBox(height: 12),
                  _ConnectCard(
                    icon: Icons.usb,
                    title: 'Connect via USB',
                    busy: _busy,
                    onTap: _busy ? null : _connectViaUsb,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Connected scaffold ────────────────────────────────────────────────────

  Widget _buildConnectedScaffold({required bool wide}) {
    // Always wrap IndexedStack in Expanded inside a Row so it receives tight
    // constraints regardless of orientation.  The portrait-blank bug was caused
    // by the old _narrowConnectedBody() putting IndexedStack as a direct child
    // of SafeArea (loose constraints), while the wide layout used Expanded
    // (tight constraints).  Now the structure is identical in both orientations.
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: _buildConnectedAppBar(),
      body: Row(
        children: [
          if (wide) ...[
            _buildNavRail(),
            const VerticalDivider(width: 1, thickness: 1),
          ],
          Expanded(
            child: IndexedStack(index: _navIndex, children: _tabBodies()),
          ),
        ],
      ),
      bottomNavigationBar: wide ? null : _buildBottomNav(),
    );
  }

  Widget _buildNavRail() {
    return NavigationRail(
      selectedIndex: _navIndex,
      onDestinationSelected: (i) => setState(() => _navIndex = i),
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.monitor_outlined),
          selectedIcon: Icon(Icons.monitor),
          label: Text('Dashboard'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.electric_meter_outlined),
          selectedIcon: Icon(Icons.electric_meter),
          label: Text('Live Data'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history),
          label: Text('History'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
      ],
    );
  }

  /// Tab body list — order must match navigation destinations.
  List<Widget> _tabBodies() => [
        // 0 — Dashboard (live Pi display)
        MonitorPage(
          host: _host,
          screenSharePort: _port + 1,
          client: widget.client,
          embedded: true,
        ),
        // 1 — Live Data (meter readings)
        MeterDataPage(client: widget.client, isActive: _navIndex == 1),
        // 2 — History (kWh logs read from Pi's flash)
        HistoryPage(client: widget.client),
        // 3 — Settings
        _SettingsTabContent(
          client: widget.client,
          onDataSourceChanged: _onDataSourceChanged,
        ),
      ];

  NavigationBar _buildBottomNav() {
    return NavigationBar(
      selectedIndex: _navIndex,
      onDestinationSelected: (i) => setState(() => _navIndex = i),
      height: 64,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.monitor_outlined),
          selectedIcon: Icon(Icons.monitor),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.electric_meter_outlined),
          selectedIcon: Icon(Icons.electric_meter),
          label: 'Live Data',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history),
          label: 'History',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }

  PreferredSizeWidget _buildConnectedAppBar() {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      leading: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.bolt, size: 20, color: cs.onPrimaryContainer),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _deviceName.isNotEmpty ? _deviceName : 'PowerView',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          Text(
            _host.isEmpty ? '—' : _host,
            style: TextStyle(
              fontSize: 11,
              color: cs.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        ConnectionStatusBadge(client: widget.client),
        // Spinner shown only while a connect/disconnect operation is in
        // flight.  The no-op "Reload from Pi" button was removed — each
        // tab provides its own reload where applicable (HistoryPage, the
        // pushed Settings sub-pages, etc).
        if (_busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
          ),
        PopupMenuButton<_OverflowAction>(
          onSelected: (action) {
            switch (action) {
              case _OverflowAction.disconnect:
                _disconnect();
              case _OverflowAction.viewLog:
                _showLogSheet();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: _OverflowAction.disconnect,
              child: _MenuRow(icon: Icons.link_off, label: 'Disconnect'),
            ),
            const PopupMenuItem(
              value: _OverflowAction.viewLog,
              child: _MenuRow(icon: Icons.terminal_outlined, label: 'View Log'),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Card 1: Connect via Wi-Fi
  /// Opens the UDP-30303 scan dialog → user picks a device → TCP connect.
  Future<void> _connectViaWifi() async {
    final device = await showDialog<DiscoveredDevice>(
      context: context,
      builder: (_) => const _DiscoveryDialog(),
    );
    if (device == null || !mounted) return;
    await _connectAndSave(
      host: device.host,
      port: device.tcpPort,
      name: device.name,
      label: 'Connect Wi-Fi',
    );
  }

  /// Card 2: Connect via PI AP.
  ///
  /// First opens a guide dialog that:
  ///   1. shows the PI_AP SSID + password
  ///   2. launches the system Wi-Fi picker so the user can join it
  ///   3. waits for the user to confirm they're connected
  /// Then TCP-connects to the well-known PI_AP gateway (192.168.50.1:5555).
  Future<void> _connectViaPiAp() async {
    final joined = await PiApGuideDialog.show(context);
    if (!joined || !mounted) return;
    await _connectAndSave(
      host: _piApHost,
      port: _piApPort,
      name: 'PI_AP',
      label: 'Connect PI_AP',
    );
  }

  /// Card 3: Connect via USB CDC (no host/port to remember).
  Future<void> _connectViaUsb() async {
    await UsbConnectDialog.show(context, widget.client);
    if (widget.client.isConnected) {
      setState(() {
        _connected  = true;
        _host       = 'USB';
        _deviceName = 'PowerView USB';
      });
    }
  }

  /// Shared TCP connect + persist helper used by Wi-Fi and PI AP cards.
  Future<void> _connectAndSave({
    required String host,
    required int    port,
    required String name,
    required String label,
  }) async {
    await _run(label, () async {
      await widget.client.connectTcp(host: host, port: port);
      _connected  = true;
      _host       = host;
      _port       = port;
      _deviceName = name;
      await DeviceStorage.save(SavedDevice(
        host: host, port: port, name: name,
      ));
    });
  }

  Future<void> _disconnect() async {
    await _run('Disconnect', () async {
      await widget.client.close();
      _connected = false;
      _navIndex  = 0;
    });
  }

  /// Called when DataSourcePage is popped — no-op for now but kept as a hook.
  void _onDataSourceChanged() {
    _appendLog('Data sources updated');
  }

  void _showLogSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LogSheet(
        controller: _logController,
        onClear: () => setState(() => _logController.clear()),
      ),
    );
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _appendLog('$label: ok');
    } catch (error) {
      _appendLog('$label: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _appendLog(String text) {
    final now = DateTime.now().toIso8601String().substring(11, 19);
    _logController.text = '[$now] $text\n${_logController.text}';
  }
}

// ── Connect-screen card ───────────────────────────────────────────────────────

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.busy,
    this.subtitle,
  });

  final IconData      icon;
  final String        title;
  final String?       subtitle;
  final bool          busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final disabled = onTap == null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    size: 24, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: disabled ? cs.outline : cs.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.primary,
                      ),
                    )
                  : Icon(Icons.chevron_right, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Overflow menu enum ────────────────────────────────────────────────────────

enum _OverflowAction { disconnect, viewLog }

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

// ── Settings tab content (inline, no own Scaffold) ────────────────────────────

class _SettingsTabContent extends StatelessWidget {
  const _SettingsTabContent({
    required this.client,
    required this.onDataSourceChanged,
  });

  final DeviceClient client;
  final VoidCallback onDataSourceChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── METER ──────────────────────────────────────────────────────
        const _SectionHeader('METER'),
        _SettingsTile(
          icon: Icons.electrical_services_outlined,
          iconColor: const Color(0xFF1565C0),
          title: 'Data Source',
          subtitle: 'Meter sensors and Modbus connections',
          onTap: () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => DataSourcePage(client: client)),
            );
            onDataSourceChanged();
          },
        ),
        _SettingsTile(
          icon: Icons.tune_outlined,
          iconColor: const Color(0xFF6A1B9A),
          title: 'PowerView Config',
          subtitle: 'CT type, electricity rate, carbon factor, VI gain',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => PiPowerViewPage(client: client)),
          ),
        ),
        _SettingsTile(
          icon: Icons.dashboard_customize_outlined,
          iconColor: const Color(0xFFE65100),
          title: 'Dashboard Layout',
          subtitle: 'Assign meter values to each display slot',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
                builder: (_) => DashboardConfigPage(client: client)),
          ),
        ),
        _SettingsTile(
          icon: Icons.restart_alt,
          iconColor: const Color(0xFFC62828),
          title: 'Meter Actions',
          subtitle: 'Reset energy counters',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
                builder: (_) => PiMeterActionsPage(client: client)),
          ),
        ),

        // ── CONNECTIVITY ───────────────────────────────────────────────
        const _SectionHeader('CONNECTIVITY'),
        _SettingsTile(
          icon: Icons.lan_outlined,
          iconColor: const Color(0xFF00796B),
          title: 'Network',
          subtitle: 'IP, subnet, gateway, DNS, TCP port',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => PiNetworkPage(client: client)),
          ),
        ),
        _SettingsTile(
          icon: Icons.wifi_outlined,
          iconColor: const Color(0xFF0277BD),
          title: 'WiFi',
          subtitle: 'SSID and password',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => PiWifiPage(client: client)),
          ),
        ),

        // ── NOTIFICATIONS ──────────────────────────────────────────────
        const _SectionHeader('NOTIFICATIONS'),
        _SettingsTile(
          icon: Icons.notifications_outlined,
          iconColor: const Color(0xFFF57C00),
          title: 'Alarms',
          subtitle: 'Threshold, setpoint and unbalance alerts',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => AlarmPage(client: client)),
          ),
        ),

        // ── SYSTEM ─────────────────────────────────────────────────────
        const _SectionHeader('SYSTEM'),
        _SettingsTile(
          icon: Icons.system_update_alt_outlined,
          iconColor: const Color(0xFF6A1B9A),
          title: 'Software Update',
          subtitle: 'Install firmware updates or rollback',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => UpdatePage(client: client)),
          ),
        ),
        _SettingsTile(
          icon: Icons.info_outline,
          iconColor: const Color(0xFF455A64),
          title: 'About',
          subtitle: 'App version and device information',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => PiAboutPage(client: client)),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle:
          Text(subtitle, style: TextStyle(color: cs.outline, fontSize: 12)),
      trailing: Icon(Icons.chevron_right, color: cs.outline),
      onTap: onTap,
    );
  }
}

// ── Log bottom sheet ──────────────────────────────────────────────────────────

class _LogSheet extends StatelessWidget {
  const _LogSheet({required this.controller, required this.onClear});
  final TextEditingController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(
              children: [
                Text(
                  'Command Log',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  tooltip: 'Clear log',
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(),

          // ── Log body ─────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: TextField(
                  controller: controller,
                  readOnly: true,
                  maxLines: null,
                  expands: true,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: cs.onSurface,
                    height: 1.6,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}

// ── UDP Discovery dialog ──────────────────────────────────────────────────────

class _DiscoveryDialog extends StatefulWidget {
  const _DiscoveryDialog();

  @override
  State<_DiscoveryDialog> createState() => _DiscoveryDialogState();
}

class _DiscoveryDialogState extends State<_DiscoveryDialog> {
  bool _scanning = false;
  String _status = '';
  List<DiscoveredDevice> _devices = [];

  final _startIpCtrl = TextEditingController(text: '192.168.1.1');
  final _endIpCtrl = TextEditingController(text: '192.168.1.254');
  @override
  void initState() {
    super.initState();
    _startScan(startIp: _startIpCtrl.text, endIp: _endIpCtrl.text);
  }

  @override
  void dispose() {
    _startIpCtrl.dispose();
    _endIpCtrl.dispose();
    super.dispose();
  }

  Future<void> _startScan({String? startIp, String? endIp}) async {
    setState(() {
      _scanning = true;
      _status = '';
      _devices = [];
    });
    List<DiscoveredDevice> found = [];
    try {
      found = await discoverDevices(
        timeout: const Duration(seconds: 12),
        startIp: startIp,
        endIp: endIp,
        onProgress: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _devices = found;
      if (found.isEmpty && _status.isEmpty) {
        _status = 'No devices found.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              child: Row(
                children: [
                  Icon(Icons.wifi_find, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Scan network',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_scanning)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_status.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: Row(
                          children: [
                            Icon(
                              _status.startsWith('Found')
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                              size: 14,
                              color: _status.startsWith('Found')
                                  ? const Color(0xFF1AAB5F)
                                  : cs.outline,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _status,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.outline),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _startIpCtrl,
                              enabled: !_scanning,
                              decoration: const InputDecoration(
                                labelText: 'Start IP',
                                isDense: true,
                              ),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 13),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('–',
                                style: TextStyle(color: cs.outline)),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _endIpCtrl,
                              enabled: !_scanning,
                              decoration: const InputDecoration(
                                labelText: 'End IP',
                                isDense: true,
                              ),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_devices.isNotEmpty)
                      Column(
                        children: _devices
                            .map((d) => _DeviceListTile(
                                  device: d,
                                  onTap: () => Navigator.pop(context, d),
                                ))
                            .toList(),
                      )
                    else if (!_scanning)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.search_off,
                                  size: 36, color: cs.outlineVariant),
                              const SizedBox(height: 8),
                              Text(
                                'No PowerView devices found',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.outline),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (!_scanning)
                    TextButton.icon(
                      onPressed: () => _startScan(
                        startIp: _startIpCtrl.text.trim(),
                        endIp: _endIpCtrl.text.trim(),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Rescan'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
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

class _DeviceListTile extends StatelessWidget {
  const _DeviceListTile({required this.device, required this.onTap});
  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.electrical_services,
                  size: 20, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${device.host} : ${device.tcpPort}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontFamily: 'monospace', color: cs.outline),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Connect',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
