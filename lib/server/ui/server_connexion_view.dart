import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../websocket_server.dart';

/// Page "Connexion" côté PC : montre comment coupler un téléphone
/// (IP + port + QR code à scanner) et la liste des appareils déjà connectés.
class ServerConnexionView extends StatelessWidget {
  const ServerConnexionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerController>(
      builder: (context, server, _) {
        final ip = server.localIp;
        final address = ip != null ? '$ip:${server.port}' : null;
        final qrPayload = jsonEncode({'ip': ip, 'port': server.port});

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Coupler un téléphone',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Ouvrez l\'application sur le téléphone (même réseau WiFi), '
                  'puis scannez ce QR code ou saisissez l\'adresse manuellement.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                if (ip == null)
                  Column(
                    children: [
                      const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text(
                          'Aucune adresse IP locale détectée.\nVérifiez la connexion WiFi.'),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8),
                      ],
                    ),
                    child: QrImageView(
                      data: qrPayload,
                      version: QrVersions.auto,
                      size: 220,
                    ),
                  ),
                const SizedBox(height: 20),
                if (address != null)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: address));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Adresse copiée !')),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          address,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.copy, size: 18),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Appareils connectés (${server.connectedClientsCount})',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 8),
                if (server.connectedClientsCount == 0)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Aucun téléphone connecté pour le moment.',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  Column(
                    children: server.connectedClientAddresses
                        .map((addr) => ListTile(
                              leading: const Icon(Icons.phone_android,
                                  color: Colors.green),
                              title: Text(addr),
                              contentPadding: EdgeInsets.zero,
                            ))
                        .toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
