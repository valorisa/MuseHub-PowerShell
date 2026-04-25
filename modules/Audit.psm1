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
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param ()

    Write-MuseLog -Level INFO -Message "Recherche des applications Muse Hub..."

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

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
            
            # ✅ FIX DÉFINITIF : DisplayName avec fallback ultra-sûr
            if ($app.PSObject.Properties['DisplayName'] -and $app.DisplayName) {
                $displayName = $app.DisplayName
            } elseif ($_.PSChildName) {
                $displayName = $_.PSChildName
            } else {
			    $displayName = 'Application inconnue'
			}

            $isMuseApp = $museKeywords | Where-Object { $displayName -like "*$_*" }

            if ($isMuseApp -and $displayName -ne 'Application inconnue') {
                $displayVersion = if ($app.PSObject.Properties['DisplayVersion'] -and $app.DisplayVersion) { 
                    $app.DisplayVersion 
                } else { 'N/A' }

                $installLocation = if ($app.PSObject.Properties['InstallLocation'] -and $app.InstallLocation) { 
                    $app.InstallLocation 
                } else { 'N/A' }

                $estimatedSize = if ($app.PSObject.Properties['EstimatedSize'] -and $app.EstimatedSize) { 
                    $app.EstimatedSize 
                } else { 0 }

                $installDate = if ($app.PSObject.Properties['InstallDate'] -and $app.InstallDate) {
                    try {
                        [datetime]::ParseExact($app.InstallDate, 'yyyyMMdd', $null)
                    } catch {
                        $null
                    }
                } else { $null }

                $entry = [PSCustomObject]@{
                    Name          = $displayName
                    Version       = $displayVersion
                    Path          = $installLocation
                    SizeKB        = $estimatedSize
                    InstalledDate = $installDate
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
    
    # ✅ FIX Count null-safe
    $totalSizeKB = if ($allComponents) {
        ($allComponents | Measure-Object -Property SizeKB -Sum -ErrorAction SilentlyContinue).Sum ?? 0
    } else { 0 }

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

    $dllCandidates = Get-ChildItem -Path $PluginPath -Filter '*.dll' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($dllCandidates) {
        try {
            $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dllCandidates.FullName)
            if ($info.FileVersion) { return $info.FileVersion }
        } catch {
            # Silencieux
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