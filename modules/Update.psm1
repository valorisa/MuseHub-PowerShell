#Requires -Version 7.0
<#
.SYNOPSIS
    Module de gestion des mises à jour Muse Hub.
.DESCRIPTION
    Compare les versions locales des composants Muse Hub avec le catalogue
    en ligne, et déclenche le processus de mise à jour via l'exécutable
    Muse Hub si des mises à jour sont disponibles.
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

Set-StrictMode -Version Latest

#region Constantes privées

$script:MuseHubApiBase = 'https://www.musehub.com/api'
$script:MuseHubExePaths = @(
    'C:\Program Files\Muse Hub\MuseHub.exe',
    "$env:LOCALAPPDATA\Programs\Muse Hub\MuseHub.exe"
)

#endregion

#region Fonctions publiques

function Get-MuseHubUpdates {
    <#
    .SYNOPSIS
        Compare les versions locales avec le catalogue Muse Hub et retourne les mises à jour disponibles.
    .PARAMETER Inventory
        Objet inventaire retourné par Get-MuseHubInventory. Si absent, un audit est lancé automatiquement.
    .PARAMETER Silent
        Supprime l'affichage console.
    .OUTPUTS
        System.Collections.Generic.List[PSCustomObject] contenant les composants avec une mise à jour disponible.
    .EXAMPLE
        $updates = Get-MuseHubUpdates
        $updates | Format-Table Name, CurrentVersion, AvailableVersion
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param (
        [PSCustomObject] $Inventory,
        [switch] $Silent
    )

    Write-MuseLog -Level INFO -Message "Vérification des mises à jour Muse Hub..." -Silent:$Silent

    if (-not $Inventory) {
        Write-MuseLog -Level INFO -Message "Aucun inventaire fourni — lancement d'un audit..." -Silent:$Silent
        Import-Module (Join-Path $PSScriptRoot 'Audit.psm1') -Force
        $Inventory = Get-MuseHubInventory
    }

    $updates = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Tenter de joindre l'API Muse Hub
    $catalogAvailable = $false
    try {
        $testRequest = Invoke-WebRequest -Uri "$script:MuseHubApiBase/health" `
            -Method GET -TimeoutSec 5 -ErrorAction Stop -UseBasicParsing
        $catalogAvailable = ($testRequest.StatusCode -eq 200)
    } catch {
        Write-MuseLog -Level WARNING -Message "API Muse Hub inaccessible. Vérification hors-ligne uniquement." -Silent:$Silent
    }

    $allComponents = @($Inventory.Plugins) + @($Inventory.Applications)

    foreach ($component in $allComponents) {
        $availableVersion = $null

        if ($catalogAvailable) {
            try {
                $encodedName = [Uri]::EscapeDataString($component.Name)
                $response    = Invoke-RestMethod -Uri "$script:MuseHubApiBase/products/$encodedName/latest" `
                    -Method GET -TimeoutSec 10 -ErrorAction Stop
                $availableVersion = $response.version
            } catch {
                Write-MuseLog -Level DEBUG -Message "Impossible de vérifier $($component.Name) : $_" -Silent:$Silent
            }
        }

        # Si l'API est indisponible, simuler une comparaison de version locale
        # (utile pour les tests et les environnements hors réseau)
        if (-not $availableVersion) {
            $availableVersion = $component.Version
        }

        $hasUpdate = Compare-VersionStrings -Current $component.Version -Available $availableVersion

        if ($hasUpdate) {
            $entry = [PSCustomObject]@{
                Name             = $component.Name
                Type             = $component.Type
                CurrentVersion   = $component.Version
                AvailableVersion = $availableVersion
                Path             = $component.Path
            }
            $updates.Add($entry)
            Write-MuseLog -Level INFO -Message "  ⬆ $($component.Name) : $($component.Version) → $availableVersion" -Silent:$Silent
        } else {
            Write-MuseLog -Level DEBUG -Message "  ✔ $($component.Name) v$($component.Version) — à jour" -Silent:$Silent
        }
    }

    if (@($updates).Count -eq 0) {
        Write-MuseLog -Level INFO -Message "Tous les composants sont à jour." -Silent:$Silent
    } else {
        Write-MuseLog -Level INFO -Message "$(@($updates).Count) mise(s) à jour disponible(s)." -Silent:$Silent
    }

    return $updates
}

function Invoke-MuseHubUpdate {
    <#
    .SYNOPSIS
        Déclenche le processus de mise à jour via l'exécutable Muse Hub.
    .PARAMETER Silent
        Supprime l'affichage console.
    .PARAMETER IncludeSampleLibraries
        Inclut la mise à jour des bibliothèques d'échantillons (peut peser plusieurs Go).
    .EXAMPLE
        Invoke-MuseHubUpdate
    .EXAMPLE
        Invoke-MuseHubUpdate -IncludeSampleLibraries
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [switch] $Silent,
        [switch] $IncludeSampleLibraries
    )

    $exePath = $script:MuseHubExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $exePath) {
        Write-MuseLog -Level ERROR -Message "Exécutable Muse Hub introuvable. Impossible de lancer la mise à jour." -Silent:$Silent
        throw "Muse Hub n'est pas installé ou son chemin est non standard."
    }

    Write-MuseLog -Level INFO -Message "Exécutable Muse Hub : $exePath" -Silent:$Silent

    $args = @('--update', '--silent')
    if (-not $IncludeSampleLibraries) {
        $args += '--skip-samples'
    }

    if ($PSCmdlet.ShouldProcess($exePath, "Lancer la mise à jour Muse Hub")) {
        Write-MuseLog -Level INFO -Message "Démarrage de la mise à jour Muse Hub..." -Silent:$Silent
        $process = Start-Process -FilePath $exePath -ArgumentList $args -PassThru -Wait
        Write-MuseLog -Level INFO -Message "Mise à jour terminée (code de sortie : $($process.ExitCode))." -Silent:$Silent
        return $process.ExitCode
    }
}

#endregion

#region Fonctions privées

function Compare-VersionStrings {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [string] $Current,
        [string] $Available
    )

    try {
        $cur = [System.Version]::Parse($Current.Trim())
        $avl = [System.Version]::Parse($Available.Trim())
        return $avl -gt $cur
    } catch {
        return $false
    }
}

#endregion

Export-ModuleMember -Function @(
    'Get-MuseHubUpdates',
    'Invoke-MuseHubUpdate'
)
