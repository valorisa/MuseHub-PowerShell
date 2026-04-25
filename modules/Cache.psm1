#Requires -Version 7.0
<#
.SYNOPSIS
    Module de gestion et nettoyage des caches Muse Hub.
.DESCRIPTION
    Calcule la taille des caches accumulés par Muse Hub et les supprime
    de manière sécurisée. Ne touche ni aux plugins installés ni aux presets.
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

Set-StrictMode -Version Latest

#region Constantes privées

$script:CachePaths = @(
    @{ Label = 'Cache applicatif';    Path = "$env:LOCALAPPDATA\Muse Hub\Cache" },
    @{ Label = 'Cache téléchargement';Path = "$env:LOCALAPPDATA\Muse Hub\Downloads" },
    @{ Label = 'Temp système';        Path = "$env:TEMP\MuseHub" },
    @{ Label = 'Temp système (alt.)'; Path = "$env:TEMP\Muse Hub" },
    @{ Label = 'Logs Muse Hub';       Path = "$env:LOCALAPPDATA\Muse Hub\Logs" }
)

#endregion

#region Fonctions publiques

function Get-MuseHubCacheSize {
    <#
    .SYNOPSIS
        Calcule et retourne la taille totale des caches Muse Hub présents sur le système.
    .OUTPUTS
        PSCustomObject avec TotalSizeKB, TotalSizeMB, Details (liste par répertoire).
    .EXAMPLE
        $cache = Get-MuseHubCacheSize
        Write-Host "Cache total : $($cache.TotalSizeMB) Mo"
        $cache.Details | Format-Table
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    Write-MuseLog -Level INFO -Message "Calcul de la taille des caches Muse Hub..."

    $details = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalKB = 0.0

    foreach ($cache in $script:CachePaths) {
        if (-not (Test-Path $cache.Path)) {
            $details.Add([PSCustomObject]@{
                Label   = $cache.Label
                Path    = $cache.Path
                SizeKB  = 0
                Exists  = $false
                Files   = 0
            })
            continue
        }

        $files     = @(Get-ChildItem -Path $cache.Path -Recurse -File -ErrorAction SilentlyContinue)
        $measure   = $files | Measure-Object -Property Length -Sum
        $sumBytes  = if ($null -ne $measure -and $null -ne $measure.Sum) { $measure.Sum } else { 0 }
        $sizeKB    = [math]::Round($sumBytes / 1KB, 2)
        $fileCount = $files.Count
        $totalKB  += $sizeKB

        $details.Add([PSCustomObject]@{
            Label  = $cache.Label
            Path   = $cache.Path
            SizeKB = $sizeKB
            Exists = $true
            Files  = $fileCount
        })

        Write-MuseLog -Level DEBUG -Message "  $($cache.Label) : $sizeKB Ko ($fileCount fichiers)"
    }

    $result = [PSCustomObject]@{
        TotalSizeKB = [math]::Round($totalKB, 2)
        TotalSizeMB = [math]::Round($totalKB / 1024, 2)
        Details     = $details
    }

    Write-MuseLog -Level INFO -Message "Taille totale du cache : $($result.TotalSizeMB) Mo"
    return $result
}

function Clear-MuseHubCache {
    <#
    .SYNOPSIS
        Supprime les fichiers de cache Muse Hub de manière sécurisée.
    .DESCRIPTION
        Cible uniquement les répertoires de cache connus. Ne supprime
        aucun plugin installé, preset ou fichier de configuration utilisateur.
    .PARAMETER IncludeLogs
        Si présent, supprime également les logs applicatifs de Muse Hub.
    .PARAMETER Silent
        Supprime l'affichage console.
    .OUTPUTS
        PSCustomObject avec FreedKB, FreedMB, DeletedFiles, Errors.
    .EXAMPLE
        Clear-MuseHubCache
    .EXAMPLE
        Clear-MuseHubCache -IncludeLogs -Silent
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param (
        [switch] $IncludeLogs,
        [switch] $Silent
    )

    Write-MuseLog -Level INFO -Message "=== Nettoyage du cache Muse Hub ===" -Silent:$Silent

    # Calculer la taille avant nettoyage
    $sizeBefore = Get-MuseHubCacheSize

    $freedKB      = 0.0
    $deletedFiles = 0
    $errors       = [System.Collections.Generic.List[string]]::new()

    foreach ($cache in $script:CachePaths) {
        # Exclure les logs si non demandé
        if ($cache.Label -like '*Logs*' -and -not $IncludeLogs) {
            Write-MuseLog -Level DEBUG -Message "  Ignoré (logs) : $($cache.Path)" -Silent:$Silent
            continue
        }

        if (-not (Test-Path $cache.Path)) { continue }

        Write-MuseLog -Level INFO -Message "  Nettoyage : $($cache.Label)" -Silent:$Silent

        $files = Get-ChildItem -Path $cache.Path -Recurse -File -ErrorAction SilentlyContinue

        foreach ($file in $files) {
            if ($PSCmdlet.ShouldProcess($file.FullName, 'Supprimer')) {
                try {
                    $sizeKB = [math]::Round($file.Length / 1KB, 2)
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    $freedKB      += $sizeKB
                    $deletedFiles++
                } catch {
                    $errors.Add("$($file.FullName) : $_")
                    Write-MuseLog -Level WARNING -Message "    Impossible de supprimer : $($file.FullName)" -Silent:$Silent
                }
            }
        }

        # Supprimer les répertoires vides
        Get-ChildItem -Path $cache.Path -Recurse -Directory -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Where-Object { (Get-ChildItem $_.FullName -Force).Count -eq 0 } |
            ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    }

    $result = [PSCustomObject]@{
        FreedKB      = [math]::Round($freedKB, 2)
        FreedMB      = [math]::Round($freedKB / 1024, 2)
        DeletedFiles = $deletedFiles
        Errors       = $errors
    }

    Write-MuseLog -Level INFO -Message "=== Cache nettoyé : $($result.FreedMB) Mo libérés, $($result.DeletedFiles) fichier(s) supprimé(s) ===" -Silent:$Silent

    if ($errors.Count -gt 0) {
        Write-MuseLog -Level WARNING -Message "$($errors.Count) erreur(s) lors du nettoyage. Consultez les logs pour les détails." -Silent:$Silent
    }

    return $result
}

#endregion

Export-ModuleMember -Function @(
    'Get-MuseHubCacheSize',
    'Clear-MuseHubCache'
)
