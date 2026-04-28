#Requires -Version 7.0
<#
.SYNOPSIS
    Module de journalisation centralisé pour musehub-pwsh.
.DESCRIPTION
    Fournit des fonctions de logging horodatées avec rotation automatique
    des fichiers de log. Tous les modules du projet utilisent ce module.
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

Set-StrictMode -Version Latest

#region Variables privées du module

$script:LogLevels = @{
    DEBUG   = 0
    INFO    = 1
    WARNING = 2
    ERROR   = 3
}

$script:CurrentLogPath = $null
$script:ConfiguredLevel = 'INFO'
$script:MaxLogFiles = 30

#endregion

#region Fonctions publiques

function Initialize-MuseLogger {
    <#
    .SYNOPSIS
        Initialise le système de logging pour la session courante.
    .PARAMETER LogDirectory
        Répertoire où seront créés les fichiers de log.
    .PARAMETER Level
        Niveau de verbosité : DEBUG, INFO, WARNING, ERROR.
    .PARAMETER MaxLogFiles
        Nombre maximal de fichiers de log conservés.
    .EXAMPLE
        Initialize-MuseLogger -LogDirectory "C:\Projets\musehub-pwsh\logs" -Level INFO
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $LogDirectory,

        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR')]
        [string] $Level = 'INFO',

        [int] $MaxLogFiles = 30
    )

    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $script:CurrentLogPath   = Join-Path $LogDirectory "musehub-pwsh_$timestamp.log"
    $script:ConfiguredLevel  = $Level
    $script:MaxLogFiles      = $MaxLogFiles

    Write-MuseLog -Level INFO -Message "=== Session démarrée — musehub-pwsh ==="
    Write-MuseLog -Level INFO -Message "PowerShell $($PSVersionTable.PSVersion) | $([System.Environment]::OSVersion.VersionString)"
    Write-MuseLog -Level INFO -Message "Niveau de log : $Level"
}

function Write-MuseLog {
    <#
    .SYNOPSIS
        Écrit un message horodaté dans le fichier de log et la console.
    .PARAMETER Level
        Niveau du message : DEBUG, INFO, WARNING, ERROR.
    .PARAMETER Message
        Texte du message à journaliser.
    .PARAMETER Silent
        Si présent, supprime l'affichage console (log fichier uniquement).
    .EXAMPLE
        Write-MuseLog -Level INFO -Message "Audit démarré"
        Write-MuseLog -Level ERROR -Message "Fichier introuvable" -Silent
    #>
    [CmdletBinding()]
    param (
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR')]
        [string] $Level = 'INFO',

        [Parameter(Mandatory)]
        [string] $Message,

        [switch] $Silent
    )

    # Filtre selon le niveau configuré
    if ($script:LogLevels[$Level] -lt $script:LogLevels[$script:ConfiguredLevel]) {
        return
    }

    $timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine    = "[$timestamp] [$Level] $Message"

    # Écriture fichier
    if ($script:CurrentLogPath) {
        Add-Content -Path $script:CurrentLogPath -Value $logLine -Encoding UTF8
    }

    # Affichage console
    if (-not $Silent) {
        $color = switch ($Level) {
            'DEBUG'   { 'Gray' }
            'INFO'    { 'Cyan' }
            'WARNING' { 'Yellow' }
            'ERROR'   { 'Red' }
        }
        $prefix = switch ($Level) {
            'DEBUG'   { '[DEBUG]  ' }
            'INFO'    { '[INFO]   ' }
            'WARNING' { '[WARN]   ' }
            'ERROR'   { '[ERROR]  ' }
        }
        Write-Host "$prefix$Message" -ForegroundColor $color
    }
}

function Get-MuseLogPath {
    <#
    .SYNOPSIS
        Retourne le chemin du fichier de log de la session courante.
    .EXAMPLE
        $path = Get-MuseLogPath
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    return $script:CurrentLogPath
}

function Invoke-LogRotation {
    <#
    .SYNOPSIS
        Supprime les fichiers de log les plus anciens au-delà du quota configuré.
    .PARAMETER LogDirectory
        Répertoire contenant les fichiers de log à évaluer.
    .EXAMPLE
        Invoke-LogRotation -LogDirectory ".\logs"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $LogDirectory
    )

    if (-not (Test-Path -Path $LogDirectory)) { return }

    $logFiles = @(Get-ChildItem -Path $LogDirectory -Filter 'musehub-pwsh_*.log' |
        Sort-Object LastWriteTime -Descending)

    if ($logFiles.Count -gt $script:MaxLogFiles) {
        $toDelete = @($logFiles | Select-Object -Skip $script:MaxLogFiles)
        foreach ($file in $toDelete) {
            Remove-Item -Path $file.FullName -Force
            Write-MuseLog -Level DEBUG -Message "Log archivé supprimé : $($file.Name)"
        }
        Write-MuseLog -Level INFO -Message "$($toDelete.Count) fichier(s) de log supprimé(s) par rotation."
    }
}

#endregion

Export-ModuleMember -Function @(
    'Initialize-MuseLogger',
    'Write-MuseLog',
    'Get-MuseLogPath',
    'Invoke-LogRotation'
)
