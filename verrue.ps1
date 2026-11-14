# =====================================================================
#  verrue.ps1 : recolte du champ de nether wart (verrues du Nether ; outil 3x3 au sol qui replante seul).
#  Lance par le menu, page Culture > Nether wart. Meme fonctionnement que ble.ps1, sans eau dans le champ.
#
#  Champ : nether wart de X 96 a 149 et de Z -149 a -86, couloirs en Z -85 (depart) et Z -150 (murs derriere).
#  Pas d'eau : un passage tous les 3 blocs, 18 passages par etage (X 97, 100, 103 ... 148).
#  Le joueur marche (regard plein nord = 180 ou plein sud = 0, environ 50 vers le bas, lu dans F3), clic gauche tenu.
#  Au bout : couloir, de cote jusqu'a la ligne suivante, demi-tour, et ainsi de suite (serpentin).
#  10 etages, couloirs en Y -2, 1, 4 ... 25 (tous les 3 blocs). Sur le sable des ames, Y lu = Y du couloir - 1.
#  Etage impair : de X 148 a X 97, fin au couloir Z -85 ; echelle en X 96 (Z -85).
#  Etage pair   : de X 97 a X 148, fin au couloir Z -85 ; echelle en X 149 (Z -85).
#  En haut de l'echelle : de cote jusqu'a la ligne d'a cote (X 97 ou X 148). Apres l'etage 10 : /home verrue.
#
#  DEPART : dans un couloir, sur la ligne d'un passage (debut du champ : X 148, Y -2, couloir Z -85), F3 ferme, outil en main.
#
#  SECURITES
#    F7 : demarrer, puis pause / reprise        F8 (ou Arreter du menu) : arret, tout est relache
#    Jeu plus au premier plan : tout est relache, puis attente de F7
#    Bloque, sorti de sa ligne, teleporte ou coordonnees illisibles : tout est relache et arret
#  Rien n'est ecrit dans le chat, sauf /home verrue a la fin de l'etage 10 (autorise par l'utilisateur le 12/11/2026)
#  et le nombre de la verification AFK si l'option est active.
# =====================================================================
param(
  [int]$Tours = 0,                 # 0 = sans limite
  [int]$EtageDepart = 0,           # 1 a 10, choisi dans le menu (0 = deduit de la position du joueur)
  [int]$PassageDepart = 0,         # 1 a 18, choisi dans le menu (0 = deduit de la position) ; les tours suivants repartent du debut
  [int]$AttenteS = 0,              # attente apres le /home, avant le tour suivant (le nether wart repousse)
  [int]$XMin = 96,                 # fixe : premier rang a l'ouest
  [int]$Passages = 18,             # fixe : 54 de large, un passage tous les 3 blocs
  [int]$ZNord = -150,              # fixe : couloir nord (fond du champ)
  [int]$ZSud = -85,                # fixe : couloir sud (depart, echelles, /home)
  [int]$YBas = -2,                 # fixe : couloir de l'etage 1
  [int]$EcartEtages = 3,           # fixe : un etage tous les 3 blocs
  [int]$Etages = 10,               # fixe
  [string]$HomeRetour = 'verrue',  # /home autorise par l'utilisateur le 12/11/2026 : ramene au debut du champ (X 148 Y -2 Z -85)
  [double]$Inclinaison = 50,       # regard vers le bas (F3), tire a +/- 1 degre a chaque passage
  [int]$SlotOutil = 1,             # slot de l'outil 3x3 (pris au demarrage et apres chaque vente)
  [int]$SlotDial = 2,              # slot du dial
  [int]$VenteTous = 0,             # vente au dial tous les N passages, dans le couloir (0 = pas de vente)
  [int]$VenteMs = 100,             # apres le clic de vente, temps avant de reprendre l'outil (court : le dial en main s'use)
  [int]$RepondreVerif = 0,         # 1 = repondre a la verification AFK (option du menu)
  [int]$TouchePause = 0x76,        # F7 par defaut
  [int]$ToucheArret = 0x77,        # F8 par defaut
  [int]$StopTP = 0,                # 1 = arret si teleporte (option du menu)
  [int]$TPBlocs = 3
)

