import 'dart:io';

import 'package:flutter/material.dart';

import '../client/ui/dashboard_screen.dart';
import '../server/ui/server_home_view.dart';

/// Sur PC : affiche toutes les informations matérielles du PC.
/// Sur Android : affiche le dashboard temps réel reçu du PC connecté.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return const ClientHomeView();
    }
    return const ServerHomeView();
  }
}
