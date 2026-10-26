# =====================================================================
#  canne-etage.ps1 : recolte de la ferme a canne a pied, sans fly, etage par etage (12 etages, echelle entre deux etages)
#
#  Ferme 80 x 80 fermee par un mur a hauteur de tete sur les 4 cotes.
#  Tu regardes vers l'EST (ou l'OUEST), colle au mur de depart.
#  Q / D : traversee nord-sud, clic gauche tenu, jusqu'a buter contre le mur
#          (le mur arrete le personnage : plus aucune derive possible).
#  Z     : on avance de 2 blocs entre deux traversees, en lisant la position.
#  L'avance ne depasse jamais 78 blocs depuis le depart : on ne touche pas
#  le mur d'en face, donc on ne passe jamais par les trous des coins.
#
#  POSITION : lue a l'ecran dans l'affichage des coordonnees de Lunar,
#  en haut a gauche (lignes "X: ...", "Y: ...", "Z: ...").
#
#  SECURITES
#    F8 : arret immediat (toutes les touches relachees)
#    F7 : pause / reprise
#    Jeu plus au premier plan : tout est relache, puis attente de F7.
#    Si ta hauteur (Y) baisse : arret immediat (chute).
#
#  LANCEMENT :
#    powershell -ExecutionPolicy Bypass -File "D:\macros-minecraft\canne-etage.ps1"
#  Puis : dans le jeu, colle au mur de depart, en visant les cannes, F7.
# =====================================================================

# Reglages passes par le menu (Ferme-canne.exe). Sans eux, ceux du bloc A REGLER s'appliquent.
param([int]$EtageDepart = 0, [int]$VenteSeuil = -1, [int]$VenteMs = -1, [int]$Pas = 0, [int]$MargeEchelle = -1, [string]$RecalerRegard = '', [int]$Tours = 0, [int]$TouchePause = 0x76, [int]$ToucheArret = 0x77, [int]$RepondreVerif = 0, [int]$Sons = 1)

# ------------------------------ A REGLER -----------------------------
$Config = @{
  Orientation  = 'ouest'      # ou tu regardes au 1er etage : 'est' ou 'ouest' (s'inverse a chaque etage)
  NbEtages     = 9         # etages a enchainer (echelle au bout de chaque etage, sauf le dernier)
  Montee       = 4          # blocs entre deux etages
  PremierSens  = 'droite'   # 1re traversee : 'droite' (D) ou 'gauche' (Q)
  Pas          = 2          # blocs avances en Z entre deux traversees (3 teste : laisse des cannes)
  AvanceMax    = 76         # blocs maximum avances depuis le depart. Pas 2 : 76 ; pas 3 : 78 (la derniere traversee doit etre a 3 blocs au plus du mur d'en face)

  AppuiMs      = 100        # petites pressions pendant la traversee : enfoncee...
  RelacheMs    = 0          # ...puis relachee (0 = touche tenue en continu)
  CentrageMs   = 0          # apres chaque avance : petit appui de plus pour se placer au milieu du bloc (0 = desactive)
  VenteSeuil   = 2176       # cannes dans l'inventaire (compteur en bas a droite) : a partir de la, on vend (0 = jamais)
  VenteMs      = 100        # apres le clic de vente, temps avant de revenir au slot 2
  MargeEchelle = 4          # derniere traversee : clic relache a ce nombre de blocs du mur (l'echelle est au bout)
  MurMs        = 400        # touche enfoncee sans changer de bloc pendant ce temps = mur atteint
  TraverseeMaxS = 60        # securite : une traversee ne dure jamais plus

  RecalerRegard = $true     # a chaque F7 : ouvre F3, lit l'orientation et tourne la souris pile vers l'est / l'ouest
  SeuilF3      = 210        # texte de F3 : gris clair (224) ...
  EchelleF3    = 3          # ... agrandi 3 fois (echelle d'interface du jeu)

  ProgrammeJeu = @('javaw', 'java')   # Lunar Client = javaw
  # Coordonnees en haut a gauche : position des nombres depuis le coin de la fenetre
  HudX = 44; HudLigneX = 44; HudLigneY = 66; HudLigneZ = 88; HudLargeur = 120; HudHauteur = 16
}
# ---------------------------------------------------------------------
$Config.EtageDepart = 1
if ($EtageDepart -ge 1) {
  $Config.EtageDepart = $EtageDepart
  $Config.NbEtages = 13 - $EtageDepart                                   # jusqu'au 12e
  $Config.Orientation = if ($EtageDepart % 2 -eq 1) { 'est' } else { 'ouest' }   # impairs : est, pairs : ouest
}
if ($VenteSeuil -ge 0) { $Config.VenteSeuil = $VenteSeuil }
if ($VenteMs -ge 0) { $Config.VenteMs = $VenteMs }
if ($Pas -ge 1) { $Config.Pas = $Pas; $Config.AvanceMax = if ($Pas -eq 3) { 78 } else { 76 } }   # Pas 25 = 2 et 3 en alternance
if ($MargeEchelle -ge 0) { $Config.MargeEchelle = $MargeEchelle }
$Config.Tours = $Tours   # 0 = a l'infini (jusqu'a F8 / Arreter)
if ($RecalerRegard -ne '') { $Config.RecalerRegard = ($RecalerRegard -eq '1') }

$Dossier = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -AssemblyName System.Windows.Forms
$NomPause = ([System.Windows.Forms.Keys]$TouchePause).ToString()   # nom affiche des touches (F7, F8, Pause...)
$NomArret = ([System.Windows.Forms.Keys]$ToucheArret).ToString()

# Codes de POSITION des touches : Z/Q/S/D en AZERTY.
$Touche = @{ avant = 0x11; arriere = 0x1F; gauche = 0x1E; droite = 0x20 }

# Pour chaque orientation : axe et signe de "droite" et de "avant" (0 = X, 2 = Z).
$TableAxes = @{
  est   = @{ lat = 2; latSigne =  1; av = 0; avSigne =  1 }
  sud   = @{ lat = 0; latSigne = -1; av = 2; avSigne =  1 }
  ouest = @{ lat = 2; latSigne = -1; av = 0; avSigne = -1 }
  nord  = @{ lat = 0; latSigne =  1; av = 2; avSigne = -1 }
}
$Axes = $TableAxes[$Config.Orientation]

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

public static class Entree {
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint data; public uint dwFlags; public uint time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public static void Touche(ushort scan, bool bas) {
    if (Fond.Actif) { Fond.Touche(scan, bas); return; }   // mode second plan : directement a la fenetre du jeu
    var i = new INPUT { type = 1 };
    i.u.ki.wScan = scan;
    i.u.ki.dwFlags = 0x0008 | (bas ? 0u : 0x0002u);
    SendInput(1, new[] { i }, Marshal.SizeOf(typeof(INPUT)));
  }
  // Clic gauche par mouse_event, comme les mouvements : avec SendInput, un evenement souris
  // a deja ete perdu (21/10/2026) ; un "relache" perdu laisse le clic enfonce et casse l'echelle.
  public static void ClicGauche(bool bas) { if (Fond.Actif) { Fond.Clic(false, bas); return; } mouse_event(bas ? 0x0002u : 0x0004u, 0, 0, 0, IntPtr.Zero); }
  // Mouvement relatif de la souris. (Teste le 21/10/2026 : mouse_event fait tourner la vue
  // dans le jeu, alors que SendInput n'avait pas d'effet.)
  [DllImport("user32.dll")] static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  public static void Souris(int dx, int dy) { mouse_event(0x0001u, dx, dy, 0, IntPtr.Zero); }
  public static bool Appuyee(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
  public static IntPtr FenetrePremierPlan() { return GetForegroundWindow(); }
  public static uint PidDe(IntPtr h) { uint pid; GetWindowThreadProcessId(h, out pid); return pid; }
}

// Mode "second plan" (minage, peche) : touches et clics envoyes DIRECTEMENT a la fenetre du jeu
// (PostMessage), jamais a la fenetre au premier plan. Teste le 25/10/2026 (outils\test-second-plan.ps1) :
// Lunar accepte touches, clic droit et clic gauche tenu, a condition que F3 + P ait desactive la pause.
public static class Fond {
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out Entree.RECT r);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  public static IntPtr Fenetre = IntPtr.Zero;
  public static bool Actif { get { return Fenetre != IntPtr.Zero; } }
  // le jeu est la et pas reduit (au second plan, il doit rester visible : on lit l'ecran)
  public static bool Visible() { return IsWindow(Fenetre) && !IsIconic(Fenetre); }
  static IntPtr Centre() { Entree.RECT r; GetClientRect(Fenetre, out r); int x = (r.R - r.L) / 2, y = (r.B - r.T) / 2; return (IntPtr)((y << 16) | (x & 0xFFFF)); }
  public static void Touche(ushort scan, bool bas) {
    uint vk = MapVirtualKey(scan, 1);   // code de position -> touche virtuelle
    long l = 1 | ((long)scan << 16);
    if (!bas) l |= (1L << 30) | (1L << 31);
    PostMessage(Fenetre, bas ? 0x0100u : 0x0101u, (IntPtr)vk, (IntPtr)l);
  }
  public static void Clic(bool droit, bool bas) {
    uint msg = droit ? (bas ? 0x0204u : 0x0205u) : (bas ? 0x0201u : 0x0202u);
    PostMessage(Fenetre, msg, (IntPtr)(bas ? (droit ? 2 : 1) : 0), Centre());
  }
  public static void Caractere(char c) { PostMessage(Fenetre, 0x0102u, (IntPtr)c, (IntPtr)1); }   // WM_CHAR (texte du chat)
}

