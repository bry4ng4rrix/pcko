import 'dart:io';

import 'system_actions.dart';

/// Actions système Linux — best-effort, car aucune de ces fonctions n'a
/// d'API universelle sous Linux (ça dépend de l'environnement de bureau et
/// des paquets installés) :
/// - Verrouillage : `loginctl lock-session`, puis `xdg-screensaver`/`dm-tool`.
/// - Gestionnaire de tâches : premier moniteur système graphique trouvé
///   parmi les plus courants (GNOME, KDE, XFCE, MATE, LXDE).
/// - Volume : `pactl` (PulseAudio/PipeWire), puis `wpctl`, puis `amixer`.
/// - Luminosité : `brightnessctl`, puis `light`.
/// - Média : `playerctl` (MPRIS), puis touches multimédia via `xdotool`.
/// - Capture : `grim`/`gnome-screenshot`/`scrot`/`import` pour les captures
///   d'écran, `wf-recorder`/`ffmpeg` pour la vidéo.
class LinuxSystemActions implements SystemActions {
  Process? _recordingProcess;

  @override
  bool get isCapturingVideo => _recordingProcess != null;

  String get _captureDir {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/Pictures/pcko';
  }

  String _timestampedPath(String extension) {
    final dir = Directory(_captureDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final stamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    return '$_captureDir/pcko_$stamp.$extension';
  }

  @override
  Future<ActionResult> lockScreen() async {
    if (await _tryRun('loginctl', ['lock-session'])) {
      return const ActionResult.ok();
    }
    if (await _tryRun('xdg-screensaver', ['lock'])) {
      return const ActionResult.ok();
    }
    if (await _tryRun('dm-tool', ['lock'])) {
      return const ActionResult.ok();
    }
    return const ActionResult.fail(
        'Aucun verrouilleur d\'écran trouvé (loginctl/xdg-screensaver/dm-tool).');
  }

  @override
  Future<ActionResult> openTaskManager() async {
    const candidates = [
      'gnome-system-monitor',
      'plasma-systemmonitor',
      'ksysguard',
      'xfce4-taskmanager',
      'mate-system-monitor',
      'lxtask',
    ];
    for (final exe in candidates) {
      if (await _spawnDetached(exe, const [])) return const ActionResult.ok();
    }
    return ActionResult.fail(
        'Aucun gestionnaire de tâches graphique trouvé parmi : ${candidates.join(', ')}.');
  }

  @override
  Future<int?> getVolume() async {
    final pactl = await _runOutput('pactl', ['get-sink-volume', '@DEFAULT_SINK@']);
    if (pactl != null) {
      final match = RegExp(r'(\d+)%').firstMatch(pactl);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    final wpctl = await _runOutput('wpctl', ['get-volume', '@DEFAULT_AUDIO_SINK@']);
    if (wpctl != null) {
      final match = RegExp(r'([\d.]+)').firstMatch(wpctl);
      if (match != null) {
        final ratio = double.tryParse(match.group(1)!);
        if (ratio != null) return (ratio * 100).round();
      }
    }
    final amixer = await _runOutput('amixer', ['get', 'Master']);
    if (amixer != null) {
      final match = RegExp(r'\[(\d+)%\]').firstMatch(amixer);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    return null;
  }

  @override
  Future<ActionResult> setVolume(int percent) async {
    final clamped = percent.clamp(0, 100);
    if (await _tryRun(
        'pactl', ['set-sink-volume', '@DEFAULT_SINK@', '$clamped%'])) {
      return const ActionResult.ok();
    }
    if (await _tryRun('wpctl',
        ['set-volume', '@DEFAULT_AUDIO_SINK@', '${clamped / 100}'])) {
      return const ActionResult.ok();
    }
    if (await _tryRun('amixer', ['sset', 'Master', '$clamped%'])) {
      return const ActionResult.ok();
    }
    return const ActionResult.fail(
        'Aucun contrôleur de volume trouvé (pactl/wpctl/amixer).');
  }

  @override
  Future<int?> getBrightness() async {
    final current = await _runOutput('brightnessctl', ['get']);
    final max = await _runOutput('brightnessctl', ['max']);
    if (current != null && max != null) {
      final currentValue = int.tryParse(current.trim());
      final maxValue = int.tryParse(max.trim());
      if (currentValue != null && maxValue != null && maxValue > 0) {
        return ((currentValue / maxValue) * 100).round();
      }
    }
    final light = await _runOutput('light', ['-G']);
    if (light != null) {
      final value = double.tryParse(light.trim());
      if (value != null) return value.round();
    }
    return null;
  }

  @override
  Future<ActionResult> setBrightness(int percent) async {
    final clamped = percent.clamp(0, 100);
    if (await _tryRun('brightnessctl', ['set', '$clamped%'])) {
      return const ActionResult.ok();
    }
    if (await _tryRun('light', ['-S', '$clamped'])) {
      return const ActionResult.ok();
    }
    return const ActionResult.fail(
        'Aucun contrôleur de luminosité trouvé (installez `brightnessctl`).');
  }

  @override
  Future<ActionResult> mediaPrevious() => _mediaCommand('previous', 'XF86AudioPrev');

  @override
  Future<ActionResult> mediaPlayPause() =>
      _mediaCommand('play-pause', 'XF86AudioPlay');

  @override
  Future<ActionResult> mediaNext() => _mediaCommand('next', 'XF86AudioNext');

  Future<ActionResult> _mediaCommand(String playerctlCommand, String key) async {
    if (await _tryRun('playerctl', [playerctlCommand])) {
      return const ActionResult.ok();
    }
    if (await _tryRun('xdotool', ['key', key])) {
      return const ActionResult.ok();
    }
    return const ActionResult.fail(
        'Aucun contrôleur média trouvé (installez `playerctl`).');
  }

  @override
  Future<ActionResult> takeScreenshot() async {
    final path = _timestampedPath('png');
    if (await _tryRun('grim', [path])) {
      return ActionResult.ok('Capture enregistrée : $path');
    }
    if (await _tryRun('gnome-screenshot', ['-f', path])) {
      return ActionResult.ok('Capture enregistrée : $path');
    }
    if (await _tryRun('scrot', [path])) {
      return ActionResult.ok('Capture enregistrée : $path');
    }
    if (await _tryRun('import', ['-window', 'root', path])) {
      return ActionResult.ok('Capture enregistrée : $path');
    }
    return const ActionResult.fail(
        'Aucun outil de capture trouvé (grim/gnome-screenshot/scrot/import).');
  }

  @override
  Future<ActionResult> startVideoCapture() async {
    if (_recordingProcess != null) {
      return const ActionResult.fail('Un enregistrement est déjà en cours.');
    }
    final path = _timestampedPath('mp4');

    final wfRecorder = await _spawnRecording('wf-recorder', ['-f', path]);
    if (wfRecorder != null) {
      _recordingProcess = wfRecorder;
      return ActionResult.ok('Enregistrement démarré : $path');
    }

    final resolution = await _detectX11Resolution();
    final ffmpeg = await _spawnRecording('ffmpeg', [
      '-y',
      '-video_size',
      resolution,
      '-f',
      'x11grab',
      '-i',
      ':0.0',
      path,
    ]);
    if (ffmpeg != null) {
      _recordingProcess = ffmpeg;
      return ActionResult.ok('Enregistrement démarré : $path');
    }

    return const ActionResult.fail(
        'Aucun outil de capture vidéo trouvé (installez `wf-recorder` ou `ffmpeg`).');
  }

  @override
  Future<ActionResult> stopVideoCapture() async {
    final process = _recordingProcess;
    if (process == null) {
      return const ActionResult.fail('Aucun enregistrement en cours.');
    }
    _recordingProcess = null;
    process.kill(ProcessSignal.sigint);
    return const ActionResult.ok('Enregistrement arrêté.');
  }

  Future<String> _detectX11Resolution() async {
    final output = await _runOutput('xdpyinfo', const []);
    if (output != null) {
      final match = RegExp(r'dimensions:\s+(\d+x\d+)').firstMatch(output);
      if (match != null) return match.group(1)!;
    }
    return '1920x1080';
  }

  Future<Process?> _spawnRecording(
      String executable, List<String> args) async {
    try {
      final process = await Process.start(executable, args,
          mode: ProcessStartMode.detached);
      return process.pid > 0 ? process : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _tryRun(String executable, List<String> args) async {
    try {
      final result = await Process.run(executable, args);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _runOutput(String executable, List<String> args) async {
    try {
      final result = await Process.run(executable, args);
      if (result.exitCode != 0) return null;
      return result.stdout as String;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _spawnDetached(String executable, List<String> args) async {
    try {
      final process =
          await Process.start(executable, args, mode: ProcessStartMode.detached);
      return process.pid > 0;
    } catch (_) {
      return false;
    }
  }
}
