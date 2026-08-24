import 'dart:io';

import 'package:flutter/material.dart';

import '../client/ui/client_settings_view.dart';
import '../server/ui/server_settings_view.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return const ClientSettingsView();
    }
    return const ServerSettingsView();
  }
}
