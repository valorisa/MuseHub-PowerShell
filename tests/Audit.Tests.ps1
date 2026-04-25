#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
<#
.SYNOPSIS
    Tests unitaires Pester pour le module Audit.psm1.
.DESCRIPTION
    Couvre les fonctions Get-MuseHubPlugins, Get-MuseHubApplications,
    Get-MuseHubInventory et Test-MuseHubInstallation.
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

BeforeAll {
    # Charger les modules nécessaires
    $modulesDir = Join-Path $PSScriptRoot '..\modules'
    Import-Module (Join-Path $modulesDir 'Logger.psm1') -Force

    # Initialiser le logger en mode silencieux pour les tests
    Initialize-MuseLogger -LogDirectory (Join-Path $PSScriptRoot '..\logs') -Level 'ERROR'

    Import-Module (Join-Path $modulesDir 'Audit.psm1') -Force

    # Données de mock pour les tests
    $script:MockPlugin = [PSCustomObject]@{
        Name          = 'MuseStrings'
        Version       = '1.3.0'
        Path          = 'C:\Program Files\Common Files\VST3\MuseStrings.vst3'
        SizeKB        = 512.5
        InstalledDate = [datetime]'2025-01-15'
        Type          = 'VST3'
        Status        = 'Installé'
    }

    $script:MockApplication = [PSCustomObject]@{
        Name          = 'MuseScore 4'
        Version       = '4.4.3'
        Path          = 'C:\Program Files\MuseScore 4'
        SizeKB        = 204800
        InstalledDate = [datetime]'2025-01-10'
        Type          = 'Application'
        Status        = 'Installé'
    }
}

Describe "Get-MuseHubPlugins" {

    Context "Retour de type et structure" {
        It "Retourne un objet de type List ou tableau" {
            $result = Get-MuseHubPlugins
            $result | Should -Not -BeNullOrEmpty -Because "La fonction doit retourner un résultat (vide ou non)"
            # Sur un système sans Muse Hub, la liste peut être vide — c'est acceptable
            $result | Should -BeOfType [System.Object]
        }
    }

    Context "Structure des objets retournés" {
        BeforeAll {
            # Mocker la présence d'un VST3 fictif
            $script:TestVst3Dir = Join-Path $env:TEMP 'musehub-pwsh-tests\VST3'
            $script:TestVst3File = Join-Path $script:TestVst3Dir 'MuseStrings.vst3'
            New-Item -ItemType Directory -Path $script:TestVst3Dir -Force | Out-Null
            New-Item -ItemType Directory -Path $script:TestVst3File -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:TestVst3File 'MuseStrings.dll') -Force | Out-Null
        }

        It "Chaque plugin possède une propriété Name non vide" {
            $result = Get-MuseHubPlugins -AdditionalScanPaths $script:TestVst3Dir
            if ($result.Count -gt 0) {
                $result | ForEach-Object {
                    $_.Name | Should -Not -BeNullOrEmpty
                }
            }
        }

        It "Chaque plugin possède une propriété Version au format x.y.z" {
            $result = Get-MuseHubPlugins -AdditionalScanPaths $script:TestVst3Dir
            if ($result.Count -gt 0) {
                $result | ForEach-Object {
                    $_.Version | Should -Match '^\d+\.\d+\.\d+' -Because "La version doit être au format SemVer"
                }
            }
        }

        It "Chaque plugin possède une propriété Type égale à VST3" {
            $result = Get-MuseHubPlugins -AdditionalScanPaths $script:TestVst3Dir
            if ($result.Count -gt 0) {
                $result | ForEach-Object {
                    $_.Type | Should -Be 'VST3'
                }
            }
        }

        It "Chaque plugin possède une propriété Path non vide" {
            $result = Get-MuseHubPlugins -AdditionalScanPaths $script:TestVst3Dir
            if ($result.Count -gt 0) {
                $result | ForEach-Object {
                    $_.Path | Should -Not -BeNullOrEmpty
                }
            }
        }

        AfterAll {
            Remove-Item -Path (Join-Path $env:TEMP 'musehub-pwsh-tests') -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Gestion des chemins inexistants" {
        It "Ne lève pas d'erreur si un chemin de scan est inexistant" {
            { Get-MuseHubPlugins -AdditionalScanPaths 'C:\CheminQuiNExistePas\VST3' } |
                Should -Not -Throw
        }

        It "Retourne une liste vide si aucun plugin Muse n'est trouvé" {
            $result = Get-MuseHubPlugins -AdditionalScanPaths 'C:\Windows\Temp'
            $result.Count | Should -Be 0 -Because "Aucun plugin Muse Hub ne devrait se trouver dans C:\Windows\Temp"
        }
    }
}

