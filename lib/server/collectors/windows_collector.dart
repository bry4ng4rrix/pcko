// Collecteur de métriques pour Windows.
//
// IMPORTANT : pour obtenir les températures CPU/GPU, Windows n'expose rien
// de fiable nativement. Il faut lancer en arrière-plan le logiciel gratuit
// LibreHardwareMonitor (https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)
// avec l'option "Remote Web Server" activée (Options > Remote Web Server > Run),
// par défaut sur le port 8085. Ce collecteur interroge alors
// http://localhost:<port>/data.json pour extraire les capteurs de température.
// Si ce service n'est pas lancé, les températures restent `null` (mode dégradé),
// jamais estimées.
import 'dart:convert';
import 'dart:io';

import '../../shared/models/metrics_payload.dart';
import 'metrics_collector.dart';

class WindowsMetricsCollector implements MetricsCollector {
  WindowsMetricsCollector({this.libreHardwareMonitorPort = 8085});

  /// Port de l'API HTTP locale de LibreHardwareMonitor (Remote Web Server).
  int libreHardwareMonitorPort;

  /// Nom (ou chemin complet) de l'exécutable PresentMon, voir `_collectScreen`.
  String presentMonExecutable = 'PresentMon.exe';

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 1);

  bool _warnedNoLhm = false;
  bool _warnedNoGpu = false;
  bool _warnedNoFps = false;

  @override
  Future<MetricsPayload> collect() async {
    final lhm = await _collectFromLhm();
    final cpuInfo = await _collectCpuInfo();
    final ramInfo = await _collectRam();

    final cpuUsage = lhm.cpuLoad ?? cpuInfo.usagePercent;
    final cpuTemp = lhm.cpuTemp;
    final cpuFreq = lhm.cpuFreq ?? cpuInfo.frequencyGhz;

    final ram = RamMetrics(
      usedMb: lhm.ramUsed?.toInt() ?? ramInfo.usedMb,
      totalMb: (lhm.ramUsed != null && lhm.ramFree != null) 
          ? (lhm.ramUsed! + lhm.ramFree!).toInt() 
          : ramInfo.totalMb,
      usagePercent: lhm.ramLoad ?? ramInfo.usagePercent,
    );

    List<GpuMetrics> gpus;
    if (lhm.gpus.isNotEmpty) {
      gpus = lhm.gpus;
    } else {
      gpus = await _collectGpus(lhm.cpuTemp);
    }

    final screen = await _collectScreen();

    return MetricsPayload(
      timestamp: DateTime.now(),
      hostname: Platform.localHostname,
      cpu: CpuMetrics(
        usagePercent: cpuUsage,
        temperatureC: cpuTemp,
        cores: Platform.numberOfProcessors,
        frequencyGhz: cpuFreq,
      ),
      gpus: gpus,
      ram: ram,
      network: await _collectNetwork(),
      screen: screen,
    );
  }

  Future<_CpuInfo> _collectCpuInfo() async {
    try {
      // Get-CimInstance est plus rapide et moderne que wmic (déprécié).
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'$proc = Get-CimInstance Win32_Processor; '
            r'$load = ($proc | Measure-Object -Property LoadPercentage -Average).Average; '
            r'$freq = ($proc | Measure-Object -Property CurrentClockSpeed -Average).Average; '
            r'"$load,$freq"',
      ]);
      if (result.exitCode == 0) {
        final parts = (result.stdout as String).trim().split(',');
        if (parts.length == 2) {
          final load = double.tryParse(parts[0]);
          final freqMhz = double.tryParse(parts[1]);
          return _CpuInfo(
            load,
            freqMhz != null ? freqMhz / 1000.0 : null,
          );
        }
      }
    } catch (e) {
      stderr.writeln('[WindowsCollector] Lecture CPU impossible : $e');
    }
    return const _CpuInfo(null, null);
  }

  Future<RamMetrics> _collectRam() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'$os = Get-CimInstance Win32_OperatingSystem; '
            r'"$($os.TotalVisibleMemorySize),$($os.FreePhysicalMemory)"',
      ]);
      if (result.exitCode == 0) {
        final parts = (result.stdout as String).trim().split(',');
        if (parts.length == 2) {
          final totalKb = int.tryParse(parts[0]);
          final freeKb = int.tryParse(parts[1]);
          if (totalKb != null && freeKb != null && totalKb > 0) {
            final usedKb = totalKb - freeKb;
            return RamMetrics(
              totalMb: totalKb ~/ 1024,
              usedMb: usedKb ~/ 1024,
              usagePercent: (usedKb / totalKb * 100).clamp(0, 100),
            );
          }
        }
      }
    } catch (e) {
      stderr.writeln('[WindowsCollector] Lecture RAM impossible : $e');
    }
    return const RamMetrics();
  }

  Future<NetworkMetrics> _collectNetwork() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'$c = Get-Counter "\Network Interface(*)\Bytes Received/sec","\Network Interface(*)\Bytes Sent/sec" -ErrorAction Stop; '
            r'$rx = ($c.CounterSamples | Where-Object {$_.Path -like "*received*" -and $_.InstanceName -notlike "*loopback*"} | Measure-Object -Property CookedValue -Sum).Sum; '
            r'$tx = ($c.CounterSamples | Where-Object {$_.Path -like "*sent*" -and $_.InstanceName -notlike "*loopback*"} | Measure-Object -Property CookedValue -Sum).Sum; '
            r'"$rx,$tx"',
      ]);
      if (result.exitCode == 0) {
        final parts = (result.stdout as String).trim().split(',');
        if (parts.length == 2) {
          final rxBytesPerSec = double.tryParse(parts[0]);
          final txBytesPerSec = double.tryParse(parts[1]);
          if (rxBytesPerSec != null && txBytesPerSec != null) {
            return NetworkMetrics(
              downloadKbps: rxBytesPerSec * 8 / 1000,
              uploadKbps: txBytesPerSec * 8 / 1000,
              interfaceName: 'all',
            );
          }
        }
      }
    } catch (e) {
      stderr.writeln('[WindowsCollector] Lecture réseau impossible : $e');
    }
    return const NetworkMetrics();
  }

  Future<_LhmMetrics> _collectFromLhm() async {
    try {
      final uri =
          Uri.parse('http://127.0.0.1:$libreHardwareMonitorPort/data.json');
      final request = await _httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('status ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      final root = jsonDecode(body) as Map<String, dynamic>;

      double? cpuTemp;
      double? cpuLoad;
      double? cpuFreq;
      double? ramLoad;
      double? ramUsed;
      double? ramFree;
      final gpusMap = <String, GpuMetrics>{};

      void walk(Map<String, dynamic> node, String hardwareName, String hardwareImage) {
        final text = (node['Text'] as String?) ?? '';
        final textLower = text.toLowerCase();
        final value = node['Value'] as String?;
        final children = node['Children'] as List?;
        
        final imageUrl = (node['ImageURL'] as String?) ?? '';
        
        var currentHardware = hardwareName;
        var currentImage = hardwareImage;
        if (imageUrl.startsWith('images/')) {
          currentHardware = text;
          currentImage = imageUrl;
        }

        if (value != null) {
          final cleanVal = value.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.').trim();
          final parsed = double.tryParse(cleanVal);

          if (parsed != null) {
            if (currentImage.contains('cpu.png')) {
              if (textLower.contains('cpu package') || textLower.contains('core (tctl')) {
                cpuTemp = parsed;
              } else if (textLower.contains('cpu total')) {
                cpuLoad = parsed;
              } else if (textLower.contains('cpu core #1') && textLower.contains('clock')) {
                cpuFreq = parsed / 1000.0;
              }
            } else if (currentImage.contains('ram.png') || currentHardware.toLowerCase().contains('memory')) {
              if (textLower.contains('memory') && value.contains('%')) {
                ramLoad = parsed;
              } else if (textLower.contains('used memory')) {
                ramUsed = parsed * 1024;
              } else if (textLower.contains('available memory')) {
                ramFree = parsed * 1024;
              }
            } else if (currentImage.contains('nvidia.png') || 
                       currentImage.contains('amd.png') || 
                       currentImage.contains('intel.png') || 
                       currentImage.contains('gpu.png') ||
                       currentHardware.toLowerCase().contains('graphics') ||
                       currentHardware.toLowerCase().contains('geforce') ||
                       currentHardware.toLowerCase().contains('radeon')) {
              final gpu = gpusMap[currentHardware] ?? GpuMetrics(name: currentHardware);
              
              double? usage = gpu.usagePercent;
              double? temp = gpu.temperatureC;
              int? vramUsed = gpu.vramUsedMb;
              int? vramTotal = gpu.vramTotalMb;

              if (textLower.contains('gpu core') && value.contains('%')) {
                usage = parsed;
              } else if (textLower.contains('gpu core') && value.contains('°C')) {
                temp = parsed;
              } else if (textLower.contains('gpu memory used') || (textLower.contains('gpu memory') && value.contains('MB') && textLower.contains('used'))) {
                vramUsed = parsed.toInt();
              } else if (textLower.contains('gpu memory total') || (textLower.contains('gpu memory') && value.contains('MB') && textLower.contains('total'))) {
                vramTotal = parsed.toInt();
              } else if (textLower.contains('gpu memory free')) {
                if (vramUsed != null) {
                  vramTotal = vramUsed + parsed.toInt();
                }
              }

              gpusMap[currentHardware] = GpuMetrics(
                name: currentHardware,
                usagePercent: usage,
                temperatureC: temp,
                vramUsedMb: vramUsed,
                vramTotalMb: vramTotal,
              );
            }
          }
        }

        if (children != null) {
          for (final child in children) {
            if (child is Map<String, dynamic>) {
              walk(child, currentHardware, currentImage);
            }
          }
        }
      }

      walk(root, '', '');
      _warnedNoLhm = false;
      return _LhmMetrics(
        cpuTemp: cpuTemp,
        cpuLoad: cpuLoad,
        cpuFreq: cpuFreq,
        ramLoad: ramLoad,
        ramUsed: ramUsed,
        ramFree: ramFree,
        gpus: gpusMap.values.toList(),
      );
    } catch (e) {
      if (!_warnedNoLhm) {
        stderr.writeln(
            '[WindowsCollector] LibreHardwareMonitor inaccessible sur le port '
            '$libreHardwareMonitorPort — températures/gpus = null. ($e)');
        _warnedNoLhm = true;
      }
      return const _LhmMetrics(gpus: []);
    }
  }

  /// Liste tous les GPU détectés (`nvidia-smi` renvoie une ligne par carte
  /// sur les systèmes multi-GPU). Le repli de température LibreHardwareMonitor
  /// n'est appliqué que s'il n'y a qu'un seul GPU (impossible de savoir à
  /// quelle carte associer la mesure LHM sinon). Si aucun GPU n'est détecté,
  /// renvoie une entrée unique "indisponible" plutôt qu'une liste vide.
  Future<List<GpuMetrics>> _collectGpus(double? fallbackTempFromLhm) async {
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
              temperatureC: double.tryParse(parts[1]) ??
                  (lines.length == 1 ? fallbackTempFromLhm : null),
              name: parts[2],
              vramUsedMb: int.tryParse(parts[3]),
              vramTotalMb: int.tryParse(parts[4]),
            ));
          } else if (parts.length >= 3) {
            gpus.add(GpuMetrics(
              usagePercent: double.tryParse(parts[0]),
              temperatureC: double.tryParse(parts[1]) ??
                  (lines.length == 1 ? fallbackTempFromLhm : null),
              name: parts[2],
            ));
          }
        }
        if (gpus.isNotEmpty) return gpus;
      }
    } catch (e) {
      if (!_warnedNoGpu) {
        stderr.writeln(
            '[WindowsCollector] `nvidia-smi` indisponible, usage/nom GPU = null ($e)');
        _warnedNoGpu = true;
      }
    }
    return [GpuMetrics(temperatureC: fallbackTempFromLhm)];
  }

  /// FPS réel de rendu (bureau/jeu au premier plan).
  /// Nécessite PresentMon (Intel, open-source,
  /// https://github.com/GameTechDev/PresentMon) accessible dans le PATH ou
  /// via [presentMonExecutable]. On lance une capture courte (1s) en sortie
  /// CSV sur stdout et on calcule la FPS moyenne de l'application qui a
  /// présenté le plus d'images (vraisemblablement l'appli au premier plan).
  /// Si PresentMon est absent ou la capture échoue, FPS = null (jamais estimé).
  Future<ScreenMetrics> _collectScreen() async {
    try {
      final result = await Process.run(presentMonExecutable, [
        '-stop_existing_session',
        '-no_top',
        '-timed',
        '1',
        '-output_stdout',
      ]).timeout(const Duration(seconds: 5));

      if (result.exitCode != 0) {
        throw ProcessException(
            presentMonExecutable, [], 'exit code ${result.exitCode}');
      }

      final lines = (result.stdout as String)
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.length < 2) return const ScreenMetrics();

      final header = lines.first.split(',');
      final appIndex = header.indexOf('Application');
      final msBetweenIndex = header.indexOf('MsBetweenPresents');
      if (msBetweenIndex == -1) return const ScreenMetrics();

      // Regroupe les temps entre présentations par application et retient
      // celle avec le plus d'images capturées (l'appli active au premier plan).
      final samplesByApp = <String, List<double>>{};
      for (final line in lines.skip(1)) {
        final fields = line.split(',');
        if (fields.length <= msBetweenIndex) continue;
        final ms = double.tryParse(fields[msBetweenIndex]);
        if (ms == null || ms <= 0) continue;
        final app = (appIndex != -1 && fields.length > appIndex)
            ? fields[appIndex]
            : 'inconnu';
        samplesByApp.putIfAbsent(app, () => []).add(ms);
      }
      if (samplesByApp.isEmpty) return const ScreenMetrics();

      final busiest = samplesByApp.entries
          .reduce((a, b) => a.value.length >= b.value.length ? a : b);
      final avgMs = busiest.value.reduce((a, b) => a + b) / busiest.value.length;

      _warnedNoFps = false;
      return ScreenMetrics(
        fps: avgMs > 0 ? 1000 / avgMs : null,
        processName: busiest.key,
      );
    } catch (e) {
      if (!_warnedNoFps) {
        stderr.writeln(
            '[WindowsCollector] PresentMon indisponible, FPS écran = null. '
            'Installez PresentMon (https://github.com/GameTechDev/PresentMon) et '
            'ajoutez-le au PATH (ou renseignez `presentMonExecutable`) pour '
            'activer le suivi FPS réel. ($e)');
        _warnedNoFps = true;
      }
      return const ScreenMetrics();
    }
  }
}

class _LhmMetrics {
  final double? cpuTemp;
  final double? cpuLoad;
  final double? cpuFreq;
  final double? ramLoad;
  final double? ramUsed;
  final double? ramFree;
  final List<GpuMetrics> gpus;

  const _LhmMetrics({
    this.cpuTemp,
    this.cpuLoad,
    this.cpuFreq,
    this.ramLoad,
    this.ramUsed,
    this.ramFree,
    required this.gpus,
  });
}

class _CpuInfo {
  final double? usagePercent;
  final double? frequencyGhz;
  const _CpuInfo(this.usagePercent, this.frequencyGhz);
}