$Dossier = Split-Path -Parent $MyInvocation.MyCommand.Path
# Outils communs (touches, pause, verification AFK, coordonnees, F3, chat) : repris de recolte.ps1 pour n'avoir qu'une seule version.
$src = Get-Content (Join-Path $Dossier 'recolte.ps1') -Raw
$i = $src.IndexOf('Add-Type -AssemblyName System.Windows.Forms'); $j = $src.IndexOf('# ---------------------------- LOGIQUE-' + 'DEBUT')   # repere coupe en deux : il ne doit exister qu'une fois dans ce fichier
Invoke-Expression ($src.Substring($i, $j - $i))
# F3 lu sur toute la hauteur de la fenetre (recolte.ps1 n'en lit que le haut, 55 %). 11/11/2026, images de diagnostic :
# avec Lunar 26.2 et ses mods, la position et le regard sont dans la colonne de droite, et quand on vise du ble F3 y
# ajoute les lignes du bloc vise (ble, age, tags) : la ligne du regard descendait sous la zone lue -> "regard illisible".
function Zones-F3 {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $c = [Interface]::Client($h)
  return @((New-Object System.Drawing.Rectangle ($c.X + [int]($c.Width * 0.45)), $c.Y, ($c.Width - [int]($c.Width * 0.45)), $c.Height),
           (New-Object System.Drawing.Rectangle $c.X, $c.Y, ([int]($c.Width * 0.62)), $c.Height))
}
# 12/11/2026, images de diagnostic : les hitbox (F3+B) des objets tombes dans le champ dessinent de fins traits blancs
# juste au-dessus de la ligne du regard ; la lecture prend alors le haut de la ligne trop tot et ne reconnait plus rien.
# F3+B se rallume a chaque lancement du jeu. Le texte de F3 est d'un gris pur (224/224/224), les traits sont
# legerement bleutes (229/230/232) : on efface tout ce qui n'est pas ce gris avant de lire. Sans resultat, lecture normale.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class FiltreF3 {
  public static Bitmap Capturer(Rectangle ecran) {
    var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb);
    using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
    Nettoyer(bmp); return bmp;
  }
  public static void Nettoyer(Bitmap bmp) {
    var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadWrite, PixelFormat.Format24bppRgb);
    var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length);
    for (int y = 0; y < bmp.Height; y++) for (int x = 0, o = y * bd.Stride; x < bmp.Width; x++, o += 3) {
      int r = b[o + 2], v = b[o + 1], bl = b[o];
      if (!(r == v && v == bl && Math.Abs(r - 224) <= 4)) { b[o] = 0; b[o + 1] = 0; b[o + 2] = 0; }
    }
    Marshal.Copy(b, 0, bd.Scan0, b.Length); bmp.UnlockBits(bd);
  }
}
'@
function Lire-F3($motif, $groupes) {
  for ($n = 0; $n -lt 6; $n++) {
    $zones = Zones-F3
    if ($script:ReglageF3) { $essais = @(, $script:ReglageF3) }
    else { $essais = @(@(0, $script:Gui), @(0, 3), @(0, 2), @(0, 4), @(1, $script:Gui), @(1, 3), @(1, 2), @(1, 4), @(1, 1)) }
    foreach ($e in $essais) {
      foreach ($filtre in $true, $false) {                                  # d'abord filtre, puis lecture normale en secours
        if ($filtre) { $bmp = [FiltreF3]::Capturer($zones[$e[0]]); try { $lignes = [Glyphes]::Lignes($bmp, $SeuilF3, $e[1]) } finally { $bmp.Dispose() } }
        else { $lignes = [Glyphes]::Lignes($zones[$e[0]], $SeuilF3, $e[1]) }
        foreach ($ligne in $lignes) {
          $m = [regex]::Match($ligne, $motif)
          if ($m.Success) {
            if (-not $script:ReglageF3) { $script:ReglageF3 = $e }
            $inv = [Globalization.CultureInfo]::InvariantCulture
            return @(1..$groupes | ForEach-Object { [double]::Parse($m.Groups[$_].Value, $inv) })
          }
        }
      }
    }
    Start-Sleep -Milliseconds 150
  }
  return $null
}
# Journal des deplacements fins (centrage, petits pas dans le couloir) : diagnostics\verrue-deplacements.log
function Noter($t) { try { $d = Join-Path $Dossier 'diagnostics'; New-Item -ItemType Directory -Force $d | Out-Null; Add-Content (Join-Path $d 'verrue-deplacements.log') ("{0:dd/MM HH:mm:ss.fff} {1}" -f (Get-Date), $t) } catch { } }
# Image de ce que montre F3 quand le regard est illisible (diagnostics\verrue-f3-illisible-N.png, 5 au plus par session)
$script:ImagesF3 = 0
function Image-F3 {
  if ($script:ImagesF3 -ge 5) { return }
  $script:ImagesF3++
  try {
    $h = [IntPtr]::Zero
    foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
    $z = [Interface]::Client($h)                                            # toute la fenetre : les deux colonnes de F3
    $bmp = New-Object System.Drawing.Bitmap $z.Width, $z.Height; $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($z.Location, [System.Drawing.Point]::Empty, $z.Size); $g.Dispose()
    $d = Join-Path $Dossier 'diagnostics'; New-Item -ItemType Directory -Force $d | Out-Null
    $bmp.Save((Join-Path $d ("verrue-f3-illisible-{0}.png" -f $script:ImagesF3))); $bmp.Dispose()
  } catch { }
}
# Comme celui de recolte.ps1, mais retient qu'il y a eu une pause ou une verification AFK : la vue a pu bouger,
# le demi-tour suivant se refera avec F3 au lieu du demi-tour sec.
$script:Recaler = $true
function Tic {
  if (Surveiller-Verification) { $script:Recaler = $true; return $true }
  if (Verifier) { $script:Recaler = $true; return $true }
  Suivre-Argent
  return $false
}
# Appui sur la touche d'un slot (touches du jeu, lues dans ses reglages)
function Appuyer-Slot($n) { $sc = $script:Slots[$n - 1]; [Entree]::Touche($sc, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 25 -Maximum 45); [Entree]::Touche($sc, $false) }

# ---------------------------- LOGIQUE-DEBUT ---------------------------- (testee hors du jeu avec un champ simule)
$script:DerPos = $null; $script:DerLecture = 0
$script:YEtage = $YBas; $script:Couloir = $ZSud; $script:PassagesFaits = 0; $script:PeutReessayer = $false; $script:Decale = $false
$script:DegresParPoint = $null                                            # mesure au premier calage du regard
$XMax = $XMin + 3 * $Passages - 1                                          # dernier rang a l'est (149)
# Lignes des passages : le milieu de chaque groupe de 3 rangs. Etage impair d'est en ouest (X 148 ... 97), pair a l'envers.
$script:LignesPair = @(for ($u = 0; $u -lt $Passages; $u++) { $XMin + 3 * $u + 1 })
$script:LignesImpair = @($script:LignesPair[($Passages - 1)..0])
function Lignes($etage) { if ($etage % 2 -eq 1) { return $script:LignesImpair } else { return $script:LignesPair } }
function Y-Etage($etage) { return $YBas + $EcartEtages * ($etage - 1) }
# Passage k : les pairs partent du couloir sud (Z -85) vers le nord (180), les impairs du couloir nord vers le sud (0).
function Cap-Passage($k) { if ($k % 2 -eq 0) { return 180.0 } else { return 0.0 } }
# Etage lu sur Y : dans le couloir, Y du couloir ; sur le sable des ames (plus bas), un de moins. 0 si aucun etage.
function Etage-De-Y($y) { for ($e = 1; $e -le $Etages; $e++) { $d = (Y-Etage $e) - $y; if ($d -ge 0 -and $d -le 1) { return $e } }; return 0 }

