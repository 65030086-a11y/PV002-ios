class DashboardInfo {
  const DashboardInfo({required this.index, required this.name});

  final int index;
  final String name;

  factory DashboardInfo.fromJson(Map<String, dynamic> json) {
    return DashboardInfo(
      index: (json['index'] as num).toInt(),
      name: json['name']?.toString() ?? '',
    );
  }
}

class DashboardList {
  const DashboardList({required this.dashboards, required this.current});

  final List<DashboardInfo> dashboards;
  final int current;

  factory DashboardList.fromJson(Map<String, dynamic> json) {
    final list = (json['dashboards'] as List<dynamic>? ?? [])
        .map((e) => DashboardInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return DashboardList(
      dashboards: list,
      current: (json['current'] as num?)?.toInt() ?? 0,
    );
  }
}
