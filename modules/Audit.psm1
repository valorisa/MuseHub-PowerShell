#Requires -Version 7.0
<#
.SYNOPSIS
    Module d'audit et d'inventaire des plugins Muse Hub.
.DESCRIPTION
    Scanne le système Windows pour détecter tous les composants Muse Hub
    installés : plugins VST3, applications (MuseScore, Audacity) et
    données associées (taille, version, chemin, date d'installation).
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

#Requires -Modules @{ ModuleName='Logger'; ModuleVersion='0.0.1' }

Set-StrictMode -Version Latest

#region Constantes privées

$script:DefaultVst3Paths = @(
    'C:\Program Files\Common Files\VST3',
    "$env:APPDATA\VST3",
    "$env:LOCALAPPDATA\Programs\Common\VST3"
)

$script:MuseHubAppPaths = @(
    'C:\Program Files\MuseScore 4',
    'C:\Program Files\Audacity',
    'C:\Program Files\Muse Hub'
)

$script:KnownMusePlugins = @(
    'MuseStrings', 'MuseBrass', 'MuseChoir',
    'MusePercussion', 'MuseWoodwinds', 'MuseHarp',
    'MuseKeys', 'MuseGuitars', 'MuseSamplerPlugin'
)

#endregion

#region Fonctions publiques

function Get-MuseHubPlugins {
    <#
    .SYNOPSIS
        Retourne la liste des plugins VST3 Muse Hub installés sur le système.
    .PARAMETER AdditionalScanPaths
        Chemins supplémentaires à scanner en plus des chemins VST3 par défaut.
    .OUTPUTS
        System.Collections.Generic.List[PSCustomObject]
        Chaque objet possède les propriétés : Name, Version, Path, SizeKB, InstalledDate, Type.
    .EXAMPLE
        $plugins = Get-MuseHubPlugins
        $plugins | Format-Table -AutoSize
    .EXAMPLE
        Get-MuseHubPlugins -AdditionalScanPaths 'D:\VST3'
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param (
        [string[]] $AdditionalScanPaths = @()
    )

    Write-MuseLog -Level INFO -Message "Recherche des plugins VST3 Muse Hub..."

    $scanPaths = $script:DefaultVst3Paths + $AdditionalScanPaths | Select-Object -Unique
    $results   = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($scanPath in $scanPaths) {
        if (-not (Test-Path -Path $scanPath)) {
            Write-MuseLog -Level DEBUG -Message "Chemin absent, ignoré : $scanPath"
            continue
        }

        Write-MuseLog -Level DEBUG -Message "Scan : $scanPath"

        $vst3Items = Get-ChildItem -Path $scanPath -Filter '*.vst3' -Recurse -ErrorAction SilentlyContinue

        foreach ($item in $vst3Items) {
            $isMusePlugin = $script:KnownMusePlugins | Where-Object { $item.Name -like "*$_*" }
            if (-not $isMusePlugin) { continue }

            $version = Get-PluginVersion -PluginPath $item.FullName
            $sizeKB  = [math]::Round((Get-ChildItem -Path $item.FullName -Recurse -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum / 1KB, 2)

            $entry = [PSCustomObject]@{
                Name          = $item.BaseName
                Version       = $version
                Path          = $item.FullName
                SizeKB        = $sizeKB
                InstalledDate = $item.CreationTime
                Type          = 'VST3'
                Status        = 'Installé'
            }

            $results.Add($entry)
            Write-MuseLog -Level INFO -Message "  ✔ $($entry.Name) v$($entry.Version)"
        }
    }

    Write-MuseLog -Level INFO -Message "$($results.Count) plugin(s) VST3 Muse Hub détecté(s)."
    return $results
}

function Get-MuseHubApplications {
    <#
    .SYNOPSIS
        Retourne les applications Muse Hub installées (MuseScore, Audacity, Muse Hub).
    .OUTPUTS
        System.Collections.Generic.List[PSCustomObject]
    .EXAMPLE
        Get-MuseHubApplications | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param ()

    Write-MuseLog -Level INFO -Message "Recherche des applications Muse Hub..."

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Recherche via le registre Windows (source la plus fiable)
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $museKeywords = @('MuseScore', 'Audacity', 'Muse Hub', 'MuseHub')

    foreach ($regPath in $registryPaths) {
        if (-not (Test-Path -Path $regPath)) { continue }

        Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            $app = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            $isMuseApp = $museKeywords | Where-Object { $app.DisplayName -like "*$_*" }

            if ($isMuseApp -and $app.DisplayName) {
                $entry = [PSCustomObject]@{
                    Name          = $app.DisplayName
                    Version       = if ($app.DisplayVersion) { $app.DisplayVersion } else { 'N/A' }
                    Path          = if ($app.InstallLocation) { $app.InstallLocation } else { 'N/A' }
                    SizeKB        = if ($app.EstimatedSize) { $app.EstimatedSize } else { 0 }
                    InstalledDate = if ($app.InstallDate) {
                                       [datetime]::ParseExact($app.InstallDate, 'yyyyMMdd', $null)
                                   } else { $null }
                    Type          = 'Application'
                    Status        = 'Installé'
                }
                $results.Add($entry)
                Write-MuseLog -Level INFO -Message "  ✔ $($entry.Name) v$($entry.Version)"
            }
        }
    }

    Write-MuseLog -Level INFO -Message "$($results.Count) application(s) Muse Hub détectée(s)."
    return $results
}

function Get-MuseHubInventory {
    <#
    .SYNOPSIS
        Agrège plugins et applications en un inventaire complet.
    .PARAMETER AdditionalVst3Paths
        Chemins VST3 supplémentaires transmis à Get-MuseHubPlugins.
    .OUTPUTS
        PSCustomObject avec propriétés Plugins, Applications, GeneratedAt, TotalComponents, TotalSizeKB.
    .EXAMPLE
        $inv = Get-MuseHubInventory
        $inv.Plugins | Format-Table
        Write-Host "Total : $($inv.TotalComponents) composants"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [string[]] $AdditionalVst3Paths = @()
    )

    Write-MuseLog -Level INFO -Message "=== Démarrage de l'audit Muse Hub ==="
    $startTime = Get-Date

    $plugins      = Get-MuseHubPlugins -AdditionalScanPaths $AdditionalVst3Paths
    $applications = Get-MuseHubApplications

    $allComponents = @($plugins) + @($applications)
    $totalSizeKB   = ($allComponents | Measure-Object -Property SizeKB -Sum).Sum

    $inventory = [PSCustomObject]@{
        Plugins         = $plugins
        Applications    = $applications
        GeneratedAt     = Get-Date
        TotalComponents = $allComponents.Count
        TotalSizeKB     = [math]::Round($totalSizeKB, 2)
        DurationSeconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
    }

    Write-MuseLog -Level INFO -Message "=== Audit terminé : $($inventory.TotalComponents) composant(s) en $($inventory.DurationSeconds)s ==="
    return $inventory
}