# Mouvement de souris compte : pendant un demi-tour fait avec F3, le total donne le nombre exact de points pour 180 degres.
$script:CumulX = 0; $script:PtsSudNord = $null
function Tourner($dx, $dy) { $script:CumulX += $dx; Bouger-Souris $dx $dy }

function Ecart-Angle($cible, $a) { $d = ($cible - $a) % 360; if ($d -gt 180) { $d -= 360 }; if ($d -lt -180) { $d += 360 }; return $d }
# Regard plein sud (0) : l'est (X croissants) est a gauche. Regard plein nord (180) : a droite.
function Touche-Est($cap) { if ([Math]::Abs((Ecart-Angle 0 $cap)) -lt 90) { return $T.gauche } else { return $T.droite } }
function Touche-Ouest($cap) { if ((Touche-Est $cap) -eq $T.gauche) { return $T.droite } else { return $T.gauche } }

function Stop-Recolte($msg) {
  Relacher-Tout; $script:Arret = $true
  [console]::Beep(880, 250); [console]::Beep(660, 400)
  Write-Host ("Recolte arretee : {0}" -f $msg)
}

function Attendre-Stable($ms) {
  $fin = [Environment]::TickCount + $ms
  while ([Environment]::TickCount -lt $fin -and -not $script:Arret) { if (Tic) { $fin = [Environment]::TickCount + $ms; continue }; Start-Sleep -Milliseconds 10 }
}

# Position lue, ou $null si illisible ou incoherente (saut de plus de 3 blocs, ou plus a la hauteur de l'etage).
# Au bout de 1,5 s sans lecture valable : arret (F3 ouvert, chat ouvert, teleportation...).
function Lire-Pos {
  $mtn = [Environment]::TickCount
  $p = Lire-Coord
  $bon = $null -ne $p
  if ($bon -and $null -ne $script:DerPos) { for ($n = 0; $n -lt 3; $n++) { if ([Math]::Abs($p[$n] - $script:DerPos[$n]) -gt 3) { $bon = $false } } }
  if ($bon) { $dy = $script:YEtage - $p[1]; if ($dy -lt 0 -or $dy -gt 1) { $bon = $false } }   # sur le sable des ames, Y est un de moins que dans le couloir
  if ($bon) { $script:DerPos = $p; $script:DerLecture = $mtn; return $p }
  if ($script:DerLecture -ne 0 -and $mtn - $script:DerLecture -gt 1500) { Stop-Recolte "position illisible ou incoherente depuis 1,5 s (F3 ou chat ouvert ? teleporte ?)" }
  return $null
}

# Lecture du regard avec deux secours. 11/11/2026 : "Regard illisible" en X 4 alors que les demi-tours d'avant avaient marche.
#  1) l'appui sur F3 a pu se perdre : on rappuie (et on rappuie encore si ce n'etait pas ca, pour que F3 reste ouvert) ;
#  2) le fond derriere le texte a pu etre trop clair : on regarde plus haut, puis ailleurs, et on relit.
function Lire-Regard-Sur {
  $r = Lire-Regard
  if ($null -ne $r) { return $r }
  Image-F3
  Basculer-F3; Start-Sleep -Milliseconds 450
  $r = Lire-Regard
  if ($null -ne $r) { Write-Host "Regard relu apres un nouvel appui sur F3."; return $r }
  Basculer-F3; Start-Sleep -Milliseconds 450
  $pt = if ($null -ne $script:DegresParPoint) { [Math]::Abs($script:DegresParPoint) } else { 0.15 }
  foreach ($m in @(@(0, -35), @(45, 0), @(-90, 0))) {
    if ($script:Arret) { return $null }
    Tourner ([int]($m[0] / $pt)) ([int]($m[1] / $pt)); Start-Sleep -Milliseconds 350
    $r = Lire-Regard
    if ($null -ne $r) { Write-Host "Regard relu en regardant ailleurs."; return $r }
  }
  Image-F3
  return $null
}

