class PiNetworkSettings {
  PiNetworkSettings({
    required this.dhcp,
    required this.ip,
    required this.netmask,
    required this.gateway,
    required this.port,
    required this.dns,
    required this.ssid,
  });

  bool dhcp;
  String ip;
  String netmask;
  String gateway;
  int port;
  String dns;
  String ssid;
}

class WifiNetwork {
  const WifiNetwork(
      {required this.ssid, required this.signal, required this.security});

  final String ssid;
  final int signal;
  final String security;
}

class PiPowerViewSettings {
  PiPowerViewSettings({
    required this.ctType,
    required this.elecRate,
    required this.cef,
  });

  int ctType;
  double elecRate;
  double cef;
}