// Taille de l'interface du jeu, trouvee sur la barre d'objets (26/10/2026 : pour qu'un autre joueur n'ait pas a la
// regler a 3). La barre fait 182 x taille de large, ses cases sont espacees de 20 x taille : le bas des cases (leur
// cadre, sans l'objet) se repete exactement tous les 20 x taille pixels. Pour chaque taille : ecart entre un pixel
// et celui 20 x taille plus loin, divise par l'ecart pour un decalage quelconque (7 x taille). Le plus petit gagne.
// Captures de l'auteur (taille 3) : 0,12 a 0,29 pour 3, plus de 1 pour les autres. 0 si rien de net (< 0,6).
public static class Interface {
  [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out Entree.RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  public static Rectangle Client(IntPtr h) { Entree.RECT r; GetClientRect(h, out r); var p = new POINT(); ClientToScreen(h, ref p); return new Rectangle(p.X, p.Y, r.R - r.L, r.B - r.T); }
  public static int Taille(IntPtr fenetre) {
    var c = Client(fenetre); if (c.Width < 400 || c.Height < 200) return 0;
    var bas = new Rectangle(c.X, c.Bottom - 100, c.Width, 100);
    using (var bmp = new Bitmap(bas.Width, bas.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(bas.Location, Point.Empty, bas.Size);
      return Taille(bmp);
    }
  }
  public static int Taille(Bitmap bmp) {
    var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
    int w = bmp.Width, h = bmp.Height, st = bd.Stride, cx = w / 2, meilleure = 0; double mieux = 0.6;
    for (int s = 1; s <= 4; s++) {
      double dPer = 0, dAutre = 0; int n = 0;
      foreach (int dy in new[] { 1, 2 }) {
        int y = h - dy * s - s / 2; if (y < 0) continue;
        for (int x = cx - 90 * s; x < cx + 70 * s; x++) {
          int x2 = x + 20 * s, x3 = x + 7 * s; if (x < 0 || x2 >= w) continue;
          int o = y * st + x * 3, o2 = y * st + x2 * 3, o3 = y * st + x3 * 3;
          for (int k = 0; k < 3; k++) { dPer += Math.Abs(b[o + k] - b[o2 + k]); dAutre += Math.Abs(b[o + k] - b[o3 + k]); }
          n++;
        }
      }
      if (n == 0) continue;
      double sc = (dPer + 1) / (dAutre + 1);
      if (sc < mieux) { mieux = sc; meilleure = s; }
    }
    return meilleure;
  }
}

// Lecture du texte de Minecraft par comparaison exacte avec des modeles
// (police pixel : un caractere est toujours dessine de la meme facon).
public static class Glyphes {
  public static Dictionary<string, char> Modeles = new Dictionary<string, char>();
  public const int Seuil = 225;
  public static int Echelle = 2;   // taille du texte des coordonnees (2 chez l auteur) ; trouvee par TrouverCoordonnees

  public static void Charger(string fichier) {
    foreach (var l in System.IO.File.ReadAllLines(fichier)) {
      if (l.Length < 3 || l[0] == '#') continue;
      Modeles[l.Substring(2)] = l[0];
    }
  }

  public static string Lire(Rectangle ecran) { return Lire(ecran, Echelle); }
  public static string Lire(Rectangle ecran, int ech) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
      var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
      int w = bmp.Width, h = bmp.Height;
      Func<int, int, bool> px = (x, y) => { int o = y * bd.Stride + x * 3; return b[o] >= Seuil && b[o + 1] >= Seuil && b[o + 2] >= Seuil; };
      int haut = -1, bas = -1;
      for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) if (px(x, y)) { if (haut < 0) haut = y; bas = y; break; }
      if (haut < 0) return "";
      int lignes = (h - haut + ech - 1) / ech; if (lignes > 8) lignes = 8;
      var sb = new StringBuilder();
      int x0 = -1;
      for (int x = 0; x <= w; x++) {
        bool v = false;
        if (x < w) for (int y = haut; y < h; y++) if (px(x, y)) { v = true; break; }
        if (v && x0 < 0) x0 = x;
        if (!v && x0 >= 0) {
          int larg = (x - x0 + ech - 1) / ech;
          var k = new StringBuilder();
          for (int gy = 0; gy < 8; gy++) {
            if (gy > 0) k.Append('/');
            for (int gx = 0; gx < larg; gx++) {
              int cx = x0 + gx * ech + ech / 2, cy = haut + gy * ech + ech / 2;
              k.Append(cx < w && cy < h && px(cx, cy) ? '#' : '.');
            }
          }
          char c;
          if (Modeles.TryGetValue(k.ToString(), out c)) sb.Append(c);
          else if (larg == 5) sb.Append('2');   // seul chiffre jamais vu a l'apprentissage : par elimination
          else sb.Append('?');
          x0 = -1;
        }
      }
      return sb.ToString();
    }
  }

  // Coordonnees de Lunar cherchees automatiquement (26/10/2026 : pour qu'un autre joueur n'ait pas a les placer
  // au pixel pres). Dans la zone : les lignes de texte blanc dont le dernier mot est un nombre entier, a une
  // taille de 1 a 4 ; les trois premieres qui se suivent, alignees, sont X, Y et Z ("C: 188/1", "Biome",
  // "FPS", "Ping: 15 ms" ne finissent pas par un nombre entier).
  // Renvoie { echelle, x du nombre, largeur, haut X, haut Y, haut Z, hauteur } (coordonnees dans la zone), ou null.
  public static int[] TrouverCoordonnees(Rectangle ecran) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      return TrouverCoordonnees(bmp);
    }
  }
  public static int[] TrouverCoordonnees(Bitmap bmp) {
    var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
    int w = bmp.Width, h = bmp.Height, st = bd.Stride;
    Func<int, int, bool> px = (x, y) => { int o = y * st + x * 3; return b[o] >= Seuil && b[o + 1] >= Seuil && b[o + 2] >= Seuil; };
    // bord gauche du texte : premiere colonne avec du blanc
    int xl = -1;
    for (int x = 0; x < w && xl < 0; x++) for (int y = 0; y < h; y++) if (px(x, y)) { xl = x; break; }
    if (xl < 0) return null;
    // pour chaque taille possible : une bande juste assez large pour "X: -123456789" (11 caracteres de 6 pixels
    // de police) ; plus a droite, Lunar dessine la boussole (- / W / B...) sur les memes lignes (26/10/2026)
    for (int e = 1; e <= 4; e++) {
      int xr = Math.Min(w, xl + 70 * e);
      var ok = new bool[h];
      for (int y = 0; y < h; y++) for (int x = xl; x < xr; x++) if (px(x, y)) { ok[y] = true; break; }
      var lignes = new List<int[]>();   // { haut, x du nombre }
      int yy = 0;
      while (yy < h) {
        if (!ok[yy]) { yy++; continue; }
        int haut = yy; while (yy < h && ok[yy]) yy++;
        int hb = yy - haut;
        if (Math.Abs(hb - 7 * e) > e / 2) continue;                              // chiffres : 7 pixels de police de haut
        // caracteres, regroupes en mots (espace = vide de 3 pixels de police ou plus)
        var mots = new List<List<int[]>>(); int x0 = -1, fin = -100;
        for (int x = xl; x <= xr; x++) {
          bool v = false;
          if (x < xr) for (int y = haut; y < haut + hb; y++) if (px(x, y)) { v = true; break; }
          if (v && x0 < 0) { if (x - fin >= 3 * e || mots.Count == 0) mots.Add(new List<int[]>()); x0 = x; }
          if (!v && x0 >= 0) { mots[mots.Count - 1].Add(new[] { x0, x }); fin = x; x0 = -1; }
        }
        if (mots.Count < 2) continue;
        // le mot juste apres l'etiquette ("X:") doit etre un nombre entier
        var sb = new StringBuilder();
        foreach (var c in mots[1]) {
          int larg = (c[1] - c[0] + e - 1) / e;
          var m = new StringBuilder();
          for (int gy = 0; gy < 8; gy++) {
            if (gy > 0) m.Append('/');
            for (int gx = 0; gx < larg; gx++) { int cx = c[0] + gx * e + e / 2, cy = haut + gy * e + e / 2; m.Append(cx < w && cy < h && px(cx, cy) ? '#' : '.'); }
          }
          char ch; sb.Append(Modeles.TryGetValue(m.ToString(), out ch) ? ch : '?');
        }
        if (System.Text.RegularExpressions.Regex.IsMatch(sb.ToString(), @"^-?\d{1,9}$")) lignes.Add(new[] { haut, mots[1][0][0] });
      }
      // trois lignes de suite, nombres alignes a gauche, ecart regulier : X, Y, Z
      for (int i = 0; i + 2 < lignes.Count; i++) {
        var a = lignes[i]; var c1 = lignes[i + 1]; var c2 = lignes[i + 2];
        if (Math.Abs(c1[1] - a[1]) > 2 * e || Math.Abs(c2[1] - a[1]) > 2 * e) continue;
        int d1 = c1[0] - a[0], d2 = c2[0] - c1[0];
        if (Math.Abs(d1 - d2) > e || d1 > 14 * e) continue;
        int gauche = Math.Max(0, Math.Min(a[1], Math.Min(c1[1], c2[1])) - e);
        return new[] { e, gauche, Math.Min(w - gauche, 60 * e), a[0], c1[0], c2[0], 8 * e };
      }
    }
    return null;
  }

  // Compteur d'objets (en bas a droite) cherche automatiquement : le nombre SEUL (mot unique en chiffres) le plus
  // a droite de la zone, a une taille de 1 a 4. Renvoie { echelle, x, y, largeur, hauteur } dans la zone, ou null.
  public static int[] TrouverCompteur(Rectangle ecran) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      return TrouverCompteur(bmp);
    }
  }
  public static int[] TrouverCompteur(Bitmap bmp) {
    var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
    int w = bmp.Width, h = bmp.Height, st = bd.Stride;
    Func<int, int, bool> px = (x, y) => { int o = y * st + x * 3; return b[o] >= Seuil && b[o + 1] >= Seuil && b[o + 2] >= Seuil; };
    var ok = new bool[h];
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) if (px(x, y)) { ok[y] = true; break; }
    int[] meilleur = null; int droite = -1;
    int yy = 0;
    while (yy < h) {
      if (!ok[yy]) { yy++; continue; }
      int haut = yy; while (yy < h && ok[yy]) yy++;
      int hb = yy - haut, e = (int)Math.Round(hb / 7.0);
      if (e < 1 || e > 4 || Math.Abs(hb - 7 * e) > e / 2) continue;
      // mots de la bande
      var mots = new List<List<int[]>>(); int x0 = -1, fin = -100;
      for (int x = 0; x <= w; x++) {
        bool v = false;
        if (x < w) for (int y = haut; y < haut + hb; y++) if (px(x, y)) { v = true; break; }
        if (v && x0 < 0) { if (x - fin >= 3 * e || mots.Count == 0) mots.Add(new List<int[]>()); x0 = x; }
        if (!v && x0 >= 0) { mots[mots.Count - 1].Add(new[] { x0, x }); fin = x; x0 = -1; }
      }
      foreach (var mot in mots) {
        var sb = new StringBuilder();
        foreach (var c in mot) {
          int larg = (c[1] - c[0] + e - 1) / e;
          var m = new StringBuilder();
          for (int gy = 0; gy < 8; gy++) {
            if (gy > 0) m.Append('/');
            for (int gx = 0; gx < larg; gx++) { int cx = c[0] + gx * e + e / 2, cy = haut + gy * e + e / 2; m.Append(cx < w && cy < h && px(cx, cy) ? '#' : '.'); }
          }
          char ch; sb.Append(Modeles.TryGetValue(m.ToString(), out ch) ? ch : '?');
        }
        int fx = mot[mot.Count - 1][1];
        if (System.Text.RegularExpressions.Regex.IsMatch(sb.ToString(), @"^\d{1,5}$") && fx > droite) {
          droite = fx;
          int gauche = Math.Max(0, fx - 6 * e * 6);                                  // jusqu'a 6 chiffres, cale a droite
          meilleur = new[] { e, gauche, Math.Max(0, haut - 1), Math.Min(w - gauche, fx - gauche + 2 * e), 8 * e + 2 };
        }
      }
    }
    return meilleur;
  }

  // Lit toutes les lignes de texte clair d'une zone de l'ecran (texte de F3 : gris tres clair,
  // agrandi $ech fois). Chaque ligne est decoupee en caracteres comme Lire().
  public static List<string> Lignes(Rectangle ecran, int seuil, int ech) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      return Lignes(bmp, seuil, ech);
    }
  }
  public static List<string> Lignes(Bitmap bmp, int seuil, int ech) {
    var res = new List<string>();
    {
      var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
      var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
      int w = bmp.Width, h = bmp.Height, stride = bd.Stride;
      Func<int, int, bool> px = (x, y) => { int o = y * stride + x * 3; int r = b[o + 2], gg = b[o + 1], bl = b[o]; return r >= seuil && gg >= seuil && bl >= seuil && Math.Abs(r - bl) < 16; };
      var ligneOk = new bool[h];
      for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) if (px(x, y)) { ligneOk[y] = true; break; }
      int yy = 0;
      while (yy < h) {
        if (!ligneOk[yy]) { yy++; continue; }
        int haut = yy; while (yy < h && ligneOk[yy]) yy++;
        int bas = Math.Min(h - 1, haut + 9 * ech);
        var sb = new StringBuilder(); int x0 = -1;
        for (int x = 0; x <= w; x++) {
          bool v = false;
          if (x < w) for (int y = haut; y < bas; y++) if (px(x, y)) { v = true; break; }
          if (v && x0 < 0) x0 = x;
          if (!v && x0 >= 0) {
            int larg = (x - x0 + ech - 1) / ech;
            var k = new StringBuilder();
            for (int gy = 0; gy < 8; gy++) {
              if (gy > 0) k.Append('/');
              for (int gx = 0; gx < larg; gx++) { int cx = x0 + gx * ech + ech / 2, cy = haut + gy * ech + ech / 2; k.Append(cx < w && cy < h && px(cx, cy) ? '#' : '.'); }
            }
            char c;
            if (Modeles.TryGetValue(k.ToString(), out c)) sb.Append(c); else if (larg == 5) sb.Append('2'); else sb.Append('?');
            x0 = -1;
          }
        }
        res.Add(sb.ToString());
      }
    }
    return res;
  }

  // Argent affiche en haut de l'ecran (texte jaune 255/188/53, agrandi 3 fois, ex. "31.78M").
  // Renvoie le texte de la premiere ligne jaune trouvee dans la zone, "" si rien.
  public static string LireCouleur(Rectangle ecran, int rr, int gg, int bb, int ech) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      return LireCouleur(bmp, rr, gg, bb, ech);
    }
  }
  public static string LireCouleur(Bitmap bmp, int rr, int gg, int bb, int ech) {
    var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
    int w = bmp.Width, h = bmp.Height, stride = bd.Stride;
    Func<int, int, bool> px = (x, y) => { int o = y * stride + x * 3; return Math.Abs(b[o + 2] - rr) <= 12 && Math.Abs(b[o + 1] - gg) <= 14 && Math.Abs(b[o] - bb) <= 30; };
    int haut = -1;
    for (int y = 0; y < h && haut < 0; y++) for (int x = 0; x < w; x++) if (px(x, y)) { haut = y; break; }
    if (haut < 0) return "";
    int bas = Math.Min(h, haut + 8 * ech);
    var sb = new StringBuilder(); int x0 = -1, vide = 0;
    for (int x = 0; x <= w; x++) {
      bool v = false;
      if (x < w) for (int y = haut; y < bas; y++) if (px(x, y)) { v = true; break; }
      if (v && x0 < 0) { if (sb.Length > 0 && vide >= 3 * ech) sb.Append(' '); x0 = x; }
      if (!v && x0 < 0) vide++;
      if (!v && x0 >= 0) {
        int larg = (x - x0 + ech - 1) / ech;
        var k = new StringBuilder();
        for (int gy = 0; gy < 8; gy++) {
          if (gy > 0) k.Append('/');
          for (int gx = 0; gx < larg; gx++) { int cx = x0 + gx * ech + ech / 2, cy = haut + gy * ech + ech / 2; k.Append(cx < w && cy < h && px(cx, cy) ? '#' : '.'); }
        }
        char c;
        if (Modeles.TryGetValue(k.ToString(), out c)) sb.Append(c); else if (larg == 5) sb.Append('2'); else sb.Append('?');
        x0 = -1; vide = 1;
      }
    }
    return sb.ToString().Trim();
  }
}

