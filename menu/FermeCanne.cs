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
  public static Color Fond = Color.FromArgb(13, 13, 15);
  public static Color Carte = Color.FromArgb(24, 24, 28);
  public static Color CarteHaute = Color.FromArgb(32, 32, 38);
  public static Color Champ = Color.FromArgb(40, 40, 47);
  public static Color Bordure = Color.FromArgb(48, 48, 56);
  public static Color Texte = Color.FromArgb(240, 240, 244);
  public static Color Discret = Color.FromArgb(140, 140, 152);
  public static Color Accent = Color.FromArgb(255, 138, 0);
  public static GraphicsPath Arrondi(RectangleF r, float rayon) {
    var p = new GraphicsPath(); float d = rayon * 2;
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
    p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
  }
  public static Color Melange(Color a, Color b, float t) { return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t)); }
}

// Carte arrondie : le controle a la couleur du fond, et dessine sa carte par-dessus.
public class CarteRonde : Panel {
  public Color Remplissage = Th.Carte; public bool BordAccent; public float Rayon = 14;
  public CarteRonde() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true); BackColor = Th.Fond; }
  protected override void OnPaint(PaintEventArgs e) {
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    using (var p = Th.Arrondi(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Rayon))
    using (var b = new SolidBrush(Remplissage)) using (var pen = new Pen(BordAccent ? Th.Accent : Th.Bordure, BordAccent ? 2f : 1f)) { e.Graphics.FillPath(b, p); e.Graphics.DrawPath(pen, p); }
  }
}

