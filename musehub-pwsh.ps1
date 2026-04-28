#Requires -Version 7.0
<#
.SYNOPSIS
    musehub-pwsh — Toolkit PowerShell pour l'écosystème Muse Hub.
.DESCRIPTION
    Point d'entrée principal du projet musehub-pwsh.
    Dispatche les actions vers les modules appropriés selon les paramètres fournis.

    Actions disponibles :
      Audit        — Inventaire des plugins et applications Muse Hub installés.
      Backup       — Sauvegarde des presets et de la configuration.
      Restore      — Restauration d'une sauvegarde.
      Report       — Génération d'un rapport HTML, CSV ou JSON.
      CheckUpdates — Vérification des mises à jour disponibles.
      Update       — Vérification et déclenchement des mises à jour.
      CleanCache   — Nettoyage des caches Muse Hub.
      CacheSize    — Affichage de la taille actuelle des caches.

.PARAMETER Action
    Action à exécuter (voir liste ci-dessus).
.PARAMETER OutputFormat
    Format de sortie pour l'action Audit ou Report : HTML, CSV ou JSON.
.PARAMETER OutputPath
    Chemin de fichier de sortie pour les exports.
.PARAMETER BackupPath
    Chemin vers une archive ZIP pour l'action Restore.
.PARAMETER IncludeSampleLibraries
    Inclure les bibliothèques d'échantillons dans les sauvegardes ou mises à jour.
.PARAMETER Silent
    Mode silencieux (log fichier uniquement, pas de sortie console).
.PARAMETER Version
    Affiche la version du toolkit et quitte.
.PARAMETER Config
    Chemin vers un fichier de configuration alternatif.
.EXAMPLE
    .\musehub-pwsh.ps1 -Action Audit
.EXAMPLE
    .\musehub-pwsh.ps1 -Action Audit -OutputFormat CSV -OutputPath ".\logs\audit.csv"
.EXAMPLE
    .\musehub-pwsh.ps1 -Action Backup
.EXAMPLE
    .\musehub-pwsh.ps1 -Action Report -OutputPath ".\logs\rapport.html"
.EXAMPLE
    .\musehub-pwsh.ps1 -Action CleanCache
.EXAMPLE
    .\musehub-pwsh.ps1 -Version
.NOTES
    Auteur  : valorisa
    GitHub  : https://github.com/valorisa/musehub-pwsh
    Licence : MIT
#>

[CmdletBinding()]
param (
    [ValidateSet('Audit', 'Backup', 'Restore', 'Report', 'CheckUpdates', 'Update', 'CleanCache', 'CacheSize')]
    [string] $Action,

    [ValidateSet('HTML', 'CSV', 'JSON')]
    [string] $OutputFormat = 'HTML',

    [string] $OutputPath,

    [string] $BackupPath,

    [switch] $IncludeSampleLibraries,

    [switch] $Silent,

    [switch] $Version,

    [string] $Config
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Constantes

$script:ToolkitVersion = '1.0.0'
$script:ScriptRoot     = $PSScriptRoot
$script:ModulesDir     = Join-Path $script:ScriptRoot 'modules'
$script:DefaultConfig  = Join-Path $script:ScriptRoot 'config\musehub-pwsh.json'

#endregion

#region Fonctions utilitaires internes

function Import-MuseModules {
    $modules = @('Logger', 'Audit', 'Backup', 'Report', 'Update', 'Cache')
    foreach ($mod in $modules) {
        $path = Join-Path $script:ModulesDir "$mod.psm1"
        if (Test-Path $path) {
            Import-Module $path -Force -Global -DisableNameChecking
        } else {
            Write-Warning "Module introuvable : $path"
        }
    }
}

function Read-MuseConfig {
    param ([string] $ConfigPath)
    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Fichier de configuration introuvable : $ConfigPath. Utilisation des valeurs par défaut."
        return $null
    }
    return Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

function Show-Version {
    $museHub = 'Non détecté'
    $exePaths = @(
        'C:\Program Files\Muse Hub\MuseHub.exe',
        "$env:LOCALAPPDATA\Programs\Muse Hub\MuseHub.exe"
    )
    $exe = $exePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exe) {
        $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion
        $museHub = "v$ver ($exe)"
    }

    Write-Host ""
    Write-Host "  musehub-pwsh v$script:ToolkitVersion" -ForegroundColor Cyan
    Write-Host "  PowerShell $($PSVersionTable.PSVersion) | $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
    Write-Host "  Muse Hub : $museHub" -ForegroundColor Gray
    Write-Host "  GitHub   : https://github.com/valorisa/musehub-pwsh" -ForegroundColor Gray
    Write-Host ""
}

#endregion

#region Point d'entrée

# Afficher la version et quitter
if ($Version) {
    Show-Version
    exit 0
}

