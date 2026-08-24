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
class LinuxSystemActions implements SystemActions {
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
  Future<ActionResult> volumeUp() => _changeVolume(true);

  @override
  Future<ActionResult> volumeDown() => _changeVolume(false);

  Future<ActionResult> _changeVolume(bool up) async {
    if (await _tryRun('pactl',
        ['set-sink-volume', '@DEFAULT_SINK@', up ? '+5%' : '-5%'])) {
      return const ActionResult.ok();
    }
    if (await _tryRun('wpctl',
        ['set-volume', '@DEFAULT_AUDIO_SINK@', up ? '5%+' : '5%-'])) {
      return const ActionResult.ok();
    }
    if (await _tryRun('amixer', ['sset', 'Master', up ? '5%+' : '5%-'])) {
      return const ActionResult.ok();
    }
    return const ActionResult.fail(
        'Aucun contrôleur de volume trouvé (pactl/wpctl/amixer).');
  }

  @override
  Future<ActionResult> brightnessUp() => _changeBrightness(true);

  @override
  Future<ActionResult> brightnessDown() => _changeBrightness(false);

  Future<ActionResult> _changeBrightness(bool up) async {
    if (await _tryRun('brightnessctl', ['set', up ? '5%+' : '5%-'])) {
      return const ActionResult.ok();
    }
    if (await _tryRun('light', [up ? '-A' : '-U', '5'])) {
      return const ActionResult.ok();
    }
    return const ActionResult.fail(
        'Aucun contrôleur de luminosité trouvé (installez `brightnessctl`).');
  }

  Future<bool> _tryRun(String executable, List<String> args) async {
    try {
      final result = await Process.run(executable, args);
      return result.exitCode == 0;
    } catch (_) {
      return false;
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
