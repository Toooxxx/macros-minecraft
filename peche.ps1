# =====================================================================
#  peche.ps1 : peche automatique avec le mini-jeu de la barre (lance par le menu, tuile Peche)
#
#  Clic droit : lance la ligne. Quand ca mord, la barre apparait toute seule ; le script garde
#  la zone verte sur le poisson (clic droit tenu = la zone monte, relache = elle descend),
#  puis relance la ligne. Aucune commande, aucun message dans le chat.
#
#  Mesures faites sur l'enregistrement du 24/10/2026 (ecran 2560 x 1440) :
#    zone verte 122 px de haut, monte a ~175 px/s, descend a ~108 px/s, ~200 ms de retard
#    apres le clic ; poisson ~50 px/s en moyenne, pointes a ~490 px/s.
#    Fin du mini-jeu : la barre disparait ; jauge pleine = poisson attrape.
#
#  SECURITES
#    F7 : demarrer, puis pause / reprise ; F8 (ou Arreter dans le menu) : arret
#    Jeu plus au premier plan : clic relache, puis attente de F7
# =====================================================================
param(
  [int]$AnticipMs = 50,          # le clic agit vite (< 0,1 s) : on vise ou sera la zone dans ce temps
  [int]$Tolerance = 10,          # ecart zone / poisson (px en interface x3) ou on ne cherche plus a corriger
  [int]$AttenteMs = 1200,        # apres un mini-jeu, attente avant de relancer la ligne
  [int]$RelanceS = 120,          # rien ne mord pendant ce temps : on ramene et on relance
  [int]$PoissonsMax = 0,         # 0 = sans limite
  [int]$SlotCanne = 1,           # slot de la canne a peche
  [int]$RepondreVerif = 0,       # 1 = repondre a la verification AFK (option du menu)
  [int]$SecondPlan = 0,          # 1 = touches et clics envoyes directement a la fenetre du jeu (jeu au second plan)
  [int]$TouchePause = 0x76,
  [int]$ToucheArret = 0x77
)

$Dossier = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -AssemblyName System.Windows.Forms
$NomPause = ([System.Windows.Forms.Keys]$TouchePause).ToString()
$NomArret = ([System.Windows.Forms.Keys]$ToucheArret).ToString()

