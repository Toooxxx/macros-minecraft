# =====================================================================
#  recolte.ps1 : recolte de fermes en rangees (pasteques, citrouilles). Lance par le menu, onglet Recolte.
#
#  Le joueur regarde sur le cote des fruits (regard fixe, jamais touche par le script) et se deplace
#  de cote le long de la ligne de tiges, colle au mur qui est dans son dos.
#  En serpentin : une rangee, le couloir (avancer de $Ecart blocs), la rangee suivante en sens inverse.
#  A la fin du tour, retour au depart par le couloir (a reculons).
#
#  DEPART : dans le couloir, juste devant la 1re ligne de tiges, regard deja regle, F3 ferme
#  (le script lit les coordonnees de Lunar en haut a gauche), les deux couloirs fermes par un mur.
#
#  SECURITES
#    F7 : demarrer, puis pause / reprise        F8 (ou Arreter du menu) : arret, tout est relache
#    Jeu plus au premier plan : tout est relache, puis attente de F7
#    Bloque, sorti de la rangee, teleporte ou coordonnees illisibles : tout est relache et arret
#  Rien n'est ecrit dans le chat, sauf le nombre de la verification AFK si l'option est active
#  et /home pasteque ou /home citrouille a la fin de l'etage 2 (autorises par l'utilisateur le 09/11/2026).
# =====================================================================
param(
  [string]$Culture = 'pasteque',   # 'pasteque' (etage 1 regard a l'est, /home pasteque) ou 'citrouille' (etage 1 regard a l'ouest, /home citrouille)
  [int]$RangeeDepart = 1,        # rangee ou commencer au premier tour (1 a 12) ; les tours suivants repartent de la 1re
  [int]$Rangees = 12,              # fixe : rangees par etage (nombre pair : on finit du cote du depart)
  [int]$Longueur = 111,            # fixe : rangs cultives entre les deux couloirs (toutes les fermes ont la meme taille)
  [int]$Ecart = 5,                 # fixe : blocs entre deux lignes de tiges
  [string]$Sens = 'droite',        # fixe : regard a l'est, depart cote nord, donc la 1re rangee part vers la droite
  [int]$Tours = 0,                 # 0 = sans limite
  [int]$CalerRegard = 1,           # 1 = au debut de chaque tour : regard plein est, 35 a 40 vers le bas (lu dans F3)
  [int]$EtageDepart = 1,           # 1 = etage du bas (puis echelle, etage 2 regard a l'ouest, /home) ; 2 = commence directement a l'etage 2
  [int]$BlocsEchelle = 3,          # fixe : blocs entre la derniere rangee et l'echelle
  [int]$HauteurEtage = 3,          # fixe : blocs entre deux etages
  [string]$HomeRetour = 'pasteque',     # /home autorise par l'utilisateur le 09/11/2026 : ramene au debut de la ferme
  [int]$RepondreVerif = 0,         # 1 = repondre a la verification AFK (option du menu)
  [int]$TouchePause = 0x76,        # F7 par defaut
  [int]$ToucheArret = 0x77,        # F8 par defaut
  [int]$StopTP = 0,                # 1 = arret si teleporte (option du menu)
  [int]$TPBlocs = 3
)

$Dossier = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -AssemblyName System.Windows.Forms
$NomPause = ([System.Windows.Forms.Keys]$TouchePause).ToString()
$NomArret = ([System.Windows.Forms.Keys]$ToucheArret).ToString()

# Memes outils que le script de la ferme : on reprend son bloc C# pour n'avoir qu'une seule version.
$src = Get-Content (Join-Path $Dossier 'canne-etage.ps1') -Raw
$i = $src.IndexOf('Add-Type -AssemblyName System.Drawing'); $j = $src.IndexOf("'@", $i)
Invoke-Expression ($src.Substring($i, $j - $i + 2))
[Glyphes]::Charger((Join-Path $Dossier 'police.txt'))

. (Join-Path $Dossier 'touches.ps1')                                       # touches du jeu, lues dans ses reglages
. (Join-Path $Dossier 'securite.ps1')                                      # arret si teleporte (option du menu)
$T = @{ avant = $script:Cles.avant; arriere = $script:Cles.arriere; gauche = $script:Cles.gauche; droite = $script:Cles.droite }
$script:Arret = $false
$script:Tenues = @(); $script:ClicBas = $false
# noms attendus par verification.ps1 ; ici toujours vides : apres une verification, Poser remet les touches
$script:ToucheTenue = $null; $script:ClicTenu = $false; $script:Tenu = $false

# Tient exactement ces touches et ce clic ; relache tout le reste.
function Poser($touches, $clic) {
  foreach ($t in @($script:Tenues)) { if (@($touches) -notcontains $t) { [Entree]::Touche([uint16]$t, $false) } }
  foreach ($t in @($touches)) { if ($script:Tenues -notcontains $t) { [Entree]::Touche([uint16]$t, $true) } }
  $script:Tenues = @($touches)
  if ($clic -ne $script:ClicBas) { [Entree]::ClicGauche($clic); $script:ClicBas = $clic }
}
# Relache aussi les touches que le script croit deja relachees : aucune touche ne doit rester enfoncee apres un arret.
function Relacher-Tout { Poser @() $false; foreach ($v in $T.Values) { [Entree]::Touche([uint16]$v, $false) }; [Entree]::ClicGauche($false) }

