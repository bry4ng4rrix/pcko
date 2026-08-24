import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/tool_button.dart';
import '../websocket_client.dart';

/// Page Tools côté téléphone : contrôle à distance du PC connecté
/// (verrouillage, gestionnaire de tâches, volume, luminosité), exécuté
/// par le serveur — voir `ClientController.sendSystemAction`.
class ClientToolsView extends StatefulWidget {
  const ClientToolsView({super.key});

  @override
  State<ClientToolsView> createState() => _ClientToolsViewState();
}

class _ClientToolsViewState extends State<ClientToolsView> {
  StreamSubscription<ClientActionResult>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        context.read<ClientController>().actionResults.listen(_showResult);
  }

  void _showResult(ClientActionResult result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success
            ? _successLabel(result.action)
            : (result.message ?? 'Échec de l\'action.')),
        backgroundColor:
            result.success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  String _successLabel(String action) => switch (action) {
        'lock' => 'PC verrouillé.',
        'task_manager' => 'Gestionnaire de tâches ouvert.',
        'volume_up' => 'Volume augmenté.',
        'volume_down' => 'Volume réduit.',
        'brightness_up' => 'Luminosité augmentée.',
        'brightness_down' => 'Luminosité réduite.',
        _ => 'Action effectuée.',
      };

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientController>(
      builder: (context, client, _) {
        if (!client.isConnected) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_off, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Aucun PC connecté.\nRendez-vous dans l\'onglet Connexion.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        void send(String action) => client.sendSystemAction(action);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tools', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Contrôle à distance de ${client.serverHostname ?? 'ce PC'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.3,
                    children: [
                      ToolButton(
                        icon: Icons.lock,
                        label: 'Verrouiller',
                        onTap: () => send('lock'),
                      ),
                      ToolButton(
                        icon: Icons.bar_chart,
                        label: 'Gestionnaire de tâches',
                        onTap: () => send('task_manager'),
                      ),
                      ToolButton(
                        icon: Icons.volume_up,
                        label: 'Volume +',
                        onTap: () => send('volume_up'),
                      ),
                      ToolButton(
                        icon: Icons.volume_down,
                        label: 'Volume -',
                        onTap: () => send('volume_down'),
                      ),
                      ToolButton(
                        icon: Icons.brightness_high,
                        label: 'Luminosité +',
                        onTap: () => send('brightness_up'),
                      ),
                      ToolButton(
                        icon: Icons.brightness_low,
                        label: 'Luminosité -',
                        onTap: () => send('brightness_down'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