function Test-MuseHubInstallation {
    <#
    .SYNOPSIS
        Vérifie l'intégrité de l'installation Muse Hub.
    .OUTPUTS
        PSCustomObject avec IsInstalled, ExecutablePath, Version, PresetsPath, CachePath.
    .EXAMPLE
        $check = Test-MuseHubInstallation
        if ($check.IsInstalled) { Write-Host "Muse Hub $($check.Version) détecté." }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    Write-MuseLog -Level INFO -Message "Vérification de l'installation Muse Hub..."

    $execPaths = @(
        'C:\Program Files\Muse Hub\MuseHub.exe',
        "$env:LOCALAPPDATA\Programs\Muse Hub\MuseHub.exe"
    )

    $execPath = $execPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    $result = [PSCustomObject]@{
        IsInstalled    = [bool] $execPath
        ExecutablePath = $execPath
        Version        = 'N/A'
        PresetsPath    = "$env:APPDATA\Muse Hub\Presets"
        CachePath      = "$env:LOCALAPPDATA\Muse Hub\Cache"
        PresetsExist   = Test-Path "$env:APPDATA\Muse Hub\Presets"
        CacheExists    = Test-Path "$env:LOCALAPPDATA\Muse Hub\Cache"
    }

    if ($result.IsInstalled) {
        $fileInfo       = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($execPath)
        $result.Version = $fileInfo.FileVersion
        Write-MuseLog -Level INFO -Message "Muse Hub v$($result.Version) détecté à : $execPath"
    } else {
        Write-MuseLog -Level WARNING -Message "Exécutable Muse Hub introuvable aux chemins connus."
    }

    return $result
}

#endregion

#region Fonctions privées

function Get-PluginVersion {
    [CmdletBinding()]
    param ([string] $PluginPath)

    # Tenter de lire la version depuis les métadonnées du fichier
    $dllCandidates = Get-ChildItem -Path $PluginPath -Filter '*.dll' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($dllCandidates) {
        try {
            $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dllCandidates.FullName)
            if ($info.FileVersion) { return $info.FileVersion }
        } catch {
            # Silencieux, on retourne une valeur par défaut
        }
    }

    return '1.0.0'
}

#endregion

Export-ModuleMember -Function @(
    'Get-MuseHubPlugins',
    'Get-MuseHubApplications',
    'Get-MuseHubInventory',
    'Test-MuseHubInstallation'
)
