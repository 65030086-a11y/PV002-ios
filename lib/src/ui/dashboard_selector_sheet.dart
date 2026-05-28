import 'package:flutter/material.dart';

import '../models/dashboard_info.dart';
import '../services/device_client.dart';

Future<void> showDashboardSelectorSheet(
  BuildContext context,
  DeviceClient client,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DashboardSelectorSheet(client: client),
  );
}

class _DashboardSelectorSheet extends StatefulWidget {
  const _DashboardSelectorSheet({required this.client});

  final DeviceClient client;

  @override
  State<_DashboardSelectorSheet> createState() =>
      _DashboardSelectorSheetState();
}

class _DashboardSelectorSheetState extends State<_DashboardSelectorSheet> {
  DashboardList? _list;
  int? _pending;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.client.getDashboardList();
      if (mounted) {
        setState(() {
          _list = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _select(int index) async {
    setState(() => _pending = index);
    try {
      final current = await widget.client.setDashboard(index);
      if (mounted) {
        setState(() {
          _pending = null;
          if (_list != null) {
            _list = DashboardList(
              dashboards: _list!.dashboards,
              current: current,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pending = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Select Dashboard',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: _load,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
              const SizedBox(height: 8),
            ],
            if (_list != null) _buildList(_list!),
          ],
        ),
      ),
    );
  }

  Widget _buildList(DashboardList list) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: list.dashboards.map((d) {
        final isCurrent = d.index == list.current;
        final isLoading = _pending == d.index;
        return _DashboardTile(
          info: d,
          isCurrent: isCurrent,
          isLoading: isLoading,
          onTap: isLoading ? null : () => _select(d.index),
        );
      }).toList(),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  const _DashboardTile({
    required this.info,
    required this.isCurrent,
    required this.isLoading,
    required this.onTap,
  });

  final DashboardInfo info;
  final bool isCurrent;
  final bool isLoading;
  final VoidCallback? onTap;

  IconData get _icon {
    switch (info.index) {
      case 0:
        return Icons.dashboard_outlined;
      case 1:
        return Icons.grid_view_outlined;
      case 2:
        return Icons.view_compact_outlined;
      default:
        return Icons.show_chart_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isCurrent ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          _icon,
          size: 20,
          color: isCurrent ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
      title: Text(
        info.name,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
          color: isCurrent ? cs.primary : null,
        ),
      ),
      trailing: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : isCurrent
              ? Icon(Icons.check_circle_rounded, color: cs.primary, size: 20)
              : null,
      onTap: onTap,
    );
  }
}
