# 📡 WiFi LAN Monitor — Monitoring PC en temps réel sur Android via WebSocket

Application Flutter multiplateforme qui permet de visualiser **en temps réel**, depuis un téléphone Android, les métriques matérielles d'un PC (Windows ou Linux) : usage et température CPU, usage et température GPU, RAM, réseau. La communication passe par **WebSocket** sur le réseau WiFi local — aucune donnée ne sort du LAN.

## 1. Architecture générale

```
┌───────────────────────────┐        WiFi local (LAN)         ┌───────────────────────────┐
│   PC (Windows / Linux)    │ ───────── WebSocket (ws) ──────► │      Android (client)     │
│   Flutter Desktop App     │                                  │      Flutter Mobile App   │
│   - Collecte métriques    │ ◄──────── ping / commandes ───── │      - Reçoit le flux JSON│
│   - Serveur WebSocket     │                                  │      - Dashboard temps réel│
└───────────────────────────┘                                  └───────────────────────────┘
```

Un **seul projet Flutter**, avec un dispatch selon la plateforme au démarrage :

- Sur **Windows / Linux** → rôle **serveur** (collecte des métriques + diffusion WebSocket)
- Sur **Android** → rôle **client** (connexion au PC + affichage du dashboard)

Cela évite de dupliquer les modèles de données et simplifie la maintenance.

## 2. Stack technique

| Besoin | Solution |
|---|---|
| Serveur WebSocket (PC) | `dart:io` (`HttpServer` + `WebSocketTransformer`) — pas de dépendance externe nécessaire |
| Client WebSocket (Android) | `web_socket_channel` |
| Graphiques temps réel | `fl_chart` |
| Gestion d'état | `provider` (ou `riverpod`) |
| Affichage IP / connexion facile | `network_info_plus` + `qr_flutter` (optionnel) |
| Auto-découverte sur le LAN | `multicast_dns` (optionnel, façon zeroconf/Bonjour) |

## 3. Collecte des métriques — le point délicat

Flutter n'a **pas** d'accès natif fiable aux capteurs matériels. Il faut passer par des sources spécifiques à chaque OS, appelées via `Process.run` ou lecture de fichiers système.

### Linux
- **CPU usage** : lecture de `/proc/stat` (calcul par delta entre deux lectures)
- **RAM** : `/proc/meminfo`
- **Réseau** : `/proc/net/dev` (delta bytes envoyés/reçus → débit)
- **Température CPU** : `/sys/class/thermal/thermal_zone*/temp`, ou commande `sensors -j` (paquet `lm-sensors` : `sudo apt install lm-sensors`)
- **GPU NVIDIA (un ou plusieurs)** : `nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,name --format=csv,noheader,nounits` renvoie une ligne par carte détectée — toutes les cartes sont listées dans `gpus[]`.
- **GPU AMD/Intel** : plus limité, best-effort via `/sys/class/drm/card0/device/...`
- **FPS écran (rendu réel)** : best-effort via le log CSV de [**MangoHud**](https://github.com/flightlx/MangoHud) (`output_folder=<dossier>` dans `MangoHud.conf`, dossier à renseigner dans `mangoHudLogDirectory`). Sans MangoHud configuré → `null`.

### Windows
- **CPU/RAM usage** : WMI via PowerShell (`Get-Counter`) ou `wmic cpu get LoadPercentage`
- **Température CPU/GPU** : Windows ne l'expose pas nativement de façon fiable. **Solution recommandée** : faire tourner [**LibreHardwareMonitor**](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) (gratuit, open-source) en arrière-plan avec son option *"Remote Web Server"* activée (port local, ex: `8085`). L'app PC interroge simplement cette API HTTP locale en JSON — c'est l'approche la plus fiable et la plus utilisée pour ce genre de projet.
- **GPU NVIDIA (un ou plusieurs)** : `nvidia-smi` fonctionne aussi sous Windows si les drivers sont installés ; une ligne par carte → `gpus[]`.
- **FPS écran (rendu réel)** : best-effort via [**PresentMon**](https://github.com/GameTechDev/PresentMon) (Intel, open-source), à installer et ajouter au PATH. Sans PresentMon → `null`.

> ⚠️ Ces limitations doivent être **affichées honnêtement dans l'UI** (ex: "Température GPU indisponible") plutôt que d'inventer des valeurs par défaut.

## 4. Format des messages WebSocket (JSON)

```json
{
  "type": "metrics",
  "timestamp": "2026-08-18T10:15:30Z",
  "hostname": "PC-Bureau",
  "cpu": { "usage_percent": 42.3, "temperature_c": 61.0, "cores": 8 },
  "gpus": [
    { "usage_percent": 15.0, "temperature_c": 54.0, "name": "RTX 3060" }
  ],
  "ram": { "used_mb": 8210, "total_mb": 16384, "usage_percent": 50.1 },
  "network": { "download_kbps": 1240.5, "upload_kbps": 320.2, "interface": "wlan0" },
  "screen": { "fps": 118.4, "process": "game.exe" }
}
```

Messages de contrôle prévus :
- `{"type": "hello", "hostname": "...", "interval_ms": 1000}` — envoyé par le serveur à la connexion
- `{"type": "set_interval", "interval_ms": 2000}` — envoyé par le client pour ajuster la fréquence
- `{"type": "ping"}` / `{"type": "pong"}` — keep-alive

## 5. Structure du projet

```
wifi_lan_monitor/
├── lib/
│   ├── main.dart                        # dispatch serveur/client selon Platform
│   ├── shared/
│   │   └── models/metrics_payload.dart
│   ├── server/                          # actif uniquement sur desktop
│   │   ├── websocket_server.dart
│   │   └── collectors/
│   │       ├── metrics_collector.dart         # interface abstraite
│   │       ├── linux_collector.dart
│   │       └── windows_collector.dart
│   └── client/                          # actif uniquement sur Android
│       ├── websocket_client.dart
│       ├── discovery/lan_discovery.dart
│       └── ui/dashboard_screen.dart
├── README.md
└── PROMPT.md
```

## 6. Lancer le projet

**Côté PC (serveur)**
```bash
flutter run -d windows   # ou -d linux
```
L'app affiche l'IP locale + le port (ex: `192.168.1.42:9090`) et, idéalement, un QR code.

**Côté Android (client)**
```bash
flutter build apk --release
```
Installer l'APK sur le téléphone connecté au **même réseau WiFi**, puis scanner le QR code ou saisir l'IP manuellement.

## 7. Sécurité

- Communication **non chiffrée** par défaut (`ws://`) car limitée au réseau local — à ne **jamais** exposer sur Internet tel quel.
- Prévoir un **token/PIN partagé** à la connexion pour éviter qu'un autre appareil du réseau se connecte sans autorisation.

## 8. Roadmap / améliorations possibles

- Support multi-PC (dashboard avec plusieurs sources)
- Historique des métriques (graphique sur 24h, export CSV)
- Notifications si température > seuil
- Authentification par PIN/QR sécurisé
- Support iOS pour le client
