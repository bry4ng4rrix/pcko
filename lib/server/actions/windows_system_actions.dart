import 'dart:io';

import 'system_actions.dart';

/// Actions système Windows.
/// - Verrouillage et gestionnaire de tâches : natifs, aucune dépendance.
/// - Volume : API Core Audio (`IAudioEndpointVolume`) via interop COM
///   généré en PowerShell — pas de dépendance tierce, fonctionne sans droits
///   admin.
/// - Luminosité : classe WMI `WmiMonitorBrightnessMethods`. Ne fonctionne
///   que sur l'écran interne d'un laptop qui l'expose ; les moniteurs
///   externes ne sont pas supportés (limitation de Windows lui-même, qui
///   nécessiterait DDC/CI et un outil tiers).
/// - Média : touches multimédia simulées via `keybd_event` (P/Invoke).
/// - Capture d'écran : `System.Drawing`/`System.Windows.Forms` (.NET,
///   toujours présent). Capture vidéo : raccourci Win+Alt+R de la Xbox
///   Game Bar (natif, bascule démarrage/arrêt — nécessite que la capture en
///   arrière-plan de la Game Bar soit activée dans les paramètres Windows).
class WindowsSystemActions implements SystemActions {
  static const _vkMediaPlayPause = 0xB3;
  static const _vkMediaNextTrack = 0xB0;
  static const _vkMediaPrevTrack = 0xB1;
  static const _vkLWin = 0x5B;
  static const _vkMenu = 0x12; // Alt
  static const _vkR = 0x52;

  bool _recording = false;

  @override
  bool get isCapturingVideo => _recording;

  /// Interop COM vers `IAudioEndpointVolume`, réutilisé pour lire et écrire
  /// le volume maître du périphérique de sortie par défaut.
  static const _audioComShim = r'''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume {
  int NotImpl1();
  int NotImpl2();
  int GetChannelCount(out uint pnChannelCount);
  int SetMasterVolumeLevel(float fLevelDB, Guid pguidEventContext);
  int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
  int GetMasterVolumeLevel(out float pfLevelDB);
  int GetMasterVolumeLevelScalar(out float pfLevel);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
  int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IAudioEndpointVolume ppInterface);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
  int NotImpl1();
  int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class MMDeviceEnumeratorComObject { }

public class PckoAudio {
  static IAudioEndpointVolume GetEndpointVolume() {
    var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
    IMMDevice device;
    Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
    var iid = typeof(IAudioEndpointVolume).GUID;
    IAudioEndpointVolume volume;
    Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out volume));
    return volume;
  }

  public static float GetVolumeScalar() {
    float level;
    Marshal.ThrowExceptionForHR(GetEndpointVolume().GetMasterVolumeLevelScalar(out level));
    return level;
  }

  public static void SetVolumeScalar(float level) {
    Marshal.ThrowExceptionForHR(GetEndpointVolume().SetMasterVolumeLevelScalar(level, Guid.Empty));
  }
}
"@
''';

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
  Future<int?> getVolume() async {
    final script = '$_audioComShim\n[PckoAudio]::GetVolumeScalar()';
    final result =
        await Process.run('powershell', ['-NoProfile', '-Command', script]);
    if (result.exitCode != 0) return null;
    final value = double.tryParse((result.stdout as String).trim());
    if (value == null) return null;
    return (value * 100).round();
  }

  @override
  Future<ActionResult> setVolume(int percent) async {
    final clamped = percent.clamp(0, 100);
    final scalar = clamped / 100;
    final script =
        '$_audioComShim\n[PckoAudio]::SetVolumeScalar($scalar)';
    final result =
        await Process.run('powershell', ['-NoProfile', '-Command', script]);
    return result.exitCode == 0
        ? const ActionResult.ok()
        : ActionResult.fail('PowerShell a échoué (code ${result.exitCode}).');
  }

  @override
  Future<int?> getBrightness() async {
    const script = r'''
(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop).CurrentBrightness
''';
    final result =
        await Process.run('powershell', ['-NoProfile', '-Command', script]);
    if (result.exitCode != 0) return null;
    return int.tryParse((result.stdout as String).trim());
  }

