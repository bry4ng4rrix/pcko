import 'dart:io';

import 'package:flutter/material.dart';

import '../../shared/widgets/media_control_bar.dart';
import '../../shared/widgets/percent_slider_tile.dart';
import '../../shared/widgets/tool_button.dart';
import '../actions/linux_system_actions.dart';
import '../actions/system_actions.dart';
import '../actions/windows_system_actions.dart';

/// Page Tools côté PC : mêmes actions que côté téléphone, mais exécutées
/// directement en local (pratique pour tester sans second appareil).
class ServerToolsView extends StatefulWidget {
  const ServerToolsView({super.key});

  @override
  State<ServerToolsView> createState() => _ServerToolsViewState();
}

class _ServerToolsViewState extends State<ServerToolsView> {
  late final SystemActions _actions =
      Platform.isWindows ? WindowsSystemActions() : LinuxSystemActions();

  int? _volume;
  int? _brightness;
  bool _recording = false;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final volume = await _actions.getVolume();
    final brightness = await _actions.getBrightness();
    if (!mounted) return;
    setState(() {
      _volume = volume;
      _brightness = brightness;
      _recording = _actions.isCapturingVideo;
    });
  }

  Future<void> _run(
      String successLabel, Future<ActionResult> Function() action) async {
    final result = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(result.success ? successLabel : (result.message ?? 'Échec de l\'action.')),
        backgroundColor:
            result.success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Future<void> _toggleRecording() async {
    final result = _recording
        ? await _actions.stopVideoCapture()
        : await _actions.startVideoCapture();
    if (!mounted) return;
    if (result.success) setState(() => _recording = !_recording);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ??
            (result.success ? 'Action effectuée.' : 'Échec de l\'action.')),
        backgroundColor:
            result.success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tools', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Actions rapides sur ce PC',
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
                          onTap: () =>
                              _run('PC verrouillé.', _actions.lockScreen),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ToolButton(
                          icon: Icons.bar_chart,
                          label: 'Gestionnaire de tâches',
                          onTap: () => _run('Gestionnaire de tâches ouvert.',
                              _actions.openTaskManager),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PercentSliderTile(
                    icon: Icons.volume_up,
                    label: 'Volume',
                    value: _volume,
                    onChanged: (v) => setState(() => _volume = v),
                    onChangeEnd: (v) => _actions.setVolume(v),
                  ),
                  const SizedBox(height: 12),
                  PercentSliderTile(
                    icon: Icons.brightness_6,
                    label: 'Luminosité',
                    value: _brightness,
                    onChanged: (v) => setState(() => _brightness = v),
                    onChangeEnd: (v) => _actions.setBrightness(v),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ToolButton(
                          icon: Icons.camera_alt,
                          label: 'Capture d\'écran',
                          onTap: () => _run(
                              'Capture d\'écran effectuée.', _actions.takeScreenshot),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ToolButton(
                          icon: _recording
                              ? Icons.stop_circle
                              : Icons.fiber_manual_record,
                          label: _recording
                              ? 'Arrêter la capture vidéo'
                              : 'Démarrer la capture vidéo',
                          color: _recording ? Colors.red : null,
                          onTap: _toggleRecording,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  MediaControlBar(
                    isPlaying: _isPlaying,
                    onPrevious: () => _run(
                        'Piste précédente.', _actions.mediaPrevious),
                    onPlayPause: () {
                      setState(() => _isPlaying = !_isPlaying);
                      _run('Lecture/pause.', _actions.mediaPlayPause);
                    },
                    onNext: () =>
                        _run('Piste suivante.', _actions.mediaNext),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
