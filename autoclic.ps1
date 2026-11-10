# =====================================================================
#  autoclic.ps1 : autoclick pour Minecraft (lance par le menu, onglet Autoclick)
#
#  Clic gauche ou droit, en clics repetes (intervalle regulier) ou maintenu.
#  Vente avec le Dial (slot 1) quand le compteur en bas a droite atteint le seuil.
#
#  SECURITES
#    F7 : demarrer, puis pause / reprise
#    F8 (ou le bouton Arreter du menu) : arret, tout est relache
#    Jeu plus au premier plan : tout est relache, puis attente de F7
# =====================================================================
param(
  [string]$Bouton = 'gauche',      # 'gauche' ou 'droit'
  [string]$Mode = 'clics',         # 'clics' (repetes) ou 'maintien' (bouton tenu)
  [int]$IntervalleMs = 100,        # mode clics : temps entre deux clics
  [int]$DureeMaxS = 0,             # 0 = sans limite (temps actif, hors pauses)
  [int]$ClicsMax = 0,              # 0 = sans limite
  [int]$VenteSeuil = 0,            # 0 = pas de vente
  [int]$VenteMs = 100,             # apres le clic de vente, temps avant de revenir au slot de retour
  [int]$SlotRetour = 2,            # slot repris apres la vente (le Dial est au slot 1)
  [int]$VoteSlots = 2,             # slots pris par les objets du VoteParty (0 = ignorer) : le seuil de vente baisse de 64 par slot
  [int]$StopTP = 0,                # 1 = arret si teleporte (saut de position lu en haut a gauche)
  [int]$TPBlocs = 3,               # saut de position (en blocs) compte comme une teleportation
  [int]$RepondreVerif = 0,         # 1 = repondre a la verification AFK (option du menu)
  [int]$SecondPlan = 0,          # 1 = touches et clics envoyes directement a la fenetre du jeu (jeu au second plan)
  [int]$Avancer = 0,               # 1 = mine en ligne droite : avance en minant ; au mur, /home <HomeMine> puis recommence
  [string]$HomeMine = 'm',         # nom du home au depart de la mine (/sethome m fait en regardant le tunnel)
  [int]$MurS = 5,                  # secondes sans avancer d'un bloc = mur atteint
  [int]$Mine = 0,                  # mine 3x3 (onglet Minage) : 1 = part de X -140 vers l'est, 2 = part de X 128 vers l'ouest ; 0 = pas de mine
  [int]$MineY = -3,                # fixe : hauteur du tunnel ; au bout, le joueur tombe a -5
  [int]$MineAttenteS = 20,         # fixe : attente au fond de la chute, avant le /home
  [int]$MineBloqueS = 30,          # secondes sans avancer dans le tunnel = bloque, arret
  [int]$TouchePause = 0x76,        # F7 par defaut (code de touche virtuelle Windows)
  [int]$ToucheArret = 0x77         # F8 par defaut
)

$Dossier = Split-Path -Parent $MyInvocation.MyCommand.Path
# Mine 3x3 : clic gauche maintenu en avancant. /home mine1 et /home mine2 autorises par l'utilisateur le 10/11/2026.
$MineDepartX = 0; $MineSens = 1; $MineXMin = -145; $MineXMax = 133
if ($Mine -gt 0) {
  $Avancer = 1; $Mode = 'maintien'; $Bouton = 'gauche'; $HomeMine = "mine$Mine"
  if ($Mine -eq 1) { $MineDepartX = -140; $MineSens = 1 } else { $MineDepartX = 128; $MineSens = -1 }
}
Add-Type -AssemblyName System.Windows.Forms
$NomPause = ([System.Windows.Forms.Keys]$TouchePause).ToString()   # nom affiche des touches (F7, F8, Pause...)
$NomArret = ([System.Windows.Forms.Keys]$ToucheArret).ToString()
. (Join-Path $Dossier 'touches.ps1')                               # touches du jeu, lues dans ses reglages

# Memes outils que le script de la ferme (touches, souris, lecture des chiffres a l'ecran) :
# on reprend son bloc C# pour n'avoir qu'une seule version.
$src = Get-Content (Join-Path $Dossier 'canne-etage.ps1') -Raw
$i = $src.IndexOf('Add-Type -AssemblyName System.Drawing'); $j = $src.IndexOf("'@", $i)
Invoke-Expression ($src.Substring($i, $j - $i + 2))
[Glyphes]::Charger((Join-Path $Dossier 'police.txt'))
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class ClicDroit {
  [DllImport("user32.dll")] static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  public static void Bouton(bool bas) { mouse_event(bas ? 0x0008u : 0x0010u, 0, 0, 0, IntPtr.Zero); }
  // zone de jeu (sans bordure ni titre) en coordonnees ecran
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  public static System.Drawing.Rectangle Client(IntPtr h) {
    RECT r; GetClientRect(h, out r); var p = new POINT(); ClientToScreen(h, ref p);
    return new System.Drawing.Rectangle(p.X, p.Y, r.R - r.L, r.B - r.T);
  }
  // pixels de la piece (icone de l'argent, orange) dans une zone de l'ecran
  public static int PixelsPiece(System.Drawing.Rectangle ecran) {
    using (var bmp = new System.Drawing.Bitmap(ecran.Width, ecran.Height)) {
      using (var g = System.Drawing.Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, System.Drawing.Point.Empty, ecran.Size);
      int n = 0;
      for (int y = 0; y < bmp.Height; y += 2) for (int x = 0; x < bmp.Width; x += 2) { var c = bmp.GetPixel(x, y); if (c.R >= 230 && c.G >= 150 && c.G <= 210 && c.B <= 110) n++; }
      return n;
    }
  }
}
'@

