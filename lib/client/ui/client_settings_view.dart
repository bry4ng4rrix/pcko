import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../websocket_client.dart';

/// Paramètres côté téléphone : intervalle de rafraîchissement demandé au PC.
class ClientSettingsView extends StatefulWidget {
  const ClientSettingsView({super.key});

  @override
  State<ClientSettingsView> createState() => _ClientSettingsViewState();
}

class _ClientSettingsViewState extends State<ClientSettingsView> {
  int _intervalMs = 1000;

  @override
  Widget build(BuildContext context) {
    final client = context.watch<ClientController>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Paramètres', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            Text('Intervalle de rafraîchissement souhaité : $_intervalMs ms'),
            Slider(
              value: _intervalMs.toDouble(),
              min: 200,
              max: 5000,
              divisions: 24,
              label: '$_intervalMs ms',
              onChanged: (v) => setState(() => _intervalMs = v.round()),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Envoyer au PC'),
              onPressed: client.isConnected
                  ? () {
                      client.requestInterval(_intervalMs);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Intervalle envoyé.')),
                      );
                    }
                  : null,
            ),
            if (!client.isConnected) ...[
              const SizedBox(height: 8),
              const Text(
                'Connectez-vous à un PC (onglet Connexion) pour modifier l\'intervalle.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
