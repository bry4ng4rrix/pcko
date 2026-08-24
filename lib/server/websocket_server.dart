import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../shared/models/metrics_payload.dart';
import '../shared/util/network_util.dart';
import 'actions/linux_system_actions.dart';
import 'actions/system_actions.dart';
import 'actions/windows_system_actions.dart';
import 'collectors/linux_collector.dart';
import 'collectors/metrics_collector.dart';
import 'collectors/windows_collector.dart';

/// Contrôleur du rôle "serveur" (PC Windows/Linux).
/// Démarre un serveur WebSocket qui diffuse en continu les métriques
/// matérielles collectées, et expose l'état à l'UI via [ChangeNotifier].
class ServerController extends ChangeNotifier {
  ServerController() {
    _collector = Platform.isWindows
        ? WindowsMetricsCollector(libreHardwareMonitorPort: libreHardwareMonitorPort)
        : LinuxMetricsCollector();
    _actions = Platform.isWindows
        ? WindowsSystemActions()
        : LinuxSystemActions();
  }

  late SystemActions _actions;

  int port = 9090;
  int libreHardwareMonitorPort = 8085;
  int intervalMs = 1000;

  late MetricsCollector _collector;
  HttpServer? _httpServer;
  Timer? _broadcastTimer;
  final Map<WebSocket, String> _clients = {};

  String? localIp;
  MetricsPayload? lastPayload;
  String? lastError;
  bool get isRunning => _httpServer != null;
  int get connectedClientsCount => _clients.length;
  List<String> get connectedClientAddresses => _clients.values.toList();

  String get hostname => Platform.localHostname;

  Future<void> start() async {
    if (isRunning) return;
    try {
      localIp = await getLocalIpAddress();
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
      lastError = null;
      _httpServer!.listen(_handleRequest, onError: (e) {
        lastError = e.toString();
        notifyListeners();
      });
      _startBroadcastLoop();
      notifyListeners();
    } catch (e) {
      lastError = "Impossible de démarrer le serveur sur le port $port : $e";
      _httpServer = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    for (final client in _clients.keys.toList()) {
      await client.close();
    }
    _clients.clear();
    await _httpServer?.close(force: true);
    _httpServer = null;
    notifyListeners();
  }

  /// Redémarre le serveur avec un nouveau port WebSocket.
  Future<void> setPort(int newPort) async {
    port = newPort;
    if (isRunning) {
      await stop();
      await start();
    }
  }

  /// Change le port de l'API LibreHardwareMonitor (Windows uniquement).
  void setLibreHardwareMonitorPort(int newPort) {
    libreHardwareMonitorPort = newPort;
    final collector = _collector;
    if (collector is WindowsMetricsCollector) {
      collector.libreHardwareMonitorPort = newPort;
    }
    notifyListeners();
  }

  void setInterval(int ms) {
    intervalMs = ms;
    if (isRunning) {
      _startBroadcastLoop();
    }
    notifyListeners();
  }

  void _startBroadcastLoop() {
    _broadcastTimer?.cancel();
    _broadcastTimer =
        Timer.periodic(Duration(milliseconds: intervalMs), (_) => _tick());
  }

  Future<void> _tick() async {
    try {
      final payload = await _collector.collect();
      lastPayload = payload;
      final message = jsonEncode(payload.toJson());
      for (final client in _clients.keys.toList()) {
        try {
          client.add(message);
        } catch (_) {
          _clients.remove(client);
        }
      }
      notifyListeners();
    } catch (e) {
      lastError = 'Erreur de collecte des métriques : $e';
      notifyListeners();
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('Ce serveur ne parle que WebSocket.')
        ..close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      final remote = '${request.connectionInfo?.remoteAddress.address}:'
          '${request.connectionInfo?.remotePort}';
      _clients[socket] = remote;
      notifyListeners();

      socket.add(jsonEncode({
        'type': 'hello',
        'hostname': hostname,
        'interval_ms': intervalMs,
      }));

      socket.listen(
        (data) => _handleClientMessage(socket, data),
        onDone: () {
          _clients.remove(socket);
          notifyListeners();
        },
        onError: (_) {
          _clients.remove(socket);
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (e) {
      lastError = 'Erreur lors de la connexion d\'un client : $e';
      notifyListeners();
    }
  }

  void _handleClientMessage(WebSocket socket, dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      switch (json['type']) {
        case 'set_interval':
          final ms = json['interval_ms'] as int?;
          if (ms != null && ms >= 200) {
            setInterval(ms);
          }
          break;
        case 'ping':
          socket.add(jsonEncode({'type': 'pong'}));
          break;
        case 'system_action':
          _runSystemAction(socket, json['action'] as String?);
          break;
      }
    } catch (_) {
      // Message de contrôle malformé : on l'ignore silencieusement.
    }
  }

  Future<void> _runSystemAction(WebSocket socket, String? action) async {
    final ActionResult result = switch (action) {
      'lock' => await _actions.lockScreen(),
      'task_manager' => await _actions.openTaskManager(),
      'volume_up' => await _actions.volumeUp(),
      'volume_down' => await _actions.volumeDown(),
      'brightness_up' => await _actions.brightnessUp(),
      'brightness_down' => await _actions.brightnessDown(),
      _ => ActionResult.fail('Action inconnue : $action'),
    };
    try {
      socket.add(jsonEncode({
        'type': 'system_action_result',
        'action': action,
        'success': result.success,
        'message': result.message,
      }));
    } catch (_) {
      // Le client a peut-être déjà fermé la connexion.
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