// Gros message au centre de l'ecran (titre de Minecraft, ex. "VERIFICATION : taper 2 dans le chat").
// Signature : chaque pixel du texte a son ombre decalee d'un pixel de police (titre : 4 x l'echelle de
// l'interface, soit 12 px en interface x3 ; sous-titre : 6 px), de couleur egale au quart du texte.
// Score = nombre de pixels (1 sur 4) qui ont cette ombre. Le monde du jeu n'en donne presque jamais.
public static class Titre {
  public static int Score(Rectangle ecran, int[] decalages) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      return Score(bmp, decalages);
    }
  }
  public static int Score(Bitmap bmp, int[] decalages) {
    var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
    int w = bmp.Width, h = bmp.Height, s = bd.Stride, n = 0;
    foreach (int d in decalages)
      for (int y = 0; y + d < h; y += 2) for (int x = 0; x + d < w; x += 2) {
        int o = y * s + x * 3, r = b[o + 2], gg = b[o + 1], bl = b[o];
        if (Math.Max(r, Math.Max(gg, bl)) < 120) continue;
        int q = (y + d) * s + (x + d) * 3;
        if (Math.Abs(b[q + 2] - r / 4) <= 5 && Math.Abs(b[q + 1] - gg / 4) <= 5 && Math.Abs(b[q] - bl / 4) <= 5) n++;
      }
    return n;
  }
  public static void SauverEcran(Rectangle ecran, string fichier) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      bmp.Save(fichier, ImageFormat.Png);
    }
  }
}
'@

