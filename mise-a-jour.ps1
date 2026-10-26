# mise-a-jour.ps1 : appele par Ferme-canne.ps1 avant d'ouvrir le menu.
# Compare version.txt a celui du depot GitHub ecrit dans depot.txt (proprietaire/nom).
# Si le depot a une version plus recente : demande, garde une copie de l'ancienne version
# dans "ancienne-version", installe. Les reglages, l'historique et les diagnostics ne sont jamais touches.
# Pas de depot, pas d'Internet, GitHub en panne : le menu s'ouvre normalement, sans rien dire.
param([string]$Dossier)

$depotFichier = Join-Path $Dossier 'depot.txt'
if (-not (Test-Path $depotFichier)) { return }
$depot = (Get-Content $depotFichier -TotalCount 1).Trim()
if ($depot -notmatch '^[\w.-]+/[\w.-]+$') { return }

function Numero-Version($texte) { if ($texte -match '^\s*(\d+)') { return [int]$Matches[1] } return 0 }

# Fichiers et dossiers propres a chaque joueur : jamais remplaces ni supprimes (seulement crees s'ils manquent).
$proteges = @('Ferme-canne.ini', 'historique.csv', 'lectures.log', 'depot.txt', 'departs-etages.txt', 'diagnostics', 'ancienne-version', '.git')

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $local = 0
  $versionLocale = Join-Path $Dossier 'version.txt'
  if (Test-Path $versionLocale) { $local = Numero-Version (Get-Content $versionLocale -Raw) }

  $req = [Net.WebRequest]::Create("https://raw.githubusercontent.com/$depot/main/version.txt?t=$([Environment]::TickCount)")
  $req.Timeout = 4000
  $rep = $req.GetResponse()
  $texte = (New-Object IO.StreamReader $rep.GetResponseStream()).ReadToEnd(); $rep.Close()
  $distante = Numero-Version $texte
  if ($distante -le $local) { return }

  # version.txt : premiere ligne = numero, lignes suivantes = nouveautes
  $notes = (($texte -split "`r?`n") | Select-Object -Skip 1 | Where-Object { $_.Trim() }) -join "`n"
  $msg = "Nouvelle version disponible (version $distante, tu as la version $local).`n`n"
  if ($notes) { $msg += "Nouveautes :`n$notes`n`n" }
  $msg += "L'installer maintenant ?`n(Tes reglages et tes statistiques sont conserves, l'ancienne version est gardee dans le dossier `"ancienne-version`".)"
  $choix = [System.Windows.Forms.MessageBox]::Show($msg, 'Macros Minecraft : mise a jour', 'YesNo', 'Question')
  if ($choix -ne 'Yes') { return }

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
    if (($proteges -contains ($rel -split '\\')[0]) -and (Test-Path $cible)) { continue }
    if (Test-Path $cible) {
      $copie = Join-Path $sauvegarde $rel
      New-Item -ItemType Directory -Force (Split-Path $copie) | Out-Null
      Copy-Item $cible $copie -Force
    }
    New-Item -ItemType Directory -Force (Split-Path $cible) | Out-Null
    Copy-Item $f.FullName $cible -Force
  }
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  [void][System.Windows.Forms.MessageBox]::Show("Mise a jour installee (version $distante).", 'Macros Minecraft : mise a jour', 'OK', 'Information')
} catch {
  if ($choix -eq 'Yes') {
    [void][System.Windows.Forms.MessageBox]::Show("La mise a jour a echoue : $($_.Exception.Message)`nLe logiciel reste dans sa version actuelle.", 'Macros Minecraft : mise a jour', 'OK', 'Warning')
  }
}