$script:Arret = $false
$script:Tenu = $false
# clic droit : directement a la fenetre du jeu en mode second plan
function Clic-Droit($bas) { if ([Fond]::Actif) { [Fond]::Clic($true, $bas) } else { [ClicDroit]::Bouton($bas) } }
function Bouton($bas) {
  if ($Bouton -eq 'droit') { (Clic-Droit $bas) } else { [Entree]::ClicGauche($bas) }
  $script:Tenu = $bas
}
function Relacher-Tout { if ($script:Tenu) { Bouton $false }; [Entree]::ClicGauche($false); (Clic-Droit $false); $script:Tenu = $false; Lacher }
# touche d'avance (mine en ligne droite) ; memes noms que la ferme : verification.ps1 la reprend apres une verification
function Enfoncer($t) { [Entree]::Touche($t, $true); $script:ToucheTenue = $t }
function Lacher { if ($null -ne $script:ToucheTenue) { [Entree]::Touche($script:ToucheTenue, $false); $script:ToucheTenue = $null } }
$script:ToucheTenue = $null

$script:PidsJeu = @(Garder-Lunar (Get-Process -Name javaw, java -ErrorAction SilentlyContinue) | ForEach-Object { [uint32]$_.Id })
. (Join-Path $Dossier 'verification.ps1')                       # gros message au centre (verification) : images seulement
if ($SecondPlan -eq 1) {                                                   # mode second plan : on vise la fenetre du jeu
  $fj = Get-Process -Id $script:PidsJeu -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
  if ($fj) { [Fond]::Fenetre = $fj.MainWindowHandle; Write-Host "Mode second plan : touches et clics envoyes directement au jeu. Le jeu doit rester VISIBLE (pas reduit ni cache) et F3 + P doit avoir coupe sa pause automatique." }
}
# au second plan : il suffit que le jeu soit la et pas reduit (on lit l ecran : il doit rester visible)
function Au-Premier-Plan { if ([Fond]::Actif) { return [Fond]::Visible() }; return $script:PidsJeu -contains [Entree]::PidDe([Entree]::FenetrePremierPlan()) }
$script:FichierArret = Join-Path $Dossier 'arret.flag'
if (Test-Path $script:FichierArret) { Remove-Item $script:FichierArret -Force }
function Arret-Demande { return ([Entree]::Appuyee($ToucheArret) -or (Test-Path $script:FichierArret)) }
function Attendre-Relache($vk) { while ([Entree]::Appuyee($vk)) { Start-Sleep -Milliseconds 30 } }
function Attendre-F7 {
  Attendre-Relache $TouchePause
  while (-not [Entree]::Appuyee($TouchePause)) { if (Arret-Demande) { $script:Arret = $true; return $false }; Start-Sleep -Milliseconds 30 }
  Attendre-Relache $TouchePause
  return $true
}

# Pause (F7) ou jeu au second plan : on relache tout et on attend F7. Renvoie $true s'il y a eu une pause.
$script:Actif = [Diagnostics.Stopwatch]::new()
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
  if (-not $pause) { return $false }
  Relacher-Tout; $script:Actif.Stop()
  while ($true) {
    if (-not (Attendre-F7)) { return $true }
    if (Au-Premier-Plan) { break }
    Write-Host "$NomPause recu, mais le jeu n'est pas au premier plan : clique dans le jeu puis $NomPause."
  }
  Start-Sleep -Milliseconds 300
  Write-Host "Reprise"; $script:Actif.Start()
  $script:PosRef = $null                                                   # on a pu bouger pendant la pause
  if ($script:EnAttenteMine) { return $true }                              # au fond de la chute : rien a reprendre
  if ($Mode -eq 'maintien') { Bouton $true }
  if ($Avancer -eq 1) { Enfoncer $script:Cles.avant; $script:Progres = $null }          # on repart tout droit (le temps de pause ne compte pas pour le mur)
  return $true
}
function Dormir($ms) {
  $fin = [Environment]::TickCount + $ms
  while ([Environment]::TickCount -lt $fin -and -not $script:Arret) { Start-Sleep -Milliseconds 5; if (Surveiller-Verification) { return $true }; if (Verifier) { return $true }; if ($ms -gt 300) { Suivre-Gains } }   # longue attente : on suit quand meme les gains
  return $false
}

