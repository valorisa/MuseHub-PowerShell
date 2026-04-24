# MuseHub-PowerShell

> **Un toolkit PowerShell 7 pour automatiser, auditer et orchestrer votre écosystème Muse Hub sous Windows 11.**

[![PowerShell](https://img.shields.io/badge/PowerShell-7.6%2B-blue?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-11%20Enterprise-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-valorisa%2Fmusehub--pwsh-181717?logo=github)](https://github.com/valorisa/musehub-pwsh)
[![Maintenance](https://img.shields.io/badge/Maintained-yes-brightgreen)](https://github.com/valorisa/musehub-pwsh/graphs/commit-activity)

---

## Table des matières

- [À propos du projet](#à-propos-du-projet)
- [Qu'est-ce que Muse Hub ?](#quest-ce-que-muse-hub-)
- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Structure du dépôt](#structure-du-dépôt)
- [Utilisation](#utilisation)
  - [Audit des plugins installés](#audit-des-plugins-installés)
  - [Sauvegarde des préférences](#sauvegarde-des-préférences)
  - [Mise à jour automatisée](#mise-à-jour-automatisée)
  - [Rapport HTML](#rapport-html)
- [Configuration](#configuration)
- [Modules PowerShell](#modules-powershell)
- [Tests](#tests)
- [Feuille de route](#feuille-de-route)
- [Contribuer](#contribuer)
- [Auteur](#auteur)
- [Licence](#licence)
- [Remerciements](#remerciements)

---

## À propos du projet

**musehub-pwsh** est un ensemble de scripts et de modules PowerShell 7 conçus pour les musiciens producteurs et sound designers sous Windows 11 qui utilisent [Muse Hub](https://www.musehub.com) au quotidien.

L'objectif est de combler le manque d'outils en ligne de commande autour de l'écosystème Muse Hub : auditer l'état des plugins VST/AU installés, automatiser les sauvegardes des presets, générer des rapports d'inventaire détaillés et synchroniser les configurations entre plusieurs postes de travail.

Ce projet n'est pas affilié à Muse Group ni à ses filiales. Il s'agit d'un projet communautaire open-source.

---

## Qu'est-ce que Muse Hub ?

[Muse Hub](https://www.musehub.com) est la plateforme de distribution de plugins et d'instruments virtuels développée par **Muse Group**, la société à l'origine des logiciels MuseScore, Audacity, Ultimate Guitar et LANDR. Lancée en 2022, elle propose un catalogue croissant de plugins VST3, instruments virtuels et effets audio, dont une large part est disponible **gratuitement**.

### Plugins et instruments notables disponibles via Muse Hub

- **Muse Strings** — Bibliothèque de cordes orchestrales haute fidélité.
- **Muse Brass** — Cuivres symphoniques avec articulations multiples.
- **Muse Choir** — Chœurs mixtes avec phonèmes chantés.
- **Muse Percussion** — Percussions orchestrales et ethniques.
- **Audacity** — L'éditeur audio multi-piste open-source historique.
- **MuseScore 4** — Le logiciel de notation musicale de référence.
- Plugins tiers partenaires (effets, synthétiseurs, utilitaires).

### Pourquoi un outil en ligne de commande ?

L'interface graphique de Muse Hub est fluide pour la découverte et l'installation. Cependant, les utilisateurs avancés — ingénieurs du son, compositeurs avec plusieurs postes, administrateurs IT en studio — ont besoin de :

- Savoir exactement quels plugins sont installés, dans quelle version et à quel chemin.
- Automatiser les sauvegardes de presets avant une réinstallation système.
- Générer des inventaires pour des besoins de licence ou de documentation.
- Scripter les mises à jour dans des pipelines CI/CD d'un studio.

**musehub-pwsh** répond précisément à ces besoins.

---

## Fonctionnalités

- **Audit complet** — Détecte tous les plugins Muse Hub installés (VST3, CLAP, exécutables) avec leur version, chemin, taille et date d'installation.
- **Rapport HTML interactif** — Génère un rapport visuel prêt à être partagé ou archivé.
- **Rapport CSV/JSON** — Export des données d'inventaire dans des formats exploitables par d'autres outils.
- **Sauvegarde des presets** — Copie et archive les presets utilisateur dans un répertoire de sauvegarde horodaté.
- **Restauration des presets** — Réimporte une sauvegarde dans le répertoire attendu par Muse Hub.
- **Vérification des mises à jour** — Compare les versions locales avec le catalogue en ligne de Muse Hub via son API publique.
- **Nettoyage des caches** — Purge les fichiers temporaires et caches de téléchargement de Muse Hub.
- **Mode silencieux** — Toutes les commandes acceptent un flag `-Silent` pour une intégration dans des pipelines automatisés.
- **Journalisation** — Chaque opération produit un fichier de log horodaté dans `logs/`.
- **Profils multi-postes** — Exportez et importez des profils de configuration pour synchroniser plusieurs DAW.

---

## Prérequis

Avant d'utiliser **musehub-pwsh**, assurez-vous que les éléments suivants sont installés et configurés sur votre système.

### Système d'exploitation

- Windows 11 (toutes éditions, dont Enterprise)
- Windows 10 version 22H2 ou ultérieure (support limité)

### PowerShell

- **PowerShell 7.6.1** ou supérieur (PowerShell Core)
- PowerShell 5.1 (Windows PowerShell) n'est **pas** supporté

Vérifiez votre version :

```powershell
$PSVersionTable.PSVersion
```

Téléchargez PowerShell 7 depuis le [dépôt officiel GitHub](https://github.com/PowerShell/PowerShell/releases).

### Muse Hub

- [Muse Hub](https://www.musehub.com) installé et ayant effectué au moins une synchronisation.
- Chemin d'installation par défaut : `C:\Program Files\Muse Hub\`

### Modules PowerShell requis

Les modules suivants seront installés automatiquement si absents (voir section [Installation](#installation)) :

| Module | Version minimale | Usage |
|---|---|---|
| `PSWriteHTML` | 1.0.0 | Génération des rapports HTML |
| `ImportExcel` | 7.8.0 | Export Excel optionnel |
| `Pester` | 5.6.0 | Exécution des tests unitaires |

### Droits d'exécution

Autorisez l'exécution des scripts PowerShell signés localement :

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Installation

### Cloner le dépôt

Ouvrez **PowerShell 7** et exécutez les commandes suivantes :

```powershell
# Se placer dans l'espace de travail
Set-Location -Path "C:\Users\bbrod\Projets"

# Cloner le dépôt
git clone https://github.com/valorisa/musehub-pwsh.git

# Entrer dans le répertoire
Set-Location -Path "musehub-pwsh"
```

### Installer les dépendances

Un script d'amorçage installe automatiquement les modules PowerShell nécessaires :

```powershell
.\scripts\Install-Dependencies.ps1
```

Ce script effectue les opérations suivantes :

1. Vérifie la version de PowerShell (7.x requis).
2. Installe `PSWriteHTML`, `ImportExcel` et `Pester` depuis PSGallery si absents.
3. Vérifie la présence de Muse Hub et détecte son répertoire d'installation.
4. Crée les répertoires `logs/` et `backups/` s'ils n'existent pas.
5. Génère un fichier de configuration initiale `config/musehub-pwsh.json`.

### Vérifier l'installation

```powershell
.\musehub-pwsh.ps1 -Version
```

Résultat attendu :

```text
musehub-pwsh v1.0.0
PowerShell 7.6.1 | Windows 11 Enterprise
Muse Hub détecté : C:\Program Files\Muse Hub\MuseHub.exe (v2.x.x)
```

---

## Structure du dépôt

```text
musehub-pwsh/
├── musehub-pwsh.ps1          # Point d'entrée principal (dispatcher)
├── config/
│   └── musehub-pwsh.json     # Configuration utilisateur (généré à l'init)
├── modules/
│   ├── Audit.psm1            # Détection et inventaire des plugins
│   ├── Backup.psm1           # Sauvegarde et restauration des presets
│   ├── Report.psm1           # Génération des rapports HTML, CSV, JSON
│   ├── Update.psm1           # Vérification et déclenchement des mises à jour
│   ├── Cache.psm1            # Nettoyage des caches Muse Hub
│   └── Logger.psm1           # Système de journalisation centralisé
├── scripts/
│   └── Install-Dependencies.ps1  # Script d'amorçage des dépendances
├── tests/
│   ├── Audit.Tests.ps1
│   ├── Backup.Tests.ps1
│   └── Report.Tests.ps1
├── logs/                     # Journaux d'exécution (ignoré par Git)
├── backups/                  # Sauvegardes des presets (ignoré par Git)
├── docs/
│   ├── CONTRIBUTING.md
│   ├── CHANGELOG.md
│   └── screenshots/
├── .gitignore
├── LICENSE
└── README.md
```

---

## Utilisation

Toutes les commandes s'exécutent depuis la racine du projet dans **PowerShell 7**.

### Audit des plugins installés

Scanne le système à la recherche de tous les composants Muse Hub installés.

```powershell
.\musehub-pwsh.ps1 -Action Audit
```

Exemple de sortie console :

```text
[INFO] Démarrage de l'audit Muse Hub...
[INFO] Recherche des plugins VST3...
  ✔ Muse Strings        v1.3.0   C:\Program Files\Common Files\VST3\MuseStrings.vst3
  ✔ Muse Brass          v1.1.2   C:\Program Files\Common Files\VST3\MuseBrass.vst3
  ✔ Muse Choir          v1.0.5   C:\Program Files\Common Files\VST3\MuseChoir.vst3
  ✔ Muse Percussion     v1.2.1   C:\Program Files\Common Files\VST3\MusePercussion.vst3
[INFO] Recherche des applications Muse Hub...
  ✔ MuseScore 4         v4.4.3   C:\Program Files\MuseScore 4\
  ✔ Audacity            v3.6.4   C:\Program Files\Audacity\
[INFO] Audit terminé : 6 composants détectés en 2.3s
```

Pour exporter l'inventaire :

```powershell
# Export JSON
.\musehub-pwsh.ps1 -Action Audit -OutputFormat JSON -OutputPath ".\logs\audit.json"

# Export CSV
.\musehub-pwsh.ps1 -Action Audit -OutputFormat CSV -OutputPath ".\logs\audit.csv"
```

### Sauvegarde des préférences

Sauvegarde l'ensemble des presets utilisateur Muse Hub dans le répertoire `backups/`.

```powershell
.\musehub-pwsh.ps1 -Action Backup
```

La sauvegarde est automatiquement compressée en archive `.zip` et horodatée :

```text
backups/
└── musehub-backup-2025-04-24T14-32-00/
    ├── presets/
    │   ├── MuseStrings/
    │   ├── MuseBrass/
    │   └── ...
    ├── musehub-config.json
    └── backup-manifest.json
```

Pour restaurer une sauvegarde :

```powershell
.\musehub-pwsh.ps1 -Action Restore -BackupPath ".\backups\musehub-backup-2025-04-24T14-32-00"
```

### Mise à jour automatisée

Vérifie si des mises à jour sont disponibles pour les composants Muse Hub installés.

```powershell
# Vérification seule (sans installation)
.\musehub-pwsh.ps1 -Action CheckUpdates

# Vérification et déclenchement des mises à jour disponibles
.\musehub-pwsh.ps1 -Action Update
```

> **Note :** La commande `-Action Update` lance l'interface Muse Hub en mode mise à jour silencieuse. Une connexion Internet est requise. Les mises à jour des bibliothèques d'échantillons (plusieurs Go) sont exclues par défaut pour éviter une saturation de la bande passante. Utilisez le flag `-IncludeSampleLibraries` pour les inclure.

### Rapport HTML

Génère un rapport visuel complet de l'état de votre installation Muse Hub.

```powershell
.\musehub-pwsh.ps1 -Action Report -OutputPath ".\logs\rapport-musehub.html"
```

Le rapport HTML inclut :

- Un tableau de bord synthétique (nombre de plugins, espace disque utilisé, état des mises à jour).
- Un tableau interactif et triable de tous les composants installés.
- Un graphique de répartition par catégorie (instruments, effets, applications).
- L'historique des 10 dernières opérations journalisées.

Ouvrez le rapport dans votre navigateur :

```powershell
Start-Process ".\logs\rapport-musehub.html"
```

### Nettoyage du cache

Supprime les fichiers temporaires et caches de téléchargement accumulés par Muse Hub.

```powershell
.\musehub-pwsh.ps1 -Action CleanCache
```

> **Attention :** Cette opération ne supprime pas les plugins installés ni les presets. Elle cible uniquement les répertoires `%TEMP%\MuseHub\` et `%LOCALAPPDATA%\Muse Hub\Cache\`.

---

## Configuration

Le fichier `config/musehub-pwsh.json` centralise tous les paramètres du toolkit. Il est généré automatiquement lors de la première exécution de `Install-Dependencies.ps1`.

```json
{
  "$schema": "https://raw.githubusercontent.com/valorisa/musehub-pwsh/main/config/schema.json",
  "musehub": {
    "installPath": "C:\\Program Files\\Muse Hub",
    "presetsPath": "%APPDATA%\\Muse Hub\\Presets",
    "cachePath": "%LOCALAPPDATA%\\Muse Hub\\Cache",
    "vst3ScanPaths": [
      "C:\\Program Files\\Common Files\\VST3",
      "%APPDATA%\\VST3"
    ]
  },
  "backup": {
    "destination": "C:\\Users\\bbrod\\Projets\\musehub-pwsh\\backups",
    "maxBackups": 10,
    "compress": true,
    "includeSampleLibraries": false
  },
  "report": {
    "defaultFormat": "HTML",
    "openAfterGeneration": true,
    "theme": "dark"
  },
  "logging": {
    "level": "INFO",
    "maxLogFiles": 30,
    "logPath": "C:\\Users\\bbrod\\Projets\\musehub-pwsh\\logs"
  }
}
```

### Paramètres notables

| Clé | Type | Description |
|---|---|---|
| `musehub.vst3ScanPaths` | `string[]` | Chemins supplémentaires à scanner pour les VST3 |
| `backup.maxBackups` | `integer` | Nombre maximal de sauvegardes conservées (rotation automatique) |
| `backup.includeSampleLibraries` | `boolean` | Inclure les bibliothèques d'échantillons dans les sauvegardes |
| `report.theme` | `string` | Thème du rapport HTML (`dark` ou `light`) |
| `logging.level` | `string` | Niveau de verbosité : `DEBUG`, `INFO`, `WARNING`, `ERROR` |

---

## Modules PowerShell

Le cœur du projet est organisé en modules PowerShell indépendants et testables unitairement.

### `Audit.psm1`

Ce module expose les fonctions de détection et d'inventaire.

| Fonction | Description |
|---|---|
| `Get-MuseHubPlugins` | Retourne la liste des plugins VST3/CLAP installés |
| `Get-MuseHubApplications` | Retourne les applications Muse Hub (MuseScore, Audacity…) |
| `Get-MuseHubInventory` | Agrège les résultats de `Get-MuseHubPlugins` et `Get-MuseHubApplications` |
| `Test-MuseHubInstallation` | Vérifie l'intégrité de l'installation Muse Hub |

Exemple d'utilisation directe du module :

```powershell
Import-Module .\modules\Audit.psm1

$inventory = Get-MuseHubInventory
$inventory | Format-Table -AutoSize
```

### `Backup.psm1`

| Fonction | Description |
|---|---|
| `Invoke-MuseHubBackup` | Déclenche une sauvegarde complète des presets |
| `Restore-MuseHubBackup` | Restaure une sauvegarde dans les répertoires Muse Hub |
| `Get-MuseHubBackups` | Liste les sauvegardes disponibles dans le répertoire de destination |
| `Remove-OldBackups` | Supprime les sauvegardes en excès selon `backup.maxBackups` |

### `Report.psm1`

| Fonction | Description |
|---|---|
| `Export-MuseHubReport` | Génère un rapport dans le format spécifié (HTML, CSV, JSON) |
| `New-MuseHubHtmlReport` | Crée le rapport HTML interactif via `PSWriteHTML` |
| `Export-MuseHubCsv` | Exporte l'inventaire en CSV |
| `Export-MuseHubJson` | Exporte l'inventaire en JSON formaté |

### `Update.psm1`

| Fonction | Description |
|---|---|
| `Get-MuseHubUpdates` | Compare les versions locales avec le catalogue Muse Hub |
| `Invoke-MuseHubUpdate` | Déclenche le processus de mise à jour via l'exécutable Muse Hub |

### `Cache.psm1`

| Fonction | Description |
|---|---|
| `Clear-MuseHubCache` | Supprime les caches temporaires de Muse Hub |
| `Get-MuseHubCacheSize` | Calcule la taille actuelle des caches |

### `Logger.psm1`

| Fonction | Description |
|---|---|
| `Write-MuseLog` | Écrit un message horodaté dans le fichier de log courant |
| `Get-MuseLogPath` | Retourne le chemin du fichier de log de la session courante |
| `Invoke-LogRotation` | Supprime les fichiers de log au-delà de `logging.maxLogFiles` |

---

## Tests

Les tests unitaires sont écrits avec le framework [Pester 5](https://pester.dev/).

### Exécuter tous les tests

```powershell
Invoke-Pester -Path ".\tests\" -Output Detailed
```

### Exécuter les tests d'un module spécifique

```powershell
Invoke-Pester -Path ".\tests\Audit.Tests.ps1" -Output Detailed
```

### Générer un rapport de couverture

```powershell
Invoke-Pester -Path ".\tests\" -CodeCoverage ".\modules\*.psm1" -CodeCoverageOutputFile ".\logs\coverage.xml"
```

### Exemple de test Pester

```powershell
Describe "Get-MuseHubPlugins" {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\modules\Audit.psm1"
    }

    Context "Quand Muse Hub est installé" {
        It "Retourne une liste non vide" {
            $result = Get-MuseHubPlugins
            $result | Should -Not -BeNullOrEmpty
        }

        It "Chaque plugin possède une propriété 'Name'" {
            $result = Get-MuseHubPlugins
            $result | ForEach-Object { $_.Name | Should -Not -BeNullOrEmpty }
        }

        It "Chaque plugin possède une propriété 'Version' valide" {
            $result = Get-MuseHubPlugins
            $result | ForEach-Object {
                $_.Version | Should -Match '^\d+\.\d+\.\d+$'
            }
        }
    }
}
```

---

## Feuille de route

Les fonctionnalités planifiées pour les prochaines versions sont les suivantes.

### v1.1.0 — Synchronisation multi-postes

- Exportation d'un profil complet (plugins + presets + configuration) vers un partage réseau ou OneDrive.
- Importation du profil sur un autre poste pour répliquer l'environnement de production.

### v1.2.0 — Intégration DAW

- Détection automatique des DAW installés (Reaper, Ableton Live, FL Studio, Cubase, Studio One).
- Vérification que chaque plugin Muse Hub est correctement référencé dans les scanpaths de chaque DAW.
- Génération d'un rapport de compatibilité DAW/plugin.

### v1.3.0 — Tableau de bord TUI

- Interface en ligne de commande interactive basée sur [Terminal-UI](https://github.com/nickcoutsos/terminalui) pour naviguer dans l'inventaire et déclencher des actions sans mémoriser les flags.

### v2.0.0 — API REST locale

- Exposition d'une mini-API REST locale (via `Pode`) permettant d'intégrer musehub-pwsh dans des outils tiers, des dashboards HomeAssistant ou des scripts Python/Node.

---

## Contribuer

Les contributions sont les bienvenues ! Avant de soumettre une Pull Request, merci de lire le guide [CONTRIBUTING.md](docs/CONTRIBUTING.md).

### Processus de contribution

1. Forkez le dépôt.
2. Créez une branche de fonctionnalité : `git checkout -b feature/ma-nouvelle-fonctionnalite`.
3. Committez vos changements : `git commit -m "feat: ajoute la fonctionnalité X"`.
4. Poussez vers votre fork : `git push origin feature/ma-nouvelle-fonctionnalite`.
5. Ouvrez une Pull Request sur le dépôt principal.

### Standards de code

- Respectez les conventions de nommage PowerShell : verbe-nom approuvé (`Get-`, `Set-`, `Invoke-`, etc.).
- Documentez chaque fonction publique avec un bloc `<#.SYNOPSIS / .DESCRIPTION / .PARAMETER / .EXAMPLE#>`.
- Ajoutez un test Pester pour chaque nouvelle fonction exposée.
- Assurez-vous que `Invoke-Pester` passe à 100 % avant de soumettre.

### Signaler un bug

Ouvrez une [issue GitHub](https://github.com/valorisa/musehub-pwsh/issues) en utilisant le template **Bug Report** et incluez :

- La version de musehub-pwsh (`.\musehub-pwsh.ps1 -Version`).
- La sortie de `$PSVersionTable`.
- Le contenu du fichier de log de la session concernée.

---

## Auteur

**valorisa**

- GitHub : [github.com/valorisa](https://github.com/valorisa)
- Projet hébergé dans : `C:\Users\bbrod\Projets\musehub-pwsh\`

---

## Licence

Ce projet est distribué sous licence **MIT**. Consultez le fichier [LICENSE](LICENSE) pour les détails complets.

---

## Remerciements

- [Muse Group](https://www.musegroup.com) pour l'écosystème Muse Hub et ses plugins gratuits de qualité professionnelle.
- L'équipe [PowerShell](https://github.com/PowerShell/PowerShell) pour PowerShell 7 et sa richesse d'API cross-platform.
- [EvotecIT](https://github.com/EvotecIT/PSWriteHTML) pour le module `PSWriteHTML` qui simplifie extraordinairement la génération de rapports HTML.
- [PnP PowerShell Community](https://pnp.github.io) pour les nombreuses ressources et bonnes pratiques PowerShell.
- La communauté [Pester](https://pester.dev) pour un framework de test unitaire robuste et bien documenté.

---

*Dernière mise à jour : 24 avril 2025 — musehub-pwsh v1.0.0*
