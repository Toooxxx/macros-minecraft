# =====================================================================
#  test-souris-second-plan.ps1 : la vue du jeu peut-elle tourner quand le jeu est au SECOND PLAN ?
#
#  Les mouvements sont envoyes DIRECTEMENT a la fenetre de Minecraft (PostMessage) ; rien n'est envoye
#  a la fenetre au premier plan, rien n'est ecrit dans le chat.
#
#  Avant, dans le jeu : F3 + P (pas de pause au second plan), et Options > Commandes > Reglages de la
#  souris > "Entree brute" (Raw Input) : DESACTIVEE (sinon le jeu lit la souris par un canal qu'on ne
#  peut pas imiter). Ensuite clique sur une AUTRE fenetre et regarde le jeu.
#
#  Test A (par defaut, sans risque) : mouvement vers la droite puis retour, envoye a la fenetre.
#  Test B (avec -AvecFocus) : on fait d'abord croire au jeu qu'il est actif. ATTENTION : le jeu peut
#  alors attraper ta souris un instant (elle saute sur le jeu) ; elle est remise a sa place et liberee a la fin.
#
#  LANCEMENT :
#    powershell -ExecutionPolicy Bypass -File "D:\macros-minecraft\outils\test-souris-second-plan.ps1"
#    powershell -ExecutionPolicy Bypass -File "D:\macros-minecraft\outils\test-souris-second-plan.ps1" -AvecFocus
# =====================================================================
param([switch]$AvecFocus)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SourisFond {
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool ClipCursor(IntPtr r);
  public static int[] Taille(IntPtr h) { RECT r; GetClientRect(h, out r); return new[] { r.R - r.L, r.B - r.T }; }
  public static void Bouger(IntPtr h, int x, int y) { PostMessage(h, 0x0200, IntPtr.Zero, (IntPtr)((y << 16) | (x & 0xFFFF))); }   // WM_MOUSEMOVE
  public static void Focus(IntPtr h, bool oui) { PostMessage(h, oui ? 0x0007u : 0x0008u, IntPtr.Zero, IntPtr.Zero); }        // WM_SETFOCUS / WM_KILLFOCUS
}
'@

$jeu = Get-Process -Name javaw, java -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
if (-not $jeu) { Write-Host "Le jeu n'est pas lance." -ForegroundColor Red; return }
$h = $jeu.MainWindowHandle
Write-Host ("Fenetre du jeu : '{0}'" -f $jeu.MainWindowTitle)
Write-Host "Dans le jeu : F3 + P, et 'Entree brute' (Raw Input) DESACTIVEE dans les reglages de la souris." -ForegroundColor Cyan
Write-Host "Puis clique sur une AUTRE fenetre. Le test attend que le jeu ne soit plus au premier plan." -ForegroundColor Cyan

$fin = [Environment]::TickCount + 120000
while ([SourisFond]::GetForegroundWindow() -eq $h) {
  if ([Environment]::TickCount -gt $fin) { Write-Host "Le jeu est reste au premier plan : test annule." -ForegroundColor Red; return }
  Start-Sleep -Milliseconds 200
}
$t = [SourisFond]::Taille($h); $cx = [int]($t[0] / 2); $cy = [int]($t[1] / 2)
$p = New-Object SourisFond+POINT; [void][SourisFond]::GetCursorPos([ref]$p)   # position de ta souris, remise a la fin
Write-Host ("Le jeu est au second plan. Test {0} dans 3 s : regarde le jeu." -f $(if ($AvecFocus) { 'B (avec focus simule)' } else { 'A (sans risque)' })) -ForegroundColor Green
Start-Sleep -Seconds 3

# un mouvement : point de depart, puis 15 pas de 20 px (la vue doit tourner), pause, puis retour
function Mouvement([int]$sens) {   # [int] : sinon "-1" arrive en texte ("-1" x 20 = "-1-1-1...")
  [SourisFond]::Bouger($h, $cx, $cy); Start-Sleep -Milliseconds 40
  for ($k = 1; $k -le 15; $k++) { [SourisFond]::Bouger($h, $cx + $sens * 20 * $k, $cy); Start-Sleep -Milliseconds 30 }
}
try {
  if ($AvecFocus) { [SourisFond]::Focus($h, $true); Start-Sleep -Milliseconds 150 }
  Write-Host "  -> vers la droite (la vue doit tourner a droite)" -ForegroundColor Yellow
  Mouvement 1
  Start-Sleep -Seconds 2
  Write-Host "  -> retour vers la gauche" -ForegroundColor Yellow
  Mouvement -1
  Start-Sleep -Milliseconds 300
} finally {
  if ($AvecFocus) { [SourisFond]::Focus($h, $false); Start-Sleep -Milliseconds 150 }
  [void][SourisFond]::ClipCursor([IntPtr]::Zero)                            # souris liberee quoi qu'il arrive
  [void][SourisFond]::SetCursorPos($p.X, $p.Y)                              # et remise ou elle etait
}
Write-Host "`nTermine. Dis-moi si la vue a tourne (a droite puis retour), et si ta souris a saute." -ForegroundColor Green