# F3 ouvert : tourne la vue pile sur $cibleYaw (0 sud, 180 nord) et sur l'inclinaison $ciblePitch. $true si c'est atteint.
function Ajuster-Regard($cibleYaw, $ciblePitch) {
  $r = Lire-Regard-Sur
  if ($null -eq $r) { Write-Host "Regard illisible dans F3."; return $false }
  if ($null -eq $script:DegresParPoint) {
    $sens = if ((Ecart-Angle $cibleYaw $r[0]) -ge 0) { 1 } else { -1 }
    Tourner (200 * $sens) 0; Start-Sleep -Milliseconds 250
    $r2 = Lire-Regard-Sur
    if ($null -eq $r2) { Write-Host "Regard illisible dans F3."; return $false }
    $d = Ecart-Angle $r2[0] $r[0]
    if ([Math]::Abs($d) -lt 0.5) {
      # jeu repris sans cliquer dedans : le clavier repond mais la souris n'est pas captee. Un clic la capte (meme cas que les pasteques).
      Cliquer-Une-Fois
      Start-Sleep -Milliseconds 350
      Tourner (200 * $sens) 0; Start-Sleep -Milliseconds 250
      $r3 = Lire-Regard-Sur
      if ($null -eq $r3) { Write-Host "Regard illisible dans F3."; return $false }
      $d = Ecart-Angle $r3[0] $r2[0]
      if ([Math]::Abs($d) -lt 0.5) { Stop-Recolte "la souris ne fait pas tourner la vue : clique une fois dans le jeu, puis relance"; return $false }
      $r2 = $r3
    }
    $script:DegresParPoint = $d / (200 * $sens)
    $r = $r2
  }
  $parPoint = [Math]::Abs($script:DegresParPoint)
  $tolYaw = [Math]::Max(0.05, 0.7 * $parPoint)
  for ($n = 0; $n -lt 12; $n++) {
    if ($script:Arret) { return $false }
    $ey = Ecart-Angle $cibleYaw $r[0]; $ep = $ciblePitch - $r[1]
    if ([Math]::Abs($ey) -le $tolYaw -and [Math]::Abs($ep) -le 0.3) { return $true }
    $dx = if ([Math]::Abs($ey) -le $tolYaw) { 0 } else { [int][Math]::Round($ey / $script:DegresParPoint) }
    if ($dx -eq 0 -and [Math]::Abs($ey) -gt $tolYaw) { $dx = [Math]::Sign($ey / $script:DegresParPoint) }
    if ($dx -ne 0 -and [Math]::Abs($ey) -le 0.11) { $dx = [Math]::Sign($dx) }   # tout pres : un point a la fois
    $dy = if ([Math]::Abs($ep) -le 0.3) { 0 } else { [int][Math]::Round($ep / $parPoint) }
    Tourner $dx $dy
    Start-Sleep -Milliseconds 250
    $l = Lire-Regard-Sur
    if ($null -eq $l) { Write-Host "Regard illisible dans F3."; return $false }
    $r = $l
  }
  return ([Math]::Abs((Ecart-Angle $cibleYaw $r[0])) -le 0.15 -and [Math]::Abs($ciblePitch - $r[1]) -le 0.5)
}

# Dans le couloir, sur la ligne du passage : F3 ouvert, regard cale (demi-tour compris), puis joueur ecarte du bord du bloc.
# 11/11/2026 : les hitbox (F3+B) des objets au sol passaient derriere la ligne du regard et la rendaient illisible :
# l'utilisateur les desactive.
function Preparer-Passage($col, $cap) {
  Poser @() $false
  Attendre-Stable 150
  if ($script:Arret) { return $false }
  Basculer-F3
  Start-Sleep -Milliseconds 400
  try {
    $incl = [Math]::Round($Inclinaison - 1 + (Get-Random -Minimum 0.0 -Maximum 2.0), 1)
    if (-not (Ajuster-Regard $cap $incl)) { if (-not $script:Arret) { Stop-Recolte ("regard pas cale vers {0} dans F3" -f $(if ($cap -eq 0) { 'le sud' } else { 'le nord' })) }; return $false }
    $est = Touche-Est $cap; $ouest = Touche-Ouest $cap
    # Pas besoin d'etre pile au centre (remarque de l'utilisateur, 11/11/2026) : il suffit de ne pas etre au bord du bloc,
    # le regard cale fait aller tout droit. Bon des que X est entre 0,2 et 0,8 dans le bloc de la ligne.
    $cible = $col + 0.5; $duree = 40; $avant = $null; $x = $null
    # 12/11/2026 : une lecture ratee arretait la boucle sans aucun appui ("pas sur la ligne" sans avoir bouge) : on relit.
    $rates = 0; $plafond = 400; $ms = 400
    for ($n = 0; $n -lt 12; $n++) {
      if (Tic) { if ($script:Arret) { return $false } }
      $x = Lire-XYZ
      if ($null -eq $x) { $rates++; Noter ("centrage X {0} : lecture XYZ ratee ({1})" -f $col, $rates); if ($rates -ge 4) { break }; Start-Sleep -Milliseconds 200; $n--; continue }
      $reste = $cible - $x[0]
      if ([Math]::Abs($reste) -le 0.3) { if ($n -gt 0) { Noter ("centrage X {0} : X {1:N2}, bon" -f $col, $x[0]) }; return $true }
      if ($null -ne $avant -and [Math]::Abs($x[0] - $avant) -lt 0.02) { $duree = [Math]::Min(150, $duree + 20) }   # n'a pas bouge : appui plus long
      # 12/11/2026 (journal) : 115,02 -> 116,11 -> 114,48 -> 116,65 -> 113,94 -> 117,74... chaque correction depassait
      # davantage. Ligne depassee : l'appui suivant ne peut plus faire plus de la moitie du precedent.
      if ($null -ne $avant -and [Math]::Sign($cible - $avant) -ne [Math]::Sign($reste)) { $plafond = [Math]::Max(20, [int]($ms / 2)); $duree = [Math]::Min($duree, $plafond) }
      $avant = $x[0]
      $ms = [Math]::Min($plafond, [Math]::Max($duree, [Math]::Min(400, [int](1000 * [Math]::Abs($reste) / 4.3) - 40)))   # loin : un appui plus long
      Noter ("centrage X {0} : X {1:N2}, appui {2} {3} ms" -f $col, $x[0], $(if ($reste -gt 0) { 'est' } else { 'ouest' }), $ms)
      Poser @($(if ($reste -gt 0) { $est } else { $ouest })) $false
      Start-Sleep -Milliseconds $ms
      Poser @() $false
      Start-Sleep -Milliseconds 350
    }
    # Pas reussi a s'eloigner du bord : on part quand meme si on est sur la ligne, le passage se recale s'il derive d'un bloc.
    if ($null -eq $x) { $x = Lire-XYZ }
    if ($null -ne $x -and [Math]::Floor($x[0]) -eq $col) { Write-Host ("Centrage approximatif sur la ligne X {0} (X {1:N2}) : on part quand meme." -f $col, $x[0]); return $true }
    $lu = if ($null -ne $x) { "{0:N2}" -f $x[0] } else { 'illisible' }
    # 12/11/2026 : arret en X 130,46 au lieu de 133 alors que le couloir est libre (le serveur a sans doute renvoye le
    # joueur en arriere : inventaire plein, 481 objets au sol). Premiere fois : on le signale et Faire-Etage reessaie.
    if ($script:PeutReessayer) { $script:Decale = $true; Write-Host ("Pas sur la ligne X {0} (X lu dans F3 : {1}) : nouvel essai." -f $col, $lu); return $false }
    Image-F3
    Stop-Recolte ("pas sur la ligne X {0} au depart du passage (X lu dans F3 : {1})" -f $col, $lu)
    return $false
  } finally {
    Basculer-F3
    Start-Sleep -Milliseconds 300
    $script:DerPos = $null; $script:DerLecture = [Environment]::TickCount
  }
}