$script:PidsJeu = @(Garder-Lunar (Get-Process -Name javaw, java -ErrorAction SilentlyContinue) | ForEach-Object { [uint32]$_.Id })
. (Join-Path $Dossier 'verification.ps1')
function Au-Premier-Plan { return $script:PidsJeu -contains [Entree]::PidDe([Entree]::FenetrePremierPlan()) }
$script:FichierArret = Join-Path $Dossier 'arret.flag'
if (Test-Path $script:FichierArret) { Remove-Item $script:FichierArret -Force }
function Arret-Demande { return ([Entree]::Appuyee($ToucheArret) -or (Test-Path $script:FichierArret)) }
function Attendre-Relache($vk) { while ([Entree]::Appuyee($vk)) { Start-Sleep -Milliseconds 30 } }
# Relance par le menu apres une reconnexion auto (variable MACROS_DEPART_AUTO) : la premiere attente de F7 est sautee.
$script:DepartAuto = $env:MACROS_DEPART_AUTO -eq '1'
function Attendre-F7 {
  if ($script:DepartAuto) { $script:DepartAuto = $false; Write-Host "Depart automatique apres la reconnexion."; return $true }
  Attendre-Relache $TouchePause
  while (-not [Entree]::Appuyee($TouchePause)) { if (Arret-Demande) { $script:Arret = $true; return $false }; Start-Sleep -Milliseconds 30 }
  Attendre-Relache $TouchePause
  return $true
}

$script:Actif = [Diagnostics.Stopwatch]::new()
# Pause (F7) ou jeu au second plan : on relache tout et on attend F7. Renvoie $true s'il y a eu une interruption.
function Verifier {
  if (Arret-Demande) { $script:Arret = $true; Relacher-Tout; return $true }
  $pause = $false
  if ([Entree]::Appuyee($TouchePause)) { $pause = $true; Write-Host "PAUSE ($NomPause = reprendre, $NomArret = arreter)" }
  elseif (-not (Au-Premier-Plan)) {
    Relacher-Tout
    $fin = [Environment]::TickCount + 500
    while ([Environment]::TickCount -lt $fin) { Start-Sleep -Milliseconds 25; if (Au-Premier-Plan) { return $true } }
    $pause = $true; Write-Host "Le jeu n'est plus au premier plan : en pause. Reviens dans le jeu, ferme le menu (Echap), puis $NomPause."
  }
  if (-not $pause) { Verifier-TP; return [bool]$script:Arret }
  Relacher-Tout; $script:Actif.Stop()
  while ($true) {
    if (-not (Attendre-F7)) { return $true }
    if (Au-Premier-Plan) { break }
    Write-Host "$NomPause recu, mais le jeu n'est pas au premier plan : clique dans le jeu puis $NomPause."
  }
  Start-Sleep -Milliseconds 300
  Write-Host "Reprise"; $script:Actif.Start()
  $script:DerPos = $null; Oublier-TP                                        # on a pu bouger pendant la pause
  return $true
}

# ------------------------------ Argent ------------------------------
$script:ProchaineLectureArgent = 0
function Rect-Jeu {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  return $r
}
function Lire-Argent {
  $r = Rect-Jeu
  $larg = $r.R - $r.L
  if ($larg -lt 200) { return $null }
  $zone = New-Object System.Drawing.Rectangle ($r.L + [int]($larg * 0.15)), ($r.T + 8), ([int]($larg * 0.7)), (37 * $script:Gui)
  $t = [Glyphes]::LireCouleur($zone, 255, 188, 53, $script:Gui)
  if ($t -notmatch '(\d+(?:\.\d+)?)([KMB]?)$') { return $null }
  $mult = @{ '' = 1; 'K' = 1e3; 'M' = 1e6; 'B' = 1e9 }[$Matches[2]]
  return [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) * $mult
}
function Suivre-Argent($forcer = $false) {
  if (-not $forcer -and [Environment]::TickCount -lt $script:ProchaineLectureArgent) { return }
  $script:ProchaineLectureArgent = [Environment]::TickCount + 30000
  $a = Lire-Argent
  if ($null -ne $a) { Write-Host ("argent : {0}" -f [long]$a) }
}