// Tuile de navigation : icone dessinee + titre + sous-titre ; survol et selection.
public class Tuile : Control {
  public string Titre, SousTitre, Icone; public bool Choisie, Compacte; bool survol;
  public Tuile() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true); BackColor = Th.Fond; Cursor = Cursors.Hand; }
  protected override void OnMouseEnter(EventArgs e) { survol = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { survol = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    var r = new RectangleF(1, 1, Width - 3, Height - 3);
    Color fond = Choisie ? Th.Melange(Th.Carte, Th.Accent, 0.12f) : (survol && Enabled ? Th.CarteHaute : Th.Carte);
    using (var p = Th.Arrondi(r, 16)) using (var b = new SolidBrush(fond)) using (var pen = new Pen(Choisie ? Th.Accent : Th.Bordure, Choisie ? 2f : 1f)) { g.FillPath(b, p); g.DrawPath(pen, p); }
    Color ic = !Enabled ? Th.Bordure : (Choisie ? Th.Accent : (survol ? Th.Texte : Th.Discret));
    // pastille de l'icone
    var rp = Compacte ? new RectangleF((Width - 46) / 2f, (Height - 46) / 2f, 46, 46) : new RectangleF(18, 18, 46, 46);
    using (var p = Th.Arrondi(rp, 12)) using (var b = new SolidBrush(Choisie ? Th.Melange(Th.Carte, Th.Accent, 0.25f) : Th.Champ)) g.FillPath(b, p);
    DessinerIcone(g, Icone, rp, ic);
    if (Compacte) return;
    using (var f = new Font("Segoe UI Semibold", 12.5f)) TextRenderer.DrawText(g, Titre, f, new Rectangle(76, 0, Width - 80, Height), Enabled ? Th.Texte : Th.Discret, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
    if (!string.IsNullOrEmpty(SousTitre)) using (var f = new Font("Segoe UI", 9f)) using (var b = new SolidBrush(Th.Discret)) g.DrawString(SousTitre, f, b, 77, 44);
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
  public BoutonRond() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true); BackColor = Th.Carte; Cursor = Cursors.Hand; }
  protected override void OnMouseEnter(EventArgs e) { survol = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { survol = false; appui = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnMouseDown(MouseEventArgs e) { appui = true; Invalidate(); base.OnMouseDown(e); }
  protected override void OnMouseUp(MouseEventArgs e) { appui = false; Invalidate(); base.OnMouseUp(e); }
  protected override void OnEnabledChanged(EventArgs e) { Cursor = Enabled ? Cursors.Hand : Cursors.Default; Invalidate(); base.OnEnabledChanged(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    var r = new RectangleF(1, 1, Width - 3, Height - 3);
    Color fond, texte, bord;
    if (Principal) {
      fond = !Enabled ? Th.Champ : (appui ? Th.Melange(Th.Accent, Color.Black, 0.2f) : survol ? Th.Melange(Th.Accent, Color.White, 0.18f) : Th.Accent);
      texte = Enabled ? Color.FromArgb(16, 16, 18) : Th.Discret; bord = fond;
    } else {
      fond = !Enabled ? Th.Carte : (survol ? Th.CarteHaute : Th.Champ);
      texte = Enabled ? (CouleurBord.IsEmpty ? Th.Texte : CouleurBord) : Th.Bordure;
      bord = Enabled && !CouleurBord.IsEmpty ? CouleurBord : Th.Bordure;
    }
    using (var p = Th.Arrondi(r, Height / 2.6f)) using (var b = new SolidBrush(fond)) using (var pen = new Pen(bord, 1.2f)) { g.FillPath(b, p); g.DrawPath(pen, p); }
    TextRenderer.DrawText(g, Text, Font, Rectangle.Round(r), texte, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
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
  public double? Gains { get { if (ArgentPrises > 0) return ArgentPrises; return ArgentDebut.HasValue && ArgentFin.HasValue ? ArgentFin - ArgentDebut : null; } }
  public double? ParHeure { get { return Gains.HasValue && DureeS >= 60 ? Gains / (DureeS / 3600.0) : null; } }
  static readonly System.Globalization.CultureInfo Inv = System.Globalization.CultureInfo.InvariantCulture;
  // peche : poissons par espece, avec la couleur du nom dans le chat (sa rarete)
  public Dictionary<string, int> Especes = new Dictionary<string, int>();
  public Dictionary<string, Color> CouleursEsp = new Dictionary<string, Color>();
  public const string Entete = "date;duree_s;mode;tours;etages;clics;ventes;essais;argent_debut;argent_fin;especes;argent_prises;xp";
  public string Ligne() {
    var esp = new List<string>();
    foreach (var kv in Especes) { Color c; CouleursEsp.TryGetValue(kv.Key, out c); esp.Add(string.Format("{0}:{1}:{2:X2}{3:X2}{4:X2}", kv.Key.Replace(";", "").Replace("|", "").Replace(":", ""), kv.Value, c.R, c.G, c.B)); }
    return string.Join(";", new[] { Date.ToString("yyyy-MM-dd HH:mm", Inv), DureeS.ToString(), Mode, Tours.ToString(), Etages.ToString(), Clics.ToString(), Ventes.ToString(), Essais.ToString(),
      ArgentDebut.HasValue ? ArgentDebut.Value.ToString("0", Inv) : "", ArgentFin.HasValue ? ArgentFin.Value.ToString("0", Inv) : "", string.Join("|", esp.ToArray()),
      ArgentPrises.ToString("0.##", Inv), Xp.ToString("0.##", Inv) });
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
  public Graphique() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true); BackColor = Th.Carte; }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    var petit = new Font("Segoe UI Semibold", 8.25f); var gros = new Font("Segoe UI Semibold", 14f); var normal = new Font("Segoe UI", 9f); var mono = new Font("Consolas", 9f);
    var liste = Filtre == null ? Sessions : Sessions.FindAll(x => x.Mode == Filtre);
    try {
      if (liste.Count == 0) {
        TextRenderer.DrawText(g, Filtre == null ? "Aucune session enregistree pour l'instant.\nChaque session (ferme, peche ou minage) s'ajoute ici quand le script s'arrete." : "Aucune session dans cette categorie pour l'instant.", normal, new Rectangle(0, 0, Width, 80), Th.Discret, TextFormatFlags.Left | TextFormatFlags.WordBreak);
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
      TextRenderer.DrawText(g, "GAINS PAR HEURE  (dernieres sessions)", petit, new Point(0, y0), Th.Discret);
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
        TextRenderer.DrawText(g, "POISSONS PAR ESPECE", petit, new Point(0, yl), Th.Discret);
        double xpTotal = 0; foreach (var s in liste) xpTotal += s.Xp;
        if (xpTotal > 0) TextRenderer.DrawText(g, "XP GAGNEE  " + Session.Signe(xpTotal), petit, new Rectangle(0, yl, Width, 16), Th.Accent, TextFormatFlags.Right);
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
        if (xpSeul > 0) { TextRenderer.DrawText(g, "XP GAGNEE  " + Session.Signe(xpSeul), petit, new Point(0, yl), Th.Accent); yl += 26; }
      }
      // dernieres sessions
      TextRenderer.DrawText(g, "DERNIERES SESSIONS", petit, new Point(0, yl), Th.Discret);
      yl += 22;
      for (int i = liste.Count - 1; i >= 0 && yl + 18 <= Height; i--) {
        var s = liste[i];
        string quoi = s.Mode == "autoclick" ? "minage" : s.Mode == "peche" ? "peche" : (s.Tours > 0 ? s.Tours + " tour" + (s.Tours > 1 ? "s" : "") : s.Etages + " etage" + (s.Etages > 1 ? "s" : ""));
        TextRenderer.DrawText(g, string.Format("{0:dd/MM HH:mm}  {1,8}  {2,-10}", s.Date, Session.Duree(s.DureeS), quoi), mono, new Point(0, yl), Th.Texte);
        TextRenderer.DrawText(g, s.Gains.HasValue ? Session.Signe(s.Gains.Value) : "-", mono, new Rectangle(0, yl, Width - 92, 18), s.Gains.HasValue ? Th.Accent : Th.Discret, TextFormatFlags.Right);
        TextRenderer.DrawText(g, s.Mode == "peche" ? s.Clics + " poissons" : s.Ventes + " ventes", mono, new Rectangle(0, yl, Width, 18), Th.Discret, TextFormatFlags.Right);
        yl += 20;
      }
    } finally { petit.Dispose(); gros.Dispose(); normal.Dispose(); mono.Dispose(); }
  }
}

// Mini-fenetre toujours au premier plan : etat, temps, ventes, gains par heure.
// Elle ne prend jamais le focus (sinon le jeu passerait au second plan et le script se mettrait en pause).
public class MiniFenetre : Form {
  public string Etat = "arrete", Temps = "-", Ventes = "-", Gains = "-"; public Color Pastille = Th.Discret;
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
    using (var p = Th.Arrondi(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 14)) using (var b = new SolidBrush(Th.Carte)) using (var pen = new Pen(Th.Accent, 1.5f)) { g.FillPath(b, p); g.DrawPath(pen, p); }
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
  string FichierArret { get { return Path.Combine(dossier, "arret.flag"); } }
  string FichierReglages { get { return Path.Combine(dossier, "Ferme-canne.ini"); } }
  string FichierHistorique { get { return Path.Combine(dossier, "historique.csv"); } }
  string FichierDeparts { get { return Path.Combine(dossier, "departs-etages.txt"); } }

  Nombre etage, seuil, venteMs, marge, tours;
  Interrupteur venteActive, regard, sonsActive;
  Segments pas, statsFiltre;
  Segments acBouton, acMode; Nombre acIntervalle, acDuree, acClicsMax, acSeuil, acVenteMs, acSlot, acTPBlocs; Interrupteur acVente, acStopTP; Label acCps;
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
  double? argentDebut, argentDernier, argentAttente;
  DateTime debutSession;
  int mode;   // script lance : 0 ferme, 1 minage (autoclic.ps1), 4 peche (meme numero que sa tuile)
  bool modeClic { get { return mode == 1; } }
  bool modePeche { get { return mode == 4; } }
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
  CarteRonde pagePeche;
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
    Text = "Macros Minecraft"; ClientSize = new Size(1000, 936); MinimumSize = new Size(1016, 900);
    Font = new Font("Segoe UI", 9.75f); StartPosition = FormStartPosition.CenterScreen; BackColor = Th.Fond; ForeColor = Th.Texte;
    DoubleBuffered = true;
    ChargerAccent();

    // ---------- en-tete ----------
    Controls.Add(new Label { Text = "MACROS", Left = 26, Top = 18, AutoSize = true, Font = new Font("Segoe UI Black", 20f), ForeColor = Th.Texte, BackColor = Th.Fond });
    titreAccent = new Label { Text = "MINECRAFT", Left = 162, Top = 18, AutoSize = true, Font = new Font("Segoe UI Black", 20f), ForeColor = Th.Accent, BackColor = Th.Fond };
    Controls.Add(titreAccent);


    // ---------- tuiles ----------
    // numero de tuile = numero de page ; Options et Statistiques : petites tuiles carrees a droite
    var defs = new[] { new[] { "Ferme a canne", "", "canne" }, new[] { "Minage", "", "pioche" }, new[] { "Options", "", "palette" }, new[] { "Statistiques", "", "stats" }, new[] { "Peche", "", "poisson" } };
    int[] gauches = { 24, 282, 798, 892, 540 };
    var bulles = new ToolTip();
    for (int k = 0; k < defs.Length; k++) {
      int idx = k; bool petite = k == 2 || k == 3;
      var t = new Tuile { Titre = defs[k][0], SousTitre = defs[k][1], Icone = defs[k][2], Compacte = petite, Left = gauches[k], Top = 92, Width = petite ? 82 : 246, Height = 82 };
      if (petite) bulles.SetToolTip(t, defs[k][0]);
      t.Click += (s, e) => { if (t.Enabled) Montrer(idx); };
      tuiles.Add(t); Controls.Add(t);
    }

    // ---------- pages de reglages ----------
    pageCanne = Page("Reglages de la ferme");
    int y = 54;
    etage = Num(pageCanne, "Etage de depart (1 a 12)", ref y, 1, 12, 1, 1);
    tours = Num(pageCanne, "Tours (0 = a l'infini)", ref y, 0, 999, 0, 1);
    pas = Liste(pageCanne, "Pas entre deux traversees", ref y, new[] { "2", "2,5", "3" });
    marge = Num(pageCanne, "Marge avant l'echelle (blocs)", ref y, 0, 10, 4, 1);
    regard = Case(pageCanne, "Recaler le regard avec F3", ref y, true);
    sonsActive = Case(pageCanne, "Sons de fin d'etage et de tour", ref y, true);
    sonsActive.CheckedChanged += (s, e) => Sauver();
    y += 4; Separateur(pageCanne, "VENTE AVEC LE DIAL", ref y);
    venteActive = Case(pageCanne, "Vente automatique", ref y, true);
    seuil = Num(pageCanne, "Cannes avant vente", ref y, 64, 2304, 2176, 64);
    venteMs = Num(pageCanne, "Temps sur le slot de vente (ms)", ref y, 50, 500, 100, 10);
    venteActive.CheckedChanged += (s, e) => { seuil.Enabled = venteMs.Enabled = venteActive.Checked; };
    seuil.ValueChanged += (s, e) => Multiple64(seuil);
    y += 4; Separateur(pageCanne, "REPRISE", ref y);
    lReprise = new Label { Left = 24, Top = y, Width = 400, Height = 44, ForeColor = Th.Discret, BackColor = Th.Carte, Text = "Aucun arret enregistre." };
    pageCanne.Controls.Add(lReprise); y += 46;
    bReprise = new BoutonRond { Left = 24, Top = y, Width = 400, Height = 40, Font = new Font("Segoe UI Semibold", 10f), BackColor = Th.Carte, Visible = false };
    bReprise.Click += (s, e) => { if (bReprise.Enabled && reprise > 0) etage.Value = reprise; };
    pageCanne.Controls.Add(bReprise);
    etage.ValueChanged += (s, e) => MajReprise();

    pageClic = Page("Reglages du minage");
    int yc = 54;
    acBouton = Liste(pageClic, "Bouton", ref yc, new[] { "Gauche", "Droit" });
    acMode = Liste(pageClic, "Mode", ref yc, new[] { "Clics", "Maintenu" });
    acIntervalle = Num(pageClic, "Intervalle entre deux clics (ms)", ref yc, 20, 10000, 100, 10);
    acCps = new Label { Left = 24, Top = yc - 10, Width = 400, ForeColor = Th.Accent, Font = new Font("Segoe UI", 8.75f), BackColor = Th.Carte, Tag = "accent-texte" }; pageClic.Controls.Add(acCps); yc += 12;
    acDuree = Num(pageClic, "Duree max (min, 0 = sans limite)", ref yc, 0, 1440, 0, 5);
    acClicsMax = Num(pageClic, "Clics max (0 = sans limite)", ref yc, 0, 10000000, 0, 100);
    acStopTP = Case(pageClic, "Arret si teleporte (coordonnees en haut a gauche)", ref yc, false);
    acTPBlocs = Num(pageClic, "Distance comptee comme TP (blocs)", ref yc, 1, 10, 3, 1);
    acTPBlocs.Enabled = false;
    acSecondPlan = Case(pageClic, "Au second plan (jeu visible sur un autre ecran)", ref yc, false);
    acStopTP.CheckedChanged += (s, e) => { acTPBlocs.Enabled = acStopTP.Checked && !EnCours(); };
    yc += 4; Separateur(pageClic, "VENTE AVEC LE DIAL (SLOT 1)", ref yc);
    acVente = Case(pageClic, "Vente automatique", ref yc, false);
    acSeuil = Num(pageClic, "Objets avant vente", ref yc, 64, 2304, 2176, 64);
    acVenteMs = Num(pageClic, "Temps avant retour au slot (ms)", ref yc, 50, 500, 100, 10);
    acSlot = Num(pageClic, "Slot repris apres la vente", ref yc, 2, 9, 2, 1);
    acIntervalle.ValueChanged += (s, e) => MajCps(); acMode.SelectedIndexChanged += (s, e) => MajCps(); acVente.CheckedChanged += (s, e) => MajCps();
    acSeuil.ValueChanged += (s, e) => Multiple64(acSeuil);

    pageTheme = Page("Options");
    int yt = 54;
    pageTheme.Controls.Add(new Label { Text = "Couleur d'accent", Left = 24, Top = yt, AutoSize = true, ForeColor = Th.Texte, BackColor = Th.Carte });
    yt += 26;
    thCouleurs = new Pastilles { Left = 22, Top = yt, Width = 410, Height = 44 };
    thCouleurs.Couleurs.AddRange(Accents.Values);
    thCouleurs.Choisie += (s, k) => ChoixAccent(k);
    pageTheme.Controls.Add(thCouleurs);
    yt += 56;
    thApercu = new Panel { Left = 24, Top = yt, Width = 400, Height = 6, BackColor = Th.Accent, Tag = "accent" }; pageTheme.Controls.Add(thApercu);
    yt += 20;
    pageTheme.Controls.Add(new Label { Text = "La couleur s'applique tout de suite a tout le menu et est retenue pour la prochaine ouverture.", Left = 24, Top = yt, Width = 400, Height = 40, ForeColor = Th.Discret, BackColor = Th.Carte });
    yt += 50; Separateur(pageTheme, "TOUCHES DANS LE JEU", ref yt);
    tPause = Touche(pageTheme, "Pause / reprise", ref yt, 0x76);
    tArret = Touche(pageTheme, "Arret", ref yt, 0x77);
    tPause.Refus = k => RefusTouche(k, tArret.Vk); tArret.Refus = k => RefusTouche(k, tPause.Vk);
    tPause.Changee += (s, e) => Sauver(); tArret.Changee += (s, e) => Sauver();
    yt += 4; Separateur(pageTheme, "MINI-FENETRE", ref yt);
    miniActive = Case(pageTheme, "Mini-fenetre par-dessus le jeu", ref yt, false);
    miniActive.CheckedChanged += (s, e) => { if (miniActive.Checked && EnCours()) MontrerMini(); else if (!miniActive.Checked) CacherMini(); Sauver(); };
    pageTheme.Controls.Add(new Label { Text = "Etat, temps, ventes et gains, toujours visibles pendant que le script tourne. Elle ne prend pas la main sur le jeu. Ne la pose pas en haut de l'ecran ni en bas a droite : le script y lit l'argent et le compteur.", Left = 24, Top = yt, Width = 400, Height = 62, ForeColor = Th.Discret, BackColor = Th.Carte });
    yt += 64; Separateur(pageTheme, "VERIFICATION AFK", ref yt);
    verifActive = Case(pageTheme, "Repondre seul (ecrit le nombre dans le chat)", ref yt, false);
    verifActive.CheckedChanged += (s, e) => Sauver();

    pageStats = Page("Statistiques");
    // choix de la categorie : tout, ou une seule (chaque categorie a ses propres totaux et son graphique)
    statsFiltre = new Segments("Global", "Canne", "Peche", "Minage") { Left = 24, Top = 50, Width = 400, Height = 30 };
    statsFiltre.SelectedIndexChanged += (s, e) => { graphique.Filtre = new string[] { null, "canne", "peche", "autoclick" }[statsFiltre.SelectedIndex]; graphique.Invalidate(); Sauver(); };
    pageStats.Controls.Add(statsFiltre);
    graphique = new Graphique { Left = 24, Top = 94, Width = 400, Height = 430 };
    pageStats.Controls.Add(graphique);

    pagePeche = Page("Reglages de la peche");
    int yp = 54;
    pcAnticip = Num(pagePeche, "Anticipation (ms)", ref yp, 0, 500, 50, 10);
    pcTol = Num(pagePeche, "Tolerance sur le poisson (px)", ref yp, 0, 60, 10, 2);
    pagePeche.Controls.Add(new Label { Text = "La zone a de l'inertie : le script freine avant le poisson pour s'y arreter. Anticipation : le temps que met le clic a agir (50 ms conseille). Si la zone depasse souvent le poisson, monte-la un peu.", Left = 24, Top = yp - 4, Width = 400, Height = 62, ForeColor = Th.Discret, BackColor = Th.Carte });
    yp += 62;
    pcAttente = Num(pagePeche, "Attente avant de relancer (ms)", ref yp, 300, 5000, 1200, 100);
    pcRelance = Num(pagePeche, "Relancer si rien ne mord (s)", ref yp, 20, 300, 120, 10);
    pcMax = Num(pagePeche, "Poissons max (0 = sans limite)", ref yp, 0, 100000, 0, 10);
    pcSlot = Num(pagePeche, "Slot de la canne", ref yp, 1, 9, 1, 1);
    pcSecondPlan = Case(pagePeche, "Au second plan (jeu visible sur un autre ecran)", ref yp, false);
    pagePeche.Controls.Add(new Label { Text = "Dans le jeu : canne en main, ligne pas lancee, puis la touche pause (F7 par defaut). Le script lance la ligne, joue le mini-jeu et relance.", Left = 24, Top = yp + 4, Width = 400, Height = 44, ForeColor = Th.Discret, BackColor = Th.Carte });

    foreach (var p in new[] { pageCanne, pageClic, pageTheme, pageStats, pagePeche }) { p.Left = 24; p.Top = 190; p.Width = 448; p.Height = 536; Controls.Add(p); }

    // ---------- en direct ----------
    var etat = new CarteRonde { Left = 488, Top = 190, Width = 488, Height = 64 };
    pastille = new Panel { Left = 22, Top = 26, Width = 12, Height = 12, BackColor = Th.Discret };
    var gp = new GraphicsPath(); gp.AddEllipse(0, 0, 12, 12); pastille.Region = new Region(gp);
    etat.Controls.Add(pastille);
    etat.Controls.Add(new Label { Text = "ETAT", Left = 44, Top = 12, AutoSize = true, ForeColor = Th.Discret, BackColor = Th.Carte, Font = new Font("Segoe UI Semibold", 8.25f) });
    lEtat = new Label { Text = "arrete", Left = 44, Top = 28, Width = 420, Height = 26, ForeColor = Th.Texte, BackColor = Th.Carte, Font = new Font("Segoe UI Semibold", 12f) };
    etat.Controls.Add(lEtat);
    Controls.Add(etat);

    lTour = Stat("TOUR", 488, 266, out cTour); lEtage = Stat("ETAGE", 652, 266, out cEtage); lTraversee = Stat("TRAVERSEE", 816, 266, out cTraversee);
    Label c1; lVentes = Stat("VENTES", 488, 362, out cVentes, 324); lTemps = Stat("TEMPS", 816, 362, out c1);
    lVentes.Font = new Font("Segoe UI Semibold", 15f); lVentes.AutoEllipsis = true;
    lGains = Stat("GAINS (ARGENT EN HAUT DE L'ECRAN)", 488, 458, out cGains, 324); lHeure = Stat("PAR HEURE", 816, 458, out c1);
    lGains.ForeColor = Th.Accent; lGains.Tag = "accent-texte"; lHeure.Font = new Font("Segoe UI Semibold", 15f);

    demarrer = new BoutonRond { Text = "DEMARRER", Principal = true, Left = 488, Top = 606, Width = 488, Height = 58, Font = new Font("Segoe UI Black", 14f), BackColor = Th.Fond };
    arreter = new BoutonRond { Text = "Arreter", Left = 488, Top = 674, Width = 240, Height = 52, Font = new Font("Segoe UI Semibold", 10.5f), BackColor = Th.Fond, CouleurBord = Color.FromArgb(255, 90, 80), Enabled = false };
    vider = new BoutonRond { Text = "Vider le journal", Left = 736, Top = 674, Width = 240, Height = 52, Font = new Font("Segoe UI Semibold", 10.5f), BackColor = Th.Fond };
    demarrer.Click += (s, e) => { if (demarrer.Enabled) Demarrer(); }; arreter.Click += (s, e) => { if (arreter.Enabled) Arreter(); }; vider.Click += (s, e) => journal.Clear();
    Controls.Add(demarrer); Controls.Add(arreter); Controls.Add(vider);

    // ---------- journal ----------
    var cadre = new CarteRonde { Left = 24, Top = 742, Width = 952, Height = 178, Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right };
    cadre.Controls.Add(new Label { Text = "JOURNAL", Left = 20, Top = 12, AutoSize = true, Font = new Font("Segoe UI Semibold", 8.25f), ForeColor = Th.Discret, BackColor = Th.Carte });
    journal = new RichTextBox { Left = 20, Top = 34, Width = 912, Height = 132, ReadOnly = true, BorderStyle = BorderStyle.None, BackColor = Th.Carte,
      ForeColor = Th.Texte, Font = new Font("Consolas", 9.75f), Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right };
    cadre.Controls.Add(journal);
    Controls.Add(cadre);

    horloge = new Timer { Interval = 1000 };
    horloge.Tick += (s, e) => { AfficherTemps(); AfficherGains(); MajMini(); };
    horloge.Start();

    Charger();
    ChargerHistorique();
    ChargerDeparts();
    MajReprise();
    MajCps();
    Montrer(page);
    AppliquerAccent();
    Etat("arrete", Th.Discret);
    Ecrire("Regle les options, clique Demarrer, puis dans le jeu : chat ferme, " + NomPause + ".", Th.Accent);
    Ecrire(NomPause + " = pause / reprise, " + NomArret + " ou le bouton Arreter = arret.", Th.Discret);
    FormClosing += (s, e) => { Sauver(); if (proc != null && !proc.HasExited) Arreter(); CacherMini(); };
    HandleCreated += (s, e) => BarreSombre();
  }

  // ------------------------------ Construction ------------------------------
  void BarreSombre() {
    try { int un = 1; DwmSetWindowAttribute(Handle, 20, ref un, 4); int c = Th.Fond.R | (Th.Fond.G << 8) | (Th.Fond.B << 16); DwmSetWindowAttribute(Handle, 35, ref c, 4); } catch { }
  }
  CarteRonde Page(string titre) {
    var p = new CarteRonde();
    p.Controls.Add(new Label { Text = titre, Left = 22, Top = 16, AutoSize = true, Font = new Font("Segoe UI Semibold", 12f), ForeColor = Th.Texte, BackColor = Th.Carte });
    return p;
  }
  Label Stat(string titre, int x, int y, out Label legende, int largeur = 160) {
    var c = new CarteRonde { Left = x, Top = y, Width = largeur, Height = 86 };
    legende = new Label { Text = titre, Left = 18, Top = 14, AutoSize = true, ForeColor = Th.Discret, BackColor = Th.Carte, Font = new Font("Segoe UI Semibold", 8.25f) };
    var v = new Label { Text = "-", Left = 16, Top = 34, Width = largeur - 26, Height = 40, ForeColor = Th.Texte, BackColor = Th.Carte, Font = new Font("Segoe UI Semibold", 19f) };
    c.Controls.Add(legende); c.Controls.Add(v); Controls.Add(c);
    return v;
  }
  void Separateur(Control parent, string texte, ref int y) {
    parent.Controls.Add(new Label { Text = texte, Left = 24, Top = y, AutoSize = true, Font = new Font("Segoe UI Semibold", 8.5f), ForeColor = Th.Accent, BackColor = Th.Carte, Tag = "accent-texte" });
    parent.Controls.Add(new Panel { Left = 24, Top = y + 20, Width = 400, Height = 1, BackColor = Th.Bordure });
    y += 30;
  }
  Nombre Num(Control parent, string texte, ref int y, int min, int max, int val, int pasNum) {
    parent.Controls.Add(new Label { Text = texte, Left = 24, Top = y + 6, Width = 260, ForeColor = Th.Texte, BackColor = Th.Carte });
    var n = new Nombre { Left = 288, Top = y, Width = 136, Height = 30, Minimum = min, Maximum = max, Increment = pasNum };
    n.Value = val;
    parent.Controls.Add(n); y += 36; return n;
  }
  Interrupteur Case(Control parent, string texte, ref int y, bool val) {
    var c = new Interrupteur { Text = texte, Left = 24, Top = y, Width = 400, Height = 30 };
    c.Checked = val;
    parent.Controls.Add(c); y += 36; return c;
  }
  Segments Liste(Control parent, string texte, ref int y, string[] choix) {
    parent.Controls.Add(new Label { Text = texte, Left = 24, Top = y + 6, Width = 200, ForeColor = Th.Texte, BackColor = Th.Carte });
    var l = new Segments(choix) { Left = 228, Top = y, Width = 196, Height = 30 };
    parent.Controls.Add(l); y += 36; return l;
  }
  ChoixTouche Touche(Control parent, string texte, ref int y, int vk) {
    parent.Controls.Add(new Label { Text = texte, Left = 24, Top = y + 6, Width = 200, ForeColor = Th.Texte, BackColor = Th.Carte });
    var t = new ChoixTouche { Left = 228, Top = y, Width = 196, Height = 30, Vk = vk };
    parent.Controls.Add(t); y += 36; return t;
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
    pageCanne.Visible = i == 0; pageClic.Visible = i == 1; pageTheme.Visible = i == 2; pageStats.Visible = i == 3; pagePeche.Visible = i == 4;
    for (int k = 0; k < tuiles.Count; k++) { tuiles[k].Choisie = k == i; tuiles[k].Invalidate(); }
  }
  void Multiple64(Nombre n) { decimal v = Math.Max(64m, Math.Min(2304m, Math.Round(n.Value / 64m) * 64m)); if (v != n.Value) n.Value = v; }
  void MajCps() {
    bool clics = acMode.SelectedIndex == 0;
    acIntervalle.Enabled = clics && !EnCours();
    acCps.Text = clics ? string.Format("soit {0:0.##} clics par seconde", 1000.0 / (double)acIntervalle.Value) : "bouton tenu en continu";
    acSeuil.Enabled = acVenteMs.Enabled = acSlot.Enabled = acVente.Checked && !EnCours();
  }
  bool EnCours() { return proc != null && !proc.HasExited; }

  // ------------------------------ Couleur d'accent ------------------------------
  void ChargerAccent() {
    try {
      if (!File.Exists(FichierReglages)) return;
      foreach (var l in File.ReadAllLines(FichierReglages)) if (l.StartsWith("accent=")) Th.Accent = ColorTranslator.FromHtml("#" + l.Substring(7));
    } catch { }
  }
  void ChoixAccent(int k) {
    if (k < thCouleurs.Couleurs.Count) Th.Accent = thCouleurs.Couleurs[k];
    else using (var d = new ColorDialog { Color = Th.Accent, FullOpen = true }) { if (d.ShowDialog(this) != DialogResult.OK) return; Th.Accent = d.Color; }
    AppliquerAccent(); Sauver();
  }
  void AppliquerAccent() {
    titreAccent.ForeColor = Th.Accent;
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
    }
    AfficherGains();
  }
  void AfficherGains() {
    double h = Ecoule().TotalHours;
    if ((modePeche || modeClic) && prisesLues > 0) {   // peche et minage : somme des gains lus au-dessus de la vie (plus precis que l'argent du haut, arrondi a 10K)
      lGains.Text = Session.Signe(argentPeche) + "  ·  " + Session.Signe(xpPeche) + " xp";
      lHeure.Text = h >= 1.0 / 60 ? Session.Signe(argentPeche / h) + "/h" : "-";
      return;
    }
    if (!argentDebut.HasValue) return;
    double gains = argentDernier.Value - argentDebut.Value;
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
    if ((modePeche || modeClic) && prisesLues > 0) mini.Gains = Session.Signe(argentPeche) + "  ·  " + Session.Signe(xpPeche) + " xp";
    else mini.Gains = argentDebut.HasValue ? lHeure.Text + "   " + Session.Signe(argentDernier.Value - argentDebut.Value) : "gains : -";
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
  // Fin de session : etage interrompu -> on y repart ; etage fini -> le suivant (en haut de l'echelle) ; tour fini -> etage 1 (/home s).
  void CalculerReprise() {
    if (mode != 0 || !chronoLance) return;
    reprise = etageEnCours == 0 ? 1 : (etageFini ? etageEnCours % 12 + 1 : etageEnCours);
    Sauver(); MajReprise();
    Ecrire("Pour reprendre : etage " + reprise + ". " + OuSePlacer(reprise), Th.Accent);
  }
  string OuSePlacer(int n) {
    string regardTxt = n % 2 == 1 ? "est" : "ouest", pos;
    if (n == 1) return "Fais /home s (depart en 19 107 -80), regard vers l'est.";
    if (departs.TryGetValue(n, out pos)) return "Place-toi en " + pos + ", colle au mur de depart, regard vers l'" + regardTxt + ".";
    return "Depart de cet etage pas encore connu (en haut de l'echelle de l'etage " + (n - 1) + "), regard vers l'" + regardTxt + ".";
  }
  void MajReprise() {
    if (lReprise == null) return;
    if (reprise <= 0) { lReprise.Text = "Aucun arret enregistre."; bReprise.Visible = false; return; }
    lReprise.Text = "Dernier arret : reprendre a l'etage " + reprise + ".\n" + OuSePlacer(reprise);
    bReprise.Visible = true;
    bool dejaRegle = etage.Value == reprise;
    bReprise.Text = dejaRegle ? "Etage de depart regle sur " + reprise : "Reprendre a l'etage " + reprise;
    bReprise.Principal = !dejaRegle; bReprise.Enabled = !dejaRegle && !EnCours(); bReprise.Invalidate();
  }

  // ------------------------------ Historique ------------------------------
  void ChargerHistorique() {
    graphique.Sessions.Clear();
    try {
      if (File.Exists(FichierHistorique))
        foreach (var l in File.ReadAllLines(FichierHistorique)) { var s = Session.Lire(l); if (s != null) graphique.Sessions.Add(s); }
    } catch { }
    graphique.Invalidate();
  }
  void EnregistrerSession() {
    int duree = (int)Ecoule().TotalSeconds;
    if (!chronoLance || duree < 30) return;   // session pas vraiment commencee
    var s = new Session { Date = debutSession, DureeS = duree, Mode = modePeche ? "peche" : modeClic ? "autoclick" : "canne", Tours = toursFinis, Etages = etagesFinis, Clics = clics,
      Ventes = ventes, Essais = essais, ArgentDebut = argentDebut, ArgentFin = argentDernier };
    if (modeClic) { s.ArgentPrises = argentPeche; s.Xp = xpPeche; }
    if (modePeche) { s.Clics = poissons; s.Essais = poissons + rates; s.ArgentPrises = argentPeche; s.Xp = xpPeche; foreach (var kv in especes) s.Especes[kv.Key] = kv.Value; foreach (var kv in couleursEsp) s.CouleursEsp[kv.Key] = kv.Value; }   // peche : poissons attrapes / mini-jeux
    try {
      if (!File.Exists(FichierHistorique)) File.WriteAllText(FichierHistorique, Session.Entete + Environment.NewLine);
      File.AppendAllText(FichierHistorique, s.Ligne() + Environment.NewLine);
    } catch (Exception ex) { Ecrire("Historique non enregistre : " + ex.Message, Rouge); }
    graphique.Sessions.Add(s); graphique.Invalidate();
    Ecrire(string.Format("Session enregistree : {0}, {1} ventes{2}.", Session.Duree(duree), ventes, s.Gains.HasValue ? ", " + Session.Signe(s.Gains.Value) + (s.ParHeure.HasValue ? " (" + Session.Signe(s.ParHeure.Value) + "/h)" : "") : ""), Th.Accent);
  }
  TimeSpan Ecoule() { return cumul + (debut.HasValue ? DateTime.Now - debut.Value : TimeSpan.Zero); }
  void AfficherTemps() { if (!chronoLance) return; var d = Ecoule(); lTemps.Text = string.Format("{0}:{1:00}:{2:00}", (int)d.TotalHours, d.Minutes, d.Seconds); lTemps.ForeColor = debut.HasValue ? Th.Accent : Th.Discret; }
  void ChronoMarche() { chronoLance = true; if (!debut.HasValue) debut = DateTime.Now; AfficherTemps(); }
  void ChronoFige() { if (debut.HasValue) { cumul += DateTime.Now - debut.Value; debut = null; } AfficherTemps(); }

  void Ecrire(string ligne, Color c) {
    journal.SelectionStart = journal.TextLength; journal.SelectionLength = 0;
    journal.SelectionColor = Color.FromArgb(90, 90, 100);
    journal.AppendText(DateTime.Now.ToString("HH:mm:ss") + "  ");
    journal.SelectionColor = c;
    journal.AppendText(ligne + "\n");
    journal.ScrollToCaret();
  }

  // ------------------------------ Lancement ------------------------------
  void Demarrer() {
    if (EnCours()) return;
    if (page == 2 || page == 3) { Ecrire("Choisis la tuile Ferme a canne, Minage ou Peche avant de demarrer.", Jaune); return; }
    mode = page;
    string scr = modePeche ? ScriptPeche : modeClic ? ScriptClic : Script;
    if (!File.Exists(scr)) { Ecrire("Script introuvable : " + scr, Rouge); return; }
    if (File.Exists(FichierArret)) File.Delete(FichierArret);
    Sauver();
    ventes = 0; essais = 0; debut = null; cumul = TimeSpan.Zero; chronoLance = false;
    toursFinis = 0; etagesFinis = 0; clics = 0; etageEnCours = (int)etage.Value; etageFini = false; argentDebut = argentDernier = argentAttente = null; debutSession = DateTime.Now;
    lGains.Text = "-"; lHeure.Text = "-";
    cTour.Text = modeClic ? "BOUTON" : "TOUR"; cEtage.Text = modeClic ? "MODE" : "ETAGE"; cTraversee.Text = modeClic ? "CLICS" : "TRAVERSEE";
    if (modeClic) { lTour.Text = acBouton.SelectedIndex == 0 ? "Gauche" : "Droit"; lEtage.Text = acMode.SelectedIndex == 0 ? "Clics" : "Tenu"; lTraversee.Text = "0"; }
    else { lTour.Text = "1"; lEtage.Text = etage.Value + "/12"; lTraversee.Text = "-"; }
    poissons = 0; rates = 0; especes.Clear(); couleursEsp.Clear();
    cVentes.Text = modePeche ? "PAR ESPECE" : "VENTES";
    // peche : liste des especes en petit sur deux lignes (en gros, elle etait coupee des la 3e espece)
    lVentes.Font = new Font("Segoe UI Semibold", modePeche ? 9.5f : 15f); lVentes.AutoEllipsis = true;
    lVentes.Top = modePeche ? 32 : 34; lVentes.Height = modePeche ? 46 : 40;
    bulleEspeces.SetToolTip(lVentes, null);
    argentPeche = 0; xpPeche = 0; prisesLues = 0;
    cGains.Text = modePeche ? "GAINS DES PRISES (ARGENT  ·  XP)" : modeClic ? "GAINS DU MINAGE (ARGENT  ·  XP)" : "GAINS (ARGENT EN HAUT DE L'ECRAN)";
    if (modePeche) { cTour.Text = "POISSONS"; cEtage.Text = "RATES"; cTraversee.Text = "REUSSITE"; lTour.Text = "0"; lEtage.Text = "0"; lTraversee.Text = "-"; }
    lVentes.Text = "-"; lTemps.Text = "-"; lTemps.ForeColor = Th.Discret;
    string args = modePeche
      ? string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -AnticipMs {1} -Tolerance {2} -AttenteMs {3} -RelanceS {4} -PoissonsMax {5} -SlotCanne {6}",
          ScriptPeche, (int)pcAnticip.Value, (int)pcTol.Value, (int)pcAttente.Value, (int)pcRelance.Value, (int)pcMax.Value, (int)pcSlot.Value)
      : modeClic
      ? string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Bouton {1} -Mode {2} -IntervalleMs {3} -DureeMaxS {4} -ClicsMax {5} -VenteSeuil {6} -VenteMs {7} -SlotRetour {8}",
          ScriptClic, acBouton.SelectedIndex == 0 ? "gauche" : "droit", acMode.SelectedIndex == 0 ? "clics" : "maintien", (int)acIntervalle.Value,
          (int)acDuree.Value * 60, (int)acClicsMax.Value, acVente.Checked ? (int)acSeuil.Value : 0, (int)acVenteMs.Value, (int)acSlot.Value)
      : string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -EtageDepart {1} -VenteSeuil {2} -VenteMs {3} -Pas {4} -MargeEchelle {5} -RecalerRegard {6} -Tours {7}",
          Script, etage.Value, venteActive.Checked ? (int)seuil.Value : 0, (int)venteMs.Value, new[] { 2, 25, 3 }[pas.SelectedIndex], (int)marge.Value, regard.Checked ? "1" : "0", (int)tours.Value);
    args += string.Format(" -TouchePause {0} -ToucheArret {1} -RepondreVerif {2}", tPause.Vk, tArret.Vk, verifActive.Checked ? 1 : 0);
    if (mode == 0) args += " -Sons " + (sonsActive.Checked ? 1 : 0);
    if (modeClic) args += " -StopTP " + (acStopTP.Checked ? 1 : 0) + " -TPBlocs " + (int)acTPBlocs.Value;
    if (modeClic || modePeche) args += " -SecondPlan " + ((modeClic ? acSecondPlan.Checked : pcSecondPlan.Checked) ? 1 : 0);
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
    if (modePeche) Ecrire("Lancement de la peche.", Th.Texte);
    else if (modeClic) Ecrire("Lancement du minage.", Th.Texte);
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
    else if (l.StartsWith("Minage lance") || l.StartsWith("Peche lancee")) { ChronoMarche(); Etat("en cours", Vert); c = Vert; }
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
      var d = Regex.Match(l, @"depart X (-?[\d.]+)\s+Y (-?[\d.]+)\s+Z (-?[\d.]+)");
      if (d.Success) RetenirDepart(etageEnCours, d.Groups[1].Value + " " + d.Groups[2].Value + " " + d.Groups[3].Value);
    }
    else if ((m = Regex.Match(l, @"traversee (\d+)/(\d+)")).Success) { lTraversee.Text = m.Groups[1].Value + "/" + m.Groups[2].Value; c = Color.FromArgb(110, 110, 122); }
    else if (l.Contains("vente reussie")) { ventes++; lVentes.Text = ventes + " reussies / " + essais; c = Violet; }
    else if (l.Contains("essai de vente")) { essais++; lVentes.Text = ventes + " reussies / " + essais; c = Color.FromArgb(170, 130, 210); }
    else if (l.StartsWith("PAUSE") || l.Contains("en pause")) { ChronoFige(); Etat("pause  -  " + NomPause + " pour reprendre", Jaune); c = Jaune; }
    else if (l.StartsWith("Reprise")) { if (chronoLance) ChronoMarche(); Etat("en cours", Vert); c = Vert; }
    else if (l.Contains("termine") || l.Contains("recale") || l.StartsWith("En haut")) {
      if (Regex.IsMatch(l, @"^Tour \d+ termine")) { toursFinis++; etageEnCours = 0; }
      else if (Regex.IsMatch(l, @"^Etage \d+ termine")) { etagesFinis++; etageFini = true; }
      c = Vert;
    }
    else if (Regex.IsMatch(l, "arret|ARRET|illisible|impossible|Trop|trop longue|incertaine|redescends")) c = Rouge;
    else if (l.StartsWith("Dans le jeu") || l.StartsWith("Reviens") || l.StartsWith("Minage :")) c = Th.Accent;
    Ecrire(l.Trim(), c);
  }

  void Arreter() {
    if (!EnCours()) return;
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
    Etat("arrete", Th.Discret);
    demarrer.Enabled = true; arreter.Enabled = false; ActiverReglages(true);
    Ecrire("Script termine.", Th.Texte);
    EnregistrerSession();
    CalculerReprise();
    MajReprise();
    CacherMini();
  }
  void ActiverReglages(bool on) {
    foreach (Control c in new Control[] { etage, tours, venteActive, seuil, venteMs, marge, regard, sonsActive, pas, acBouton, acMode, acIntervalle, acDuree, acClicsMax, acVente, acSeuil, acVenteMs, acSlot, acStopTP, acTPBlocs, tPause, tArret, verifActive }) c.Enabled = on;
    // pendant que ca tourne : pas de changement de mode, mais Options et Statistiques restent visibles
    for (int k = 0; k < tuiles.Count; k++) tuiles[k].Enabled = on || k == mode || k == 2 || k == 3;
    foreach (Control c in new Control[] { pcAnticip, pcTol, pcAttente, pcRelance, pcMax, pcSlot, pcSecondPlan, acSecondPlan }) c.Enabled = on;
    if (on) { seuil.Enabled = venteMs.Enabled = venteActive.Checked; MajCps(); acTPBlocs.Enabled = acStopTP.Checked; }
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
        "acBouton=" + acBouton.SelectedIndex, "acMode=" + acMode.SelectedIndex, "acIntervalle=" + acIntervalle.Value, "acDuree=" + acDuree.Value,
        "acClicsMax=" + acClicsMax.Value, "acStopTP=" + (acStopTP.Checked ? 1 : 0), "acTPBlocs=" + acTPBlocs.Value, "acVente=" + (acVente.Checked ? 1 : 0), "acSeuil=" + acSeuil.Value, "acVenteMs=" + acVenteMs.Value, "acSlot=" + acSlot.Value,
        "pcAnticip2=" + pcAnticip.Value, "pcSecondPlan=" + (pcSecondPlan.Checked ? 1 : 0), "acSecondPlan=" + (acSecondPlan.Checked ? 1 : 0), "pcTol2=" + pcTol.Value, "pcAttente=" + pcAttente.Value, "pcRelance=" + pcRelance.Value, "pcMax=" + pcMax.Value, "pcSlot=" + pcSlot.Value,
        "onglet=" + page, "stats=" + statsFiltre.SelectedIndex, "reprise=" + reprise, "pause=" + tPause.Vk, "arret=" + tArret.Vk, "mini=" + (miniActive.Checked ? 1 : 0), "verif=" + (verifActive.Checked ? 1 : 0),
        "miniX=" + (miniPos.HasValue ? miniPos.Value.X : -99999), "miniY=" + (miniPos.HasValue ? miniPos.Value.Y : -99999),
        "accent=" + string.Format("{0:X2}{1:X2}{2:X2}", Th.Accent.R, Th.Accent.G, Th.Accent.B) });
    } catch { }
  }
  void Charger() {
    if (!File.Exists(FichierReglages)) return;
    chargement = true;
    try {
      var d = new Dictionary<string, int>();
      foreach (var l in File.ReadAllLines(FichierReglages)) { var p = l.Split('='); int v; if (p.Length == 2 && int.TryParse(p[1], out v)) d[p[0]] = v; }
      int x;
      if (d.TryGetValue("etage", out x)) etage.Value = Math.Max(1, Math.Min(12, x));
      if (d.TryGetValue("tours", out x)) tours.Value = Math.Max(0, Math.Min(999, x));
      if (d.TryGetValue("vente", out x)) venteActive.Checked = x == 1;
      if (d.TryGetValue("seuil", out x)) seuil.Value = Math.Max(64, Math.Min(2304, (int)Math.Round(x / 64.0) * 64));
      if (d.TryGetValue("venteMs", out x)) venteMs.Value = Math.Max(50, Math.Min(500, x));
      if (d.TryGetValue("marge", out x)) marge.Value = Math.Max(0, Math.Min(10, x));
      if (d.TryGetValue("regard", out x)) regard.Checked = x == 1;
      if (d.TryGetValue("sons", out x)) sonsActive.Checked = x == 1;
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
      if (d.TryGetValue("acStopTP", out x)) acStopTP.Checked = x == 1;
      if (d.TryGetValue("acTPBlocs", out x)) acTPBlocs.Value = Math.Max(1, Math.Min(10, x));
      acTPBlocs.Enabled = acStopTP.Checked;
      if (d.TryGetValue("onglet", out x)) page = (x >= 0 && x <= 4) ? x : 0;
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
      int mx, my; if (d.TryGetValue("miniX", out mx) && d.TryGetValue("miniY", out my) && mx != -99999) miniPos = new Point(mx, my);
      seuil.Enabled = venteMs.Enabled = venteActive.Checked;
    } catch { }
    chargement = false;
  }
}