# Vérifier qu'une action est fournie
if (-not $Action) {
    Write-Host ""
    Write-Host "  Usage : .\musehub-pwsh.ps1 -Action <action> [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Actions disponibles :" -ForegroundColor Cyan
    Write-Host "    Audit        — Inventaire complet des plugins et applications"
    Write-Host "    Backup       — Sauvegarde des presets et de la configuration"
    Write-Host "    Restore      — Restauration d'une sauvegarde (-BackupPath requis)"
    Write-Host "    Report       — Génération d'un rapport (-OutputFormat HTML|CSV|JSON)"
    Write-Host "    CheckUpdates — Vérification des mises à jour disponibles"
    Write-Host "    Update       — Vérification et installation des mises à jour"
    Write-Host "    CleanCache   — Nettoyage des caches Muse Hub"
    Write-Host "    CacheSize    — Affichage de la taille des caches"
    Write-Host ""
    Write-Host "  Exemple : .\musehub-pwsh.ps1 -Action Audit -OutputFormat CSV -OutputPath .\logs\audit.csv" -ForegroundColor Gray
    Write-Host "  Aide    : Get-Help .\musehub-pwsh.ps1 -Full" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# Charger les modules
Import-MuseModules

# Charger la configuration
$configPath = if ($Config) { $Config } else { $script:DefaultConfig }
$cfg = Read-MuseConfig -ConfigPath $configPath

# Initialiser le logger
$logDir = if ($cfg) { $cfg.logging.logPath } else { Join-Path $script:ScriptRoot 'logs' }
Initialize-MuseLogger -LogDirectory $logDir -Level ($cfg ? $cfg.logging.level : 'INFO')

Write-MuseLog -Level INFO -Message "musehub-pwsh v$script:ToolkitVersion — Action : $Action" -Silent:$Silent

#region Dispatch des actions

switch ($Action) {

    'Audit' {
        $inventory = Get-MuseHubInventory

        if ($OutputPath -or $OutputFormat -ne 'HTML') {
            $path   = if ($OutputPath) { $OutputPath } else { Join-Path $logDir "audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').$($OutputFormat.ToLower())" }
            Export-MuseHubReport -Inventory $inventory -OutputPath $path -Format $OutputFormat -Silent:$Silent
            Write-MuseLog -Level INFO -Message "Export : $path" -Silent:$Silent
        } else {
            # Affichage console formaté
            Write-Host "`n  === Plugins VST3 ===" -ForegroundColor Cyan
            $inventory.Plugins | Format-Table Name, Version, @{N='Taille Ko';E={$_.SizeKB}}, InstalledDate -AutoSize
            Write-Host "  === Applications ===" -ForegroundColor Cyan
            $inventory.Applications | Format-Table Name, Version, Path -AutoSize
            Write-Host "  Total : $($inventory.TotalComponents) composant(s) — $([math]::Round($inventory.TotalSizeKB/1024,2)) Mo`n" -ForegroundColor Green
        }
    }

    'Backup' {
        $dest      = if ($cfg) { $cfg.backup.destination } else { Join-Path $script:ScriptRoot 'backups' }
        $maxBackup = if ($cfg) { $cfg.backup.maxBackups } else { 10 }
        $result = Invoke-MuseHubBackup -Destination $dest -MaxBackups $maxBackup `
                    -IncludeSampleLibraries:$IncludeSampleLibraries -Silent:$Silent
        Write-Host "`n  ✔ Sauvegarde créée : $($result.BackupPath) ($($result.SizeKB) Ko, $($result.Duration)s)`n" -ForegroundColor Green
    }

    'Restore' {
        if (-not $BackupPath) {
            Write-MuseLog -Level ERROR -Message "-BackupPath est requis pour l'action Restore." -Silent:$Silent
            Write-Host "  Erreur : spécifiez -BackupPath <chemin.zip>" -ForegroundColor Red
            exit 1
        }
        Restore-MuseHubBackup -BackupPath $BackupPath -Silent:$Silent
        Write-Host "`n  ✔ Restauration terminée depuis : $BackupPath`n" -ForegroundColor Green
    }

    'Report' {
        $inventory  = Get-MuseHubInventory
        $defaultOut = Join-Path $logDir "rapport-musehub-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
        $outPath    = if ($OutputPath) { $OutputPath } else { $defaultOut }
        $fmt        = $OutputFormat

        $openAfter = $cfg ? $cfg.report.openAfterGeneration : $true
        Export-MuseHubReport -Inventory $inventory -OutputPath $outPath -Format $fmt `
            -OpenAfterGeneration:$openAfter -Silent:$Silent
        Write-Host "`n  ✔ Rapport généré : $outPath`n" -ForegroundColor Green
    }

    'CheckUpdates' {
        $updates = @(Get-MuseHubUpdates -Silent:$Silent)
        if ($updates.Count -eq 0) {
            Write-Host "`n  ✔ Tous les composants sont à jour.`n" -ForegroundColor Green
        } else {
            Write-Host "`n  ⬆ $($updates.Count) mise(s) à jour disponible(s) :" -ForegroundColor Yellow
            $updates | Format-Table Name, CurrentVersion, AvailableVersion, Type -AutoSize
        }
    }

    'Update' {
        $updates = @(Get-MuseHubUpdates -Silent:$Silent)
        if ($updates.Count -eq 0) {
            Write-Host "`n  ✔ Aucune mise à jour nécessaire.`n" -ForegroundColor Green
        } else {
            Invoke-MuseHubUpdate -IncludeSampleLibraries:$IncludeSampleLibraries -Silent:$Silent
        }
    }

    'CleanCache' {
        $result = Clear-MuseHubCache -Silent:$Silent
        Write-Host "`n  ✔ Cache nettoyé : $($result.FreedMB) Mo libérés, $($result.DeletedFiles) fichier(s) supprimé(s).`n" -ForegroundColor Green
        if ($result.Errors.Count -gt 0) {
            Write-Host "  ⚠ $($result.Errors.Count) erreur(s). Consultez : $(Get-MuseLogPath)`n" -ForegroundColor Yellow
        }
    }

    'CacheSize' {
        $cache = Get-MuseHubCacheSize
        Write-Host "`n  === Taille du cache Muse Hub ===" -ForegroundColor Cyan
        $cache.Details | Format-Table Label, @{N='Taille Ko';E={$_.SizeKB}}, Files, Exists -AutoSize
        Write-Host "  Total : $($cache.TotalSizeMB) Mo`n" -ForegroundColor Yellow
    }
}

#endregion

Invoke-LogRotation -LogDirectory $logDir

#endregion
