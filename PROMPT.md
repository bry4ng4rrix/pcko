# Prompt pour Claude Code — WiFi LAN Monitor

Copie-colle ce prompt dans Claude Code à la racine d'un dossier vide (ou d'un projet Flutter déjà initialisé) pour démarrer la construction. Traite les phases **dans l'ordre**, et valide chaque phase avant de passer à la suivante.

---

## Contexte et objectif

Construis une application **Flutter unique** (mono-repo, un seul `pubspec.yaml`) qui fonctionne en deux rôles selon la plateforme d'exécution :

- **Windows / Linux (desktop)** → rôle **serveur** : collecte en continu les métriques matérielles de la machine (usage CPU, température CPU, usage GPU, température GPU, usage RAM, débit réseau) et les diffuse via un serveur WebSocket sur le réseau local.
- **Android (mobile)** → rôle **client** : se connecte au serveur WebSocket du PC (même réseau WiFi) et affiche ces métriques en temps réel sous forme de dashboard (jauges + courbes).

Contraintes générales :
- Le code doit tourner **sans connexion Internet**, uniquement sur le réseau local (LAN).
- Ne jamais fabriquer de valeurs factices pour une métrique indisponible : afficher explicitement "indisponible" / `null` plutôt qu'une fausse valeur.
- Le rafraîchissement des métriques doit être configurable (par défaut 1000 ms).
- Le code doit être organisé en modules clairs, testables indépendamment (collecteurs, serveur, client, UI).

## Stack imposée

- Flutter 3.x / Dart 3, null-safety
- `dart:io` pour le serveur WebSocket (`HttpServer` + `WebSocketTransformer`), pas de dépendance serveur externe
- `web_socket_channel` pour le client
- `fl_chart` pour les courbes temps réel côté Android
- `provider` pour la gestion d'état
- `network_info_plus` pour récupérer l'IP locale du PC
- `qr_flutter` pour générer un QR code de connexion (IP:port) — optionnel mais souhaité dès la phase 3
- `multicast_dns` pour l'auto-découverte réseau — optionnel, phase 4

## Format du contrat de données (à respecter strictement)

```json
{
  "type": "metrics",
  "timestamp": "2026-08-18T10:15:30Z",
  "hostname": "PC-Bureau",
  "cpu": { "usage_percent": 42.3, "temperature_c": 61.0, "cores": 8 },
  "gpu": { "usage_percent": 15.0, "temperature_c": 54.0, "name": "RTX 3060" },
  "ram": { "used_mb": 8210, "total_mb": 16384, "usage_percent": 50.1 },
  "network": { "download_kbps": 1240.5, "upload_kbps": 320.2, "interface": "wlan0" }
}
```

Champs numériques absents/indisponibles → `null` (jamais 0 par défaut, sauf si la valeur réelle est 0).

Messages de contrôle :
- `{"type": "hello", "hostname": "...", "interval_ms": 1000}` (serveur → client, à la connexion)
- `{"type": "set_interval", "interval_ms": 2000}` (client → serveur)
- `{"type": "ping"}` / `{"type": "pong"}` (keep-alive dans les deux sens)

## Structure de fichiers attendue

```
lib/
├── main.dart
├── shared/models/metrics_payload.dart
├── server/
│   ├── websocket_server.dart
│   └── collectors/
│       ├── metrics_collector.dart
│       ├── linux_collector.dart
│       └── windows_collector.dart
└── client/
    ├── websocket_client.dart
    ├── discovery/lan_discovery.dart
    └── ui/dashboard_screen.dart
```

---

## Phase 1 — Socle du projet + serveur Linux + client minimal

1. Initialise le projet Flutter avec support `windows`, `linux` et `android`.
2. Crée le modèle `MetricsPayload` (dans `shared/models/`) avec `toJson`/`fromJson`, correspondant exactement au contrat JSON ci-dessus.
3. Crée l'interface abstraite `MetricsCollector` avec une méthode `Future<MetricsPayload> collect()`.
4. Implémente `LinuxMetricsCollector` :
   - CPU usage via delta sur `/proc/stat`
   - RAM via `/proc/meminfo`
   - Réseau via delta sur `/proc/net/dev`
   - Température CPU via `/sys/class/thermal/thermal_zone*/temp`, avec fallback sur la commande `sensors -j` si disponible
   - GPU via `nvidia-smi` si la commande existe sur le système (sinon `null`)