# Un passage : avance clic tenu jusqu'au couloir d'en face. Le clic est lache sur les 2 derniers rangs (le regard
# viserait le sol du couloir) et des que le joueur ne bouge plus (sinon la terre labouree finirait par casser).
function Passage($col, $cap) {
  $sud = [Math]::Abs((Ecart-Angle 0 $cap)) -lt 90
  $vers = if ($sud) { 1 } else { -1 }
  $fin = if ($sud) { $ZSud } else { $ZNord }
  $lacher = if ($sud) { $ZSud - 2 } else { $ZNord + 2 }
  $est = Touche-Est $cap; $ouest = Touche-Ouest $cap
  $clic = $true; $corr = $null; $derZ = $null; $tBouge = [Environment]::TickCount; $finCorr = 0
  Poser @($T.avant) $true
  while (-not $script:Arret) {
    if (Tic) {
      if ($script:Arret) { return $false }
      $corr = $null; Poser @($T.avant) $clic; $tBouge = [Environment]::TickCount; continue
    }
    $p = Lire-Pos
    if ($null -eq $p) { Start-Sleep -Milliseconds 15; continue }
    $mtn = [Environment]::TickCount
    if ([Math]::Abs($p[0] - $col) -gt 1) { Stop-Recolte ("sorti de la ligne X {0} (lu X {1}, Z {2})" -f $col, $p[0], $p[2]); return $false }
    $z = $p[2]
    if (($z - $fin) * $vers -ge 0) { break }
    if ($z -ne $derZ) { $derZ = $z; $tBouge = $mtn }
    $immobile = $mtn - $tBouge
    if ($immobile -gt 1500) { Stop-Recolte ("bloque dans le passage X {0} (Z {1})" -f $col, $z); return $false }
    $veutClic = (($z - $lacher) * $vers -lt 0) -and ($immobile -le 400)
    # derive d'un bloc sur le cote : on revient sur la ligne en marchant, et on continue 80 ms une fois revenu
    # pour ne pas rester au bord du bloc
    $veutCorr = if ($p[0] -gt $col) { $ouest } elseif ($p[0] -lt $col) { $est } else { $null }
    if ($null -ne $veutCorr) { $finCorr = $mtn + 80 } elseif ($null -ne $corr -and $mtn -lt $finCorr) { $veutCorr = $corr }
    if ($veutClic -ne $clic -or $veutCorr -ne $corr) {
      $clic = $veutClic; $corr = $veutCorr
      $touches = @($T.avant); if ($null -ne $corr) { $touches += $corr }
      Poser $touches $clic
    }
    Start-Sleep -Milliseconds 15
  }
  if ($script:Arret) { return $false }
  # Dans le couloir : encore un instant contre le mur du fond, puis arret
  Poser @($T.avant) $false
  Attendre-Stable 150
  Poser @() $false
  Attendre-Stable 200
  $script:Couloir = $fin
  return (-not $script:Arret)
}

# Dans le couloir, de cote jusqu'a la ligne $col (regard encore dans le sens du passage qui vient de finir).
function Aller-Ligne($col, $cap) {
  $p = $script:DerPos
  if ($null -eq $p) { $p = Lire-Pos }
  if ($null -eq $p) { if (-not $script:Arret) { Stop-Recolte "position illisible dans le couloir" }; return $false }
  $vers = [Math]::Sign($col - $p[0])
  $touche = if ($vers -gt 0) { Touche-Est $cap } else { Touche-Ouest $cap }
  # 12/11/2026 20:24 : en haut de l'echelle (X 147 pour X 148), la touche tenue pour 1 seul bloc a glisse jusqu'en X 149,
  # sur l'echelle (on redescend, Y faux, arret). A 1 bloc pres : seulement les petits pas ci-dessous.
  if ([Math]::Abs($col - $p[0]) -ge 2) {
    Poser @($touche) $false
    $tBouge = [Environment]::TickCount; $der = $null
    while (-not $script:Arret) {
      if (Tic) { if ($script:Arret) { return $false }; Poser @($touche) $false; $tBouge = [Environment]::TickCount; continue }
      $p = Lire-Pos
      if ($null -eq $p) { Start-Sleep -Milliseconds 10; continue }
      $mtn = [Environment]::TickCount
      if ([Math]::Abs($p[2] - $script:Couloir) -gt 1) { Stop-Recolte ("sorti du couloir Z {0} (lu Z {1})" -f $script:Couloir, $p[2]); return $false }
      if (($p[0] - $col) * $vers -ge 0) { break }
      if ($p[0] -ne $der) { $der = $p[0]; $tBouge = $mtn }
      if ($mtn - $tBouge -gt 1500) { Stop-Recolte ("bloque dans le couloir (X {0}, Z {1})" -f $p[0], $p[2]); return $false }
      Start-Sleep -Milliseconds 5
    }
    if ($script:Arret) { return $false }
    Poser @() $false
    Attendre-Stable 200
  }
  # Petits pas vers la ligne. 12/11/2026 : "ligne X 133 pas atteinte" (8 pas de 70 ms n'avaient pas suffi) : plus de pas,
  # et un pas plus long tant que X ne change pas (on repart court si on a depasse la ligne).
  $duree = 70; $avant = $null
  for ($n = 0; $n -lt 16 -and -not $script:Arret; $n++) {
    $p = Lire-Pos
    if ($null -eq $p) { Start-Sleep -Milliseconds 50; continue }
    $e = $p[0] - $col
    if ($e -eq 0) { return $true }
    if ($null -ne $avant) { if ($p[0] -eq $avant[0]) { $duree = [Math]::Min(250, $duree + 40) } elseif ([Math]::Sign($p[0] - $col) -ne [Math]::Sign($avant[0] - $col)) { $duree = 70 } }
    $avant = $p
    Noter ("couloir vers X {0} : X {1} Z {2}, petit pas {3} {4} ms" -f $col, $p[0], $p[2], $(if ($e -gt 0) { 'ouest' } else { 'est' }), $duree)
    Poser @($(if ($e -gt 0) { Touche-Ouest $cap } else { Touche-Est $cap })) $false; Start-Sleep -Milliseconds $duree; Poser @() $false
    Attendre-Stable 180
  }
  if (-not $script:Arret) { $p = $script:DerPos; Image-F3; Stop-Recolte ("ligne X {0} pas atteinte dans le couloir (lu X {1}, Z {2})" -f $col, $(if ($p) { $p[0] } else { '?' }), $(if ($p) { $p[2] } else { '?' })) }
  return $false
}

