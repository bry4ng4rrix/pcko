import 'package:flutter/material.dart';

/// Barre de contrôle média (précédent / lecture-pause / suivant), fixée en
/// bas de la page Tools.
class MediaControlBar extends StatelessWidget {
  const MediaControlBar({
    super.key,
    required this.isPlaying,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              iconSize: 28,
              icon: const Icon(Icons.skip_previous),
              color: color,
              onPressed: onPrevious,
            ),
            IconButton(
              iconSize: 40,
              icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
              color: color,
              onPressed: onPlayPause,
            ),
            IconButton(
              iconSize: 28,
              icon: const Icon(Icons.skip_next),
              color: color,
              onPressed: onNext,
            ),
          ],
        ),
      ),
    );
  }
}