# Memes outils que la ferme (touches, lecture de l'argent) : on reprend son bloc C#.
$src = Get-Content (Join-Path $Dossier 'canne-etage.ps1') -Raw
$i = $src.IndexOf('Add-Type -AssemblyName System.Drawing'); $j = $src.IndexOf("'@", $i)
Invoke-Expression ($src.Substring($i, $j - $i + 2))
[Glyphes]::Charger((Join-Path $Dossier 'police.txt'))
# Lecture du chat (nom du poisson attrape) : police a 9 rangees, accents compris.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition (Get-Content (Join-Path $Dossier 'lecture-chat.cs') -Raw)
[Chat]::Charger((Join-Path $Dossier 'police-chat.txt'))
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class Peche {
  [DllImport("user32.dll")] static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  public static void ClicDroit(bool bas) { mouse_event(bas ? 0x0008u : 0x0010u, 0, 0, 0, IntPtr.Zero); }
  // Le plus gros bloc de lignes (au moins [min] pixels, trous de [trou] lignes toleres) : { haut, bas }, -1 si rien.
  // Sert au poisson : la petite jarre en bas de la barre montre parfois du fonce (25/10/2026 : un Nemo de 62 s,
  // le "poisson" allait de sa vraie place jusqu a la jarre, donc son centre etait faux).
  // Les 5 marrons exacts du cadre de la barre (mesures sur la capture du 24/10/2026), a +-10 pres. Plus large,
  // la barre de vie rouge sous la barre passait pour le cadre (25/10/2026 : clics dans le vide apres un poisson).
  static readonly int[][] Marrons = { new[] { 207, 127, 88 }, new[] { 163, 98, 65 }, new[] { 144, 79, 46 }, new[] { 92, 52, 46 }, new[] { 184, 114, 79 } };
  public static bool CouleurCadre(int r, int g, int b) {
    foreach (var m in Marrons) if (Math.Abs(r - m[0]) <= 10 && Math.Abs(g - m[1]) <= 10 && Math.Abs(b - m[2]) <= 10) return true;
    return false;
  }
  static int[] Bloc(int[] compte, int min, int trou) {
    int mh = -1, mb = -1, mt = 0, dh = -1, db = -1, tot = 0, vide = 0;
    for (int y = 0; y <= compte.Length; y++) {
      bool ok = y < compte.Length && compte[y] >= min;
      if (ok) { if (dh < 0) { dh = y; tot = 0; } db = y; tot += compte[y]; vide = 0; }
      else if (dh >= 0 && (++vide > trou || y == compte.Length)) { if (tot > mt) { mt = tot; mh = dh; mb = db; } dh = -1; vide = 0; }
    }
    return new[] { mh, mb };
  }
  // Une image de la barre deja trouvee : { pixels verts, zone haut, zone bas, poisson haut, poisson bas, jauge, cadre }
  // (coordonnees dans la capture ; -1 si pas trouve). x0..x1 / y0..y1 : interieur de la barre ; xj : colonne de la jauge ;
  // xg..xd : bande de colonnes ou chercher le cote gauche du cadre ; cadre = % de ses pixels : tant qu il y en a,
  // la barre est la (la zone verte, elle, peut etre cachee par le poisson : test du 25/10/2026, poisson epique).
  public static int[] Mesurer(Rectangle ecran, int x0, int x1, int y0, int y1, int xj, int xg, int xd) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      return Mesurer(bmp, x0, x1, y0, y1, xj, xg, xd);
    }
  }
  public static int[] Mesurer(Bitmap bmp, int x0, int x1, int y0, int y1, int xj, int xg, int xd) {
    {
      var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
      var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
      int s = bd.Stride, h = bmp.Height, w = bmp.Width;
      int nv = 0, zh = -1, zb = -1, ph = -1, pb = -1, jauge = 0;
      var fonces = new int[h]; var verts = new int[h]; var teintes = new int[h];
      int minVert = Math.Max(4, (x1 - x0) / 4);
      int yFin = y1 - (y1 - y0) / 9;                                              // la jarre, en bas (~1/9 de la barre) : pas de poisson la-dedans
      for (int y = 0; y < h; y++) {
        int vert = 0, fonce = 0, teinte = 0;
        if (y >= y0 && y <= y1)
          for (int x = x0; x <= x1 && x < w; x++) {
            int o = y * s + x * 3; int bl = b[o], gg = b[o + 1], r = b[o + 2];
            if (gg >= 140 && gg - r >= 50 && gg - bl >= 50 && r <= 150) vert++;   // zone verte (vert strict : un vert plus large prenait les algues du fond, 25/10/2026)
            if (r + gg + bl < 150 && bl - gg >= 15) fonce++;                       // casquette bleu marine (le fond du chat, les algues : gris-vert)
            else if (r + gg + bl < 150 && Math.Abs(bl - gg) <= 12 && gg - r >= 20) teinte++;   // casquette d'un poisson DANS la zone (teinte en vert)
          }
        nv += vert;
        verts[y] = vert;
        if (y <= yFin) { fonces[y] = fonce; teintes[y] = teinte; }
        if (y > y0 - 12 && xj < w) { int oj = y * s + xj * 3; if (b[oj + 2] >= 200 || b[oj + 1] >= 170) jauge++; }   // jauge : rouge -> vert
      }
      // cadre : son COTE GAUCHE, colonnes [xg..xd], la meilleure (sa place varie de quelques pixels), en % de ses pixels.
      // Pas une ligne du haut ou du bas : sur le 2e ecran, les gains (+15, piece) sous la barre passaient pour le cadre
      // et le script "jouait" dans le vide (25/10/2026). 69 images avec barre : 76 a 96 % ; sans barre : 0 %.
      int cadre = 0;
      for (int x = Math.Max(0, xg); x <= xd && x < w; x++) {
        int n = 0, t = 0;
        for (int y = y0; y <= y1 && y < h; y += 6) { t++; int o = y * s + x * 3; if (CouleurCadre(b[o + 2], b[o + 1], b[o])) n++; }
        if (t > 0) cadre = Math.Max(cadre, 100 * n / t);
      }
      var zv = Bloc(verts, minVert, 6); zh = zv[0]; zb = zv[1];   // zone : le plus gros bloc de lignes vertes
      // le poisson teinte en vert ne peut etre que dans la zone (+- la moitie de sa taille)
      if (zh >= 0) { int marge = (y1 - y0) / 18; for (int y = Math.Max(0, zh - marge); y <= Math.Min(h - 1, zb + marge); y++) fonces[y] += teintes[y]; }
      var p = Bloc(fonces, 3, 6); ph = p[0]; pb = p[1];
      return new[] { nv, zh, zb, ph, pb, jauge, cadre };
    }
  }

  // Barre trouvee automatiquement dans une grande zone (25/10/2026 : sur le 2e ecran, plus etroit, la barre
  // n'etait plus la ou on la cherchait). Zone verte = colonnes vertes sur 20 unites de haut au moins, sur
  // 8 unites de large ; interieur de la barre = jusqu'au cadre marron au-dessus et au-dessous (exige :
  // sans cadre, ce n'est pas la barre, ex. de l'herbe). s = echelle de l'interface (3).
  // Renvoie { pixels verts, zone haut, zone bas, poisson haut, poisson bas, jauge, interieur haut, interieur bas, gauche, droite }.
  public static int[] Chercher(Rectangle ecran, int s) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      return Chercher(bmp, s);
    }
  }
  public static int[] Chercher(Bitmap bmp, int s) {
    var rien = new[] { 0, -1, -1, -1, -1, 0, -1, -1, -1, -1 };
    var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
    int st = bd.Stride, h = bmp.Height, w = bmp.Width;
    Func<int, int, bool> vert = (x, y) => { int o = y * st + x * 3; int bl = b[o], gg = b[o + 1], r = b[o + 2]; return gg >= 140 && gg - r >= 50 && gg - bl >= 50 && r <= 150; };
    Func<int, int, bool> marron = (x, y) => { int o = y * st + x * 3; return CouleurCadre(b[o + 2], b[o + 1], b[o]); };
    // colonnes vertes (une ligne sur deux suffit)
    var col = new int[w];
    for (int y = 0; y < h; y += 2) for (int x = 0; x < w; x++) if (vert(x, y)) col[x]++;
    int seuilCol = 10 * s, x0 = -1, x1 = -1, deb = -1;
    for (int x = 0; x <= w; x++) {
      bool ok = x < w && col[x] >= seuilCol;
      if (ok && deb < 0) deb = x;
      if (!ok && deb >= 0) { if (x - deb > x1 - x0) { x0 = deb; x1 = x - 1; } deb = -1; }
    }
    if (x0 < 0 || x1 - x0 + 1 < 8 * s) return rien;
    int nv = 0; for (int x = x0; x <= x1; x++) nv += col[x] * 2;
    // lignes de la zone verte
    // (la plus longue suite de lignes vertes, trous de 2 unites toleres : du texte vert du HUD en haut de
    // l'ecran peut etre dans les memes colonnes)
    int zh = -1, zb = -1, larg = x1 - x0 + 1, dh = -1, db = -1, trou = 0;
    for (int y = 0; y <= h; y++) {
      bool ok = false;
      if (y < h) { int n = 0; for (int x = x0; x <= x1; x++) if (vert(x, y)) n++; ok = n >= larg / 3; }
      if (ok) { if (dh < 0) dh = y; db = y; trou = 0; }
      else if (dh >= 0 && ++trou > 2 * s) { if (db - dh > zb - zh) { zh = dh; zb = db; } dh = -1; trou = 0; }
    }
    if (dh >= 0 && db - dh > zb - zh) { zh = dh; zb = db; }
    if (zh < 0 || zb - zh < 20 * s) return rien;
    // cadre marron au-dessus et au-dessous (dans la colonne du milieu et a un quart de la largeur)
    int xm = (x0 + x1) / 2, xq = x0 + larg / 4, haut = -1, bas = -1;
    for (int y = zh; y >= 0; y--) if (marron(xm, y) && marron(xq, y)) { haut = y + 1; break; }
    for (int y = zb; y < h; y++) if (marron(xm, y) && marron(xq, y)) { bas = y - 1; break; }
    if (haut < 0 || bas < 0 || bas - haut < 120 * s) return rien;      // interieur de la barre : ~187 unites de haut
    // poisson : pixels tres fonces (casquette, oeil) dans l'interieur
    // (le plus gros bloc de lignes foncees : la petite jarre en bas de la barre peut avoir du fonce, 25/10/2026)
    var fonces = new int[h];
    for (int y = haut; y <= bas; y++) { int f = 0; for (int x = x0; x <= x1; x++) { int o = y * st + x * 3; if (b[o] + b[o + 1] + b[o + 2] < 150 && b[o] - b[o + 1] >= 15) f++; } fonces[y] = f; }
    var pf = Bloc(fonces, 3, 6); int ph = pf[0], pb = pf[1];
    // jauge : a 13 unites a droite de l'interieur (rouge -> vert en se remplissant)
    int xj = x1 + 13 * s, jauge = 0;
    if (xj < w) for (int y = Math.Max(0, haut - 4 * s); y <= Math.Min(h - 1, bas + 8 * s); y++) { int o = y * st + xj * 3; if (b[o + 2] >= 200 || b[o + 1] >= 170) jauge++; }
    return new[] { nv, zh, zb, ph, pb, jauge, haut, bas, x0, x1 };
  }

  // Icone de la canne dans la barre d'objets : elle change quand la ligne est lancee (le fil disparait).
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  // zone de jeu (sans bordure ni titre) en coordonnees ecran
  public static Rectangle Client(IntPtr h) {
    RECT r; GetClientRect(h, out r); var p = new POINT(); ClientToScreen(h, ref p);
    return new Rectangle(p.X, p.Y, r.R - r.L, r.B - r.T);
  }
  public static byte[] Pixels(Rectangle ecran) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
      var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
      return b;
    }
  }
  public static double Ecart(byte[] a, byte[] b) {
    if (a == null || b == null || a.Length != b.Length) return 999;
    long s = 0; for (int i = 0; i < a.Length; i++) s += Math.Abs(a[i] - b[i]);
    return (double)s / a.Length;
  }
  public static void Sauver(Rectangle ecran, string fichier) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      bmp.Save(fichier, ImageFormat.Png);
    }
  }
}
'@