# Vente dans le couloir, a l'arret : dial, un clic gauche, puis retour a l'outil.
$script:Ventes = 0
function Vendre($etage, $k) {
  Poser @() $false
  Attendre-Stable 150
  if ($script:Arret -or -not (Au-Premier-Plan)) { return }
  Appuyer-Slot $SlotDial
  Start-Sleep -Milliseconds (Get-Random -Minimum 120 -Maximum 180)
  Cliquer-Une-Fois
  Start-Sleep -Milliseconds $VenteMs
  Appuyer-Slot $SlotOutil
  Start-Sleep -Milliseconds 120
  $script:Ventes++
  Write-Host ("vente au dial ({0}, etage {1} apres le passage {2})" -f $script:Ventes, $etage, ($k + 1))
}

function Faire-Etage($etage, $debut) {
  $lignes = Lignes $etage
  for ($k = $debut; $k -lt $Passages; $k++) {
    $cap = Cap-Passage $k
    if ($k -gt $debut) { if (-not (Aller-Ligne $lignes[$k] (180.0 - $cap))) { return $false } }
    $script:PeutReessayer = $true; $script:Decale = $false
    $ok = Preparer-Passage $lignes[$k] $cap
    $script:PeutReessayer = $false
    if (-not $ok -and $script:Decale -and -not $script:Arret) {
      # pas reste sur la ligne : on laisse le serveur se calmer, on revient sur la ligne et on recommence une fois
      Attendre-Stable 1500
      if (-not (Aller-Ligne $lignes[$k] $cap)) { return $false }
      $ok = Preparer-Passage $lignes[$k] $cap
    }
    if (-not $ok) { return $false }
    Write-Host ("passage {0}/{1} (etage {2}, X {3})" -f ($k + 1), $Passages, $etage, $lignes[$k])
    if (-not (Passage $lignes[$k] $cap)) { return $false }
    $script:PassagesFaits++
    Write-Host ("passages faits : {0}" -f $script:PassagesFaits)
    if ($VenteTous -gt 0 -and (($k + 1) % $VenteTous) -eq 0) { Vendre $etage $k; if ($script:Arret) { return $false } }
  }
  return $true
}

# Fin d'un etage, couloir sud (Z -85), regard au sud : l'echelle est juste a cote, en X 96 (etage impair, fini en X 97)
# ou en X 149 (etage pair, fini en X 148). Avancer et aller vers elle poussent contre le mur ou elle est posee, donc
# on monte. En haut : de cote dans l'autre sens jusqu'a la ligne d'a cote (meme X qu'en bas), premier passage de l'etage.
function Monter-Echelle($etage) {
  $haut = Y-Etage ($etage + 1)
  $cap = Cap-Passage ($Passages - 1)                                       # sens du dernier passage
  $col = (Lignes $etage)[$Passages - 1]
  $xEchelle = if ($etage % 2 -eq 1) { $XMin } else { $XMax }
  $vers = if ($xEchelle -lt $col) { Touche-Ouest $cap } else { Touche-Est $cap }
  $retour = if ($xEchelle -lt $col) { Touche-Est $cap } else { Touche-Ouest $cap }
  $sensRetour = [Math]::Sign($col - $xEchelle)
  Write-Host ("Echelle (X {0}) : montee a l'etage {1}." -f $xEchelle, ($etage + 1))
  Poser @($T.avant, $vers) $false
  $fin = [Environment]::TickCount + 10000; $tLu = [Environment]::TickCount
  while ($true) {
    if ($script:Arret) { return $false }
    if (Tic) { if ($script:Arret) { return $false }; Poser @($T.avant, $vers) $false; $fin = [Environment]::TickCount + 10000; continue }
    $p = Lire-Coord
    $mtn = [Environment]::TickCount
    if ($null -eq $p) { if ($mtn - $tLu -gt 1500) { Stop-Recolte "coordonnees illisibles sur l'echelle"; return $false }; Start-Sleep -Milliseconds 10; continue }
    $tLu = $mtn
    if ($p[1] -ge $haut) { break }
    if ($mtn -gt $fin) { Stop-Recolte ("echelle pas montee (X {0} Y {1} Z {2})" -f $p[0], $p[1], $p[2]); return $false }
    Start-Sleep -Milliseconds 10
  }
  $col2 = (Lignes ($etage + 1))[0]
  Poser @($retour) $false
  $fin = [Environment]::TickCount + 1500
  while ([Environment]::TickCount -lt $fin -and -not $script:Arret) {
    $p = Lire-Coord
    if ($null -ne $p -and ($p[0] - $col2) * $sensRetour -ge 0) { break }
    Start-Sleep -Milliseconds 5
  }
  Poser @() $false
  if ($script:Arret) { return $false }
  Attendre-Stable 250
  $p = Lire-Coord
  if ($null -eq $p) { Start-Sleep -Milliseconds 300; $p = Lire-Coord }
  if ($null -eq $p) { Stop-Recolte "coordonnees illisibles en haut de l'echelle"; return $false }
  Write-Host ("Haut de l'echelle : X {0} Y {1} Z {2}." -f $p[0], $p[1], $p[2])
  if ($p[1] -ne $haut -or [Math]::Abs($p[0] - $col2) -gt 1 -or [Math]::Abs($p[2] - $ZSud) -gt 1) {
    Stop-Recolte ("pas arrive au debut de l'etage {0} (attendu X {1} Y {2} Z {3})" -f ($etage + 1), $col2, $haut, $ZSud); return $false
  }
  $script:YEtage = $haut; $script:Couloir = $ZSud
  $script:DerPos = $p; $script:DerLecture = [Environment]::TickCount
  if ($p[0] -ne $col2) { return (Aller-Ligne $col2 $cap) }
  return $true
}