# ---------------------------- Coordonnees ----------------------------
# Coordonnees de Lunar en haut a gauche (X, Y, Z en blocs entiers), cherchees une fois comme pour le minage.
$script:ZonesCoord = $null
function Lire-Coord {
  $r = Rect-Jeu
  if ($null -eq $script:ZonesCoord) {
    $coin = New-Object System.Drawing.Rectangle $r.L, $r.T, ([Math]::Min([Math]::Max(900, 300 * $script:Gui), $r.R - $r.L)), ([Math]::Min([Math]::Max(600, 200 * $script:Gui), $r.B - $r.T))
    $tc = [Glyphes]::TrouverCoordonnees($coin)
    if ($tc) { [Glyphes]::Echelle = $tc[0]; $script:ZonesCoord = foreach ($k in 3, 4, 5) { New-Object System.Drawing.Rectangle $tc[1], ($tc[$k] - 1), $tc[2], ($tc[6] + 2) } }
    else { [Glyphes]::Echelle = 2; $script:ZonesCoord = foreach ($dy in 44, 66, 88) { New-Object System.Drawing.Rectangle 44, $dy, 120, 16 } }
  }
  $pos = @()
  foreach ($z in $script:ZonesCoord) {
    $t = [Glyphes]::Lire((New-Object System.Drawing.Rectangle ($r.L + $z.X), ($r.T + $z.Y), $z.Width, $z.Height))
    if ($t -notmatch '^-?\d+$') { return $null }
    $pos += [int]$t
  }
  return $pos
}
# ------------------------------- Regard -------------------------------
# Lecture de la ligne "Facing" de F3, memes zones et memes essais que la ferme a canne.
$script:ReglageF3 = $null
$SeuilF3 = 210                                                             # texte de F3 : gris clair (meme valeur que la ferme a canne)
function Zones-F3 {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $c = [Interface]::Client($h)
  return @((New-Object System.Drawing.Rectangle ($c.X + [int]($c.Width * 0.45)), $c.Y, ($c.Width - [int]($c.Width * 0.45)), ([int]($c.Height * 0.55))),
           (New-Object System.Drawing.Rectangle $c.X, $c.Y, ([int]($c.Width * 0.62)), ([int]($c.Height * 0.55))))
}
# Trois nombres ou deux, lus sur la ligne de F3 qui correspond au motif ; $null si illisible
function Lire-F3($motif, $groupes) {
  for ($n = 0; $n -lt 6; $n++) {
    $zones = Zones-F3
    if ($script:ReglageF3) { $essais = @(, $script:ReglageF3) }
    else { $essais = @(@(0, $script:Gui), @(0, 3), @(0, 2), @(0, 4), @(1, $script:Gui), @(1, 3), @(1, 2), @(1, 4), @(1, 1)) }
    foreach ($e in $essais) {
      foreach ($ligne in [Glyphes]::Lignes($zones[$e[0]], $SeuilF3, $e[1])) {
        $m = [regex]::Match($ligne, $motif)
        if ($m.Success) {
          if (-not $script:ReglageF3) { $script:ReglageF3 = $e }
          $inv = [Globalization.CultureInfo]::InvariantCulture
          return @(1..$groupes | ForEach-Object { [double]::Parse($m.Groups[$_].Value, $inv) })
        }
      }
    }
    Start-Sleep -Milliseconds 150
  }
  return $null
}
# @(lacet, inclinaison)
function Lire-Regard { return (Lire-F3 '\((-?\d+\.\d)/(-?\d+\.\d)\)$' 2) }
# @(x, y, z) avec les decimales
function Lire-XYZ { return (Lire-F3 '(-?\d+\.\d+)/(-?\d+\.\d+)/(-?\d+\.\d+)$' 3) }
# Tape une commande autorisee dans le chat, avec des temps varies (meme fonction que le minage).
function Taper-Commande($texte) {
  Oublier-TP 8000   # teleportation voulue
  Relacher-Tout
  if (-not (Au-Premier-Plan)) { Stop-Recolte "le jeu n'est pas visible : /$texte annule"; return $false }
  Start-Sleep -Milliseconds (Get-Random -Minimum 250 -Maximum 600)
  [Entree]::Touche($script:Cles.chat, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 70); [Entree]::Touche($script:Cles.chat, $false)   # ouvre le chat
  Start-Sleep -Milliseconds (Get-Random -Minimum 600 -Maximum 900)
  foreach ($ch in ('/' + $texte).ToCharArray()) {
    [System.Windows.Forms.SendKeys]::SendWait(($(if ('+^%~(){}[]'.Contains([string]$ch)) { '{' + $ch + '}' } else { [string]$ch })))
    Start-Sleep -Milliseconds (Get-Random -Minimum 40 -Maximum 120)
  }
  Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 450)
  [Entree]::Touche(0x1C, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 70); [Entree]::Touche(0x1C, $false)   # Entree
  return $true
}
function Basculer-F3 { [Entree]::Touche(0x3D, $true); Start-Sleep -Milliseconds 60; [Entree]::Touche(0x3D, $false) }
function Bouger-Souris($dx, $dy) { [Entree]::Souris($dx, $dy) }
function Cliquer-Une-Fois { [Entree]::ClicGauche($true); Start-Sleep -Milliseconds 40; [Entree]::ClicGauche($false) }

function Tic {
  if (Surveiller-Verification) { return $true }
  if (Verifier) { return $true }
  Suivre-Argent
  return $false
}

# ---------------------------- LOGIQUE-DEBUT ---------------------------- (testee hors du jeu avec un monde simule)
$script:DerPos = $null; $script:DerLecture = 0
$script:Axe = $null; $script:AxePerp = $null; $script:SensAxe = 0; $script:SensPerp = 0
# Les citrouilles sont le miroir des pasteques : regard, sens des rangees et cote de depart inverses, ainsi que le /home.
if ($Culture -eq 'citrouille') { $HomeRetour = 'citrouille' }
$script:Cap1 = if ($Culture -eq 'citrouille') { 90.0 } else { -90.0 }     # regard de l'etage 1 (F3 : -90 = est, 90 = ouest)
$script:Cap2 = -$script:Cap1                                              # regard de l'etage du dessus, apres le demi-tour
$script:Sens1 = if ($script:Cap1 -lt 0) { 'droite' } else { 'gauche' }    # touche vers le sud a l'etage 1
$script:Sens2 = if ($script:Cap1 -lt 0) { 'gauche' } else { 'droite' }    # et a l'etage du dessus
$script:Perp1 = if ($script:Cap1 -lt 0) { 1 } else { -1 }                 # avancer a l'etage 1 : vers les X croissants ou decroissants
$script:Sens = $script:Sens1
$script:Depart = $null; $script:Couloir = $null; $script:RangeesFaites = 0; $script:DepartCale = $false

$script:DegresParPoint = $null                                            # mesure au premier calibrage
# Regard calibre pile a l'est : plus besoin de reculer dans les rangees (7,7 blocs/s au lieu de 5,4)
$script:RegardPile = $false
function Ecart-Angle($cible, $a) { $d = ($cible - $a) % 360; if ($d -gt 180) { $d -= 360 }; if ($d -lt -180) { $d += 360 }; return $d }