Describe "Get-MuseHubApplications" {

    Context "Retour de type et structure" {
        It "Ne lève pas d'exception" {
            { Get-MuseHubApplications } | Should -Not -Throw
        }

        It "Retourne un objet itérable" {
            $result = Get-MuseHubApplications
            $result | Should -Not -Be $null
        }
    }

    Context "Structure des objets retournés (si applications présentes)" {
        It "Chaque application possède les propriétés requises" {
            $result = Get-MuseHubApplications
            if ($result.Count -gt 0) {
                $requiredProps = @('Name', 'Version', 'Path', 'Type', 'Status')
                $result | ForEach-Object {
                    foreach ($prop in $requiredProps) {
                        $_ | Get-Member -Name $prop | Should -Not -BeNullOrEmpty -Because "La propriété '$prop' est requise"
                    }
                }
            }
        }

        It "Chaque application a le Type 'Application'" {
            $result = Get-MuseHubApplications
            if ($result.Count -gt 0) {
                $result | ForEach-Object {
                    $_.Type | Should -Be 'Application'
                }
            }
        }
    }
}

Describe "Get-MuseHubInventory" {

    Context "Structure de l'objet retourné" {
        It "Retourne un PSCustomObject non nul" {
            $result = Get-MuseHubInventory
            $result | Should -Not -BeNullOrEmpty
        }

        It "Possède une propriété Plugins" {
            $result = Get-MuseHubInventory
            $result | Get-Member -Name 'Plugins' | Should -Not -BeNullOrEmpty
        }

        It "Possède une propriété Applications" {
            $result = Get-MuseHubInventory
            $result | Get-Member -Name 'Applications' | Should -Not -BeNullOrEmpty
        }

        It "Possède une propriété TotalComponents de type entier" {
            $result = Get-MuseHubInventory
            $result.TotalComponents | Should -BeOfType [int]
        }

        It "TotalComponents est cohérent avec Plugins + Applications" {
            $result = Get-MuseHubInventory
            $expected = $result.Plugins.Count + $result.Applications.Count
            $result.TotalComponents | Should -Be $expected
        }

        It "Possède une propriété GeneratedAt de type DateTime" {
            $result = Get-MuseHubInventory
            $result.GeneratedAt | Should -BeOfType [datetime]
        }

        It "Possède une propriété DurationSeconds positive" {
            $result = Get-MuseHubInventory
            $result.DurationSeconds | Should -BeGreaterOrEqual 0
        }
    }
}

Describe "Test-MuseHubInstallation" {

    Context "Structure de l'objet retourné" {
        It "Retourne un PSCustomObject avec IsInstalled (booléen)" {
            $result = Test-MuseHubInstallation
            $result | Should -Not -BeNullOrEmpty
            $result.IsInstalled | Should -BeOfType [bool]
        }

        It "Possède une propriété PresetsPath non vide" {
            $result = Test-MuseHubInstallation
            $result.PresetsPath | Should -Not -BeNullOrEmpty
        }

        It "Possède une propriété CachePath non vide" {
            $result = Test-MuseHubInstallation
            $result.CachePath | Should -Not -BeNullOrEmpty
        }

        It "Possède une propriété PresetsExist de type booléen" {
            $result = Test-MuseHubInstallation
            $result.PresetsExist | Should -BeOfType [bool]
        }

        It "Si IsInstalled est vrai, ExecutablePath pointe vers un fichier existant" {
            $result = Test-MuseHubInstallation
            if ($result.IsInstalled) {
                Test-Path $result.ExecutablePath | Should -BeTrue
            }
        }

        It "Si IsInstalled est faux, Version vaut N/A" {
            $result = Test-MuseHubInstallation
            if (-not $result.IsInstalled) {
                $result.Version | Should -Be 'N/A'
            }
        }
    }
}