  @override
  Future<ActionResult> setBrightness(int percent) async {
    final clamped = percent.clamp(0, 100);
    final script = r'''
Invoke-CimMethod -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -MethodName WmiSetBrightness -Arguments @{Timeout=1; Brightness=''' +
        clamped.toString() +
        r'''}
''';
    final result =
        await Process.run('powershell', ['-NoProfile', '-Command', script]);
    return result.exitCode == 0
        ? const ActionResult.ok()
        : const ActionResult.fail(
            'Ajustement de la luminosité impossible (écran externe non '
            'supporté par WMI, ou pilote sans classe WmiMonitorBrightness).');
  }

  @override
  Future<ActionResult> mediaPrevious() => _sendMediaKey(_vkMediaPrevTrack);

  @override
  Future<ActionResult> mediaPlayPause() => _sendMediaKey(_vkMediaPlayPause);

  @override
  Future<ActionResult> mediaNext() => _sendMediaKey(_vkMediaNextTrack);

  Future<ActionResult> _sendMediaKey(int vk) async {
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
  Future<ActionResult> takeScreenshot() async {
    final userProfile = Platform.environment['USERPROFILE'] ?? '.';
    final dir = '$userProfile\\Pictures\\pcko';
    final stamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final path = '$dir\\pcko_$stamp.png';
    final script = '''
New-Item -ItemType Directory -Force -Path "$dir" | Out-Null
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
\$bmp = New-Object System.Drawing.Bitmap \$bounds.Width, \$bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bmp)
\$graphics.CopyFromScreen(\$bounds.Location, [System.Drawing.Point]::Empty, \$bounds.Size)
\$bmp.Save("$path", [System.Drawing.Imaging.ImageFormat]::Png)
''';
    final result =
        await Process.run('powershell', ['-NoProfile', '-Command', script]);
    return result.exitCode == 0
        ? ActionResult.ok('Capture enregistrée : $path')
        : ActionResult.fail('PowerShell a échoué (code ${result.exitCode}).');
  }

  @override
  Future<ActionResult> startVideoCapture() async {
    if (_recording) {
      return const ActionResult.fail('Un enregistrement est déjà en cours.');
    }
    final result = await _sendGameBarToggle();
    if (result.success) _recording = true;
    return result.success
        ? const ActionResult.ok('Enregistrement démarré (Xbox Game Bar).')
        : result;
  }

  @override
  Future<ActionResult> stopVideoCapture() async {
    if (!_recording) {
      return const ActionResult.fail('Aucun enregistrement en cours.');
    }
    final result = await _sendGameBarToggle();
    _recording = false;
    return result.success
        ? const ActionResult.ok('Enregistrement arrêté.')
        : result;
  }

  Future<ActionResult> _sendGameBarToggle() async {
    final script = r'''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class PckoKeyboard {
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
$down = 0
$up = 2
[PckoKeyboard]::keybd_event(''' +
        _vkLWin.toString() +
        r''', 0, $down, [UIntPtr]::Zero)
[PckoKeyboard]::keybd_event(''' +
        _vkMenu.toString() +
        r''', 0, $down, [UIntPtr]::Zero)
[PckoKeyboard]::keybd_event(''' +
        _vkR.toString() +
        r''', 0, $down, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 50
[PckoKeyboard]::keybd_event(''' +
        _vkR.toString() +
        r''', 0, $up, [UIntPtr]::Zero)
[PckoKeyboard]::keybd_event(''' +
        _vkMenu.toString() +
        r''', 0, $up, [UIntPtr]::Zero)
[PckoKeyboard]::keybd_event(''' +
        _vkLWin.toString() +
        r''', 0, $up, [UIntPtr]::Zero)
''';
    final result =
        await Process.run('powershell', ['-NoProfile', '-Command', script]);
    return result.exitCode == 0
        ? const ActionResult.ok()
        : ActionResult.fail('PowerShell a échoué (code ${result.exitCode}).');
  }
}