$script:Arret = $false
$script:Tenu = $false
# clic droit : directement a la fenetre du jeu en mode second plan
function Clic-Droit($bas) { if ([Fond]::Actif) { [Fond]::Clic($true, $bas) } else { [Peche]::ClicDroit($bas) } }
function Bouton($bas) { (Clic-Droit $bas); $script:Tenu = $bas }
function Relacher-Tout { (Clic-Droit $false); $script:Tenu = $false }
function Clic-Court { (Clic-Droit $true); Start-Sleep -Milliseconds 60; (Clic-Droit $false) }

$script:PidsJeu = @(Get-Process -Name javaw, java -ErrorAction SilentlyContinue | ForEach-Object { [uint32]$_.Id })
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
# Pause ou jeu au second plan : clic relache, attente de la touche pause. Renvoie $true s'il y a eu une pause.
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
  Relacher-Tout
  while ($true) {
    if (-not (Attendre-F7)) { return $true }
    if (Au-Premier-Plan) { break }
    Write-Host "$NomPause recu, mais le jeu n'est pas au premier plan : clique dans le jeu puis $NomPause."
  }
  Start-Sleep -Milliseconds 300
  Write-Host "Reprise"
  return $true
}
function Dormir($ms) {
  $fin = [Environment]::TickCount + $ms
  while ([Environment]::TickCount -lt $fin -and -not $script:Arret) { Start-Sleep -Milliseconds 15; if (Surveiller-Verification) { return $true }; if (Verifier) { return $true } }
  return $false
}

