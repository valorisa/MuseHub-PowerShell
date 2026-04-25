#Requires -Version 7.0
<#
.SYNOPSIS
    Module de sauvegarde et restauration des presets Muse Hub.
.DESCRIPTION
    Permet de sauvegarder l'intégralité des presets et de la configuration
    Muse Hub dans une archive ZIP horodatée, et de restaurer une sauvegarde
    précédente. Gère également la rotation automatique des sauvegardes.
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

Set-StrictMode -Version Latest

#region Fonctions publiques

function Invoke-MuseHubBackup {
    <#
    .SYNOPSIS
        Déclenche une sauvegarde complète des presets et de la configuration Muse Hub.
    .PARAMETER Destination
        Répertoire de destination des sauvegardes.
    .PARAMETER IncludeSampleLibraries
        Si présent, inclut les bibliothèques d'échantillons (peut peser plusieurs Go).
    .PARAMETER MaxBackups
        Nombre maximal de sauvegardes à conserver (rotation automatique).
    .PARAMETER Silent
        Supprime l'affichage console.
    .OUTPUTS
        PSCustomObject avec BackupPath, SizeKB, Duration, ItemCount.
    .EXAMPLE
        Invoke-MuseHubBackup -Destination "C:\Projets\musehub-pwsh\backups"
    .EXAMPLE
        Invoke-MuseHubBackup -Destination "D:\Backup" -IncludeSampleLibraries -MaxBackups 5
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [string] $Destination,

        [switch] $IncludeSampleLibraries,

        [int] $MaxBackups = 10,

        [switch] $Silent
    )

    Write-MuseLog -Level INFO -Message "=== Démarrage de la sauvegarde Muse Hub ===" -Silent:$Silent
    $startTime = Get-Date

    # Répertoires sources à sauvegarder
    $sourcePaths = [System.Collections.Generic.List[hashtable]]::new()

    $presetsPath = "$env:APPDATA\Muse Hub\Presets"
    $configPath  = "$env:APPDATA\Muse Hub"
    $samplesPath = "$env:LOCALAPPDATA\Muse Hub\Samples"

    if (Test-Path $presetsPath) {
        $sourcePaths.Add(@{ Path = $presetsPath; Label = 'Presets' })
    } else {
        Write-MuseLog -Level WARNING -Message "Répertoire Presets introuvable : $presetsPath" -Silent:$Silent
    }

    if (Test-Path $configPath) {
        $sourcePaths.Add(@{ Path = $configPath; Label = 'Config' })
    }

    if ($IncludeSampleLibraries -and (Test-Path $samplesPath)) {
        $sourcePaths.Add(@{ Path = $samplesPath; Label = 'SampleLibraries' })
        Write-MuseLog -Level INFO -Message "Bibliothèques d'échantillons incluses." -Silent:$Silent
    }

    # Créer le répertoire de destination
    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $timestamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $backupName = "musehub-backup_$timestamp"
    $backupDir  = Join-Path $Destination $backupName
    $zipPath    = "$backupDir.zip"

    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $itemCount = 0

    foreach ($source in $sourcePaths) {
        $targetSubDir = Join-Path $backupDir $source.Label
        Write-MuseLog -Level INFO -Message "  Copie : $($source.Label) → $targetSubDir" -Silent:$Silent

        try {
            Copy-Item -Path $source.Path -Destination $targetSubDir -Recurse -Force -ErrorAction Stop
            $count = (Get-ChildItem -Path $targetSubDir -Recurse -File -ErrorAction SilentlyContinue).Count
            $itemCount += $count
            Write-MuseLog -Level INFO -Message "    $count fichier(s) copiés." -Silent:$Silent
        } catch {
            Write-MuseLog -Level WARNING -Message "    Erreur lors de la copie : $_" -Silent:$Silent
        }
    }

    # Manifeste JSON
    $manifest = [PSCustomObject]@{
        BackupName    = $backupName
        CreatedAt     = (Get-Date -Format 'o')
        Sources       = $sourcePaths | ForEach-Object { $_.Label }
        ItemCount     = $itemCount
        MuseHubPwshVersion = '1.0.0'
    }
    $manifest | ConvertTo-Json -Depth 5 |
        Set-Content -Path (Join-Path $backupDir 'backup-manifest.json') -Encoding UTF8

    # Compression ZIP
    Write-MuseLog -Level INFO -Message "  Compression en cours → $zipPath" -Silent:$Silent
    Compress-Archive -Path "$backupDir\*" -DestinationPath $zipPath -CompressionLevel Optimal -Force
    Remove-Item -Path $backupDir -Recurse -Force

    $sizeKB = [math]::Round((Get-Item $zipPath).Length / 1KB, 2)

    Write-MuseLog -Level INFO -Message "  Archive créée : $zipPath ($sizeKB Ko)" -Silent:$Silent

    # Rotation des anciennes sauvegardes
    Remove-OldBackups -Destination $Destination -MaxBackups $MaxBackups -Silent:$Silent

    $duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
    Write-MuseLog -Level INFO -Message "=== Sauvegarde terminée en $($duration)s ===" -Silent:$Silent

    return [PSCustomObject]@{
        BackupPath = $zipPath
        SizeKB     = $sizeKB
        Duration   = $duration
        ItemCount  = $itemCount
    }
}