# Debut de tour, joueur arrete : ouvre F3, tourne la souris plein est (-90) et a une inclinaison tiree entre 35 et 40,
# referme F3. En cas d'echec on continue avec le regard actuel (il n'a aucune raison d'avoir bouge).
function Caler-Regard($cibleYaw = -90.0) {
  $script:RegardPile = $false                                              # vrai seulement si ce calibrage reussit
  if (-not (Au-Premier-Plan)) { return }
  $ciblePitch = [Math]::Round(35.0 + (Get-Random -Minimum 0.0 -Maximum 5.0), 1)
  Basculer-F3
  Start-Sleep -Milliseconds 400
  try {
    $r = Lire-Regard
    if ($null -eq $r) { Write-Host "Regard illisible dans F3 : pas de calibrage pour ce tour."; return }
    if ($null -eq $script:DegresParPoint) {
      $sens = if ((Ecart-Angle $cibleYaw $r[0]) -ge 0) { 1 } else { -1 }
      Bouger-Souris (200 * $sens) 0; Start-Sleep -Milliseconds 250
      $r2 = Lire-Regard
      if ($null -eq $r2) { Write-Host "Regard illisible dans F3 : pas de calibrage pour ce tour."; return }
      $d = Ecart-Angle $r2[0] $r[0]
      if ([Math]::Abs($d) -lt 0.5) {
        # 09/11/2026 : jeu repris sans cliquer dedans, le clavier repond mais la souris n'est pas captee. Un clic la capte.
        Cliquer-Une-Fois
        Start-Sleep -Milliseconds 350
        Bouger-Souris (200 * $sens) 0; Start-Sleep -Milliseconds 250
        $r3 = Lire-Regard
        if ($null -eq $r3) { Write-Host "Regard illisible dans F3 : pas de calibrage pour ce tour."; return }
        $d = Ecart-Angle $r3[0] $r2[0]
        if ([Math]::Abs($d) -lt 0.5) { Stop-Recolte "la souris ne fait pas tourner la vue : clique une fois dans le jeu, puis relance"; return }
        $r2 = $r3
      }
      $script:DegresParPoint = $d / (200 * $sens)
      $r = $r2
    }
    $parPoint = [Math]::Abs($script:DegresParPoint)
    # Au plus pres que la souris permet : un point de souris est le plus petit pas possible, et F3 n'affiche qu'une decimale.
    # 0,7 pas : assez pour ne pas osciller de part et d'autre de la cible quand elle tombe entre deux points.
    $tolYaw = [Math]::Max(0.05, 0.7 * $parPoint)
    for ($n = 0; $n -lt 10; $n++) {
      $ey = Ecart-Angle $cibleYaw $r[0]; $ep = $ciblePitch - $r[1]
      if ([Math]::Abs($ey) -le $tolYaw -and [Math]::Abs($ep) -le 0.3) { $script:RegardPile = $true; Write-Host ("Regard calibre : {0:N1} / {1:N1}" -f $r[0], $r[1]); return }
      $dx = if ([Math]::Abs($ey) -le $tolYaw) { 0 } else { [int][Math]::Round($ey / $script:DegresParPoint) }
      if ($dx -eq 0 -and [Math]::Abs($ey) -gt $tolYaw) { $dx = [Math]::Sign($ey / $script:DegresParPoint) }
      # tout pres de la cible : un seul point a la fois, sinon le regard saute de -90,1 a -89,9 sans jamais lire -90,0 (09/11/2026)
      if ($dx -ne 0 -and [Math]::Abs($ey) -le 0.11) { $dx = [Math]::Sign($dx) }
      $dy = if ([Math]::Abs($ep) -le 0.3) { 0 } else { [int][Math]::Round($ep / $parPoint) }
      Bouger-Souris $dx $dy
      Start-Sleep -Milliseconds 250
      $l = Lire-Regard
      if ($null -eq $l) { Write-Host "Regard illisible dans F3 : calibrage interrompu."; return }
      $r = $l
    }
    # 10 corrections faites : la derniere lecture n'a pas encore ete jugee. A 0,15 pres, le regard reste bon pour marcher sans reculer.
    if ([Math]::Abs((Ecart-Angle $cibleYaw $r[0])) -le 0.15 -and [Math]::Abs($ciblePitch - $r[1]) -le 0.5) { $script:RegardPile = $true; Write-Host ("Regard calibre : {0:N1} / {1:N1}" -f $r[0], $r[1]); return }
    Write-Host ("Regard illisible dans F3 : calibrage pas tout a fait atteint ({0:N1} / {1:N1})." -f $r[0], $r[1])
  } finally {
    Basculer-F3
    Start-Sleep -Milliseconds 300
    $script:DerLecture = [Environment]::TickCount
  }
}

function Stop-Recolte($msg) {
  Relacher-Tout; $script:Arret = $true
  [console]::Beep(880, 250); [console]::Beep(660, 400)
  Write-Host ("Recolte arretee : {0}" -f $msg)
}

# Position lue, ou $null si illisible ou incoherente (saut de plus de 3 blocs entre deux lectures).
# Au bout de 1,5 s sans lecture valable : arret (F3 ouvert, chat ouvert, teleportation...).
function Lire-Pos {
  $mtn = [Environment]::TickCount
  $p = Lire-Coord
  $bon = $null -ne $p
  if ($bon -and $null -ne $script:DerPos) { for ($n = 0; $n -lt 3; $n++) { if ([Math]::Abs($p[$n] - $script:DerPos[$n]) -gt 3) { $bon = $false } } }
  if ($bon -and [Math]::Abs($p[1] - $script:Depart[1]) -gt 1) { $bon = $false }
  if ($bon) { $script:DerPos = $p; $script:DerLecture = $mtn; return $p }
  if ($script:DerLecture -ne 0 -and $mtn - $script:DerLecture -gt 1500) { Stop-Recolte "position illisible ou incoherente depuis 1,5 s (F3 ou chat ouvert ? teleporte ?)" }
  return $null
}

