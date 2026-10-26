# =====================================================================
#  enregistrer-peche.ps1 : enregistre le mini-jeu de peche pendant que TU peches.
#
#  N'appuie sur AUCUNE touche, ne clique pas, n'ecrit rien dans le chat : il regarde seulement.
#  Pendant que la barre de peche est a l'ecran (zone verte visible), il capture la barre
#  ~20 fois par seconde et note si tu tiens le clic droit. Les images vont dans
#  D:\macros-minecraft\enregistrement-peche\<date>\ avec un fichier clics.csv.
#
#  F8 : arret.  Arret tout seul apres 10 minutes.
#  LANCEMENT :
#    powershell -ExecutionPolicy Bypass -File "D:\macros-minecraft\outils\enregistrer-peche.ps1"
# =====================================================================
$racine = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$sortie = Join-Path $racine ('enregistrement-peche\' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
New-Item -ItemType Directory -Force $sortie | Out-Null

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class Regard {
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
  public static bool Appuyee(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
  public static Bitmap Capturer(Rectangle r) {
    var bmp = new Bitmap(r.Width, r.Height, PixelFormat.Format24bppRgb);
    using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(r.Location, Point.Empty, r.Size);
    return bmp;
  }
  // pixels du vert de la zone de peche (81,178,84 / 68,154,72 / 108,211,121)
  public static int NbVert(Bitmap bmp) {
    var bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var b = new byte[bd.Stride * bmp.Height]; Marshal.Copy(bd.Scan0, b, 0, b.Length); bmp.UnlockBits(bd);
    int n = 0;
    for (int y = 0; y < bmp.Height; y += 2) for (int x = 0; x < bmp.Width; x += 2) {
      int o = y * bd.Stride + x * 3; int bl = b[o], gg = b[o + 1], rr = b[o + 2];
      if (gg >= 140 && gg - rr >= 50 && gg - bl >= 50 && rr <= 150) n++;
    }
    return n;
  }
}
'@

# Zone : la barre et sa jauge, au centre gauche de l'ecran du jeu (mesure sur une capture 2560 x 1440 :
# barre en x 1034-1150, y 480-1090), avec de la marge.
$jeu = Get-Process -Name javaw, java -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
if (-not $jeu) { Write-Host "Le jeu n'est pas lance." -ForegroundColor Red; return }
$ecran = [System.Windows.Forms.Screen]::FromHandle($jeu.MainWindowHandle).Bounds
$zone = New-Object System.Drawing.Rectangle ($ecran.X + [int]($ecran.Width * 0.39)), ($ecran.Y + [int]($ecran.Height * 0.31)), ([int]($ecran.Width * 0.07)), ([int]($ecran.Height * 0.48))
Write-Host ("Ecran du jeu {0} x {1}, zone capturee {2} x {3} en ({4}, {5})." -f $ecran.Width, $ecran.Height, $zone.Width, $zone.Height, $zone.X, $zone.Y)
Write-Host "Peche normalement : 3 ou 4 poissons, si possible de raretes differentes. F8 = arret." -ForegroundColor Cyan
Write-Host "Je n'appuie sur rien, je regarde seulement." -ForegroundColor Cyan

$csv = Join-Path $sortie 'clics.csv'
Set-Content $csv 'image;ms;clic_droit;mini_jeu'
$sw = [Diagnostics.Stopwatch]::StartNew()
$n = 0; $enCours = $false; $finMs = 0; $miniJeux = 0
while (-not [Regard]::Appuyee(0x77) -and $sw.Elapsed.TotalMinutes -lt 10) {
  $t0 = $sw.ElapsedMilliseconds
  $bmp = [Regard]::Capturer($zone)
  $visible = ([Regard]::NbVert($bmp) -gt 150)
  if ($visible -and -not $enCours) { $miniJeux++; Write-Host ("Mini-jeu {0} : enregistrement..." -f $miniJeux) -ForegroundColor Green }
  if (-not $visible -and $enCours) { $finMs = $t0 + 1500 }            # encore 1,5 s apres la fin, pour voir comment ca se termine
  $enCours = $visible
  if ($visible -or $t0 -lt $finMs) {
    $n++
    $nom = 'f{0:D5}.png' -f $n
    $bmp.Save((Join-Path $sortie $nom), [System.Drawing.Imaging.ImageFormat]::Png)
    Add-Content $csv ('{0};{1};{2};{3}' -f $nom, $t0, [int][Regard]::Appuyee(0x02), [int]$visible)
  }
  $bmp.Dispose()
  $reste = 50 - ($sw.ElapsedMilliseconds - $t0)
  if ($reste -gt 0) { Start-Sleep -Milliseconds $reste }
}
Write-Host ("Termine : {0} mini-jeux, {1} images dans {2}" -f $miniJeux, $n, $sortie) -ForegroundColor Green