function Restore-MuseHubBackup {
    <#
    .SYNOPSIS
        Restaure une sauvegarde Muse Hub dans les répertoires appropriés.
    .PARAMETER BackupPath
        Chemin vers l'archive ZIP de sauvegarde à restaurer.
    .PARAMETER Force
        Écrase les fichiers existants sans confirmation.
    .PARAMETER Silent
        Supprime l'affichage console.
    .EXAMPLE
        Restore-MuseHubBackup -BackupPath ".\backups\musehub-backup_2025-04-24_14-00-00.zip"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string] $BackupPath,

        [switch] $Force,

        [switch] $Silent
    )

    Write-MuseLog -Level INFO -Message "=== Démarrage de la restauration ===" -Silent:$Silent
    Write-MuseLog -Level INFO -Message "  Source : $BackupPath" -Silent:$Silent

    $tempDir = Join-Path $env:TEMP "musehub-restore-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        Expand-Archive -Path $BackupPath -DestinationPath $tempDir -Force
        Write-MuseLog -Level INFO -Message "  Archive extraite dans : $tempDir" -Silent:$Silent

        # Lire le manifeste
        $manifestPath = Join-Path $tempDir 'backup-manifest.json'
        if (Test-Path $manifestPath) {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            Write-MuseLog -Level INFO -Message "  Manifeste lu : $($manifest.ItemCount) fichier(s), créé le $($manifest.CreatedAt)" -Silent:$Silent
        }

        # Restauration des presets
        $presetsSource = Join-Path $tempDir 'Presets'
        if (Test-Path $presetsSource) {
            $presetsTarget = "$env:APPDATA\Muse Hub\Presets"
            if ($PSCmdlet.ShouldProcess($presetsTarget, 'Restaurer les presets')) {
                Copy-Item -Path "$presetsSource\*" -Destination $presetsTarget -Recurse -Force:$Force
                Write-MuseLog -Level INFO -Message "  Presets restaurés → $presetsTarget" -Silent:$Silent
            }
        }

        # Restauration de la config
        $configSource = Join-Path $tempDir 'Config'
        if (Test-Path $configSource) {
            $configTarget = "$env:APPDATA\Muse Hub"
            if ($PSCmdlet.ShouldProcess($configTarget, 'Restaurer la configuration')) {
                Get-ChildItem -Path $configSource -Filter '*.json' | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination $configTarget -Force:$Force
                }
                Write-MuseLog -Level INFO -Message "  Configuration restaurée → $configTarget" -Silent:$Silent
            }
        }

        Write-MuseLog -Level INFO -Message "=== Restauration terminée avec succès ===" -Silent:$Silent

    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-MuseHubBackups {
    <#
    .SYNOPSIS
        Liste les sauvegardes disponibles dans le répertoire de destination.
    .PARAMETER Destination
        Répertoire contenant les archives de sauvegarde.
    .OUTPUTS
        System.IO.FileInfo[] trié par date décroissante.
    .EXAMPLE
        Get-MuseHubBackups -Destination ".\backups" | Format-Table Name, LastWriteTime, @{N='SizeMB';E={[math]::Round($_.Length/1MB,2)}}
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param (
        [Parameter(Mandatory)]
        [string] $Destination
    )

    if (-not (Test-Path $Destination)) {
        Write-MuseLog -Level WARNING -Message "Répertoire de sauvegarde introuvable : $Destination"
        return @()
    }

    return Get-ChildItem -Path $Destination -Filter 'musehub-backup_*.zip' |
        Sort-Object LastWriteTime -Descending
}

function Remove-OldBackups {
    <#
    .SYNOPSIS
        Supprime les sauvegardes en excès selon le quota MaxBackups.
    .PARAMETER Destination
        Répertoire contenant les archives de sauvegarde.
    .PARAMETER MaxBackups
        Nombre maximal de sauvegardes à conserver.
    .PARAMETER Silent
        Supprime l'affichage console.
    .EXAMPLE
        Remove-OldBackups -Destination ".\backups" -MaxBackups 5
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Destination,

        [int] $MaxBackups = 10,

        [switch] $Silent
    )

    $backups = Get-MuseHubBackups -Destination $Destination

    if ($backups.Count -gt $MaxBackups) {
        $toDelete = $backups | Select-Object -Skip $MaxBackups
        foreach ($backup in $toDelete) {
            Remove-Item -Path $backup.FullName -Force
            Write-MuseLog -Level INFO -Message "  Ancienne sauvegarde supprimée : $($backup.Name)" -Silent:$Silent
        }
        Write-MuseLog -Level INFO -Message "Rotation : $($toDelete.Count) archive(s) supprimée(s)." -Silent:$Silent
    }
}

#endregion

Export-ModuleMember -Function @(
    'Invoke-MuseHubBackup',
    'Restore-MuseHubBackup',
    'Get-MuseHubBackups',
    'Remove-OldBackups'
)