# Ligne de tiges numero $k (0 = la premiere), sur l'axe perpendiculaire aux rangees
function Colonne($k) { return $script:Depart[$script:AxePerp] + $script:SensPerp * $k * $Ecart }

# Une rangee, de cote, clic tenu, jusqu'au couloir d'en face. Le recul (touche arriere) colle au mur du dos, une fois entre
# dans la rangee : sans ca, le moindre ecart du regard ferait deriver le joueur de plus d'un bloc sur 111.
function Passage($k) {
  $aller = ($k % 2) -eq 0
  $droite = ($Sens -eq 'droite') -eq $aller
  $touche = if ($droite) { $T.droite } else { $T.gauche }
  # 1re rangee faite : le joueur a pu partir de n'importe quelle rangee, dans le couloir ou dans le 1er rang. Le couloir d'arrivee
  # se reconnait a la marche en sortant de la terre labouree ; il donne la position des deux couloirs.
  $premiere = -not $script:DepartCale; $minY = $null; $l0 = $null; $recaler = $false
  $cible = if ($aller) { $script:Depart[$script:Axe] + $script:SensAxe * ($Longueur + 1) } else { $script:Depart[$script:Axe] }
  $vers = if ($aller) { $script:SensAxe } else { -$script:SensAxe }
  $col = Colonne $k
  # Partant d'un couloir, le clic n'est tenu qu'une fois entre dans la rangee : 09/11/2026, bloque a l'entree de la 5e,
  # le regard visait le sol du couloir et le clic allait casser le bloc.
  $clic = $null -eq $script:Couloir
  Poser @($touche) $clic
  $colle = $false; $essais = 0; $depL = $null; $avecS = $null
  $tBouge = [Environment]::TickCount; $derL = $null
  while (-not $script:Arret) {
    if (Tic) {
      if ($script:Arret) { return $false }
      if ($colle) { $clic = $true }
      Poser @($touche) $clic; $colle = $false; $depL = $null; $tBouge = [Environment]::TickCount; continue
    }
    $p = Lire-Pos
    if ($null -eq $p) { Start-Sleep -Milliseconds 15; continue }
    $mtn = [Environment]::TickCount
    if ([Math]::Abs($p[$script:AxePerp] - $col) -gt 1) { Stop-Recolte ("sorti de la rangee {0} (attendu {1}, lu {2})" -f ($k + 1), $col, $p[$script:AxePerp]); return $false }
    $L = $p[$script:Axe]
    if ($premiere) {
      if ($null -eq $l0) { $l0 = $L }
      if ($null -eq $minY -or $p[1] -lt $minY) { $minY = $p[1] }
      # seulement en fin de rangee : un bloc de terre pietinee donne aussi une marche (09/11/2026 : faux couloir au 2e rang)
      if ($p[1] -gt $minY -and [Math]::Abs($L - $l0) -ge ($Longueur - 5)) {
        $recaler = $true
        break
      }
    }
    elseif (($L - $cible) * $vers -ge 0) { break }
    if ($L -ne $derL) { $derL = $L; $tBouge = $mtn }
    if ($null -eq $depL) { $depL = $L }
    # on ne recule qu'une fois entre d'un bloc dans la rangee : dans le couloir, reculer ecarterait le joueur de sa ligne
    if (-not $colle -and $L -ne $depL) { $colle = $true; $avecS = $null; $clic = $null }
    if ($colle) {
      $immobile = $mtn - $tBouge
      # Recul : tout le temps si le regard n'est pas calibre ; sinon sur les 3 premiers rangs (09/11/2026 : entre trop a l'est, le joueur
      # butait sur le coin de la pasteque suivante), quand il ne bouge plus, ou s'il a derive d'un bloc.
      $veutS = (-not $script:RegardPile) -or ([Math]::Abs($L - $depL) -le 3) -or ($immobile -gt 200) -or ($p[$script:AxePerp] -ne $col)
      # Immobile, le regard reste sur le meme bloc : on lache le clic avant que la terre ne casse.
      $veutClic = $immobile -le 400
      if ($veutS -ne $avecS -or $veutClic -ne $clic) {
        $avecS = $veutS; $clic = $veutClic
        if ($avecS) { Poser @($touche, $T.arriere) $clic } else { Poser @($touche) $clic }
      }
    }
    if ($mtn - $tBouge -gt $(if ($colle) { 1500 } else { 800 })) {
      # bloque (le plus souvent a l'entree : coin du mur ou premier fruit) : on se place au centre de la ligne de tiges avec F3
      $essais++
      if ($essais -gt 2) { Stop-Recolte ("bloque dans la rangee {0} (position {1})" -f ($k + 1), $L); return $false }
      $clic = $colle -or ($null -eq $script:Couloir)
      Poser @() $false
      Write-Host ("Rangee {0} : entree bloquee, recentrage." -f ($k + 1))
      Attendre-Stable 200
      if (-not (Centrer-Colonne $k)) { return $false }
      Poser @($touche) $clic; $colle = $false; $depL = $null; $tBouge = [Environment]::TickCount
    }
    Start-Sleep -Milliseconds 15
  }
  if ($script:Arret) { return $false }
  # Dans le couloir : on continue de cote jusqu'au mur du fond, sans clic ni recul. 09/11/2026 : arrete des l'entree du couloir,
  # le joueur etait encore en face du bout des murs et s'y cognait en allant a la rangee suivante.
  Poser @($touche) $false
  Attendre-Stable 300
  Poser @() $false
  Attendre-Stable 200
  if ($script:Arret) { return $false }
  if ($recaler) {
    # On lit le couloir une fois colle au mur du fond : la marche se franchit alors que le centre du joueur est encore
    # sur le dernier rang (09/11/2026 : couloirs reperes un bloc trop loin, Z 39 au lieu de 38).
    $p = $null
    for ($n = 0; $n -lt 20 -and $null -eq $p -and -not $script:Arret; $n++) { $p = Lire-Pos; if ($null -eq $p) { Start-Sleep -Milliseconds 40 } }
    if ($null -eq $p) { if (-not $script:Arret) { Stop-Recolte "couloir illisible en fin de rangee" }; return $false }
    $cible = $p[$script:Axe]
    $script:Depart[$script:Axe] = if ($aller) { $cible - $script:SensAxe * ($Longueur + 1) } else { $cible }
    Write-Host ("Couloirs reperes : Z {0} et Z {1}." -f $script:Depart[$script:Axe], ($script:Depart[$script:Axe] + $script:SensAxe * ($Longueur + 1)))
  }
  $script:Couloir = $cible; $script:DepartCale = $true
  return (-not $script:Arret)
}