[Glyphes]::Charger((Join-Path $Dossier 'police.txt'))

$script:Arret = $false
$script:ToucheTenue = $null
$script:ClicTenu = $false
$script:DernierePos = $null

function Relacher-Tout {
  if ($null -ne $script:ToucheTenue) { [Entree]::Touche($script:ToucheTenue, $false); $script:ToucheTenue = $null }
  if ($script:ClicTenu) { [Entree]::ClicGauche($false); $script:ClicTenu = $false }
}
function Enfoncer($t) { [Entree]::Touche($t, $true); $script:ToucheTenue = $t }
function Lacher { if ($null -ne $script:ToucheTenue) { [Entree]::Touche($script:ToucheTenue, $false); $script:ToucheTenue = $null } }
function Clic($bas) { [Entree]::ClicGauche($bas); $script:ClicTenu = $bas }

# Le jeu est reconnu par son PROGRAMME (javaw), pas par le titre de fenetre
# (une video YouTube "Minecraft" dans Chrome a aussi ce mot dans son titre).
$script:PidsJeu = @(Get-Process -Name $Config.ProgrammeJeu -ErrorAction SilentlyContinue | ForEach-Object { [uint32]$_.Id })
. (Join-Path $Dossier 'verification.ps1')                       # gros message au centre (verification) : images seulement
function Au-Premier-Plan { return $script:PidsJeu -contains [Entree]::PidDe([Entree]::FenetrePremierPlan()) }

function Attendre-Relache($vk) { while ([Entree]::Appuyee($vk)) { Start-Sleep -Milliseconds 30 } }
function Attendre-F7 {
  Attendre-Relache $TouchePause
  while (-not [Entree]::Appuyee($TouchePause)) {
    if ([Entree]::Appuyee($ToucheArret) -or (Arret-Demande)) { $script:Arret = $true; return $false }
    Start-Sleep -Milliseconds 30
  }
  Attendre-Relache $TouchePause
  return $true
}

# Bouton Arreter du menu : il cree ce fichier, le script s'arrete comme avec F8.
$script:FichierArret = Join-Path $Dossier 'arret.flag'
if (Test-Path $script:FichierArret) { Remove-Item $script:FichierArret -Force }
function Arret-Demande { return (Test-Path $script:FichierArret) }

function Verifier {
  if ([Entree]::Appuyee($ToucheArret) -or (Arret-Demande)) { $script:Arret = $true; Relacher-Tout; return $true }
  if ([Entree]::Appuyee($TouchePause)) {
    Relacher-Tout
    Write-Host "PAUSE ($NomPause = reprendre, $NomArret = arreter)" -ForegroundColor Yellow
    if (-not (Attendre-F7)) { return $true }
    Write-Host "Reprise" -ForegroundColor Green
    $script:DernierePos = $null
    return $true
  }
  if (-not (Au-Premier-Plan)) {
    Relacher-Tout   # tout de suite : aucune touche ne doit partir dans une autre fenetre
    # Perte tres breve (notification Windows, overlay...) : on reprend tout seul.
    # Mesure du 07/10/2026 : une perte de ce genre a interrompu un test alors
    # que Lunar etait bien au premier plan juste avant et juste apres.
    $fin = [Environment]::TickCount + 500
    while ([Environment]::TickCount -lt $fin) {
      Start-Sleep -Milliseconds 25
      if (Au-Premier-Plan) { return $true }
    }
    # Vraie perte : Lunar ouvre le menu pause des qu'il perd la main, on attend F7.
    $voleur = Get-Process -Id ([Entree]::PidDe([Entree]::FenetrePremierPlan())) -ErrorAction SilentlyContinue
    $nomVoleur = if ($voleur) { "$($voleur.ProcessName) (PID $($voleur.Id)) : '$($voleur.MainWindowTitle)'" } else { 'aucune fenetre' }
    Write-Host "Le jeu n'est plus au premier plan (a la place : $nomVoleur) : en pause." -ForegroundColor Yellow
    Write-Host "Reviens dans le jeu, ferme le menu (Echap), puis $NomPause." -ForegroundColor Yellow
    if (-not (Attendre-F7)) { return $true }
    Write-Host "Reprise" -ForegroundColor Green
    $script:DernierePos = $null
    return $true
  }
  return $false
}

function Dormir($ms) {
  $fin = [Environment]::TickCount + $ms
  while ([Environment]::TickCount -lt $fin -and -not $script:Arret) {
    Start-Sleep -Milliseconds 15
    if (Surveiller-Verification) { $script:DernierePos = $null; return $true }   # verification AFK repondue : reprise comme apres une pause
    if (Verifier) { return $true }
  }
  return $false
}

# ----------------------------- Position -----------------------------
function Rect-Ligne($dy) {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  return New-Object System.Drawing.Rectangle ($r.L + $Config.HudX), ($r.T + $dy), $Config.HudLargeur, $Config.HudHauteur
}
$script:Zones = $null
# Coordonnees cherchees automatiquement dans le coin en haut a gauche (n'importe quelle place ou taille) ;
# si rien n'est trouve, les places mesurees chez l'auteur (44 / 66 / 88 px du haut, taille 2).
function Preparer-Zones {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  $coin = New-Object System.Drawing.Rectangle $r.L, $r.T, ([Math]::Min(900, $r.R - $r.L)), ([Math]::Min(600, $r.B - $r.T))
  $t = [Glyphes]::TrouverCoordonnees($coin)
  if ($t) {
    [Glyphes]::Echelle = $t[0]
    $script:Zones = foreach ($k in 3, 4, 5) { New-Object System.Drawing.Rectangle ($coin.X + $t[1]), ($coin.Y + $t[$k] - 1), $t[2], ($t[6] + 2) }
    Write-Host ("Coordonnees trouvees en haut a gauche (taille {0})." -f $t[0])
  } else {
    [Glyphes]::Echelle = 2
    $script:Zones = @((Rect-Ligne $Config.HudLigneX), (Rect-Ligne $Config.HudLigneY), (Rect-Ligne $Config.HudLigneZ))
    Write-Host "Coordonnees pas trouvees automatiquement : je lis aux places par defaut (affiche-les en blanc en haut a gauche)."
    Image-Diag $coin 'coordonnees-coin.png'
  }
}

