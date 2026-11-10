# =====================================================================
#  securite.ps1 : arret si le joueur est teleporte (option "Securite" du menu). Charge par la canne, les cultures et la peche.
#
#  Coordonnees lues toutes les 0,5 s. Le joueur se deplace : un saut n'est suspect que s'il depasse la distance choisie
#  PLUS ce qu'on parcourt a pied dans ce temps. Deux lectures de suite doivent le confirmer (un chiffre mal lu ne compte pas).
#  Les /home et /spawn du script ne comptent pas : il appelle Oublier-TP juste avant de les taper, et apres une pause.
#  Le script qui charge ce fichier fournit $StopTP, $TPBlocs, Relacher-Tout et $script:Arret.
# =====================================================================
$script:PosTP = $null; $script:TempsTP = 0; $script:ProchaineTP = 0; $script:SuspectTP = 0; $script:PermisTP = 0
$script:ZonesTP = $null; $script:TPLibreJusque = 0; $script:TPAnnonce = $false
$script:VitesseMaxTP = 8   # blocs par seconde : plus que le sprint (5,6)

function Lire-CoordTP {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  if ($null -eq $script:ZonesTP) {
    # rien de memorise tant qu'on ne les a pas trouvees : F3 peut etre ouvert a ce moment-la
    $coin = New-Object System.Drawing.Rectangle $r.L, $r.T, ([Math]::Min([Math]::Max(900, 300 * $script:Gui), $r.R - $r.L)), ([Math]::Min([Math]::Max(600, 200 * $script:Gui), $r.B - $r.T))
    $tc = [Glyphes]::TrouverCoordonnees($coin)
    if (-not $tc) { return $null }
    [Glyphes]::Echelle = $tc[0]
    $script:ZonesTP = foreach ($k in 3, 4, 5) { New-Object System.Drawing.Rectangle $tc[1], ($tc[$k] - 1), $tc[2], ($tc[6] + 2) }
  }
  $pos = @()
  foreach ($z in $script:ZonesTP) {
    $t = [Glyphes]::Lire((New-Object System.Drawing.Rectangle ($r.L + $z.X), ($r.T + $z.Y), $z.Width, $z.Height))
    if ($t -notmatch '^-?\d+$') { return $null }
    $pos += [int]$t
  }
  return $pos
}

# A appeler avant une teleportation voulue ($ms : temps pendant lequel on ne surveille plus) et apres une pause.
function Oublier-TP($ms = 0) {
  $script:PosTP = $null; $script:SuspectTP = 0
  if ($ms -gt 0) { $script:TPLibreJusque = [Environment]::TickCount + $ms }
}

function Verifier-TP {
  if ($StopTP -le 0) { return }
  $mtn = [Environment]::TickCount
  if ($mtn -lt $script:ProchaineTP) { return }
  $script:ProchaineTP = $mtn + 500
  if ($mtn -lt $script:TPLibreJusque) { return }
  $p = Lire-CoordTP
  if ($null -eq $p) { return }
  if ($null -eq $script:PosTP) {
    $script:PosTP = $p; $script:TempsTP = $mtn
    if (-not $script:TPAnnonce) { $script:TPAnnonce = $true; Write-Host ("Arret si teleporte : actif, au-dela de {0} bloc(s) en plus de la marche." -f $TPBlocs) }
    return
  }
  $d = 0; for ($i = 0; $i -lt 3; $i++) { $d = [Math]::Max($d, [Math]::Abs($p[$i] - $script:PosTP[$i])) }
  if ($script:SuspectTP -eq 0) { $script:PermisTP = $TPBlocs + $script:VitesseMaxTP * ($mtn - $script:TempsTP) / 1000.0 }
  if ($d -le $script:PermisTP) { $script:SuspectTP = 0; $script:PosTP = $p; $script:TempsTP = $mtn; return }
  $script:SuspectTP++
  if ($script:SuspectTP -lt 2) { return }
  Relacher-Tout; $script:Arret = $true
  [console]::Beep(880, 250); [console]::Beep(660, 400)
  Write-Host ("TELEPORTE : position {0} {1} {2} -> {3} {4} {5}, arret." -f $script:PosTP[0], $script:PosTP[1], $script:PosTP[2], $p[0], $p[1], $p[2])
}