# Place le joueur au centre de la ligne de tiges (+/- 0,15 bloc), par petits appuis, avec la position precise de F3.
function Centrer-Colonne($k) {
  $cible = (Colonne $k) + 0.5
  Basculer-F3
  Start-Sleep -Milliseconds 400
  try {
    $duree = 40; $avant = $null; $resteAvant = $null; $trace = New-Object System.Collections.Generic.List[string]
    $ecrire = { param($fin) Write-Host ("Recentrage rangee {0} ({1}) : cible {2:N2}, lu {3}" -f ($k + 1), $fin, $cible, ($trace -join ' ')) }
    for ($n = 0; $n -le 25; $n++) {
      if (Tic) { if ($script:Arret) { return $false } }
      $x = Lire-XYZ
      if ($null -eq $x) { & $ecrire 'F3 illisible'; Stop-Recolte "position precise illisible dans F3 pendant le recentrage"; return $false }
      $pos = $x[$script:AxePerp]
      $reste = ($cible - $pos) * $script:SensPerp
      $trace.Add(("{0:N2}" -f $pos))
      if ([Math]::Abs($reste) -le 0.15) { if ($n -gt 3) { & $ecrire 'reussi' }; return $true }
      if ($n -eq 25) { break }   # derniere lecture, apres le dernier appui
      if ($null -ne $avant -and [Math]::Abs($pos - $avant) -lt 0.02) { $duree = [Math]::Min(150, $duree + 20) }   # n'a pas bouge : appui plus long
      # 14/11/2026 : passe de l'autre cote du centre -> appui plus court (sinon il peut tourner autour sans jamais y tomber)
      elseif ($null -ne $resteAvant -and [Math]::Sign($reste) -ne [Math]::Sign($resteAvant)) { $duree = [Math]::Max(20, [int]($duree / 2)) }
      $avant = $pos; $resteAvant = $reste
      Poser @($(if ($reste -gt 0) { $T.avant } else { $T.arriere })) $false
      Start-Sleep -Milliseconds $duree
      Poser @() $false
      Start-Sleep -Milliseconds 350
    }
    # 14/11/2026 (rangee 8 des pasteques) : a moins de 0,3 bloc du centre, on repart plutot que de couper la recolte
    if ([Math]::Abs($reste) -le 0.3) { & $ecrire 'presque centre, on repart'; return $true }
    & $ecrire 'echec'
    Stop-Recolte ("recentrage impossible sur la rangee {0}" -f ($k + 1))
    return $false
  } finally {
    Basculer-F3
    Start-Sleep -Milliseconds 300
    $script:DerPos = $null; $script:DerLecture = [Environment]::TickCount
  }
}

function Attendre-Stable($ms) {
  $fin = [Environment]::TickCount + $ms
  while ([Environment]::TickCount -lt $fin -and -not $script:Arret) { if (Tic) { $fin = [Environment]::TickCount + $ms; continue }; Start-Sleep -Milliseconds 10 }
}

# Dans le couloir : avance (ou recule) jusqu'a la ligne de tiges $k, puis petits pas si on est alle trop loin ou pas assez.
function Aller-Colonne($k, $touche) {
  $vers = if ($touche -eq $T.avant) { 1 } else { -1 }
  Poser @($touche) $false
  $tBouge = [Environment]::TickCount; $der = $null
  while (-not $script:Arret) {
    if (Tic) { if ($script:Arret) { return $false }; Poser @($touche) $false; $tBouge = [Environment]::TickCount; continue }
    $p = Lire-Pos
    if ($null -eq $p) { Start-Sleep -Milliseconds 10; continue }
    $mtn = [Environment]::TickCount
    if ([Math]::Abs($p[$script:Axe] - $script:Couloir) -gt 1) { Stop-Recolte ("sorti du couloir (attendu {0}, lu {1})" -f $script:Couloir, $p[$script:Axe]); return $false }
    $b = $p[$script:AxePerp]
    if ($script:SensPerp -eq 0 -and $b -ne $script:Depart[$script:AxePerp]) { $script:SensPerp = [Math]::Sign($b - $script:Depart[$script:AxePerp]) }
    if ($script:SensPerp -ne 0) {
      $cible = Colonne $k
      if (($b - $cible) * $script:SensPerp * $vers -ge 0) { break }
    }
    if ($b -ne $der) { $der = $b; $tBouge = $mtn }
    if ($mtn - $tBouge -gt 1500) { Stop-Recolte "bloque dans le couloir (position $b)"; return $false }
    Start-Sleep -Milliseconds 5
  }
  if ($script:Arret) { return $false }
  Poser @() $false
  Attendre-Stable 200
  $cible = Colonne $k
  for ($n = 0; $n -lt 8 -and -not $script:Arret; $n++) {
    $p = Lire-Pos
    if ($null -eq $p) { Start-Sleep -Milliseconds 50; continue }
    $e = $p[$script:AxePerp] - $cible
    if ($e -eq 0) { return $true }
    $pas = if ($e * $script:SensPerp -gt 0) { $T.arriere } else { $T.avant }
    Poser @($pas) $false; Start-Sleep -Milliseconds 70; Poser @() $false
    Attendre-Stable 180
  }
  if (-not $script:Arret) { Stop-Recolte ("rangee {0} pas atteinte dans le couloir" -f ($k + 1)) }
  return $false
}

