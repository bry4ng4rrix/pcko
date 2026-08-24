import 'package:flutter/material.dart';

import '../models/metrics_payload.dart';

/// Jauge circulaire générique pour un pourcentage (CPU/GPU/RAM).
/// Affiche explicitement "N/A" si la valeur est indisponible (`null`),
/// plutôt que d'inventer une valeur.
class PercentGauge extends StatelessWidget {
  const PercentGauge({
    super.key,
    required this.label,
    required this.percent,
    this.size = 110,
  });

  final String label;
  final double? percent;
  final double size;

  Color _colorFor(double p) {
    if (p < 60) return Colors.green;
    if (p < 85) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final value = percent;
    final color = value == null ? Colors.grey : _colorFor(value);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: value == null ? 0 : (value.clamp(0, 100)) / 100,
                  strokeWidth: 10,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Text(
                value == null ? 'N/A' : '${value.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: value == null ? Colors.grey : null,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

String _gpuLabel(GpuMetrics gpu, int index, int total) =>
    gpu.name ?? (total > 1 ? 'GPU ${index + 1}' : 'GPU');

/// Une jauge de pourcentage par GPU détecté (gère le cas multi-GPU).
class GpuGaugesRow extends StatelessWidget {
  const GpuGaugesRow({super.key, required this.gpus});

  final List<GpuMetrics> gpus;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 16,
      children: [
        for (var i = 0; i < gpus.length; i++)
          PercentGauge(
            label: _gpuLabel(gpus[i], i, gpus.length),
            percent: gpus[i].usagePercent,
            size: 100,
          ),
      ],
    );
  }
}

/// Une température par GPU détecté (gère le cas multi-GPU).
class GpuTemperatureList extends StatelessWidget {
  const GpuTemperatureList({super.key, required this.gpus});

  final List<GpuMetrics> gpus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < gpus.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          TemperatureBadge(
            label: _gpuLabel(gpus[i], i, gpus.length),
            temperatureC: gpus[i].temperatureC,
          ),
        ],
      ],
    );
  }
}

/// Jauge linéaire de température : une ligne = un capteur (CPU, GPU 1, GPU 2…).
/// La couleur varie en continu du vert au rouge selon [warningThreshold] et
/// [criticalThreshold]. `null` => piste vide + "N/A", jamais de valeur inventée.
class TemperatureBadge extends StatelessWidget {
  const TemperatureBadge({
    super.key,
    required this.label,
    required this.temperatureC,
    this.warningThreshold = 60,
    this.criticalThreshold = 80,
    this.minC = 20,
    this.maxC = 100,
  });

  final String label;
  final double? temperatureC;
  final double warningThreshold;
  final double criticalThreshold;
  final double minC;
  final double maxC;

  Color _colorFor(double temp) {
    final t = ((temp - warningThreshold) / (criticalThreshold - warningThreshold))
        .clamp(0.0, 1.0);
    return t < 0.5
        ? Color.lerp(Colors.green, Colors.orange, t / 0.5)!
        : Color.lerp(Colors.orange, Colors.red, (t - 0.5) / 0.5)!;
  }

  @override
  Widget build(BuildContext context) {
    final temp = temperatureC;
    final color = temp == null ? Colors.grey : _colorFor(temp);
    final ratio =
        temp == null ? 0.0 : ((temp - minC) / (maxC - minC)).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: Colors.grey.withValues(alpha: 0.15)),
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    tween: Tween<double>(begin: 0, end: ratio),
                    builder: (context, animRatio, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: animRatio,
                      child: Container(color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: Text(
            temp == null ? 'N/A' : '${temp.toStringAsFixed(0)} °C',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ],
    );
  }
}

String _formatKbps(double kbps) {
  if (kbps >= 1000) return '${(kbps / 1000).toStringAsFixed(1)} Mb/s';
  return '${kbps.toStringAsFixed(0)} kb/s';
}

Color _pingColor(double ms) {
  if (ms < 50) return Colors.green;
  if (ms < 150) return Colors.orange;
  return Colors.red;
}

/// Vitesse réseau (↓/↑, en direct) et ping sur une seule ligne bien visible.
class NetworkSpeedRow extends StatelessWidget {
  const NetworkSpeedRow({super.key, required this.network});

  final NetworkMetrics network;

  @override
  Widget build(BuildContext context) {
    final pingMs = network.pingMs;
    final pingColor = pingMs == null ? Colors.grey : _pingColor(pingMs);
    final titleStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.bold);

    return Wrap(
      spacing: 20,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_downward, color: Colors.blue, size: 20),
            const SizedBox(width: 4),
            Text(
              network.downloadKbps != null
                  ? _formatKbps(network.downloadKbps!)
                  : 'N/A',
              style: titleStyle,
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_upward, color: Colors.orange, size: 20),
            const SizedBox(width: 4),
            Text(
              network.uploadKbps != null
                  ? _formatKbps(network.uploadKbps!)
                  : 'N/A',
              style: titleStyle,
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.network_ping, color: pingColor, size: 20),
            const SizedBox(width: 4),
            Text(
              pingMs != null ? '${pingMs.toStringAsFixed(0)} ms' : 'N/A',
              style: titleStyle?.copyWith(color: pingColor),
            ),
          ],
        ),
      ],
    );
  }
}

