import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'client/websocket_client.dart';
import 'main_screen.dart';
import 'server/websocket_server.dart';

/// Rôle "serveur" (collecte + diffusion) sur PC, rôle "client" (dashboard)
/// sur Android — un seul code, dispatché selon la plateforme d'exécution.
bool get isServerRole => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        if (isServerRole)
          ChangeNotifierProvider(create: (_) => ServerController()..start()),
        if (!isServerRole) ChangeNotifierProvider(create: (_) => ClientController()),
      ],
      child: MaterialApp(
        title: 'PCKO Monitor',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const MainScreen(),
      ),
    );
  }
}
