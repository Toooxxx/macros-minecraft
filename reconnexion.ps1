# =====================================================================
#  reconnexion.ps1 : retour sur l'ile apres une fermeture du serveur (redemarrage de la nuit). Lance par le menu
#  (option "Reconnexion auto" dans Options), N minutes apres l'un de ces deux cas, lus dans le journal du jeu :
#
#  1) "You were kicked from island-... : Server closed" (vu le 13/11/2026) : le jeu reste connecte, on est renvoye au
#     hub (X 0 Y 100 Z 0), boussole en main au slot 5. Pour revenir : clic droit sur la boussole -> menu
#     "MinePiece - Join" -> clic sur l'objet "Fuchsia Village" (icone doree au centre) -> file "spawn" -> spawn.
#  2) "Client disconnected with reason: Disconnected" (vu le 14/11/2026, -Deconnecte) : le jeu est deconnecte, ecran
#     "Connection Lost / Disconnected" avec deux boutons, "Back to Server List" puis "Reconnect" (plus etroit, dessous).
#     Pour revenir : clic sur "Reconnect" -> file "spawn" -> spawn (pas de hub).
#  Puis dans les deux cas : /home de la ferme.
#
#  Codes de sortie : 0 reussi ; 1 rate, a reessayer plus tard ; 2 abandon (pas au hub, /home refuse, arret demande).
#  Rien n'est ecrit dans le chat sauf le /home de la ferme (autorise par l'utilisateur). Le jeu n'est jamais
#  mis au premier plan par le script : s'il n'y est pas, on attend.
# =====================================================================
param(
  [string]$NomHome = 'canne',          # canne, pasteque, citrouille, ble, carotte, verrue, mine1, mine2
  [switch]$Deconnecte,                 # cas 2 : chercher d'abord le bouton "Reconnect"
  [int]$SlotBoussole = 5,
  [int]$TouchePause = 0x76, [int]$ToucheArret = 0x77,
  [int]$RepondreVerif = 0, [int]$StopTP = 0, [int]$TPBlocs = 3, [int]$VenteMs = 100
)
$Dossier = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Get-Content (Join-Path $Dossier 'recolte.ps1') -Raw
$i = $src.IndexOf('Add-Type -AssemblyName System.Windows.Forms'); $j = $src.IndexOf('# ---------------------------- LOGIQUE-' + 'DEBUT')
Invoke-Expression ($src.Substring($i, $j - $i))
$script:DepartAuto = $false
function Stop-Recolte($msg) { Relacher-Tout; $script:Arret = $true; Write-Host ("Reconnexion : {0}" -f $msg) }
function Appuyer-Slot($n) { $sc = $script:Slots[$n - 1]; [Entree]::Touche($sc, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 25 -Maximum 45); [Entree]::Touche($sc, $false) }
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Reco {
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  public static void Placer(int x, int y) { SetCursorPos(x, y); }
  public static void ClicDroit() { mouse_event(0x0008, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(50); mouse_event(0x0010, 0, 0, 0, IntPtr.Zero); }
  public static void ClicGauche() { mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(50); mouse_event(0x0004, 0, 0, 0, IntPtr.Zero); }
}
'@

function Fin($code, $msg) { Relacher-Tout; Write-Host $msg; exit $code }
function Attente($ms) { $f = [Environment]::TickCount + $ms; while ([Environment]::TickCount -lt $f) { if (Arret-Demande) { Fin 2 'Reconnexion annulee (arret demande).' }; Start-Sleep -Milliseconds 50 } }

# --- journal du jeu : seulement les lignes ecrites depuis le debut de la reconnexion (chat, et deconnexion du client)
$script:Log = Get-ChildItem "$env:USERPROFILE\.lunarclient\profiles\*\logs\latest.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$script:LogPos = if ($script:Log) { $script:Log.Length } else { 0 }
function Lignes-Jeu {
  if (-not $script:Log) { return @() }
  try {
    $fs = [System.IO.File]::Open($script:Log.FullName, 'Open', 'Read', 'ReadWrite,Delete')
    if ($fs.Length -lt $script:LogPos) { $script:LogPos = 0 }
    $n = $fs.Length - $script:LogPos
    if ($n -le 0) { $fs.Close(); return @() }
    [void]$fs.Seek($script:LogPos, 'Begin'); $buf = New-Object byte[] $n; $lu = $fs.Read($buf, 0, $n); $fs.Close()
    $script:LogPos += $lu
    return @([System.Text.Encoding]::UTF8.GetString($buf, 0, $lu) -split "`r?`n" | Where-Object { $_ -match '\[CHAT\]|Client disconnected with reason' } | ForEach-Object { ($_ -replace '^.*\[CHAT\]\s*', '' -replace '^.*(Client disconnected)', '$1').Trim() } | Where-Object { $_ })
  } catch { return @() }
}

function Fenetre-Jeu {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  return [Interface]::Client($h)
}
function Image-Menu($nom) { try { $d = Join-Path $Dossier 'diagnostics'; New-Item -ItemType Directory -Force $d | Out-Null; $script:ImageMenu.Save((Join-Path $d $nom)) } catch { } }

# --- icone doree de "Fuchsia Village" dans le menu de la boussole (centre de l'ecran, vu le 13/11/2026 en 1280,564
# pour une fenetre de 2560x1369). On compare avant / apres le clic droit : seul l'or QUI APPARAIT compte (le decor du
# hub peut contenir de l'or), en un groupe serre, et on vise sa mediane. Teste sur les captures de la nuit du 13/11 :
# menu = 90 points (moitie de taille), paires sans menu = 13 au plus (hors teleportation).
function Masque-Or {
  $c = Fenetre-Jeu
  $z = New-Object System.Drawing.Rectangle ($c.X + [int]($c.Width * 0.42)), ($c.Y + [int]($c.Height * 0.12)), ([int]($c.Width * 0.16)), ([int]($c.Height * 0.55))
  $bmp = New-Object System.Drawing.Bitmap $z.Width, $z.Height; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($z.Location, [System.Drawing.Point]::Empty, $z.Size); $g.Dispose()
  $d = $bmp.LockBits((New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height), 'ReadOnly', 'Format32bppArgb')
  $px = New-Object byte[] ($d.Stride * $bmp.Height); [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $px, 0, $px.Length); $bmp.UnlockBits($d)
  $l = [int][Math]::Ceiling($bmp.Width / 2); $m = New-Object bool[] ($l * [int][Math]::Ceiling($bmp.Height / 2))
  for ($y = 0; $y -lt $bmp.Height; $y += 2) { for ($x = 0; $x -lt $bmp.Width; $x += 2) {
    $o = $y * $d.Stride + 4 * $x
    $m[($y / 2) * $l + ($x / 2)] = $px[$o + 2] -ge 220 -and $px[$o + 1] -ge 150 -and $px[$o + 1] -le 235 -and $px[$o] -le 120
  } }
  $script:ImageMenu = $bmp
  return @{ M = $m; L = $l; Z = $z; W = $c.Width }
}
function Icone-Apparue($avant) {
  $apres = Masque-Or
  $xs = New-Object System.Collections.Generic.List[int]; $ys = New-Object System.Collections.Generic.List[int]
  for ($k = 0; $k -lt $apres.M.Length; $k++) { if ($apres.M[$k] -and -not $avant.M[$k]) { $xs.Add(2 * ($k % $apres.L)); $ys.Add(2 * [int][Math]::Floor($k / $apres.L)) } }
  if ($xs.Count -lt 25) { return $null }
  $xs.Sort(); $ys.Sort()
  $n = $xs.Count; $etendue = $xs[[int]($n * 0.75)] - $xs[[int]($n * 0.25)]
  if ($etendue -gt 0.04 * $apres.W) { Write-Host ("Reconnexion : or apparu trop eparpille ({0} points, {1} px)." -f $n, $etendue); return $null }
  return @(($apres.Z.X + $xs[[int]($n / 2)]), ($apres.Z.Y + $ys[[int]($n / 2)]), $n)
}

# --- bouton "Reconnect" de l'ecran "Connection Lost" (vu le 14/11/2026 : fenetre 2560x1368, "Back to Server List"
# x 984-1578 y 708-760, "Reconnect" x 1058-1502 y 778-830, gris uni R=G=B 80-175 sur fond flou presque noir).
# On cherche, au centre de la fenetre entre 40 % et 80 % de la hauteur, EXACTEMENT deux bandes grises l'une sous
# l'autre, la seconde plus etroite que la premiere, sans autre bouton autour (le menu Echap en a beaucoup plus).
# Renvoie le centre du bouton du bas (ecran), ou $null.
function Bouton-Reconnect {
  $c = Fenetre-Jeu
  if ($c.Width -lt 200 -or $c.Height -lt 200) { return $null }
  $bmp = New-Object System.Drawing.Bitmap $c.Width, $c.Height; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($c.Location, [System.Drawing.Point]::Empty, $bmp.Size); $g.Dispose()
  $script:ImageMenu = $bmp
  $d = $bmp.LockBits((New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height), 'ReadOnly', 'Format32bppArgb')
  $px = New-Object byte[] ($d.Stride * $bmp.Height); [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $px, 0, $px.Length); $bmp.UnlockBits($d)
  $W = $bmp.Width; $H = $bmp.Height; $cx = [int]($W / 2)
  $gris = { param($x, $y) $o = $y * $d.Stride + 4 * $x; $b = $px[$o]; $v = $px[$o + 1]; $r = $px[$o + 2]
    $r -ge 70 -and $r -le 200 -and [Math]::Abs($r - $v) -le 8 -and [Math]::Abs($r - $b) -le 10 -and [Math]::Abs($v - $b) -le 10 }
  # colonnes a +-6 % du centre (dans les deux boutons, hors du texte le plus souvent) : une ligne est "bouton" si
  # au moins 2 des 3 points (gauche, droite, et un peu a cote) sont gris
  $xs = @(($cx - [int]($W * 0.06)), ($cx + [int]($W * 0.06)), ($cx - [int]($W * 0.03)))
  $bandes = @(); $debut = -1; $trou = 0; $tolTrou = [Math]::Max(2, [int]($H * 0.004))
  for ($y = [int]($H * 0.40); $y -lt [int]($H * 0.80); $y++) {
    $n = 0; foreach ($x in $xs) { if (& $gris $x $y) { $n++ } }
    if ($n -ge 2) { if ($debut -lt 0) { $debut = $y }; $fin = $y; $trou = 0 }
    elseif ($debut -ge 0) { $trou++; if ($trou -gt $tolTrou) { $bandes += , @($debut, $fin); $debut = -1; $trou = 0 } }
  }
  if ($debut -ge 0) { $bandes += , @($debut, $fin) }
  $bandes = @($bandes | Where-Object { ($_[1] - $_[0]) -ge [int]($H * 0.012) })
  if ($bandes.Count -ne 2) { Write-Host ("Reconnexion : ecran Connection Lost pas reconnu ({0} bande(s) grise(s) au centre au lieu de 2)." -f $bandes.Count); return $null }
  $larg = foreach ($bd in $bandes) {
    $y = $bd[0] + [int](($bd[1] - $bd[0]) * 0.2)                     # au-dessus du texte du bouton
    $gx = $cx; while ($gx -gt 0 -and ((& $gris ($gx - 1) $y) -or (& $gris ($gx - 2) $y) -or (& $gris ($gx - 3) $y))) { $gx-- }
    $dx = $cx; while ($dx -lt $W - 4 -and ((& $gris ($dx + 1) $y) -or (& $gris ($dx + 2) $y) -or (& $gris ($dx + 3) $y))) { $dx++ }
    , @($gx, $dx)
  }
  $l1 = $larg[0][1] - $larg[0][0]; $l2 = $larg[1][1] - $larg[1][0]
  $h1 = $bandes[0][1] - $bandes[0][0]; $h2 = $bandes[1][1] - $bandes[1][0]; $ecart = $bandes[1][0] - $bandes[0][1]
  $ok = $l1 -ge $W * 0.10 -and $l1 -le $W * 0.45 -and $l2 -ge $W * 0.08 -and $l2 -le $l1 * 0.92 -and
        [Math]::Abs($h1 - $h2) -le [Math]::Max(4, $h1 * 0.25) -and $ecart -gt 0 -and $ecart -le $h1 * 1.5 -and
        [Math]::Abs(($larg[1][0] + $larg[1][1]) / 2 - $cx) -le $W * 0.02
  if (-not $ok) { Write-Host ("Reconnexion : deux boutons vus mais pas ceux de Connection Lost (largeurs {0} et {1}, hauteurs {2} et {3}, ecart {4})." -f $l1, $l2, $h1, $h2, $ecart); return $null }
  return @(($c.X + [int](($larg[1][0] + $larg[1][1]) / 2)), ($c.Y + [int](($bandes[1][0] + $bandes[1][1]) / 2)))
}

# --- file d'attente puis spawn : au plus 10 min dans la file, 60 s sans aucune reponse
function Attendre-Spawn {
  $debut = [Environment]::TickCount; $file = $false
  while ($true) {
    Attente 1000
    foreach ($l in (Lignes-Jeu)) {
      if ($l -match 'queue|Teleporting|kicked|full|offline|Could not|Unable|rejoindre|plein|disconnected') { Write-Host "Reconnexion (jeu) : $l" }
      if ($l -match 'joined the queue') { $file = $true }
      if ($l -match 'kicked|offline|Could not connect|Unable to connect|Client disconnected') { Fin 1 'Reconnexion : le serveur a refuse la connexion (pas encore relance ?).' }
    }
    $q = Lire-Coord
    if ($null -ne $q -and [Math]::Abs($q[2] - 10935) -le 150) { Write-Host ("Reconnexion : arrive au spawn (X {0} Y {1} Z {2})." -f $q[0], $q[1], $q[2]); break }
    $dt = [Environment]::TickCount - $debut
    if (-not $file -and $dt -gt 60000) { Fin 1 'Reconnexion : pas de reponse 60 s apres le clic.' }
    if ($dt -gt 600000) { Fin 1 'Reconnexion : toujours dans la file apres 10 min.' }
  }
  Attente 4000                                                              # chargement du monde
}

Write-Host ("Reconnexion : debut{0} (/home $NomHome a la fin)." -f $(if ($Deconnecte) { ' apres une perte de connexion' } else { '' }))
# 1) le jeu doit etre au premier plan (on ne le force jamais)
$dit = $false
while (-not (Au-Premier-Plan)) {
  if (-not $dit) { Write-Host 'Reconnexion : en attente du jeu au premier plan (clique dans le jeu).'; $dit = $true }
  Attente 1000
}
Attente 500

# 2) cas "Connection Lost" : bouton Reconnect (3 regards a 1 s d'intervalle). Pas trouve : on regarde ou on est
# (l'utilisateur a peut-etre deja reconnecte a la main).
$cliqueReco = $false
if ($Deconnecte) {
  $bt = $null
  for ($k = 1; $k -le 3 -and $null -eq $bt; $k++) { $bt = Bouton-Reconnect; if ($null -eq $bt) { if ($k -eq 3) { Image-Menu 'reconnexion-ecran.png' } else { Attente 1000 } } }
  if ($null -ne $bt) {
    Write-Host 'Reconnexion : ecran Connection Lost reconnu, clic sur Reconnect.'
    [Reco]::Placer($bt[0], $bt[1]); Attente 250
    if ($null -eq (Bouton-Reconnect)) { Fin 1 'Reconnexion : l''ecran a change avant le clic, rien clique.' }
    [Reco]::ClicGauche()
    $cliqueReco = $true
    Attendre-Spawn
  }
}

if (-not $cliqueReco) {
  # 3) ou est-on ? hub = autour de X 0 Z 0
  $p = Lire-Coord
  if ($null -eq $p) { Attente 1000; $p = Lire-Coord }
  if ($null -eq $p) { Fin 1 'Reconnexion : coordonnees illisibles (jeu deconnecte ? menu ouvert ?).' }
  Write-Host ("Reconnexion : position X {0} Y {1} Z {2}." -f $p[0], $p[1], $p[2])
  $auHub = [Math]::Abs($p[0]) -le 40 -and [Math]::Abs($p[2]) -le 40
  $auSpawn = [Math]::Abs($p[2] - 10935) -le 150
  if (-not $auHub -and -not $auSpawn) { Fin 2 'Reconnexion : ni au hub ni au spawn (deja revenu sur l''ile ?) : rien fait.' }

  if ($auHub) {
    # 4) boussole -> menu -> Fuchsia Village (deux essais)
    $ok = $false
    for ($essai = 1; $essai -le 2 -and -not $ok; $essai++) {
      Appuyer-Slot $SlotBoussole; Attente 600
      $avant = Masque-Or
      [Reco]::ClicDroit()
      $ic = $null
      for ($k = 0; $k -lt 10 -and $null -eq $ic; $k++) { Attente 300; $ic = Icone-Apparue $avant }
      if ($null -eq $ic) {
        Write-Host "Reconnexion : menu de la boussole pas vu (essai $essai)."
        Image-Menu ("reconnexion-menu-{0}.png" -f $essai)
        [Entree]::Touche(0x01, $true); Start-Sleep -Milliseconds 50; [Entree]::Touche(0x01, $false)   # Echap : referme un menu eventuel
        Attente 800; continue
      }
      Write-Host ("Reconnexion : Fuchsia Village trouve ({0} points), clic." -f $ic[2])
      [Reco]::Placer($ic[0], $ic[1]); Attente 250
      [Reco]::ClicGauche()
      $ok = $true
    }
    if (-not $ok) { Fin 1 'Reconnexion : impossible d''ouvrir le menu de la boussole.' }
    Attendre-Spawn
  }
}

# 5) /home de la ferme (deux essais), verifie dans le chat
$vu = $false
for ($essai = 1; $essai -le 2 -and -not $vu; $essai++) {
  if (-not (Au-Premier-Plan)) { Fin 1 'Reconnexion : le jeu n''est plus au premier plan, /home pas tape.' }
  [void](Lignes-Jeu)
  if (-not (Taper-Commande "home $NomHome")) { Fin 1 'Reconnexion : /home pas tape.' }
  $f = [Environment]::TickCount + 8000
  while ([Environment]::TickCount -lt $f -and -not $vu) {
    Attente 300
    foreach ($l in (Lignes-Jeu)) {
      if ($l -match [regex]::Escape("home $NomHome")) { $vu = $true; Write-Host "Reconnexion (jeu) : $l" }
      elseif ($l -match 'home|existe|inconnu|introuvable') { Write-Host "Reconnexion (jeu) : $l" }
    }
  }
}
if (-not $vu) { Fin 2 "Reconnexion : /home $NomHome sans reponse du serveur." }
Attente 5000                                                                # teleportation + chargement de la ferme
Fin 0 "Reconnexion reussie : au /home $NomHome."
