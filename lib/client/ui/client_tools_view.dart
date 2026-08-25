import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/media_control_bar.dart';
import '../../shared/widgets/percent_slider_tile.dart';
import '../../shared/widgets/tool_button.dart';
import '../websocket_client.dart';

/// Page Tools côté téléphone : contrôle à distance du PC connecté
/// (verrouillage, gestionnaire de tâches, volume, luminosité, média,
/// capture d'écran/vidéo), exécuté par le serveur — voir
/// `ClientController.sendSystemAction`.
class ClientToolsView extends StatefulWidget {
  const ClientToolsView({super.key});

  @override
  State<ClientToolsView> createState() => _ClientToolsViewState();
}

class _ClientToolsViewState extends State<ClientToolsView> {
  StreamSubscription<ClientActionResult>? _subscription;

  int? _localVolume;
  int? _localBrightness;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _subscription =
        context.read<ClientController>().actionResults.listen(_showResult);
  }

  void _showResult(ClientActionResult result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ??
            (result.success ? _successLabel(result.action) : 'Échec de l\'action.')),
        backgroundColor:
            result.success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  String _successLabel(String action) => switch (action) {
        'lock' => 'PC verrouillé.',
        'task_manager' => 'Gestionnaire de tâches ouvert.',
        'media_previous' => 'Piste précédente.',
        'media_play_pause' => 'Lecture/pause.',
        'media_next' => 'Piste suivante.',
        'screenshot' => 'Capture d\'écran effectuée.',
        _ => 'Action effectuée.',
      };

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientController>(
      builder: (context, client, _) {
        if (!client.isConnected) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_off, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Aucun PC connecté.\nRendez-vous dans l\'onglet Connexion.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        void send(String action, {int? value}) =>
            client.sendSystemAction(action, value: value);

        final volume = _localVolume ?? client.systemState?.volume;
        final brightness = _localBrightness ?? client.systemState?.brightness;
        final recording = client.systemState?.recording ?? false;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tools', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Contrôle à distance de ${client.serverHostname ?? 'ce PC'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ToolButton(
                              icon: Icons.lock,
                              label: 'Verrouiller',
                              onTap: () => send('lock'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ToolButton(
                              icon: Icons.bar_chart,
                              label: 'Gestionnaire de tâches',
                              onTap: () => send('task_manager'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      PercentSliderTile(
                        icon: Icons.volume_up,
                        label: 'Volume',
                        value: volume,
                        onChanged: (v) => setState(() => _localVolume = v),
                        onChangeEnd: (v) {
                          send('volume_set', value: v);
                          setState(() => _localVolume = null);
                        },
                      ),
                      const SizedBox(height: 12),
                      PercentSliderTile(
                        icon: Icons.brightness_6,
                        label: 'Luminosité',
                        value: brightness,
                        onChanged: (v) => setState(() => _localBrightness = v),
                        onChangeEnd: (v) {
                          send('brightness_set', value: v);
                          setState(() => _localBrightness = null);
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ToolButton(
                              icon: Icons.camera_alt,
                              label: 'Capture d\'écran',
                              onTap: () => send('screenshot'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ToolButton(
                              icon: recording
                                  ? Icons.stop_circle
                                  : Icons.fiber_manual_record,
                              label: recording
                                  ? 'Arrêter la capture vidéo'
                                  : 'Démarrer la capture vidéo',
                              color: recording ? Colors.red : null,
                              onTap: () => send(recording
                                  ? 'video_capture_stop'
                                  : 'video_capture_start'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      MediaControlBar(
                        isPlaying: _isPlaying,
                        onPrevious: () => send('media_previous'),
                        onPlayPause: () {
                          setState(() => _isPlaying = !_isPlaying);
                          send('media_play_pause');
                        },
                        onNext: () => send('media_next'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