# Lecture brute (x, y, z) en blocs entiers. $null si illisible.
# Image d'une zone de l'ecran dans diagnostics\ (pour comprendre une lecture ratee)
function Image-Diag($zone, $nom) {
  try {
    $d = Join-Path $Dossier 'diagnostics'; New-Item -ItemType Directory -Force $d | Out-Null
    $bmp = New-Object System.Drawing.Bitmap $zone.Width, $zone.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($zone.Location, [System.Drawing.Point]::Empty, $zone.Size); $g.Dispose()
    $bmp.Save((Join-Path $d $nom)); $bmp.Dispose()
    Write-Host "  (image de ce que le script voyait : diagnostics\$nom)"
  } catch { }
}
function Coin-HautGauche {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  return New-Object System.Drawing.Rectangle $r.L, $r.T, ([Math]::Max(1, [Math]::Min(900, $r.R - $r.L))), ([Math]::Max(1, [Math]::Min(600, $r.B - $r.T)))
}
$script:Journal = Join-Path $Dossier 'lectures.log'
$script:NbCaptures = 0
function Lire-Brut {
  $p = @(); $textes = @()
  foreach ($z in $script:Zones) {
    $t = [Glyphes]::Lire($z); $textes += "'$t'"; $script:DerniersTextes = $textes -join ' '
    if ($t -notmatch '^-?\d+$') {
      # diagnostic : on note ce qui a ete lu, et on garde une image de la zone (10 au plus)
      Add-Content $script:Journal ("{0:HH:mm:ss.fff} illisible : {1}" -f (Get-Date), ($textes -join ' '))
      if ($script:NbCaptures -lt 10) {
        $script:NbCaptures++
        $r = $script:Zones[0]; $h = $script:Zones[2].Bottom - $r.Top
        $bmp = New-Object System.Drawing.Bitmap $r.Width, $h
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.Location, [System.Drawing.Point]::Empty, (New-Object System.Drawing.Size $r.Width, $h)); $g.Dispose()
        $bmp.Save((Join-Path $Dossier ("illisible-{0}.png" -f $script:NbCaptures))); $bmp.Dispose()
      }
      return $null
    }
    $p += [int]$t
  }
  return $p
}
$script:Valide = $null   # derniere position confirmee
# Position confirmee : deux lectures identiques de suite, et au plus 3 blocs
# d'ecart avec la derniere position confirmee. Sinon $null.
# (un ecran flou - menu pause en train de se fermer - donne des nombres faux)
$script:ValideT = 0
# Une lecture est acceptee si elle reste a une distance possible de la derniere
# position acceptee : 2 blocs + 8 blocs par seconde ecoulee depuis.
# (en marchant, deux lectures de suite peuvent differer d'un bloc : c'est normal)
function Lire-Position {
  $a = Lire-Brut; if ($null -eq $a) { return $null }
  $maintenant = [Environment]::TickCount
  if ($null -ne $script:Valide) {
    $max = 2 + 8 * ($maintenant - $script:ValideT) / 1000.0
    for ($i = 0; $i -lt 3; $i++) { if ([Math]::Abs($a[$i] - $script:Valide[$i]) -gt $max) { Add-Content $script:Journal ("{0:HH:mm:ss.fff} saut impossible : {1} (avant {2})" -f (Get-Date), ($a -join ','), ($script:Valide -join ',')); return $null } }
  }
  $script:Valide = $a; $script:ValideT = $maintenant
  return $a
}
function Position-Sure {
  for ($i = 0; $i -lt 40 -and -not $script:Arret; $i++) {
    $p = Lire-Position
    if ($null -ne $p) { return $p }
    Start-Sleep -Milliseconds 50
  }
  return $null
}
# Position de reference : la meme lecture 5 fois de suite, sur environ 1 s.
function Position-Depart {
  $script:Valide = $null
  for ($essai = 0; $essai -lt 20; $essai++) {
    $ref = Lire-Brut; $ok = $null -ne $ref
    for ($n = 0; $n -lt 4 -and $ok; $n++) {
      Start-Sleep -Milliseconds 200
      $q = Lire-Brut
      if ($null -eq $q) { $ok = $false } else { for ($i = 0; $i -lt 3; $i++) { if ($q[$i] -ne $ref[$i]) { $ok = $false } } }
    }
    if ($ok) { $script:Valide = $ref; $script:ValideT = [Environment]::TickCount; return $ref }
    Start-Sleep -Milliseconds 200
  }
  return $null
}

$script:Y0 = $null
$script:AvMin = -100000; $script:AvMax = 100000
$script:Bas = 0
# Chute : Y plus bas que le depart sur 3 positions confirmees de suite.
# Sons de fin d etage et de fin de tour (option du menu). Les alarmes (chute, on redescend) sonnent toujours.
function Bip($frequence, $duree) { if ($Sons -eq 1) { [console]::Beep($frequence, $duree) } }
function Controle-Chute($p) {
  if ($null -ne $script:Y0 -and $p[1] -lt $script:Y0) { $script:Bas++ } else { $script:Bas = 0 }
  if ($script:Bas -ge 3) {
    Relacher-Tout; $script:Arret = $true
    [console]::Beep(400, 600)
    Write-Host "Ta hauteur a baisse (Y $($p[1]) au lieu de $script:Y0) : ARRET." -ForegroundColor Red
    return $true
  }
  return $false
}

# ------------------------------- Vente -------------------------------
# Compteur de Lunar en bas a droite (nombre de l'objet tenu, a cote de son icone).
# Quand il atteint VenteSeuil : slot 1 (le Dial, qui vend au clic gauche), relache / renfonce
# du clic (un seul vrai clic), VenteMs plus tard retour au slot 2.
$script:ProchaineVerifVente = 0
$script:Ventes = 0; $script:DerniereVente = 0; $script:VenteBonus = 0; $script:Reussies = 0
$script:VenteArmee = $true   # apres une vente : plus de vente tant que le compteur n'est pas redescendu sous le seuil
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
  $zone = New-Object System.Drawing.Rectangle ($r.L + [int]($larg * 0.15)), ($r.T + 8), ([int]($larg * 0.7)), 110   # haut de l'ecran, au milieu
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
$script:JournalCompteur = Join-Path $Dossier 'lectures.log'
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
    $l = [Math]::Min(500, [int](($r.R - $r.L) / 3)); $ht = [Math]::Min(500, [int](($r.B - $r.T) / 2))
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
function Verifier-Vente {
  Suivre-Argent
  if ($Config.VenteSeuil -le 0) { return }
  $maintenant = [Environment]::TickCount
  if ($maintenant -lt $script:ProchaineVerifVente) { return }
  $script:ProchaineVerifVente = $maintenant + 1000          # une lecture par seconde
  $t = Lire-Compteur
  if ($t -notmatch '^\d+$') { return }
  $n = [int]$t
  if ($n -lt $Config.VenteSeuil) {
    if (-not $script:VenteArmee) { $script:Reussies++; Write-Host ("  vente reussie ({0} au total)" -f $script:Reussies) -ForegroundColor Magenta; Add-Content $script:Journal ("{0:HH:mm:ss.fff} vente reussie ({1} ms)" -f (Get-Date), ($Config.VenteMs + $script:VenteBonus)) }
    $script:VenteArmee = $true; $script:VenteBonus = 0; $script:Reussies = 0; return
  }
  # si la vente n'a pas marche (compteur toujours plein 3 s apres), nouvel essai, un peu plus long
  if (-not $script:VenteArmee -and ($maintenant - $script:DerniereVente) -gt 1800) { $script:VenteArmee = $true;  Add-Content $script:Journal ("{0:HH:mm:ss.fff} vente : compteur toujours plein, nouvel essai ({1} ms)" -f (Get-Date), ($Config.VenteMs + $script:VenteBonus)) }
  if ($n -gt 2304 -or -not $script:VenteArmee) { return }
  $script:VenteArmee = $false; $script:DerniereVente = $maintenant  # 2304 = 36 x 64 : au-dela, lecture fausse
  $script:Ventes++
  Add-Content $script:Journal ("{0:HH:mm:ss.fff} vente n {1} : {2} cannes" -f (Get-Date), $script:Ventes, $n)
  Write-Host ("  essai de vente ({0} cannes, {1} ms)" -f $n, ($Config.VenteMs + $script:VenteBonus)) -ForegroundColor Magenta
  # slot 1 (Dial en main), puis un vrai clic : le clic tenu est relache le plus brievement
  # possible et renfonce, ce qui fait un nouveau "clic gauche" avec le Dial (la vente).
  [Entree]::Touche(0x02, $true); Start-Sleep -Milliseconds 30; [Entree]::Touche(0x02, $false)   # slot 1
  Start-Sleep -Milliseconds 150                                                                  # le temps que le serveur voie le Dial en main (3 ticks)
  [Entree]::ClicGauche($false); Start-Sleep -Milliseconds 20; [Entree]::ClicGauche($true)        # relache / renfonce
  $script:ClicTenu = $true
  Start-Sleep -Milliseconds $Config.VenteMs                                                      # Dial encore en main
  [Entree]::Touche(0x03, $true); Start-Sleep -Milliseconds 30; [Entree]::Touche(0x03, $false)   # slot 2
  $script:ProchaineVerifVente = [Environment]::TickCount + 1200   # le temps que le compteur redescende
}
# ----------------------------- Mouvements -----------------------------
# Traverse vers $sens ('droite' / 'gauche'), clic tenu, jusqu'a buter contre le mur.
# Pendant la traversee, la colonne "avant" doit rester $colonne : si tu deries
# (regard pas tout a fait droit), on s'arrete et on se recale avant de repartir.
# Important dans les coins : c'est la que sont les trous des murs est / ouest.
# $finLat : pour la derniere traversee de l'etage, qui finit devant l'echelle : le clic est
# relache a $Config.MargeEchelle blocs du mur, sinon le viseur atteint l'echelle et la casse.
# $murAttendu : coordonnee laterale du mur vise (connue apres la 1re traversee). Un arret
# loin de ce mur (chute de FPS, lag) n'est pas pris pour le mur : on continue a pousser.
function Traverser($sens, $colonne, $finLat = $null, $murAttendu = $null) {
  $toucheLat = $Touche[$sens]   # (nom different de $Touche : PowerShell ne distingue pas majuscules / minuscules)
  $tenuSansBouger = 0; $dernier = $null; $illisibles = 0; $sansClic = $false; $latDebut = $null; $fauxMurs = 0
  $debut = [Environment]::TickCount
  Clic $true
  while (-not $script:Arret) {
    if (([Environment]::TickCount - $debut) -gt $Config.TraverseeMaxS * 1000) { Write-Host "Traversee trop longue : arret de la traversee." -ForegroundColor Red; break }
    $appui = if ($Config.RelacheMs -gt 0) { $Config.AppuiMs } else { 120 }
    Enfoncer $toucheLat
    $t0 = [Environment]::TickCount
    $interrompu = Dormir $appui
    if ($Config.RelacheMs -gt 0) { Lacher }
    $tenu = [Environment]::TickCount - $t0
    if ($interrompu) { if (-not $script:Arret) { Start-Sleep -Milliseconds 700; [void](Aligner-Regard); [void](Position-Depart); if (-not $sansClic) { Clic $true } }; $dernier = $null; $tenuSansBouger = 0; continue }
    $p = Lire-Position
    if ($null -eq $p) { $illisibles++; if ($illisibles -gt 25) { Write-Host "Position illisible : traversee arretee (coordonnees cachees ?)." -ForegroundColor Red; break }; continue }
    $illisibles = 0
    if (Controle-Chute $p) { break }
    if (-not $sansClic) { Verifier-Vente }
    # Derive : on tolere un bloc d'ecart (la portee ne change pas), sauf hors de la zone
    # recoltee de l'etage (cote mur de depart : colonne du trou du coin).
    $col = $p[$Axes.av]
    if ([Math]::Abs($col - $colonne) -gt 1 -or $col -lt $script:AvMin -or $col -gt $script:AvMax) {
      Relacher-Tout
      Add-Content $script:Journal ("{0:HH:mm:ss.fff} derive : colonne {1} au lieu de {2}, recalage" -f (Get-Date), $p[$Axes.av], $colonne)
      Avancer-Jusqua $colonne
      if ($script:Arret) { break }
      if (-not $sansClic) { Clic $true }; $dernier = $null; $tenuSansBouger = 0; continue
    }
    if ($null -ne $finLat -and -not $sansClic -and [Math]::Abs($p[$Axes.lat] - $finLat) -le $Config.MargeEchelle) {
      [Entree]::ClicGauche($false); $script:ClicTenu = $false; $sansClic = $true
      Add-Content $script:Journal ("{0:HH:mm:ss.fff} fin d'etage : clic relache a {1} (mur vers {2})" -f (Get-Date), $p[$Axes.lat], $finLat)
    }
    if ($null -ne $dernier -and $p[$Axes.lat] -eq $dernier) { $tenuSansBouger += $tenu } else { $tenuSansBouger = 0 }
    $dernier = $p[$Axes.lat]
    if ($null -eq $latDebut) { $latDebut = $p[$Axes.lat] }
    if ($tenuSansBouger -ge $Config.MurMs) {                # plus de mouvement : le mur est atteint ?
      $lat = $p[$Axes.lat]
      $loin = if ($null -ne $murAttendu) { [Math]::Abs($lat - $murAttendu) -gt 2 } else { [Math]::Abs($lat - $latDebut) -lt 70 }
      if ($loin -and $fauxMurs -lt 20) {
        $fauxMurs++; $tenuSansBouger = 0
        Add-Content $script:Journal ("{0:HH:mm:ss.fff} faux mur (lag ?) : arrete a {1}, mur attendu vers {2}" -f (Get-Date), $lat, $(if ($null -ne $murAttendu) { $murAttendu } else { 'au moins 70 blocs du depart' }))
        continue
      }
      break
    }
    if ($Config.RelacheMs -gt 0) { if (Dormir $Config.RelacheMs) { if (-not $script:Arret -and -not $sansClic) { Clic $true } } }
  }
  Relacher-Tout
}