# ------------------------------- Vente -------------------------------
# Meme principe que pour la ferme : compteur en bas a droite ; au seuil, slot 1 (Dial),
# un vrai clic gauche, retour au slot de retour. Une seule vente tant que le compteur n'est pas
# redescendu sous le seuil ; nouvel essai si le compteur est toujours plein 1,8 s apres.
$script:ProchaineVerif = 0; $script:Armee = $true; $script:DerniereVente = 0; $script:Reussies = 0; $script:Essais = 0
# ------------------------------ Argent ------------------------------
# Argent affiche en haut de l'ecran (texte jaune, ex. "31.78M") : lu toutes les 30 s et ecrit
# "argent : <nombre>" pour le menu, qui en tire les gains et le gain par heure.
$script:ProchaineLectureArgent = 0
function Lire-Argent {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  $larg = $r.R - $r.L
  if ($larg -lt 200) { return $null }
  $zone = New-Object System.Drawing.Rectangle ($r.L + [int]($larg * 0.15)), ($r.T + 8), ([int]($larg * 0.7)), (37 * $script:Gui)   # haut de l'ecran, au milieu
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
# Compteur d'objets en bas a droite. La place mesuree chez l'auteur (100 px du bord droit, 174 du bas, taille 2)
# est TOUJOURS lue en premier. La place trouvee automatiquement (pour un autre joueur) ne sert que si la place
# habituelle ne donne rien. 26/10/2026 : l'ancienne version, une fois une place trouvee, ne lisait plus qu'elle ;
# au debut de la ferme (compteur pas encore affiche), elle s'etait accrochee a un autre nombre -> plus aucune vente.
$script:CompteurAuto = $null; $script:EchAuto = 2; $script:EchecsCompteur = 0; $script:EchecsAuto = 0
$script:ProchaineRechercheCompteur = 0; $script:ProchaineTraceCompteur = 0; $script:ImageCompteur = $false
$script:JournalCompteur = Join-Path $Dossier 'diagnostics\minage-gains.log'
New-Item -ItemType Directory -Force (Join-Path $Dossier 'diagnostics') | Out-Null
function Image-Diag($zone, $nom) {
  try {
    $bmp = New-Object System.Drawing.Bitmap $zone.Width, $zone.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($zone.Location, [System.Drawing.Point]::Empty, $zone.Size); $g.Dispose()
    $bmp.Save((Join-Path $Dossier "diagnostics\$nom")); $bmp.Dispose()
    Write-Host "  (image de ce que le script voyait : diagnostics\$nom)"
  } catch { }
}
function Fenetre-Rect {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  return $r
}
function Rect-Compteur { $r = Fenetre-Rect; return New-Object System.Drawing.Rectangle ($r.R - 100), ($r.B - 174), 92, 16 }
function Tracer-Compteur($texte) {
  if ([Environment]::TickCount -lt $script:ProchaineTraceCompteur) { return }
  $script:ProchaineTraceCompteur = [Environment]::TickCount + 30000
  try { Add-Content $script:JournalCompteur ("{0:HH:mm:ss.fff} compteur : {1}" -f (Get-Date), $texte) } catch { }
}
function Lire-Compteur {
  $r = Fenetre-Rect
  $t = [Glyphes]::Lire((Rect-Compteur), 2)                                  # 1) la place habituelle
  if ($t -match '^\d+$') { $script:EchecsCompteur = 0; Tracer-Compteur "$t (place habituelle)"; return $t }
  $script:EchecsCompteur++
  if ($script:CompteurAuto) {                                               # 2) la place trouvee
    $c = $script:CompteurAuto
    $t2 = [Glyphes]::Lire((New-Object System.Drawing.Rectangle ($r.R - $c[0]), ($r.B - $c[1]), $c[2], $c[3]), $script:EchAuto)
    if ($t2 -match '^\d+$') { $script:EchecsAuto = 0; Tracer-Compteur "$t2 (place trouvee)"; return $t2 }
    $script:EchecsAuto++
    if ($script:EchecsAuto -ge 10) { $script:CompteurAuto = $null; $script:EchecsAuto = 0; Tracer-Compteur "place trouvee oubliee (illisible 10 fois)" }
  }
  if (-not $script:ImageCompteur -and $script:EchecsCompteur -ge 5) { $script:ImageCompteur = $true; Image-Diag (Rect-Compteur) 'compteur-illisible.png' }
  Tracer-Compteur ("illisible ('{0}')" -f $t)
  # 3) recherche dans le coin en bas a droite, au plus toutes les 10 s
  if ($null -eq $script:CompteurAuto -and $script:EchecsCompteur -ge 5 -and [Environment]::TickCount -ge $script:ProchaineRechercheCompteur) {
    $script:ProchaineRechercheCompteur = [Environment]::TickCount + 10000
    $l = [Math]::Min([Math]::Max(500, 170 * $script:Gui), [int](($r.R - $r.L) / 3)); $ht = [Math]::Min([Math]::Max(500, 170 * $script:Gui), [int](($r.B - $r.T) / 2))
    $zone = New-Object System.Drawing.Rectangle ($r.R - $l), ($r.B - $ht), $l, $ht
    $f = [Glyphes]::TrouverCompteur($zone)
    if ($f) {
      $script:CompteurAuto = @(($r.R - ($zone.X + $f[1])), ($r.B - ($zone.Y + $f[2])), $f[3], $f[4]); $script:EchAuto = $f[0]; $script:EchecsAuto = 0
      Write-Host ("Compteur d'objets trouve en bas a droite (taille {0}), utilise si la place habituelle reste illisible." -f $f[0])
      Tracer-Compteur ("place trouvee : {0} px du bord droit, {1} px du bas, taille {2}" -f $script:CompteurAuto[0], $script:CompteurAuto[1], $f[0])
    }
  }
  return $t
}
# ---------------------------- Vote party ----------------------------
# Meme fonctionnement que la ferme : quand "VoteParty 909/1250" repart de zero, le serveur donne des objets qui prennent
# des slots : le compteur n'atteindrait plus le seuil. On baisse le seuil de $VoteSlots x 64, une seule fois par session.
# Une baisse doit etre lue 2 fois de suite.
$script:VoteAvant = $null; $script:VoteDoute = $null; $script:VoteReduit = $false; $script:ProchaineLectureVote = 0
function Lire-VoteParty {
  $r = Fenetre-Rect; $larg = $r.R - $r.L
  if ($larg -lt 200) { return '' }
  $zone = New-Object System.Drawing.Rectangle ($r.L + [int]($larg * 0.15)), ($r.T + 8), ([int]($larg * 0.7)), (53 * $script:Gui)
  return [Glyphes]::LireCouleur($zone, 137, 214, 250, $script:Gui)
}
function Suivre-VoteParty {
  if ($VoteSlots -le 0 -or $script:VoteReduit) { return }
  if ([Environment]::TickCount -lt $script:ProchaineLectureVote) { return }
  $script:ProchaineLectureVote = [Environment]::TickCount + 15000
  $t = Lire-VoteParty
  if ($t -notmatch '(\d+)/(\d+)') { return }
  $v = [int]$Matches[1]; $total = [int]$Matches[2]
  if ($null -ne $script:VoteDoute) {
    $ok = $v -le $script:VoteDoute + 50
    $script:VoteDoute = $null
    if ($ok) {
      $script:VoteReduit = $true
      $ancien = $VenteSeuil
      $script:VenteSeuil = [Math]::Max(64, $VenteSeuil - 64 * $VoteSlots)
      Write-Host ("Vote party atteint : {0} slots en moins, vente a {1} objets au lieu de {2}." -f $VoteSlots, $script:VenteSeuil, $ancien)
      $script:VoteAvant = $v; return
    }
  }
  if ($null -ne $script:VoteAvant -and $v -lt $script:VoteAvant -and $script:VoteAvant -ge $total - 150 -and $v -le 150) { $script:VoteDoute = $v }
  $script:VoteAvant = $v
}
function Verifier-Vente {
  if ($VenteSeuil -le 0) { return }
  Suivre-VoteParty
  $maintenant = [Environment]::TickCount
  if ($maintenant -lt $script:ProchaineVerif) { return }
  $script:ProchaineVerif = $maintenant + 1000
  $t = Lire-Compteur
  if ($t -notmatch '^\d+$') { return }
  $n = [int]$t
  if ($n -lt $VenteSeuil) {
    if (-not $script:Armee) { $script:Reussies++; Write-Host ("  vente reussie ({0} au total)" -f $script:Reussies) }
    $script:Armee = $true; return
  }
  if (-not $script:Armee -and ($maintenant - $script:DerniereVente) -gt 1800) { $script:Armee = $true }
  if ($n -gt 2304 -or -not $script:Armee) { return }
  $script:Armee = $false; $script:DerniereVente = $maintenant; $script:Essais++
  Write-Host ("  essai de vente ({0} objets)" -f $n)
  $tenu = $script:Tenu
  if ($tenu) { Bouton $false }                                                            # on lache le bouton de l'autoclick
  [Entree]::Touche($script:Slots[0], $true); Start-Sleep -Milliseconds 30; [Entree]::Touche($script:Slots[0], $false)   # slot 1 : le Dial
  Start-Sleep -Milliseconds 150
  [Entree]::ClicGauche($true); Start-Sleep -Milliseconds 20; [Entree]::ClicGauche($false)         # le clic de vente
  Start-Sleep -Milliseconds $VenteMs
  $sc = $script:Slots[$SlotRetour - 1]
  [Entree]::Touche($sc, $true); Start-Sleep -Milliseconds 30; [Entree]::Touche($sc, $false)
  Start-Sleep -Milliseconds 50
  if ($tenu) { Bouton $true }
  $script:ProchaineVerif = [Environment]::TickCount + 1200
}

# ------------------------- Arret si teleporte -------------------------
# Coordonnees en haut a gauche (memes zones que la ferme : X, Y, Z a 44 / 66 / 88 px du haut de la fenetre).
# Toutes les 0,5 s : si la position s'eloigne de plus de $TPBlocs blocs d'un coup (1 a 10, reglable), et que la lecture suivante
# le confirme (pas une lecture fausse), c'est une teleportation : on lache tout et on s'arrete.
$script:PosRef = $null; $script:ProchaineTP = 0; $script:Suspect = 0
$script:ZonesCoord = $null
function Lire-Coord {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  if ($null -eq $script:ZonesCoord) {
    # cherchees une fois dans le coin en haut a gauche (n'importe quelle place ou taille), sinon places par defaut
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
# ------------------------------ Gains ------------------------------
# Au-dessus de la vie : "+argent (piece)  +xp (fiole)", en vert clair. Test du 24/10/2026 : en minage
# continu c'est un CUMUL (25.55 -> 29.9 -> 36.4 -> 45.51) qui continue meme si l'affichage disparait
# une seconde entre deux blocs. On ne compte donc que ce que le cumul AJOUTE d'une lecture a l'autre.
# Nouveau cumul seulement si la valeur redescend (confirme sur 2 lectures : un chiffre mal lu ne compte
# pas) ou apres plus de 10 s sans affichage. Envoi au menu toutes les 10 s : "gain : argent X xp Y".
$script:ProchainGain = 0; $script:PrecA = $null; $script:PrecX = $null; $script:VuGain = 0
$script:AttA = 0.0; $script:AttX = 0.0; $script:Envoi = 0; $script:Baisse = $false
function Rect-Gains {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $c = [ClicDroit]::Client($h)
  $s = $script:Gui                                                        # echelle de l interface
  return New-Object System.Drawing.Rectangle ($c.X + [int]($c.Width / 2) - 130 * $s), ($c.Bottom - 80 * $s), (133 * $s), (22 * $s)
}
function Lire-TexteGains($r) { return [Glyphes]::LireCouleur($r, 111, 221, 155, $script:Gui) }
function Envoyer-Gains {
  if ($script:AttA -le 0 -and $script:AttX -le 0) { return }
  $inv = [Globalization.CultureInfo]::InvariantCulture
  Write-Host ("  gain : argent {0} xp {1}" -f $script:AttA.ToString('0.##', $inv), $script:AttX.ToString('0.##', $inv))
  $script:AttA = 0.0; $script:AttX = 0.0
}
# Journal detaille des lectures (diagnostic, test du 24/10/2026 : +402 compte pour un compteur a 180)
$script:JournalGains = Join-Path $Dossier 'diagnostics\minage-gains.log'
New-Item -ItemType Directory -Force (Split-Path $script:JournalGains) | Out-Null
Set-Content $script:JournalGains ("{0:yyyy-MM-dd HH:mm:ss} debut du minage" -f (Get-Date))
$script:ImagesRemise = 0; $script:ImagesAbime = 0; $script:ProchaineImageAbime = 0
function Noter-Gain($texte) { Add-Content $script:JournalGains ("{0:HH:mm:ss.fff} {1}" -f (Get-Date), $texte) }
function Suivre-Gains($fin = $false) {
  if ($fin) { Noter-Gain ("fin : envoi argent {0} xp {1}" -f $script:AttA, $script:AttX); Envoyer-Gains; return }
  $mtn = [Environment]::TickCount
  if ($mtn -ge $script:Envoi) { $script:Envoi = $mtn + 10000; if ($script:AttA -gt 0 -or $script:AttX -gt 0) { Noter-Gain ("envoi argent {0} xp {1}" -f $script:AttA, $script:AttX) }; Envoyer-Gains }
  if ($mtn -lt $script:ProchainGain) { return }
  $script:ProchainGain = $mtn + 250
  $r = Rect-Gains
  $t = Lire-TexteGains $r
  if ($t -eq '') { return }
  # Du texte vert est la, meme mal lu : le compteur est affiche. Test du 24/10/2026 : au-dela de ~900,
  # "+9..." etait mal lu pendant plus de 10 s, et la regle des 10 s avait cru a un nouveau cumul
  # (925, 999 puis 1086 comptes en entier une 2e fois). Seul un affichage VIDE fait courir les 10 s.
  if ($null -ne $script:PrecA -and $mtn - $script:VuGain -gt 10000) { Noter-Gain "plus de 10 s sans affichage : nouveau cumul"; $script:PrecA = $null; $script:PrecX = $null }
  $script:VuGain = $mtn
  $n = [regex]::Matches($t, '\+(\d+(?:\.\d+)?)')
  # deux nombres obligatoires (argent puis XP) : un seul nombre pouvait etre l'XP prise pour de l'argent,
  # donc une fausse baisse, donc un faux "nouveau cumul" compte en double
  if ($t -match '\?' -or $n.Count -lt 2) {
    Noter-Gain ("lu [{0}] : {1}, ignore" -f $t, $(if ($t -match '\?') { 'abime' } else { 'moins de 2 nombres' }))
    if ($script:ImagesAbime -lt 6 -and $mtn -ge $script:ProchaineImageAbime) {   # pour comprendre la mauvaise lecture (une image toutes les 20 s au plus)
      $script:ImagesAbime++; $script:ProchaineImageAbime = $mtn + 20000
      try { $bmp = New-Object System.Drawing.Bitmap $r.Width, $r.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.Location, [System.Drawing.Point]::Empty, $r.Size); $g.Dispose(); $bmp.Save((Join-Path (Split-Path $script:JournalGains) ("minage-abime-{0}.png" -f $script:ImagesAbime))); $bmp.Dispose() } catch { }
    }
    return
  }
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $a = [double]::Parse($n[0].Groups[1].Value, $inv); $x = [double]::Parse($n[1].Groups[1].Value, $inv)
  $baisse = ($null -ne $script:PrecA) -and ($a -lt $script:PrecA - 0.001 -or $x -lt $script:PrecX - 0.001)
  if ($baisse) {
    if (-not $script:Baisse) { $script:Baisse = $true; Noter-Gain ("lu [{0}] : plus bas que {1} / {2}, a confirmer" -f $t, $script:PrecA, $script:PrecX); return }
    Noter-Gain ("lu [{0}] : baisse confirmee, nouveau cumul (avant {1} / {2})" -f $t, $script:PrecA, $script:PrecX)
    if ($script:ImagesRemise -lt 10) { $script:ImagesRemise++; try { $bmp = New-Object System.Drawing.Bitmap $r.Width, $r.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.Location, [System.Drawing.Point]::Empty, $r.Size); $g.Dispose(); $bmp.Save((Join-Path (Split-Path $script:JournalGains) ("minage-remise-{0}.png" -f $script:ImagesRemise))); $bmp.Dispose() } catch { } }
    $script:PrecA = $null; $script:PrecX = $null
  }
  $script:Baisse = $false
  $dA = $a - $(if ($null -ne $script:PrecA) { $script:PrecA } else { 0 }); $dX = $x - $(if ($null -ne $script:PrecX) { $script:PrecX } else { 0 })
  if ($dA -gt 0) { $script:AttA += $dA }; if ($dX -gt 0) { $script:AttX += $dX }
  if ($dA -gt 0 -or $dX -gt 0) { Noter-Gain ("lu [{0}] : +{1} argent, +{2} xp" -f $t, [Math]::Max(0, $dA), [Math]::Max(0, $dX)) }
  $script:PrecA = $a; $script:PrecX = $x
}

function Verifier-TP {
  if ($StopTP -le 0 -or [Environment]::TickCount -lt $script:ProchaineTP) { return }
  $script:ProchaineTP = [Environment]::TickCount + 500
  $p = Lire-Coord
  if ($null -eq $p) { return }
  $mtn = [Environment]::TickCount
  if ($null -eq $script:PosRef) { $script:PosRef = $p; $script:TempsPosRef = $mtn; return }
  $d = 0; for ($i = 0; $i -lt 3; $i++) { $d = [Math]::Max($d, [Math]::Abs($p[$i] - $script:PosRef[$i])) }
  # dans la mine, le joueur marche : on ajoute ce qu'il peut parcourir (8 blocs/s au plus) depuis la VRAIE derniere lecture.
  # 10/11/2026 : la macro a ete figee 3,5 s, le joueur a marche 15 blocs, et c'etait compte comme une teleportation.
  $permis = $TPBlocs; if ($Mine -gt 0) { $permis += 8 * ($mtn - $script:TempsPosRef) / 1000.0 }
  if ($d -le $permis) { $script:Suspect = 0; $script:PosRef = $p; $script:TempsPosRef = $mtn; return }
  $script:Suspect++
  if ($script:Suspect -lt 2) { return }
  Relacher-Tout; $script:Arret = $true
  [console]::Beep(880, 250); [console]::Beep(660, 400)
  Write-Host ("TELEPORTE : position {0} {1} {2} -> {3} {4} {5}, arret." -f $script:PosRef[0], $script:PosRef[1], $script:PosRef[2], $p[0], $p[1], $p[2])
}

# ------------------------- Mine en ligne droite -------------------------
# Le joueur avance (touche Z) en minant. Les coordonnees en haut a gauche sont lues toutes les 0,5 s :
# s'il n'a pas avance d'un bloc depuis $MurS secondes, c'est le mur du fond. Alors /home <HomeMine>
# (commande autorisee par l'utilisateur le 06/11/2026), verification que la position est revenue au depart,
# et on recommence. Le home doit avoir ete pose en regardant le tunnel : le serveur rend aussi la direction.
$script:Progres = $null; $script:ProchainPas = 0; $script:DepartMine = $null; $script:Retours = 0
function Taper-Commande($texte) {
  Relacher-Tout
  if (-not (Au-Premier-Plan)) { Write-Host "Le jeu n'est pas visible : /$texte annule, arret." -ForegroundColor Red; $script:Arret = $true; return $false }
  Add-Content $script:JournalGains ("{0:HH:mm:ss.fff} commande /{1}" -f (Get-Date), $texte)
  Start-Sleep -Milliseconds (Get-Random -Minimum 250 -Maximum 600)
  [Entree]::Touche($script:Cles.chat, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 70); [Entree]::Touche($script:Cles.chat, $false)   # ouvre le chat
  Start-Sleep -Milliseconds (Get-Random -Minimum 600 -Maximum 900)
  foreach ($ch in ('/' + $texte).ToCharArray()) {
    if ([Fond]::Actif) { [Fond]::Caractere($ch) } else { [System.Windows.Forms.SendKeys]::SendWait(($(if ('+^%~(){}[]'.Contains([string]$ch)) { '{' + $ch + '}' } else { [string]$ch }))) }
    Start-Sleep -Milliseconds (Get-Random -Minimum 40 -Maximum 120)
  }
  Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 450)
  [Entree]::Touche(0x1C, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 70); [Entree]::Touche(0x1C, $false)   # Entree
  return $true
}
function Retour-Mine {
  if ($Mine -le 0) { Write-Host ("Mur atteint : retour au depart (/home {0})." -f $HomeMine) -ForegroundColor Cyan }
  if (-not (Taper-Commande "home $HomeMine")) { return }
  if (Dormir 2500) { if ($script:Arret) { return } }
  $p = $null; $d = 99
  for ($n = 0; $n -lt 5; $n++) {                                           # le serveur peut mettre quelques secondes a teleporter
    $p = Lire-Coord
    if ($null -ne $p) { $d = 0; for ($i = 0; $i -lt 3; $i++) { $d = [Math]::Max($d, [Math]::Abs($p[$i] - $script:DepartMine[$i])) }; if ($d -le 2) { break } }
    [void](Dormir 1000); if ($script:Arret) { return }
  }
  if ($null -eq $p) { Write-Host "Coordonnees illisibles apres /home : arret." -ForegroundColor Red; $script:Arret = $true; return }
  if ($d -gt 2) { Write-Host ("Pas revenu au depart apres /home {0} (X {1} Y {2} Z {3}, depart {4} {5} {6}) : arret." -f $HomeMine, $p[0], $p[1], $p[2], $script:DepartMine[0], $script:DepartMine[1], $script:DepartMine[2]) -ForegroundColor Red; $script:Arret = $true; return }
  $script:Retours++
  Write-Host ("Au depart de la mine ({0} retour{1}). On repart." -f $script:Retours, $(if ($script:Retours -gt 1) { 's' } else { '' })) -ForegroundColor Green
  $script:PosRef = $null; $script:Progres = $null                          # le saut du /home n'est pas une teleportation suspecte
  Start-Sleep -Milliseconds (Get-Random -Minimum 300 -Maximum 700)
  if ($Mode -eq 'maintien') { Bouton $true }
  Enfoncer $script:Cles.avant
}
# ------------------------------ Mine 3x3 ------------------------------
# Position lue toutes les 0,1 s. Au bout du tunnel le joueur tombe de -3 a -5 devant un mur d'obsidienne : des que deux lectures
# de suite donnent un Y plus bas, tout est relache, attente de $MineAttenteS s, puis /home mine1 ou mine2 et on repart.
# Hors de la mine (teleporte, autre monde) ou bloque : arret, aucune commande tapee.
$script:EnAttenteMine = $false; $script:DouteChute = 0
function Stop-Mine($msg) {
  Relacher-Tout; $script:Arret = $true
  [console]::Beep(880, 250); [console]::Beep(660, 400)
  Write-Host ("Mine : {0}, arret." -f $msg) -ForegroundColor Red
}
function Fin-Mine {
  Relacher-Tout
  $script:PosRef = $null; $script:Progres = $null                          # la chute n'est pas une teleportation suspecte
  $script:EnAttenteMine = $true
  Write-Host ("Bout de la mine : attente de {0} s, puis /home {1}." -f $MineAttenteS, $HomeMine) -ForegroundColor Cyan
  $fin = [Environment]::TickCount + $MineAttenteS * 1000
  while ([Environment]::TickCount -lt $fin -and -not $script:Arret) { [void](Dormir 250) }
  if (-not $script:Arret) { Retour-Mine }
  $script:EnAttenteMine = $false
}
function Verifier-Chute {
  if ($Mine -le 0 -or [Environment]::TickCount -lt $script:ProchainPas) { return }
  $script:ProchainPas = [Environment]::TickCount + 100
  $p = Lire-Coord
  if ($null -eq $p) { return }
  if ($p[0] -lt $MineXMin -or $p[0] -gt $MineXMax -or $p[1] -gt $MineY + 1 -or $p[1] -lt $MineY - 3) {
    $script:DouteChute = 0; $script:HorsMine++
    if ($script:HorsMine -ge 3) { Stop-Mine ("hors de la mine (X {0} Y {1} Z {2})" -f $p[0], $p[1], $p[2]) }
    return
  }
  $script:HorsMine = 0
  if ($p[1] -lt $MineY) {
    $script:DouteChute++
    if ($script:DouteChute -ge 2) { $script:DouteChute = 0; Fin-Mine }
    return
  }
  $script:DouteChute = 0
  $mtn = [Environment]::TickCount
  if ($null -eq $script:Progres) { $script:Progres = @{ Pos = $p; T = $mtn }; return }
  $avance = ($p[0] - $script:Progres.Pos[0]) * $MineSens
  if ($avance -ge 1) { $script:Progres = @{ Pos = $p; T = $mtn }; return }
  if ($avance -le -4) { Stop-Mine "le joueur recule : verifie le regard enregistre dans /home $HomeMine"; return }
  if ($mtn - $script:Progres.T -ge $MineBloqueS * 1000) { Stop-Mine ("plus aucune avance depuis {0} s (X {1})" -f $MineBloqueS, $p[0]) }
}
$script:HorsMine = 0

