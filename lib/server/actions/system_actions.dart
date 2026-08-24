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
/// luminosité. Une implémentation par OS, voir `linux_system_actions.dart`
/// et `windows_system_actions.dart`.
abstract class SystemActions {
  Future<ActionResult> lockScreen();
  Future<ActionResult> openTaskManager();
  Future<ActionResult> volumeUp();
  Future<ActionResult> volumeDown();
  Future<ActionResult> brightnessUp();
  Future<ActionResult> brightnessDown();
}
