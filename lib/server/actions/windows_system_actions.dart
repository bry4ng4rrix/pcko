import 'dart:io';

import 'system_actions.dart';

/// Actions système Windows.
/// - Verrouillage et gestionnaire de tâches : natifs, aucune dépendance.
/// - Volume : simule les touches multimédia (`keybd_event` via P/Invoke en
///   PowerShell), exactement comme un clavier physique — pas de dépendance
///   tierce.
/// - Luminosité : classe WMI `WmiMonitorBrightnessMethods`. Ne fonctionne
///   que sur l'écran interne d'un laptop qui l'expose ; les moniteurs
///   externes ne sont pas supportés (limitation de Windows lui-même, qui
///   nécessiterait DDC/CI et un outil tiers).
class WindowsSystemActions implements SystemActions {
  static const _vkVolumeUp = 0xAF;
  static const _vkVolumeDown = 0xAE;

  @override
  Future<ActionResult> lockScreen() async {
    final result =
        await Process.run('rundll32.exe', ['user32.dll,LockWorkStation']);
    return result.exitCode == 0
        ? const ActionResult.ok()
        : ActionResult.fail('rundll32 a échoué (code ${result.exitCode}).');
  }

  @override
  Future<ActionResult> openTaskManager() async {
    try {
      await Process.start('taskmgr.exe', const [],
          mode: ProcessStartMode.detached);
      return const ActionResult.ok();
    } catch (e) {
      return ActionResult.fail('Impossible de lancer taskmgr.exe : $e');
    }
  }

  @override
  Future<ActionResult> volumeUp() => _sendVolumeKey(_vkVolumeUp);

  @override
  Future<ActionResult> volumeDown() => _sendVolumeKey(_vkVolumeDown);

  Future<ActionResult> _sendVolumeKey(int vk) async {
    final script = r'''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class PckoKeyboard {
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
[PckoKeyboard]::keybd_event(''' +
        vk.toString() +
        r''', 0, 0, [UIntPtr]::Zero)
[PckoKeyboard]::keybd_event(''' +
        vk.toString() +
        r''', 0, 2, [UIntPtr]::Zero)
''';
    final result =
        await Process.run('powershell', ['-NoProfile', '-Command', script]);
    return result.exitCode == 0
        ? const ActionResult.ok()
        : ActionResult.fail('PowerShell a échoué (code ${result.exitCode}).');
  }

  @override
  Future<ActionResult> brightnessUp() => _changeBrightness(10);

  @override
  Future<ActionResult> brightnessDown() => _changeBrightness(-10);

  Future<ActionResult> _changeBrightness(int deltaPercent) async {
    final script = r'''
$monitor = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop
$target = [Math]::Max(0, [Math]::Min(100, $monitor.CurrentBrightness + (''' +
        deltaPercent.toString() +
        r''')))
Invoke-CimMethod -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -MethodName WmiSetBrightness -Arguments @{Timeout=1; Brightness=$target}
''';
    final result =
        await Process.run('powershell', ['-NoProfile', '-Command', script]);
    return result.exitCode == 0
        ? const ActionResult.ok()
        : const ActionResult.fail(
            'Ajustement de la luminosité impossible (écran externe non '
            'supporté par WMI, ou pilote sans classe WmiMonitorBrightness).');
  }
}
