import 'dart:io';

import 'package:flutter/material.dart';

import '../../shared/widgets/tool_button.dart';
import '../actions/linux_system_actions.dart';
import '../actions/system_actions.dart';
import '../actions/windows_system_actions.dart';

/// Page Tools côté PC : mêmes actions que côté téléphone, mais exécutées
/// directement en local (pratique pour tester sans second appareil).
class ServerToolsView extends StatefulWidget {
  const ServerToolsView({super.key});

  @override
  State<ServerToolsView> createState() => _ServerToolsViewState();
}

class _ServerToolsViewState extends State<ServerToolsView> {
  late final SystemActions _actions =
      Platform.isWindows ? WindowsSystemActions() : LinuxSystemActions();

  Future<void> _run(
      String successLabel, Future<ActionResult> Function() action) async {
    final result = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(result.success ? successLabel : (result.message ?? 'Échec de l\'action.')),
        backgroundColor:
            result.success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tools', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Actions rapides sur ce PC',
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
                    onTap: () =>
                        _run('PC verrouillé.', _actions.lockScreen),
                  ),
                  ToolButton(
                    icon: Icons.bar_chart,
                    label: 'Gestionnaire de tâches',
                    onTap: () => _run(
                        'Gestionnaire de tâches ouvert.', _actions.openTaskManager),
                  ),
                  ToolButton(
                    icon: Icons.volume_up,
                    label: 'Volume +',
                    onTap: () => _run('Volume augmenté.', _actions.volumeUp),
                  ),
                  ToolButton(
                    icon: Icons.volume_down,
                    label: 'Volume -',
                    onTap: () => _run('Volume réduit.', _actions.volumeDown),
                  ),
                  ToolButton(
                    icon: Icons.brightness_high,
                    label: 'Luminosité +',
                    onTap: () =>
                        _run('Luminosité augmentée.', _actions.brightnessUp),
                  ),
                  ToolButton(
                    icon: Icons.brightness_low,
                    label: 'Luminosité -',
                    onTap: () =>
                        _run('Luminosité réduite.', _actions.brightnessDown),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
