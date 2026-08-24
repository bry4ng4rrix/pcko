// Modèle de données partagé entre le serveur (PC) et le client (Android).
// Respecte strictement le contrat JSON défini dans PROMPT.md.
// Règle importante : un champ numérique indisponible doit être `null`,
// jamais une valeur inventée (0 par défaut par exemple).

double? _toDouble(dynamic value) =>
    value == null ? null : (value as num).toDouble();

int? _toInt(dynamic value) => value == null ? null : (value as num).toInt();

class CpuMetrics {
  final double? usagePercent;
  final double? temperatureC;
  final int? cores;
  final double? frequencyGhz;

  const CpuMetrics({
    this.usagePercent,
    this.temperatureC,
    this.cores,
    this.frequencyGhz,
  });

  factory CpuMetrics.fromJson(Map<String, dynamic> json) => CpuMetrics(
        usagePercent: _toDouble(json['usage_percent']),
        temperatureC: _toDouble(json['temperature_c']),
        cores: _toInt(json['cores']),
        frequencyGhz: _toDouble(json['frequency_ghz']),
      );

  Map<String, dynamic> toJson() => {
        'usage_percent': usagePercent,
        'temperature_c': temperatureC,
        'cores': cores,
        'frequency_ghz': frequencyGhz,
      };
}

class GpuMetrics {
  final double? usagePercent;
  final double? temperatureC;
  final String? name;
  final int? vramUsedMb;
  final int? vramTotalMb;

  const GpuMetrics({
    this.usagePercent,
    this.temperatureC,
    this.name,
    this.vramUsedMb,
    this.vramTotalMb,
  });

  factory GpuMetrics.fromJson(Map<String, dynamic> json) => GpuMetrics(
        usagePercent: _toDouble(json['usage_percent']),
        temperatureC: _toDouble(json['temperature_c']),
        name: json['name'] as String?,
        vramUsedMb: _toInt(json['vram_used_mb']),
        vramTotalMb: _toInt(json['vram_total_mb']),
      );

  Map<String, dynamic> toJson() => {
        'usage_percent': usagePercent,
        'temperature_c': temperatureC,
        'name': name,
        'vram_used_mb': vramUsedMb,
        'vram_total_mb': vramTotalMb,
      };
}

/// FPS réel de rendu de l'écran (bureau/jeu au premier plan), mesuré via un
/// outil externe (PresentMon sur Windows, MangoHud sur Linux). `null` si cet
/// outil n'est pas installé/configuré — jamais une valeur estimée.
class ScreenMetrics {
  final double? fps;
  final String? processName;

  const ScreenMetrics({this.fps, this.processName});

  factory ScreenMetrics.fromJson(Map<String, dynamic> json) => ScreenMetrics(
        fps: _toDouble(json['fps']),
        processName: json['process'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'fps': fps,
        'process': processName,
      };
}

class RamMetrics {
  final int? usedMb;
  final int? totalMb;
  final double? usagePercent;

  const RamMetrics({this.usedMb, this.totalMb, this.usagePercent});

  factory RamMetrics.fromJson(Map<String, dynamic> json) => RamMetrics(
        usedMb: _toInt(json['used_mb']),
        totalMb: _toInt(json['total_mb']),
        usagePercent: _toDouble(json['usage_percent']),
      );

  Map<String, dynamic> toJson() => {
        'used_mb': usedMb,
        'total_mb': totalMb,
        'usage_percent': usagePercent,
      };
}

class NetworkMetrics {
  final double? downloadKbps;
  final double? uploadKbps;
  final String? interfaceName;

  const NetworkMetrics(
      {this.downloadKbps, this.uploadKbps, this.interfaceName});

  factory NetworkMetrics.fromJson(Map<String, dynamic> json) =>
      NetworkMetrics(
        downloadKbps: _toDouble(json['download_kbps']),
        uploadKbps: _toDouble(json['upload_kbps']),
        interfaceName: json['interface'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'download_kbps': downloadKbps,
        'upload_kbps': uploadKbps,
        'interface': interfaceName,
      };
}

class MetricsPayload {
  final DateTime timestamp;
  final String hostname;
  final CpuMetrics cpu;
  final List<GpuMetrics> gpus;
  final RamMetrics ram;
  final NetworkMetrics network;
  final ScreenMetrics screen;

  const MetricsPayload({
    required this.timestamp,
    required this.hostname,
    required this.cpu,
    required this.gpus,
    required this.ram,
    required this.network,
    required this.screen,
  });

  factory MetricsPayload.fromJson(Map<String, dynamic> json) =>
      MetricsPayload(
        timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
        hostname: json['hostname'] as String? ?? 'inconnu',
        cpu: CpuMetrics.fromJson(
            (json['cpu'] as Map?)?.cast<String, dynamic>() ?? const {}),
        gpus: (json['gpus'] as List?)
                ?.map((e) =>
                    GpuMetrics.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        ram: RamMetrics.fromJson(
            (json['ram'] as Map?)?.cast<String, dynamic>() ?? const {}),
        network: NetworkMetrics.fromJson(
            (json['network'] as Map?)?.cast<String, dynamic>() ?? const {}),
        screen: ScreenMetrics.fromJson(
            (json['screen'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );

  Map<String, dynamic> toJson() => {
        'type': 'metrics',
        'timestamp': timestamp.toUtc().toIso8601String(),
        'hostname': hostname,
        'cpu': cpu.toJson(),
        'gpus': gpus.map((g) => g.toJson()).toList(),
        'ram': ram.toJson(),
        'network': network.toJson(),
        'screen': screen.toJson(),
      };
}