function Faire-Rangees($debut = 0) {
  for ($k = $debut; $k -lt $Rangees; $k++) {
    Write-Host ("rangee {0}/{1}" -f ($k + 1), $Rangees)
    if (-not (Passage $k)) { return $false }
    $script:RangeesFaites++
    Write-Host ("rangees faites : {0}" -f $script:RangeesFaites)
    if ($k -lt $Rangees - 1) { if (-not (Aller-Colonne ($k + 1) $T.avant)) { return $false } }
  }
  return $true
}

# Depuis le couloir, au bout de la derniere rangee : avance jusqu'a l'echelle, monte, entre de cote dans la 1re rangee de l'etage,
# demi-tour vers l'ouest. Le repere de l'etage du dessus part de la colonne de l'echelle, dans l'autre sens.
function Monter-Echelle {
  $colE = (Colonne ($Rangees - 1)) + $script:SensPerp * $BlocsEchelle
  $yBas = $script:DerPos[1]; $yHaut = $yBas + $HauteurEtage
  Write-Host "Echelle : montee a l'etage du dessus."
  Poser @($T.avant) $false
  $fin = [Environment]::TickCount + 10000; $tLu = [Environment]::TickCount
  while ($true) {
    if ($script:Arret) { return $false }
    if (Tic) { if ($script:Arret) { return $false }; Poser @($T.avant) $false; $fin = [Environment]::TickCount + 10000; continue }
    $p = Lire-Coord
    $mtn = [Environment]::TickCount
    if ($null -eq $p) { if ($mtn - $tLu -gt 1500) { Stop-Recolte "coordonnees illisibles sur l'echelle"; return $false }; Start-Sleep -Milliseconds 10; continue }
    $tLu = $mtn
    if ($p[1] -ge $yHaut) { break }
    if ($mtn -gt $fin) { Stop-Recolte ("echelle pas montee (position X {0} Y {1})" -f $p[$script:AxePerp], $p[1]); return $false }
    Start-Sleep -Milliseconds 10
  }
  # En haut, regard encore a l'est : de cote vers le sud, on entre directement dans le 1er rang de la rangee (demande du 09/11/2026).
  $rang1 = $script:Depart[$script:Axe] + $script:SensAxe
  Poser @($(if ($script:Sens -eq 'droite') { $T.droite } else { $T.gauche })) $false
  $fin = [Environment]::TickCount + 800
  while ([Environment]::TickCount -lt $fin -and -not $script:Arret) {
    $p = Lire-Coord
    if ($null -ne $p -and ($p[$script:Axe] - $rang1) * $script:SensAxe -ge 0) { break }
    Start-Sleep -Milliseconds 5
  }
  Poser @() $false
  if ($script:Arret) { return $false }
  Attendre-Stable 250
  $p = Lire-Coord
  if ($null -eq $p) { Start-Sleep -Milliseconds 300; $p = Lire-Coord }
  if ($null -eq $p) { Stop-Recolte "coordonnees illisibles en haut de l'echelle"; return $false }
  Write-Host ("Haut de l'echelle : X {0} Y {1} Z {2}." -f $p[0], $p[1], $p[2])
  if ($p[1] -lt $yHaut - 1 -or $p[$script:Axe] -eq $script:Depart[$script:Axe]) { Stop-Recolte ("pas entre dans la 1re rangee de l'etage du dessus (Y {0}, Z {1})" -f $p[1], $p[$script:Axe]); return $false }
  Caler-Regard $script:Cap2
  if ($script:Arret) { return $false }
  if (-not $script:RegardPile) { Stop-Recolte "demi-tour pas reussi"; return $false }
  # Nouveau repere : colonne de l'echelle, meme couloir de depart, avancer va maintenant dans l'autre sens
  $d = @(0, 0, 0)
  $d[$script:AxePerp] = $colE; $d[1] = $yHaut; $d[$script:Axe] = $script:Depart[$script:Axe]
  $script:Depart = $d
  $script:SensPerp = -$script:SensPerp
  $script:Sens = $script:Sens2
  $script:DerPos = $null; $script:DerLecture = [Environment]::TickCount
  return $true
}