function Retour-Home {
  Write-Host ("Etage {0} fini : /home {1}." -f $Etages, $HomeRetour)
  if (-not (Taper-Commande "home $HomeRetour")) { return $false }
  Attendre-Stable 2500
  if ($script:Arret) { return $false }
  Couper-Vol
  $p = Lire-Coord
  if ($null -eq $p) { Start-Sleep -Milliseconds 500; $p = Lire-Coord }
  if ($null -eq $p) { Stop-Recolte "coordonnees illisibles apres /home"; return $false }
  $col = (Lignes 1)[0]
  if ($p[1] -ne $YBas -or [Math]::Abs($p[0] - $col) -gt 1 -or [Math]::Abs($p[2] - $ZSud) -gt 1) {
    Stop-Recolte ("pas revenu au debut du champ apres /home (X {0} Y {1} Z {2}) : pose /sethome {3} en X {4} Y {5} Z {6}" -f $p[0], $p[1], $p[2], $HomeRetour, $col, $YBas, $ZSud); return $false
  }
  $script:YEtage = $YBas; $script:Couloir = $ZSud
  $script:DerPos = $p; $script:DerLecture = [Environment]::TickCount
  if ($p[0] -ne $col) { return (Aller-Ligne $col (Cap-Passage 0)) }
  return $true
}

function Attendre-Repousse {
  if ($AttenteS -le 0) { return $true }
  Write-Host ("Attente de {0} s avant le tour suivant." -f $AttenteS)
  $fin = [Environment]::TickCount + 1000 * $AttenteS
  while ([Environment]::TickCount -lt $fin -and -not $script:Arret) {
    if (Tic) { if ($script:Arret) { return $false } }
    Start-Sleep -Milliseconds 100
  }
  return (-not $script:Arret)
}

function Un-Tour($etage, $debut) {
  for ($e = $etage; $e -le $Etages; $e++) {
    if (-not (Faire-Etage $e $debut)) { return $false }
    if ($e -lt $Etages) { if (-not (Monter-Echelle $e)) { return $false } }
    $debut = 0
  }
  return (Retour-Home)
}

# Depart a cote de la ligne choisie, dans le bon couloir : regard cale dans le sens du passage (F3), puis de cote jusqu'a la ligne.
function Aller-Au-Depart($etage, $k) {
  $cap = Cap-Passage $k
  $col = (Lignes $etage)[$k]
  Write-Host ("Pas encore sur la ligne du passage : la macro va en X {0}." -f $col)
  Basculer-F3
  Start-Sleep -Milliseconds 400
  try {
    if (-not (Ajuster-Regard $cap $Inclinaison)) { if (-not $script:Arret) { Stop-Recolte "regard pas cale dans F3 au depart" }; return $false }
  } finally {
    Basculer-F3
    Start-Sleep -Milliseconds 300
    $script:DerPos = $null; $script:DerLecture = [Environment]::TickCount
  }
  return (Aller-Ligne $col $cap)
}

# Ou se placer pour un passage : @(X, Z du couloir, Y du couloir)
function Place-Passage($etage, $k) { return @((Lignes $etage)[$k], $(if ($k % 2 -eq 0) { $ZSud } else { $ZNord }), (Y-Etage $etage)) }

