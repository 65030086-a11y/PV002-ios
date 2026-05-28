import 'package:flutter/material.dart';

import '../services/device_client.dart';
import 'dashboard_config_page.dart';
import 'pi_network_page.dart';
import 'pi_wifi_page.dart';
import 'pi_power_view_page.dart';
import 'pi_meter_actions_page.dart';

class PiSettingsPage extends StatelessWidget {
  const PiSettingsPage({super.key, required this.client});

  final DeviceClient client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SettingsTile(
            icon: Icons.lan_outlined,
            iconColor: const Color(0xFF1565C0),
            title: 'Network',
            subtitle: 'IP, subnet, gateway, DNS, TCP port',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PiNetworkPage(client: client),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.wifi_outlined,
            iconColor: const Color(0xFF00796B),
            title: 'WiFi',
            subtitle: 'SSID and password',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PiWifiPage(client: client),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.tune_outlined,
            iconColor: const Color(0xFF6A1B9A),
            title: 'PowerView Config',
            subtitle: 'CT type, electricity rate, carbon factor, VI gain',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PiPowerViewPage(client: client),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.tune_outlined,
            iconColor: const Color(0xFFE65100),
            title: 'Dashboard Layout',
            subtitle: 'Assign meter values to each display slot',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DashboardConfigPage(client: client),
              ),
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          _SettingsTile(
            icon: Icons.restart_alt,
            iconColor: const Color(0xFFC62828),
            title: 'Meter Actions',
            subtitle: 'Reset energy counters',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PiMeterActionsPage(client: client),
              ),
            ),
          ),
        ],
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
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
