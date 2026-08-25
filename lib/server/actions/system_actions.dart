/// Résultat honnête d'une action système : succès, ou message d'erreur réel
/// en cas d'échec (jamais un succès simulé si l'action n'a pas abouti).
class ActionResult {
  final bool success;
  final String? message;

  const ActionResult.ok([this.message]) : success = true;
  const ActionResult.fail(this.message) : success = false;
}

/// Actions système déclenchables à distance depuis le téléphone (ou
/// localement côté PC) : verrouillage, gestionnaire de tâches, volume,
/// luminosité, contrôle média. Une implémentation par OS, voir
/// `linux_system_actions.dart` et `windows_system_actions.dart`.
abstract class SystemActions {
  Future<ActionResult> lockScreen();
  Future<ActionResult> openTaskManager();

  /// Niveau de volume actuel (0-100), ou `null` si indisponible.
  Future<int?> getVolume();

  /// Fixe le volume à une valeur absolue (0-100).
  Future<ActionResult> setVolume(int percent);

  /// Niveau de luminosité actuel (0-100), ou `null` si indisponible.
  Future<int?> getBrightness();

  /// Fixe la luminosité à une valeur absolue (0-100).
  Future<ActionResult> setBrightness(int percent);

  Future<ActionResult> mediaPrevious();
  Future<ActionResult> mediaPlayPause();
  Future<ActionResult> mediaNext();

  /// Capture l'écran et l'enregistre sur le PC.
  Future<ActionResult> takeScreenshot();

  /// Démarre l'enregistrement vidéo de l'écran.
  Future<ActionResult> startVideoCapture();

  /// Arrête l'enregistrement vidéo en cours.
  Future<ActionResult> stopVideoCapture();

  /// `true` si un enregistrement vidéo est en cours.
  bool get isCapturingVideo;
}