# Avance par petits appuis jusqu'a ce que la coordonnee "avant" atteigne $cible (en blocs entiers).
function Avancer-Jusqua($cible) {
  # Appuis de 60 ms ; s'ils ne font pas changer de bloc, ils s'allongent (jusqu'a 250 ms).
  # S'ils font depasser la cible (aller-retour), ils raccourcissent.
  # Une fois la colonne atteinte, on est juste apres sa limite : un appui de plus
  # (CentrageMs, dans le meme sens) place le personnage vers le milieu du bloc, pour que
  # le moindre ecart pendant la traversee ne le fasse pas repasser dans la colonne voisine.
  $duree = 60; $avant = $null; $sensAvant = 0; $centre = $false; $verifie = $false
  for ($essai = 0; $essai -lt 60 -and -not $script:Arret; $essai++) {
    $p = Position-Sure
    if ($null -eq $p) { Write-Host "Position illisible pendant l'avance." -ForegroundColor Red; $script:Arret = $true; return }
    if (Controle-Chute $p) { return }
    $reste = ($cible - $p[$Axes.av]) * $Axes.avSigne
    if ($reste -eq 0) {
      # Le personnage glisse encore un peu apres le dernier appui : on attend qu'il soit
      # arrete et on relit. S'il a glisse dans la colonne suivante, la boucle le ramene.
      # (21/10 : en haut de l'echelle, il avait glisse jusque dans le couloir de l'echelle.)
      if (-not $verifie) { $verifie = $true; Start-Sleep -Milliseconds 350; continue }
      if ($centre -or $sensAvant -eq 0 -or $Config.CentrageMs -le 0) { return }
      $centre = $true
      Add-Content $script:Journal ("{0:HH:mm:ss.fff} centrage : appui {1} ms {2}" -f (Get-Date), $Config.CentrageMs, $(if ($sensAvant -gt 0) { 'Z' } else { 'S' }))
      Enfoncer $(if ($sensAvant -gt 0) { $Touche.avant } else { $Touche.arriere })
      [void](Dormir $Config.CentrageMs)
      Lacher
      Start-Sleep -Milliseconds 150
      continue   # on relit : si le centrage a fait depasser, la boucle revient en arriere
    }
    $sens = [Math]::Sign($reste)
    if ($null -ne $avant -and $p[$Axes.av] -eq $avant -and $sens -eq $sensAvant) { $duree = [Math]::Min(250, $duree + 40) }
    elseif ($sensAvant -ne 0 -and $sens -ne $sensAvant) { $duree = [Math]::Max(30, [int]($duree / 2)) }
    Add-Content $script:Journal ("{0:HH:mm:ss.fff} avance : colonne {1}, cible {2}, appui {3} ms {4}" -f (Get-Date), $p[$Axes.av], $cible, $duree, $(if ($sens -gt 0) { 'Z' } else { 'S' }))
    $avant = $p[$Axes.av]; $sensAvant = $sens
    $verifie = $false
    Enfoncer $(if ($sens -gt 0) { $Touche.avant } else { $Touche.arriere })
    [void](Dormir $duree)
    Lacher
    Start-Sleep -Milliseconds 150
  }
  Write-Host "Avance impossible (bloque ?) : arret." -ForegroundColor Red; $script:Arret = $true
}

# ------------------------- Recalage du regard -------------------------
# Ouvre F3, lit "Facing: ... (yaw / pitch)" et tourne la souris jusqu'a viser pile
# l'orientation choisie (est = -90), puis referme F3.
$TableCap = @{ est = -90.0; ouest = 90.0; sud = 0.0; nord = 180.0 }
$Cap = $TableCap[$Config.Orientation]
$script:DegresParPoint = $null   # mesure au premier recalage

function Zone-F3 {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  # zone de jeu exacte, jusqu'a son bord droit (26/10/2026 : a la taille 2, le texte de F3 colle au bord et la marge de
  # 12 px d'avant coupait son dernier caractere, donc "(-79.1/-6.2)" sans sa parenthese : orientation illisible)
  $c = [Interface]::Client($h)
  return New-Object System.Drawing.Rectangle ($c.X + [int]($c.Width * 0.45)), $c.Y, ($c.Width - [int]($c.Width * 0.45)), ([int]($c.Height * 0.55))
}
# F3 lu d'abord comme chez l'auteur (moitie droite de la fenetre, taille 3). Si rien ne correspond, on essaie
# les autres tailles (2, 4, 1) et une zone plus large depuis le bord gauche (26/10/2026 : chez un autre joueur,
# F3 illisible ; a une autre taille d'interface, la ligne "Facing" est plus courte). La combinaison qui marche est gardee.
$script:ReglageF3 = $null
function Zone-F3Large {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  $c = [Interface]::Client($h)
  return New-Object System.Drawing.Rectangle $c.X, $c.Y, ([int]($c.Width * 0.62)), ([int]($c.Height * 0.55))
}
function Chercher-F3($motif) {
  # (liste construite a part : sortie d un "if", une liste de 2 valeurs etait aplatie, d ou le plantage du 26/10/2026)
  if ($script:ReglageF3) { $essais = @(, $script:ReglageF3) }
  else { $essais = @(@($false, $script:Gui), @($false, 3), @($false, 2), @($false, 4), @($true, $script:Gui), @($true, 3), @($true, 2), @($true, 4), @($true, 1)) }   # la taille trouvee sur la barre d objets d abord
  foreach ($e in $essais) {
    $zone = if ($e[0]) { Zone-F3Large } else { Zone-F3 }
    foreach ($ligne in [Glyphes]::Lignes($zone, $Config.SeuilF3, $e[1])) {
      $m = [regex]::Match($ligne, $motif)
      if ($m.Success) { if (-not $script:ReglageF3) { $script:ReglageF3 = $e }; return $m }
    }
  }
  return $null
}
function Lire-Cap {
  for ($i = 0; $i -lt 6; $i++) {
    $m = Chercher-F3 '\((-?\d+\.\d)/(-?\d+\.\d)\)$'
    if ($m) { return [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) }
    Start-Sleep -Milliseconds 150
  }
  return $null
}
function Ecart-Cap($yaw) { $d = ($Cap - $yaw) % 360; if ($d -gt 180) { $d -= 360 }; if ($d -lt -180) { $d += 360 }; return $d }

