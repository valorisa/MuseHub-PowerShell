#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
<#
.SYNOPSIS
    Tests unitaires Pester pour le module Report.psm1.
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

BeforeAll {
    $modulesDir = Join-Path $PSScriptRoot '..\modules'
    Import-Module (Join-Path $modulesDir 'Logger.psm1') -Force
    Initialize-MuseLogger -LogDirectory (Join-Path $PSScriptRoot '..\logs') -Level 'ERROR'
    Import-Module (Join-Path $modulesDir 'Report.psm1') -Force

    $script:TestOutputDir = Join-Path $env:TEMP 'musehub-pwsh-report-tests'
    New-Item -ItemType Directory -Path $script:TestOutputDir -Force | Out-Null

    # Inventaire fictif pour les tests
    $script:MockInventory = [PSCustomObject]@{
        Plugins      = @(
            [PSCustomObject]@{
                Name          = 'MuseStrings'
                Version       = '1.3.0'
                Path          = 'C:\Program Files\Common Files\VST3\MuseStrings.vst3'
                SizeKB        = 512.5
                InstalledDate = [datetime]'2025-01-15'
                Type          = 'VST3'
                Status        = 'Installé'
            },
            [PSCustomObject]@{
                Name          = 'MuseBrass'
                Version       = '1.1.2'
                Path          = 'C:\Program Files\Common Files\VST3\MuseBrass.vst3'
                SizeKB        = 384.0
                InstalledDate = [datetime]'2025-02-01'
                Type          = 'VST3'
                Status        = 'Installé'
            }
        )
        Applications = @(
            [PSCustomObject]@{
                Name          = 'MuseScore 4'
                Version       = '4.4.3'
                Path          = 'C:\Program Files\MuseScore 4'
                SizeKB        = 204800
                InstalledDate = [datetime]'2025-01-10'
                Type          = 'Application'
                Status        = 'Installé'
            }
        )
        GeneratedAt     = Get-Date
        TotalComponents = 3
        TotalSizeKB     = 205696.5
        DurationSeconds = 1.23
    }
}

AfterAll {
    Remove-Item -Path $script:TestOutputDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Export-MuseHubCsv" {

    Context "Génération du fichier CSV" {
        BeforeAll {
            $script:CsvPath = Join-Path $script:TestOutputDir 'test-audit.csv'
            Export-MuseHubCsv -Inventory $script:MockInventory -OutputPath $script:CsvPath -Silent
        }

        It "Crée un fichier CSV" {
            Test-Path $script:CsvPath | Should -BeTrue
        }

        It "Le fichier CSV n'est pas vide" {
            (Get-Item $script:CsvPath).Length | Should -BeGreaterThan 0
        }

        It "Le fichier CSV contient l'en-tête correct" {
            $content = Get-Content $script:CsvPath -First 1
            $content | Should -Match 'Name'
            $content | Should -Match 'Version'
            $content | Should -Match 'Type'
        }

        It "Le fichier CSV contient le bon nombre de lignes de données" {
            $imported = Import-Csv $script:CsvPath -Delimiter ';'
            # 2 plugins + 1 application = 3 entrées
            $imported.Count | Should -Be 3
        }

        It "Les données contiennent MuseStrings" {
            $imported = Import-Csv $script:CsvPath -Delimiter ';'
            $museStrings = $imported | Where-Object { $_.Name -eq 'MuseStrings' }
            $museStrings | Should -Not -BeNullOrEmpty
        }

        It "Les données contiennent MuseScore 4" {
            $imported = Import-Csv $script:CsvPath -Delimiter ';'
            $museScore = $imported | Where-Object { $_.Name -eq 'MuseScore 4' }
            $museScore | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Export-MuseHubJson" {

    Context "Génération du fichier JSON" {
        BeforeAll {
            $script:JsonPath = Join-Path $script:TestOutputDir 'test-audit.json'
            Export-MuseHubJson -Inventory $script:MockInventory -OutputPath $script:JsonPath -Silent
        }

        It "Crée un fichier JSON" {
            Test-Path $script:JsonPath | Should -BeTrue
        }

        It "Le fichier JSON est un JSON valide" {
            $content = Get-Content $script:JsonPath -Raw
            { $content | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Le JSON contient la propriété TotalComponents" {
            $parsed = Get-Content $script:JsonPath -Raw | ConvertFrom-Json
            $parsed | Get-Member -Name 'TotalComponents' | Should -Not -BeNullOrEmpty
        }

        It "TotalComponents vaut 3" {
            $parsed = Get-Content $script:JsonPath -Raw | ConvertFrom-Json
            $parsed.TotalComponents | Should -Be 3
        }
    }
}

Describe "New-MuseHubHtmlReport" {

    Context "Génération du rapport HTML" {
        BeforeAll {
            $script:HtmlPath = Join-Path $script:TestOutputDir 'test-rapport.html'
            New-MuseHubHtmlReport -Inventory $script:MockInventory -OutputPath $script:HtmlPath -Silent
        }

        It "Crée un fichier HTML" {
            Test-Path $script:HtmlPath | Should -BeTrue
        }

        It "Le fichier HTML n'est pas vide" {
            (Get-Item $script:HtmlPath).Length | Should -BeGreaterThan 1000
        }

        It "Le fichier HTML contient la déclaration DOCTYPE" {
            $content = Get-Content $script:HtmlPath -Raw
            $content | Should -Match '<!DOCTYPE html>'
        }

        It "Le fichier HTML contient le titre du rapport" {
            $content = Get-Content $script:HtmlPath -Raw
            $content | Should -Match 'Rapport Muse Hub'
        }

        It "Le fichier HTML mentionne musehub-pwsh" {
            $content = Get-Content $script:HtmlPath -Raw
            $content | Should -Match 'musehub-pwsh'
        }

        It "Le fichier HTML contient MuseStrings" {
            $content = Get-Content $script:HtmlPath -Raw
            $content | Should -Match 'MuseStrings'
        }

        It "Le fichier HTML contient le total de composants" {
            $content = Get-Content $script:HtmlPath -Raw
            $content | Should -Match '3'
        }
    }
}

Describe "Export-MuseHubReport" {

    Context "Dispatcher de formats" {
        It "Génère un fichier HTML via le dispatcher" {
            $outPath = Join-Path $script:TestOutputDir 'dispatch-test.html'
            Export-MuseHubReport -Inventory $script:MockInventory -OutputPath $outPath -Format HTML -Silent
            Test-Path $outPath | Should -BeTrue
        }

        It "Génère un fichier CSV via le dispatcher" {
            $outPath = Join-Path $script:TestOutputDir 'dispatch-test.csv'
            Export-MuseHubReport -Inventory $script:MockInventory -OutputPath $outPath -Format CSV -Silent
            Test-Path $outPath | Should -BeTrue
        }

        It "Génère un fichier JSON via le dispatcher" {
            $outPath = Join-Path $script:TestOutputDir 'dispatch-test.json'
            Export-MuseHubReport -Inventory $script:MockInventory -OutputPath $outPath -Format JSON -Silent
            Test-Path $outPath | Should -BeTrue
        }

        It "Crée le répertoire parent si inexistant" {
            $newDir  = Join-Path $script:TestOutputDir 'sous-dossier-nouveau'
            $outPath = Join-Path $newDir 'rapport.json'
            Export-MuseHubReport -Inventory $script:MockInventory -OutputPath $outPath -Format JSON -Silent
            Test-Path $outPath | Should -BeTrue
        }
    }
}