function Verifier-Mur {
  if ($Avancer -ne 1 -or $Mine -gt 0 -or [Environment]::TickCount -lt $script:ProchainPas) { return }
  $script:ProchainPas = [Environment]::TickCount + 500
  $p = Lire-Coord
  if ($null -eq $p) { return }
  $mtn = [Environment]::TickCount
  if ($null -eq $script:Progres) { $script:Progres = @{ Pos = $p; T = $mtn }; return }
  $d = [Math]::Max([Math]::Abs($p[0] - $script:Progres.Pos[0]), [Math]::Abs($p[2] - $script:Progres.Pos[2]))
  if ($d -ge 1) { $script:Progres = @{ Pos = $p; T = $mtn }; return }
  if ($mtn - $script:Progres.T -ge $MurS * 1000) { Retour-Mine }
}

# ------------------------------ Autoclick ------------------------------
function Autoclick {
  if ($script:PidsJeu.Count -eq 0) { Write-Host "Le jeu n'est pas lance." -ForegroundColor Red; return }
  $txtMode = if ($Mode -eq 'maintien') { 'bouton maintenu' } else { "un clic toutes les $IntervalleMs ms ({0:N1} par seconde)" -f (1000.0 / $IntervalleMs) }
  if ($Mine -gt 0) { Write-Host "Mine 3x3 : clic gauche maintenu en avancant." } else { Write-Host ("Autoclick : clic {0}, {1}{2}{3}." -f $Bouton, $txtMode, $(if ($DureeMaxS -gt 0) { ", $DureeMaxS s max" } else { '' }), $(if ($ClicsMax -gt 0) { ", $ClicsMax clics max" } else { '' })) }
  Write-Host "Dans le jeu : ferme le chat et le menu (Echap), puis $NomPause. ($NomArret = annuler)"
  while ($true) {
    if (-not (Attendre-F7)) { return }
    if (Au-Premier-Plan) { break }
    Write-Host "$NomPause recu, mais le jeu n'est pas au premier plan : clique dans le jeu puis $NomPause."
  }
  Start-Sleep -Milliseconds 300
  Write-Host $(if ($Mine -gt 0) { "Mine lancee." } else { "Autoclick lance." })
  Detecter-Interface
  Suivre-Argent $true
  if ($StopTP -gt 0) {
    $p0 = Lire-Coord
    if ($null -eq $p0) { Write-Host "Coordonnees illisibles en haut a gauche : arret si teleporte desactive (affiche-les dans Lunar)."; $script:StopTP = 0 }
    else { $script:PosRef = $p0; $script:TempsPosRef = [Environment]::TickCount; Write-Host ("Arret si teleporte : actif, au-dela de {3} bloc(s) (depart {0} {1} {2})." -f $p0[0], $p0[1], $p0[2], $TPBlocs) }
  }
  if ($Mine -gt 0) {
    $p = Lire-Coord
    if ($null -eq $p) { Write-Host "Mine : coordonnees illisibles en haut a gauche (affiche-les dans Lunar), arret." -ForegroundColor Red; return }
    if ($p[1] -ne $MineY -or $p[0] -lt $MineXMin -or $p[0] -gt $MineXMax) { Write-Host ("Mine : place-toi dans le tunnel (Y {0}, X entre -140 et 128) ; lu X {1} Y {2}, arret." -f $MineY, $p[0], $p[1]) -ForegroundColor Red; return }
    $script:DepartMine = @($MineDepartX, $MineY, $p[2])
    Write-Host ("Mine {0} : depart X {1}, retour par /home {2} apres {3} s au fond." -f $Mine, $MineDepartX, $HomeMine, $MineAttenteS)
  }
  elseif ($Avancer -eq 1) {
    $script:DepartMine = Lire-Coord
    if ($null -eq $script:DepartMine) { Write-Host "Mine en ligne droite : coordonnees illisibles en haut a gauche (affiche-les dans Lunar). Arret." -ForegroundColor Red; return }
    Write-Host ("Mine en ligne droite : depart X {0} Y {1} Z {2}. Au mur ({3} s sans avancer) : /home {4}." -f $script:DepartMine[0], $script:DepartMine[1], $script:DepartMine[2], $MurS, $HomeMine)
  }
  $script:Actif.Start()
  $clics = 0; $prochainBilan = [Environment]::TickCount + 5000
  if ($Mode -eq 'maintien') { Bouton $true }
  if ($Avancer -eq 1) { Enfoncer $script:Cles.avant }
  while (-not $script:Arret) {
    if ($Mode -eq 'maintien') {
      if (Dormir 50) { continue }
    } else {
      $debut = [Environment]::TickCount
      Bouton $true; Start-Sleep -Milliseconds ([Math]::Min(30, [int]($IntervalleMs / 2))); Bouton $false
      $clics++
      $reste = $IntervalleMs - ([Environment]::TickCount - $debut)
      if ($reste -gt 0) { if (Dormir $reste) { continue } } elseif (Verifier) { continue }
    }
    Verifier-Vente
    Verifier-TP
    Verifier-Chute
    Verifier-Mur
    [void](Surveiller-Verification)
    Suivre-Gains
    Suivre-Argent
    if ([Environment]::TickCount -ge $prochainBilan) { $prochainBilan = [Environment]::TickCount + 5000; if ($Mode -ne 'maintien') { Write-Host ("clics : {0}" -f $clics) } }
    if ($DureeMaxS -gt 0 -and $script:Actif.Elapsed.TotalSeconds -ge $DureeMaxS) { Write-Host "Duree maximale atteinte."; break }
    if ($ClicsMax -gt 0 -and $clics -ge $ClicsMax) { Write-Host "Nombre de clics maximal atteint."; break }
  }
  Relacher-Tout
  if ($Mode -ne 'maintien') { Write-Host ("clics : {0}" -f $clics) }
  Suivre-Argent $true
  Suivre-Gains $true
  Write-Host ("{2} termine : {0:N0} s actives{1}." -f $script:Actif.Elapsed.TotalSeconds, $(if ($Avancer -eq 1) { ", $($script:Retours) retour(s) au depart" } else { '' }), $(if ($Mine -gt 0) { 'Mine' } else { 'Autoclick' }))
}

try { Autoclick }
finally {
  Relacher-Tout
  Write-Host "Toutes les touches sont relachees."
}