# Position precise (avec decimales) lue dans F3, ligne "XYZ: 96.464 / 107.00000 / 0.383". F3 doit etre ouvert.
function Lire-XYZ {
  for ($i = 0; $i -lt 6; $i++) {
    $m = Chercher-F3 '(-?\d+\.\d+)/(-?\d+\.\d+)/(-?\d+\.\d+)$'
    if ($m) { return @(1..3 | ForEach-Object { [double]::Parse($m.Groups[$_].Value, [Globalization.CultureInfo]::InvariantCulture) }) }
    Start-Sleep -Milliseconds 150
  }
  return $null
}

# Place le personnage a $cible (+/- 0,2 bloc) sur l'axe "avant", par petits appuis Z / S.
function Centrer-Precis($cible) {
  [Entree]::Touche(0x3D, $true); Start-Sleep -Milliseconds 60; [Entree]::Touche(0x3D, $false)   # F3
  Start-Sleep -Milliseconds 400
  try {
    $duree = 40; $avant = $null
    for ($essai = 0; $essai -lt 25 -and -not $script:Arret; $essai++) {
      $p = Lire-XYZ
      if ($null -eq $p) { Write-Host "Position precise illisible dans F3 : pas de centrage." -ForegroundColor Yellow; return }
      $pos = $p[$Axes.av]
      $reste = ($cible - $pos) * $Axes.avSigne
      Add-Content $script:Journal ("{0:HH:mm:ss.fff} centrage precis : {1:N3} (cible {2:N1})" -f (Get-Date), $pos, $cible)
      if ([Math]::Abs($reste) -le 0.2) { return }
      if ($null -ne $avant -and [Math]::Abs($pos - $avant) -lt 0.02) { $duree = [Math]::Min(150, $duree + 20) }   # n'a pas bouge : appui plus long
      $avant = $pos
      Enfoncer $(if ($reste -gt 0) { $Touche.avant } else { $Touche.arriere })
      Start-Sleep -Milliseconds $duree
      Lacher
      Start-Sleep -Milliseconds 350   # le temps de s'arreter
    }
    Write-Host "Centrage precis non atteint." -ForegroundColor Yellow
  } finally {
    Relacher-Tout
    [Entree]::Touche(0x3D, $true); Start-Sleep -Milliseconds 60; [Entree]::Touche(0x3D, $false)   # referme F3
    Start-Sleep -Milliseconds 300
  }
}

function Aligner-Regard {
  if (-not $Config.RecalerRegard) { return $true }
  [Entree]::Touche(0x3D, $true); Start-Sleep -Milliseconds 60; [Entree]::Touche(0x3D, $false)   # F3
  Start-Sleep -Milliseconds 400
  $ok = $false
  try {
    $yaw = Lire-Cap
    if ($null -eq $yaw) { Write-Host "Je n'arrive pas a lire l'orientation dans F3 : regard non recale." -ForegroundColor Yellow; Image-Diag (Zone-F3) 'f3-illisible.png'; return $false }
    if ($null -eq $script:DegresParPoint) {
      # mesure : de combien de degres tourne un deplacement de souris de 200 points
      $sens = if ((Ecart-Cap $yaw) -ge 0) { 1 } else { -1 }
      [Entree]::Souris(200 * $sens, 0); Start-Sleep -Milliseconds 250
      $yaw2 = Lire-Cap
      if ($null -eq $yaw2) { Write-Host "Orientation illisible pendant la mesure." -ForegroundColor Yellow; return $false }
      $d = (($yaw2 - $yaw) % 360); if ($d -gt 180) { $d -= 360 }; if ($d -lt -180) { $d += 360 }
      if ([Math]::Abs($d) -lt 0.5) { Write-Host "La souris ne fait pas tourner la vue : regard non recale." -ForegroundColor Yellow; return $false }
      $script:DegresParPoint = $d / (200 * $sens)
      Add-Content $script:Journal ("{0:HH:mm:ss.fff} souris : {1:N4} degre par point" -f (Get-Date), $script:DegresParPoint)
      $yaw = $yaw2
    }
    for ($essai = 0; $essai -lt 8; $essai++) {
      $ecart = Ecart-Cap $yaw
      Add-Content $script:Journal ("{0:HH:mm:ss.fff} regard : {1:N1} (ecart {2:N1})" -f (Get-Date), $yaw, $ecart)
      if ([Math]::Abs($ecart) -le 0.15) { $ok = $true; break }
      $points = [int][Math]::Round($ecart / $script:DegresParPoint)
      if ($points -eq 0) { $points = [Math]::Sign($ecart / $script:DegresParPoint) }
      [Entree]::Souris($points, 0); Start-Sleep -Milliseconds 250
      $y = Lire-Cap; if ($null -eq $y) { break }; $yaw = $y
    }
    if ($ok) { Write-Host ("Regard recale : {0:N1}" -f $yaw) -ForegroundColor Green } else { Write-Host ("Regard pas tout a fait recale : {0:N1}" -f $yaw) -ForegroundColor Yellow }
    return $ok
  } finally {
    [Entree]::Touche(0x3D, $true); Start-Sleep -Milliseconds 60; [Entree]::Touche(0x3D, $false)   # referme F3
    Start-Sleep -Milliseconds 300
  }
}

# ------------------------------- Recolte -------------------------------
function Attendre-Depart {
  Write-Host "Dans le jeu : colle au mur de depart, en visant les cannes, ferme le menu (Echap), puis $NomPause. ($NomArret = annuler)" -ForegroundColor Cyan
  while ($true) {
    if (-not (Attendre-F7)) { return }
    if (Au-Premier-Plan) { Start-Sleep -Milliseconds 300; return }
    Write-Host "$NomPause recu, mais le jeu n'est pas au premier plan : clique dans le jeu puis $NomPause." -ForegroundColor Yellow
  }
}

function Changer-Orientation($o) {
  $script:Orient = $o
  $script:Axes = $TableAxes[$o]
  $script:Cap = $TableCap[$o]
}
$script:Orient = $Config.Orientation
$Inverse = @{ est = 'ouest'; ouest = 'est'; nord = 'sud'; sud = 'nord' }

# Recolte d'un etage depuis la position actuelle (colle au mur de depart, regard deja recale).
function Recolte-Etage($numero) {
  # Decalage de chaque traversee depuis le depart : pas fixe (2 ou 3), ou 2 et 3 en alternance (Pas = 25).
  $decalages = @(); $o = 0; $i = 0
  while ($o -le $Config.AvanceMax) { $decalages += $o; $o += $(if ($Config.Pas -eq 25) { if ($i % 2 -eq 0) { 2 } else { 3 } } else { $Config.Pas }); $i++ }
  # Il faut un nombre impair de traversees : la derniere doit finir du meme cote que la 1re (l'echelle).
  if ($decalages.Count % 2 -eq 0) { $decalages = $decalages[0..($decalages.Count - 2)] }
  $nbPassages = $decalages.Count
  $p0 = Position-Depart
  if ($null -eq $p0) { Write-Host "Je n'arrive pas a lire tes coordonnees en haut a gauche : sont-elles affichees ?" -ForegroundColor Red; Write-Host ("  derniere lecture : {0}" -f $script:DerniersTextes); Image-Diag (Coin-HautGauche) 'coordonnees-illisibles.png'; $script:Arret = $true; return }
  $script:Y0 = $p0[1]; $script:Bas = 0
  $av0 = $p0[$Axes.av]
  $avFin = $av0 + $Axes.avSigne * ($Config.AvanceMax + 2)
  $script:AvMin = [Math]::Min($av0, $avFin); $script:AvMax = [Math]::Max($av0, $avFin)
  Write-Host ("Etage {0}/{1} : depart X {2}  Y {3}  Z {4}, regard vers {5}, {6} traversees." -f ($Config.EtageDepart + $numero - 1), 12, $p0[0], $p0[1], $p0[2], $script:Orient, $nbPassages) -ForegroundColor Cyan

  $sens = $Config.PremierSens
  $latMurFin = $null; $latMurDepart = $p0[$Axes.lat]
  $autre = @{ droite = 'gauche'; gauche = 'droite' }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  for ($k = 0; $k -lt $nbPassages -and -not $script:Arret; $k++) {
    Write-Host ("  traversee {0}/{1}" -f ($k + 1), $nbPassages)
    $finLat = if ($k -eq $nbPassages - 1 -and $null -ne $latMurFin) { $latMurFin } else { $null }
    # mur vise : traversees paires vers le mur du bout (connu apres la 1re), impaires vers le mur de depart
    $murAttendu = if ($k -eq 0 -or $null -eq $latMurFin) { $null } elseif ($k % 2 -eq 0) { $latMurFin } else { $latMurDepart }
    Traverser $sens ($av0 + $Axes.avSigne * $decalages[$k]) $finLat $murAttendu
    if ($k -eq 0 -and $null -ne $script:Valide) { $latMurFin = $script:Valide[$Axes.lat] }   # bout de la 1re traversee = cote de l'echelle (nombre impair : la derniere va du meme cote)
    if ($script:Arret) { break }
    if ($k -lt $nbPassages - 1) { Avancer-Jusqua ($av0 + $Axes.avSigne * $decalages[$k + 1]) }
    $sens = $autre[$sens]
  }
  if (-not $script:Arret) {
    Bip 880 200
    Write-Host ("Etage {0} termine en {1:N0} s." -f ($Config.EtageDepart + $numero - 1), $sw.Elapsed.TotalSeconds) -ForegroundColor Green
  }
}

