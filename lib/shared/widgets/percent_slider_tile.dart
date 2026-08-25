import 'package:flutter/material.dart';

/// Carte avec icône, libellé, slider et pourcentage — utilisée pour le
/// volume et la luminosité sur la page Tools.
class PercentSliderTile extends StatelessWidget {
  const PercentSliderTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final IconData icon;
  final String label;

  /// `null` tant que la valeur n'a pas encore été reçue du PC.
  final int? value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final displayValue = value ?? 0;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 16),
                    ),
                    child: Slider(
                      value: displayValue.clamp(0, 100).toDouble(),
                      min: 0,
                      max: 100,
                      activeColor: color,
                      onChanged: value == null
                          ? null
                          : (v) => onChanged(v.round()),
                      onChangeEnd: value == null || onChangeEnd == null
                          ? null
                          : (v) => onChangeEnd!(v.round()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 40,
              child: Text(
                value == null ? '—' : '$displayValue%',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
