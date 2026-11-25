/// Connection types a printer can be added with (Hardware board).
const printerConnections = ['LAN', 'USB', 'BLUETOOTH'];

/// Paper widths in millimetres.
const printerPaperWidths = [58, 80];

final _ipv4 = RegExp(r'^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$');

/// True for a dotted IPv4 address such as 192.168.1.30.
bool isValidIPv4(String value) => _ipv4.hasMatch(value.trim());

/// Error for a LAN printer's host and port, or null when both are valid.
String? lanAddressError({required String host, required String port}) {
  if (!isValidIPv4(host)) return 'Enter an IP address such as 192.168.1.30';
  final p = int.tryParse(port.trim());
  if (p == null || p < 1 || p > 65535) return 'Port must be between 1 and 65535';
  return null;
}
