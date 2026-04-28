#Requires -Version 7.0
<#
.SYNOPSIS
    Script d'amorçage et d'installation des dépendances musehub-pwsh.
.DESCRIPTION
    Ce script doit être exécuté une seule fois après le clonage du dépôt.
    Il vérifie les prérequis système, installe les modules PowerShell requis,
    détecte l'installation de Muse Hub et génère le fichier de configuration initiale.
.EXAMPLE
    .\scripts\Install-Dependencies.ps1
.EXAMPLE
    .\scripts\Install-Dependencies.ps1 -Verbose
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

[CmdletBinding()]
param ()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

#region Helpers

function Write-Step {
    param ([string] $Message, [string] $Color = 'Cyan')
    Write-Host "`n  ► $Message" -ForegroundColor $Color
}

function Write-Ok   { param ([string] $Message) Write-Host "    ✔ $Message" -ForegroundColor Green }
function Write-Warn { param ([string] $Message) Write-Host "    ⚠ $Message" -ForegroundColor Yellow }
function Write-Fail { param ([string] $Message) Write-Host "    ✘ $Message" -ForegroundColor Red }

#endregion

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   musehub-pwsh — Installation des dépendances║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
$projectRoot = Split-Path $scriptDir -Parent

#region Étape 1 — Vérification de PowerShell

Write-Step "Étape 1/5 — Vérification de PowerShell"

$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 7) {
    Write-Ok "PowerShell $psVersion détecté."
} else {
    Write-Fail "PowerShell 7.x requis. Version actuelle : $psVersion"
    Write-Fail "Téléchargez PowerShell 7 sur : https://github.com/PowerShell/PowerShell/releases"
    exit 1
}

#endregion

#region Étape 1b — Déblocage des fichiers du dépôt (Zone.Identifier)

Write-Step "Étape 1b/5 — Déblocage des fichiers issus d'un téléchargement (Zone.Identifier)"

# Lorsque le dépôt est téléchargé en ZIP depuis GitHub (plutôt que cloné via git),
# Windows marque les fichiers avec un ADS NTFS "Zone.Identifier" qui bloque leur
# exécution sous la policy par défaut. Unblock-File ne supprime QUE ce stream et
# n'altère pas le contenu. On limite le scan aux fichiers .ps1/.psm1/.psd1 de
# sous-répertoires connus du projet pour rester conservateur.

$unblockTargets = @(
    (Join-Path $projectRoot 'musehub-pwsh.ps1'),
    (Join-Path $projectRoot 'modules'),
    (Join-Path $projectRoot 'scripts'),
    (Join-Path $projectRoot 'tests')
) | Where-Object { Test-Path $_ }

$unblockCount = 0
foreach ($target in $unblockTargets) {
    $files = if ((Get-Item $target).PSIsContainer) {
        Get-ChildItem -Path $target -Recurse -File -Include '*.ps1','*.psm1','*.psd1' -ErrorAction SilentlyContinue
    } else {
        Get-Item -Path $target -ErrorAction SilentlyContinue
    }

    foreach ($file in $files) {
        if (Get-Item -Path $file.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) {
            try {
                Unblock-File -Path $file.FullName -ErrorAction Stop
                $unblockCount++
            } catch {
                Write-Warn "Impossible de débloquer $($file.FullName) : $_"
            }
        }
    }
}

if ($unblockCount -gt 0) {
    Write-Ok "$unblockCount fichier(s) débloqué(s) (Zone.Identifier retiré)."
} else {
    Write-Ok "Aucun fichier bloqué détecté."
}

#endregion

#region Étape 2 — Installation des modules PSGallery

Write-Step "Étape 2/5 — Installation des modules PowerShell requis"

$requiredModules = @(
    @{ Name = 'PSWriteHTML'; MinVersion = '1.0.0';  Description = 'Génération de rapports HTML' },
    @{ Name = 'ImportExcel';  MinVersion = '7.8.0';  Description = 'Export Excel optionnel' },
    @{ Name = 'Pester';       MinVersion = '5.6.0';  Description = 'Tests unitaires' }
)

# Vérifier la disponibilité de PSGallery
try {
    $null = Find-Module -Name 'Pester' -Repository 'PSGallery' -ErrorAction Stop
    Write-Ok "PSGallery accessible."
} catch {
    Write-Warn "PSGallery inaccessible. Les modules devront être installés manuellement."
}

