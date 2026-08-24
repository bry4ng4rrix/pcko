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

/// Mesure le ping (aller-retour ICMP) vers [host] via la commande système
/// `ping`, une seule requête. Retourne `null` si `ping` est absent, échoue,
/// ou si l'hôte est injoignable — jamais une valeur inventée.
Future<double?> measurePingMs({String host = '8.8.8.8'}) async {
  try {
    final result = Platform.isWindows
        ? await Process.run('ping', ['-n', '1', '-w', '1000', host])
        : await Process.run('ping', ['-c', '1', '-W', '1', host]);
    if (result.exitCode != 0) return null;
    final match =
        RegExp(r'(\d+(?:[.,]\d+)?)\s*ms').firstMatch(result.stdout as String);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  } catch (_) {
    return null;
  }
}
