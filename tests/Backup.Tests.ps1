#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
<#
.SYNOPSIS
    Tests unitaires Pester pour le module Backup.psm1.
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

BeforeAll {
    $modulesDir = Join-Path $PSScriptRoot '..\modules'
    Import-Module (Join-Path $modulesDir 'Logger.psm1') -Force
    Initialize-MuseLogger -LogDirectory (Join-Path $PSScriptRoot '..\logs') -Level 'ERROR'
    Import-Module (Join-Path $modulesDir 'Backup.psm1') -Force

    # Répertoire de test temporaire
    $script:TestRoot      = Join-Path $env:TEMP 'musehub-pwsh-backup-tests'
    $script:TestBackupDir = Join-Path $script:TestRoot 'backups'
    $script:TestSourceDir = Join-Path $script:TestRoot 'fake-presets'

    New-Item -ItemType Directory -Path $script:TestBackupDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestSourceDir -Force | Out-Null

    # Créer des fichiers de presets fictifs
    1..5 | ForEach-Object {
        Set-Content -Path (Join-Path $script:TestSourceDir "preset_$_.mhp") -Value "Preset content $_"
    }
}

AfterAll {
    Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Get-MuseHubBackups" {

    Context "Répertoire vide" {
        It "Retourne un tableau vide si aucune sauvegarde n'existe" {
            $emptyDir = Join-Path $script:TestRoot 'empty-backups'
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            $result = Get-MuseHubBackups -Destination $emptyDir
            $result.Count | Should -Be 0
        }
    }

    Context "Répertoire inexistant" {
        It "Ne lève pas d'exception si le répertoire n'existe pas" {
            { Get-MuseHubBackups -Destination 'C:\CheminInexistant\backups' } |
                Should -Not -Throw
        }

        It "Retourne un tableau vide si le répertoire n'existe pas" {
            $result = Get-MuseHubBackups -Destination 'C:\CheminInexistant\backups'
            @($result).Count | Should -Be 0
        }
    }

    Context "Avec des sauvegardes présentes" {
        BeforeAll {
            # Créer des archives ZIP fictives avec le bon nommage
            $datesTest = @('2025-01-10_10-00-00', '2025-02-15_11-30-00', '2025-03-20_09-15-00')
            foreach ($d in $datesTest) {
                $fakeZip = Join-Path $script:TestBackupDir "musehub-backup_$d.zip"
                # Créer un fichier temporaire et le compresser
                $tmpFile = Join-Path $env:TEMP "test_$d.txt"
                Set-Content -Path $tmpFile -Value "test"
                Compress-Archive -Path $tmpFile -DestinationPath $fakeZip -Force
                Remove-Item $tmpFile -Force
            }
        }

        It "Retourne les sauvegardes triées par date décroissante" {
            $result = Get-MuseHubBackups -Destination $script:TestBackupDir
            $result.Count | Should -BeGreaterOrEqual 3
            # La plus récente doit être première
            $result[0].LastWriteTime | Should -BeGreaterOrEqual $result[-1].LastWriteTime
        }

        It "Retourne uniquement les fichiers au format musehub-backup_*.zip" {
            # Créer un fichier parasite
            Set-Content -Path (Join-Path $script:TestBackupDir 'other-file.zip') -Value 'x'
            $result = Get-MuseHubBackups -Destination $script:TestBackupDir
            $result | ForEach-Object {
                $_.Name | Should -Match '^musehub-backup_'
            }
        }
    }
}

Describe "Remove-OldBackups" {

    Context "Rotation des sauvegardes" {
        BeforeAll {
            $script:RotationDir = Join-Path $script:TestRoot 'rotation-backups'
            New-Item -ItemType Directory -Path $script:RotationDir -Force | Out-Null

            # Créer 8 archives fictives
            1..8 | ForEach-Object {
                $date    = (Get-Date).AddDays(-$_).ToString('yyyy-MM-dd_HH-mm-ss')
                $zipPath = Join-Path $script:RotationDir "musehub-backup_$date.zip"
                $tmpFile = Join-Path $env:TEMP "rot_test_$_.txt"
                Set-Content -Path $tmpFile -Value "content $_"
                Compress-Archive -Path $tmpFile -DestinationPath $zipPath -Force
                Remove-Item $tmpFile -Force
            }
        }

        It "Conserve exactement MaxBackups sauvegardes" {
            Remove-OldBackups -Destination $script:RotationDir -MaxBackups 5 -Silent
            $remaining = Get-ChildItem -Path $script:RotationDir -Filter 'musehub-backup_*.zip'
            $remaining.Count | Should -Be 5
        }

        It "Ne supprime rien si le nombre de sauvegardes est inférieur au quota" {
            $smallDir = Join-Path $script:TestRoot 'small-backups'
            New-Item -ItemType Directory -Path $smallDir -Force | Out-Null
            $tmpFile = Join-Path $env:TEMP 'small_test.txt'
            Set-Content -Path $tmpFile -Value 'x'
            Compress-Archive -Path $tmpFile -DestinationPath (Join-Path $smallDir 'musehub-backup_2025-01-01_00-00-00.zip') -Force
            Remove-Item $tmpFile -Force

            Remove-OldBackups -Destination $smallDir -MaxBackups 10 -Silent
            $remaining = Get-ChildItem -Path $smallDir -Filter 'musehub-backup_*.zip'
            $remaining.Count | Should -Be 1
        }
    }
}

Describe "Invoke-MuseHubBackup" {

    Context "Paramètres et création d'archive" {
        It "Ne lève pas d'exception avec un répertoire de destination valide" {
            {
                # La fonction peut ne rien trouver si Muse Hub n'est pas installé — acceptable
                Invoke-MuseHubBackup -Destination $script:TestBackupDir -MaxBackups 5 -Silent -WhatIf
            } | Should -Not -Throw
        }
    }
}

Describe "Restore-MuseHubBackup" {

    Context "Paramètre BackupPath invalide" {
        It "Lève une erreur si BackupPath n'existe pas" {
            {
                Restore-MuseHubBackup -BackupPath 'C:\FichierInexistant.zip' -WhatIf
            } | Should -Throw
        }
    }
}
