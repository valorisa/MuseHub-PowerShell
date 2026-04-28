#Requires -Version 7.0
<#
.SYNOPSIS
    Module de génération de rapports pour musehub-pwsh.
.DESCRIPTION
    Génère des rapports d'inventaire Muse Hub aux formats HTML interactif,
    CSV et JSON. Le rapport HTML intègre un tableau de bord, des graphiques
    et un tableau triable de tous les composants détectés.
.NOTES
    Auteur  : valorisa
    Projet  : musehub-pwsh
    Licence : MIT
#>

Set-StrictMode -Version Latest

#region Fonctions publiques

function Export-MuseHubReport {
    <#
    .SYNOPSIS
        Génère un rapport dans le format spécifié à partir d'un inventaire.
    .PARAMETER Inventory
        Objet inventaire retourné par Get-MuseHubInventory.
    .PARAMETER OutputPath
        Chemin complet du fichier de sortie (extension détermine le format si Format n'est pas fourni).
    .PARAMETER Format
        Format de sortie : HTML, CSV ou JSON.
    .PARAMETER OpenAfterGeneration
        Ouvre le rapport dans le navigateur/application par défaut après génération.
    .PARAMETER Silent
        Supprime l'affichage console.
    .EXAMPLE
        $inv = Get-MuseHubInventory
        Export-MuseHubReport -Inventory $inv -OutputPath ".\logs\rapport.html" -Format HTML
    .EXAMPLE
        Export-MuseHubReport -Inventory $inv -OutputPath ".\logs\audit.csv" -Format CSV
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject] $Inventory,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [ValidateSet('HTML', 'CSV', 'JSON')]
        [string] $Format = 'HTML',

        [switch] $OpenAfterGeneration,

        [switch] $Silent
    )

    # Créer le répertoire parent si nécessaire
    $parentDir = Split-Path $OutputPath -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    Write-MuseLog -Level INFO -Message "Génération du rapport $Format → $OutputPath" -Silent:$Silent

    switch ($Format) {
        'HTML' { New-MuseHubHtmlReport -Inventory $Inventory -OutputPath $OutputPath -Silent:$Silent }
        'CSV'  { Export-MuseHubCsv    -Inventory $Inventory -OutputPath $OutputPath -Silent:$Silent }
        'JSON' { Export-MuseHubJson   -Inventory $Inventory -OutputPath $OutputPath -Silent:$Silent }
    }

    if ($OpenAfterGeneration -and (Test-Path $OutputPath)) {
        Start-Process $OutputPath
    }
}

