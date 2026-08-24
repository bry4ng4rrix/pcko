import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/gauges.dart';
import '../websocket_server.dart';

/// Page d'accueil côté PC : affiche toutes les informations matérielles
/// collectées en temps réel (CPU, GPU, RAM, réseau).
class ServerHomeView extends StatefulWidget {
  const ServerHomeView({super.key});

  @override
  State<ServerHomeView> createState() => _ServerHomeViewState();
}

class _ServerHomeViewState extends State<ServerHomeView> {
  @override
  void initState() {
    super.initState();
    // Le serveur démarre automatiquement dès l'ouverture de l'application.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServerController>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerController>(
      builder: (context, server, _) {
        final payload = server.lastPayload;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      server.isRunning ? Icons.dns : Icons.dns_outlined,
                      color: server.isRunning ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        server.hostname,
                        style: Theme.of(context).textTheme.headlineSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  server.isRunning
                      ? 'Serveur actif · ${server.connectedClientsCount} appareil(s) connecté(s)'
                      : 'Serveur arrêté',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey),
                ),
                if (server.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    server.lastError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 24),
                if (payload == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  ProSystemMetricsRow(
                    cpu: payload.cpu,
                    gpus: payload.gpus,
                    ram: payload.ram,
                    screen: payload.screen,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Températures',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          TemperatureBadge(
                            label: 'CPU',
                            temperatureC: payload.cpu.temperatureC,
                          ),
                          const SizedBox(height: 8),
                          GpuTemperatureList(gpus: payload.gpus),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Réseau',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                              'Interface : ${payload.network.interfaceName ?? 'indisponible'}'),
                          const SizedBox(height: 8),
                          NetworkSpeedRow(network: payload.network),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Dernière mise à jour : ${payload.timestamp.hour.toString().padLeft(2, '0')}:'
                    '${payload.timestamp.minute.toString().padLeft(2, '0')}:'
                    '${payload.timestamp.second.toString().padLeft(2, '0')}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
