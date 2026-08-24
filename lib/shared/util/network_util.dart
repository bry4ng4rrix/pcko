import 'dart:io';

/// Retourne l'adresse IPv4 locale de la machine sur le réseau LAN
/// (celle utilisée par le téléphone pour se connecter), ou `null`
/// si aucune interface réseau utilisable n'est trouvée.
Future<String?> getLocalIpAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    // On privilégie une adresse privée classique (192.168.x, 10.x, 172.16-31.x)
    // pour éviter de choisir par erreur une interface virtuelle (docker, vpn...).
    String? fallback;
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (addr.isLoopback) continue;
        final ip = addr.address;
        if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
          return ip;
        }
        if (ip.startsWith('172.')) {
          final second = int.tryParse(ip.split('.')[1]) ?? 0;
          if (second >= 16 && second <= 31) return ip;
        }
        fallback ??= ip;
      }
    }
    return fallback;
  } catch (_) {
    return null;
  }
}
