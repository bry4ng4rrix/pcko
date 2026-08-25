import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../shared/models/metrics_payload.dart';

enum ConnectionStatus { disconnected, connecting, connected, reconnecting }

/// Résultat d'une action système (verrouillage, volume…) demandée au PC,
/// renvoyé par le serveur — jamais un succès supposé côté client.
class ClientActionResult {
  final String action;
  final bool success;
  final String? message;

  const ClientActionResult(
      {required this.action, required this.success, this.message});
}

/// État système courant du PC connecté (volume, luminosité, enregistrement
/// vidéo en cours), reçu via le message `system_state`.
class SystemState {
  final int? volume;
  final int? brightness;
  final bool recording;

  const SystemState(
      {this.volume, this.brightness, this.recording = false});
}

/// Contrôleur du rôle "client" (téléphone Android).
/// Gère la connexion WebSocket vers le PC, la réception des métriques,
/// et la reconnexion automatique (backoff exponentiel, max 30s).
class ClientController extends ChangeNotifier {
  static const int _maxHistoryLength = 60; // fenêtre glissante ~60s
  static const int _maxBackoffSeconds = 30;

  ConnectionStatus status = ConnectionStatus.disconnected;
  String? serverIp;
  int? serverPort;
  String? serverHostname;
  String? lastError;

  MetricsPayload? lastPayload;
  final List<MetricsPayload> history = [];
  SystemState? systemState;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _manualDisconnect = false;

  final _actionResultController =
      StreamController<ClientActionResult>.broadcast();

  /// Résultats des actions système (`sendSystemAction`), un évènement par
  /// réponse du serveur — à écouter côté UI pour afficher un feedback ponctuel.
  Stream<ClientActionResult> get actionResults =>
      _actionResultController.stream;

  bool get isConnected => status == ConnectionStatus.connected;

  Future<void> connect(String ip, int port) async {
    _manualDisconnect = false;
    serverIp = ip;
    serverPort = port;
    _reconnectAttempts = 0;
    await _openSocket();
  }

  Future<void> _openSocket() async {
    _reconnectTimer?.cancel();
    if (serverIp == null || serverPort == null) return;

    status = ConnectionStatus.connecting;
    lastError = null;
    notifyListeners();

    try {
      final uri = Uri.parse('ws://$serverIp:$serverPort');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      _channel = channel;
      _reconnectAttempts = 0;
      status = ConnectionStatus.connected;
      notifyListeners();

      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: _handleDisconnection,
        onError: (e) {
          lastError = e.toString();
          _handleDisconnection();
        },
        cancelOnError: true,
      );
    } catch (e) {
      lastError = 'Connexion impossible : $e';
      _handleDisconnection();
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (json['type']) {
        case 'hello':
          serverHostname = json['hostname'] as String?;
          break;
        case 'metrics':
          final payload = MetricsPayload.fromJson(json);
          lastPayload = payload;
          history.add(payload);
          while (history.length > _maxHistoryLength) {
            history.removeAt(0);
          }
          break;
        case 'ping':
          _channel?.sink.add(jsonEncode({'type': 'pong'}));
          break;
        case 'system_action_result':
          _actionResultController.add(ClientActionResult(
            action: json['action'] as String? ?? '',
            success: json['success'] as bool? ?? false,
            message: json['message'] as String?,
          ));
          break;
        case 'system_state':
          systemState = SystemState(
            volume: json['volume'] as int?,
            brightness: json['brightness'] as int?,
            recording: json['recording'] as bool? ?? false,
          );
          break;
      }
      notifyListeners();
    } catch (e) {
      lastError = 'Message invalide reçu du serveur : $e';
    }
  }

  void _handleDisconnection() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    if (_manualDisconnect) {
      status = ConnectionStatus.disconnected;
      notifyListeners();
      return;
    }

    status = ConnectionStatus.reconnecting;
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final delaySeconds =
        min(pow(2, _reconnectAttempts).toInt(), _maxBackoffSeconds);
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), _openSocket);
  }

  /// Demande au serveur de changer l'intervalle de rafraîchissement.
  void requestInterval(int ms) {
    _channel?.sink.add(jsonEncode({'type': 'set_interval', 'interval_ms': ms}));
  }

  /// Demande au PC connecté d'exécuter une action système (voir
  /// `SystemActions` côté serveur pour la liste : lock, task_manager,
  /// volume_set, brightness_set, media_previous, media_play_pause,
  /// media_next, screenshot, video_capture_start, video_capture_stop).
  /// `value` est requis pour `volume_set`/`brightness_set` (0-100).
  void sendSystemAction(String action, {int? value}) {
    final payload = <String, dynamic>{'type': 'system_action', 'action': action};
    if (value != null) payload['value'] = value;
    _channel?.sink.add(jsonEncode(payload));
  }

  /// Demande un rafraîchissement immédiat de l'état système (volume,
  /// luminosité, enregistrement en cours).
  void requestSystemState() {
    _channel?.sink.add(jsonEncode({'type': 'get_system_state'}));
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    status = ConnectionStatus.disconnected;
    lastPayload = null;
    history.clear();
    systemState = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _actionResultController.close();
    super.dispose();
  }
}
