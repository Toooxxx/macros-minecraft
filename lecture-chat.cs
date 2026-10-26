// lecture-chat.cs : lecture des messages du chat de Minecraft a l ecran (police : police-chat.txt).
// Utilise par peche.ps1 pour lire le nom du poisson attrape.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
// Lecture du chat : lignes sur une grille de 9 rangees ; chaque lettre est lue sur 9 rangees
// (0 = accents, 1 = haut des lettres, 7 = base, 8 = jambages), avec sa couleur.
public static class Chat {
  public static Dictionary<string, char> Modeles = new Dictionary<string, char>();
  public class Ligne { public string Texte = ""; public List<Color> Couleurs = new List<Color>(); public int Base; }
  public static void Charger(string fichier) {
    foreach (var l in System.IO.File.ReadAllLines(fichier, Encoding.UTF8)) { if (l.Length < 3 || l.StartsWith("# ")) continue; Modeles[l.Substring(2)] = l[0]; }   // "# " = commentaire
  }
  // rangees : ecart entre deux lignes (9 pour le chat, 10 pour les sous-titres)
  public static List<Ligne> Lire(Rectangle ecran, int ech, int rangees = 9) {
    using (var bmp = new Bitmap(ecran.Width, ecran.Height, PixelFormat.Format24bppRgb)) {
      using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(ecran.Location, Point.Empty, ecran.Size);
      return Lire(bmp, ech, rangees);
    }
  }
  public static List<Ligne> Lire(Bitmap bmp, int ech, int rangees = 9) {
    var res = new List<Ligne>();
    var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
    int w = bmp.Width, h = bmp.Height, s = bd.Stride;
    // texte : pixel vif (l'ombre du texte et le fond du chat sont sombres)
    // rangees du chat : son fond est sombre (10 % de pixels tres sombres ou plus) ; de jour, le monde autour est clair.
    // Si presque tout est sombre (nuit), on ne filtre pas.
    var bande = new bool[h]; int nbBande = 0;
    for (int y = 0; y < h; y++) {
      int sombre = 0;
      for (int x = 0; x < w; x += 2) { int o = y * s + x * 3; if (Math.Max(b[o + 2], Math.Max(b[o + 1], b[o])) <= 60) sombre++; }
      bande[y] = sombre * 2 >= w / 10; if (bande[y]) nbBande++;   // 10 % : une ligne pleine de texte n a que ~21 % de sombre (test du 24/10/2026), l eau autour 0 a 1 %
    }
    if (nbBande > h * 8 / 10) for (int y = 0; y < h; y++) bande[y] = true;
    var clair = new bool[w, h];
    var cnt = new int[h];
    for (int y = 0; y < h; y++) { if (!bande[y]) continue; for (int x = 0; x < w; x++) {
      int o = y * s + x * 3; int bl = b[o], gg = b[o + 1], r = b[o + 2];
      if (Math.Max(r, Math.Max(gg, bl)) >= 90 && r + gg + bl >= 200) { clair[x, y] = true; cnt[y]++; }
    } }
    // grille des lignes : la rangee de base est pleine, celle d'en dessous presque vide
    int pas = rangees * ech, phase = 0; long meilleur = long.MinValue;
    for (int p = 0; p < pas; p++) {
      long sc = 0;
      for (int y = p; y + 2 * ech <= h; y += pas) for (int i = 0; i < ech; i++) sc += cnt[y + i] - cnt[y + ech + i];   // rangee entiere (ech pixels)
      if (sc > meilleur) { meilleur = sc; phase = p; }
    }
    for (int yg = phase; yg < h; yg += pas) {
      // chaque ligne est recalee a +-3 px sur sa propre base (test du 24/10/2026 : apres un message sur
      // deux lignes, les lignes du dessus etaient decalees de quelques pixels par rapport a la grille)
      int yb = yg; long mieux = long.MinValue;
      for (int o = -3; o <= 3; o++) {
        int y = yg + o; if (y < 0 || y + 2 * ech > h) continue;
        long sc = 0; for (int i = 0; i < ech; i++) sc += cnt[y + i] - cnt[y + ech + i];
        if (sc > mieux) { mieux = sc; yb = y; }
      }
      int y0 = yb - 7 * ech, y1 = yb + 2 * ech;   // rangees 0 a 8
      if (y0 < 0) continue;
      int total = 0; for (int y = y0; y < Math.Min(h, y1); y++) total += cnt[y];
      if (total < 20 * ech) continue;
      var li = new Ligne { Base = yb }; var sb = new StringBuilder();
      int x0 = -1, vide = 0;
      for (int x = 0; x <= w; x++) {
        bool v = false;
        if (x < w) for (int y = y0; y < Math.Min(h, y1); y++) if (clair[x, y]) { v = true; break; }
        if (v && x0 < 0) { if (sb.Length > 0 && vide > 2 * ech) { sb.Append(' '); li.Couleurs.Add(Color.Empty); } x0 = x; }
        if (!v && x0 < 0) vide++;
        if (!v && x0 >= 0) {
          int larg = (x - x0 + ech - 1) / ech;
          var k = new StringBuilder(); long sr = 0, sg = 0, sbl = 0, n = 0;
          for (int gy = 0; gy < 9; gy++) {
            if (gy > 0) k.Append('/');
            for (int gx = 0; gx < larg; gx++) {
              int cx = x0 + gx * ech + ech / 2, cy = y0 + gy * ech + ech / 2;
              bool on = cx < w && cy < h && clair[cx, cy];
              k.Append(on ? '#' : '.');
              if (on) { int o = cy * s + cx * 3; sbl += b[o]; sg += b[o + 1]; sr += b[o + 2]; n++; }
            }
          }
          char c; sb.Append(Modeles.TryGetValue(k.ToString(), out c) ? c : '?');
          li.Couleurs.Add(n > 0 ? Color.FromArgb((int)(sr / n), (int)(sg / n), (int)(sbl / n)) : Color.Empty);
          x0 = -1; vide = 1;
        }
      }
      li.Texte = sb.ToString(); res.Add(li);
    }
    return res;
  }
}
