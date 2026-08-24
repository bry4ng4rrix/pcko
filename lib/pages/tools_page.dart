import 'dart:io';

import 'package:flutter/material.dart';

import '../client/ui/client_tools_view.dart';
import '../server/ui/server_tools_view.dart';

/// Sur PC : actions rapides exécutées localement.
/// Sur Android : mêmes actions, envoyées au PC connecté.
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return const ClientToolsView();
    }
    return const ServerToolsView();
  }
}
