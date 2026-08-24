import 'dart:convert';
import 'dart:io';

import '../../shared/models/metrics_payload.dart';
import 'metrics_collector.dart';

/// Collecteur de métriques pour Linux.
/// Sources : /proc/stat (CPU), /proc/meminfo (RAM), /proc/net/dev (réseau),
/// /sys/class/thermal (température CPU, avec repli sur `sensors -j`),
/// `nvidia-smi` (GPU, uniquement si la commande est disponible).
class LinuxMetricsCollector implements MetricsCollector {
  // Interfaces réseau à ignorer car non représentatives du trafic LAN/WAN réel.
  static const _ignoredInterfacePrefixes = [
    'lo',
    'docker',
    'veth',
    'br-',
    'virbr',
    'tun',
    'tap',
  ];

  /// Dossier des logs CSV MangoHud (voir `_collectScreen`), à configurer
  /// manuellement — aucune valeur par défaut ne peut être devinée.
  String? mangoHudLogDirectory;

  // État conservé entre deux appels successifs pour calculer des deltas.
  List<int>? _prevCpuTimes;
  final Map<String, _NetSample> _prevNetSamples = {};
  DateTime? _prevNetTimestamp;
  bool _warnedNoTemp = false;
  bool _warnedNoGpu = false;
  bool _warnedNoFps = false;

  @override
  Future<MetricsPayload> collect() async {
    final cpu = await _collectCpu();
    final ram = await _collectRam();
    final network = await _collectNetwork();
    final gpus = await _collectGpus();
    final screen = await _collectScreen();

    return MetricsPayload(
      timestamp: DateTime.now(),
      hostname: Platform.localHostname,
      cpu: cpu,
      gpus: gpus,
      ram: ram,
      network: network,
      screen: screen,
    );
  }

  Future<CpuMetrics> _collectCpu() async {
    double? usagePercent;
    try {
      final lines = await File('/proc/stat').readAsLines();
      final cpuLine = lines.firstWhere((l) => l.startsWith('cpu '));
      final parts = cpuLine
          .substring(4)
          .trim()
          .split(RegExp(r'\s+'))
          .map((e) => int.parse(e))
          .toList();

      if (_prevCpuTimes != null) {
        final prev = _prevCpuTimes!;
        final idlePrev = prev[3] + (prev.length > 4 ? prev[4] : 0);
        final idleNow = parts[3] + (parts.length > 4 ? parts[4] : 0);
        final totalPrev = prev.fold<int>(0, (a, b) => a + b);
        final totalNow = parts.fold<int>(0, (a, b) => a + b);

        final totalDelta = totalNow - totalPrev;
        final idleDelta = idleNow - idlePrev;
        if (totalDelta > 0) {
          usagePercent =
              ((totalDelta - idleDelta) / totalDelta * 100).clamp(0, 100);
        }
      }
      _prevCpuTimes = parts;
    } catch (e) {
      stderr.writeln('[LinuxCollector] Lecture /proc/stat impossible : $e');
    }

    return CpuMetrics(
      usagePercent: usagePercent,
      temperatureC: await _collectCpuTemperature(),
      cores: Platform.numberOfProcessors,
      frequencyGhz: await _collectCpuFrequency(),
    );
  }

