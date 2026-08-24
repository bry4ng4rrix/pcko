import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/gauges.dart';
import '../websocket_client.dart';

/// Page "Connexion" côté téléphone : couplage avec le PC par saisie
/// manuelle de l'IP/port ou par scan du QR code affiché sur le PC.
class ClientConnexionView extends StatefulWidget {
  const ClientConnexionView({super.key});

  @override
  State<ClientConnexionView> createState() => _ClientConnexionViewState();
}

class _ClientConnexionViewState extends State<ClientConnexionView> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9090');

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _scanQrCode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (result == null || !mounted) return;

    try {
      final json = jsonDecode(result) as Map<String, dynamic>;
      final ip = json['ip'] as String?;
      final port = json['port'] as int?;
      if (ip != null && port != null) {
        _ipController.text = ip;
        _portController.text = port.toString();
        _connect();
        return;
      }
    } catch (_) {
      // Pas du JSON : on tente le format "ip:port".
      final parts = result.split(':');
      if (parts.length == 2) {
        _ipController.text = parts[0];
        _portController.text = parts[1];
        _connect();
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR code non reconnu.')),
      );
    }
  }

  void _connect() {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (ip.isEmpty || port == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adresse IP ou port invalide.')),
      );
      return;
    }
    context.read<ClientController>().connect(ip, port);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientController>(
      builder: (context, client, _) {
        final (color, label) = switch (client.status) {
          ConnectionStatus.connected => (Colors.green, 'Connecté'),
          ConnectionStatus.connecting => (Colors.orange, 'Connexion en cours…'),
          ConnectionStatus.reconnecting => (Colors.orange, 'Reconnexion en cours…'),
          ConnectionStatus.disconnected => (Colors.grey, 'Déconnecté'),
        };

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Se connecter au PC',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                StatusDot(color: color, label: label),
                if (client.serverHostname != null &&
                    client.isConnected) ...[
                  const SizedBox(height: 4),
                  Text('PC : ${client.serverHostname}'),
                ],
                if (client.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(client.lastError!,
                      style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'Adresse IP du PC',
                    hintText: '192.168.1.42',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: client.isConnected ? null : _connect,
                  icon: const Icon(Icons.link),
                  label: const Text('Se connecter'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _scanQrCode,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanner un QR code'),
                ),
                if (client.isConnected) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => context.read<ClientController>().disconnect(),
                    icon: const Icon(Icons.link_off, color: Colors.red),
                    label: const Text('Se déconnecter',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QrScannerScreen extends StatelessWidget {
  const _QrScannerScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner le QR code du PC')),
      body: MobileScanner(
        onDetect: (capture) {
          if (capture.barcodes.isEmpty) return;
          final value = capture.barcodes.first.rawValue;
          if (value != null) {
            Navigator.of(context).pop(value);
          }
        },
      ),
    );
  }
}
