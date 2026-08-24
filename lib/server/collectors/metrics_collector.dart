import '../../shared/models/metrics_payload.dart';

/// Interface commune à tous les collecteurs de métriques matérielles.
/// Chaque plateforme (Linux, Windows...) fournit sa propre implémentation.
abstract class MetricsCollector {
  Future<MetricsPayload> collect();
}