# En fin d'etage, colle au mur du coin ou est l'echelle : on avance (Z) jusqu'a l'echelle,
# on grimpe de $Config.Montee blocs, puis on recule d'un pas sur l'etage du dessus.
# Securites : on ne lache jamais tout sur l'echelle (on glisserait), arret si on va
# trop loin en avant (plus de 8 blocs), si on redescend, ou si ca dure plus de 15 s.
function Monter-Echelle {
  $p = Position-Sure
  if ($null -eq $p) { Write-Host "Position illisible avant l'echelle." -ForegroundColor Red; $script:Arret = $true; return }
  $yDepart = $p[1]; $yCible = $yDepart + $Config.Montee; $avDepart = $p[$Axes.av]
  Add-Content $script:Journal ("{0:HH:mm:ss.fff} echelle : depart {1}, cible Y {2}" -f (Get-Date), ($p -join ','), $yCible)
  Write-Host ("Montee a l'echelle : Y {0} -> {1}" -f $yDepart, $yCible) -ForegroundColor Cyan
  # surtout pas de clic pendant la montee : on relache le clic gauche (deux fois, par securite)
  [Entree]::ClicGauche($false); Start-Sleep -Milliseconds 50; [Entree]::ClicGauche($false); $script:ClicTenu = $false
  Start-Sleep -Milliseconds 150
  $debut = [Environment]::TickCount
  Enfoncer $Touche.avant
  while (-not $script:Arret) {
    if (([Environment]::TickCount - $debut) -gt 15000) { Relacher-Tout; Write-Host "Echelle pas atteinte ou montee trop longue : arret." -ForegroundColor Red; $script:Arret = $true; return }
    if (Dormir 60) { if ($script:Arret) { return }; Enfoncer $Touche.avant; continue }   # pause : on reprend la montee
    $p = Lire-Position
    if ($null -eq $p) { continue }
    if ((($p[$Axes.av] - $avDepart) * $Axes.avSigne) -gt 8) { Relacher-Tout; Write-Host "Trop loin en avant sans monter : arret." -ForegroundColor Red; $script:Arret = $true; return }
    if ($p[1] -lt $yDepart) { Relacher-Tout; [console]::Beep(400, 600); Write-Host "Tu redescends : arret." -ForegroundColor Red; $script:Arret = $true; return }
    if ($p[1] -ge $yCible) { break }
  }
  # encore un peu de montee pour passer le bord, puis un pas en arriere sur l'etage
  [void](Dormir 150)
  Lacher
  Enfoncer $Touche.arriere; [void](Dormir 350); Lacher
  Start-Sleep -Milliseconds 400
  $p = Position-Sure
  Add-Content $script:Journal ("{0:HH:mm:ss.fff} echelle : arrivee {1}" -f (Get-Date), ($p -join ','))
  if ($null -eq $p -or $p[1] -ne $yCible) { Write-Host ("Arrivee incertaine en haut de l'echelle (Y {0}) : arret." -f $(if ($p) { $p[1] } else { '?' })) -ForegroundColor Red; $script:Arret = $true; return }
  # Sortie du couloir de l'echelle : juste apres le pas en arriere, le personnage deborde
  # encore sur la colonne de l'echelle et accroche les blocs qui l'encadrent.
  # La recolte de l'etage commence dans la colonne d'arrivee (X 98 / X 19). Mais si le
  # personnage est au bord de cette colonne, cote echelle (ex. X 98,9), il deborde sur la
  # colonne de l'echelle et la 1re traversee accroche le bloc qui l'encadre (21/10).
  # Les coordonnees en haut a gauche n'ont pas de decimales : on lit la position precise
  # dans F3 et on se place au milieu du bloc.
  $col = $p[$Axes.av]
  Centrer-Precis ($col + 0.5)
  if ($script:Arret) { return }
  Write-Host "En haut de l'echelle." -ForegroundColor Green
}

# Fin du 12e etage : /home s ramene au depart du 1er etage (X 19, Y 107, Z -80), face a l'est.
# Seule commande tapee dans le chat par le script.
$Depart = @{ X = 19; Y = 107; Z = -80 }
Add-Type -AssemblyName System.Windows.Forms
function Retour-Home {
  Relacher-Tout
  Write-Host "Retour au depart : /home s" -ForegroundColor Cyan
  Add-Content $script:Journal ("{0:HH:mm:ss.fff} /home s" -f (Get-Date))
  if (-not (Au-Premier-Plan)) { Write-Host "Le jeu n'est pas au premier plan : /home annule, arret." -ForegroundColor Red; $script:Arret = $true; return }
  [Entree]::Touche(0x14, $true); Start-Sleep -Milliseconds 40; [Entree]::Touche(0x14, $false)   # T : ouvre le chat
  Start-Sleep -Milliseconds 700
  [System.Windows.Forms.SendKeys]::SendWait('/home s'); Start-Sleep -Milliseconds 300
  [Entree]::Touche(0x1C, $true); Start-Sleep -Milliseconds 40; [Entree]::Touche(0x1C, $false)   # Entree
  Start-Sleep -Milliseconds 2500
  $script:Valide = $null
  $p = Position-Depart
  if ($null -eq $p) { Write-Host "Position illisible apres /home : arret." -ForegroundColor Red; $script:Arret = $true; return }
  if ([Math]::Abs($p[0] - $Depart.X) -gt 2 -or $p[1] -ne $Depart.Y -or [Math]::Abs($p[2] - $Depart.Z) -gt 2) {
    Write-Host ("Pas au depart apres /home (X {0} Y {1} Z {2}) : arret." -f $p[0], $p[1], $p[2]) -ForegroundColor Red; $script:Arret = $true; return
  }
  Changer-Orientation 'est'
  [void](Aligner-Regard)
  Centrer-Precis ($Depart.X + 0.5)
  Write-Host ("Au depart : X {0} Y {1} Z {2}." -f $p[0], $p[1], $p[2]) -ForegroundColor Green
}

function Recolte {
  if ($script:PidsJeu.Count -eq 0) { Write-Host "Le jeu n'est pas lance." -ForegroundColor Red; return }
  Attendre-Depart
  if ($script:Arret) { return }
  Preparer-Zones
  Detecter-Interface
  Start-Sleep -Milliseconds 700   # le temps que le menu pause finisse de se fermer
  Suivre-Argent $true             # argent au depart
  $total = [Diagnostics.Stopwatch]::StartNew()
  for ($tour = 1; -not $script:Arret; $tour++) {
    Write-Host ("Tour {0}{1}" -f $tour, $(if ($Config.Tours -gt 0) { " / $($Config.Tours)" } else { " (boucle infinie)" })) -ForegroundColor Cyan
    $sw = [Diagnostics.Stopwatch]::StartNew()
    for ($e = 1; $e -le $Config.NbEtages -and -not $script:Arret; $e++) {
      [void](Aligner-Regard)
      Recolte-Etage $e
      if ($script:Arret -or $e -eq $Config.NbEtages) { break }
      Monter-Echelle
      if ($script:Arret) { break }
      Changer-Orientation $Inverse[$script:Orient]     # demi-tour pour l'etage suivant
    }
    if ($script:Arret) { break }
    Bip 660 300; Bip 880 300; Bip 1100 400
    Write-Host ("Tour {0} termine : {1} etages en {2:N0} min." -f $tour, $Config.NbEtages, $sw.Elapsed.TotalMinutes) -ForegroundColor Green
    if ($Config.Tours -gt 0 -and $tour -ge $Config.Tours) { break }
    Retour-Home
    if ($script:Arret) { break }
    $Config.EtageDepart = 1; $Config.NbEtages = 12            # les tours suivants font les 12 etages
  }
  Suivre-Argent $true
  Write-Host ("Recolte terminee en {0:N0} min." -f $total.Elapsed.TotalMinutes) -ForegroundColor Green
}
try { Recolte }
finally {
  Relacher-Tout
  Write-Host "Toutes les touches sont relachees." -ForegroundColor Cyan
}