# D'ou part le joueur. Depart choisi dans le menu : on verifie qu'il y est. Sinon : etage par Y, passage par X, couloir par Z.
# $null (et un message) si ce n'est pas un depart possible.
function Trouver-Depart($p) {
  if ($EtageDepart -ge 1 -and $PassageDepart -ge 1) {
    $etage = [Math]::Min($Etages, $EtageDepart); $k = [Math]::Min($Passages, $PassageDepart) - 1
    $pl = Place-Passage $etage $k
    # Dans le bon couloir, a quelques blocs de la ligne : la macro y va seule. Y : celui du couloir (ou un de moins sur le sable des ames).
    $dy = $pl[2] - $p[1]
    if ($dy -lt 0 -or $dy -gt 1 -or [Math]::Abs($p[0] - $pl[0]) -gt 8 -or [Math]::Abs($p[2] - $pl[1]) -gt 1) {
      Write-Host ("Recolte arretee : pour l'etage {0}, passage {1}, place-toi en X {2} Y {3} Z {4} (tu es en X {5} Y {6} Z {7})." -f $etage, ($k + 1), $pl[0], $pl[2], $pl[1], $p[0], $p[1], $p[2])
      return $null
    }
    return @($etage, $k, $pl[1])
  }
  $etage = Etage-De-Y $p[1]
  if ($etage -eq 0) { Write-Host ("Recolte arretee : tu n'es a aucun etage (Y {0} ; couloirs en Y {1}, {2} ... {3})." -f $p[1], (Y-Etage 1), (Y-Etage 2), (Y-Etage $Etages)); return $null }
  $lignes = Lignes $etage
  $k = [array]::IndexOf($lignes, [int]$p[0])
  if ($k -lt 0) { Write-Host ("Recolte arretee : X {0} n'est pas la ligne d'un passage. Debut de l'etage {1} : X {2}, couloir Z {3}." -f $p[0], $etage, $lignes[0], $ZSud); return $null }
  $sudC = [Math]::Abs($p[2] - $ZSud) -le 1; $nordC = [Math]::Abs($p[2] - $ZNord) -le 1
  if (-not $nordC -and -not $sudC) { Write-Host ("Recolte arretee : place-toi dans un couloir (Z {0} ou Z {1}), pas au milieu du champ (Z {2})." -f $ZSud, $ZNord, $p[2]); return $null }
  if ((($k % 2) -eq 0) -ne $sudC) { Write-Host ("Recolte arretee : le passage {0} de l'etage {1} (X {2}) part du couloir Z {3}." -f ($k + 1), $etage, $lignes[$k], $(if ($k % 2 -eq 0) { $ZSud } else { $ZNord })); return $null }
  return @($etage, $k, $(if ($sudC) { $ZSud } else { $ZNord }))
}
# ---------------------------- LOGIQUE-FIN ------------------------------

function Verrue {
  if ($script:PidsJeu.Count -eq 0) { Write-Host "Le jeu n'est pas lance."; return }
  if ($SlotOutil -eq $SlotDial) { Write-Host "Recolte arretee : l'outil et le dial sont regles sur le meme slot."; return }
  Write-Host ("Recolte (nether wart) : {0}{1}, {2}." -f $(if ($Tours -gt 0) { "$Tours tour(s)" } else { 'tours sans limite' }), $(if ($AttenteS -gt 0) { ", attente de $AttenteS s entre deux tours" } else { '' }),
    $(if ($VenteTous -gt 0) { "vente au dial (slot $SlotDial) tous les $VenteTous passages" } else { 'pas de vente' }))
  if ($EtageDepart -ge 1 -and $PassageDepart -ge 1) {
    $pl = Place-Passage ([Math]::Min($Etages, $EtageDepart)) ([Math]::Min($Passages, $PassageDepart) - 1)
    Write-Host ("Dans le jeu : F3 ferme, outil 3x3 en main, en X {0} Y {1} Z {2} (etage {3}, passage {4}), puis {5}. ({6} = annuler)" -f $pl[0], $pl[2], $pl[1], $EtageDepart, $PassageDepart, $NomPause, $NomArret)
  } else {
    Write-Host ("Dans le jeu : F3 ferme, outil 3x3 en main, dans un couloir sur la ligne d'un passage (debut du champ : X {0}, Y {1}, couloir Z {2}), puis {3}. ({4} = annuler)" -f $script:LignesImpair[0], $YBas, $ZSud, $NomPause, $NomArret)
  }
  while ($true) {
    if (-not (Attendre-F7)) { return }
    if (Au-Premier-Plan) { break }
    Write-Host "$NomPause recu, mais le jeu n'est pas au premier plan : clique dans le jeu puis $NomPause."
  }
  Start-Sleep -Milliseconds 300
  Detecter-Interface
  Couper-Vol
  Appuyer-Slot $SlotOutil                                                # l'outil en main, quoi qu'on tenait
  Start-Sleep -Milliseconds 150
  $p0 = Lire-Coord
  if ($null -eq $p0) { Start-Sleep -Milliseconds 300; $p0 = Lire-Coord }
  if ($null -eq $p0) { Write-Host "Recolte arretee : coordonnees illisibles en haut a gauche (ferme F3, affiche-les dans Lunar)."; return }
  $dep = Trouver-Depart $p0
  if ($null -eq $dep) { return }
  $script:YEtage = Y-Etage $dep[0]; $script:Couloir = $dep[2]
  $script:DerPos = $p0; $script:DerLecture = [Environment]::TickCount
  Write-Host "Recolte lancee."
  Write-Host ("Depart : X {0} Y {1} Z {2} (etage {3}, passage {4}/{5})." -f $p0[0], $p0[1], $p0[2], $dep[0], ($dep[1] + 1), $Passages)
  Suivre-Argent $true
  $script:Actif.Start()
  if ($p0[0] -ne (Lignes $dep[0])[$dep[1]] -and -not (Aller-Au-Depart $dep[0] $dep[1])) { $script:Arret = $true }
  $n = 0
  while (-not $script:Arret) {
    if ($n -gt 0 -and -not (Attendre-Repousse)) { break }
    $ok = if ($n -eq 0) { Un-Tour $dep[0] $dep[1] } else { Un-Tour 1 0 }
    if (-not $ok) { break }
    $n++
    Write-Host ("recolte : tour {0} fini" -f $n)
    if ($Tours -gt 0 -and $n -ge $Tours) { Write-Host "Nombre de tours atteint."; break }
  }
  Relacher-Tout
  Suivre-Argent $true
  Write-Host ("Recolte finie : {0:N0} s actives, {1} passages, {2} vente(s), {3} tour(s) complets." -f $script:Actif.Elapsed.TotalSeconds, $script:PassagesFaits, $script:Ventes, $n)
}

try { Verrue }
finally {
  Relacher-Tout
  Write-Host "Toutes les touches sont relachees."
}