foreach ($mod in $requiredModules) {
    $installed = Get-Module -ListAvailable -Name $mod.Name |
        Where-Object { $_.Version -ge [version]$mod.MinVersion } |
        Select-Object -First 1

    if ($installed) {
        Write-Ok "$($mod.Name) v$($installed.Version) — déjà installé ($($mod.Description))."
    } else {
        Write-Host "    ⟳ Installation de $($mod.Name) >= $($mod.MinVersion)..." -ForegroundColor Yellow
        try {
            Install-Module -Name $mod.Name -MinimumVersion $mod.MinVersion `
                -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
            Write-Ok "$($mod.Name) installé avec succès."
        } catch {
            Write-Warn "Impossible d'installer $($mod.Name) : $_"
        }
    }
}

#endregion

#region Étape 3 — Détection de Muse Hub

Write-Step "Étape 3/5 — Détection de Muse Hub"

$museHubExePaths = @(
    'C:\Program Files\Muse Hub\MuseHub.exe',
    "$env:LOCALAPPDATA\Programs\Muse Hub\MuseHub.exe"
)

$detectedExe     = $museHubExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
$detectedVersion = 'N/A'
$detectedPath    = 'C:\Program Files\Muse Hub'
$presetsPath     = "$env:APPDATA\Muse Hub\Presets"
$cachePath       = "$env:LOCALAPPDATA\Muse Hub\Cache"

if ($detectedExe) {
    $detectedVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($detectedExe).FileVersion
    $detectedPath    = Split-Path $detectedExe -Parent
    Write-Ok "Muse Hub v$detectedVersion détecté : $detectedExe"
} else {
    Write-Warn "Muse Hub non détecté aux chemins connus."
    Write-Warn "Téléchargez Muse Hub sur : https://www.musehub.com"
    Write-Warn "La configuration sera créée avec les chemins par défaut."
}

if (Test-Path $presetsPath) {
    Write-Ok "Presets : $presetsPath"
} else {
    Write-Warn "Répertoire Presets absent (normal si Muse Hub n'a jamais été lancé) : $presetsPath"
}

#endregion

#region Étape 4 — Création des répertoires de travail

Write-Step "Étape 4/5 — Création des répertoires de travail"

$workDirs = @(
    Join-Path $projectRoot 'logs',
    Join-Path $projectRoot 'backups',
    Join-Path $projectRoot 'config'
)

foreach ($dir in $workDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Ok "Créé : $dir"
    } else {
        Write-Ok "Existant : $dir"
    }
}

#endregion

#region Étape 5 — Génération de la configuration initiale

Write-Step "Étape 5/5 — Génération de la configuration"

$configPath = Join-Path $projectRoot 'config\musehub-pwsh.json'

if (Test-Path $configPath) {
    Write-Warn "Fichier de configuration existant conservé : $configPath"
} else {
    $config = [ordered]@{
        '$schema'  = 'https://raw.githubusercontent.com/valorisa/musehub-pwsh/main/config/schema.json'
        musehub    = [ordered]@{
            installPath    = $detectedPath
            executablePath = if ($detectedExe) { $detectedExe } else { 'C:\Program Files\Muse Hub\MuseHub.exe' }
            version        = $detectedVersion
            presetsPath    = $presetsPath
            cachePath      = $cachePath
            vst3ScanPaths  = @(
                'C:\Program Files\Common Files\VST3',
                "$env:APPDATA\VST3"
            )
        }
        backup     = [ordered]@{
            destination            = (Join-Path $projectRoot 'backups')
            maxBackups             = 10
            compress               = $true
            includeSampleLibraries = $false
        }
        report     = [ordered]@{
            defaultFormat       = 'HTML'
            openAfterGeneration = $true
            theme               = 'dark'
        }
        logging    = [ordered]@{
            level       = 'INFO'
            maxLogFiles = 30
            logPath     = (Join-Path $projectRoot 'logs')
        }
    }

    $config | ConvertTo-Json -Depth 10 |
        Set-Content -Path $configPath -Encoding UTF8

    Write-Ok "Configuration générée : $configPath"
}

#endregion

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║   Installation terminée avec succès !        ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Pour commencer :" -ForegroundColor Cyan
Write-Host "    .\musehub-pwsh.ps1 -Version" -ForegroundColor White
Write-Host "    .\musehub-pwsh.ps1 -Action Audit" -ForegroundColor White
Write-Host "    .\musehub-pwsh.ps1 -Action Report" -ForegroundColor White
Write-Host ""
