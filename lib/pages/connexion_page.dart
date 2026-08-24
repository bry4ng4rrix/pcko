import 'dart:io';

import 'package:flutter/material.dart';

import '../client/ui/connection_screen.dart';
import '../server/ui/server_connexion_view.dart';

/// Sur PC : affiche l'IP/port + QR code pour coupler un téléphone.
/// Sur Android : permet de saisir l'IP/port ou de scanner le QR code du PC.
class ConnexionPage extends StatelessWidget {
  const ConnexionPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return const ClientConnexionView();
    }
    return const ServerConnexionView();
  }
}