5. Implémente `WebSocketServer` : écoute sur un port configurable (par défaut `9090`), diffuse le JSON du collecteur toutes les `interval_ms`, gère plusieurs clients connectés simultanément, gère proprement la déconnexion d'un client.
6. Dans `main.dart`, détecte la plateforme (`Platform.isLinux`, `Platform.isWindows`, `Platform.isAndroid`) et lance le rôle serveur ou client en conséquence.
7. Crée un écran serveur minimal affichant : IP locale, port, nombre de clients connectés, dernier payload envoyé (debug).
8. Implémente `WebSocketClient` côté Android : connexion à une IP/port saisis manuellement, réception des messages, parsing en `MetricsPayload`, gestion de la reconnexion automatique (backoff exponentiel, max 30s) si la connexion est perdue.
9. Crée un écran client minimal qui affiche les valeurs JSON reçues en texte brut (pas encore de dashboard graphique).

**Critère de validation Phase 1** : sur un PC Linux et un téléphone Android connectés au même WiFi, le téléphone reçoit et affiche en texte les métriques réelles du PC, mises à jour chaque seconde.

## Phase 2 — Collecteur Windows

1. Implémente `WindowsMetricsCollector` :
   - CPU/RAM usage via PowerShell (`Get-Counter`) ou `wmic`
   - Température CPU/GPU via requête HTTP vers l'API locale de **LibreHardwareMonitor** (Remote Web Server, port configurable, par défaut `8085`) — si l'API n'est pas accessible, renvoyer `null` pour ces champs et logger un avertissement clair, jamais planter l'app.
   - GPU NVIDIA via `nvidia-smi` si présent.
2. Documente dans le code (commentaire en tête de fichier) la nécessité de lancer LibreHardwareMonitor avec l'option Remote Web Server activée pour obtenir les températures.
3. Ajoute un écran de configuration côté serveur permettant de changer le port WebSocket et le port de l'API LibreHardwareMonitor.

**Critère de validation Phase 2** : le serveur Windows fonctionne en mode dégradé (sans température) si LibreHardwareMonitor n'est pas lancé, et en mode complet sinon.

## Phase 3 — Dashboard Android complet

1. Construis `DashboardScreen` avec :
   - Jauges circulaires (usage CPU %, usage GPU %, usage RAM %)
   - Courbes temps réel (`fl_chart`) sur une fenêtre glissante des 60 dernières secondes pour CPU/RAM/réseau
   - Affichage clair des températures avec code couleur (vert/orange/rouge selon seuils configurables)
   - État "indisponible" explicite pour les champs `null`
2. Ajoute un écran de connexion avec saisie manuelle IP/port **et** un bouton "scanner un QR code" (le PC affiche son QR code IP:port, généré avec `qr_flutter`).
3. Gère l'affichage d'un indicateur de statut de connexion (connecté / reconnexion en cours / déconnecté).

**Critère de validation Phase 3** : dashboard fluide et lisible, avec historique glissant visible, et connexion possible par scan QR code.

## Phase 4 — Auto-découverte et robustesse

1. Implémente une découverte réseau optionnelle via `multicast_dns` : le serveur PC s'annonce comme service `_wifilanmonitor._tcp.local`, le client Android liste les PC détectés sur le réseau sans saisie manuelle.
2. Ajoute un mécanisme de `ping`/`pong` toutes les 5s pour détecter une connexion morte plus vite que le timeout TCP par défaut.
3. Gère le cycle de vie Android (app en arrière-plan) : garder la connexion WebSocket active si possible, ou la reprendre proprement au retour en avant-plan.
4. Ajoute des tests unitaires sur le parsing JSON du modèle `MetricsPayload` et sur la logique de calcul des deltas CPU/réseau (Linux).

**Critère de validation Phase 4** : le téléphone détecte automatiquement le PC sur le réseau sans saisie manuelle, et la connexion résiste à une mise en arrière-plan de l'app.

## Phase 5 — Sécurité et finitions

1. Ajoute un token/PIN partagé généré côté serveur (affiché à l'écran + dans le QR code) et vérifié à la connexion du client ; refuser toute connexion sans le bon token.
2. Ajoute un écran de paramètres côté client (intervalle de rafraîchissement, seuils d'alerte température).
3. Nettoie les logs, ajoute une gestion d'erreur explicite partout où un `Process.run` ou une requête HTTP peut échouer (timeout, commande absente, etc.).

**Critère de validation Phase 5** : un appareil non autorisé ne peut pas se connecter au serveur sans le PIN, et l'app ne plante jamais silencieusement en cas d'erreur de collecte.

---

## Consignes générales pour Claude Code

- Implémente une phase à la fois, montre le résultat, attends validation avant de continuer.
- Privilégie la lisibilité et les commentaires en français dans le code.
- Ne jamais introduire de dépendance nécessitant une connexion Internet pour fonctionner (tout doit marcher en LAN pur).
- Si une métrique n'est techniquement pas récupérable sur une plateforme donnée, le dire explicitement plutôt que de l'estimer.