function Retour-Home($base) {
  Write-Host ("Etage du dessus fini : /home {0}." -f $HomeRetour)
  if (-not (Taper-Commande "home $HomeRetour")) { return $false }
  Attendre-Stable 2500
  if ($script:Arret) { return $false }
  Couper-Vol
  $p = Lire-Coord
  if ($null -eq $p) { Start-Sleep -Milliseconds 500; $p = Lire-Coord }
  if ($null -eq $p) { Stop-Recolte "coordonnees illisibles apres /home"; return $false }
  $yEtage = $script:Depart[1]
  $script:SensPerp = -$script:SensPerp
  $script:Sens = $script:Sens1
  if ($null -eq $base) {
    # depart direct a l'etage 2 : le debut de la ferme n'est connu qu'ici, c'est l'endroit ou le /home vient de nous poser
    if ($yEtage - $p[1] -lt 2) { Stop-Recolte ("pas revenu au debut de la ferme apres /home (X {0} Y {1} Z {2})" -f $p[0], $p[1], $p[2]); return $false }
    $script:Depart = @($p); $script:DepartCale = $false
    $script:DerPos = $p; $script:DerLecture = [Environment]::TickCount
    return $true
  }
  $script:Depart = $base
  if ([Math]::Abs($p[$script:AxePerp] - $base[$script:AxePerp]) -gt 2 -or [Math]::Abs($p[$script:Axe] - $base[$script:Axe]) -gt 3 -or [Math]::Abs($p[1] - $base[1]) -gt 1) {
    Stop-Recolte ("pas revenu au debut de la ferme apres /home (X {0} Y {1} Z {2})" -f $p[0], $p[1], $p[2]); return $false
  }
  $script:DerPos = $p; $script:DerLecture = [Environment]::TickCount
  return $true
}

function Un-Tour($premier) {
  $debut = if ($premier) { $RangeeDepart - 1 } else { 0 }
  if ($premier -and $EtageDepart -eq 2) {
    if (-not (Faire-Rangees $debut)) { return $false }
    return (Retour-Home $null)
  }
  if (-not (Faire-Rangees $debut)) { return $false }
  $base = @($script:Depart)
  if (-not (Monter-Echelle)) { return $false }
  if (-not (Faire-Rangees)) { return $false }
  return (Retour-Home $base)
}
# ---------------------------- LOGIQUE-FIN ------------------------------

function Recolte {
  if ($script:PidsJeu.Count -eq 0) { Write-Host "Le jeu n'est pas lance."; return }
  if ($Rangees % 2 -ne 0) { Write-Host "Recolte arretee : il faut un nombre pair de rangees (retour du cote du depart)."; return }  if ($RangeeDepart -lt 1 -or $RangeeDepart -gt $Rangees) { Write-Host "Recolte arretee : rangee de depart hors limites."; return }
  Write-Host ("Recolte ({0}) : etage de depart {1}, rangee de depart {2}{3}." -f $Culture, $EtageDepart, $RangeeDepart, $(if ($Tours -gt 0) { ", $Tours tour(s)" } else { '' }))
  $bout = if (($RangeeDepart % 2) -eq 1) { 'nord (petit Z)' } else { 'sud (grand Z)' }
  Write-Host "Dans le jeu : F3 ferme, au debut de la rangee $RangeeDepart, cote $bout, puis $NomPause. ($NomArret = annuler)"
  while ($true) {
    if (-not (Attendre-F7)) { return }
    if (Au-Premier-Plan) { break }
    Write-Host "$NomPause recu, mais le jeu n'est pas au premier plan : clique dans le jeu puis $NomPause."
  }
  Start-Sleep -Milliseconds 300
  Detecter-Interface
  Couper-Vol
  if ($EtageDepart -eq 2) {
    $script:Sens = $script:Sens2
    Caler-Regard $script:Cap2
    if ($script:Arret) { return }
    if (-not $script:RegardPile) { Write-Host "Recolte arretee : regard pas calibre pour l'etage 2."; return }
  }
  elseif ($CalerRegard -eq 1) { Caler-Regard $script:Cap1; if ($script:Arret) { return } }
  $p0 = Lire-Coord
  if ($null -eq $p0) { Start-Sleep -Milliseconds 300; $p0 = Lire-Coord }
  if ($null -eq $p0) { Write-Host "Recolte arretee : coordonnees illisibles en haut a gauche (ferme F3, affiche-les dans Lunar)."; return }
  # La ferme est toujours orientee pareil : rangees du nord au sud (Z), rangees suivantes vers l'est a l'etage 1 et vers l'ouest a l'etage 2.
  # Le repere part de la 1re rangee, meme si le joueur commence plus loin : la colonne de l'echelle reste juste.
  $script:Axe = 2; $script:AxePerp = 0; $script:SensAxe = 1
  $script:SensPerp = if ($EtageDepart -eq 2) { -$script:Perp1 } else { $script:Perp1 }
  $script:Depart = @($p0)
  $script:Depart[0] = $p0[0] - $script:SensPerp * ($RangeeDepart - 1) * $Ecart
  $script:DerPos = $p0; $script:DerLecture = [Environment]::TickCount
  Write-Host "Recolte lancee."
  Write-Host ("Depart : X {0} Y {1} Z {2}." -f $p0[0], $p0[1], $p0[2])
  Suivre-Argent $true
  $script:Actif.Start()
  $n = 0
  while (-not $script:Arret) {
    if ($n -gt 0 -and $CalerRegard -eq 1) { Caler-Regard $script:Cap1 }
    if (-not (Un-Tour ($n -eq 0))) { break }
    $n++
    Write-Host ("recolte : tour {0} fini" -f $n)
    if ($Tours -gt 0 -and $n -ge $Tours) { Write-Host "Nombre de tours atteint."; break }
  }
  Relacher-Tout
  Suivre-Argent $true
  Write-Host ("Recolte finie : {0:N0} s actives, {1} rangees, {2} tour(s) complets." -f $script:Actif.Elapsed.TotalSeconds, $script:RangeesFaites, $n)
}

try { Recolte }
finally {
  Relacher-Tout
  Write-Host "Toutes les touches sont relachees."
}