  Future<double?> _collectCpuFrequency() async {
    try {
      final file = File('/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq');
      if (await file.exists()) {
        final content = (await file.readAsString()).trim();
        final kHz = double.tryParse(content);
        if (kHz != null) {
          return kHz / 1000000.0; // convert to GHz
        }
      }
    } catch (_) {}
    try {
      final lines = await File('/proc/cpuinfo').readAsLines();
      double sum = 0;
      int count = 0;
      for (final line in lines) {
        if (line.toLowerCase().startsWith('cpu mhz')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            final mhz = double.tryParse(parts[1].trim());
            if (mhz != null) {
              sum += mhz;
              count++;
            }
          }
        }
      }
      if (count > 0) {
        return (sum / count) / 1000.0; // convert to GHz
      }
    } catch (_) {}
    return null;
  }

  Future<double?> _collectCpuTemperature() async {
    // 1) Zones thermiques du noyau.
    try {
      final thermalDir = Directory('/sys/class/thermal');
      if (await thermalDir.exists()) {
        final zones = await thermalDir
            .list()
            .where((e) => e.path.contains('thermal_zone'))
            .toList();

        _ThermalZone? best;
        for (final zone in zones) {
          final typeFile = File('${zone.path}/type');
          final tempFile = File('${zone.path}/temp');
          if (!await tempFile.exists()) continue;
          final type = await typeFile.exists()
              ? (await typeFile.readAsString()).trim().toLowerCase()
              : '';
          final rawTemp = int.tryParse((await tempFile.readAsString()).trim());
          if (rawTemp == null) continue;
          final candidate = _ThermalZone(type, rawTemp / 1000.0);
          // Priorité aux zones explicitement liées au CPU.
          if (type.contains('x86_pkg_temp') ||
              type.contains('cpu') ||
              type.contains('coretemp')) {
            return candidate.tempC;
          }
          best ??= candidate;
        }
        if (best != null) return best.tempC;
      }
    } catch (e) {
      stderr.writeln('[LinuxCollector] Lecture thermal_zone impossible : $e');
    }

    // 2) Repli sur `sensors -j` (paquet lm-sensors).
    try {
      final result = await Process.run('sensors', ['-j']);
      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
        for (final chip in data.values) {
          if (chip is! Map<String, dynamic>) continue;
          for (final entry in chip.entries) {
            final value = entry.value;
            if (value is! Map<String, dynamic>) continue;
            for (final sub in value.entries) {
              if (sub.key.toString().startsWith('temp') &&
                  sub.value is num) {
                return (sub.value as num).toDouble();
              }
            }
          }
        }
      }
    } catch (e) {
      if (!_warnedNoTemp) {
        stderr.writeln(
            '[LinuxCollector] `sensors` indisponible, température CPU = null ($e)');
        _warnedNoTemp = true;
      }
    }

    if (!_warnedNoTemp) {
      stderr.writeln(
          '[LinuxCollector] Aucune source de température CPU trouvée (installez lm-sensors).');
      _warnedNoTemp = true;
    }
    return null;
  }

  Future<RamMetrics> _collectRam() async {
    try {
      final lines = await File('/proc/meminfo').readAsLines();
      int? totalKb;
      int? availableKb;
      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          totalKb = int.tryParse(RegExp(r'\d+').firstMatch(line)?.group(0) ?? '');
        } else if (line.startsWith('MemAvailable:')) {
          availableKb =
              int.tryParse(RegExp(r'\d+').firstMatch(line)?.group(0) ?? '');
        }
      }
      if (totalKb != null && availableKb != null) {
        final totalMb = totalKb ~/ 1024;
        final usedMb = (totalKb - availableKb) ~/ 1024;
        final usagePercent = totalKb > 0
            ? ((totalKb - availableKb) / totalKb * 100).clamp(0.0, 100.0)
            : null;
        return RamMetrics(
          usedMb: usedMb,
          totalMb: totalMb,
          usagePercent: usagePercent,
        );
      }
    } catch (e) {
      stderr.writeln('[LinuxCollector] Lecture /proc/meminfo impossible : $e');
    }
    return const RamMetrics();
  }

  Future<NetworkMetrics> _collectNetwork() async {
    try {
      final now = DateTime.now();
      final lines = await File('/proc/net/dev').readAsLines();
      final samples = <String, _NetSample>{};

      for (final line in lines.skip(2)) {
        final colonIndex = line.indexOf(':');
        if (colonIndex == -1) continue;
        final name = line.substring(0, colonIndex).trim();
        if (_ignoredInterfacePrefixes.any((p) => name.startsWith(p))) continue;

        final fields = line
            .substring(colonIndex + 1)
            .trim()
            .split(RegExp(r'\s+'))
            .map((e) => int.tryParse(e) ?? 0)
            .toList();
        if (fields.length < 9) continue;
        samples[name] = _NetSample(rxBytes: fields[0], txBytes: fields[8]);
      }

      String? activeInterface;
      double? downloadKbps;
      double? uploadKbps;

      if (_prevNetTimestamp != null && _prevNetSamples.isNotEmpty) {
        final elapsedSeconds =
            now.difference(_prevNetTimestamp!).inMilliseconds / 1000.0;
        if (elapsedSeconds > 0) {
          int bestDelta = -1;
          for (final entry in samples.entries) {
            final prev = _prevNetSamples[entry.key];
            if (prev == null) continue;
            final rxDelta = entry.value.rxBytes - prev.rxBytes;
            final txDelta = entry.value.txBytes - prev.txBytes;
            final totalDelta = rxDelta + txDelta;
            if (totalDelta > bestDelta) {
              bestDelta = totalDelta;
              activeInterface = entry.key;
              downloadKbps = (rxDelta * 8 / 1000) / elapsedSeconds;
              uploadKbps = (txDelta * 8 / 1000) / elapsedSeconds;
            }
          }
        }
      }

      _prevNetSamples
        ..clear()
        ..addAll(samples);
      _prevNetTimestamp = now;

      return NetworkMetrics(
        downloadKbps: downloadKbps,
        uploadKbps: uploadKbps,
        interfaceName: activeInterface,
      );
    } catch (e) {
      stderr.writeln('[LinuxCollector] Lecture /proc/net/dev impossible : $e');
      return const NetworkMetrics();
    }
  }

  /// Liste tous les GPU détectés (`nvidia-smi` renvoie une ligne par carte
  /// sur les systèmes multi-GPU). Si aucun GPU n'est détecté, renvoie une
  /// entrée unique "indisponible" plutôt qu'une liste vide.
  Future<List<GpuMetrics>> _collectGpus() async {
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=utilization.gpu,temperature.gpu,name,memory.used,memory.total',
        '--format=csv,noheader,nounits',
      ]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .trim()
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        final gpus = <GpuMetrics>[];
        for (final line in lines) {
          final parts = line.split(',').map((e) => e.trim()).toList();
          if (parts.length >= 5) {
            gpus.add(GpuMetrics(
              usagePercent: double.tryParse(parts[0]),
              temperatureC: double.tryParse(parts[1]),
              name: parts[2],
              vramUsedMb: int.tryParse(parts[3]),
              vramTotalMb: int.tryParse(parts[4]),
            ));
          } else if (parts.length >= 3) {
            gpus.add(GpuMetrics(
              usagePercent: double.tryParse(parts[0]),
              temperatureC: double.tryParse(parts[1]),
              name: parts[2],
            ));
          }
        }
        if (gpus.isNotEmpty) return gpus;
      }
    } catch (e) {
      if (!_warnedNoGpu) {
        stderr.writeln(
            '[LinuxCollector] `nvidia-smi` indisponible, métriques GPU = null ($e)');
        _warnedNoGpu = true;
      }
    }
    return const [GpuMetrics()];
  }

  /// FPS réel de rendu (bureau/jeu au premier plan).
  /// Nécessite MangoHud (https://github.com/flightlx/MangoHud) installé et
  /// configuré pour journaliser en CSV : dans `~/.config/MangoHud/MangoHud.conf`,
  /// définir `output_folder=<dossier>` puis renseigner ce même dossier dans
  /// [mangoHudLogDirectory]. On lit le fichier `.csv` le plus récent de ce
  /// dossier et on prend la dernière valeur de la colonne `fps`.
  /// Si MangoHud n'est pas configuré ou aucun log n'est trouvé, FPS = null
  /// (jamais une valeur estimée).
  Future<ScreenMetrics> _collectScreen() async {
    final dirPath = mangoHudLogDirectory;
    if (dirPath == null) {
      if (!_warnedNoFps) {
        stderr.writeln(
            '[LinuxCollector] Aucun `mangoHudLogDirectory` configuré, FPS écran = null. '
            'Installez MangoHud et définissez `output_folder=<dossier>` dans MangoHud.conf '
            'pour activer le suivi FPS réel.');
        _warnedNoFps = true;
      }
      return const ScreenMetrics();
    }

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return const ScreenMetrics();

      final csvFiles =
          await dir.list().where((e) => e.path.endsWith('.csv')).toList();
      if (csvFiles.isEmpty) return const ScreenMetrics();

      csvFiles.sort((a, b) => File(b.path)
          .statSync()
          .modified
          .compareTo(File(a.path).statSync().modified));
      final latest = File(csvFiles.first.path);
      final lines = await latest.readAsLines();
      // Format MangoHud : ligne 0 = infos système, ligne 1 = en-têtes CSV,
      // lignes suivantes = échantillons.
      if (lines.length < 3) return const ScreenMetrics();

      final header = lines[1].split(',');
      final fpsIndex = header.indexOf('fps');
      if (fpsIndex == -1) return const ScreenMetrics();

      final lastRow = lines.last.split(',');
      if (lastRow.length <= fpsIndex) return const ScreenMetrics();
      final fps = double.tryParse(lastRow[fpsIndex]);

      _warnedNoFps = false;
      return ScreenMetrics(
        fps: fps,
        processName: latest.uri.pathSegments.isNotEmpty
            ? latest.uri.pathSegments.last
            : null,
      );
    } catch (e) {
      if (!_warnedNoFps) {
        stderr.writeln(
            '[LinuxCollector] Lecture du log MangoHud impossible, FPS écran = null ($e)');
        _warnedNoFps = true;
      }
      return const ScreenMetrics();
    }
  }
}

class _NetSample {
  final int rxBytes;
  final int txBytes;
  const _NetSample({required this.rxBytes, required this.txBytes});
}

class _ThermalZone {
  final String type;
  final double tempC;
  const _ThermalZone(this.type, this.tempC);
}