function New-MuseHubHtmlReport {
    <#
    .SYNOPSIS
        Crée un rapport HTML interactif et auto-contenu.
    .PARAMETER Inventory
        Objet inventaire retourné par Get-MuseHubInventory.
    .PARAMETER OutputPath
        Chemin du fichier HTML à générer.
    .PARAMETER Silent
        Supprime l'affichage console.
    .EXAMPLE
        New-MuseHubHtmlReport -Inventory $inv -OutputPath ".\logs\rapport.html"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject] $Inventory,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [switch] $Silent
    )

    $allComponents = @($Inventory.Plugins) + @($Inventory.Applications)
    $genDate       = $Inventory.GeneratedAt.ToString('dd/MM/yyyy HH:mm:ss')
    $totalSizeMB   = [math]::Round($Inventory.TotalSizeKB / 1024, 2)

    # Construction des lignes du tableau
    $tableRows = ($allComponents | ForEach-Object {
        $date = if ($_.InstalledDate) { $_.InstalledDate.ToString('dd/MM/yyyy') } else { 'N/A' }
        $size = if ($_.SizeKB -gt 1024) { "$([math]::Round($_.SizeKB/1024,2)) Mo" } else { "$($_.SizeKB) Ko" }
        "<tr>
          <td>$($_.Name)</td>
          <td><span class='badge badge-$($_.Type.ToLower())'>$($_.Type)</span></td>
          <td>$($_.Version)</td>
          <td class='path' title='$($_.Path)'>$($_.Path)</td>
          <td>$size</td>
          <td>$date</td>
          <td><span class='status-ok'>✔ $($_.Status)</span></td>
        </tr>"
    }) -join "`n"

    # Données pour le graphique en secteurs (Types)
    $typeGroups = $allComponents | Group-Object Type
    $chartLabels = ($typeGroups | ForEach-Object { "'$($_.Name)'" }) -join ','
    $chartData   = ($typeGroups | ForEach-Object { $_.Count }) -join ','
    $chartColors = "'#4f8ef7','#f7a94f','#4ff7a9','#f74f4f'" # VST3, App, etc.

    $html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Rapport Muse Hub — musehub-pwsh</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    :root {
      --bg: #0f1117; --surface: #1a1d27; --border: #2a2d3a;
      --text: #e0e0e0; --muted: #888; --accent: #4f8ef7;
      --green: #4ff7a9; --yellow: #f7a94f; --red: #f74f4f;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', sans-serif; padding: 2rem; }
    h1 { font-size: 1.8rem; color: var(--accent); margin-bottom: .25rem; }
    .subtitle { color: var(--muted); font-size: .9rem; margin-bottom: 2rem; }
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px,1fr)); gap: 1rem; margin-bottom: 2rem; }
    .card { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 1.25rem; text-align: center; }
    .card .value { font-size: 2rem; font-weight: 700; color: var(--accent); }
    .card .label { font-size: .8rem; color: var(--muted); margin-top: .25rem; }
    .grid2 { display: grid; grid-template-columns: 2fr 1fr; gap: 1.5rem; margin-bottom: 2rem; }
    .panel { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 1.5rem; }
    .panel h2 { font-size: 1rem; color: var(--accent); margin-bottom: 1rem; border-bottom: 1px solid var(--border); padding-bottom: .5rem; }
    table { width: 100%; border-collapse: collapse; font-size: .85rem; }
    th { background: var(--border); padding: .6rem .8rem; text-align: left; cursor: pointer; user-select: none; }
    th:hover { color: var(--accent); }
    td { padding: .55rem .8rem; border-bottom: 1px solid var(--border); vertical-align: middle; }
    td.path { max-width: 250px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--muted); font-size: .78rem; }
    tr:hover td { background: rgba(79,142,247,.06); }
    .badge { padding: .2rem .55rem; border-radius: 4px; font-size: .75rem; font-weight: 600; }
    .badge-vst3 { background: rgba(79,142,247,.2); color: var(--accent); }
    .badge-application { background: rgba(79,247,169,.2); color: var(--green); }
    .status-ok { color: var(--green); }
    input#search { width: 100%; padding: .6rem 1rem; background: var(--surface); border: 1px solid var(--border);
      border-radius: 6px; color: var(--text); font-size: .9rem; margin-bottom: 1rem; }
    input#search:focus { outline: 2px solid var(--accent); }
    footer { margin-top: 2rem; color: var(--muted); font-size: .78rem; text-align: center; }
    canvas { max-height: 240px; }
    @media (max-width: 768px) { .grid2 { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <h1>🎵 Rapport Muse Hub</h1>
  <p class="subtitle">Généré le $genDate par <strong>musehub-pwsh v1.0.0</strong> — github.com/valorisa/musehub-pwsh</p>

  <div class="cards">
    <div class="card"><div class="value">$($Inventory.TotalComponents)</div><div class="label">Composants totaux</div></div>
    <div class="card"><div class="value">$(@($Inventory.Plugins).Count)</div><div class="label">Plugins VST3</div></div>
    <div class="card"><div class="value">$(@($Inventory.Applications).Count)</div><div class="label">Applications</div></div>
    <div class="card"><div class="value">${totalSizeMB} Mo</div><div class="label">Espace total estimé</div></div>
    <div class="card"><div class="value">$($Inventory.DurationSeconds)s</div><div class="label">Durée du scan</div></div>
  </div>

  <div class="grid2">
    <div class="panel">
      <h2>📦 Inventaire des composants</h2>
      <input type="text" id="search" placeholder="Filtrer par nom, type, version…" oninput="filterTable()">
      <table id="inventoryTable">
        <thead>
          <tr>
            <th onclick="sortTable(0)">Nom ⇅</th>
            <th onclick="sortTable(1)">Type ⇅</th>
            <th onclick="sortTable(2)">Version ⇅</th>
            <th>Chemin</th>
            <th onclick="sortTable(4)">Taille ⇅</th>
            <th onclick="sortTable(5)">Installé ⇅</th>
            <th>Statut</th>
          </tr>
        </thead>
        <tbody>
          $tableRows
        </tbody>
      </table>
    </div>
    <div class="panel">
      <h2>📊 Répartition par type</h2>
      <canvas id="typeChart"></canvas>
    </div>
  </div>

  <footer>musehub-pwsh • MIT License • github.com/valorisa/musehub-pwsh</footer>

  <script>
    // Graphique en secteurs
    new Chart(document.getElementById('typeChart'), {
      type: 'doughnut',
      data: {
        labels: [$chartLabels],
        datasets: [{ data: [$chartData], backgroundColor: [$chartColors], borderWidth: 0 }]
      },
      options: { plugins: { legend: { labels: { color: '#e0e0e0' } } } }
    });

    // Filtre de tableau
    function filterTable() {
      const q = document.getElementById('search').value.toLowerCase();
      document.querySelectorAll('#inventoryTable tbody tr').forEach(row => {
        row.style.display = row.textContent.toLowerCase().includes(q) ? '' : 'none';
      });
    }

    // Tri de tableau
    function sortTable(col) {
      const table = document.getElementById('inventoryTable');
      const rows = Array.from(table.querySelectorAll('tbody tr'));
      const asc = table.dataset.sortCol == col && table.dataset.sortDir === 'asc';
      rows.sort((a,b) => {
        const va = a.cells[col].textContent.trim();
        const vb = b.cells[col].textContent.trim();
        return asc ? vb.localeCompare(va) : va.localeCompare(vb);
      });
      rows.forEach(r => table.querySelector('tbody').appendChild(r));
      table.dataset.sortCol = col;
      table.dataset.sortDir = asc ? 'desc' : 'asc';
    }
  </script>
</body>
</html>
"@

    $html | Set-Content -Path $OutputPath -Encoding UTF8
    Write-MuseLog -Level INFO -Message "Rapport HTML généré : $OutputPath" -Silent:$Silent
}

function Export-MuseHubCsv {
    <#
    .SYNOPSIS
        Exporte l'inventaire Muse Hub au format CSV.
    .PARAMETER Inventory
        Objet inventaire retourné par Get-MuseHubInventory.
    .PARAMETER OutputPath
        Chemin du fichier CSV à générer.
    .PARAMETER Silent
        Supprime l'affichage console.
    .EXAMPLE
        Export-MuseHubCsv -Inventory $inv -OutputPath ".\logs\audit.csv"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [PSCustomObject] $Inventory,
        [Parameter(Mandatory)] [string] $OutputPath,
        [switch] $Silent
    )

    $allComponents = @($Inventory.Plugins) + @($Inventory.Applications)
    $allComponents | Select-Object Name, Type, Version, Path, SizeKB, InstalledDate, Status |
        Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'

    Write-MuseLog -Level INFO -Message "Export CSV généré : $OutputPath ($($allComponents.Count) entrées)" -Silent:$Silent
}

function Export-MuseHubJson {
    <#
    .SYNOPSIS
        Exporte l'inventaire Muse Hub au format JSON formaté.
    .PARAMETER Inventory
        Objet inventaire retourné par Get-MuseHubInventory.
    .PARAMETER OutputPath
        Chemin du fichier JSON à générer.
    .PARAMETER Silent
        Supprime l'affichage console.
    .EXAMPLE
        Export-MuseHubJson -Inventory $inv -OutputPath ".\logs\audit.json"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [PSCustomObject] $Inventory,
        [Parameter(Mandatory)] [string] $OutputPath,
        [switch] $Silent
    )

    $Inventory | ConvertTo-Json -Depth 10 |
        Set-Content -Path $OutputPath -Encoding UTF8

    Write-MuseLog -Level INFO -Message "Export JSON généré : $OutputPath" -Silent:$Silent
}

#endregion

Export-ModuleMember -Function @(
    'Export-MuseHubReport',
    'New-MuseHubHtmlReport',
    'Export-MuseHubCsv',
    'Export-MuseHubJson'
)