# ------------------------------ Argent ------------------------------
# (meme lecture que la ferme : "argent : N" toutes les 30 s pour les gains du menu)
$script:ProchaineLectureArgent = 0
function Lire-Argent {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  $larg = $r.R - $r.L
  if ($larg -lt 200) { return $null }
  $zone = New-Object System.Drawing.Rectangle ($r.L + [int]($larg * 0.15)), ($r.T + 8), ([int]($larg * 0.7)), 110
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

# ------------------------------ La barre ------------------------------
# Position de la barre : mesuree en 2560 x 1440, mise a l'echelle de l'ecran du jeu.
function Preparer-Barre {
  # grande zone de recherche autour du centre (la barre y est trouvee par sa zone verte et son cadre) :
  # de 200 unites a gauche du centre a 60 a droite, toute la hauteur
  $c = Client-Jeu; $s = $script:Gui
  $script:Ech = $s / 3.0
  $script:BarreLarge = New-Object System.Drawing.Rectangle ([Math]::Max($c.X, $c.X + [int]($c.Width / 2) - 200 * $s)), $c.Y, ([Math]::Min($c.Width, 260 * $s)), $c.Height
  $script:Barre = $script:BarreLarge
  $script:SeuilVert = 90 * $s * $s                    # zone entiere : ~520 unites carrees de vert
  $script:JaugePleine = 160 * $s                      # jauge pleine : ~200 unites de haut
}
function Mesure {
  if ($script:Fixe) { return [Peche]::Mesurer($script:Barre, $script:FX0, $script:FX1, $script:FY0, $script:FY1, $script:FXJ, $script:FXG, $script:FXD) }
  return [Peche]::Chercher($script:Barre, $script:Gui)
}
# barre trouvee : on ne lit plus que sa zone (plus rapide), avec l'interieur a des coordonnees fixes ;
# [m] = resultat de Mesure dans la grande zone
$script:Fixe = $false
function Fixer-Barre($m) {
  $s = $script:Gui; $L = $script:BarreLarge
  $haut = [Math]::Max(0, $m[6] - 15 * $s)
  $script:Barre = New-Object System.Drawing.Rectangle ($L.X + $m[8] - 12 * $s), ($L.Y + $haut), ($m[9] - $m[8] + 40 * $s), ($m[7] - $m[6] + 40 * $s)
  $script:FX0 = 12 * $s; $script:FX1 = $m[9] - $m[8] + 12 * $s                 # interieur (largeur de la zone verte)
  $script:FY0 = $m[6] - $haut; $script:FY1 = $m[7] - $haut
  $script:FXJ = $script:FX1 + 13 * $s                                          # jauge
  $script:FXG = $script:FX0 - 7 * $s; $script:FXD = $script:FX0 + $s           # bande ou chercher le cote gauche du cadre
  $script:CadreMin = 40                                                        # % du cote du cadre (barre : 76 a 96 % ; sans : 0 %)
  $script:Fixe = $true
}
function Liberer-Barre { $script:Barre = $script:BarreLarge; $script:Fixe = $false }
# la barre est-elle toujours la ? (fixee : son cadre ; sinon : zone verte + cadre trouves)
function Barre-Presente($m) {
  if ($script:Fixe) { return ($m[6] -ge $script:CadreMin) }
  return ($m[0] -ge $script:SeuilVert -and $m[1] -ge 0)
}

# Joue un mini-jeu jusqu'a ce que la barre disparaisse. Renvoie la derniere jauge lue (-1 si arret).
function Jouer-MiniJeu {
  $tol = $Tolerance * $script:Ech; $anticip = $AnticipMs / 1000.0; $aFrein = 300 * $script:Ech   # freinage prevu plus doux que le vrai (marge)
  $histo = New-Object System.Collections.Generic.List[double[]]   # { t (s), centre zone, centre poisson }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $absente = 0; $jauge = 0; $fc = $null
  # journal du mini-jeu (pour regler le script sur les poissons difficiles) : une ligne par image,
  # et quelques images de la barre, gardees seulement si le poisson est rate
  $dossierMJ = Join-Path $Dossier 'diagnostics\minijeux'; New-Item -ItemType Directory -Force $dossierMJ | Out-Null
  $script:MJNom = Join-Path $dossierMJ (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
  $script:MJImages = New-Object System.Collections.Generic.List[string]
  $journal = New-Object System.Text.StringBuilder
  [void]$journal.AppendLine('ms;zone_haut;zone_bas;poisson_haut;poisson_bas;jauge;clic')
  $prochaineImage = 1.0; $vuQqch = 0.0; $prochainEnreg = 2.0
  while (-not $script:Arret) {
    $m = Mesure
    $t = $sw.Elapsed.TotalSeconds
    [void]$journal.AppendLine(('{0};{1};{2};{3};{4};{5};{6}' -f [int]($t * 1000), $m[1], $m[2], $m[3], $m[4], $m[5], [int]$script:Tenu))
    if ($t -ge $prochaineImage -and $script:MJImages.Count -lt 8 -and $m[1] -ge 0) {
      $f = '{0}-{1:00}s.png' -f $script:MJNom, [int]$t; [Peche]::Sauver($script:Barre, $f); $script:MJImages.Add($f); $prochaineImage += 3
    }
    if (-not (Barre-Presente $m)) {
      if ($script:Tenu) { Relacher-Tout }                                 # tout de suite : un clic droit tenu relancerait la ligne
      if ($absente -eq 0) { $f = "{0}-fin.png" -f $script:MJNom; try { [Peche]::Sauver($script:Barre, $f); $script:MJImages.Add($f) } catch { } }   # image du moment ou la barre semble partie (gardee si rate)
      $absente++
      if ($absente -ge 12) { break }                                     # ~0,4 s sans barre : fini (moins, une fausse fin coupait le poisson en deux)
      Start-Sleep -Milliseconds 25; continue
    }
    $absente = 0; $jauge = $m[5]
    if ($m[1] -ge 0) { $vuQqch = $t }
    # ni zone ni poisson depuis 2 s (barre partie mais cadre cru vu, ou barre cachee) : on arrete, sans cliquer dans le vide
    if ($t - $vuQqch -gt 2.0 -or $t -gt 120) { Relacher-Tout; Write-Host ("  mini-jeu arrete : {0}" -f $(if ($t -gt 120) { "plus de 2 minutes" } else { "ni zone ni poisson vus depuis 2 s" })); break }
    if ($t -ge $prochainEnreg) { $prochainEnreg = $t + 2; try { [IO.File]::WriteAllText($script:MJNom + ".csv", $journal.ToString()) } catch { } }   # journal ecrit au fur et a mesure
    if ($m[1] -lt 0) { Start-Sleep -Milliseconds 10; continue }              # zone verte cachee (poisson devant) : on garde le clic tel quel
    $zc = ($m[1] + $m[2]) / 2.0
    if ($m[3] -ge 0) { $fc = $m[3] + 30 * $script:Ech; $vuQqch = $t }       # centre du poisson : haut de sa casquette bleu marine + 30 px (poisson de 59 px)
    if ($null -eq $fc) { Start-Sleep -Milliseconds 25; continue }
    # vitesses sur ~150 ms (la zone avance par a-coups, au rythme du serveur)
    $histo.Add([double[]]@($t, $zc, $fc))
    while ($histo.Count -gt 2 -and ($t - $histo[1][0]) -ge 0.15) { $histo.RemoveAt(0) }
    $vz = 0.0; $vf = 0.0
    $dt = $t - $histo[0][0]
    if ($dt -gt 0.05) { $vz = ($zc - $histo[0][1]) / $dt; $vf = ($fc - $histo[0][2]) / $dt }
    # Zone avec INERTIE (mesure du 25/10/2026 : relachee elle accelere vers le bas a ~560 px/s2, tenue vers le
    # haut a ~500 px/s2, jusqu'a ~630 px/s ; interface x3). Comme une voiture : il faut freiner AVANT le poisson.
    # Ou sera la zone quand le clic agira (anticipation), puis la vitesse qu'elle peut avoir a cet ecart pour
    # s'arreter pile sur le poisson en freinant a $aFrein : trop lente vers le poisson -> on accelere, sinon on freine.
    # Simulation sur les 10 mini-jeux enregistres : poisson dans la zone 78 % du temps (63 % avec l'ancienne methode).
    $ac = if ($script:Tenu) { -500 * $script:Ech } else { 560 * $script:Ech }
    $zp = $zc + $vz * $anticip + 0.5 * $ac * $anticip * $anticip; $vp = $vz + $ac * $anticip
    $e = $zp - ($fc + $vf * $anticip); $ev = $vp - $vf                  # y vers le bas : e > 0 = zone sous le poisson
    $vVoulue = -[Math]::Sign($e) * [Math]::Sqrt(2 * $aFrein * [Math]::Max(0, [Math]::Abs($e) - $tol))
    $voulu = ($ev -gt $vVoulue)                                          # pas assez vite vers le haut : on tient le clic
    if ($voulu -ne $script:Tenu) { Bouton $voulu }
    if (Verifier) { $histo.Clear(); $fc = $null; continue }
    Start-Sleep -Milliseconds 10
  }
  Relacher-Tout
  $script:MJDuree = $sw.Elapsed.TotalSeconds
  try { [IO.File]::WriteAllText($script:MJNom + '.csv', $journal.ToString()) } catch { }
  if ($script:Arret) { return -1 }
  return $jauge
}
# Apres l'issue : images gardees seulement si rate ; 40 journaux au plus (les plus anciens sont effaces).
function Fin-Journal-MiniJeu($garderImages, $is = $null, $issue = '', $source = '') {
  if (-not $garderImages) { foreach ($f in $script:MJImages) { Remove-Item $f -ErrorAction SilentlyContinue } }
  $dossierMJ = Join-Path $Dossier 'diagnostics\minijeux'
  # index pour chercher des schemas de mouvement par espece : fichier ; espece ; couleur du nom (rarete) ; issue
  $index = Join-Path $dossierMJ 'index.csv'
  if (-not (Test-Path $index)) { Set-Content $index 'fichier;date;espece;couleur;quantite;issue;source;duree_s' -Encoding UTF8 }
  $nom = if ($is -and $is.Nom) { $is.Nom } else { 'inconnu' }
  $ligne = '{0};{1:yyyy-MM-dd HH:mm:ss};{2};{3};{4};{5};{6};{7}' -f (Split-Path ($script:MJNom + '.csv') -Leaf), (Get-Date), $nom, $(if ($is -and $is.Hex) { $is.Hex } else { '' }), $(if ($is -and $is.Q) { $is.Q } else { '' }), $issue, $source, ([int]$script:MJDuree)
  Add-Content $index $ligne -Encoding UTF8
  # 300 mini-jeux gardes (~3 Mo) : assez pour comparer les especes
  Get-ChildItem $dossierMJ -Filter '20*.csv' | Sort-Object Name -Descending | Select-Object -Skip 300 | ForEach-Object {
    Remove-Item $_.FullName -ErrorAction SilentlyContinue
    Remove-Item ($_.FullName -replace '\.csv$', '-*.png') -ErrorAction SilentlyContinue
  }
}

# ------------------------------ Etat de la ligne ------------------------------
# Test du 24/10/2026 : a la fin d'un mini-jeu, le clic droit encore tenu a relance la ligne tout seul,
# puis le clic de relance l'a ramenee. Donc on regarde l'icone de la canne dans la barre d'objets
# (le fil disparait quand la ligne est dehors) avant de cliquer. Calibrage au depart : icone
# ligne rentree, puis ligne lancee. Si les deux sont pareilles (pack de textures), on clique a l'aveugle.
$script:IconeOK = $false; $script:IconeRentree = $null; $script:IconeLancee = $null
function Rect-Icone {
  $jeu = Get-Process -Id $script:PidsJeu -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
  $c = [Peche]::Client($jeu.MainWindowHandle)
  $s = $script:Gui                                                        # echelle de l interface
  $x = $c.X + [int]($c.Width / 2) - 91 * $s + 3 * $s + ($SlotCanne - 1) * 20 * $s
  return New-Object System.Drawing.Rectangle $x, ($c.Bottom - 19 * $s), (16 * $s), (16 * $s)
}
function Ligne-Dehors {
  if (-not $script:IconeOK) { return $null }
  $p = [Peche]::Pixels((Rect-Icone))
  return ([Peche]::Ecart($p, $script:IconeLancee) -lt [Peche]::Ecart($p, $script:IconeRentree))
}
function Calibrer-Icone {
  $r = Rect-Icone
  $script:IconeRentree = [Peche]::Pixels($r)
  Clic-Court; Write-Host "  ligne lancee"
  Start-Sleep -Milliseconds 800
  $script:IconeLancee = [Peche]::Pixels($r)
  $d = [Peche]::Ecart($script:IconeRentree, $script:IconeLancee)
  $diag = Join-Path $Dossier 'diagnostics'; New-Item -ItemType Directory -Force $diag | Out-Null
  [Peche]::Sauver($r, (Join-Path $diag 'canne-ligne-lancee.png'))
  # verification des sous-titres : juste apres le lancer, "Bobber thrown" doit etre affiche
  $st = Lire-SousTitres
  [Peche]::Sauver((Rect-SousTitres), (Join-Path $diag 'sous-titres-lancer.png'))
  if ($st -match 'obber|thrown|ouchon') { Write-Host ("Sous-titres lus : {0}" -f $st) }
  else { Write-Host ("Sous-titres : 'Bobber thrown' pas lu (lu : {0}). Sous-titres actives ? Les touches vanilla ne seront pas vues (relance au bout de {1} s)." -f $(if ($st) { $st } else { 'rien' }), $RelanceS) }
  if ($d -ge 4) { $script:IconeOK = $true; Write-Host ("Icone de la canne : ligne lancee reconnue (ecart {0:N1})." -f $d) }
  else { Write-Host ("Icone de la canne identique ligne lancee ou non (ecart {0:N1}) : je ne peux pas verifier la ligne, je clique a l'aveugle." -f $d) }
}
# Lance la ligne si elle n'est pas deja dehors, et verifie qu'elle est sortie.
function Lancer-Ligne {
  if ($script:IconeOK) {
    if (Ligne-Dehors) { Write-Host "  ligne deja lancee"; return }
    Clic-Court; Write-Host "  ligne lancee"
    Start-Sleep -Milliseconds 800
    if (-not (Ligne-Dehors)) { Clic-Court; Write-Host "  ligne pas sortie : nouveau lancer" }
  } else { Clic-Court; Write-Host "  ligne lancee" }
}

# ------------------------------ Espece ------------------------------
# Apres une prise, le chat affiche "Vous avez attrape un(e) Carpe ! [x3]" ; le nom a la couleur de
# sa rarete. On ne prend le message que sur la DERNIERE ligne du chat (sinon ce serait celui du
# poisson d'avant, encore affiche). Ecrit "espece : Carpe x3 #62A865" pour le menu.
function Client-Jeu {
  $jeu = Get-Process -Id $script:PidsJeu -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
  return [Peche]::Client($jeu.MainWindowHandle)
}
# Bas du chat seulement (test du 24/10/2026 : plus haut, les panneaux "FOUET DE FILS" / "CLONE"
# de gauche faussaient la grille des lignes la nuit). La ligne la plus recente est vers 0,90 de la hauteur.
function Rect-Chat {
  $c = Client-Jeu
  $s = $script:Gui                                                        # de 110 a 30 unites au-dessus du bas, 290 de large
  return New-Object System.Drawing.Rectangle ($c.X + 4), ($c.Bottom - 110 * $s), (290 * $s), (80 * $s)
}
# Gains d'une prise, au-dessus de la barre de vie : "+1389.98 (piece)  +1503.47 (fiole d'XP)", en vert clair.
# Mesure (2560 x 1440, interface x3) : de 130 a 0 unites a gauche du centre, de 80 a 58 unites au-dessus du bas.
function Rect-Gains {
  $c = Client-Jeu
  $s = $script:Gui
  return New-Object System.Drawing.Rectangle ($c.X + [int]($c.Width / 2) - 130 * $s), ($c.Bottom - 80 * $s), (133 * $s), (22 * $s)
}
# Sous-titres du jeu, colles au bord droit (capture du 24/10/2026 : "Splashing", "Bobber thrown >",
# lignes espacees de 10 rangees). A gauche et en dessous : les touches Z Q S / LMB RMB de Lunar, hors zone.
function Rect-SousTitres {
  $c = Client-Jeu
  $s = $script:Gui                                                        # 86 unites contre le bord droit, de 227 a 22 unites au-dessus du bas
  return New-Object System.Drawing.Rectangle ($c.Right - 86 * $s), ($c.Bottom - 227 * $s), (86 * $s), (205 * $s)
}
function Lire-SousTitres {
  $l = [Chat]::Lire((Rect-SousTitres), $script:Gui, 10)
  return (($l | ForEach-Object { $_.Texte }) -join ' | ')
}
# Touche (le bouchon plonge) : "Bobber splashes" en anglais ; en francais, une ligne avec "bouchon" qui n'est ni
# "Bouchon lance" ni "Bouchon recupere" (26/10/2026, texte francais exact pas encore vu). Le bouchon qui tombe a
# l'eau ("Splashing" / "Eclaboussures") ne contient pas "bouchon" : pas pris pour une touche.
function Touche-Vue {
  foreach ($ligne in [Chat]::Lire((Rect-SousTitres), $script:Gui, 10)) {
    $t = $ligne.Texte
    if ($t -match 'plashes' -or ($t -match 'ouchon' -and $t -notmatch 'lanc|cup')) { return $true }
  }
  return $false
}
$script:DiagChat = 0
# Photo du chat : base de chaque ligne -> ligne lue. Prise quand ca mord, puis apres le mini-jeu.
function Photo-Chat {
  $h = @{}
  foreach ($l in [Chat]::Lire((Rect-Chat), $script:Gui)) { $h[$l.Base] = $l }
  return $h
}
# Lignes arrivees depuis la photo d'avant. Test du 24/10/2026 : apres le poisson, le serveur a envoye
# deux autres messages (jobs, niveau), donc le message du poisson n'etait plus en bas. Chaque message
# fait monter les lignes de 27 px : on cherche le decalage qui retrouve le mieux les anciennes lignes ;
# les nouvelles sont celles qui viennent d'en dessous.
function Nouvelles-Lignes($avant, $apres) {
  $pas = 9 * $script:Gui                                                   # une ligne de chat = 9 pixels de police
  if ($apres.Count -eq 0) { return @() }
  if ($avant.Count -eq 0) { return @($apres.Keys | Sort-Object | ForEach-Object { $apres[$_] }) }
  $maxAvant = ($avant.Keys | Measure-Object -Maximum).Maximum
  $meilleurD = 0; $meilleur = 0
  for ($d = 0; $d -le 10; $d++) {
    $score = 0
    foreach ($b in $apres.Keys) { $src = $b + $d * $pas; if ($avant.ContainsKey($src) -and $avant[$src].Texte -eq $apres[$b].Texte) { $score++ } }
    if ($score -gt $meilleur) { $meilleur = $score; $meilleurD = $d }
  }
  if ($meilleur -eq 0) {   # anciennes lignes effacees (10 s) : nouvelle = pas la meme a la meme place
    return @($apres.Keys | Where-Object { -not ($avant.ContainsKey($_) -and $avant[$_].Texte -eq $apres[$_].Texte) } | Sort-Object | ForEach-Object { $apres[$_] })
  }
  return @($apres.Keys | Where-Object { $_ + $meilleurD * $pas -gt $maxAvant } | Sort-Object | ForEach-Object { $apres[$_] })
}
# Apres un mini-jeu : l'issue d'apres le chat ("Vous avez attrape un(e) Carpe ! [x3]" ou
# "Votre ligne s'est cassee..."), l'espece (avec la couleur de sa rarete) et les gains au-dessus de la vie.
function Lire-Issue($avant) {
  Start-Sleep -Milliseconds 300                                            # le temps que le message arrive
  $res = @{ Issue = $null }
  $fin = [Environment]::TickCount + 2500
  while ([Environment]::TickCount -lt $fin) {
    if (-not $res.Issue) {
      foreach ($l in (Nouvelles-Lignes $avant (Photo-Chat))) {
        $m = [regex]::Match($l.Texte, 'attrap\S*\s+\S+\s+(.+?)\s*!(?:\s*\[x(\d+)\])?')
        if ($m.Success) {
          $res.Issue = 'attrape'; $res.Nom = $m.Groups[1].Value; $res.Q = if ($m.Groups[2].Success) { [int]$m.Groups[2].Value } else { 1 }
          $r = 0; $g = 0; $b = 0; $k = 0                                    # couleur du nom : sa rarete
          for ($i = $m.Groups[1].Index; $i -lt $m.Groups[1].Index + $res.Nom.Length; $i++) { $c = $l.Couleurs[$i]; if (-not $c.IsEmpty) { $r += $c.R; $g += $c.G; $b += $c.B; $k++ } }
          $res.Hex = if ($k -gt 0) { '{0:X2}{1:X2}{2:X2}' -f [int]($r / $k), [int]($g / $k), [int]($b / $k) } else { '808080' }
          break
        }
        if ($l.Texte -match 'cass|chapp|perdu') { $res.Issue = 'rate'; $res.Texte = $l.Texte.Trim('? '); break }
      }
    }
    if ($res.Issue -eq 'attrape' -and -not $res.Argent) {
      $t = [Glyphes]::LireCouleur((Rect-Gains), 111, 221, 155, $script:Gui)
      $n = [regex]::Matches($t, '\+(\d+(?:\.\d+)?)')
      if ($n.Count -ge 2) { $res.Argent = $n[0].Groups[1].Value; $res.Xp = $n[1].Groups[1].Value }
    }
    if ($res.Issue -eq 'rate' -or ($res.Issue -eq 'attrape' -and $res.Argent)) { break }
    Start-Sleep -Milliseconds 200
  }
  if (-not $res.Issue) {
    # image du chat pour comprendre (10 au plus, les plus anciennes sont remplacees)
    $script:DiagChat = $script:DiagChat % 10 + 1
    $diag = Join-Path $Dossier 'diagnostics'; New-Item -ItemType Directory -Force $diag | Out-Null
    [Peche]::Sauver((Rect-Chat), (Join-Path $diag ("chat-pas-lu-{0}.png" -f $script:DiagChat)))
    $res.Diag = "chat-pas-lu-{0}.png" -f $script:DiagChat
  }
  return $res
}

# ------------------------------ Boucle ------------------------------
function Peche-Auto {
  if ($script:PidsJeu.Count -eq 0) { Write-Host "Le jeu n'est pas lance." -ForegroundColor Red; return }
  Preparer-Barre
  Write-Host ("Peche : anticipation {0} ms, tolerance {1} px, canne au slot {2}{3}." -f $AnticipMs, $Tolerance, $SlotCanne, $(if ($PoissonsMax -gt 0) { ", $PoissonsMax poissons max" } else { '' }))
  Write-Host "Dans le jeu : canne en main, ligne PAS lancee, chat et menu fermes, puis $NomPause. ($NomArret = annuler)"
  while ($true) {
    if (-not (Attendre-F7)) { return }
    if (Au-Premier-Plan) { break }
    Write-Host "$NomPause recu, mais le jeu n'est pas au premier plan : clique dans le jeu puis $NomPause."
  }
  Start-Sleep -Milliseconds 300
  $sc = [byte](0x01 + $SlotCanne)                                         # touches 1..9 : scancodes 0x02..0x0A
  [Entree]::Touche($sc, $true); Start-Sleep -Milliseconds 30; [Entree]::Touche($sc, $false)
  Start-Sleep -Milliseconds 200
  Write-Host "Peche lancee."
  Detecter-Interface; Preparer-Barre                                      # taille de l interface lue sur la barre d objets
  Suivre-Argent $true
  $attrapes = 0; $rates = 0; $vanilla = 0; $faussesTouches = 0; $script:VuSplash = $false
  Calibrer-Icone                                                          # premier lancer + photo de l'icone
  $premier = $true
  while (-not $script:Arret) {
    if ($premier) { $premier = $false } else { Lancer-Ligne }
    $debut = [Environment]::TickCount; $mord = $false; $controle = [Environment]::TickCount + 3000
    $prochainST = 0; $ignorerST = [Environment]::TickCount + 1500        # pas de sous-titre d'avant le lancer
    while (-not $script:Arret) {
      if (Verifier) { if (-not $script:Arret) { $debut = [Environment]::TickCount }; continue }
      $m = Mesure
      if ($m[0] -ge $script:SeuilVert -and $m[1] -ge 0) { $mord = $true; break }
      if (([Environment]::TickCount - $debut) -gt $RelanceS * 1000) { break }
      # touche vanilla : sous-titre "Bobber splashes" sans barre de mini-jeu dans les 0,8 s -> clic droit
      # pour ramener le poisson, puis relance. ("Splashing" = le bouchon qui tombe a l'eau : pas une touche.)
      if ([Environment]::TickCount -ge $prochainST) {
        $prochainST = [Environment]::TickCount + 150
        if ([Environment]::TickCount -ge $ignorerST -and (Touche-Vue)) {
          $barre = $false; $vu = [Environment]::TickCount; $finAttente = $vu + 1200   # 1,2 s : une touche vanilla reste accrochee 1 a 2 s
          while ([Environment]::TickCount -lt $finAttente) { $m = Mesure; if ($m[0] -ge $script:SeuilVert -and $m[1] -ge 0) { $barre = $true; break }; Start-Sleep -Milliseconds 30 }
          if ($barre) { Write-Host ("  touche : barre apres {0} ms" -f ([Environment]::TickCount - $vu)); $mord = $true; break }
          if (-not $script:VuSplash) { $script:VuSplash = $true; [Peche]::Sauver((Rect-SousTitres), (Join-Path (Join-Path $Dossier 'diagnostics') 'sous-titres-touche.png')) }
          # attrape pour de vrai = "+argent +xp" au-dessus de la vie (affichage different de celui d'avant le clic)
          $gainsAvant = [Glyphes]::LireCouleur((Rect-Gains), 111, 221, 155, $script:Gui)
          Clic-Court
          $n = $null; $finG = [Environment]::TickCount + 2000
          while ([Environment]::TickCount -lt $finG) {
            Start-Sleep -Milliseconds 200
            $t = [Glyphes]::LireCouleur((Rect-Gains), 111, 221, 155, $script:Gui)
            if ($t -ne $gainsAvant) { $n = [regex]::Matches($t, '\+(\d+(?:\.\d+)?)'); if ($n.Count -ge 1) { break } }
          }
          if ($n -and $n.Count -ge 2) { $vanilla++; Write-Host ("  poisson vanilla : attrape ({0} au total)" -f $vanilla); Write-Host ("  gain : argent {0} xp {1}" -f $n[0].Groups[1].Value, $n[1].Groups[1].Value) }
          elseif ($n -and $n.Count -eq 1) { $vanilla++; Write-Host ("  poisson vanilla : attrape ({0} au total), gain lu : +{1}" -f $vanilla, $n[0].Groups[1].Value) }
          else { $faussesTouches++; Write-Host ("  poisson vanilla : rien gagne, fausse touche ({0} au total)" -f $faussesTouches) }
          if (Dormir 700) { }
          Lancer-Ligne
          $ignorerST = [Environment]::TickCount + 3500                      # le sous-titre reste affiche ~3 s
          $debut = [Environment]::TickCount; $controle = [Environment]::TickCount + 3000
          continue
        }
      }
      # toutes les 3 s : la ligne est-elle toujours dehors ? (sinon on attendrait pour rien)
      if ($script:IconeOK -and [Environment]::TickCount -ge $controle) {
        $controle = [Environment]::TickCount + 3000
        if (-not (Ligne-Dehors)) { Write-Host "  ligne rentree : relance"; Lancer-Ligne; $debut = [Environment]::TickCount }
      }
      Suivre-Argent
      [void](Surveiller-Verification)
      Start-Sleep -Milliseconds 40
    }
    if ($script:Arret) { break }
    if (-not $mord) {
      Write-Host "  rien ne mord : on ramene la ligne et on relance"
      if ($script:IconeOK) { if (Ligne-Dehors) { Clic-Court } } else { Clic-Court }
      if (Dormir 800) { continue }; continue
    }
    $avant = Photo-Chat                                                   # pour reperer ensuite les nouveaux messages
    Fixer-Barre $m                                                        # on ne lit plus que la zone de la barre
    $j = Jouer-MiniJeu
    Liberer-Barre
    if ($j -lt 0) { break }
    $is = Lire-Issue $avant
    $issue = $is.Issue; $note = ''
    if (-not $issue) {                                                    # chat pas lu : d'apres la jauge
      $issue = if ($j -ge $script:JaugePleine) { 'attrape' } else { 'rate' }
      $note = " (chat pas lu, d'apres la jauge - image {0})" -f $is.Diag
    }
    if ($issue -eq 'attrape') {
      $attrapes++; Write-Host ("  poisson attrape ({0} au total){1}" -f $attrapes, $note)
      if ($is.Nom) { Write-Host ("  espece : {0} x{1} #{2}" -f $is.Nom, $is.Q, $is.Hex) }
      if ($is.Argent) { Write-Host ("  gain : argent {0} xp {1}" -f $is.Argent, $is.Xp) } else { Write-Host "  gain : pas lu" }
    } else {
      $rates++; Write-Host ("  poisson rate ({0} au total){1}" -f $rates, $(if ($is.Texte) { " : " + $is.Texte } else { $note }))
    }
    Fin-Journal-MiniJeu ($issue -ne 'attrape') $is $issue $(if ($is.Issue) { 'chat' } else { 'jauge' })
    Suivre-Argent
    if ($PoissonsMax -gt 0 -and $attrapes -ge $PoissonsMax) { Write-Host "Nombre de poissons maximal atteint."; break }
    if (Dormir $AttenteMs) { }
  }
  Suivre-Argent $true
  Write-Host ("Peche terminee : {0} poissons attrapes, {1} rates, {2} vanilla attrapes, {3} fausses touches." -f $attrapes, $rates, $vanilla, $faussesTouches)
}

try { Peche-Auto }
finally {
  Relacher-Tout
  Write-Host "Toutes les touches sont relachees."
}