/// Petit indicateur textuel + pastille de couleur pour un état de connexion.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class ProSystemMetricsRow extends StatelessWidget {
  final CpuMetrics cpu;
  final List<GpuMetrics> gpus;
  final RamMetrics ram;
  final ScreenMetrics screen;

  const ProSystemMetricsRow({
    super.key,
    required this.cpu,
    required this.gpus,
    required this.ram,
    required this.screen,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = [];

    // 1. CPU
    cards.add(
      ProAnimatedCircularCard(
        title: 'CPU',
        icon: Icons.developer_board,
        progress: cpu.usagePercent != null ? cpu.usagePercent! / 100.0 : 0.0,
        centerText: cpu.usagePercent != null ? '${cpu.usagePercent!.toStringAsFixed(0)}%' : 'N/A',
        color: Colors.blueAccent,
        details: [
          if (cpu.frequencyGhz != null) '${cpu.frequencyGhz!.toStringAsFixed(2)} GHz',
          if (cpu.temperatureC != null) '${cpu.temperatureC!.toStringAsFixed(0)}°C',
        ],
      ),
    );

    // 2. RAM
    cards.add(
      ProAnimatedCircularCard(
        title: 'RAM',
        icon: Icons.memory,
        progress: ram.usagePercent != null ? ram.usagePercent! / 100.0 : 0.0,
        centerText: ram.usagePercent != null ? '${ram.usagePercent!.toStringAsFixed(0)}%' : 'N/A',
        color: Colors.purpleAccent,
        details: [
          if (ram.usedMb != null && ram.totalMb != null)
            '${(ram.usedMb! / 1024).toStringAsFixed(1)}/${(ram.totalMb! / 1024).toStringAsFixed(0)}G',
        ],
      ),
    );

    // 3. GPUs
    if (gpus.isEmpty) {
      cards.add(
        const ProAnimatedCircularCard(
          title: 'GPU',
          icon: Icons.videogame_asset,
          progress: 0.0,
          centerText: 'N/A',
          color: Colors.tealAccent,
          details: [],
        ),
      );
    } else {
      for (var i = 0; i < gpus.length; i++) {
        final gpu = gpus[i];
        final gpuName = gpu.name ?? (gpus.length > 1 ? 'GPU ${i + 1}' : 'GPU');
        final displayName = gpuName
            .replaceAll('GeForce', '')
            .replaceAll('Graphics', '')
            .replaceAll('Corporation', '')
            .trim();

        cards.add(
          ProAnimatedCircularCard(
            title: displayName,
            icon: Icons.videogame_asset,
            progress: gpu.usagePercent != null ? gpu.usagePercent! / 100.0 : 0.0,
            centerText: gpu.usagePercent != null ? '${gpu.usagePercent!.toStringAsFixed(0)}%' : 'N/A',
            color: i == 0 ? Colors.tealAccent.shade700 : Colors.teal.shade700,
            details: [
              if (gpu.vramUsedMb != null && gpu.vramTotalMb != null)
                '${(gpu.vramUsedMb! / 1024).toStringAsFixed(1)}/${(gpu.vramTotalMb! / 1024).toStringAsFixed(0)}G',
              if (gpu.temperatureC != null) '${gpu.temperatureC!.toStringAsFixed(0)}°C',
            ],
          ),
        );
      }
    }

    // 4. FPS Screen
    final fpsVal = screen.fps;
    final fpsProgress = fpsVal != null ? (fpsVal / 144.0).clamp(0.0, 1.0) : 0.0;
    final fpsCenterText = fpsVal != null ? fpsVal.toStringAsFixed(0) : 'N/A';
    cards.add(
      ProAnimatedCircularCard(
        title: 'Screen FPS',
        icon: Icons.speed,
        progress: fpsProgress,
        centerText: fpsCenterText,
        color: Colors.amberAccent.shade700,
        details: [
          if (screen.processName != null) screen.processName!,
          if (fpsVal != null) 'FPS',
        ],
      ),
    );

    // Group cards 2 per line
    final List<Widget> gridRows = [];
    for (var i = 0; i < cards.length; i += 2) {
      final nextIndex = i + 1;
      gridRows.add(
        Row(
          children: [
            Expanded(child: cards[i]),
            const SizedBox(width: 12),
            Expanded(
              child: nextIndex < cards.length 
                  ? cards[nextIndex] 
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (nextIndex < cards.length) {
        gridRows.add(const SizedBox(height: 12));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: gridRows,
    );
  }
}

class ProAnimatedCircularCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double progress;
  final String centerText;
  final Color color;
  final List<String> details;

  const ProAnimatedCircularCard({
    super.key,
    required this.title,
    required this.icon,
    required this.progress,
    required this.centerText,
    required this.color,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = centerText != 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: color.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade300,
                        fontSize: 11,
                      ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 70,
            height: 70,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: progress),
              builder: (context, animVal, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: CircularProgressIndicator(
                        value: animVal,
                        strokeWidth: 7,
                        backgroundColor: color.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    Text(
                      centerText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: hasValue ? Colors.white : Colors.grey,
                            fontSize: 14,
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: details.map((detail) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade300,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
