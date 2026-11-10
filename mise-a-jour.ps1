# mise-a-jour.ps1 : appele par le menu quand le joueur accepte la mise a jour (popup du menu).
# Telecharge le depot GitHub ecrit dans depot.txt (proprietaire/nom), garde une copie de l'ancienne version
# dans "ancienne-version", installe. Les reglages, l'historique et les diagnostics ne sont jamais touches.
# Code de sortie : 0 = installe, 1 = echec (le message est ecrit sur la sortie).
param([string]$Dossier, [switch]$Installer)
if (-not $Installer) { return }   # une ancienne version de Ferme-canne.ps1 peut encore l'appeler sans -Installer : le menu s'en charge

# Fichiers et dossiers propres a chaque joueur : jamais remplaces ni supprimes (seulement crees s'ils manquent).
$proteges = @('Ferme-canne.ini', 'historique.csv', 'lectures.log', 'depot.txt', 'departs-etages.txt', 'diagnostics', 'ancienne-version', '.git')

try {
  $depot = (Get-Content (Join-Path $Dossier 'depot.txt') -TotalCount 1).Trim()
  if ($depot -notmatch '^[\w.-]+/[\w.-]+$') { throw 'depot.txt invalide' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("macros-maj-" + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $zip = Join-Path $tmp 'maj.zip'
  (New-Object Net.WebClient).DownloadFile("https://github.com/$depot/archive/refs/heads/main.zip", $zip)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, (Join-Path $tmp 'x'))
  $source = Get-ChildItem (Join-Path $tmp 'x') -Directory | Select-Object -First 1
  if (-not $source -or -not (Test-Path (Join-Path $source.FullName 'version.txt'))) { throw 'archive incomplete' }

  $sauvegarde = Join-Path $Dossier 'ancienne-version'
  if (Test-Path $sauvegarde) { Remove-Item $sauvegarde -Recurse -Force }
  New-Item -ItemType Directory -Force $sauvegarde | Out-Null

  foreach ($f in Get-ChildItem $source.FullName -Recurse -File) {
    $rel = $f.FullName.Substring($source.FullName.Length + 1)
    $cible = Join-Path $Dossier $rel
    if (($proteges -contains $rel.Split([char]92)[0]) -and (Test-Path $cible)) { continue }
    if (Test-Path $cible) {
      $copie = Join-Path $sauvegarde $rel
      New-Item -ItemType Directory -Force (Split-Path $copie) | Out-Null
      Copy-Item $cible $copie -Force
    }
    New-Item -ItemType Directory -Force (Split-Path $cible) | Out-Null
    Copy-Item $f.FullName $cible -Force
  }
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  exit 0
} catch {
  Write-Output $_.Exception.Message
  exit 1
}
