import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../websocket_server.dart';

/// Paramètres côté PC : intervalle de rafraîchissement, port WebSocket,
/// port de l'API LibreHardwareMonitor (Windows).
class ServerSettingsView extends StatefulWidget {
  const ServerSettingsView({super.key});

  @override
  State<ServerSettingsView> createState() => _ServerSettingsViewState();
}

class _ServerSettingsViewState extends State<ServerSettingsView> {
  late final TextEditingController _portController;
  late final TextEditingController _lhmPortController;

  @override
  void initState() {
    super.initState();
    final server = context.read<ServerController>();
    _portController = TextEditingController(text: server.port.toString());
    _lhmPortController =
        TextEditingController(text: server.libreHardwareMonitorPort.toString());
  }

  @override
  void dispose() {
    _portController.dispose();
    _lhmPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerController>(
      builder: (context, server, _) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Paramètres', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                Text('Intervalle de rafraîchissement : ${server.intervalMs} ms'),
                Slider(
                  value: server.intervalMs.toDouble(),
                  min: 200,
                  max: 5000,
                  divisions: 24,
                  label: '${server.intervalMs} ms',
                  onChanged: (v) => server.setInterval(v.round()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port du serveur WebSocket',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lhmPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port API LibreHardwareMonitor (Windows)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Appliquer (redémarre le serveur)'),
                  onPressed: () async {
                    final port = int.tryParse(_portController.text.trim());
                    final lhmPort = int.tryParse(_lhmPortController.text.trim());
                    if (port != null) await server.setPort(port);
                    if (lhmPort != null) {
                      server.setLibreHardwareMonitorPort(lhmPort);
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Paramètres appliqués.')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
