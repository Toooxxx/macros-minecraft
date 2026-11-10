// Macros Minecraft : menu de lancement des scripts canne-etage.ps1 (ferme a canne) et autoclic.ps1.
// Lance par Ferme-canne.ps1 (raccourci Ferme-canne.lnk) : compile en memoire par PowerShell.
// Style "launcher" : tuiles avec icones, cartes arrondies, gros chiffres en direct. Couleur d'accent modifiable.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

// ------------------------------ Theme partage ------------------------------
public static class Th {
  // fond en degrade violet -> bleu nuit ; cartes violet sombre ; une couleur par mode (ParMode)
  public static Color Fond = Color.FromArgb(14, 12, 30);
  public static Color FondHaut = Color.FromArgb(40, 22, 78), FondBas = Color.FromArgb(8, 16, 38);
  public static Color Carte = Color.FromArgb(25, 22, 48);
  public static Color CarteHaute = Color.FromArgb(40, 36, 70);
  public static Color Champ = Color.FromArgb(36, 32, 63);
  public static Color Bordure = Color.FromArgb(54, 49, 90);
  public static Color Texte = Color.FromArgb(242, 240, 252);
  public static Color Discret = Color.FromArgb(152, 148, 186);
  public static Color Accent = Color.FromArgb(64, 214, 120);
  public static bool ParMode = true;
  // Arc-en-ciel : contour fin des boutons en degrade de toutes les teintes, qui tourne avec Phase (degres)
  public static bool Arc; public static double Phase;
  public static Color Teinte(double h) {   // teinte (0-360) -> couleur vive (saturation 0,7, luminosite 1)
    h = ((h % 360) + 360) % 360;
    double c = 0.7, x = c * (1 - Math.Abs(h / 60 % 2 - 1)), m = 1 - c, r = 0, g = 0, b = 0;
    if (h < 60) { r = c; g = x; } else if (h < 120) { r = x; g = c; } else if (h < 180) { g = c; b = x; } else if (h < 240) { g = x; b = c; } else if (h < 300) { r = x; b = c; } else { r = c; b = x; }
    return Color.FromArgb((int)((r + m) * 255), (int)((g + m) * 255), (int)((b + m) * 255));
  }
  public static void ContourArc(Graphics g, GraphicsPath p, RectangleF r, bool actif = true) {
    var blend = new ColorBlend(7); var cols = new Color[7]; var pos = new float[7];
    for (int i = 0; i < 7; i++) { cols[i] = Color.FromArgb(actif ? 255 : 110, Teinte(Phase + i * 60)); pos[i] = i / 6f; }
    blend.Colors = cols; blend.Positions = pos;
    using (var b = new LinearGradientBrush(new RectangleF(r.X - 1, r.Y - 1, r.Width + 2, r.Height + 2), Color.Black, Color.Black, 20f) { InterpolationColors = blend })
    using (var pen = new Pen(b, 1.6f)) g.DrawPath(pen, p);
  }
  public static readonly Color Ferme = Color.FromArgb(64, 214, 120), Minage = Color.FromArgb(255, 166, 64), Autoclick = Color.FromArgb(240, 100, 170), Peche = Color.FromArgb(56, 182, 255), Violet = Color.FromArgb(170, 125, 255);
  // texte lisible sur une couleur vive : sombre sur clair, blanc sur fonce
  public static Color TexteSur(Color c) { return c.R * 0.299 + c.G * 0.587 + c.B * 0.114 > 150 ? Color.FromArgb(18, 16, 34) : Color.White; }
  public static GraphicsPath Arrondi(RectangleF r, float rayon) {
    var p = new GraphicsPath(); float d = rayon * 2;
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
    p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
  }
  public static Color Melange(Color a, Color b, float t) { return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t)); }
}

// Carte arrondie posee sur le degrade (coins transparents). Lueur = halo de la couleur d'accent en haut
// (carte Session ; ses textes sont transparents pour la laisser voir).
public class CarteRonde : Panel {
  public Color Remplissage = Th.Carte; public bool BordAccent, Lueur; public float Rayon = 20;
  public CarteRonde() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true); BackColor = Color.Transparent; }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    using (var p = Th.Arrondi(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Rayon)) {
      using (var b = new SolidBrush(Remplissage)) g.FillPath(b, p);
      if (Lueur) {
        var clip = g.Clip; g.SetClip(p);
        using (var b = new LinearGradientBrush(new Rectangle(0, 0, Width, 170), Color.FromArgb(70, Th.Accent), Color.FromArgb(0, Th.Accent), LinearGradientMode.Vertical)) g.FillRectangle(b, 0, 0, Width, 170);
        g.Clip = clip;
      }
      Color bord = BordAccent || Lueur ? Color.FromArgb(Lueur ? 110 : 255, Th.Accent) : Color.FromArgb(60, 255, 255, 255);
      using (var pen = new Pen(bord, BordAccent ? 2f : 1f)) g.DrawPath(pen, p);
    }
  }
}

// Tuile de navigation : icone dessinee + titre + sous-titre ; survol et selection.
public class Tuile : Control {
  public string Titre, SousTitre, Icone; public bool Choisie, Compacte; bool survol;
  public Color Couleur = Color.Empty;   // couleur propre de la tuile (mode), si Th.ParMode
  public Tuile() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true); BackColor = Color.Transparent; Cursor = Cursors.Hand; }
  protected override void OnMouseEnter(EventArgs e) { survol = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { survol = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    // pastille : choisie = remplie de sa couleur en degrade ; sinon voile clair sur le fond, icone dans sa couleur
    var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
    Color c = Th.ParMode && !Couleur.IsEmpty ? Couleur : Th.Accent;
    using (var p = Th.Arrondi(r, Height / 2f)) {
      if (Choisie) using (var b = new LinearGradientBrush(Rectangle.Round(r), Th.Melange(c, Color.White, 0.22f), c, LinearGradientMode.ForwardDiagonal)) g.FillPath(b, p);
      else using (var b = new SolidBrush(Color.FromArgb(survol && Enabled ? 40 : 20, 255, 255, 255))) g.FillPath(b, p);
      if (Th.Arc) Th.ContourArc(g, p, r, Enabled);
    }
    Color ic = !Enabled ? Th.Bordure : (Choisie ? Th.TexteSur(c) : c);
    var rp = Compacte ? new RectangleF((Width - 40) / 2f, (Height - 40) / 2f, 40, 40) : new RectangleF(12, (Height - 40) / 2f, 40, 40);
    DessinerIcone(g, Icone, rp, ic);
    if (Compacte) return;
    using (var f = new Font("Segoe UI Semibold", 11f)) TextRenderer.DrawText(g, Titre, f, new Rectangle(56, 0, Width - 60, Height), !Enabled ? Th.Discret : (Choisie ? Th.TexteSur(c) : Th.Texte), TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
  }
  static void DessinerIcone(Graphics g, string nom, RectangleF r, Color c) {
    float cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2;
    using (var pen = new Pen(c, 2.6f) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round }) using (var b = new SolidBrush(c)) {
      if (nom == "canne") {
        foreach (var dx in new[] { -9f, 0f, 9f }) {
          float h = dx == 0 ? 26 : 20, y0 = cy + 12 - h;
          g.DrawLine(pen, cx + dx, cy + 12, cx + dx, y0);
          for (float y = y0 + 6; y < cy + 10; y += 7) g.DrawLine(pen, cx + dx - 2.5f, y, cx + dx + 2.5f, y);
        }
      } else if (nom == "souris") {
        using (var p = Th.Arrondi(new RectangleF(cx - 9, cy - 13, 18, 26), 8.5f)) g.DrawPath(pen, p);
        g.DrawLine(pen, cx, cy - 13, cx, cy - 4);
        g.FillEllipse(b, cx - 9 + 2, cy - 11.5f, 6, 6);
      } else if (nom == "pioche") {
        g.DrawLine(pen, cx - 11, cy + 12, cx + 4, cy - 3);                                                    // manche
        g.DrawBezier(pen, new PointF(cx - 7, cy - 12), new PointF(cx + 5, cy - 14), new PointF(cx + 14, cy - 5), new PointF(cx + 12, cy + 7));   // fer
      } else if (nom == "poisson") {
        g.DrawEllipse(pen, cx - 12, cy - 7, 20, 14);
        g.DrawLines(pen, new[] { new PointF(cx + 7, cy), new PointF(cx + 14, cy - 6), new PointF(cx + 14, cy + 6), new PointF(cx + 7, cy) });
        g.FillEllipse(b, cx - 7, cy - 3, 3.5f, 3.5f);
      } else if (nom == "stats") {
        g.DrawLine(pen, cx - 13, cy + 12, cx + 13, cy + 12);
        float[] hauteurs = { 9, 16, 12, 22 };
        for (int i = 0; i < 4; i++) { float x = cx - 10 + i * 6.8f; g.DrawLine(pen, x, cy + 7, x, cy + 7 - hauteurs[i] + 4); }
      } else {   // palette
        g.DrawEllipse(pen, cx - 13, cy - 12, 26, 24);
        foreach (var pt in new[] { new PointF(cx - 6, cy - 4), new PointF(cx + 1, cy - 7), new PointF(cx + 7, cy - 2) }) g.FillEllipse(b, pt.X - 2.5f, pt.Y - 2.5f, 5, 5);
        g.FillEllipse(b, cx - 3, cy + 3, 7, 7);
      }
    }
  }
}

