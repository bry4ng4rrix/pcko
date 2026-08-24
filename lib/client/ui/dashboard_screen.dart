import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/models/metrics_payload.dart';
import '../../shared/widgets/gauges.dart';
import '../websocket_client.dart';

/// Page d'accueil côté téléphone : dashboard temps réel des métriques
/// reçues du PC (jauges + courbes glissantes sur ~60 secondes).
class ClientHomeView extends StatelessWidget {
  const ClientHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientController>(
      builder: (context, client, _) {
        if (!client.isConnected && client.lastPayload == null) {
          return _NotConnectedPlaceholder(status: client.status);
        }

        final payload = client.lastPayload;
        if (payload == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.computer, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        client.serverHostname ?? payload.hostname,
                        style: Theme.of(context).textTheme.headlineSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                ProSystemMetricsRow(
                  cpu: payload.cpu,
                  gpus: payload.gpus,
                  ram: payload.ram,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Températures',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        TemperatureBadge(
                            label: 'CPU', temperatureC: payload.cpu.temperatureC),
                        const SizedBox(height: 8),
                        GpuTemperatureList(gpus: payload.gpus),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FPS écran',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(payload.screen.fps != null
                            ? '${payload.screen.fps!.toStringAsFixed(0)} FPS'
                                '${payload.screen.processName != null ? ' · ${payload.screen.processName}' : ''}'
                            : 'indisponible'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('CPU / RAM (60 dernières secondes)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 160,
                  child: _UsageLineChart(history: client.history),
                ),
                const SizedBox(height: 24),
                Text('Réseau (kb/s)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  child: _NetworkLineChart(history: client.history),
                ),
                const SizedBox(height: 16),
                Text(
                  'Interface : ${payload.network.interfaceName ?? 'indisponible'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotConnectedPlaceholder extends StatelessWidget {
  const _NotConnectedPlaceholder({required this.status});
  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final message = switch (status) {
      ConnectionStatus.connecting => 'Connexion en cours…',
      ConnectionStatus.reconnecting => 'Reconnexion en cours…',
      _ => 'Aucun PC connecté.\nRendez-vous dans l\'onglet Connexion.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _UsageLineChart extends StatelessWidget {
  const _UsageLineChart({required this.history});
  final List<MetricsPayload> history;

  @override
  Widget build(BuildContext context) {
    final cpuSpots = <FlSpot>[];
    final ramSpots = <FlSpot>[];
    for (var i = 0; i < history.length; i++) {
      final cpu = history[i].cpu.usagePercent;
      final ram = history[i].ram.usagePercent;
      if (cpu != null) cpuSpots.add(FlSpot(i.toDouble(), cpu));
      if (ram != null) ramSpots.add(FlSpot(i.toDouble(), ram));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: cpuSpots,
            isCurved: true,
            color: Colors.teal,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: ramSpots,
            isCurved: true,
            color: Colors.deepPurple,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _NetworkLineChart extends StatelessWidget {
  const _NetworkLineChart({required this.history});
  final List<MetricsPayload> history;

  @override
  Widget build(BuildContext context) {
    final downSpots = <FlSpot>[];
    final upSpots = <FlSpot>[];
    double maxY = 10;
    for (var i = 0; i < history.length; i++) {
      final down = history[i].network.downloadKbps;
      final up = history[i].network.uploadKbps;
      if (down != null) {
        downSpots.add(FlSpot(i.toDouble(), down));
        if (down > maxY) maxY = down;
      }
      if (up != null) {
        upSpots.add(FlSpot(i.toDouble(), up));
        if (up > maxY) maxY = up;
      }
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: downSpots,
            isCurved: true,
            color: Colors.blue,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: upSpots,
            isCurved: true,
            color: Colors.orange,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
