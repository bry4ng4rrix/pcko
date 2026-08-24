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

/// Affiche une température avec un code couleur selon des seuils configurables.
/// `null` => "indisponible", jamais de valeur inventée.
class TemperatureBadge extends StatelessWidget {
  const TemperatureBadge({
    super.key,
    required this.label,
    required this.temperatureC,
    this.warningThreshold = 60,
    this.criticalThreshold = 80,
  });

  final String label;
  final double? temperatureC;
  final double warningThreshold;
  final double criticalThreshold;

  @override
  Widget build(BuildContext context) {
    final temp = temperatureC;
    Color color;
    String text;
    if (temp == null) {
      color = Colors.grey;
      text = 'indisponible';
    } else {
      color = temp >= criticalThreshold
          ? Colors.red
          : (temp >= warningThreshold ? Colors.orange : Colors.green);
      text = '${temp.toStringAsFixed(1)} °C';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.thermostat, color: color, size: 20),
        const SizedBox(width: 4),
        Text('$label : ', style: Theme.of(context).textTheme.bodyMedium),
        Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: color, fontWeight: FontWeight.bold),
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

  const ProSystemMetricsRow({
    super.key,
    required this.cpu,
    required this.gpus,
    required this.ram,
  });

  @override
  Widget build(BuildContext context) {
    final primaryGpu = gpus.isNotEmpty ? gpus.first : const GpuMetrics();

    return Row(
      children: [
        Expanded(
          child: _ProMetricCard(
            title: 'CPU',
            icon: Icons.developer_board,
            usage: cpu.usagePercent,
            color: Colors.blueAccent,
            details: [
              if (cpu.frequencyGhz != null) '${cpu.frequencyGhz!.toStringAsFixed(2)} GHz',
              if (cpu.temperatureC != null) '${cpu.temperatureC!.toStringAsFixed(0)}°C',
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ProMetricCard(
            title: 'GPU',
            icon: Icons.videogame_asset,
            usage: primaryGpu.usagePercent,
            color: Colors.greenAccent.shade700,
            details: [
              if (primaryGpu.vramUsedMb != null && primaryGpu.vramTotalMb != null)
                '${(primaryGpu.vramUsedMb! / 1024).toStringAsFixed(1)}/${(primaryGpu.vramTotalMb! / 1024).toStringAsFixed(0)}G',
              if (primaryGpu.temperatureC != null) '${primaryGpu.temperatureC!.toStringAsFixed(0)}°C',
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ProMetricCard(
            title: 'RAM',
            icon: Icons.memory,
            usage: ram.usagePercent,
            color: Colors.purpleAccent,
            details: [
              if (ram.usedMb != null && ram.totalMb != null)
                '${(ram.usedMb! / 1024).toStringAsFixed(1)}/${(ram.totalMb! / 1024).toStringAsFixed(0)}G',
            ],
          ),
        ),
      ],
    );
  }
}

class _ProMetricCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double? usage;
  final Color color;
  final List<String> details;

  const _ProMetricCard({
    required this.title,
    required this.icon,
    required this.usage,
    required this.color,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = usage != null;
    final valText = hasValue ? '${usage!.toStringAsFixed(0)}%' : 'N/A';
    final progress = hasValue ? (usage! / 100.0).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            valText,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: details.map((detail) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade300,
                          fontSize: 10,
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