// Bouton arrondi (principal = rempli de la couleur d'accent).
public class BoutonRond : Control {
  public bool Principal; public Color CouleurBord = Color.Empty; bool survol, appui;
  public BoutonRond() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true); BackColor = Color.Transparent; Cursor = Cursors.Hand; }
  protected override void OnMouseEnter(EventArgs e) { survol = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { survol = false; appui = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnMouseDown(MouseEventArgs e) { appui = true; Invalidate(); base.OnMouseDown(e); }
  protected override void OnMouseUp(MouseEventArgs e) { appui = false; Invalidate(); base.OnMouseUp(e); }
  protected override void OnEnabledChanged(EventArgs e) { Cursor = Enabled ? Cursors.Hand : Cursors.Default; Invalidate(); base.OnEnabledChanged(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    var r = new RectangleF(1, 1, Width - 3, Height - 3);
    Color fond, texte, bord;
    if (Principal && Enabled) {
      // degrade de la couleur d'accent (plus clair en haut a gauche), plus lumineux au survol
      Color a = appui ? Th.Melange(Th.Accent, Color.Black, 0.15f) : Th.Accent;
      using (var p = Th.Arrondi(r, Height / 2.4f)) {
        using (var b = new LinearGradientBrush(Rectangle.Round(r), Th.Melange(a, Color.White, survol ? 0.38f : 0.25f), a, LinearGradientMode.ForwardDiagonal)) g.FillPath(b, p);
        if (Th.Arc) Th.ContourArc(g, p, r);
      }
      TextRenderer.DrawText(g, Text, Font, Rectangle.Round(r), Th.TexteSur(a), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
      return;
    }
    if (Principal) { fond = Th.Champ; texte = Th.Discret; bord = Th.Bordure; }
    else {
      fond = !Enabled ? Th.Carte : (survol ? Th.CarteHaute : Th.Champ);
      texte = Enabled ? (CouleurBord.IsEmpty ? Th.Texte : CouleurBord) : Th.Bordure;
      bord = Enabled && !CouleurBord.IsEmpty ? CouleurBord : Th.Bordure;
    }
    using (var p = Th.Arrondi(r, Height / 2.4f)) using (var b = new SolidBrush(fond)) using (var pen = new Pen(bord, 1.2f)) { g.FillPath(b, p); if (Th.Arc) Th.ContourArc(g, p, r, Enabled); else g.DrawPath(pen, p); }
    if (Emoji == null) { TextRenderer.DrawText(g, Text, Font, Rectangle.Round(r), texte, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter); return; }
    // icone en couleur + texte, centres ensemble
    int lt = TextRenderer.MeasureText(g, Text, Font).Width; const int ti = 34, ecart = 10;
    float x = (Width - (ti + ecart + lt)) / 2f;
    IconeCulture.Dessiner(g, Emoji, new RectangleF(x, (Height - ti) / 2f, ti, ti), Enabled);
    TextRenderer.DrawText(g, Text, Font, new Rectangle((int)x + ti + ecart, 0, lt + 4, Height), texte, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
  }
  public string Emoji;   // "canne", "pasteque" ou "citrouille" : petite icone en couleur devant le texte
}

// Petites icones en couleur des cultures. Dessinees a la main : Windows affiche les emojis en noir et blanc dans les menus de ce type.
public static class IconeCulture {
  static Color C(int r, int v, int b, bool actif) { var c = Color.FromArgb(r, v, b); return actif ? c : Th.Melange(c, Th.Carte, 0.65f); }
  public static void Dessiner(Graphics g, string nom, RectangleF z, bool actif) {
    float s = z.Width / 32f;
    Func<float, float> X = v => z.X + v * s, Y = v => z.Y + v * s;
    if (nom == "pasteque") {
      // tranche : ecorce verte, chair rouge, pepins
      using (var b = new SolidBrush(C(62, 158, 72, actif))) g.FillPie(b, X(2), Y(-8), 28 * s, 28 * s + 8 * s, 0, 180);
      using (var b = new SolidBrush(C(238, 244, 214, actif))) g.FillPie(b, X(4.5f), Y(-7), 23 * s, 25 * s + 8 * s, 0, 180);
      using (var b = new SolidBrush(C(236, 62, 72, actif))) g.FillPie(b, X(6), Y(-6.5f), 20 * s, 23 * s + 8 * s, 0, 180);
      using (var b = new SolidBrush(C(40, 34, 40, actif)))
        foreach (var p in new[] { new PointF(11, 12), new PointF(16, 15), new PointF(21, 12), new PointF(13.5f, 19.5f), new PointF(18.5f, 19.5f) })
          g.FillEllipse(b, X(p.X - 1.1f), Y(p.Y - 1.6f), 2.2f * s, 3.2f * s);
    } else if (nom == "citrouille") {
      using (var pen = new Pen(C(84, 150, 62, actif), 3 * s) { StartCap = LineCap.Round, EndCap = LineCap.Round }) g.DrawLine(pen, X(16), Y(9), X(18.5f), Y(4));
      foreach (var q in new[] { new[] { 2f, 9f, 14f }, new[] { 16f, 9f, 14f }, new[] { 7f, 8f, 18f } })
        using (var b = new SolidBrush(C(q[0] == 7 ? 245 : 226, q[0] == 7 ? 146 : 118, q[0] == 7 ? 38 : 24, actif))) g.FillEllipse(b, X(q[0]), Y(q[1]), q[2] * s, 21 * s);
      using (var pen = new Pen(C(190, 92, 14, actif), 1.4f * s)) { g.DrawArc(pen, X(9), Y(9), 14 * s, 19 * s, 90, 180); g.DrawArc(pen, X(9), Y(9), 14 * s, 19 * s, 270, 180); }
    } else {
      // canne : trois tiges vertes a noeuds, avec une feuille
      using (var pen = new Pen(C(128, 202, 84, actif), 3.2f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round }) {
        g.DrawLine(pen, X(9), Y(28), X(9), Y(9)); g.DrawLine(pen, X(16), Y(28), X(16), Y(3)); g.DrawLine(pen, X(23), Y(28), X(23), Y(9));
      }
      using (var pen = new Pen(C(70, 138, 52, actif), 1.6f * s)) foreach (var v in new[] { new[] { 9f, 21f }, new[] { 9f, 14f }, new[] { 16f, 22f }, new[] { 16f, 15f }, new[] { 16f, 8f }, new[] { 23f, 21f }, new[] { 23f, 14f } }) g.DrawLine(pen, X(v[0] - 1.6f), Y(v[1]), X(v[0] + 1.6f), Y(v[1]));
      using (var pen = new Pen(C(86, 170, 62, actif), 2 * s) { StartCap = LineCap.Round, EndCap = LineCap.Round }) g.DrawBezier(pen, X(16), Y(11), X(21), Y(6), X(26), Y(5), X(30), Y(7));
    }
  }
}

// Boutons de la barre de titre (la fenetre n'a plus la barre de Windows) : relancer, reduire et fermer.
public class BoutonFenetre : Control {
  public bool Fermer, Relancer; bool survol;
  public BoutonFenetre() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true); BackColor = Color.Transparent; }
  protected override void OnMouseEnter(EventArgs e) { survol = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { survol = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    if (survol) using (var p = Th.Arrondi(new RectangleF(4, 6, Width - 8, Height - 12), 8)) using (var b = new SolidBrush(Fermer ? Color.FromArgb(220, 60, 60) : Th.CarteHaute)) g.FillPath(b, p);
    float cx = Width / 2f, cy = Height / 2f;
    using (var pen = new Pen(survol ? Color.White : Th.Discret, 1.4f) { StartCap = LineCap.Round, EndCap = LineCap.Round }) {
      if (Fermer) { g.DrawLine(pen, cx - 5, cy - 5, cx + 5, cy + 5); g.DrawLine(pen, cx - 5, cy + 5, cx + 5, cy - 5); }
      else if (Relancer) {   // fleche en cercle
        g.DrawArc(pen, cx - 6, cy - 6, 12, 12, -20, 290);                  // de -20 a 270 degres : ouvert en haut a droite
        using (var b = new SolidBrush(pen.Color)) g.FillPolygon(b, new[] { new PointF(cx + 4.5f, cy - 6), new PointF(cx - 1, cy - 10), new PointF(cx - 1, cy - 2) });   // pointe, sens des aiguilles
      }
      else g.DrawLine(pen, cx - 5.5f, cy, cx + 5.5f, cy);
    }
  }
}

// Courbe des gains de la session en cours (un point par seconde), remplie en degrade de la couleur d'accent.
public class Courbe : Control {
  public List<double> Points = new List<double>();
  public Courbe() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true); BackColor = Color.Transparent; }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    using (var pen = new Pen(Th.Bordure) { DashStyle = DashStyle.Dot }) for (int k = 1; k <= 3; k++) g.DrawLine(pen, 0, Height * k / 4f, Width, Height * k / 4f);   // quadrillage leger
    using (var pen = new Pen(Th.Bordure)) g.DrawLine(pen, 0, Height - 1, Width, Height - 1);
    if (Points.Count < 2) {
      using (var f = new Font("Segoe UI", 8.75f)) TextRenderer.DrawText(g, "La courbe des gains de la session s'affiche ici.", f, new Rectangle(0, 0, Width, Height), Th.Discret, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
      return;
    }
    // au plus 240 points (on en saute si la session est longue)
    int n = Points.Count, pasPt = Math.Max(1, n / 240);
    var pts = new List<double>(); for (int i = 0; i < n; i += pasPt) pts.Add(Points[i]); if ((n - 1) % pasPt != 0) pts.Add(Points[n - 1]);
    double min = 0, max = 0; foreach (var v in pts) { min = Math.Min(min, v); max = Math.Max(max, v); }
    if (max - min < 1) max = min + 1;
    float h = Height - 6;
    var ligne = new PointF[pts.Count];
    for (int i = 0; i < pts.Count; i++) ligne[i] = new PointF(i * (Width - 2f) / (pts.Count - 1) + 1, 3 + h - (float)((pts[i] - min) / (max - min) * h));
    using (var zone = new GraphicsPath()) {
      zone.AddLines(ligne); zone.AddLine(ligne[ligne.Length - 1], new PointF(ligne[ligne.Length - 1].X, Height)); zone.AddLine(new PointF(ligne[ligne.Length - 1].X, Height), new PointF(ligne[0].X, Height)); zone.CloseFigure();
      using (var b = new LinearGradientBrush(new Rectangle(0, 0, Width, Height), Color.FromArgb(90, Th.Accent), Color.FromArgb(0, Th.Accent), LinearGradientMode.Vertical)) g.FillPath(b, zone);
    }
    using (var pen = new Pen(Color.FromArgb(60, Th.Accent), 6f) { LineJoin = LineJoin.Round }) g.DrawLines(pen, ligne);   // halo
    using (var pen = new Pen(Th.Accent, 2.2f) { LineJoin = LineJoin.Round }) g.DrawLines(pen, ligne);
    var fin = ligne[ligne.Length - 1];
    using (var b = new SolidBrush(Color.FromArgb(70, Th.Accent))) g.FillEllipse(b, fin.X - 8, fin.Y - 8, 16, 16);
    using (var b = new SolidBrush(Th.Accent)) g.FillEllipse(b, fin.X - 4, fin.Y - 4, 8, 8);
  }
}

// ------------------------------ Controles de reglage dessines ------------------------------
public class ControleDessine : Control {
  protected bool survol;
  public ControleDessine() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.Selectable, true); BackColor = Th.Carte; Cursor = Cursors.Hand; }
  protected override void OnMouseEnter(EventArgs e) { survol = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { survol = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnEnabledChanged(EventArgs e) { Cursor = Enabled ? Cursors.Hand : Cursors.Default; Invalidate(); base.OnEnabledChanged(e); }
  protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
  protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
  protected Graphics Prep(PaintEventArgs e) { var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit; return g; }
}

// Nombre : [ - ]  valeur  [ + ]  ; molette, fleches du clavier, chiffres tapes puis Entree.
public class Nombre : ControleDessine {
  decimal val; string saisie;
  public decimal Minimum = 0, Maximum = 100, Increment = 1;
  public event EventHandler ValueChanged;
  public decimal Value { get { return val; } set { var v = Math.Max(Minimum, Math.Min(Maximum, value)); if (v != val) { val = v; Invalidate(); if (ValueChanged != null) ValueChanged(this, EventArgs.Empty); } } }
  RectangleF Moins { get { return new RectangleF(3, 3, Height - 6, Height - 6); } }
  RectangleF Plus { get { return new RectangleF(Width - Height + 3, 3, Height - 6, Height - 6); } }
  protected override void OnMouseDown(MouseEventArgs e) {
    Focus(); if (!Enabled) return;
    if (Moins.Contains(e.Location)) Value -= Increment; else if (Plus.Contains(e.Location)) Value += Increment;
    base.OnMouseDown(e);
  }
  protected override void OnMouseWheel(MouseEventArgs e) { if (Enabled) Value += Math.Sign(e.Delta) * Increment; base.OnMouseWheel(e); }
  protected override bool IsInputKey(Keys k) { return k == Keys.Up || k == Keys.Down || base.IsInputKey(k); }
  protected override void OnKeyDown(KeyEventArgs e) {
    if (!Enabled) return;
    if (e.KeyCode == Keys.Up) Value += Increment; else if (e.KeyCode == Keys.Down) Value -= Increment;
    else if (e.KeyCode == Keys.Enter) Valider(); else if (e.KeyCode == Keys.Escape) { saisie = null; Invalidate(); }
    else if (e.KeyCode == Keys.Back && saisie != null) { saisie = saisie.Length > 1 ? saisie.Substring(0, saisie.Length - 1) : null; Invalidate(); }
    base.OnKeyDown(e);
  }
  protected override void OnKeyPress(KeyPressEventArgs e) { if (Enabled && char.IsDigit(e.KeyChar) && (saisie == null || saisie.Length < 8)) { saisie = (saisie ?? "") + e.KeyChar; Invalidate(); } base.OnKeyPress(e); }
  protected override void OnLostFocus(EventArgs e) { Valider(); base.OnLostFocus(e); }
  void Valider() { if (saisie != null) { decimal v; var s = saisie; saisie = null; if (decimal.TryParse(s, out v)) Value = v; Invalidate(); } }
  protected override void OnPaint(PaintEventArgs e) {
    var g = Prep(e); var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
    Color bord = !Enabled ? Th.Bordure : (Focused ? Th.Accent : (survol ? Th.Melange(Th.Bordure, Th.Texte, 0.25f) : Th.Bordure));
    using (var p = Th.Arrondi(r, Height / 2f)) using (var b = new SolidBrush(Enabled ? Th.Champ : Th.Carte)) using (var pen = new Pen(bord, Focused ? 1.6f : 1f)) { g.FillPath(b, p); g.DrawPath(pen, p); }
    Color sym = Enabled ? Th.Texte : Th.Bordure;
    foreach (var zone in new[] { Moins, Plus }) {
      using (var b = new SolidBrush(Enabled ? Th.CarteHaute : Th.Carte)) g.FillEllipse(b, zone);
      using (var pen = new Pen(sym, 1.8f) { StartCap = LineCap.Round, EndCap = LineCap.Round }) {
        float cx = zone.X + zone.Width / 2, cy = zone.Y + zone.Height / 2;
        g.DrawLine(pen, cx - 4.5f, cy, cx + 4.5f, cy);
        if (zone == Plus) g.DrawLine(pen, cx, cy - 4.5f, cx, cy + 4.5f);
      }
    }
    string t = saisie != null ? saisie + "_" : val.ToString("0");
    TextRenderer.DrawText(g, t, Font, new Rectangle(0, 0, Width, Height), saisie != null ? Th.Accent : (Enabled ? Th.Texte : Th.Discret), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
  }
}

// Segments : choix parmi quelques options, en pastille ; l'option choisie est remplie de la couleur d'accent.
public class Segments : ControleDessine {
  string[] options = new string[0]; int choix = -1, survolIdx = -1;
  public event EventHandler SelectedIndexChanged;
  public Segments(params string[] opts) { options = opts; choix = 0; Text = opts.Length > 0 ? opts[0] : ""; }
  public int SelectedIndex { get { return choix; } set { if (value != choix && value >= 0 && value < options.Length) { choix = value; Text = options[value]; Invalidate(); if (SelectedIndexChanged != null) SelectedIndexChanged(this, EventArgs.Empty); } } }
  RectangleF Case(int i) { float w = (Width - 6f) / options.Length; return new RectangleF(3 + i * w, 3, w, Height - 6); }
  protected override void OnMouseMove(MouseEventArgs e) { int k = -1; for (int i = 0; i < options.Length; i++) if (Case(i).Contains(e.Location)) k = i; if (k != survolIdx) { survolIdx = k; Invalidate(); } base.OnMouseMove(e); }
  protected override void OnMouseLeave(EventArgs e) { survolIdx = -1; base.OnMouseLeave(e); }
  protected override void OnMouseDown(MouseEventArgs e) { if (Enabled) for (int i = 0; i < options.Length; i++) if (Case(i).Contains(e.Location)) SelectedIndex = i; base.OnMouseDown(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = Prep(e); var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
    using (var p = Th.Arrondi(r, Height / 2f)) using (var b = new SolidBrush(Enabled ? Th.Champ : Th.Carte)) using (var pen = new Pen(Th.Bordure)) { g.FillPath(b, p); g.DrawPath(pen, p); }
    for (int i = 0; i < options.Length; i++) {
      var c = Case(i);
      if (i == choix || (i == survolIdx && Enabled)) {
        Color f = i == choix ? (Enabled ? Th.Accent : Th.Bordure) : Th.CarteHaute;
        using (var p = Th.Arrondi(c, c.Height / 2f)) using (var b = new SolidBrush(f)) g.FillPath(b, p);
      }
      Color t = i == choix ? (Enabled ? Color.FromArgb(16, 16, 18) : Th.Discret) : (Enabled ? Th.Texte : Th.Bordure);
      using (var f = new Font(Font, i == choix ? FontStyle.Bold : FontStyle.Regular))
        TextRenderer.DrawText(g, options[i], f, Rectangle.Round(c), t, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }
  }
}

// Interrupteur : texte a gauche, bouton glissant a droite.
public class Interrupteur : ControleDessine {
  bool coche;
  public event EventHandler CheckedChanged;
  public bool Checked { get { return coche; } set { if (value != coche) { coche = value; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); } } }
  protected override void OnMouseDown(MouseEventArgs e) { if (Enabled) Checked = !Checked; base.OnMouseDown(e); }
  protected override bool IsInputKey(Keys k) { return k == Keys.Space || base.IsInputKey(k); }
  protected override void OnKeyDown(KeyEventArgs e) { if (Enabled && e.KeyCode == Keys.Space) Checked = !Checked; base.OnKeyDown(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = Prep(e);
    TextRenderer.DrawText(g, Text, Font, new Rectangle(0, 0, Width - 60, Height), Enabled ? Th.Texte : Th.Discret, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
    var rail = new RectangleF(Width - 48, (Height - 24) / 2f, 46, 24);
    Color fond = coche ? (Enabled ? Th.Accent : Th.Bordure) : (survol && Enabled ? Th.CarteHaute : Th.Champ);
    using (var p = Th.Arrondi(rail, 12)) using (var b = new SolidBrush(fond)) using (var pen = new Pen(coche ? fond : Th.Bordure)) { g.FillPath(b, p); g.DrawPath(pen, p); }
    float x = coche ? rail.Right - 21 : rail.X + 3;
    using (var b = new SolidBrush(coche ? Color.White : (Enabled ? Th.Discret : Th.Bordure))) g.FillEllipse(b, x, rail.Y + 3, 18, 18);
  }
}

// Pastilles de couleur pour le theme ; la derniere ("+") ouvre le selecteur de Windows.
public class Pastilles : ControleDessine {
  public List<Color> Couleurs = new List<Color>(); public event EventHandler<int> Choisie; int survolIdx = -1;
  RectangleF Rond(int i) { return new RectangleF(4 + i * 44, 4, 34, 34); }
  int Sous(Point p) { for (int i = 0; i <= Couleurs.Count; i++) if (Rond(i).Contains(p)) return i; return -1; }
  protected override void OnMouseMove(MouseEventArgs e) { int k = Sous(e.Location); if (k != survolIdx) { survolIdx = k; Invalidate(); } base.OnMouseMove(e); }
  protected override void OnMouseLeave(EventArgs e) { survolIdx = -1; base.OnMouseLeave(e); }
  protected override void OnMouseDown(MouseEventArgs e) { int k = Sous(e.Location); if (k >= 0 && Choisie != null) Choisie(this, k); base.OnMouseDown(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = Prep(e);
    for (int i = 0; i <= Couleurs.Count; i++) {
      var r = Rond(i);
      bool perso = i == Couleurs.Count, actif = !perso && Couleurs[i].ToArgb() == Th.Accent.ToArgb();
      if (actif || i == survolIdx) using (var pen = new Pen(actif ? Th.Texte : Th.Discret, 2f)) g.DrawEllipse(pen, r.X - 3, r.Y - 3, r.Width + 6, r.Height + 6);
      if (perso) {
        using (var b = new SolidBrush(Th.Champ)) g.FillEllipse(b, r);
        using (var pen = new Pen(Th.Texte, 2f) { StartCap = LineCap.Round, EndCap = LineCap.Round }) { float cx = r.X + 17, cy = r.Y + 17; g.DrawLine(pen, cx - 6, cy, cx + 6, cy); g.DrawLine(pen, cx, cy - 6, cx, cy + 6); }
      } else using (var b = new SolidBrush(Couleurs[i])) g.FillEllipse(b, r);
    }
  }
}

// Choix d'une touche : clic, puis appui sur la touche voulue (Echap = annuler).
public class ChoixTouche : ControleDessine {
  int vk; bool attente;
  public event EventHandler Changee;
  public Func<int, string> Refus;   // message si la touche est refusee, null sinon
  public int Vk { get { return vk; } set { vk = value; Invalidate(); } }
  public static string Nom(int vk) {
    var k = (Keys)vk;
    if (k >= Keys.D0 && k <= Keys.D9) return ((int)(k - Keys.D0)).ToString();
    if (k >= Keys.NumPad0 && k <= Keys.NumPad9) return "Pave " + (int)(k - Keys.NumPad0);
    return k.ToString();
  }
  protected override void OnMouseDown(MouseEventArgs e) { Focus(); if (Enabled) { attente = true; Invalidate(); } base.OnMouseDown(e); }
  protected override bool IsInputKey(Keys k) { return attente || base.IsInputKey(k); }
  protected override void OnKeyDown(KeyEventArgs e) {
    if (!attente) { base.OnKeyDown(e); return; }
    e.Handled = true; e.SuppressKeyPress = true; attente = false;
    if (e.KeyCode != Keys.Escape) {
      string non = Refus != null ? Refus((int)e.KeyCode) : null;
      if (non == null) { vk = (int)e.KeyCode; if (Changee != null) Changee(this, EventArgs.Empty); }
      else MessageBox.Show(FindForm(), non, "Touche refusee", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }
    Invalidate();
  }
  protected override void OnLostFocus(EventArgs e) { attente = false; base.OnLostFocus(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = Prep(e); var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
    Color bord = !Enabled ? Th.Bordure : (attente ? Th.Accent : (survol ? Th.Melange(Th.Bordure, Th.Texte, 0.25f) : Th.Bordure));
    using (var p = Th.Arrondi(r, Height / 2f)) using (var b = new SolidBrush(Enabled ? Th.Champ : Th.Carte)) using (var pen = new Pen(bord, attente ? 1.6f : 1f)) { g.FillPath(b, p); g.DrawPath(pen, p); }
    string t = attente ? "appuie sur une touche..." : Nom(vk);
    using (var f = new Font(Font, attente ? FontStyle.Regular : FontStyle.Bold))
      TextRenderer.DrawText(g, t, f, new Rectangle(0, 0, Width, Height), attente ? Th.Accent : (Enabled ? Th.Texte : Th.Discret), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
  }
}

// ------------------------------ Historique des sessions ------------------------------
public class Session {
  public DateTime Date; public int DureeS, Tours, Etages, Clics, Ventes, Essais; public string Mode; public double? ArgentDebut, ArgentFin;
  public double ArgentPrises, Xp;   // peche : somme des gains lus a chaque prise
  // details (colonnes ajoutees le 07/11/2026, vides dans les sessions d'avant) : duree moyenne d'un etage,
  // ventes reussies du 1er coup, echelles ratees puis reprises, raison de l'arret
  public int EtageMoyenS = -1, PremierCoup = -1, EchellesRatees = -1; public string Raison = "";
  public double ArgentHors;   // grosses sommes entrees ou sorties hors ferme (vente d'un objet, achat) : retirees des gains
  // peche et minage : le plus grand des gains lus a chaque prise et de l'argent du haut (voir GainsPrises du menu)
  public double? Gains { get {
    double? haut = ArgentDebut.HasValue && ArgentFin.HasValue ? ArgentFin - ArgentDebut - ArgentHors : null;
    if (ArgentPrises > 0) return haut.HasValue ? Math.Max(ArgentPrises, haut.Value) : ArgentPrises;
    return haut;
  } }
  public double? ParHeure { get { return Gains.HasValue && DureeS >= 60 ? Gains / (DureeS / 3600.0) : null; } }
  static readonly System.Globalization.CultureInfo Inv = System.Globalization.CultureInfo.InvariantCulture;
  // peche : poissons par espece, avec la couleur du nom dans le chat (sa rarete)
  public Dictionary<string, int> Especes = new Dictionary<string, int>();
  public Dictionary<string, Color> CouleursEsp = new Dictionary<string, Color>();
  public const string Entete = "date;duree_s;mode;tours;etages;clics;ventes;essais;argent_debut;argent_fin;especes;argent_prises;xp;etage_moyen_s;ventes_1er_coup;echelles_ratees;raison;argent_hors_ferme";
  public string Ligne() {
    var esp = new List<string>();
    foreach (var kv in Especes) { Color c; CouleursEsp.TryGetValue(kv.Key, out c); esp.Add(string.Format("{0}:{1}:{2:X2}{3:X2}{4:X2}", kv.Key.Replace(";", "").Replace("|", "").Replace(":", ""), kv.Value, c.R, c.G, c.B)); }
    return string.Join(";", new[] { Date.ToString("yyyy-MM-dd HH:mm", Inv), DureeS.ToString(), Mode, Tours.ToString(), Etages.ToString(), Clics.ToString(), Ventes.ToString(), Essais.ToString(),
      ArgentDebut.HasValue ? ArgentDebut.Value.ToString("0", Inv) : "", ArgentFin.HasValue ? ArgentFin.Value.ToString("0", Inv) : "", string.Join("|", esp.ToArray()),
      ArgentPrises.ToString("0.##", Inv), Xp.ToString("0.##", Inv),
      EtageMoyenS >= 0 ? EtageMoyenS.ToString() : "", PremierCoup >= 0 ? PremierCoup.ToString() : "", EchellesRatees >= 0 ? EchellesRatees.ToString() : "",
      (Raison ?? "").Replace(";", ",").Replace("\r", " ").Replace("\n", " "), ArgentHors.ToString("0", Inv) });
  }
  // 2e ligne d'une session dans les statistiques (sessions enregistrees depuis le 07/11/2026)
  public string Details() {
    var d = new List<string>();
    if (EtageMoyenS > 0) d.Add(string.Format("étage {0}:{1:00}", EtageMoyenS / 60, EtageMoyenS % 60));
    if (PremierCoup >= 0 && Ventes > 0) d.Add(string.Format("1er coup {0} %", 100 * PremierCoup / Ventes));
    if (EchellesRatees > 0) d.Add(EchellesRatees + " échelle" + (EchellesRatees > 1 ? "s" : "") + " ratée" + (EchellesRatees > 1 ? "s" : ""));
    if (!string.IsNullOrEmpty(Raison)) d.Add(Raison);
    return string.Join("  ·  ", d.ToArray());
  }
  // "Carpe:12:62A865|Saumon:4:..." (colonne absente dans les sessions d'avant le 24/10/2026)
  public static void LireEspeces(string champ, Dictionary<string, int> nb, Dictionary<string, Color> col) {
    foreach (var e in champ.Split('|')) {
      var q = e.Split(':'); int v; if (q.Length != 3 || !int.TryParse(q[1], out v)) continue;
      int deja; nb.TryGetValue(q[0], out deja); nb[q[0]] = deja + v;
      try { col[q[0]] = ColorTranslator.FromHtml("#" + q[2]); } catch { }
    }
  }
  public static Session Lire(string l) {
    var p = l.Split(';'); if (p.Length < 10) return null;
    DateTime d; if (!DateTime.TryParseExact(p[0], "yyyy-MM-dd HH:mm", Inv, System.Globalization.DateTimeStyles.None, out d)) return null;
    Func<string, int> n = s => { int v; return int.TryParse(s, out v) ? v : 0; };
    Func<string, double?> a = s => { double v; return double.TryParse(s, System.Globalization.NumberStyles.Float, Inv, out v) ? v : (double?)null; };
    var ses = new Session { Date = d, DureeS = n(p[1]), Mode = p[2], Tours = n(p[3]), Etages = n(p[4]), Clics = n(p[5]), Ventes = n(p[6]), Essais = n(p[7]), ArgentDebut = a(p[8]), ArgentFin = a(p[9]) };
    if (p.Length > 10) LireEspeces(p[10], ses.Especes, ses.CouleursEsp);
    if (p.Length > 12) { ses.ArgentPrises = a(p[11]) ?? 0; ses.Xp = a(p[12]) ?? 0; }
    Func<string, int> nv = s => { int v; return int.TryParse(s, out v) ? v : -1; };
    if (p.Length > 16) { ses.EtageMoyenS = nv(p[13]); ses.PremierCoup = nv(p[14]); ses.EchellesRatees = nv(p[15]); ses.Raison = p[16]; }
    if (p.Length > 17) ses.ArgentHors = a(p[17]) ?? 0;
    return ses;
  }
  // 31780000 -> "31.78M"
  public static string Argent(double v) {
    double x = Math.Abs(v); string s;
    if (x >= 1e9) s = (x / 1e9).ToString("0.00", Inv) + "B"; else if (x >= 1e6) s = (x / 1e6).ToString("0.00", Inv) + "M";
    else if (x >= 1e3) s = (x / 1e3).ToString("0.0", Inv) + "K"; else s = x.ToString("0", Inv);
    return (v < 0 ? "-" : "") + s;
  }
  public static string Signe(double v) { return (v >= 0 ? "+" : "") + Argent(v); }
  public static string Duree(int s) { return string.Format("{0}:{1:00}:{2:00}", s / 3600, s / 60 % 60, s % 60); }
}

// Page Statistiques : totaux, graphique des gains par heure des dernieres sessions, liste des dernieres sessions.
public class Graphique : Control {
  public List<Session> Sessions = new List<Session>();
  public string Filtre;   // null = toutes ; sinon le mode : "canne", "peche" ou "autoclick" (minage)
  public List<string[]> Verifs = new List<string[]>();   // diagnostics\verifications.csv : date;mode;nombre;reponse;resultat;dossier
  public Graphique() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true); BackColor = Th.Carte; }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    var petit = new Font("Segoe UI Semibold", 8.25f); var gros = new Font("Segoe UI Semibold", 14f); var normal = new Font("Segoe UI", 9f); var mono = new Font("Consolas", 9f);
    var liste = Filtre == null ? Sessions : Sessions.FindAll(x => x.Mode == Filtre);
    try {
      if (liste.Count == 0) {
        TextRenderer.DrawText(g, Filtre == null ? "Aucune session enregistrée pour l'instant.\nChaque session (ferme, pêche ou autoclick) s'ajoute ici quand le script s'arrête." : "Aucune session dans cette catégorie pour l'instant.", normal, new Rectangle(0, 0, Width, 80), Th.Discret, TextFormatFlags.Left | TextFormatFlags.WordBreak);
        return;
      }
      // totaux
      int duree = 0; double gains = 0; int dureeGains = 0; int ventes = 0;
      foreach (var s in liste) { duree += s.DureeS; ventes += s.Ventes; if (s.Gains.HasValue) { gains += s.Gains.Value; dureeGains += s.DureeS; } }
      var totaux = new[] {
        new[] { "SESSIONS", liste.Count.ToString() }, new[] { "TEMPS", Session.Duree(duree) },
        new[] { "GAINS", dureeGains > 0 ? Session.Signe(gains) : "-" }, new[] { "PAR HEURE", dureeGains >= 60 ? Session.Signe(gains / (dureeGains / 3600.0)) : "-" } };
      float lc = Width / 4f;
      for (int i = 0; i < 4; i++) {
        TextRenderer.DrawText(g, totaux[i][0], petit, new Point((int)(i * lc), 0), Th.Discret);
        TextRenderer.DrawText(g, totaux[i][1], gros, new Point((int)(i * lc) - 2, 16), i >= 2 ? Th.Accent : Th.Texte);
      }
      // graphique : gains par heure des 14 dernieres sessions
      int y0 = 62, hg = 170;
      TextRenderer.DrawText(g, "GAINS PAR HEURE  (dernières sessions)", petit, new Point(0, y0), Th.Discret);
      var der = liste.GetRange(Math.Max(0, liste.Count - 14), Math.Min(14, liste.Count));
      double max = 1; foreach (var s in der) if (s.ParHeure.HasValue) max = Math.Max(max, Math.Abs(s.ParHeure.Value));
      var zone = new RectangleF(0, y0 + 24, Width, hg - 44);
      using (var pen = new Pen(Th.Bordure)) g.DrawLine(pen, zone.Left, zone.Bottom, zone.Right, zone.Bottom);
      TextRenderer.DrawText(g, "max " + Session.Argent(max) + "/h", petit, new Rectangle(0, y0, Width, 16), Th.Discret, TextFormatFlags.Right);
      float lb = Width / (float)Math.Max(8, der.Count); bool unSurDeux = lb < 40;
      for (int i = 0; i < der.Count; i++) {
        var s = der[i]; float x = i * lb + lb * 0.18f, w = lb * 0.64f;
        if (s.ParHeure.HasValue && s.ParHeure.Value > 0) {
          float h = (float)(s.ParHeure.Value / max * (zone.Height - 4)); if (h < 3) h = 3;
          using (var p = Th.Arrondi(new RectangleF(x, zone.Bottom - h, w, h), Math.Min(5, w / 2))) using (var b = new SolidBrush(i == der.Count - 1 ? Th.Accent : Th.Melange(Th.Carte, Th.Accent, 0.55f))) g.FillPath(b, p);
        } else using (var b = new SolidBrush(Th.Bordure)) g.FillRectangle(b, x, zone.Bottom - 3, w, 3);
        if (!unSurDeux || (der.Count - 1 - i) % 2 == 0) TextRenderer.DrawText(g, s.Date.ToString("dd/MM"), petit, new Rectangle((int)(i * lb) - 4, (int)zone.Bottom + 4, (int)lb + 8, 16), Th.Discret, TextFormatFlags.HorizontalCenter);
      }
      // poissons par espece (toutes les sessions), dans la couleur de leur nom
      int yl = y0 + hg + 8;
      var nbEsp = new Dictionary<string, int>(); var colEsp = new Dictionary<string, Color>();
      foreach (var s in liste) foreach (var kv in s.Especes) { int deja; nbEsp.TryGetValue(kv.Key, out deja); nbEsp[kv.Key] = deja + kv.Value; Color c; if (s.CouleursEsp.TryGetValue(kv.Key, out c)) colEsp[kv.Key] = c; }
      if (nbEsp.Count > 0) {
        TextRenderer.DrawText(g, "POISSONS PAR ESPÈCE", petit, new Point(0, yl), Th.Discret);
        double xpTotal = 0; foreach (var s in liste) xpTotal += s.Xp;
        if (xpTotal > 0) TextRenderer.DrawText(g, "XP GAGNÉE  " + Session.Signe(xpTotal), petit, new Rectangle(0, yl, Width, 16), Th.Accent, TextFormatFlags.Right);
        var tri = new List<KeyValuePair<string, int>>(nbEsp); tri.Sort((x, y) => y.Value.CompareTo(x.Value));
        int xe = 0, ye = yl + 20;
        foreach (var kv in tri) {
          string t = kv.Key + " " + kv.Value; int lt = TextRenderer.MeasureText(t, normal).Width;
          if (xe + lt > Width) { xe = 0; ye += 18; if (ye > yl + 20 + 18) break; }   // 2 lignes au plus
          Color c; if (!colEsp.TryGetValue(kv.Key, out c)) c = Th.Texte;
          TextRenderer.DrawText(g, t, normal, new Point(xe, ye), c);
          xe += lt + 8;
        }
        yl = ye + 26;
      } else {   // pas d'especes (minage) : l'XP seule
        double xpSeul = 0; foreach (var s in liste) xpSeul += s.Xp;
        if (xpSeul > 0) { TextRenderer.DrawText(g, "XP GAGNÉE  " + Session.Signe(xpSeul), petit, new Point(0, yl), Th.Accent); yl += 26; }
      }
      // dernieres sessions
      TextRenderer.DrawText(g, "DERNIÈRES SESSIONS", petit, new Point(0, yl), Th.Discret);
      int nbVerif = 0, reussies = 0;
      // seulement les vraies verifications (un nombre a ete lu) : les fausses alertes (gros titre du serveur...) ne comptent pas
      foreach (var v in Verifs) if ((Filtre == null || v[1] == Filtre) && v[2].Trim() != "") { nbVerif++; if (v[4] == "reussie") reussies++; }
      if (nbVerif > 0) TextRenderer.DrawText(g, string.Format("VÉRIFICATIONS AFK  {0}  ({1} réussie{2} seul)", nbVerif, reussies, reussies > 1 ? "s" : ""), petit, new Rectangle(0, yl, Width, 16), Th.Discret, TextFormatFlags.Right);
      yl += 22;
      for (int i = liste.Count - 1; i >= 0 && yl + 18 <= Height; i--) {
        var s = liste[i];
        string quoi = s.Mode == "autoclick" ? "autoclick" : s.Mode == "peche" ? "pêche" : s.Mode == "recolte" ? "pastèque" : s.Mode == "citrouille" ? "citrouille" : (s.Tours > 0 ? s.Tours + " tour" + (s.Tours > 1 ? "s" : "") : s.Etages + " étage" + (s.Etages > 1 ? "s" : ""));
        TextRenderer.DrawText(g, string.Format("{0:dd/MM HH:mm}  {1,8}  {2,-10}", s.Date, Session.Duree(s.DureeS), quoi), mono, new Point(0, yl), Th.Texte);
        TextRenderer.DrawText(g, s.Gains.HasValue ? Session.Signe(s.Gains.Value) : "-", mono, new Rectangle(0, yl, Width - 92, 18), s.Gains.HasValue ? Th.Accent : Th.Discret, TextFormatFlags.Right);
        TextRenderer.DrawText(g, s.Mode == "peche" ? s.Clics + " poissons" : s.Ventes + " ventes", mono, new Rectangle(0, yl, Width, 18), Th.Discret, TextFormatFlags.Right);
        yl += 20;
        string det = s.Details();
        if (det.Length > 0 && yl + 16 <= Height) {
          TextRenderer.DrawText(g, det, petit, new Rectangle(8, yl - 2, Width - 8, 16), Th.Discret, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
          yl += 18;
        }
      }
    } finally { petit.Dispose(); gros.Dispose(); normal.Dispose(); mono.Dispose(); }
  }
}

// Mini-fenetre toujours au premier plan : etat, temps, ventes, gains par heure.
// Elle ne prend jamais le focus (sinon le jeu passerait au second plan et le script se mettrait en pause).
public class MiniFenetre : Form {
  public string Etat = "arrêté", Temps = "-", Ventes = "-", Gains = "-"; public Color Pastille = Th.Discret;
  public event EventHandler Deplacee;
  Point prise; bool glisse;
  public MiniFenetre() {
    FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
    Size = new Size(264, 84); BackColor = Th.Fond; DoubleBuffered = true; Cursor = Cursors.SizeAll;
    using (var p = Th.Arrondi(new RectangleF(0, 0, Width, Height), 14)) Region = new Region(p);
  }
  // Invisible aux captures d'ecran (toi, tu la vois) : les scripts lisent l'ecran et voient le jeu DERRIERE elle.
  // 26/10/2026 : posee sur les coordonnees, elle cachait la ligne Z -> lectures fausses, "faux murs", ferme bloquee.
  // (WDA_EXCLUDEFROMCAPTURE, Windows 10 2004 et plus ; sans effet ailleurs.)
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetWindowDisplayAffinity(IntPtr h, uint affinite);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool GetWindowDisplayAffinity(IntPtr h, out uint affinite);
  public bool InvisibleAuxCaptures { get { uint a; return GetWindowDisplayAffinity(Handle, out a) && a == 0x11; } }
  protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); try { SetWindowDisplayAffinity(Handle, 0x11); } catch { } }
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams { get { var cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x80 | 0x8; return cp; } }   // pas d'activation, pas dans Alt+Tab, au premier plan
  protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { glisse = true; prise = e.Location; } base.OnMouseDown(e); }
  protected override void OnMouseMove(MouseEventArgs e) { if (glisse) Location = new Point(Cursor.Position.X - prise.X, Cursor.Position.Y - prise.Y); base.OnMouseMove(e); }
  protected override void OnMouseUp(MouseEventArgs e) { if (glisse) { glisse = false; if (Deplacee != null) Deplacee(this, EventArgs.Empty); } base.OnMouseUp(e); }
  public void Maj() { Invalidate(); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    using (var p = Th.Arrondi(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 14)) using (var b = new SolidBrush(Th.Carte)) using (var pen = new Pen(Th.Bordure, 1f)) { g.FillPath(b, p); g.DrawPath(pen, p); }
    using (var b = new SolidBrush(Th.Accent)) g.FillRectangle(b, 0, 18, 3, Height - 36);   // petit repere de couleur a gauche
    using (var b = new SolidBrush(Pastille)) g.FillEllipse(b, 16, 17, 10, 10);
    using (var f = new Font("Segoe UI Semibold", 9.5f)) TextRenderer.DrawText(g, Etat, f, new Rectangle(32, 12, Width - 44, 20), Th.Texte, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
    using (var f = new Font("Segoe UI Semibold", 20f)) TextRenderer.DrawText(g, Temps, f, new Point(12, 34), Th.Accent);
    using (var f = new Font("Segoe UI", 9f)) {
      TextRenderer.DrawText(g, Ventes, f, new Rectangle(0, 36, Width - 16, 18), Th.Texte, TextFormatFlags.Right);
      TextRenderer.DrawText(g, Gains, f, new Rectangle(0, 56, Width - 16, 18), Th.Accent, TextFormatFlags.Right);
    }
  }
}

public class FermeCanne : Form {
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte sc, uint f, IntPtr e);
  [DllImport("user32.dll")] static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int taille);

  static readonly Dictionary<string, Color> Accents = new Dictionary<string, Color> {
    { "Orange", Color.FromArgb(255, 138, 0) }, { "Rouge", Color.FromArgb(235, 64, 64) }, { "Rose", Color.FromArgb(240, 84, 160) },
    { "Violet", Color.FromArgb(150, 100, 255) }, { "Bleu", Color.FromArgb(40, 140, 255) }, { "Cyan", Color.FromArgb(0, 200, 210) },
    { "Vert", Color.FromArgb(60, 200, 90) }, { "Jaune", Color.FromArgb(240, 200, 40) } };

  readonly string dossier = Environment.GetEnvironmentVariable("FERME_CANNE_DOSSIER") ?? AppDomain.CurrentDomain.BaseDirectory;
  string Script { get { return Path.Combine(dossier, "canne-etage.ps1"); } }
  string ScriptClic { get { return Path.Combine(dossier, "autoclic.ps1"); } }
  string ScriptPeche { get { return Path.Combine(dossier, "peche.ps1"); } }
  string ScriptRecolte { get { return Path.Combine(dossier, "recolte.ps1"); } }
  string FichierArret { get { return Path.Combine(dossier, "arret.flag"); } }
  string FichierReglages { get { return Path.Combine(dossier, "Ferme-canne.ini"); } }
  string FichierHistorique { get { return Path.Combine(dossier, "historique.csv"); } }
  string FichierDeparts { get { return Path.Combine(dossier, "departs-etages.txt"); } }

  Nombre etage, seuil, venteMs, marge, tours, antiLagS, voteSlots;
  Interrupteur antiLag;
  Interrupteur venteActive, regard, sonsActive;
  Segments pas, statsFiltre;
  Segments acBouton, acMode; Nombre acIntervalle, acDuree, acClicsMax, acSeuil, acVenteMs, acSlot, acTPBlocs, acVoteSlots; Interrupteur acVente, acStopTP; Label acCps;
  Interrupteur cnStopTP, rcStopTP, pcStopTP; Nombre cnTPBlocs, rcTPBlocs, pcTPBlocs; CarteRonde pageMine;
  Pastilles thCouleurs; Panel thApercu;
  ChoixTouche tPause, tArret; Interrupteur miniActive, verifActive;
  CarteRonde pageCanne, pageClic, pageTheme, pageStats; List<Tuile> tuiles = new List<Tuile>(); int page;
  Graphique graphique;
  BoutonRond demarrer, arreter, vider;
  Label lEtat, lTour, lEtage, lTraversee, lVentes, lTemps, lGains, lHeure, cTour, cEtage, cTraversee, titreAccent;
  Panel pastille;
  RichTextBox journal;
  Process proc;
  DateTime? debut; TimeSpan cumul; bool chronoLance;
  int ventes, essais, toursFinis, etagesFinis, clics;
  double? argentDebut, argentDernier, argentAttente; double argentHors;
  DateTime debutSession;
  int mode;   // script lance : 0 ferme, 1 autoclick (autoclic.ps1), 4 peche, 5 pasteques, 6 citrouilles (recolte.ps1 ; meme numero que sa tuile)
  bool modeClic { get { return mode == 1 || mode == 8; } }   // la mine 3x3 passe par autoclic.ps1
  bool modeMine { get { return mode == 8; } }
  Segments miMine; Interrupteur miStopTP; Nombre miTPBlocs;
  bool modePeche { get { return mode == 4; } }
  bool modeRecolte { get { return mode == 5 || mode == 6; } }
  CarteRonde pageCulture; List<BoutonRond> boutonsCulture = new List<BoutonRond>();
  Nombre rcEtage, rcRangees, rcTours; Interrupteur rcRegard; CarteRonde pageRecolte;   // toutes les fermes ont la meme taille et le meme regard (est) : le reste est fixe dans recolte.ps1
  int poissons, rates;
  Label cVentes, cGains;
  ToolTip bulleEspeces = new ToolTip { AutoPopDelay = 30000, InitialDelay = 200 };
  // Tuile PAR ESPECE : especes triees (la plus pechee d'abord) ; liste complete au survol.
  void MajEspeces() {
    var tri = new List<KeyValuePair<string, int>>(especes); tri.Sort((x, y) => y.Value.CompareTo(x.Value));
    var morceaux = new List<string>(); foreach (var kv in tri) morceaux.Add(kv.Key + " " + kv.Value);
    lVentes.Text = string.Join("  ·  ", morceaux.ToArray());
    bulleEspeces.SetToolTip(lVentes, string.Join("\n", morceaux.ToArray()));
  }
  double argentPeche, xpPeche; int prisesLues;   // peche : gains lus au-dessus de la vie a chaque prise
  Dictionary<string, int> especes = new Dictionary<string, int>(); Dictionary<string, Color> couleursEsp = new Dictionary<string, Color>();
  Nombre pcAnticip, pcTol, pcAttente, pcRelance, pcMax, pcSlot; Interrupteur pcSecondPlan, acSecondPlan;   // second plan : commandes envoyees a la fenetre du jeu
  CarteRonde pagePeche; Interrupteur pcVente; Nombre pcVenteMin, pcVenteSlot;
  Timer horloge;
  MiniFenetre mini; Point? miniPos;
  // Reprise : etage en cours pendant la session, etage ou repartir apres un arret, depart connu de chaque etage
  int etageEnCours, reprise; bool etageFini;
  Dictionary<int, string> departs = new Dictionary<int, string>();
  Label lReprise; BoutonRond bReprise;
  string NomPause { get { return ChoixTouche.Nom(tPause.Vk); } }
  string NomArret { get { return ChoixTouche.Nom(tArret.Vk); } }

  [STAThread] public static void Main() { Application.EnableVisualStyles(); Application.Run(new FermeCanne()); }

  public FermeCanne() {
    // Fenetre sans la barre de Windows : barre de titre dessinee (glisser pour deplacer), coins arrondis et
    // ombre de Windows 11, bords pour redimensionner (WndProc).
    Text = "Macros Minecraft"; FormBorderStyle = FormBorderStyle.None; ClientSize = new Size(1000, 860); MinimumSize = new Size(1000, 820);
    Font = new Font("Segoe UI", 9.75f); StartPosition = FormStartPosition.CenterScreen; BackColor = Th.Fond; ForeColor = Th.Texte;
    DoubleBuffered = true; SetStyle(ControlStyles.ResizeRedraw, true);
    ChargerAccent();

    // ---------- barre de titre ----------
    logo = new Panel { Left = 24, Top = 15, Width = 26, Height = 26, BackColor = Color.Transparent };
    logo.Paint += (s, e) => {
      var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
      using (var p = Th.Arrondi(new RectangleF(0, 0, 25, 25), 7)) using (var b = new LinearGradientBrush(new Rectangle(0, 0, 26, 26), Th.Melange(Th.Accent, Color.White, 0.3f), Th.Accent, LinearGradientMode.ForwardDiagonal)) g.FillPath(b, p);
      using (var pen = new Pen(Th.TexteSur(Th.Accent), 2.4f) { StartCap = LineCap.Round, EndCap = LineCap.Round }) { g.DrawLine(pen, 7, 19, 15, 11); g.DrawBezier(pen, new PointF(9, 7), new PointF(15, 5), new PointF(20, 10), new PointF(19, 16)); }
    };
    titreAccent = new Label { Text = "Macros Minecraft", Left = 58, Top = 16, AutoSize = true, Font = new Font("Segoe UI Semibold", 12f), ForeColor = Th.Texte, BackColor = Color.Transparent };
    Controls.Add(logo); Controls.Add(titreAccent);
    foreach (Control c in new Control[] { logo, titreAccent }) c.MouseDown += (s, e) => Glisser(e);
    var bReduire = new BoutonFenetre { Width = 44, Height = 44, Top = 6, Anchor = AnchorStyles.Top | AnchorStyles.Right };
    var bFermer = new BoutonFenetre { Fermer = true, Width = 44, Height = 44, Top = 6, Anchor = AnchorStyles.Top | AnchorStyles.Right };
    var bRelancer = new BoutonFenetre { Relancer = true, Width = 44, Height = 44, Top = 6, Anchor = AnchorStyles.Top | AnchorStyles.Right };
    bFermer.Left = ClientSize.Width - 14 - 44; bReduire.Left = bFermer.Left - 44; bRelancer.Left = bReduire.Left - 44;
    bReduire.Click += (s, e) => WindowState = FormWindowState.Minimized; bFermer.Click += (s, e) => Close(); bRelancer.Click += (s, e) => Relancer();
    new ToolTip().SetToolTip(bRelancer, "Redémarrer le menu (prend les dernières modifications)");
    Controls.Add(bRelancer); Controls.Add(bReduire); Controls.Add(bFermer);

    // ---------- navigation ----------
    // numero de tuile = numero de page ; Options et Statistiques : pastilles rondes a droite
    // Les cultures (0 canne, 5 pasteque, 6 citrouille) n'ont pas de tuile visible : on les choisit sur la page Culture (7).
    var defs = new[] { new[] { "Canne à sucre", "", "canne" }, new[] { "Autoclick", "", "souris" }, new[] { "Options", "", "palette" }, new[] { "Statistiques", "", "stats" }, new[] { "Pêche", "", "poisson" }, new[] { "Pastèque", "", "canne" }, new[] { "Citrouille", "", "canne" }, new[] { "Culture", "", "canne" }, new[] { "Minage", "", "pioche" } };
    int[] gauches = { 24, 588, 860, 920, 400, 24, 24, 24, 212 };
    var bulles = new ToolTip();
    for (int k = 0; k < defs.Length; k++) {
      int idx = k; bool petite = k == 2 || k == 3;
      var t = new Tuile { Titre = defs[k][0], SousTitre = defs[k][1], Icone = defs[k][2], Compacte = petite, Left = gauches[k], Top = 64, Width = petite ? 56 : 176, Height = 56, Visible = k != 0 && k != 5 && k != 6,
        Couleur = new[] { Th.Ferme, Th.Autoclick, Th.Violet, Th.Violet, Th.Peche, Th.Ferme, Th.Ferme, Th.Ferme, Th.Minage }[k] };
      if (petite) bulles.SetToolTip(t, defs[k][0]);
      t.Click += (s, e) => { if (t.Enabled) Montrer(idx); };
      tuiles.Add(t); Controls.Add(t);
    }

    // ---------- pages de reglages ----------
    // Chaque page n'affiche qu'un groupe de reglages a la fois (sous-onglets en haut) : moins charge.
    pageCanne = Page("Réglages de la canne à sucre");
    var sc = Sections(pageCanne, "Départ", "Vente", "Avancé", "Sécurité");
    Securite(sc[3], out cnStopTP, out cnTPBlocs);
    int y = 8;
    etage = Num(sc[0], "Étage de départ (1 à 12)", ref y, 1, 12, 1, 1);
    tours = Num(sc[0], "Tours (0 = à l'infini)", ref y, 0, 999, 0, 1);
    Separateur(sc[0], "REPRISE", ref y);
    lReprise = new Label { Left = 24, Top = y, Width = 400, Height = 44, ForeColor = Th.Discret, BackColor = Th.Carte, Text = "Aucun arrêt enregistré." };
    sc[0].Controls.Add(lReprise); y += 50;
    bReprise = new BoutonRond { Left = 24, Top = y, Width = 400, Height = 42, Font = new Font("Segoe UI Semibold", 10f), Visible = false };
    bReprise.Click += (s, e) => { if (bReprise.Enabled && reprise > 0) etage.Value = reprise; };
    sc[0].Controls.Add(bReprise);
    etage.ValueChanged += (s, e) => MajReprise();
    y = 8;
    venteActive = Case(sc[1], "Vente automatique au dial", ref y, true);
    seuil = Num(sc[1], "Cannes avant la vente", ref y, 64, 2304, 2176, 64);
    venteMs = Num(sc[1], "Temps sur le slot de vente (ms)", ref y, 50, 500, 100, 10);
    Aide(sc[1], "Le dial doit être au slot 1. Le script vend quand le compteur d'objets (en bas à droite) atteint ce nombre, puis vérifie qu'il est retombé.", ref y);
    voteSlots = Num(sc[1], "Vote Party", ref y, 0, 9, 2, 1);
    Aide(sc[1], "Quand le VoteParty (en haut de l'écran) repart de zéro, ses objets prennent ce nombre de slots : la vente se fait alors à 64 cannes de moins par slot, une fois par session. 0 = ignorer.", ref y);
    voteSlots.ValueChanged += (s, e) => Sauver();
    venteActive.CheckedChanged += (s, e) => { seuil.Enabled = venteMs.Enabled = voteSlots.Enabled = venteActive.Checked; };
    seuil.ValueChanged += (s, e) => Multiple64(seuil);
    y = 8;
    pas = Liste(sc[2], "Pas entre deux traversées", ref y, new[] { "2", "2,5", "3" });
    marge = Num(sc[2], "Marge avant l'échelle (blocs)", ref y, 0, 10, 4, 1);
    regard = Case(sc[2], "Recaler le regard avec F3", ref y, true);
    sonsActive = Case(sc[2], "Sons de fin d'étage et de tour", ref y, true);
    sonsActive.CheckedChanged += (s, e) => Sauver();
    // anti-lag : en fin de tour, /spawn puis /is go (les objets au sol disparaissent), puis /home canne
    Separateur(sc[2], "ANTI-LAG", ref y);
    antiLag = Case(sc[2], "Anti-lag en fin de tour", ref y, false);
    antiLagS = Num(sc[2], "Attente au spawn (s)", ref y, 10, 600, 60, 10);
    Aide(sc[2], "Après le 12e étage : /spawn, attente, /is go, puis /home canne pour reprendre. Les objets laissés au sol disparaissent pendant ce temps, ce qui évite la chute de FPS.", ref y);
    antiLag.CheckedChanged += (s, e) => { antiLagS.Enabled = antiLag.Checked && !EnCours(); Sauver(); };
    antiLagS.ValueChanged += (s, e) => Sauver();
    antiLagS.Enabled = false;

    pageClic = Page("Réglages de l'autoclick");
    var sm = Sections(pageClic, "Clics", "Vente", "Sécurité");
    int yc = 8;
    acBouton = Liste(sm[0], "Bouton", ref yc, new[] { "Gauche", "Droit" });
    acMode = Liste(sm[0], "Mode", ref yc, new[] { "Clics", "Maintenu" });
    acIntervalle = Num(sm[0], "Intervalle entre deux clics (ms)", ref yc, 20, 10000, 100, 10);
    acCps = new Label { Left = 24, Top = yc - 12, Width = 400, ForeColor = Th.Accent, Font = new Font("Segoe UI", 8.75f), BackColor = Th.Carte, Tag = "accent-texte" }; sm[0].Controls.Add(acCps); yc += 12;
    acDuree = Num(sm[0], "Durée max (min, 0 = sans limite)", ref yc, 0, 1440, 0, 5);
    acClicsMax = Num(sm[0], "Clics max (0 = sans limite)", ref yc, 0, 10000000, 0, 100);
    yc = 8;
    acVente = Case(sm[1], "Vente automatique au dial (slot 1)", ref yc, false);
    acSeuil = Num(sm[1], "Objets avant la vente", ref yc, 64, 2304, 2176, 64);
    acVenteMs = Num(sm[1], "Temps avant retour au slot (ms)", ref yc, 50, 500, 100, 10);
    acSlot = Num(sm[1], "Slot repris après la vente", ref yc, 2, 9, 2, 1);
    acVoteSlots = Num(sm[1], "Vote Party", ref yc, 0, 9, 2, 1);
    acVoteSlots.ValueChanged += (s, e) => Sauver();
    Bulle(acVoteSlots, "Slots pris par les objets du VoteParty. Quand il repart de zéro, la vente se fait 64 objets plus tôt par slot. 0 = ignorer.");
    yc = 8;
    acStopTP = Case(sm[2], "Arrêt si téléporté", ref yc, false);
    acTPBlocs = Num(sm[2], "Distance comptée comme TP (blocs)", ref yc, 1, 10, 3, 1);
    acTPBlocs.Enabled = false;
    Aide(sm[2], "Le script compare tes coordonnées (en haut à gauche) : si tu bouges de plus que cette distance d'un coup, il s'arrête.", ref yc);
    acSecondPlan = Case(sm[2], "Au second plan (jeu visible sur un autre écran)", ref yc, false);
    acStopTP.CheckedChanged += (s, e) => { acTPBlocs.Enabled = acStopTP.Checked && !EnCours(); };
    acIntervalle.ValueChanged += (s, e) => MajCps(); acMode.SelectedIndexChanged += (s, e) => MajCps(); acVente.CheckedChanged += (s, e) => MajCps();
    acSeuil.ValueChanged += (s, e) => Multiple64(acSeuil);

    pageTheme = Page("Options");
    var so = Sections(pageTheme, "Apparence", "Touches", "Divers");
    int yt = 8;
    thParMode = Case(so[0], "Une couleur par mode (culture, minage, pêche, autoclick)", ref yt, true);
    thParMode.CheckedChanged += (s, e) => { Th.ParMode = thParMode.Checked; if (Th.ParMode) Th.Accent = CouleurMode(dernierMode); AppliquerAccent(); Sauver(); };
    thArc = Case(so[0], "Arc-en-ciel (la couleur change en continu)", ref yt, false);
    thContour = Case(so[0], "Contours arc-en-ciel sur les boutons", ref yt, false);
    thArc.CheckedChanged += (s, e) => { Animer(); Sauver(); };
    thContour.CheckedChanged += (s, e) => { Animer(); Sauver(); };
    Separateur(so[0], "OU UNE SEULE COULEUR", ref yt);
    thCouleurs = new Pastilles { Left = 22, Top = yt, Width = 410, Height = 44, BackColor = Th.Carte };
    thCouleurs.Couleurs.AddRange(Accents.Values);
    thCouleurs.Choisie += (s, k) => ChoixAccent(k);
    so[0].Controls.Add(thCouleurs);
    yt += 56;
    thApercu = new Panel { Left = 24, Top = yt, Width = 400, Height = 6, BackColor = Th.Accent, Tag = "accent" }; so[0].Controls.Add(thApercu);
    yt += 18;
    Aide(so[0], "Choisir une couleur ici désactive les couleurs par mode. Tout est retenu pour la prochaine ouverture.", ref yt);
    yt = 8;
    tPause = Touche(so[1], "Pause / reprise", ref yt, 0x76);
    tArret = Touche(so[1], "Arrêt", ref yt, 0x77);
    tPause.Refus = k => RefusTouche(k, tArret.Vk); tArret.Refus = k => RefusTouche(k, tPause.Vk);
    tPause.Changee += (s, e) => Sauver(); tArret.Changee += (s, e) => Sauver();
    Aide(so[1], "Ces touches marchent dans le jeu : la première démarre puis met en pause, la seconde arrête tout de suite (tout est relâché).", ref yt);
    yt = 8;
    miniActive = Case(so[2], "Mini-fenêtre par-dessus le jeu", ref yt, false);
    miniActive.CheckedChanged += (s, e) => { if (miniActive.Checked && EnCours()) MontrerMini(); else if (!miniActive.Checked) CacherMini(); Sauver(); };
    Aide(so[2], "État, temps, ventes et gains, toujours visibles pendant que le script tourne. Elle ne prend pas la main sur le jeu, et le script voit à travers.", ref yt);
    Separateur(so[2], "VÉRIFICATION AFK", ref yt);
    verifActive = Case(so[2], "Répondre seul (écrit le nombre dans le chat)", ref yt, false);
    verifActive.CheckedChanged += (s, e) => Sauver();
    Separateur(so[2], "TESTER MON ÉCRAN", ref yt);
    bTester = new BoutonRond { Text = "Tester mon écran", Left = 24, Top = yt, Width = 400, Height = 40, Font = new Font("Segoe UI Semibold", 10f) };
    bTester.Click += (s, e) => { if (bTester.Enabled) TesterEcran(); };
    so[2].Controls.Add(bTester); yt += 50;
    Aide(so[2], "Le jeu ouvert et visible, les cannes en main : le script lit les coordonnées, le compteur d'objets, l'argent et le VoteParty, sans toucher au jeu. Le résultat s'affiche dans le journal. Le menu se cache une seconde pendant la lecture.", ref yt);

    pageStats = Page("Statistiques");
    // choix de la categorie : tout, ou une seule (chaque categorie a ses propres totaux et son graphique)
    statsFiltre = new Segments("Global", "Canne", "Pêche", "Autoclick") { Left = 24, Top = 60, Width = 400, Height = 32, BackColor = Th.Carte };
    statsFiltre.SelectedIndexChanged += (s, e) => { graphique.Filtre = new string[] { null, "canne", "peche", "autoclick" }[statsFiltre.SelectedIndex]; graphique.Invalidate(); Sauver(); };
    pageStats.Controls.Add(statsFiltre);
    graphique = new Graphique { Left = 24, Top = 108, Width = 400, Height = 590 };
    pageStats.Controls.Add(graphique);

    pagePeche = Page("Réglages de la pêche");
    var sp = Sections(pagePeche, "Pêche", "Mini-jeu", "Vente", "Sécurité");
    Securite(sp[3], out pcStopTP, out pcTPBlocs);
    int ypv = 8;
    pcVente = Case(sp[2], "Vente automatique au dial", ref ypv, false);
    pcVenteMin = Num(sp[2], "Vendre toutes les (minutes)", ref ypv, 1, 240, 5, 1);
    pcVenteSlot = Num(sp[2], "Slot du dial", ref ypv, 1, 9, 2, 1);
    pcVenteMin.Enabled = pcVenteSlot.Enabled = false;
    pcVente.CheckedChanged += (s, e) => { pcVenteMin.Enabled = pcVenteSlot.Enabled = pcVente.Checked && !EnCours(); Sauver(); };
    pcVenteMin.ValueChanged += (s, e) => Sauver(); pcVenteSlot.ValueChanged += (s, e) => Sauver();
    Aide(sp[2], "Le script vend entre deux lancers, ligne rentrée, jamais pendant le mini-jeu : il prend le dial, fait un clic gauche, puis reprend la canne. Le dial doit être dans un autre slot que la canne.", ref ypv);
    int yp = 8;
    pcSlot = Num(sp[0], "Slot de la canne", ref yp, 1, 9, 1, 1);
    pcAttente = Num(sp[0], "Attente avant de relancer (ms)", ref yp, 300, 5000, 1200, 100);
    pcRelance = Num(sp[0], "Relancer si rien ne mord (s)", ref yp, 20, 300, 120, 10);
    pcMax = Num(sp[0], "Poissons max (0 = sans limite)", ref yp, 0, 100000, 0, 10);
    pcSecondPlan = Case(sp[0], "Au second plan (jeu visible sur un autre écran)", ref yp, false);
    Aide(sp[0], "Dans le jeu : canne en main, ligne pas lancée, puis la touche pause (F7 par défaut). Le script lance la ligne, joue le mini-jeu et relance.", ref yp);
    yp = 8;
    pcAnticip = Num(sp[1], "Anticipation (ms)", ref yp, 0, 500, 50, 10);
    pcTol = Num(sp[1], "Tolérance sur le poisson (px)", ref yp, 0, 60, 10, 2);
    Aide(sp[1], "La zone a de l'inertie : le script freine avant le poisson pour s'y arrêter. Anticipation : le temps que met le clic à agir (50 ms conseillé). Si la zone dépasse souvent le poisson, monte-la un peu.", ref yp);

    pageRecolte = Page("Réglages des pastèques");
    var sr = Sections(pageRecolte, "Ferme", "Sécurité");
    Securite(sr[1], out rcStopTP, out rcTPBlocs);
    int yr = 8;
    rcEtage = Num(sr[0], "Étage de départ (1 ou 2)", ref yr, 1, 2, 1, 1);
    rcRangees = Num(sr[0], "Rangée de départ (1 à 12)", ref yr, 1, 12, 1, 1);
    rcTours = Num(sr[0], "Tours (0 = à l'infini)", ref yr, 0, 999, 0, 1);
    rcRegard = Case(sr[0], "Calibrer le regard à chaque tour", ref yr, true);
    rcRegard.CheckedChanged += (s, e) => Sauver();    Aide(sr[0], "Calibrage : au début de chaque tour, le script ouvre F3 et cale le regard pile sur la direction de l'étage, entre 35 et 40 vers le bas.", ref yr);
    Aide(sr[0], "Dans le jeu : F3 fermé, coordonnées affichées en haut à gauche, au début de la rangée de départ (pastèques : est à l'étage 1, ouest à l'étage 2 ; citrouilles : l'inverse ; rangée impaire : côté petit Z, rangée paire : côté grand Z), hache en main, puis la touche pause (F7 par défaut). Il faut un mur tout le long de chaque couloir.", ref yr);

    // Page Culture : un bouton par ferme, qui ouvre ses reglages. Recliquer sur la tuile Culture revient a ce choix.
    pageCulture = Page("Choisis ta culture");
    var choix = new[] { new KeyValuePair<string, int>("Canne à sucre", 0), new KeyValuePair<string, int>("Pastèque", 5), new KeyValuePair<string, int>("Citrouille", 6) };
    var emojis = new[] { "canne", "pasteque", "citrouille" };
    for (int k = 0; k < choix.Length; k++) {
      int cible = choix[k].Value;
      var b = new BoutonRond { Text = choix[k].Key, Emoji = emojis[k], Left = 24, Top = 70 + k * 82, Width = 400, Height = 68, Font = new Font("Segoe UI Semibold", 12f) };
      b.Click += (s, e) => { if (((Control)s).Enabled) Montrer(cible); };
      boutonsCulture.Add(b); pageCulture.Controls.Add(b);
    }

    // Page Minage : la mine 3x3 (autoclic.ps1 -Mine 1 ou 2).
    pageMine = Page("Mine 3x3");
    var smi = Sections(pageMine, "Mine 3x3", "Sécurité");
    int ymi = 8;
    miMine = Liste(smi[0], "Mine", ref ymi, new[] { "Mine 1", "Mine 2" });
    miMine.SelectedIndexChanged += (s, e) => Sauver();
    Aide(smi[0], "Mine 1 : départ en X -140, vers l'est (regard -90). Mine 2 : départ en X 128, vers l'ouest (regard 90). Regard horizontal (0).", ref ymi);
    Aide(smi[0], "Dans le jeu : F3 fermé, coordonnées affichées en haut à gauche, dans le tunnel (Y -3), pioche 3x3 en main, puis la touche pause (F7 par défaut). Au bout, après la chute, le script attend 20 s puis tape /home mine1 ou /home mine2 : pose ces homes en regardant le tunnel.", ref ymi);
    Securite(smi[1], out miStopTP, out miTPBlocs);

    foreach (var p in new[] { pageCanne, pageClic, pageTheme, pageStats, pagePeche, pageRecolte, pageCulture, pageMine }) Controls.Add(p);

    // ---------- session en direct : la carte principale, avec un halo de la couleur du mode ----------
    var ses = new CarteRonde { Left = 488, Top = 136, Width = 488, Height = 412, Lueur = true, Remplissage = Th.Carte };
    pastille = new Panel { Left = 26, Top = 27, Width = 10, Height = 10, BackColor = Th.Discret };
    var gp = new GraphicsPath(); gp.AddEllipse(0, 0, 10, 10); pastille.Region = new Region(gp);
    ses.Controls.Add(pastille);
    lEtat = new Label { Text = "arrêté", Left = 42, Top = 20, Width = 250, Height = 24, ForeColor = Th.Texte, BackColor = Color.Transparent, Font = new Font("Segoe UI Semibold", 10.5f), AutoEllipsis = true };
    ses.Controls.Add(lEtat);
    lFin = new Label { Text = "", Left = 294, Top = 22, Width = 172, Height = 22, ForeColor = Th.Discret, BackColor = Color.Transparent, Font = new Font("Segoe UI", 9.5f), TextAlign = ContentAlignment.MiddleRight };
    ses.Controls.Add(lFin);
    Label c1;
    lTemps = Stat(ses, "TEMPS", 22, 52, 240, out c1, 30f); lTemps.Font = new Font("Segoe UI Light", 32f); c1.Top = 114;
    lTemps.Top = 48; lTemps.Height = 64;
    lHeure = Stat(ses, "PAR HEURE", 246, 52, 220, out c1, 24f); lHeure.Top = 56; lHeure.Height = 52; c1.Top = 114;
    lHeure.TextAlign = ContentAlignment.MiddleRight; c1.AutoSize = false; c1.Left = 246; c1.Width = 218; c1.TextAlign = ContentAlignment.MiddleRight;
    lHeure.ForeColor = Th.Accent; lHeure.Tag = "accent-texte";
    courbe = new Courbe { Left = 24, Top = 140, Width = 440, Height = 84 };
    ses.Controls.Add(courbe);
    lTour = Stat(ses, "TOUR", 22, 240, 140, out cTour, 17f); lEtage = Stat(ses, "ÉTAGE", 170, 240, 140, out cEtage, 17f); lTraversee = Stat(ses, "TRAVERSÉE", 318, 240, 146, out cTraversee, 17f);
    lVentes = Stat(ses, "VENTES", 22, 300, 444, out cVentes, 13f); lVentes.AutoEllipsis = true;
    lGains = Stat(ses, "GAINS (ARGENT EN HAUT DE L'ÉCRAN)", 22, 356, 444, out cGains, 13f);
    lGains.ForeColor = Th.Accent; lGains.Tag = "accent-texte";
    Controls.Add(ses);

    demarrer = new BoutonRond { Text = "▶   Démarrer", Principal = true, Left = 488, Top = 562, Width = 488, Height = 58, Font = new Font("Segoe UI Semibold", 13.5f) };
    arreter = new BoutonRond { Text = "■   Arrêter", Left = 488, Top = 630, Width = 488, Height = 44, Font = new Font("Segoe UI Semibold", 10.5f), CouleurBord = Color.FromArgb(255, 100, 110), Enabled = false };
    demarrer.Click += (s, e) => { if (demarrer.Enabled) Demarrer(); }; arreter.Click += (s, e) => { if (arreter.Enabled) Arreter(); };
    Controls.Add(demarrer); Controls.Add(arreter);

    // ---------- journal : petit, sous les boutons, avec son bouton Vider ----------
    var cadre = new CarteRonde { Left = 488, Top = 688, Width = 488, Height = 156, Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left };
    cadre.Controls.Add(new Label { Text = "JOURNAL", Left = 20, Top = 14, AutoSize = true, Font = new Font("Segoe UI Semibold", 8f), ForeColor = Th.Discret, BackColor = Th.Carte });
    vider = new BoutonRond { Text = "Vider", Left = 396, Top = 8, Width = 72, Height = 26, Font = new Font("Segoe UI", 8.5f) };
    vider.Click += (s, e) => { journal.Clear(); lignesJournal.Clear(); };
    cadre.Controls.Add(vider);
    copier = new BoutonRond { Text = "Copier", Left = 316, Top = 8, Width = 74, Height = 26, Font = new Font("Segoe UI", 8.5f) };
    copier.Click += (s, e) => CopierJournal();
    cadre.Controls.Add(copier);
    alertes = new BoutonRond { Text = "Alertes", Left = 234, Top = 8, Width = 76, Height = 26, Font = new Font("Segoe UI", 8.5f) };
    alertes.Click += (s, e) => { filtreAlertes = !filtreAlertes; alertes.CouleurBord = filtreAlertes ? Jaune : Color.Empty; alertes.Invalidate(); Reafficher(); };
    cadre.Controls.Add(alertes);
    new ToolTip().SetToolTip(copier, "Copie tout le journal (pour le coller dans un message)");
    new ToolTip().SetToolTip(alertes, "N'afficher que les alertes (lignes rouges et jaunes)");
    journal = new RichTextBox { Left = 20, Top = 40, Width = 450, Height = 106, ReadOnly = true, BorderStyle = BorderStyle.None, BackColor = Th.Carte, ScrollBars = RichTextBoxScrollBars.Vertical,
      ForeColor = Th.Texte, Font = new Font("Consolas", 9f), Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right };
    cadre.Controls.Add(journal);
    Controls.Add(cadre);

    horloge = new Timer { Interval = 1000 };
    horloge.Tick += (s, e) => { AfficherTemps(); AfficherGains(); MajMini(); PointCourbe(); };
    horloge.Start();

    Bulles();
    NettoyerJournaux();
    Charger();
    ChargerHistorique();
    ChargerDeparts();
    MajReprise();
    MajCps();
    Montrer(page);
    AppliquerAccent();
    Etat("arrêté", Th.Discret);
    Ecrire("Règle les options, clique Démarrer, puis dans le jeu : chat fermé, " + NomPause + ".", Th.Accent);
    Ecrire(NomPause + " = pause / reprise, " + NomArret + " ou le bouton Arrêter = arrêt.", Th.Discret);
    FormClosing += (s, e) => { Sauver(); if (proc != null && !proc.HasExited) Arreter(); CacherMini(); if (procTuto != null && !procTuto.HasExited) { procTuto.EnableRaisingEvents = false; try { procTuto.Kill(); } catch { } } };
    HandleCreated += (s, e) => Coins();
    if (!ecranVerifie) MontrerTuto();
  }

  // ------------------------------ Fenetre sans bordure ------------------------------
  [DllImport("user32.dll")] static extern bool ReleaseCapture();
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
  Panel logo; Courbe courbe; int modeAffiche = -1;
  // ombre de Windows et reduction depuis la barre des taches, malgre l'absence de bordure
  protected override CreateParams CreateParams { get { var cp = base.CreateParams; cp.ClassStyle |= 0x20000; cp.Style |= 0x20000; return cp; } }
  // Windows 11 : coins arrondis et fin liseré autour de la fenetre
  void Coins() {
    try { int rond = 2; DwmSetWindowAttribute(Handle, 33, ref rond, 4); int c = Th.Bordure.R | (Th.Bordure.G << 8) | (Th.Bordure.B << 16); DwmSetWindowAttribute(Handle, 34, ref c, 4); } catch { }
  }
  void Glisser(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { ReleaseCapture(); SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero); } }
  protected override void OnMouseDown(MouseEventArgs e) { if (e.Y < 56) Glisser(e); base.OnMouseDown(e); }
  // bords de 6 px : redimensionner ; le reste de la bande du haut : deplacer
  protected override void WndProc(ref Message m) {
    base.WndProc(ref m);
    if (m.Msg != 0x84 || WindowState == FormWindowState.Maximized) return;
    var p = PointToClient(new Point((short)((long)m.LParam & 0xFFFF), (short)(((long)m.LParam >> 16) & 0xFFFF)));
    const int b = 6; bool g = p.X < b, d = p.X >= ClientSize.Width - b, h = p.Y < b, bas = p.Y >= ClientSize.Height - b;
    if (h && g) m.Result = (IntPtr)13; else if (h && d) m.Result = (IntPtr)14; else if (bas && g) m.Result = (IntPtr)16; else if (bas && d) m.Result = (IntPtr)17;
    else if (g) m.Result = (IntPtr)10; else if (d) m.Result = (IntPtr)11; else if (h) m.Result = (IntPtr)12; else if (bas) m.Result = (IntPtr)15;
  }
  // un point par seconde pendant la session : gains depuis le depart
  void PointCourbe() {
    if (!debut.HasValue) return;
    double v = (modePeche || modeClic) && prisesLues > 0 ? GainsPrises() : GainsArgent();
    courbe.Points.Add(v); courbe.Invalidate();
  }
  // Legendes de la carte Session selon le mode (avant le depart aussi : la peche n'a ni tour ni etage)
  void Legendes(int m) {
    bool clic = m == 1, peche = m == 4, recolte = m == 5 || m == 6;
    cTour.Text = peche ? "POISSONS" : clic ? "BOUTON" : "TOUR";
    cEtage.Text = peche ? "RATÉS" : clic ? "MODE" : recolte ? "RANGÉE" : "ÉTAGE";
    cTraversee.Text = peche ? "RÉUSSITE" : clic ? "CLICS" : recolte ? "RANGÉES FAITES" : "TRAVERSÉE";
    cVentes.Text = peche ? "PAR ESPÈCE" : "VENTES";
    cGains.Text = peche ? "GAINS DES PRISES  (ARGENT  ·  XP)" : clic ? "GAINS DE L'AUTOCLICK  (ARGENT  ·  XP)" : "GAINS  (ARGENT EN HAUT DE L'ÉCRAN)";
    // peche : liste des especes en petit sur deux lignes (en gros, elle etait coupee des la 3e espece)
    lVentes.Font = new Font("Segoe UI Semibold", peche ? 9.5f : 13f);
    lVentes.Top = peche ? 316 : 318; lVentes.Height = peche ? 40 : 32;
    modeAffiche = m;
  }
  void ViderSession() {
    foreach (var l in new[] { lTour, lEtage, lTraversee, lVentes, lGains, lHeure, lTemps }) l.Text = "–";
    lTemps.ForeColor = Th.Discret; courbe.Points.Clear(); courbe.Invalidate();
    dureesEtage.Clear(); debutEtage = null; etagePrecedent = 0; pauseDansEtage = false; if (lFin != null) lFin.Text = "";
  }

  // ------------------------------ Construction ------------------------------
  CarteRonde Page(string titre) {
    var p = new CarteRonde { Left = 24, Top = 136, Width = 448, Height = 708, Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left };
    p.Controls.Add(new Label { Text = titre, Left = 22, Top = 18, AutoSize = true, Font = new Font("Segoe UI Semibold", 13f), ForeColor = Th.Texte, BackColor = Th.Carte });
    return p;
  }
  // Sous-onglets d'une page : une pastille par groupe, un panneau par groupe (un seul visible).
  Panel[] Sections(CarteRonde page, params string[] noms) {
    var onglets = new Segments(noms) { Left = 24, Top = 60, Width = 400, Height = 32, BackColor = Th.Carte };
    var panneaux = new Panel[noms.Length];
    for (int k = 0; k < noms.Length; k++) {
      panneaux[k] = new Panel { Left = 3, Top = 108, Width = page.Width - 6, Height = page.Height - 132, BackColor = Th.Carte, Visible = k == 0 };   // sans cacher le bord arrondi de la carte
      page.Controls.Add(panneaux[k]);
    }
    onglets.SelectedIndexChanged += (s, e) => { for (int k = 0; k < panneaux.Length; k++) panneaux[k].Visible = k == onglets.SelectedIndex; };
    page.Controls.Add(onglets);
    return panneaux;
  }
  // Onglet Securite d'un mode : le script s'arrete si le joueur est teleporte (securite.ps1).
  void Securite(Panel p, out Interrupteur stop, out Nombre blocs) {
    int y = 8;
    var s = Case(p, "Arrêt si téléporté", ref y, false);
    var b = Num(p, "Distance comptée comme TP (blocs)", ref y, 1, 10, 3, 1);
    b.Enabled = false;
    s.CheckedChanged += (o, e) => { b.Enabled = s.Checked && !EnCours(); Sauver(); };
    b.ValueChanged += (o, e) => Sauver();
    Aide(p, "Le script compare tes coordonnées (en haut à gauche) : si ta position saute d'un coup de cette distance en plus de ce qu'on parcourt à pied, il s'arrête. Les /home et /spawn lancés par le script ne comptent pas.", ref y);
    stop = s; blocs = b;
  }
  // texte d'explication gris, sous les reglages
  void Aide(Control parent, string texte, ref int y) {
    var l = new Label { Text = texte, Left = 24, Top = y + 2, Width = 400, ForeColor = Th.Discret, BackColor = Th.Carte, Font = new Font("Segoe UI", 9f) };
    l.Height = TextRenderer.MeasureText(texte, l.Font, new Size(400, 0), TextFormatFlags.WordBreak).Height + 6;
    parent.Controls.Add(l); y += l.Height + 12;
  }
  // legende en petites capitales grises, valeur en dessous (dans la carte Session : fond transparent pour son halo)
  Label Stat(Control parent, string titre, int x, int y, int largeur, out Label legende, float taille) {
    legende = new Label { Text = titre, Left = x + 2, Top = y, AutoSize = true, ForeColor = Th.Discret, BackColor = Color.Transparent, Font = new Font("Segoe UI Semibold", 8f) };
    var v = new Label { Text = "–", Left = x, Top = y + 18, Width = largeur, Height = (int)(taille * 2), ForeColor = Th.Texte, BackColor = Color.Transparent, Font = new Font("Segoe UI Semibold", taille) };
    parent.Controls.Add(legende); parent.Controls.Add(v);
    return v;
  }
  void Separateur(Control parent, string texte, ref int y) {
    y += 8;
    var l = new Label { Text = texte, Left = 24, Top = y, AutoSize = true, Font = new Font("Segoe UI Semibold", 8f), ForeColor = Th.Accent, BackColor = Th.Carte, Tag = "accent-texte" };
    parent.Controls.Add(l);
    parent.Controls.Add(new Panel { Left = 24, Top = y + 20, Width = 400, Height = 1, BackColor = Th.Bordure });
    y += 32;
  }
  // ------------------------------ Bulles d'aide ------------------------------
  // Au survol d'un reglage (son nom ou sa case) : une phrase qui explique ce qu'il fait.
  ToolTip bulles = new ToolTip { AutoPopDelay = 20000, InitialDelay = 400, ReshowDelay = 100 };
  Dictionary<Control, Label> libelles = new Dictionary<Control, Label>();   // reglage -> son nom a gauche
  void Bulle(Control c, string texte) {
    // le ToolTip de Windows ne coupe pas les lignes : retour a la ligne vers 60 caracteres
    var sb = new StringBuilder(); int n = 0;
    foreach (var mot in texte.Split(' ')) {
      if (n > 0 && n + mot.Length > 60) { sb.Append('\n'); n = 0; } else if (n > 0) { sb.Append(' '); n++; }
      sb.Append(mot); n += mot.Length;
    }
    string t = sb.ToString();
    var pile = new Stack<Control>(); pile.Push(c);
    while (pile.Count > 0) { var x = pile.Pop(); bulles.SetToolTip(x, t); foreach (Control e in x.Controls) pile.Push(e); }
    Label l; if (libelles.TryGetValue(c, out l)) bulles.SetToolTip(l, t);
  }
  Label Libelle(Control parent, string texte, int y, int largeur) {
    var l = new Label { Text = texte, Left = 24, Top = y + 8, Width = largeur, ForeColor = Th.Texte, BackColor = Th.Carte };
    parent.Controls.Add(l); return l;
  }
  Nombre Num(Control parent, string texte, ref int y, int min, int max, int val, int pasNum) {
    var l = Libelle(parent, texte, y, 260);
    var n = new Nombre { Left = 288, Top = y, Width = 136, Height = 34, Minimum = min, Maximum = max, Increment = pasNum };
    n.Value = val; libelles[n] = l;
    parent.Controls.Add(n); y += 46; return n;
  }
  Interrupteur Case(Control parent, string texte, ref int y, bool val) {
    var c = new Interrupteur { Text = texte, Left = 24, Top = y, Width = 400, Height = 34 };
    c.Checked = val;
    parent.Controls.Add(c); y += 46; return c;
  }
  Segments Liste(Control parent, string texte, ref int y, string[] choix) {
    var nom = Libelle(parent, texte, y, 200);
    var l = new Segments(choix) { Left = 228, Top = y, Width = 196, Height = 34 };
    libelles[l] = nom;
    parent.Controls.Add(l); y += 46; return l;
  }
  ChoixTouche Touche(Control parent, string texte, ref int y, int vk) {
    var nom = Libelle(parent, texte, y, 200);
    var t = new ChoixTouche { Left = 228, Top = y, Width = 196, Height = 34, Vk = vk };
    libelles[t] = nom;
    parent.Controls.Add(t); y += 46; return t;
  }
  void Bulles() {
    Bulle(etage, "Étage où commence la récolte. Après un arrêt, le bouton de reprise le remplit tout seul.");
    Bulle(tours, "Nombre de tours complets avant l'arrêt. À 0, la ferme tourne jusqu'à ce que tu l'arrêtes.");
    Bulle(venteActive, "Vend les cannes avec le dial (slot 1) quand l'inventaire est presque plein.");
    Bulle(seuil, "Nombre de cannes (compteur en bas à droite) à partir duquel le script vend. 2176 = 34 slots pleins.");
    Bulle(venteMs, "Temps pendant lequel le dial reste en main. Plus long = plus d'utilisations du dial consommées.");
    Bulle(voteSlots, "Slots pris par les objets du VoteParty. Quand il repart de zéro, la vente se fait 64 cannes plus tôt par slot. 0 = ignorer.");
    Bulle(pas, "Écart, en blocs, entre deux traversées d'un même étage.");
    Bulle(marge, "Sur la dernière traversée, le clic est relâché à ce nombre de blocs du mur, pour ne pas casser l'échelle.");
    Bulle(regard, "Remet le regard bien droit avec F3 au début de chaque étage.");
    Bulle(sonsActive, "Bip à la fin de chaque étage et de chaque tour. Les alarmes sonnent toujours.");
    Bulle(antiLag, "Après le 12e étage : /spawn, attente, /is go puis /home canne. Les objets au sol disparaissent et les FPS remontent.");
    Bulle(antiLagS, "Temps passé au spawn, en plus des 3 s du téléport.");
    Bulle(acBouton, "Bouton de la souris utilisé pour miner.");
    Bulle(acMode, "Clics : clics répétés. Maintenu : bouton enfoncé en continu.");
    Bulle(acIntervalle, "Temps entre deux clics, en mode Clics.");
    Bulle(acDuree, "L'autoclick s'arrête seul après ce temps. 0 = sans limite.");
    Bulle(acClicsMax, "L'autoclick s'arrête seul après ce nombre de clics. 0 = sans limite.");
    Bulle(acVente, "Vend avec le dial (slot 1) quand le compteur atteint le seuil.");
    Bulle(acSeuil, "Nombre d'objets (compteur en bas à droite) à partir duquel le script vend.");
    Bulle(acVenteMs, "Temps pendant lequel le dial reste en main avant de reprendre l'outil.");
    Bulle(acSlot, "Slot de l'outil repris après la vente.");
    Bulle(acStopTP, "Arrête l'autoclick si ta position saute d'un coup (téléportation par quelqu'un d'autre, par exemple).");
    Bulle(acTPBlocs, "Saut de position, en blocs, compté comme une téléportation.");
    Bulle(acSecondPlan, "Le jeu peut rester visible sur un autre écran sans être au premier plan : les commandes sont envoyées à sa fenêtre.");
    Bulle(pcSecondPlan, "Le jeu peut rester visible sur un autre écran sans être au premier plan : les commandes sont envoyées à sa fenêtre.");
    Bulle(thParMode, "Une couleur d'accent par mode : vert pour la ferme, orange pour le minage, bleu pour la pêche, rose pour l'autoclick.");
    Bulle(thArc, "La couleur d'accent fait le tour des couleurs en continu.");
    Bulle(thContour, "Fin contour arc-en-ciel animé sur les boutons et les onglets.");
    Bulle(tPause, "Touche pour mettre en pause et reprendre, depuis le jeu.");
    Bulle(tArret, "Touche pour arrêter le script, depuis le jeu.");
    Bulle(miniActive, "Petite fenêtre par-dessus le jeu qui montre où en est la session.");
    Bulle(verifActive, "Quand la vérification AFK apparaît, le script écrit seul le nombre demandé dans le chat.");
    Bulle(pcSlot, "Slot de la barre où se trouve la canne à pêche.");
    Bulle(pcAttente, "Pause entre une prise et le lancer suivant.");
    Bulle(pcRelance, "Si rien ne mord pendant ce temps, la ligne est relancée.");
    Bulle(pcMax, "La pêche s'arrête seule après ce nombre de poissons. 0 = sans limite.");
    Bulle(pcAnticip, "Temps que met un clic à agir dans le mini-jeu : le script freine d'autant avant le poisson.");
    Bulle(pcTol, "Marge autour du poisson dans laquelle la zone compte comme posée dessus.");
  }
  // ------------------------------ Couleurs vivantes ------------------------------
  Interrupteur thParMode, thArc, thContour; int dernierMode;
  // Deux options separees, une seule horloge a 25 images par seconde :
  //  - arc-en-ciel : la couleur d'accent fait le tour des teintes (un tour en ~18 s ; tout le menu est redessine) ;
  //  - contours arc-en-ciel : trait fin des boutons et onglets qui tourne (seuls ces controles sont redessines : leger).
  // Menu reduit : rien n'est redessine (pas de calcul pour rien pendant que le jeu tourne).
  Timer arc; double teinte; Color avantArc; bool accentArc;   // avantArc : la couleur d'avant, remise a l'arret et enregistree
  List<Control> animes;
  void Animer() {
    if (thArc == null || thContour == null) return;
    bool fond = thArc.Checked, contours = thContour.Checked;
    if (arc == null) { arc = new Timer { Interval = 40 }; arc.Tick += (s, e) => ImageArc(); }
    if (fond && !accentArc) { avantArc = Th.Accent; teinte = 0; }
    accentArc = fond;
    if (!fond && Th.Accent.ToArgb() != avantArc.ToArgb() && avantArc.A > 0) { Th.Accent = Th.ParMode ? CouleurMode(EnCours() ? mode : dernierMode) : avantArc; AppliquerAccent(); avantArc = Color.Empty; }
    Th.Arc = contours;
    if (fond || contours) arc.Start(); else arc.Stop();
    Invalidate(true);
  }
  void ImageArc() {
    if (WindowState == FormWindowState.Minimized) return;
    Th.Phase = (Th.Phase + 3) % 360;                                       // contours : un tour en ~5 s
    if (accentArc) { teinte = (teinte + 0.8) % 360; Th.Accent = Th.Teinte(teinte); AppliquerAccent(); return; }
    if (animes == null) { animes = new List<Control>(); Trouver(this, animes); }
    foreach (var c in animes) if (c.Visible) c.Invalidate();
  }
  static void Trouver(Control parent, List<Control> res) { foreach (Control c in parent.Controls) { if (c is BoutonRond || c is Tuile) res.Add(c); Trouver(c, res); } }
  Color AccentRetenu { get { return accentArc ? avantArc : Th.Accent; } }
  static Color CouleurMode(int m) { return m == 1 ? Th.Autoclick : m == 8 ? Th.Minage : m == 4 ? Th.Peche : Th.Ferme; }
  // fond : degrade violet -> bleu nuit, avec un halo de la couleur du mode en haut a droite
  protected override void OnPaintBackground(PaintEventArgs e) {
    var g = e.Graphics; var r = ClientRectangle; if (r.Width <= 0 || r.Height <= 0) return;
    using (var b = new LinearGradientBrush(r, Th.FondHaut, Th.FondBas, 60f)) g.FillRectangle(b, r);
    using (var p = new GraphicsPath()) {
      p.AddEllipse(r.Width - 520, -360, 900, 640);
      using (var b = new PathGradientBrush(p) { CenterColor = Color.FromArgb(70, Th.Accent), SurroundColors = new[] { Color.FromArgb(0, Th.Accent) } }) g.FillPath(b, p);
    }
    using (var p = new GraphicsPath()) {
      p.AddEllipse(-300, r.Height - 300, 700, 520);
      using (var b = new PathGradientBrush(p) { CenterColor = Color.FromArgb(40, Th.Violet), SurroundColors = new[] { Color.FromArgb(0, Th.Violet) } }) g.FillPath(b, p);
    }
  }
  // Touches deja utilisees par les scripts (deplacements, chat, slots, F3) ou par l'autre reglage.
  static string RefusTouche(int vk, int autre) {
    var k = (Keys)vk;
    if (vk == autre) return "Cette touche sert deja a l'autre reglage.";
    if (k == Keys.Z || k == Keys.Q || k == Keys.S || k == Keys.D || k == Keys.T || k == Keys.F3 || k == Keys.Enter || (k >= Keys.D0 && k <= Keys.D9))
      return "Le script se sert deja de " + ChoixTouche.Nom(vk) + " (deplacements, chat, slots ou F3). Choisis une autre touche.";
    if (k == Keys.ShiftKey || k == Keys.ControlKey || k == Keys.Menu || k == Keys.LWin || k == Keys.RWin) return "Choisis une touche simple (F6 a F12, Pause, Inser...).";
    return null;
  }

  void Montrer(int i) {
    page = i;
    pageCanne.Visible = i == 0; pageClic.Visible = i == 1; pageTheme.Visible = i == 2; pageStats.Visible = i == 3; pagePeche.Visible = i == 4; pageRecolte.Visible = i == 5 || i == 6; pageCulture.Visible = i == 7; pageMine.Visible = i == 8;
    if (i == 5 || i == 6) pageRecolte.Controls[0].Text = i == 6 ? "Réglages des citrouilles" : "Réglages des pastèques";   // meme page, le titre change
    bool culture = i == 0 || i == 5 || i == 6 || i == 7;                   // la tuile Culture reste allumee sur les pages des fermes
    for (int k = 0; k < tuiles.Count; k++) { tuiles[k].Choisie = k == 7 ? culture : k == i; tuiles[k].Invalidate(); }
    // une couleur par mode : tout le menu prend celle du mode choisi (Options et Statistiques gardent la derniere)
    if (i == 0 || i == 1 || i == 4 || i == 5 || i == 6 || i == 8) dernierMode = i;
    if (Th.ParMode && !(thArc != null && thArc.Checked)) { var c = CouleurMode(EnCours() ? mode : dernierMode); if (c.ToArgb() != Th.Accent.ToArgb()) { Th.Accent = c; AppliquerAccent(); } }
    // autre mode choisi, rien ne tourne : la carte Session prend ses legendes (valeurs de l'ancien mode effacees)
    if ((i == 0 || i == 1 || i == 4 || i == 5 || i == 6 || i == 8) && i != modeAffiche && !EnCours()) { Legendes(i); ViderSession(); }
  }
  void Multiple64(Nombre n) { decimal v = Math.Max(64m, Math.Min(2304m, Math.Round(n.Value / 64m) * 64m)); if (v != n.Value) n.Value = v; }
  void MajCps() {
    bool clics = acMode.SelectedIndex == 0;
    acIntervalle.Enabled = clics && !EnCours();
    acCps.Text = clics ? string.Format("soit {0:0.##} clics par seconde", 1000.0 / (double)acIntervalle.Value) : "bouton tenu en continu";
    acSeuil.Enabled = acVenteMs.Enabled = acSlot.Enabled = acVoteSlots.Enabled = acVente.Checked && !EnCours();
  }
  bool EnCours() { return proc != null && !proc.HasExited; }

  // Tester mon ecran : canne-etage.ps1 -Tester 1 lit tout une fois (aucune touche, aucun clic) et ecrit "Test ... : OK / ECHEC".
  // Le menu devient transparent pendant la lecture, pour ne pas cacher le jeu s'il est sur le meme ecran.
  BoutonRond bTester; Process procTest;
  void TesterEcran() {
    if (EnCours()) { Ecrire("Arrête d'abord le script pour tester l'écran.", Jaune); return; }
    if (procTest != null && !procTest.HasExited) return;
    bTester.Enabled = false;
    Ecrire("Test de l'écran...", Th.Texte);
    var psi = new ProcessStartInfo("powershell.exe", string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Tester 1", Script)) {
      UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
      StandardOutputEncoding = Encoding.GetEncoding(850), StandardErrorEncoding = Encoding.GetEncoding(850), WorkingDirectory = dossier };
    procTest = new Process { StartInfo = psi, EnableRaisingEvents = true };
    procTest.OutputDataReceived += (s, e) => { if (e.Data != null) BeginInvoke((Action)(() => LigneTest(e.Data, false))); };
    procTest.ErrorDataReceived += (s, e) => { if (e.Data != null) BeginInvoke((Action)(() => LigneTest(e.Data, true))); };
    procTest.Exited += (s, e) => BeginInvoke((Action)(() => { Opacity = 1; bTester.Enabled = true; }));
    try { procTest.Start(); procTest.BeginOutputReadLine(); procTest.BeginErrorReadLine(); }
    catch (Exception ex) { Ecrire("Test impossible : " + ex.Message, Rouge); bTester.Enabled = true; }
  }
  void LigneTest(string l, bool erreur) {
    if (string.IsNullOrWhiteSpace(l)) return;
    if (l.StartsWith("Test : attente")) { Ecrire("Retourne dans le jeu (60 s maximum) et ferme le menu pause : le test se fait tout seul. Une voix dira « Test terminé » quand tu pourras revenir ici.", Jaune); return; }
    if (l.StartsWith("Test : lecture")) { Opacity = 0; return; }
    if (l.StartsWith("Test termine")) { Opacity = 1; Ecrire("Test terminé.", Th.Texte); return; }
    if (erreur) { Ecrire(l.Trim(), Rouge); return; }
    if (!l.StartsWith("Test ")) return;   // les autres lignes du script (taille de l'interface...) : pas utiles ici
    Ecrire(l.Trim(), l.Contains(": OK") ? Vert : Rouge);
  }

  // ------------------------------ Premier lancement ------------------------------
  // Tant que l'ecran n'a pas ete verifie (ecranVerifie=1 dans le .ini), ce panneau cache tout le menu sauf la barre de titre.
  // canne-etage.ps1 -Tester 2 lit l'ecran en boucle des que le jeu a la main (aucune touche, aucun clic).
  bool ecranVerifie, tutoFini; Panel tuto; Process procTuto; BoutonRond bTuto; Label lTutoAide;
  readonly Panel[] tutoPastilles = new Panel[6]; readonly Label[] tutoEtats = new Label[6]; readonly List<Control> tutoCaches = new List<Control>();
  const string TutoAideDepart = "Quand tu as lu ces étapes, clique sur « Lancer le test » : tu auras 60 secondes pour retourner dans le jeu, menus et chat fermés. Pendant le test, le logiciel ouvre et referme F3 et bouge un peu ta vue : ne touche à rien. Il ne clique pas et n'écrit rien dans le chat. À la fin, une voix dira « Test terminé » : reviens alors ici.";
  const string TutoAideEnCours = "Test lancé : retourne dans le jeu, menus et chat fermés. Tu as 60 secondes. Ne touche pas à la souris quand F3 s'ouvre. À la fin, une voix dira « Test terminé » : reviens alors ici.";

  void MontrerTuto() {
    tuto = new Panel { Left = 0, Top = 56, Width = ClientSize.Width, Height = ClientSize.Height - 56, BackColor = Th.Fond, Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right };
    var centre = new Panel { Left = 100, Top = 16, Width = 800, Height = 730, BackColor = Th.Fond, Anchor = AnchorStyles.None };
    centre.Controls.Add(new Label { Text = "Bienvenue ! On vérifie ton écran", Left = 0, Top = 4, Width = 800, Height = 46, Font = new Font("Segoe UI Semibold", 21f), ForeColor = Th.Texte, BackColor = Th.Fond });
    centre.Controls.Add(new Label { Text = "À faire une seule fois, avant d'utiliser le logiciel. Prépare les trois étapes dans le jeu, puis lance le test : chacune passe au vert quand elle est bonne.", Left = 2, Top = 54, Width = 796, Height = 46, Font = new Font("Segoe UI", 10.5f), ForeColor = Th.Discret, BackColor = Th.Fond });
    var etapes = new[] {
      new[] { "1.  Lance Lunar Client", "Connecte-toi à MinePiece, avec le jeu en fenêtre ou en fenêtre sans bordure (pas en vrai plein écran). Puis clique dans le jeu pour fermer le menu pause." },
      new[] { "2.  Affiche les coordonnées de Lunar", "Active le module de coordonnées de Lunar : X, Y et Z en blanc, dans le coin en haut à gauche. Garde F3 fermé, il les cache." },
      new[] { "3.  Prends un stack d'objets en main", "Active le compteur d'objets de Lunar, en blanc, dans le coin en bas à droite, et tiens un stack : son nombre doit s'afficher." } };
    for (int k = 0; k < 3; k++) {
      var c = new CarteRonde { Left = 0, Top = 106 + k * 106, Width = 800, Height = 98, Remplissage = Th.Carte };
      c.Controls.Add(new Label { Text = etapes[k][0], Left = 50, Top = 10, Width = 440, Height = 32, Font = new Font("Segoe UI Semibold", 13f), ForeColor = Th.Texte, BackColor = Th.Carte });
      LigneEtatTuto(c, k, 16, 12);
      c.Controls.Add(new Label { Text = etapes[k][1], Left = 50, Top = 44, Width = 726, Height = 46, Font = new Font("Segoe UI", 10.5f), ForeColor = Th.Discret, BackColor = Th.Carte });
      centre.Controls.Add(c);
    }
    // Ce que le test essaie tout seul : rien a preparer
    var auto = new CarteRonde { Left = 0, Top = 424, Width = 800, Height = 118, Remplissage = Th.Carte };
    var nomsAuto = new[] { "Tes touches (lues dans les réglages du jeu)", "Lecture de F3", "Mouvement de la souris" };
    for (int k = 0; k < 3; k++) {
      auto.Controls.Add(new Label { Text = nomsAuto[k], Left = 50, Top = 12 + k * 32, Width = 440, Height = 28, Font = new Font("Segoe UI Semibold", 11f), ForeColor = Th.Texte, BackColor = Th.Carte, TextAlign = ContentAlignment.MiddleLeft });
      LigneEtatTuto(auto, 3 + k, 19 + k * 32, 12 + k * 32);
    }
    centre.Controls.Add(auto);
    lTutoAide = new Label { Text = TutoAideDepart, Left = 2, Top = 550, Width = 796, Height = 66, Font = new Font("Segoe UI", 10.5f), ForeColor = Th.Texte, BackColor = Th.Fond };
    centre.Controls.Add(lTutoAide);
    bTuto = new BoutonRond { Text = "Lancer le test", Principal = true, Left = 150, Top = 626, Width = 500, Height = 58, Font = new Font("Segoe UI Semibold", 13.5f) };
    bTuto.Click += (s, e) => { if (!bTuto.Enabled) return; if (tutoFini) FermerTuto(); else LancerTuto(); };
    centre.Controls.Add(bTuto);
    tuto.Controls.Add(centre);
    Controls.Add(tuto); tuto.BringToFront();
    // Le menu est vraiment cache, pas seulement recouvert. Ici seulement : avant l'affichage, Visible vaut toujours false.
    Shown += (s, e) => {
      foreach (Control c in Controls) if (c != tuto && c.Top >= 56 && c.Visible) { c.Visible = false; tutoCaches.Add(c); }
    };
  }
  void LigneEtatTuto(Control parent, int k, int hautPastille, int hautEtat) {
    var p = new Panel { Left = 24, Top = hautPastille, Width = 14, Height = 14, BackColor = Th.Discret };
    var gp = new GraphicsPath(); gp.AddEllipse(0, 0, 14, 14); p.Region = new Region(gp);
    parent.Controls.Add(p); tutoPastilles[k] = p;
    tutoEtats[k] = new Label { Text = "En attente", Left = 490, Top = hautEtat, Width = 286, Height = 28, TextAlign = ContentAlignment.MiddleRight, Font = new Font("Segoe UI Semibold", 11f), ForeColor = Th.Discret, BackColor = Th.Carte, AutoEllipsis = true };
    parent.Controls.Add(tutoEtats[k]);
  }
  void LancerTuto() {
    if (procTuto != null && !procTuto.HasExited) return;
    lTutoAide.Text = TutoAideEnCours; lTutoAide.ForeColor = Th.Texte;
    bTuto.Enabled = false; bTuto.Text = "Test en cours…";
    if (!File.Exists(Script)) { TutoInterrompu("Script introuvable : " + Script); return; }
    var psi = new ProcessStartInfo("powershell.exe", string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Tester 2", Script)) {
      UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
      StandardOutputEncoding = Encoding.GetEncoding(850), StandardErrorEncoding = Encoding.GetEncoding(850), WorkingDirectory = dossier };
    procTuto = new Process { StartInfo = psi, EnableRaisingEvents = true };
    procTuto.OutputDataReceived += (s, e) => { if (e.Data != null) BeginInvoke((Action)(() => LigneTuto(e.Data, false))); };
    procTuto.ErrorDataReceived += (s, e) => { if (e.Data != null) BeginInvoke((Action)(() => LigneTuto(e.Data, true))); };
    procTuto.Exited += (s, e) => BeginInvoke((Action)(() => { if (!tutoFini && tuto != null) TutoInterrompu("Temps écoulé : tout n'est pas bon. Corrige les étapes qui ne sont pas vertes, puis relance le test."); }));
    try { procTuto.Start(); procTuto.BeginOutputReadLine(); procTuto.BeginErrorReadLine(); }
    catch (Exception ex) { TutoInterrompu("Vérification impossible : " + ex.Message); }
  }
  void TutoInterrompu(string raison) {
    lTutoAide.Text = raison; lTutoAide.ForeColor = Rouge;
    bTuto.Text = "Relancer le test"; bTuto.Enabled = true;
  }
  void EtapeTuto(int k, string texte, Color c) { tutoEtats[k].Text = texte; tutoEtats[k].ForeColor = c; tutoPastilles[k].BackColor = c; }
  void LigneTuto(string l, bool erreur) {
    if (tuto == null || string.IsNullOrWhiteSpace(l)) return;
    if (erreur) { lTutoAide.Text = l.Trim(); lTutoAide.ForeColor = Rouge; return; }
    if (l.StartsWith("Tuto fini")) {
      tutoFini = true;
      lTutoAide.Text = "Tout est bon ! Vérifie juste que le nombre lu à l'étape 3 est bien celui de ton stack, puis ouvre le menu.";
      lTutoAide.ForeColor = Vert;
      bTuto.Text = "Ouvrir le menu"; bTuto.Enabled = true;
      return;
    }
    var m = Regex.Match(l, @"^Tuto (jeu|coordonnees|compteur|touches|f3|souris) : (\S+)(?: (.*))?$");
    if (!m.Success) return;
    string etat = m.Groups[2].Value, v = m.Groups[3].Value;
    int k = Array.IndexOf(new[] { "jeu", "coordonnees", "compteur", "touches", "f3", "souris" }, m.Groups[1].Value);
    if (etat == "ATTENTE") { EtapeTuto(k, "En attente du jeu", Th.Discret); return; }
    if (etat == "DEFAUT") { EtapeTuto(k, "Réglages absents : par défaut", Jaune); return; }
    if (etat == "OK") {
      var p = v.Split(' ');
      string lu = k == 0 ? "OK (" + v.Replace(" x ", " × ") + ")"
        : k == 1 && p.Length == 3 ? "X " + p[0] + "   Y " + p[1] + "   Z " + p[2]
        : k == 2 ? "Lu : " + v
        : k == 4 ? "OK (regard " + v + ")" : "OK";
      EtapeTuto(k, lu, Vert);
      return;
    }
    if (k == 0) {
      string t = etat == "ABSENT" ? "Lunar pas lancé" : etat == "AUTRE" ? "Ce n'est pas Lunar Client" : etat == "REDUIT" ? "Fenêtre réduite" : "Clique dans le jeu";
      EtapeTuto(0, t, etat == "ARRIERE" ? Jaune : Rouge);
      return;
    }
    string echec = k == 1 ? "Coordonnées pas trouvées" : k == 2 ? "Compteur pas trouvé" : k == 4 ? "F3 illisible" : k == 5 ? "Clique dans le jeu"
      : "Non gérée : " + v.Replace("forward", "avancer").Replace("back", "reculer").Replace("left", "gauche").Replace("right", "droite");
    EtapeTuto(k, echec, Rouge);
  }
  void FermerTuto() {
    ecranVerifie = true; Sauver();
    Controls.Remove(tuto); tuto.Dispose(); tuto = null;
    foreach (var c in tutoCaches) c.Visible = true;
    tutoCaches.Clear();
    Ecrire("Écran vérifié. Tu peux utiliser le logiciel.", Vert);
  }

  // ------------------------------ Couleur d'accent ------------------------------
  void ChargerAccent() {
    try {
      if (!File.Exists(FichierReglages)) return;
      foreach (var l in File.ReadAllLines(FichierReglages)) {
        if (l.StartsWith("accent=")) Th.Accent = ColorTranslator.FromHtml("#" + l.Substring(7));
        if (l == "parMode=0") Th.ParMode = false;
      }
    } catch { }
  }
  // une couleur choisie a la main remplace les couleurs par mode
  void ChoixAccent(int k) {
    Color c;
    if (k < thCouleurs.Couleurs.Count) c = thCouleurs.Couleurs[k];
    else using (var d = new ColorDialog { Color = Th.Accent, FullOpen = true }) { if (d.ShowDialog(this) != DialogResult.OK) return; c = d.Color; }
    Th.ParMode = false; thParMode.Checked = false; thArc.Checked = false; Th.Accent = c;
    AppliquerAccent(); Sauver();
  }
  void AppliquerAccent() {
    Peindre(this);
    if (chronoLance) AfficherTemps();
    Invalidate(true);
  }
  void Peindre(Control c) {
    foreach (Control e in c.Controls) {
      if ((e.Tag as string) == "accent") e.BackColor = Th.Accent;
      if ((e.Tag as string) == "accent-texte") e.ForeColor = Th.Accent;
      Peindre(e);
    }
  }

  // ------------------------------ Suivi ------------------------------
  void Etat(string texte, Color c) { lEtat.Text = texte; pastille.BackColor = c; MajMini(); }

  // Argent lu par le script ("argent : N" toutes les 30 s). Une lecture tres differente de la
  // precedente (plus de 20 %) n'est prise que si la suivante la confirme : evite une lecture fausse.
  void MajArgent(double v) {
    if (!argentDebut.HasValue) { argentDebut = argentDernier = v; Ecrire("Argent au depart : " + Session.Argent(v), Th.Discret); }
    else {
      double prec = argentDernier.Value;
      if (Math.Abs(v - prec) <= Math.Max(prec * 0.2, 1000)) { argentDernier = v; argentAttente = null; }
      else if (argentAttente.HasValue && Math.Abs(v - argentAttente.Value) <= Math.Max(argentAttente.Value * 0.02, 1000)) { argentDernier = v; argentAttente = null; }
      else { argentAttente = v; return; }
      // Un saut que la ferme ne peut pas faire en 30 s (~20K a 2.2M/h, une vente au dial 3960) : objet vendu ou
      // achat pendant la session. Il est mis de cote pour ne pas fausser les gains et le gain par heure.
      double ecart = v - prec;
      if (ecart > SautHorsFerme || ecart < -SautHorsFerme / 10) {
        argentHors += ecart;
        Ecrire("Argent hors ferme (" + Session.Signe(ecart) + ") : pas compte dans les gains", Th.Discret);
      }
    }
    AfficherGains();
  }
  const double SautHorsFerme = 1000000;
  double GainsArgent() { return argentDebut.HasValue ? argentDernier.Value - argentDebut.Value - argentHors : 0; }
  // Peche et minage : le plus grand de la somme des gains lus a chaque prise (precise mais il en manque :
  // 07/11/2026, 179 prises sur 808 pas lues, +2.48M compte pour +3.97M reels) et de l'argent du haut
  // (complet mais arrondi a 10K : en minage, les prises restent plus grandes).
  double GainsPrises() { return argentDebut.HasValue ? Math.Max(argentPeche, GainsArgent()) : argentPeche; }
  void AfficherGains() {
    double h = Ecoule().TotalHours;
    if ((modePeche || modeClic) && prisesLues > 0) {
      double g = GainsPrises();
      lGains.Text = Session.Signe(g) + "  ·  " + Session.Signe(xpPeche) + " xp";
      lHeure.Text = h >= 1.0 / 60 ? Session.Signe(g / h) + "/h" : "-";
      return;
    }
    if (!argentDebut.HasValue) return;
    double gains = GainsArgent();
    lGains.Text = Session.Signe(gains) + "   (" + Session.Argent(argentDernier.Value) + ")";
    lHeure.Text = h >= 1.0 / 60 ? Session.Signe(gains / h) + "/h" : "-";
  }

  // ------------------------------ Mini-fenetre ------------------------------
  void MontrerMini() {
    if (mini == null || mini.IsDisposed) {
      mini = new MiniFenetre();
      var ecran = Screen.PrimaryScreen.WorkingArea;
      var pos = miniPos ?? new Point(ecran.Left + 20, ecran.Bottom - mini.Height - 200);   // en bas a gauche : loin de ce que le script lit
      if (!SystemInformation.VirtualScreen.Contains(new Rectangle(pos, mini.Size))) pos = new Point(ecran.Left + 20, ecran.Bottom - mini.Height - 200);
      mini.Location = pos;
      mini.Deplacee += (s, e) => { miniPos = mini.Location; Sauver(); };
    }
    MajMini();
    if (!mini.Visible) mini.Show();
  }
  void CacherMini() { if (mini != null && !mini.IsDisposed) { mini.Close(); mini.Dispose(); } mini = null; }
  void MajMini() {
    if (mini == null || mini.IsDisposed) return;
    mini.Etat = lEtat.Text; mini.Pastille = pastille.BackColor; mini.Temps = chronoLance ? lTemps.Text : "0:00:00";
    mini.Ventes = "ventes " + ventes + " / " + essais;
    if ((modePeche || modeClic) && prisesLues > 0) mini.Gains = Session.Signe(GainsPrises()) + "  ·  " + Session.Signe(xpPeche) + " xp";
    else mini.Gains = argentDebut.HasValue ? lHeure.Text + "   " + Session.Signe(GainsArgent()) : "gains : -";
    mini.Maj();
  }

  // ------------------------------ Reprise ------------------------------
  // Le script ecrit "Etage N/12 : depart X .. Y .. Z .., regard vers .." au debut de chaque etage :
  // le menu retient ces departs (departs-etages.txt) pour dire ou se replacer apres un arret.
  void ChargerDeparts() {
    try {
      if (File.Exists(FichierDeparts))
        foreach (var l in File.ReadAllLines(FichierDeparts)) { var p = l.Split(';'); int n; if (p.Length == 2 && int.TryParse(p[0], out n)) departs[n] = p[1]; }
    } catch { }
  }
  void RetenirDepart(int n, string pos) {
    string ancien; if (departs.TryGetValue(n, out ancien) && ancien == pos) return;
    departs[n] = pos;
    try { var lignes = new List<string>(); foreach (var kv in departs) lignes.Add(kv.Key + ";" + kv.Value); lignes.Sort(); File.WriteAllLines(FichierDeparts, lignes.ToArray()); } catch { }
  }
  // Fin de session : etage interrompu -> on y repart ; etage fini -> le suivant (en haut de l'echelle) ; tour fini -> etage 1 (/home canne).
  void CalculerReprise() {
    if (mode != 0 || !chronoLance) return;
    reprise = etageEnCours == 0 ? 1 : (etageFini ? etageEnCours % 12 + 1 : etageEnCours);
    Sauver(); MajReprise();
    Ecrire("Pour reprendre : etage " + reprise + ". " + OuSePlacer(reprise), Th.Accent);
  }
  string OuSePlacer(int n) {
    string regardTxt = n % 2 == 1 ? "est" : "ouest", pos;
    if (n == 1) return "Fais /home canne (départ en 19 107 -80), regard vers l'est.";
    if (departs.TryGetValue(n, out pos)) return "Place-toi en " + pos + ", colle au mur de départ, regard vers l'" + regardTxt + ".";
    return "Départ de cet étage pas encore connu (en haut de l'échelle de l'étage " + (n - 1) + "), regard vers l'" + regardTxt + ".";
  }
  void MajReprise() {
    if (lReprise == null) return;
    if (reprise <= 0) { lReprise.Text = "Aucun arrêt enregistré."; bReprise.Visible = false; return; }
    lReprise.Text = "Dernier arrêt : reprendre à l'étage " + reprise + ".\n" + OuSePlacer(reprise);
    bReprise.Visible = true;
    bool dejaRegle = etage.Value == reprise;
    bReprise.Text = dejaRegle ? "Étage de départ réglé sur " + reprise : "Reprendre à l'étage " + reprise;
    bReprise.Principal = !dejaRegle; bReprise.Enabled = !dejaRegle && !EnCours(); bReprise.Invalidate();
  }

  // ------------------------------ Historique ------------------------------
  void ChargerHistorique() {
    graphique.Sessions.Clear();
    try {
      if (File.Exists(FichierHistorique))
        foreach (var l in File.ReadAllLines(FichierHistorique)) { var s = Session.Lire(l); if (s != null) graphique.Sessions.Add(s); }
    } catch { }
    ChargerVerifs();
  }
  void ChargerVerifs() {
    graphique.Verifs.Clear();
    try {
      string f = Path.Combine(dossier, @"diagnostics\verifications.csv");
      if (File.Exists(f))
        foreach (var l in File.ReadAllLines(f)) { var c = l.Split(';'); if (c.Length >= 5 && c[0] != "date") graphique.Verifs.Add(c); }
    } catch { }
    graphique.Invalidate();
  }
  void EnregistrerSession() {
    int duree = (int)Ecoule().TotalSeconds;
    if (!chronoLance || duree < 30) return;   // session pas vraiment commencee
    var s = new Session { Date = debutSession, DureeS = duree, Mode = mode == 6 ? "citrouille" : modeRecolte ? "recolte" : modePeche ? "peche" : modeClic ? "autoclick" : "canne", Tours = toursFinis, Etages = etagesFinis, Clics = clics,
      Ventes = ventes, Essais = essais, ArgentDebut = argentDebut, ArgentFin = argentDernier, ArgentHors = argentHors };
    if (modeClic) { s.ArgentPrises = argentPeche; s.Xp = xpPeche; }
    // details : etage moyen, ventes du 1er coup, echelles ratees, raison de l'arret
    if (dureesEtage.Count > 0) { double t = 0; foreach (var d in dureesEtage) t += d; s.EtageMoyenS = (int)(t / dureesEtage.Count); }
    s.PremierCoup = premierCoup; s.EchellesRatees = echellesRatees;
    s.Raison = raisonArret ?? (arretMenu ? "arrêt depuis le menu" : (mode == 0 && tours.Value > 0 && toursFinis >= tours.Value) ? "tours terminés" : "arrêt (touche " + NomArret + ")");
    if (modePeche) { s.Clics = poissons; s.Essais = poissons + rates; s.ArgentPrises = argentPeche; s.Xp = xpPeche; foreach (var kv in especes) s.Especes[kv.Key] = kv.Value; foreach (var kv in couleursEsp) s.CouleursEsp[kv.Key] = kv.Value; }   // peche : poissons attrapes / mini-jeux
    try {
      if (!File.Exists(FichierHistorique)) File.WriteAllText(FichierHistorique, Session.Entete + Environment.NewLine);
      File.AppendAllText(FichierHistorique, s.Ligne() + Environment.NewLine);
    } catch (Exception ex) { Ecrire("Historique non enregistre : " + ex.Message, Rouge); }
    graphique.Sessions.Add(s); ChargerVerifs();
    Ecrire(string.Format("Session enregistree : {0}, {1} ventes{2}.", Session.Duree(duree), ventes, s.Gains.HasValue ? ", " + Session.Signe(s.Gains.Value) + (s.ParHeure.HasValue ? " (" + Session.Signe(s.ParHeure.Value) + "/h)" : "") : ""), Th.Accent);
  }
  TimeSpan Ecoule() { return cumul + (debut.HasValue ? DateTime.Now - debut.Value : TimeSpan.Zero); }
  void AfficherTemps() { if (!chronoLance) return; var d = Ecoule(); lTemps.Text = string.Format("{0}:{1:00}:{2:00}", (int)d.TotalHours, d.Minutes, d.Seconds); lTemps.ForeColor = debut.HasValue ? Th.Accent : Th.Discret; }
  void ChronoMarche() { chronoLance = true; if (!debut.HasValue) debut = DateTime.Now; AfficherTemps(); }
  void ChronoFige() { if (debut.HasValue) { cumul += DateTime.Now - debut.Value; debut = null; } AfficherTemps(); }

  // Journal : toutes les lignes sont gardees (heure, texte, couleur) pour le filtre "Alertes" et le bouton Copier.
  BoutonRond copier, alertes; bool filtreAlertes;
  List<Tuple<string, string, Color>> lignesJournal = new List<Tuple<string, string, Color>>();
  bool EstAlerte(Color c) { return c == Rouge || c == Jaune; }
  // Statistiques detaillees de la session en cours (voir EnregistrerSession)
  int premierCoup, essaisDepuis, echellesRatees; string raisonArret; bool arretMenu;
  // Journal enregistre au fil de l'eau : diagnostics\journal-AAAA-MM-JJ.txt (un fichier par jour, gardes 30 jours)
  string FichierJournal { get { return Path.Combine(dossier, @"diagnostics\journal-" + DateTime.Now.ToString("yyyy-MM-dd") + ".txt"); } }
  void EcrireFichierJournal(string texte) {
    try { Directory.CreateDirectory(Path.Combine(dossier, "diagnostics")); File.AppendAllText(FichierJournal, texte + "\r\n", Encoding.UTF8); } catch { }
  }
  void NettoyerJournaux() {   // seulement les fichiers journal-*.txt crees par le menu, de plus de 30 jours
    try {
      foreach (var f in Directory.GetFiles(Path.Combine(dossier, "diagnostics"), "journal-*.txt"))
        if (File.GetLastWriteTime(f) < DateTime.Now.AddDays(-30)) File.Delete(f);
    } catch { }
  }
  void Ecrire(string ligne, Color c) {
    string h = DateTime.Now.ToString("HH:mm:ss");
    EcrireFichierJournal(h + "  " + ligne);
    lignesJournal.Add(Tuple.Create(h, ligne, c));
    if (lignesJournal.Count > 20000) lignesJournal.RemoveRange(0, 1000);
    if (filtreAlertes && !EstAlerte(c)) return;
    Afficher(h, ligne, c);
    journal.ScrollToCaret();
  }
  void Afficher(string h, string ligne, Color c) {
    journal.SelectionStart = journal.TextLength; journal.SelectionLength = 0;
    journal.SelectionColor = Color.FromArgb(90, 90, 100);
    journal.AppendText(h + "  ");
    journal.SelectionColor = c;
    journal.AppendText(ligne + "\n");
  }
  void Reafficher() {
    journal.SuspendLayout(); journal.Clear();
    foreach (var t in lignesJournal) if (!filtreAlertes || EstAlerte(t.Item3)) Afficher(t.Item1, t.Item2, t.Item3);
    journal.ResumeLayout(); journal.ScrollToCaret();
  }
  void CopierJournal() {
    if (lignesJournal.Count == 0) return;
    var sb = new StringBuilder();
    foreach (var t in lignesJournal) sb.Append(t.Item1).Append("  ").Append(t.Item2).Append("\r\n");
    try { Clipboard.SetText(sb.ToString()); } catch { return; }
    copier.Text = "Copié ✓"; copier.Invalidate();
    var t2 = new Timer { Interval = 1500 };
    t2.Tick += (s, e) => { t2.Stop(); t2.Dispose(); copier.Text = "Copier"; copier.Invalidate(); };
    t2.Start();
  }

  // Fin du tour estimee (ferme) : duree moyenne d'un etage (debut d'etage -> debut du suivant, montee comprise),
  // sur les 6 derniers etages sans pause, multipliee par les etages restants.
  Label lFin;
  List<double> dureesEtage = new List<double>(); DateTime? debutEtage; int etagePrecedent; bool pauseDansEtage;
  void NoterEtage(int n) {
    var maintenant = DateTime.Now;
    if (debutEtage.HasValue && n == etagePrecedent + 1 && !pauseDansEtage) dureesEtage.Add((maintenant - debutEtage.Value).TotalSeconds);
    debutEtage = maintenant; etagePrecedent = n; pauseDansEtage = false;
    MajFinTour();
  }
  void MajFinTour() {
    if (mode != 0 || dureesEtage.Count == 0 || !debutEtage.HasValue) { lFin.Text = ""; return; }
    int k = Math.Min(6, dureesEtage.Count); double somme = 0;
    for (int i = dureesEtage.Count - k; i < dureesEtage.Count; i++) somme += dureesEtage[i];
    var fin = debutEtage.Value.AddSeconds(somme / k * (12 - etagePrecedent + 1));
    lFin.Text = "fin du tour vers " + fin.ToString("HH:mm");
  }

  // Redemarrer le menu : relance Ferme-canne.ps1 (comme Lancer.bat : mise a jour, puis menu recompile), puis se ferme.
  // Pas pendant qu'un script tourne : il faut l'arreter d'abord (sinon il perdrait son menu).
  void Relancer() {
    if (EnCours()) { Ecrire("Arrête d'abord le script, puis redémarre le menu.", Jaune); return; }
    string lanceur = Path.Combine(dossier, "Ferme-canne.ps1");
    if (!File.Exists(lanceur)) { Ecrire("Ferme-canne.ps1 introuvable : redémarrage impossible.", Rouge); return; }
    Sauver();
    try { Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + lanceur + "\"") { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = dossier }); }
    catch (Exception ex) { Ecrire("Redémarrage impossible : " + ex.Message, Rouge); return; }
    Close();
  }

  // ------------------------------ Lancement ------------------------------
  void Demarrer() {
    if (EnCours()) return;
    if (page == 4 && pcVente.Checked && pcVenteSlot.Value == pcSlot.Value) { Ecrire("Le dial et la canne sont réglés sur le même slot : change le slot du dial dans l'onglet Vente.", Jaune); return; }
    if (page == 2 || page == 3 || page == 7) { Ecrire("Choisis d'abord une culture, l'Autoclick ou la Pêche avant de démarrer.", Jaune); return; }
    mode = page;
    string scr = modeRecolte ? ScriptRecolte : modePeche ? ScriptPeche : modeClic ? ScriptClic : Script;
    if (!File.Exists(scr)) { Ecrire("Script introuvable : " + scr, Rouge); return; }
    if (File.Exists(FichierArret)) File.Delete(FichierArret);
    Sauver();
    ventes = 0; essais = 0; debut = null; cumul = TimeSpan.Zero; chronoLance = false;
    toursFinis = 0; etagesFinis = 0; clics = 0; etageEnCours = (int)etage.Value; etageFini = false; argentDebut = argentDernier = argentAttente = null; argentHors = 0; debutSession = DateTime.Now;
    premierCoup = 0; essaisDepuis = 0; echellesRatees = 0; raisonArret = null; arretMenu = false;
    EcrireFichierJournal("========== nouvelle session ==========");
    Legendes(mode); ViderSession();
    if (modeClic) { lTour.Text = modeMine || acBouton.SelectedIndex == 0 ? "Gauche" : "Droit"; lEtage.Text = !modeMine && acMode.SelectedIndex == 0 ? "Clics" : "Tenu"; lTraversee.Text = "0"; }
    else if (modePeche) { lTour.Text = "0"; lEtage.Text = "0"; }
    else if (modeRecolte) { lTour.Text = "1"; lEtage.Text = rcRangees.Value + "/12"; lTraversee.Text = "0"; }
    else { lTour.Text = "1"; lEtage.Text = etage.Value + "/12"; }
    poissons = 0; rates = 0; especes.Clear(); couleursEsp.Clear();
    bulleEspeces.SetToolTip(lVentes, null);
    argentPeche = 0; xpPeche = 0; prisesLues = 0;
    string args = modeRecolte
      ? string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -RangeeDepart {1} -Tours {2} -CalerRegard {3} -EtageDepart {4}",
          ScriptRecolte, (int)rcRangees.Value, (int)rcTours.Value, rcRegard.Checked ? 1 : 0, (int)rcEtage.Value)
      : modePeche
      ? string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -AnticipMs {1} -Tolerance {2} -AttenteMs {3} -RelanceS {4} -PoissonsMax {5} -SlotCanne {6}",
          ScriptPeche, (int)pcAnticip.Value, (int)pcTol.Value, (int)pcAttente.Value, (int)pcRelance.Value, (int)pcMax.Value, (int)pcSlot.Value)
      : modeMine
      ? string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Mine {1}", ScriptClic, miMine.SelectedIndex + 1)
      : modeClic
      ? string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Bouton {1} -Mode {2} -IntervalleMs {3} -DureeMaxS {4} -ClicsMax {5} -VenteSeuil {6} -VenteMs {7} -SlotRetour {8}",
          ScriptClic, acBouton.SelectedIndex == 0 ? "gauche" : "droit", acMode.SelectedIndex == 0 ? "clics" : "maintien", (int)acIntervalle.Value,
          (int)acDuree.Value * 60, (int)acClicsMax.Value, acVente.Checked ? (int)acSeuil.Value : 0, (int)acVenteMs.Value, (int)acSlot.Value)
      : string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -EtageDepart {1} -VenteSeuil {2} -VenteMs {3} -Pas {4} -MargeEchelle {5} -RecalerRegard {6} -Tours {7}",
          Script, etage.Value, venteActive.Checked ? (int)seuil.Value : 0, (int)venteMs.Value, new[] { 2, 25, 3 }[pas.SelectedIndex], (int)marge.Value, regard.Checked ? "1" : "0", (int)tours.Value);
    args += string.Format(" -TouchePause {0} -ToucheArret {1} -RepondreVerif {2}", tPause.Vk, tArret.Vk, verifActive.Checked ? 1 : 0);
    if (mode == 6) args += " -Culture citrouille";
    if (mode == 0) args += " -Sons " + (sonsActive.Checked ? 1 : 0);
    if (mode == 0) args += " -VoteSlots " + (int)voteSlots.Value;
    if (mode == 0 && antiLag.Checked) args += " -AntiLag 1 -AntiLagS " + (int)antiLagS.Value;
    if (mode == 1) args += " -StopTP " + (acStopTP.Checked ? 1 : 0) + " -TPBlocs " + (int)acTPBlocs.Value + " -VoteSlots " + (int)acVoteSlots.Value;
    if (modePeche && pcVente.Checked) args += " -VenteMin " + (int)pcVenteMin.Value + " -SlotDial " + (int)pcVenteSlot.Value;
    var stopTP = mode == 0 ? cnStopTP : mode == 4 ? pcStopTP : modeRecolte ? rcStopTP : modeMine ? miStopTP : null;
    var blocsTP = mode == 0 ? cnTPBlocs : mode == 4 ? pcTPBlocs : modeMine ? miTPBlocs : rcTPBlocs;
    if (stopTP != null && stopTP.Checked) args += " -StopTP 1 -TPBlocs " + (int)blocsTP.Value;
    if (mode == 1 || modePeche) args += " -SecondPlan " + ((mode == 1 ? acSecondPlan.Checked : pcSecondPlan.Checked) ? 1 : 0);
    var psi = new ProcessStartInfo("powershell.exe", args) {
      UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
      StandardOutputEncoding = Encoding.GetEncoding(850), StandardErrorEncoding = Encoding.GetEncoding(850), WorkingDirectory = dossier };
    proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
    proc.OutputDataReceived += (s, e) => { if (e.Data != null) BeginInvoke((Action)(() => Ligne(e.Data, false))); };
    proc.ErrorDataReceived += (s, e) => { if (e.Data != null) BeginInvoke((Action)(() => Ligne(e.Data, true))); };
    proc.Exited += (s, e) => BeginInvoke((Action)Fini);
    proc.Start(); proc.BeginOutputReadLine(); proc.BeginErrorReadLine();
    demarrer.Enabled = false; arreter.Enabled = true; ActiverReglages(false);
    Etat("attente de " + NomPause + " dans le jeu", Jaune);
    if (miniActive.Checked) MontrerMini();
    if (modeRecolte) Ecrire(mode == 6 ? "Lancement des citrouilles." : "Lancement des pasteques.", Th.Texte);
    else if (modePeche) Ecrire("Lancement de la peche.", Th.Texte);
    else if (modeMine) Ecrire("Lancement de la mine " + (miMine.SelectedIndex + 1) + ".", Th.Texte);
    else if (modeClic) Ecrire("Lancement de l'autoclick.", Th.Texte);
    else Ecrire(string.Format("Lancement : etage {0}, vente {1}, pas de {2} blocs.", etage.Value, venteActive.Checked ? seuil.Value + " cannes / " + venteMs.Value + " ms" : "desactivee", pas.Text), Th.Texte);
  }

  static readonly Color Vert = Color.FromArgb(70, 210, 110), Rouge = Color.FromArgb(255, 90, 80), Jaune = Color.FromArgb(250, 200, 60), Violet = Color.FromArgb(200, 140, 255);
  void Ligne(string l, bool erreur) {
    if (string.IsNullOrWhiteSpace(l)) return;
    Color c = Color.FromArgb(200, 200, 208);
    Match m;
    if (erreur) c = Rouge;
    else if ((m = Regex.Match(l, @"^argent : (\d+)$")).Success) { MajArgent(double.Parse(m.Groups[1].Value)); MajMini(); return; }   // pas dans le journal (toutes les 30 s)
    else if ((m = Regex.Match(l, @"^clics : (\d+)")).Success) { lTraversee.Text = m.Groups[1].Value; clics = int.Parse(m.Groups[1].Value); c = Th.Discret; }
    else if (l.StartsWith("Autoclick lance") || l.StartsWith("Mine lancee") || l.StartsWith("Peche lancee") || l.StartsWith("Recolte lancee")) { ChronoMarche(); Etat("en cours", Vert); c = Vert; }
    else if ((m = Regex.Match(l, @"^rangee (\d+)/(\d+)")).Success) { lEtage.Text = m.Groups[1].Value + "/" + m.Groups[2].Value; c = Color.FromArgb(110, 110, 122); }
    else if ((m = Regex.Match(l, @"^rangees faites : (\d+)")).Success) { lTraversee.Text = m.Groups[1].Value; return; }
    else if ((m = Regex.Match(l, @"^recolte : tour (\d+) fini")).Success) { toursFinis = int.Parse(m.Groups[1].Value); lTour.Text = (toursFinis + 1).ToString(); c = Vert; }
    else if (l.StartsWith("Recolte arretee")) { raisonArret = l; c = Rouge; }
    else if (l.StartsWith("Regard illisible")) c = Jaune;
    else if ((m = Regex.Match(l, @"poisson (attrape|rate) \((\d+)")).Success) {
      if (m.Groups[1].Value == "attrape") { poissons = int.Parse(m.Groups[2].Value); c = Vert; } else { rates = int.Parse(m.Groups[2].Value); c = Jaune; }
      lTour.Text = poissons.ToString(); lEtage.Text = rates.ToString();
      lTraversee.Text = (100 * poissons / Math.Max(1, poissons + rates)) + " %";
    }
    else if (l.Contains("ligne lancee")) c = Color.FromArgb(110, 110, 122);
    else if (l.Contains("fausse touche")) c = Jaune;
    else if (l.Contains("poisson vanilla : attrape")) {   // compte avec les especes, en gris
      int deja; especes.TryGetValue("Vanilla", out deja); especes["Vanilla"] = deja + 1; couleursEsp["Vanilla"] = Color.FromArgb(170, 170, 170);
      MajEspeces(); c = Color.FromArgb(170, 170, 170);
    }
    else if ((m = Regex.Match(l, @"gain : argent ([\d.]+) xp ([\d.]+)")).Success) {
      var inv = System.Globalization.CultureInfo.InvariantCulture;
      argentPeche += double.Parse(m.Groups[1].Value, inv); xpPeche += double.Parse(m.Groups[2].Value, inv); prisesLues++;
      AfficherGains(); MajMini(); c = Th.Accent;
    }
    else if ((m = Regex.Match(l, @"espece : (.+) x(\d+) #([0-9A-F]{6})")).Success) {
      string nom = m.Groups[1].Value; int deja; especes.TryGetValue(nom, out deja); especes[nom] = deja + int.Parse(m.Groups[2].Value);
      c = ColorTranslator.FromHtml("#" + m.Groups[3].Value); couleursEsp[nom] = c;
      MajEspeces();
    }
    else if ((m = Regex.Match(l, @"^Tour (\d+)( / \d+| \(boucle infinie\))$")).Success) { lTour.Text = m.Groups[1].Value + (tours.Value > 0 ? "/" + tours.Value : "  ∞"); c = Th.Accent; }
    else if ((m = Regex.Match(l, @"Etage (\d+)/12")).Success) {
      lEtage.Text = m.Groups[1].Value + "/12"; c = Th.Accent; ChronoMarche(); Etat("en cours", Vert);
      etageEnCours = int.Parse(m.Groups[1].Value); etageFini = false;
      NoterEtage(etageEnCours);
      var d = Regex.Match(l, @"depart X (-?[\d.]+)\s+Y (-?[\d.]+)\s+Z (-?[\d.]+)");
      if (d.Success) RetenirDepart(etageEnCours, d.Groups[1].Value + " " + d.Groups[2].Value + " " + d.Groups[3].Value);
    }
    else if ((m = Regex.Match(l, @"traversee (\d+)/(\d+)")).Success) { lTraversee.Text = m.Groups[1].Value + "/" + m.Groups[2].Value; c = Color.FromArgb(110, 110, 122); }
    else if (l.Contains("echelle ratee (") || l.StartsWith("Dial vide") || l.StartsWith("Dial toujours vide")) { if (l.Contains("echelle")) echellesRatees++; c = Jaune; }
    else if (l.StartsWith("Dial de nouveau")) c = Vert;
    else if (l.Contains("vente reussie")) { ventes++; if (essaisDepuis == 1) premierCoup++; essaisDepuis = 0; lVentes.Text = ventes + " reussies / " + essais; c = Violet; }
    else if (l.Contains("essai de vente")) { essais++; essaisDepuis++; lVentes.Text = ventes + " reussies / " + essais; c = Color.FromArgb(170, 130, 210); }
    else if (l.StartsWith("PAUSE") || l.Contains("en pause")) { pauseDansEtage = true; ChronoFige(); Etat("pause  -  " + NomPause + " pour reprendre", Jaune); c = Jaune; }
    else if (l.StartsWith("Reprise")) { if (chronoLance) ChronoMarche(); Etat("en cours", Vert); c = Vert; }
    else if (l.Contains("termine") || l.Contains("recale") || l.StartsWith("En haut")) {
      if (Regex.IsMatch(l, @"^Tour \d+ termine")) { toursFinis++; etageEnCours = 0; }
      else if (Regex.IsMatch(l, @"^Etage \d+ termine")) { etagesFinis++; etageFini = true; }
      c = Vert;
    }
    else if (Regex.IsMatch(l, "arret|ARRET|illisible|impossible|Trop|trop longue|incertaine|redescends")) c = Rouge;
    else if (l.StartsWith("Dans le jeu") || l.StartsWith("Reviens") || l.StartsWith("Autoclick :")) c = Th.Accent;
    if (c == Rouge && Regex.IsMatch(l, "arret|ARRET")) raisonArret = l.Trim();   // pour les statistiques : pourquoi la session s'est arretee
    Ecrire(l.Trim(), c);
  }

  void Arreter() {
    if (!EnCours()) return;
    arretMenu = true;
    File.WriteAllText(FichierArret, "arret");
    ChronoFige();
    Ecrire("Arret demande...", Jaune);
    arreter.Enabled = false;
    var t = new Timer { Interval = 5000 };
    t.Tick += (s, e) => {
      t.Stop();
      if (EnCours()) {
        try { proc.Kill(); } catch { }
        RelacherTout();
        Ecrire("Le script ne repondait pas : il a ete coupe, et les touches relachees.", Rouge);
      }
    };
    t.Start();
  }
  void RelacherTout() {
    foreach (byte sc in new byte[] { 0x11, 0x1E, 0x1F, 0x20 }) keybd_event(0, sc, 0x0008 | 0x0002, IntPtr.Zero);
    mouse_event(0x0004, 0, 0, 0, IntPtr.Zero); mouse_event(0x0010, 0, 0, 0, IntPtr.Zero);
  }
  void Fini() {
    if (File.Exists(FichierArret)) { try { File.Delete(FichierArret); } catch { } }
    ChronoFige();
    Etat("arrêté", Th.Discret);
    demarrer.Enabled = true; arreter.Enabled = false; ActiverReglages(true);
    Ecrire("Script termine.", Th.Texte);
    EnregistrerSession();
    CalculerReprise();
    MajReprise();
    CacherMini();
  }
  void ActiverReglages(bool on) {
    foreach (Control c in new Control[] { etage, tours, venteActive, seuil, venteMs, marge, regard, sonsActive, pas, acBouton, acMode, acIntervalle, acDuree, acClicsMax, acVente, acSeuil, acVenteMs, acSlot, acVoteSlots, acStopTP, acTPBlocs, tPause, tArret, verifActive }) c.Enabled = on;
    // pendant que ca tourne : pas de changement de mode, mais Options et Statistiques restent visibles
    // pendant qu'une culture tourne, la tuile Culture reste active pour revoir ses reglages ; les boutons des fermes sont grises
    for (int k = 0; k < tuiles.Count; k++) tuiles[k].Enabled = on || k == mode || k == 2 || k == 3 || (k == 7 && (mode == 0 || mode == 5 || mode == 6));
    foreach (var b in boutonsCulture) b.Enabled = on;
    foreach (Control c in new Control[] { miMine, miStopTP, pcAnticip, pcTol, pcAttente, pcRelance, pcMax, pcSlot, pcSecondPlan, acSecondPlan, cnStopTP, rcStopTP, pcStopTP, pcVente, antiLag, antiLagS, voteSlots, rcEtage, rcRangees, rcTours, rcRegard }) c.Enabled = on;
    if (on) { seuil.Enabled = venteMs.Enabled = voteSlots.Enabled = venteActive.Checked; MajCps(); miTPBlocs.Enabled = miStopTP.Checked; acTPBlocs.Enabled = acStopTP.Checked; cnTPBlocs.Enabled = cnStopTP.Checked; rcTPBlocs.Enabled = rcStopTP.Checked; pcTPBlocs.Enabled = pcStopTP.Checked; pcVenteMin.Enabled = pcVenteSlot.Enabled = pcVente.Checked; antiLagS.Enabled = antiLag.Checked; }
    else miTPBlocs.Enabled = cnTPBlocs.Enabled = rcTPBlocs.Enabled = pcTPBlocs.Enabled = pcVenteMin.Enabled = pcVenteSlot.Enabled = false;
    MajReprise();
  }

  // ------------------------------ Reglages ------------------------------
  bool chargement;
  void Sauver() {
    if (chargement) return;
    try {
      File.WriteAllLines(FichierReglages, new[] {
        "etage=" + etage.Value, "tours=" + tours.Value, "vente=" + (venteActive.Checked ? 1 : 0), "seuil=" + seuil.Value, "venteMs=" + venteMs.Value,
        "marge=" + marge.Value, "regard=" + (regard.Checked ? 1 : 0), "sons=" + (sonsActive.Checked ? 1 : 0), "pas=" + new[] { 0, 2, 1 }[pas.SelectedIndex],
        "antiLag=" + (antiLag.Checked ? 1 : 0), "antiLagS=" + antiLagS.Value, "voteSlots=" + voteSlots.Value,
        "acBouton=" + acBouton.SelectedIndex, "acMode=" + acMode.SelectedIndex, "acIntervalle=" + acIntervalle.Value, "acDuree=" + acDuree.Value,
        "acClicsMax=" + acClicsMax.Value, "acStopTP=" + (acStopTP.Checked ? 1 : 0), "acTPBlocs=" + acTPBlocs.Value, "acVente=" + (acVente.Checked ? 1 : 0), "acSeuil=" + acSeuil.Value, "acVenteMs=" + acVenteMs.Value, "acSlot=" + acSlot.Value, "acVoteSlots=" + acVoteSlots.Value,
        "pcAnticip2=" + pcAnticip.Value, "pcSecondPlan=" + (pcSecondPlan.Checked ? 1 : 0), "acSecondPlan=" + (acSecondPlan.Checked ? 1 : 0), "pcTol2=" + pcTol.Value, "pcAttente=" + pcAttente.Value, "pcRelance=" + pcRelance.Value, "pcMax=" + pcMax.Value, "pcSlot=" + pcSlot.Value,
        "rcRangeeDepart=" + rcRangees.Value, "rcTours=" + rcTours.Value, "rcRegard=" + (rcRegard.Checked ? 1 : 0), "rcEtage=" + rcEtage.Value,
        "miMine=" + miMine.SelectedIndex, "miStopTP=" + (miStopTP.Checked ? 1 : 0), "miTPBlocs=" + miTPBlocs.Value,
        "pcVente=" + (pcVente.Checked ? 1 : 0), "pcVenteMin=" + pcVenteMin.Value, "pcVenteSlot=" + pcVenteSlot.Value,
        "cnStopTP=" + (cnStopTP.Checked ? 1 : 0), "cnTPBlocs=" + cnTPBlocs.Value, "rcStopTP=" + (rcStopTP.Checked ? 1 : 0), "rcTPBlocs=" + rcTPBlocs.Value, "pcStopTP=" + (pcStopTP.Checked ? 1 : 0), "pcTPBlocs=" + pcTPBlocs.Value,
        "ecranVerifie=" + (ecranVerifie ? 1 : 0), "onglet=" + page, "stats=" + statsFiltre.SelectedIndex, "reprise=" + reprise, "pause=" + tPause.Vk, "arret=" + tArret.Vk, "mini=" + (miniActive.Checked ? 1 : 0), "verif=" + (verifActive.Checked ? 1 : 0),
        "miniX=" + (miniPos.HasValue ? miniPos.Value.X : -99999), "miniY=" + (miniPos.HasValue ? miniPos.Value.Y : -99999),
        "parMode=" + (Th.ParMode ? 1 : 0), "arc=" + (thArc.Checked ? 1 : 0), "contour=" + (thContour.Checked ? 1 : 0), "accent=" + string.Format("{0:X2}{1:X2}{2:X2}", AccentRetenu.R, AccentRetenu.G, AccentRetenu.B) });
    } catch { }
  }
  void Charger() {
    if (!File.Exists(FichierReglages)) return;
    chargement = true;
    try {
      var d = new Dictionary<string, int>();
      foreach (var l in File.ReadAllLines(FichierReglages)) {
        var p = l.Split('='); int v; if (p.Length == 2 && int.TryParse(p[1], out v)) d[p[0]] = v;
      }
      int x;
      if (d.TryGetValue("ecranVerifie", out x)) ecranVerifie = x == 1;
      if (d.TryGetValue("miMine", out x)) miMine.SelectedIndex = Math.Max(0, Math.Min(1, x));
      if (d.TryGetValue("miStopTP", out x)) miStopTP.Checked = x == 1;
      if (d.TryGetValue("miTPBlocs", out x)) miTPBlocs.Value = Math.Max(1, Math.Min(10, x));
      if (d.TryGetValue("pcVente", out x)) pcVente.Checked = x == 1;
      if (d.TryGetValue("pcVenteMin", out x)) pcVenteMin.Value = Math.Max(1, Math.Min(240, x));
      if (d.TryGetValue("pcVenteSlot", out x)) pcVenteSlot.Value = Math.Max(1, Math.Min(9, x));
      if (d.TryGetValue("cnStopTP", out x)) cnStopTP.Checked = x == 1;
      if (d.TryGetValue("cnTPBlocs", out x)) cnTPBlocs.Value = Math.Max(1, Math.Min(10, x));
      if (d.TryGetValue("rcStopTP", out x)) rcStopTP.Checked = x == 1;
      if (d.TryGetValue("rcTPBlocs", out x)) rcTPBlocs.Value = Math.Max(1, Math.Min(10, x));
      if (d.TryGetValue("pcStopTP", out x)) pcStopTP.Checked = x == 1;
      if (d.TryGetValue("pcTPBlocs", out x)) pcTPBlocs.Value = Math.Max(1, Math.Min(10, x));
      if (d.TryGetValue("etage", out x)) etage.Value = Math.Max(1, Math.Min(12, x));
      if (d.TryGetValue("tours", out x)) tours.Value = Math.Max(0, Math.Min(999, x));
      if (d.TryGetValue("vente", out x)) venteActive.Checked = x == 1;
      if (d.TryGetValue("seuil", out x)) seuil.Value = Math.Max(64, Math.Min(2304, (int)Math.Round(x / 64.0) * 64));
      if (d.TryGetValue("venteMs", out x)) venteMs.Value = Math.Max(50, Math.Min(500, x));
      if (d.TryGetValue("marge", out x)) marge.Value = Math.Max(0, Math.Min(10, x));
      if (d.TryGetValue("regard", out x)) regard.Checked = x == 1;
      if (d.TryGetValue("sons", out x)) sonsActive.Checked = x == 1;
      if (d.TryGetValue("antiLag", out x)) antiLag.Checked = x == 1;
      if (d.TryGetValue("antiLagS", out x)) antiLagS.Value = Math.Max(10, Math.Min(600, x));
      antiLagS.Enabled = antiLag.Checked;
      if (d.TryGetValue("voteSlots", out x)) voteSlots.Value = Math.Max(0, Math.Min(9, x));
      if (d.TryGetValue("pas", out x)) pas.SelectedIndex = new[] { 0, 2, 1 }[(x >= 0 && x <= 2) ? x : 0];
      if (d.TryGetValue("acBouton", out x)) acBouton.SelectedIndex = x == 1 ? 1 : 0;
      if (d.TryGetValue("acMode", out x)) acMode.SelectedIndex = x == 1 ? 1 : 0;
      if (d.TryGetValue("acIntervalle", out x)) acIntervalle.Value = Math.Max(20, Math.Min(10000, x));
      if (d.TryGetValue("acDuree", out x)) acDuree.Value = Math.Max(0, Math.Min(1440, x));
      if (d.TryGetValue("acClicsMax", out x)) acClicsMax.Value = Math.Max(0, Math.Min(10000000, x));
      if (d.TryGetValue("acVente", out x)) acVente.Checked = x == 1;
      if (d.TryGetValue("acSeuil", out x)) acSeuil.Value = Math.Max(64, Math.Min(2304, (int)Math.Round(x / 64.0) * 64));
      if (d.TryGetValue("acVenteMs", out x)) acVenteMs.Value = Math.Max(50, Math.Min(500, x));
      if (d.TryGetValue("acSlot", out x)) acSlot.Value = Math.Max(2, Math.Min(9, x));
      if (d.TryGetValue("acVoteSlots", out x)) acVoteSlots.Value = Math.Max(0, Math.Min(9, x));
      if (d.TryGetValue("acStopTP", out x)) acStopTP.Checked = x == 1;
      if (d.TryGetValue("acTPBlocs", out x)) acTPBlocs.Value = Math.Max(1, Math.Min(10, x));
      acTPBlocs.Enabled = acStopTP.Checked;
      if (d.TryGetValue("rcRangeeDepart", out x)) rcRangees.Value = Math.Max(1, Math.Min(12, x));
      if (d.TryGetValue("rcTours", out x)) rcTours.Value = Math.Max(0, Math.Min(999, x));
      if (d.TryGetValue("rcRegard", out x)) rcRegard.Checked = x == 1;
      if (d.TryGetValue("rcEtage", out x)) rcEtage.Value = Math.Max(1, Math.Min(2, x));
      if (d.TryGetValue("onglet", out x)) page = (x >= 0 && x <= 8) ? x : 0;
      if (d.TryGetValue("stats", out x) && x >= 0 && x <= 3) statsFiltre.SelectedIndex = x;
      if (d.TryGetValue("pcAnticip2", out x)) pcAnticip.Value = Math.Max(0, Math.Min(500, x));
      if (d.TryGetValue("pcTol2", out x)) pcTol.Value = Math.Max(0, Math.Min(60, x));
      if (d.TryGetValue("pcAttente", out x)) pcAttente.Value = Math.Max(300, Math.Min(5000, x));
      if (d.TryGetValue("pcRelance", out x)) pcRelance.Value = Math.Max(20, Math.Min(300, x));
      if (d.TryGetValue("pcMax", out x)) pcMax.Value = Math.Max(0, Math.Min(100000, x));
      if (d.TryGetValue("pcSlot", out x)) pcSlot.Value = Math.Max(1, Math.Min(9, x));
      if (d.TryGetValue("pcSecondPlan", out x)) pcSecondPlan.Checked = x == 1;
      if (d.TryGetValue("acSecondPlan", out x)) acSecondPlan.Checked = x == 1;
      if (d.TryGetValue("reprise", out x)) reprise = (x >= 1 && x <= 12) ? x : 0;
      if (d.TryGetValue("pause", out x) && x > 0 && x < 256) tPause.Vk = x;
      if (d.TryGetValue("arret", out x) && x > 0 && x < 256 && x != tPause.Vk) tArret.Vk = x;
      if (d.TryGetValue("mini", out x)) miniActive.Checked = x == 1;
      if (d.TryGetValue("verif", out x)) verifActive.Checked = x == 1;
      thParMode.Checked = Th.ParMode;
      if (d.TryGetValue("arc", out x)) thArc.Checked = x == 1;
      if (d.TryGetValue("contour", out x)) thContour.Checked = x == 1;
      int mx, my; if (d.TryGetValue("miniX", out mx) && d.TryGetValue("miniY", out my) && mx != -99999) miniPos = new Point(mx, my);
      seuil.Enabled = venteMs.Enabled = venteActive.Checked;
    } catch { }
    chargement = false;
  }
}
