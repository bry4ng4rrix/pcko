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
    final cpuInfo = await _collectCpuInfo();
    final ram = await _collectRam();
    final temps = await _collectTemperaturesFromLhm();
    final gpus = await _collectGpus(temps.gpuTempC);
    final screen = await _collectScreen();

    return MetricsPayload(
      timestamp: DateTime.now(),
      hostname: Platform.localHostname,
      cpu: CpuMetrics(
        usagePercent: cpuInfo.usagePercent,
        temperatureC: temps.cpuTempC,
        cores: Platform.numberOfProcessors,
        frequencyGhz: cpuInfo.frequencyGhz,
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

  Future<_LhmTemperatures> _collectTemperaturesFromLhm() async {
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
      double? gpuTemp;

      void walk(Map<String, dynamic> node) {
        final text = (node['Text'] as String?)?.toLowerCase() ?? '';
        final value = node['Value'] as String?;
        if (value != null && value.contains('°C')) {
          final parsed = double.tryParse(
              value.replaceAll('°C', '').replaceAll(',', '.').trim());
          if (parsed != null) {
            if (cpuTemp == null &&
                (text.contains('cpu package') || text.contains('core (tctl'))) {
              cpuTemp = parsed;
            }
            if (gpuTemp == null && text.contains('gpu') && text.contains('core')) {
              gpuTemp = parsed;
            }
          }
        }
        final children = node['Children'] as List?;
        if (children != null) {
          for (final child in children) {
            if (child is Map<String, dynamic>) walk(child);
          }
        }
      }

      walk(root);
      _warnedNoLhm = false;
      return _LhmTemperatures(cpuTemp, gpuTemp);
    } catch (e) {
      if (!_warnedNoLhm) {
        stderr.writeln(
            '[WindowsCollector] LibreHardwareMonitor inaccessible sur le port '
            '$libreHardwareMonitorPort — températures = null. '
            'Lancez LibreHardwareMonitor avec "Remote Web Server" activé. ($e)');
        _warnedNoLhm = true;
      }
      return const _LhmTemperatures(null, null);
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

class _LhmTemperatures {
  final double? cpuTempC;
  final double? gpuTempC;
  const _LhmTemperatures(this.cpuTempC, this.gpuTempC);
}

class _CpuInfo {
  final double? usagePercent;
  final double? frequencyGhz;
  const _CpuInfo(this.usagePercent, this.frequencyGhz);
}
